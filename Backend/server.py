from __future__ import annotations

import asyncio
import base64
import json
import os
import threading
import time
from contextlib import contextmanager
from datetime import datetime

os.environ.setdefault("OPENCV_LOG_LEVEL", "ERROR")  # suppress FFmpeg H.264 decode noise

import cv2
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse

try:
    import psycopg2
    DB_AVAILABLE = True
except ImportError:
    DB_AVAILABLE = False

import detection
import ring_detection
from ring_navigator import RingNavigator
from drone import DroneConnection, Control, Telemetry, StatusLED


# ---------------------------------------------------------------------------
# App-Setup
# ---------------------------------------------------------------------------

app = FastAPI(title="Drohnen-Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Datenbank-Hilfsfunktion
# ---------------------------------------------------------------------------

@contextmanager
def db_cursor():
    """Öffnet eine DB-Verbindung, liefert einen Cursor und schließt danach alles."""
    if not DB_AVAILABLE:
        raise RuntimeError("psycopg2 nicht installiert")
    conn = psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        database=os.getenv("DB_NAME", "user"),
        user=os.getenv("DB_USER", "user"),
        password=os.getenv("DB_PASSWORD", "password"),
        port=int(os.getenv("DB_PORT", "5432")),
    )
    try:
        cur = conn.cursor()
        yield cur
        conn.commit()
    finally:
        cur.close()
        conn.close()


# ---------------------------------------------------------------------------
# Drohnen-Zustand (globale Objekte)
# ---------------------------------------------------------------------------

drone_connection = DroneConnection()
control: Control | None = None
telemetry: Telemetry | None = None
status_led: StatusLED | None = None

# Wird auf True gesetzt, während ein gespeicherter Flugkurs abläuft.
# Während dieser Zeit werden manuelle RC-Eingaben ignoriert.
auto_flight_active = False

# Ring-Modus: autonomes Durchfliegen von Ringen
ring_mode_active = False
ring_navigator: RingNavigator | None = None

# Tello EDU matrix: 64 chars, each '0'=off, 'r'=red, 'b'=blue, 'p'=purple
_TT_PATTERN = "00rrrr000r0000r0r0r00r0rr000000rr0r00r0rr00rr00r0r0000r000rrrr00"
_current_mled_pattern: str = _TT_PATTERN
_mled_on: bool = True
_mled_blink_task: asyncio.Task | None = None


# ---------------------------------------------------------------------------
# Video-Aufnahme-Zustand
# ---------------------------------------------------------------------------

RECORDINGS_DIR = "recordings"
os.makedirs(RECORDINGS_DIR, exist_ok=True)

is_recording = False
video_writer: cv2.VideoWriter | None = None
current_recording_filename: str | None = None


# ---------------------------------------------------------------------------
# Flugkurs-Konstanten
# ---------------------------------------------------------------------------

# Ordnet Richtungsbezeichnungen den RC-Werten zu: (left_right, fwd_back, up_down, yaw)
RC_DIRECTION_MAP = {
    "forward":      (0,    50,  0,    0),
    "backward":     (0,   -50,  0,    0),
    "left":         (-50,   0,  0,    0),
    "right":        (50,    0,  0,    0),
    "up":           (0,     0,  50,   0),
    "down":         (0,     0, -50,   0),
    "rotate_left":  (0,     0,  0, -100),
    "rotate_right": (0,     0,  0,  100),
}


# ---------------------------------------------------------------------------
# Verbindungs-Endpoints
# ---------------------------------------------------------------------------

@app.post("/connect")
async def connect(data: dict):
    global control, telemetry, status_led

    ip = data.get("ip", "192.168.0.104")
    print(f"[INFO] Verbindungsanfrage für IP: {ip}")

    status_led = StatusLED(drone_connection, ip)
    status_led.connecting()

    success = drone_connection.connect(ip)

    if success:
        drone_connection.send_command("command")
        drone_connection.send_command("streamon")
        drone_connection.send_command("speed 50")
        status_led.connected()
        control = Control(drone_connection)
        telemetry = Telemetry(drone_connection)
        print("[INFO] Steuerung und Telemetrie initialisiert")
    else:
        status_led.error()

    return {"success": success}


