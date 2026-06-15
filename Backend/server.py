from __future__ import annotations

import asyncio
import json
import os
import threading
import time
from contextlib import contextmanager
from datetime import datetime

os.environ.setdefault("OPENCV_LOG_LEVEL", "ERROR")  # OpenCV-Logger leiser stellen
# FFmpeg-AVLog auf "fatal" (8) → unterdrückt das harmlose H.264-Dekodier-Rauschen
# ("error while decoding MB ... bytestream -6"), das bei UDP-Streams normal ist.
os.environ.setdefault("OPENCV_FFMPEG_LOGLEVEL", "8")
# Low-Delay-Decoding: kein Demuxer-Puffer, kein Frame-Threading (jeder
# Decoder-Thread puffert sonst einen Frame → mehrere 100 ms Zusatz-Latenz).
os.environ.setdefault(
    "OPENCV_FFMPEG_CAPTURE_OPTIONS",
    "fflags;nobuffer|flags;low_delay|threads;1",
)

import cv2
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

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

# Globale VideoCapture — einmal geöffnet beim Drone-Connect, damit Port 11111 nicht
# bei jeder WebSocket-Verbindung neu gebunden wird (verhindert WSAEADDRINUSE -10048).
_video_cap: cv2.VideoCapture | None = None

# Ein dedizierter Hintergrund-Thread liest KONTINUIERLICH Frames und hält nur den
# neuesten. Das hält den UDP-/FFmpeg-Puffer ständig geleert → deutlich weniger
# H.264-Dekodierfehler und kein Lag. Der WebSocket greift nur den letzten Frame ab.
_latest_frame = None
_frame_seq = 0          # zählt hoch bei jedem neuen Frame → Clients senden nur frische Bilder
_frame_lock = threading.Lock()
# Stop-Event PRO Grabber-Generation: Ein globales Bool würde ein altes, noch
# laufendes Grabber-Exemplar "wiederbeleben", sobald ein neues gestartet wird.
_grabber_stop: threading.Event | None = None
_grabber_thread: threading.Thread | None = None


def _open_stream(stop_event: threading.Event):
    """Öffnet den UDP-Videostream mit Bind-Retry. Gibt VideoCapture oder None zurück."""
    # fifo_size vergrößert den UDP-Empfangspuffer → weniger verworfene Pakete.
    url = "udp://@0.0.0.0:11111?overrun_nonfatal=1&fifo_size=5000000"
    # OPEN/READ-Timeout: ohne diese bleibt cap.read() bei totem Stream EWIG
    # blockiert → der Grabber-Thread terminiert beim Disconnect nicht und hält
    # Port 11111 → neuer Grabber bekommt "bind failed -10048". Mit Timeout kehrt
    # read() spätestens nach READ_TIMEOUT zurück, die Schleife prüft stop_event.
    base_params = [
        cv2.CAP_PROP_OPEN_TIMEOUT_MSEC, 6000,
        cv2.CAP_PROP_READ_TIMEOUT_MSEC, 3000,
    ]
    for attempt in range(5):
        if stop_event.is_set():
            return None
        # Erst mit explizitem Single-Thread-Decoder (geringste Latenz),
        # bei Ablehnung durch das Backend ohne den Thread-Parameter.
        cap = None
        try:
            cap = cv2.VideoCapture(
                url, cv2.CAP_FFMPEG, [cv2.CAP_PROP_N_THREADS, 1] + base_params
            )
        except cv2.error:
            cap = None
        if cap is None or not cap.isOpened():
            if cap is not None:
                cap.release()
            cap = cv2.VideoCapture(url, cv2.CAP_FFMPEG, base_params)
        if cap.isOpened():
            cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
            return cap
        cap.release()
        if stop_event.wait(1.0):
            return None
    return None


def _frame_grabber(stop_event: threading.Event) -> None:
    """
    Öffnet den UDP-Stream im eigenen Thread (blockiert NICHT den Event-Loop),
    liest dann dauerhaft Frames (drainiert den Puffer) und übernimmt die Aufnahme.
    Bricht der Stream ab (mehrere Read-Timeouts in Folge), wird er automatisch
    neu geöffnet — so erholt sich das Video nach einem WLAN-Aussetzer von selbst.
    """
    global _latest_frame, _frame_seq, _video_cap, video_writer, current_recording_filename, is_recording

    try:
        while not stop_event.is_set():
            cap = _open_stream(stop_event)
            if cap is None:
                if stop_event.is_set():
                    return
                print("[WARN] Video-Stream konnte nicht geöffnet werden (Port 11111 belegt?)")
                return
            _video_cap = cap
            fail_count = 0
            try:
                while not stop_event.is_set():
                    ret, frame = cap.read()
                    if not ret:
                        # Read-Timeout/Streamfehler. Bei Stop sofort raus.
                        if stop_event.is_set():
                            break
                        fail_count += 1
                        # 2 Timeouts in Folge (~6 s totale Stille) → Stream tot,
                        # Capture neu öffnen statt einzufrieren.
                        if fail_count >= 2:
                            print("[INFO] Video-Stream unterbrochen — öffne neu...")
                            break
                        time.sleep(0.01)
                        continue
                    fail_count = 0

                    # --- Aufnahme (rohe Frames in voller Rate, ohne Overlays) ---
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

                    with _frame_lock:
                        _latest_frame = frame
                        _frame_seq += 1
            finally:
                cap.release()
                _video_cap = None
    finally:
        if video_writer is not None:
            video_writer.release()
            video_writer = None
        with _frame_lock:
            _latest_frame = None