@app.post("/disconnect")
async def disconnect():
    global control, telemetry, status_led, ring_mode_active, ring_navigator

    if ring_mode_active and ring_navigator is not None:
        ring_navigator.stop()
        ring_mode_active = False
        ring_detection.enabled = False
        ring_navigator = None

    if drone_connection.connected:
        if status_led:
            status_led.off()
        drone_connection.send_command("streamoff")

    drone_connection.disconnect()
    control = None
    telemetry = None
    return {"success": True}


# ---------------------------------------------------------------------------
# LED-Steuerung
# ---------------------------------------------------------------------------

@app.post("/led")
async def set_led(data: dict):
    if not drone_connection.connected:
        return {"success": False, "error": "Nicht verbunden"}
    r = max(0, min(255, int(data.get("r", 0))))
    g = max(0, min(255, int(data.get("g", 0))))
    b = max(0, min(255, int(data.get("b", 0))))
    blink = data.get("blink", False)
    freq = float(data.get("freq", 1.0))

    if blink:
        # Tello EDU SDK: ext led bl <freq> <r1> <g1> <b1> <r2> <g2> <b2>
        drone_connection.send_command(f"ext led bl {freq} {r} {g} {b} 0 0 0")
    else:
        drone_connection.send_command(f"ext led {r} {g} {b}")

    return {"success": True}


# ---------------------------------------------------------------------------
# Matrix-LED-Steuerung (8x8)
# ---------------------------------------------------------------------------

@app.get("/mled/pattern")
async def get_mled_pattern():
    """Gibt das zuletzt gesendete (oder Standard-TT) Muster und Effekt-Status zurück."""
    return {
        "success": True,
        "pattern": _current_mled_pattern,
        "on": _mled_on,
        "blinking": _mled_blink_task is not None and not _mled_blink_task.done(),
    }


async def _stop_blink():
    """Bricht eine laufende Blink-Schleife sauber ab."""
    global _mled_blink_task
    task = _mled_blink_task
    _mled_blink_task = None
    if task is not None and not task.done():
        task.cancel()
        try:
            await task
        except (asyncio.CancelledError, Exception):
            pass


async def _blink_loop(freq: float):
    """Schaltet die Matrix abwechselnd ein und aus (Pattern ↔ Clear)."""
    interval = 1.0 / max(freq, 0.1)
    visible = True
    try:
        while True:
            if visible:
                drone_connection.send_command(f"ext mled g {_current_mled_pattern}")
            else:
                drone_connection.send_command("ext mled sc")
            visible = not visible
            await asyncio.sleep(interval)
    except asyncio.CancelledError:
        # Beim Stoppen den finalen Sichtbarkeitszustand wiederherstellen
        if _mled_on:
            drone_connection.send_command(f"ext mled g {_current_mled_pattern}")
        else:
            drone_connection.send_command("ext mled sc")
        raise


@app.post("/mled")
async def set_mled(data: dict):
    global _current_mled_pattern
    if not drone_connection.connected:
        return {"success": False, "error": "Nicht verbunden"}

    pattern = data.get("pattern", "")
    if len(pattern) != 64 or not all(c in "0rbp" for c in pattern):
        return {"success": False, "error": "Muster muss 64 Zeichen aus '0','r','b','p' sein"}

    _current_mled_pattern = pattern
    # Wenn aktuell geblinkt wird, nutzt die Schleife das neue Muster beim nächsten Tick.
    # Wenn die Matrix aus ist, das Muster nur speichern und nicht anzeigen.
    blinking = _mled_blink_task is not None and not _mled_blink_task.done()
    if _mled_on and not blinking:
        loop = asyncio.get_running_loop()
        resp = await loop.run_in_executor(
            None, drone_connection.send_command_with_response, f"ext mled g {pattern}"
        )
        print(f"[MLED] Drohnen-Antwort (grid): {resp!r}")
        if resp not in ("ok", "OK"):
            return {"success": False, "error": f"Drohne: {resp}"}
    return {"success": True}


@app.post("/mled/visibility")
async def set_mled_visibility(data: dict):
    """Schaltet die Matrix komplett an/aus, ohne das Muster zu verlieren."""
    global _mled_on
    if not drone_connection.connected:
        return {"success": False, "error": "Nicht verbunden"}

    _mled_on = bool(data.get("on", True))
    await _stop_blink()
    if _mled_on:
        drone_connection.send_command(f"ext mled g {_current_mled_pattern}")
    else:
        drone_connection.send_command("ext mled sc")
    return {"success": True, "on": _mled_on}


@app.post("/mled/blink")
async def mled_blink(data: dict):
    """Startet oder stoppt das Blinken des aktuellen Musters."""
    global _mled_blink_task
    if not drone_connection.connected:
        return {"success": False, "error": "Nicht verbunden"}

    enabled = bool(data.get("enabled", False))
    freq = float(data.get("freq", 1.0))

    await _stop_blink()

    if enabled and _mled_on:
        _mled_blink_task = asyncio.create_task(_blink_loop(freq))
    elif _mled_on:
        drone_connection.send_command(f"ext mled g {_current_mled_pattern}")

    return {"success": True, "blinking": enabled and _mled_on}


@app.post("/mled/scroll")
async def mled_scroll(data: dict):
    """Lässt Text als Laufschrift über die Matrix scrollen.

    Tello SDK: ext mled <l|r|u|d> <r|b|p> <freq 0.1-2.5> <string max 70 Zeichen>
    """
    if not drone_connection.connected:
        return {"success": False, "error": "Nicht verbunden"}

    text = str(data.get("text", "")).strip()[:70]
    direction = str(data.get("direction", "l"))
    color = str(data.get("color", "b"))
    freq = max(0.1, min(2.5, float(data.get("freq", 1.5))))

    if not text:
        return {"success": False, "error": "Text darf nicht leer sein"}
    if direction not in ("l", "r", "u", "d"):
        return {"success": False, "error": "Richtung muss l/r/u/d sein"}
    if color not in ("r", "b", "p"):
        return {"success": False, "error": "Farbe muss r/b/p sein"}

    await _stop_blink()
    loop = asyncio.get_running_loop()
    resp = await loop.run_in_executor(
        None, drone_connection.send_command_with_response,
        f"ext mled {direction} {color} {freq} {text}"
    )
    print(f"[MLED] Drohnen-Antwort (scroll): {resp!r}")
    if resp not in ("ok", "OK"):
        return {"success": False, "error": f"Drohne: {resp}"}
    return {"success": True}


# ---------------------------------------------------------------------------
# Erkennung-Endpoints
# ---------------------------------------------------------------------------

@app.post("/detection/toggle")
async def toggle_detection():
    detection.enabled = not detection.enabled
    return {"success": True, "enabled": detection.enabled}


@app.get("/detection/status")
async def detection_status():
    return {"enabled": detection.enabled}


# ---------------------------------------------------------------------------
# Ring-Modus-Endpoints
# ---------------------------------------------------------------------------

@app.post("/ring/toggle")
async def toggle_ring_mode():
    global ring_mode_active, ring_navigator

    if not drone_connection.connected or control is None:
        return {"success": False, "error": "Nicht verbunden"}

    ring_mode_active = not ring_mode_active
    ring_detection.enabled = ring_mode_active

    if ring_mode_active:
        ring_navigator = RingNavigator(control, frame_width=960, frame_height=720)
        ring_navigator.start()
        print("[RING] Ring-Modus aktiviert")
    else:
        if ring_navigator is not None:
            ring_navigator.stop()
        ring_detection.ring = None
        print("[RING] Ring-Modus deaktiviert")

    return {"success": True, "enabled": ring_mode_active}


@app.get("/ring/status")
async def ring_status():
    status = ring_navigator.get_status() if ring_navigator is not None else {}
    return {
        "enabled": ring_mode_active,
        "state": status.get("state", "idle"),
        "ring_detected": status.get("ring_detected", False),
        "cx": status.get("cx", 0),
        "cy": status.get("cy", 0),
        "radius": status.get("radius", 0),
    }