def _open_video_cap() -> None:
    global _grabber_stop, _grabber_thread
    _close_video_cap()
    _grabber_stop = threading.Event()
    _grabber_thread = threading.Thread(
        target=_frame_grabber, args=(_grabber_stop,), daemon=True
    )
    _grabber_thread.start()


def _close_video_cap() -> None:
    global _grabber_stop, _grabber_thread, is_recording
    if _grabber_stop is not None:
        _grabber_stop.set()
    if _grabber_thread is not None:
        _grabber_thread.join(timeout=5.0)
        if _grabber_thread.is_alive():
            print("[WARN] Alter Video-Grabber beendet sich nicht rechtzeitig")
        _grabber_thread = None
    _grabber_stop = None
    is_recording = False


# ---------------------------------------------------------------------------
# Ring-Erkennungs-Worker: läuft im eigenen Thread parallel zum Video-Grabber.
# Vorteile gegenüber Erkennung in der WebSocket-Schleife:
#   - bremst die Video-Sendeschleife nicht aus (weniger Latenz)
#   - verarbeitet jeden frischen Frame (~30 Hz statt jeden 2.) → präziseres Tracking
#   - Navigation funktioniert auch ohne geöffnetes Video im Frontend
# ---------------------------------------------------------------------------
_ring_worker_stop: threading.Event | None = None
_ring_worker_thread: threading.Thread | None = None


def _ring_detection_worker(stop_event: threading.Event) -> None:
    last_seq = -1
    while not stop_event.is_set():
        with _frame_lock:
            fresh = _latest_frame is not None and _frame_seq != last_seq
            seq = _frame_seq
            frame = _latest_frame.copy() if fresh else None
        if frame is None:
            time.sleep(0.005)
            continue
        last_seq = seq
        try:
            ring_detection.ring = ring_detection.detect(frame)
        except Exception as e:
            print(f"[RING] Erkennungsfehler: {e}")
            continue
        nav = ring_navigator
        if nav is not None:
            h, w = frame.shape[:2]
            nav.set_frame_size(w, h)
            nav.update_ring(ring_detection.ring)


def _start_ring_worker() -> None:
    global _ring_worker_stop, _ring_worker_thread
    _stop_ring_worker()
    _ring_worker_stop = threading.Event()
    _ring_worker_thread = threading.Thread(
        target=_ring_detection_worker, args=(_ring_worker_stop,), daemon=True
    )
    _ring_worker_thread.start()


def _stop_ring_worker() -> None:
    global _ring_worker_stop, _ring_worker_thread
    if _ring_worker_stop is not None:
        _ring_worker_stop.set()
    if _ring_worker_thread is not None:
        _ring_worker_thread.join(timeout=1.0)
        _ring_worker_thread = None
    _ring_worker_stop = None

# Ring-Modus: autonomes Durchfliegen von Ringen
ring_mode_active = False
ring_navigator: RingNavigator | None = None


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

def _discover_tello(subnet_hint: str) -> str | None:
    """
    Sucht eine Tello im /24-Subnetz der übergebenen IP: schickt 'command' an
    alle Adressen und wartet auf ein 'ok'. Nötig, weil DHCP (z. B. iPhone-
    Hotspot) der Drohne nach jedem Einschalten eine andere IP geben kann.
    """
    import socket as sock_mod

    prefix = ".".join(subnet_hint.split(".")[:3])
    s = sock_mod.socket(sock_mod.AF_INET, sock_mod.SOCK_DGRAM)
    try:
        s.settimeout(0.02)
        for i in range(1, 255):
            try:
                s.sendto(b"command", (f"{prefix}.{i}", 8889))
            except OSError:
                pass
        s.settimeout(3.0)
        while True:
            try:
                resp, addr = s.recvfrom(1024)
                if resp.strip() == b"ok":
                    return addr[0]
            except sock_mod.timeout:
                return None
            except ConnectionResetError:
                # ICMP "Port unreachable" anderer Geräte — ignorieren
                continue
    finally:
        s.close()