@app.post("/ring/config")
async def ring_config(data: dict):
    """Konfiguriert Ringerkennung (HSV-Farbe) und Navigationsparameter."""
    if data.get("color") == "red":
        ring_detection.set_color_red(
            s_low=int(data.get("s_low", 80)),
            v_low=int(data.get("v_low", 80)),
        )
    elif any(k in data for k in ("h_low", "h_high")):
        ring_detection.set_color(
            int(data.get("h_low", 5)),
            int(data.get("h_high", 25)),
            int(data.get("s_low", 80)),
            int(data.get("s_high", 255)),
            int(data.get("v_low", 80)),
            int(data.get("v_high", 255)),
        )
    if ring_navigator is not None:
        if "approach_radius" in data:
            ring_navigator.APPROACH_RADIUS = int(data["approach_radius"])
        if "pass_duration" in data:
            ring_navigator.PASS_DURATION = float(data["pass_duration"])
        if "forward_max" in data:
            ring_navigator.FORWARD_MAX = int(data["forward_max"])
        if "pass_speed" in data:
            ring_navigator.PASS_SPEED = int(data["pass_speed"])
    return {"success": True}


# ---------------------------------------------------------------------------
# Steuerungs-Endpoint
# ---------------------------------------------------------------------------

@app.post("/command")
async def send_command(data: dict):
    if not drone_connection.connected or control is None:
        return {"success": False, "error": "Nicht verbunden"}

    cmd = data.get("command", "")
    args = data.get("args", {})

    command_map = {
        "takeoff":      lambda: control.takeoff(),
        "land":         lambda: control.land(),
        "emergency":    lambda: control.emergency_stop(),
        "forward":      lambda: control.forward(args.get("distance", 50)),
        "backward":     lambda: control.backward(args.get("distance", 50)),
        "left":         lambda: control.left(args.get("distance", 50)),
        "right":        lambda: control.right(args.get("distance", 50)),
        "up":           lambda: control.up(args.get("distance", 30)),
        "down":         lambda: control.down(args.get("distance", 30)),
        "rotate_left":  lambda: control.rotate_left(args.get("angle", 45)),
        "rotate_right": lambda: control.rotate_right(args.get("angle", 45)),
        "rc": lambda: control.send_rc(
            args.get("a", 0), args.get("b", 0),
            args.get("c", 0), args.get("d", 0),
        ),
    }

    action = command_map.get(cmd)
    if action is None:
        return {"success": False, "error": f"Unbekannter Befehl: {cmd}"}

    try:
        action()
        return {"success": True}
    except Exception as e:
        return {"success": False, "error": str(e)}


# ---------------------------------------------------------------------------
# Telemetrie-Endpoint
# ---------------------------------------------------------------------------

@app.get("/telemetry")
async def get_telemetry():
    if not drone_connection.connected or telemetry is None:
        return {"success": False, "error": "Nicht verbunden"}
    try:
        return {"success": True, "data": telemetry.get_all_telemetry()}
    except Exception as e:
        return {"success": False, "error": str(e)}


# ---------------------------------------------------------------------------
# Drohnen-Verwaltung (CRUD)
# ---------------------------------------------------------------------------

@app.get("/drohnen")
def get_drohnen():
    if not DB_AVAILABLE:
        return {"success": False, "error": "Datenbank nicht verfügbar"}
    try:
        with db_cursor() as cur:
            cur.execute(
                "SELECT id, name, ip_adresse, mac_adresse, erstellt_am "
                "FROM drohne ORDER BY erstellt_am DESC"
            )
            rows = cur.fetchall()
        drohnen = [
            {
                "id": r[0], "name": r[1], "ip_adresse": r[2],
                "mac_adresse": r[3],
                "erstellt_am": r[4].isoformat() if r[4] else None,
            }
            for r in rows
        ]
        return {"success": True, "drohnen": drohnen}
    except Exception as e:
        print(f"[ERROR] get_drohnen: {e}")
        return {"success": False, "error": "Datenbankfehler"}