@app.post("/connect")
async def connect(data: dict):
    global control, telemetry, status_led

    ip = data.get("ip", "192.168.0.104")
    print(f"[INFO] Verbindungsanfrage für IP: {ip}")

    status_led = StatusLED(drone_connection, ip)
    status_led.connecting()

    # Blockierende Netzwerk-Operationen im Threadpool, damit der Server
    # während des Verbindens erreichbar bleibt.
    loop = asyncio.get_running_loop()
    success = await loop.run_in_executor(None, drone_connection.connect, ip)

    if not success:
        print("[INFO] Keine Antwort — suche Tello im Subnetz...")
        found = await loop.run_in_executor(None, _discover_tello, ip)
        if found and found != ip:
            print(f"[INFO] Tello gefunden unter {found} — verbinde...")
            ip = found
            success = await loop.run_in_executor(None, drone_connection.connect, ip)

    if success:
        drone_connection.send_command("command")
        drone_connection.send_command("streamon")
        drone_connection.send_command("speed 50")
        status_led.connected()
        control = Control(drone_connection)
        telemetry = Telemetry(drone_connection)
        print("[INFO] Steuerung und Telemetrie initialisiert")
        # Im Executor: _open_video_cap kann auf einen alten Grabber warten (join)
        # und darf den Event-Loop nicht blockieren.
        await loop.run_in_executor(None, _open_video_cap)
    else:
        status_led.error()

    return {"success": success, "ip": ip}


@app.post("/disconnect")
async def disconnect():
    global control, telemetry, status_led, ring_mode_active, ring_navigator

    if ring_mode_active and ring_navigator is not None:
        _stop_ring_worker()
        ring_navigator.stop()
        ring_mode_active = False
        ring_detection.enabled = False
        ring_navigator = None

    if drone_connection.connected:
        if status_led:
            status_led.off()
        drone_connection.send_command("streamoff")

    # Im Executor: _close_video_cap wartet (join) auf den Grabber-Thread und
    # darf den Event-Loop nicht blockieren.
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(None, _close_video_cap)
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
        r2 = max(0, min(255, int(data.get("r2", 0))))
        g2 = max(0, min(255, int(data.get("g2", 0))))
        b2 = max(0, min(255, int(data.get("b2", 0))))
        drone_connection.send_command(f"EXT led bl {freq} {r} {g} {b} {r2} {g2} {b2}")
    else:
        drone_connection.send_command(f"EXT led {r} {g} {b}")

    return {"success": True}


# ---------------------------------------------------------------------------
# Matrix-LED-Steuerung (8x8)
# ---------------------------------------------------------------------------