# d
@app.post("/drohnen")
def add_drohne(data: dict):
    if not DB_AVAILABLE:
        return {"success": False, "error": "Datenbank nicht verfügbar"}
    name = data.get("name")
    ip_adresse = data.get("ip_adresse")
    mac_adresse = data.get("mac_adresse")
    if not name or not ip_adresse:
        return {"success": False, "error": "Name und IP sind erforderlich"}
    try:
        with db_cursor() as cur:
            cur.execute(
                "INSERT INTO drohne (name, ip_adresse, mac_adresse) "
                "VALUES (%s, %s, %s) RETURNING id, erstellt_am",
                (name, ip_adresse, mac_adresse),
            )
            row = cur.fetchone()
        return {
            "success": True, "id": row[0],
            "erstellt_am": row[1].isoformat() if row[1] else None,
        }
    except Exception as e:
        print(f"[ERROR] add_drohne: {e}")
        return {"success": False, "error": "Datenbankfehler"}

@app.delete("/drohnen/{drohnen_id}")
def delete_drohne(drohnen_id: int):
    if not DB_AVAILABLE:
        return {"success": False, "error": "Datenbank nicht verfügbar"}
    try:
        with db_cursor() as cur:
            cur.execute("DELETE FROM drohne WHERE id = %s RETURNING id", (drohnen_id,))
            deleted = cur.fetchone()
        if deleted:
            return {"success": True}
        return {"success": False, "error": "Drohne nicht gefunden"}
    except Exception as e:
        print(f"[ERROR] delete_drohne: {e}")
        return {"success": False, "error": "Datenbankfehler"}


# ---------------------------------------------------------------------------
# Flugkurs-Verwaltung (CRUD + Ausführung)
# ---------------------------------------------------------------------------

@app.get("/flugkurs")
async def list_flugkurse():
    if not DB_AVAILABLE:
        return {"success": False, "error": "Datenbank nicht verfügbar"}
    try:
        with db_cursor() as cur:
            cur.execute(
                "SELECT id, name, commands, aufgezeichnet_am "
                "FROM flugkurs ORDER BY aufgezeichnet_am DESC"
            )
            rows = cur.fetchall()
        courses = [
            {
                "id": r[0], "name": r[1],
                "commands": r[2], "aufgezeichnet_am": str(r[3]),
            }
            for r in rows
        ]
        return {"success": True, "data": courses}
    except Exception as e:
        print(f"[ERROR] list_flugkurse: {e}")
        return {"success": False, "error": "Datenbankfehler"}


@app.post("/flugkurs")
async def create_flugkurs(data: dict):
    if not DB_AVAILABLE:
        return {"success": False, "error": "Datenbank nicht verfügbar"}
    name = data.get("name", "").strip()
    commands = data.get("commands", [])
    if not name:
        return {"success": False, "error": "Name darf nicht leer sein"}
    if not commands:
        return {"success": False, "error": "Mindestens ein Schritt erforderlich"}
    try:
        with db_cursor() as cur:
            cur.execute(
                "INSERT INTO flugkurs (name, commands) VALUES (%s, %s) RETURNING id",
                (name, json.dumps(commands)),
            )
            new_id = cur.fetchone()[0]
        return {"success": True, "id": new_id}
    except Exception as e:
        print(f"[ERROR] create_flugkurs: {e}")
        return {"success": False, "error": "Datenbankfehler"}


@app.delete("/flugkurs/{course_id}")
async def delete_flugkurs(course_id: int):
    if not DB_AVAILABLE:
        return {"success": False, "error": "Datenbank nicht verfügbar"}
    try:
        with db_cursor() as cur:
            cur.execute("DELETE FROM flugkurs WHERE id = %s", (course_id,))
        return {"success": True}
    except Exception as e:
        print(f"[ERROR] delete_flugkurs: {e}")
        return {"success": False, "error": "Datenbankfehler"}


@app.post("/flugkurs/{course_id}/execute")
async def execute_flugkurs(course_id: int):
    if not drone_connection.connected or control is None:
        return {"success": False, "error": "Nicht verbunden"}

    try:
        with db_cursor() as cur:
            cur.execute("SELECT commands FROM flugkurs WHERE id = %s", (course_id,))
            row = cur.fetchone()
    except Exception as e:
        print(f"[ERROR] execute_flugkurs (DB): {e}")
        return {"success": False, "error": "Datenbankfehler"}

    if not row:
        return {"success": False, "error": "Flugkurs nicht gefunden"}

    commands = row[0]

    def run_course():
        global auto_flight_active
        auto_flight_active = True
        try:
            for cmd in commands:
                direction = cmd.get("direction", "")
                seconds = float(cmd.get("seconds", 1))

                if direction == "takeoff":
                    control.takeoff()
                    time.sleep(5)
                elif direction == "land":
                    control.land()
                    time.sleep(5)
                else:
                    rc_values = RC_DIRECTION_MAP.get(direction)
                    if rc_values:
                        # Tello braucht kontinuierliche RC-Pakete (10 Hz),
                        # kein einmaliger Befehl reicht für eine Bewegung.
                        end_time = time.time() + seconds
                        while time.time() < end_time:
                            control.send_rc(*rc_values)
                            time.sleep(0.1)
                        control.send_rc(0, 0, 0, 0)
                        time.sleep(0.2)  # kurze Pause zwischen den Schritten
        except Exception as exc:
            print(f"[ERROR] run_course: {exc}")
        finally:
            auto_flight_active = False
            control.send_rc(0, 0, 0, 0)

    threading.Thread(target=run_course, daemon=True).start()
    return {"success": True}


# ---------------------------------------------------------------------------
# Video-Aufnahme-Endpoints
# ---------------------------------------------------------------------------

@app.post("/recordings/start")
async def start_recording():
    global is_recording
    if not drone_connection.connected:
        return {"success": False, "error": "Drohne nicht verbunden"}
    is_recording = True
    return {"success": True, "message": "Aufnahme gestartet"}


@app.post("/recordings/stop")
async def stop_recording():
    global is_recording, video_writer, current_recording_filename
    is_recording = False

    # Kurz warten, damit der Video-Loop den Writer sauber schließen kann
    await asyncio.sleep(0.5)

    if DB_AVAILABLE and current_recording_filename:
        try:
            with db_cursor() as cur:
                cur.execute(
                    "INSERT INTO recordings (filename, created_at) VALUES (%s, %s)",
                    (current_recording_filename, datetime.now()),
                )
        except Exception as e:
            print(f"[ERROR] Aufnahme in DB speichern fehlgeschlagen: {e}")

    current_recording_filename = None
    return {"success": True, "message": "Aufnahme gestoppt"}

@app.get("/recordings/status")
async def get_recording_status():
    global is_recording
    return {
        "success": True, 
        "isRecording": is_recording
    }


@app.get("/recordings")
async def get_recordings():
    if not DB_AVAILABLE:
        files = [f for f in os.listdir(RECORDINGS_DIR) if f.endswith(".mp4")]
        data = [{"id": i, "filename": f, "created_at": None} for i, f in enumerate(files)]
        return {"success": True, "data": data}
    try:
        with db_cursor() as cur:
            cur.execute(
                "SELECT id, filename, created_at FROM recordings ORDER BY created_at DESC"
            )
            rows = cur.fetchall()
        data = [{"id": r[0], "filename": r[1], "created_at": str(r[2])} for r in rows]
        return {"success": True, "data": data}
    except Exception as e:
        return {"success": False, "error": str(e)}
    
@app.post("/recordings/save")
async def save_recording(data:dict):
    filename = data.get("filename")
    if not filename:
        return {"success": False, "error": "Dateiname erforderlich"}
    filepath = os.path.join(RECORDINGS_DIR, filename)
    if not os.path.exists(filepath):
        return {"success": False, "error": "Datei nicht gefunden"}
    db_cursor().execute(
        "INSERT INTO recordings (filename, created_at) VALUES (%s, %s)",
        (filename, datetime.now())
    )
    return {"success": True, "message": "Aufnahme gespeichert"}
    