@app.post("/mled")
async def set_mled(data: dict):
    """Zeigt ein Muster auf der 8x8-LED-Matrix (Tello Talent).

    "leds" (oder "pattern"): Pixel als String aus '0' (aus), 'r', 'b', 'p'.
    Ein voller 8x8-Frame hat 64 Zeichen; der String wird roh durchgereicht.
    """
    if not drone_connection.connected:
        return {"success": False, "error": "Nicht verbunden"}
    leds = str(data.get("leds", data.get("pattern", "")))
    drone_connection.set_ledm(leds)
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
        _start_ring_worker()
        print("[RING] Ring-Modus aktiviert")
    else:
        _stop_ring_worker()
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
        if "target_offset_y" in data:
            ring_navigator.TARGET_OFFSET_Y = int(data["target_offset_y"])
        if "pitch_comp" in data:
            ring_navigator.PITCH_COMP = float(data["pitch_comp"])
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
    """
    await websocket.accept()

    if not drone_connection.connected:
        await websocket.send_json({"error": "Nicht verbunden"})
        await websocket.close()
        return

    # Auf den ersten Frame warten — der Grabber-Thread öffnet den Stream asynchron.
    waited = 0.0
    while _latest_frame is None and waited < 10.0 and drone_connection.connected:
        await asyncio.sleep(0.1)
        waited += 0.1
    if _latest_frame is None:
        await websocket.send_json({"error": "Kein Videosignal"})
        await websocket.close()
        return

    loop = asyncio.get_running_loop()
    last_seq = -1

    STREAM_WIDTH = 640  # Sendegröße: kleiner = schnelleres Encoding + weniger Bandbreite

    def _encode(f) -> bytes:
        h, w = f.shape[:2]
        if w > STREAM_WIDTH:
            f = cv2.resize(
                f, (STREAM_WIDTH, int(h * STREAM_WIDTH / w)),
                interpolation=cv2.INTER_AREA,
            )
        ok, buf = cv2.imencode(".jpg", f, [cv2.IMWRITE_JPEG_QUALITY, 65])
        return buf.tobytes() if ok else b""

    try:
        while True:
            # Auf den nächsten FRISCHEN Frame warten statt festem 30-ms-Takt:
            # minimale Zusatz-Latenz, kein doppeltes Senden desselben Bildes.
            waited = 0.0
            while _frame_seq == last_seq and waited < 1.0:
                await asyncio.sleep(0.005)
                waited += 0.005
            # Nach 1 s ohne neuen Frame trotzdem weitermachen (letztes Bild erneut
            # senden), damit ein Verbindungsabbruch des Clients erkannt wird.
            last_seq = _frame_seq

            # Neuesten Frame vom Grabber-Thread abgreifen (Kopie, damit Overlays
            # das geteilte Bild nicht verändern).
            with _frame_lock:
                frame = None if _latest_frame is None else _latest_frame.copy()

            if frame is None:
                await asyncio.sleep(0.02)
                continue

            # --- AI-Erkennung ---
            if detection.enabled:
                detection.frame_count += 1
                if detection.frame_count % detection.DETECT_EVERY_N == 0:
                    detection.boxes = await loop.run_in_executor(
                        None, detection.detect, frame
                    )
                detection.draw(frame, detection.boxes)

            # --- Ring-Overlay (Erkennung läuft im eigenen Worker-Thread) ---
            if ring_detection.enabled:
                ring_detection.draw(frame, ring_detection.ring)

                # State-Label ins Bild einblenden
                state_label = ring_navigator.status.get("state", "") if ring_navigator else ""
                cv2.putText(
                    frame, f"Ring: {state_label}",
                    (10, 32), cv2.FONT_HERSHEY_SIMPLEX, 0.75, (200, 0, 255), 2, cv2.LINE_AA,
                )

            # --- Frame senden (Encoding im Executor, blockiert den Loop nicht) ---
            # Binär statt base64-Text: ~33 % weniger Daten, kein Decode-Overhead
            # im Frontend → spürbar weniger Latenz.
            jpg = await loop.run_in_executor(None, _encode, frame)
            if jpg:
                await websocket.send_bytes(jpg)

    except WebSocketDisconnect:
        pass


# ---------------------------------------------------------------------------
# WebSocket: RC-Steuerung & Telemetrie
# ---------------------------------------------------------------------------

# Verhindert, dass schnelles Mehrfach-Tippen auf Takeoff/Land Dutzende Threads
# stapelt. Läuft bereits ein blockierender Befehl, werden weitere ignoriert.
_blocking_cmd_lock = threading.Lock()


def _run_exclusive(fn) -> None:
    if not _blocking_cmd_lock.acquire(blocking=False):
        print("[INFO] Befehl ignoriert — vorheriger Start/Lande-Befehl läuft noch")
        return
    try:
        fn()
    finally:
        _blocking_cmd_lock.release()


def _force_stop_all() -> None:
    """Stoppt Ring-Modus und Flugkurs sofort (für Not-Aus / sicheres Trennen)."""
    global ring_mode_active, ring_navigator, auto_flight_active
    _stop_ring_worker()
    if ring_navigator is not None:
        ring_navigator.stop()
        ring_navigator = None
    ring_mode_active = False
    ring_detection.enabled = False
    auto_flight_active = False


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

            try:
                msg = json.loads(data)
            except (ValueError, TypeError):
                continue
            cmd = msg.get("command")

            # Not-Aus hat IMMER Vorrang — auch während Ring-Modus/Flugkurs.
            if cmd == "emergency":
                _force_stop_all()
                if control is not None:
                    control.emergency_stop()
                continue

            # Matrix-LED jederzeit erlaubt (nur ein LED-Befehl, auch im Auto-Flug).
            # Akzeptiert {"command":"mled","leds":...} und {"Command":"MLED","LEDS":...}.
            mled_cmd = msg.get("command") or msg.get("Command")
            if mled_cmd and str(mled_cmd).lower() == "mled":
                drone_connection.set_ledm(str(msg.get("leds", msg.get("LEDS", ""))))
                continue

            if auto_flight_active or ring_mode_active:
                continue  # Sonstige manuelle Eingaben während Auto-Flug ignorieren

            if cmd:
                if cmd == "takeoff":
                    threading.Thread(
                        target=_run_exclusive, args=(control.takeoff,), daemon=True
                    ).start()
                elif cmd == "land":
                    threading.Thread(
                        target=_run_exclusive, args=(control.land,), daemon=True
                    ).start()
                continue

            last_rc["a"] = int(msg.get("a", 0))
            last_rc["b"] = int(msg.get("b", 0))
            last_rc["c"] = int(msg.get("c", 0))
            last_rc["d"] = int(msg.get("d", 0))

    except WebSocketDisconnect:
        if control is not None and not auto_flight_active:
            control.send_rc(0, 0, 0, 0)
    finally:
        tele_task.cancel()
        rc_task.cancel()