@app.get("/recordings/{rec_id}/video")
async def serve_recording_video(rec_id: int):
    if DB_AVAILABLE:
        try:
            with db_cursor() as cur:
                cur.execute("SELECT filename FROM recordings WHERE id = %s", (rec_id,))
                row = cur.fetchone()
                if row:
                    filepath = os.path.join(RECORDINGS_DIR, row[0])
                    if os.path.exists(filepath):
                        return FileResponse(filepath, media_type="video/mp4")
        except Exception:
            pass
    # Fallback: search by index in filesystem
    files = sorted([f for f in os.listdir(RECORDINGS_DIR) if f.endswith(".mp4")])
    if 0 <= rec_id < len(files):
        filepath = os.path.join(RECORDINGS_DIR, files[rec_id])
        return FileResponse(filepath, media_type="video/mp4")
    return {"success": False, "error": "Nicht gefunden"}


@app.delete("/recordings/{rec_id}")
async def delete_recording(rec_id: int):
    try:
        with db_cursor() as cur:
            cur.execute("SELECT filename FROM recordings WHERE id = %s", (rec_id,))
            row = cur.fetchone()
            if row:
                filepath = os.path.join(RECORDINGS_DIR, row[0])
                if os.path.exists(filepath):
                    os.remove(filepath)
                cur.execute("DELETE FROM recordings WHERE id = %s", (rec_id,))
        return {"success": True}
    except Exception as e:
        return {"success": False, "error": str(e)}


# ---------------------------------------------------------------------------
# WebSocket: Video-Stream (mit Aufnahme & AI-Erkennung)
# ---------------------------------------------------------------------------

@app.websocket("/video")
async def video_stream(websocket: WebSocket):
    """
    Streamt Drohnen-Videoframes als binäre JPEG-Bytes über WebSocket.
    Unterstützt gleichzeitig:
      - Video-Aufnahme als MP4 (gesteuert via /recordings/start + /stop)
      - AI-Erkennung (gesteuert via /detection/toggle)

    Latenz-Optimierungen:
      - Dedizierter Grabber-Thread leert OpenCVs internen Puffer kontinuierlich
        und hält immer nur den neuesten Frame → kein Frame-Stau.
      - Binäre WebSocket-Übertragung statt Base64 (~33 % weniger Daten).
      - Kein künstlicher asyncio.sleep am Ende der Sende-Schleife.
    """
    global video_writer, current_recording_filename, is_recording

    await websocket.accept()

    if not drone_connection.connected:
        await websocket.send_json({"error": "Nicht verbunden"})
        await websocket.close()
        return

    # Tello streamt auf UDP-Port 11111
    # AV_LOG_QUIET (=-8) unterdrückt FFmpeg-H264-Warnungen im Terminal
    os.environ.setdefault("OPENCV_FFMPEG_LOGLEVEL", "-8")
    cap = cv2.VideoCapture("udp://@0.0.0.0:11111", cv2.CAP_FFMPEG)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    if not cap.isOpened():
        await websocket.send_json({"error": "Video-Stream konnte nicht geöffnet werden"})
        await websocket.close()
        return

    # ------------------------------------------------------------------
    # Grabber-Thread: liest Frames so schnell wie möglich und verwirft
    # alle außer dem neuesten → OpenCV-Puffer läuft nie voll.
    # ------------------------------------------------------------------
    _latest_frame: list = [None]          # [0] = aktuellster Frame (numpy array)
    _new_frame = threading.Event()        # wird gesetzt, sobald ein neuer Frame da ist
    _grabber_running = [True]

    def _grab_frames():
        """Leert OpenCV-Puffer kontinuierlich, hält nur neuesten Frame."""
        while _grabber_running[0]:
            try:
                ret, frame = cap.read()
                if ret:
                    _latest_frame[0] = frame
                else:
                    print("[VIDEO] cap.read() → ret=False")
            except Exception as e:
                print(f"[VIDEO] Grabber-Fehler: {e}")
                break

    grabber = threading.Thread(target=_grab_frames, daemon=True)
    grabber.start()

    loop = asyncio.get_running_loop()
    sent_count = 0

    try:
        while True:
            await asyncio.sleep(0.033)   # ~30 fps

            frame = _latest_frame[0]
            if frame is None:
                continue

            # --- Aufnahme ---
            if is_recording:
                if video_writer is None:
                    h, w = frame.shape[:2]
                    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
                    current_recording_filename = f"drohne_{int(time.time())}.mp4"
                    filepath = os.path.join(RECORDINGS_DIR, current_recording_filename)
                    video_writer = cv2.VideoWriter(filepath, fourcc, 30.0, (w, h))
                video_writer.write(frame)
            elif video_writer is not None:
                video_writer.release()
                video_writer = None

            # --- AI-Erkennung ---
            if detection.enabled:
                detection.frame_count += 1
                if detection.frame_count % detection.DETECT_EVERY_N == 0:
                    detection.boxes = await loop.run_in_executor(
                        None, detection.detect, frame
                    )
                detection.draw(frame, detection.boxes)

            # --- Frame senden (base64 Text – kompatibel mit Flutter Web) ---
            _, buffer = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 60])
            await websocket.send_text(base64.b64encode(buffer).decode("utf-8"))

            sent_count += 1
            if sent_count % 30 == 0:
                print(f"[VIDEO] {sent_count} Frames gesendet")

    except WebSocketDisconnect:
        pass
    finally:
        _grabber_running[0] = False
        if video_writer is not None:
            video_writer.release()
            video_writer = None
            is_recording = False
        cap.release()


# ---------------------------------------------------------------------------
# WebSocket: RC-Steuerung & Telemetrie
# ---------------------------------------------------------------------------

@app.websocket("/rc")
async def rc_control(websocket: WebSocket):
    """
    Empfängt RC-Joystick-Eingaben und sendet Telemetrie zurück (10 Hz).
    Nachrichten vom Client:
      - RC:      {"a": int, "b": int, "c": int, "d": int}
      - Befehl:  {"command": "takeoff" | "land" | "emergency"}
    """
    await websocket.accept()

    if not drone_connection.connected or control is None:
        await websocket.send_json({"error": "Nicht verbunden"})
        await websocket.close()
        return

    last_rc = {"a": 0, "b": 0, "c": 0, "d": 0}

    async def send_telemetry():
        """Sendet alle 100 ms Telemetriedaten an den Client."""
        try:
            while websocket.client_state.value == 1:
                if telemetry:
                    await websocket.send_json({
                        "type": "telemetry",
                        "data": telemetry.get_all_telemetry(),
                    })
                await asyncio.sleep(0.1)
        except Exception:
            pass

    async def send_rc_continuous():
        """
        Sendet RC-Werte mit 10 Hz an die Drohne.
        Die Tello reagiert nur auf kontinuierliche Pakete, nicht auf einzelne Befehle.
        Bei aktivem Flugkurs werden manuelle Eingaben übersprungen.
        """
        try:
            while websocket.client_state.value == 1:
                if not auto_flight_active and not ring_mode_active:
                    control.send_rc(last_rc["a"], last_rc["b"], last_rc["c"], last_rc["d"])
                await asyncio.sleep(0.1)
        except Exception:
            pass

    tele_task = asyncio.create_task(send_telemetry())
    rc_task = asyncio.create_task(send_rc_continuous())

    try:
        while True:
            data = await websocket.receive_text()

            if auto_flight_active or ring_mode_active:
                continue  # Manuelle Eingaben während Flugkurs/Ring-Modus ignorieren

            msg = json.loads(data)
            cmd = msg.get("command")

            if cmd:
                if cmd == "takeoff":
                    threading.Thread(target=control.takeoff, daemon=True).start()
                elif cmd == "land":
                    threading.Thread(target=control.land, daemon=True).start()
                elif cmd == "emergency":
                    control.emergency_stop()
                continue

            last_rc["a"] = int(msg.get("a", 0))
            last_rc["b"] = int(msg.get("b", 0))
            last_rc["c"] = int(msg.get("c", 0))
            last_rc["d"] = int(msg.get("d", 0))

    except WebSocketDisconnect:
        if not auto_flight_active:
            control.send_rc(0, 0, 0, 0)
    finally:
        tele_task.cancel()
        rc_task.cancel()
