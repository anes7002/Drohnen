import asyncio
import json
import os
import threading
import cv2
import base64
import time
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

try:
    import psycopg2
    DB_AVAILABLE = True
except ImportError:
    DB_AVAILABLE = False

from connection import DroneConnection
from controls import Control
from telemetry import Telemetry
from status_led import StatusLED

app = FastAPI()


def get_db_connection():
    """Return a psycopg2 connection using environment variables or defaults."""
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        database=os.getenv("DB_NAME", "user"),
        user=os.getenv("DB_USER", "user"),
        password=os.getenv("DB_PASSWORD", "password"),
        port=int(os.getenv("DB_PORT", "5432")),
    )


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

drone_connection = DroneConnection()
control = None
telemetry = None
status_led = None

auto_flight_active = False

# Video stream state
video_streaming = False
video_cap = None


@app.post("/connect")
async def connect(data: dict):
    global control, telemetry, status_led
    
    ip = data.get("ip", "192.168.0.104")
    print(f"[DEBUG] Connect request for IP: {ip}")

    # Initialisieren des Status-LED Objekts mit der Connection
    status_led = StatusLED(drone_connection, ip)
    status_led.connecting()  # Blaues Blinken für "Verbinde..."

    success = drone_connection.connect(ip)
    print(f"[DEBUG] Connect success: {success}")

    if success:
        drone_connection.send_command("command")   # WICHTIG
        drone_connection.send_command("streamon")
        # Set speed to half (50) on connection
        drone_connection.send_command("speed 50")
        
        # LED Statusanzeige auf grün setzen, um erfolgreiche Verbindung zu signalisieren.
        status_led.connected() # Grün

        control = Control(drone_connection)
        telemetry = Telemetry(drone_connection)
        print("[DEBUG] Control and Telemetry initialized")
    else:
        status_led.error() # Rot bei Fehler

    return {"success": success}


@app.post("/disconnect")
async def disconnect():
    global control, telemetry, video_streaming, status_led
    video_streaming = False
    if drone_connection.connected:
        if status_led:
            status_led.off()
        drone_connection.send_command("streamoff")
    drone_connection.disconnect()
    control = None
    telemetry = None
    return {"success": True}


@app.post("/command")
async def send_command(data: dict):
    if not drone_connection.connected or control is None:
        return {"success": False, "error": "Not connected"}

    cmd = data.get("command", "")
    args = data.get("args", {})

    try:
        if cmd == "takeoff":
            control.takeoff()
        elif cmd == "land":
            control.land()
        elif cmd == "emergency":
            control.emergency_stop()
        elif cmd == "forward":
            control.forward(args.get("distance", 50))
        elif cmd == "backward":
            control.backward(args.get("distance", 50))
        elif cmd == "left":
            control.left(args.get("distance", 50))
        elif cmd == "right":
            control.right(args.get("distance", 50))
        elif cmd == "up":
            control.up(args.get("distance", 30))
        elif cmd == "down":
            control.down(args.get("distance", 30))
        elif cmd == "rotate_left":
            control.rotate_left(args.get("angle", 45))
        elif cmd == "rotate_right":
            control.rotate_right(args.get("angle", 45))
        elif cmd == "rc":
            control.send_rc(
                args.get("a", 0),
                args.get("b", 0),
                args.get("c", 0),
                args.get("d", 0),
            )
        else:
            return {"success": False, "error": f"Unknown command: {cmd}"}
        return {"success": True}
    except Exception as e:
        return {"success": False, "error": str(e)}


@app.get("/telemetry")
async def get_telemetry():
    if not drone_connection.connected or telemetry is None:
        return {"success": False, "error": "Not connected"}
    try:
        data = telemetry.get_all_telemetry()
        return {"success": True, "data": data}
    except Exception as e:
        return {"success": False, "error": str(e)}


# ==========================================
# Flugkurs CRUD Endpoints
# ==========================================

@app.get("/flugkurs")
async def list_flugkurse():
    """List all saved flight courses from the database."""
    if not DB_AVAILABLE:
        return {"success": False, "error": "Datenbank nicht verfügbar (psycopg2 fehlt)"}
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            "SELECT id, name, commands, aufgezeichnet_am FROM flugkurs ORDER BY aufgezeichnet_am DESC"
        )
        rows = cur.fetchall()
        cur.close()
        conn.close()
        courses = [
            {
                "id": r[0],
                "name": r[1],
                "commands": r[2],
                "aufgezeichnet_am": str(r[3]),
            }
            for r in rows
        ]
        return {"success": True, "data": courses}
    except Exception as e:
        print(f"[ERROR] list_flugkurse: {e}")
        return {"success": False, "error": "Datenbankfehler beim Laden der Flugkurse"}


@app.post("/flugkurs")
async def create_flugkurs(data: dict):
    """Save a new flight course (name + list of timed direction commands)."""
    if not DB_AVAILABLE:
        return {"success": False, "error": "Datenbank nicht verfügbar (psycopg2 fehlt)"}
    name = data.get("name", "").strip()
    commands = data.get("commands", [])
    if not name:
        return {"success": False, "error": "Name darf nicht leer sein"}
    if not commands:
        return {"success": False, "error": "Mindestens ein Schritt erforderlich"}
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO flugkurs (name, commands) VALUES (%s, %s) RETURNING id",
            (name, json.dumps(commands)),
        )
        new_id = cur.fetchone()[0]
        conn.commit()
        cur.close()
        conn.close()
        return {"success": True, "id": new_id}
    except Exception as e:
        print(f"[ERROR] create_flugkurs: {e}")
        return {"success": False, "error": "Datenbankfehler beim Speichern des Flugkurses"}


@app.delete("/flugkurs/{course_id}")
async def delete_flugkurs(course_id: int):
    """Delete a saved flight course by ID."""
    if not DB_AVAILABLE:
        return {"success": False, "error": "Datenbank nicht verfügbar (psycopg2 fehlt)"}
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("DELETE FROM flugkurs WHERE id = %s", (course_id,))
        conn.commit()
        cur.close()
        conn.close()
        return {"success": True}
    except Exception as e:
        print(f"[ERROR] delete_flugkurs: {e}")
        return {"success": False, "error": "Datenbankfehler beim Löschen des Flugkurses"}


@app.post("/flugkurs/{course_id}/execute")
async def execute_flugkurs(course_id: int):
    global auto_flight_active
    
    if not drone_connection.connected or control is None:
        return {"success": False, "error": "Not connected"}

    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT commands FROM flugkurs WHERE id = %s", (course_id,))
        row = cur.fetchone()
        cur.close()
        conn.close()
    except Exception as e:
        print(f"[ERROR] execute_flugkurs (db): {e}")
        return {"success": False, "error": "Datenbankfehler beim Laden des Flugkurses"}

    if not row:
        return {"success": False, "error": "Flugkurs nicht gefunden"}

    commands = row[0]
    speed = 50  # RC speed value (0–100) - Angepasst auf 50 (gleicher Wert wie bei manueller Steuerung)
    rotation_speed = 100  # Drehen so schnell wie möglich
    _STEP_PAUSE = 0.2  # Seconds pause between steps

    # Direction → (left_right, fwd_back, up_down, yaw) mapping
    _direction_rc = {
        "forward":      (0,      speed,  0,     0),
        "backward":     (0,     -speed,  0,     0),
        "left":         (-speed, 0,      0,     0),
        "right":        (speed,  0,      0,     0),
        "up":           (0,      0,      speed, 0),
        "down":         (0,      0,     -speed, 0),
        "rotate_left":  (0,      0,      0,    -rotation_speed),
        "rotate_right": (0,      0,      0,     rotation_speed),
    }

    def run_course():
        global auto_flight_active
        auto_flight_active = True  # Blockiert die manuelle Websocket-Eingabe
        
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
                    rc_values = _direction_rc.get(direction)
                    if rc_values:
                        # Tello benötigt kontinuierliche RC-Befehle, auch im Auto-Modus.
                        # Daher simulieren wir hier eine Schleife, die den Befehl wiederholt sendet.
                        end_time = time.time() + seconds
                        while time.time() < end_time:
                            control.send_rc(*rc_values)
                            time.sleep(0.1) # 10Hz RC Update-Rate
                        
                        control.send_rc(0, 0, 0, 0)
                        # WICHTIG: Minimale Verzögerung zwischen den Schritten
                        time.sleep(_STEP_PAUSE)
        except Exception as exc:
            print(f"[ERROR] execute_flugkurs run_course: {exc}")
        finally:
            # Nach dem Aufzeichnen Steuerung wieder freigeben!
            auto_flight_active = False
            control.send_rc(0, 0, 0, 0)

    thread = threading.Thread(target=run_course, daemon=True)
    thread.start()
    return {"success": True}


@app.websocket("/video")
async def video_stream(websocket: WebSocket):
    """Stream video frames from the Tello drone via WebSocket as base64 JPEG."""
    await websocket.accept()

    if not drone_connection.connected:
        await websocket.send_json({"error": "Not connected"})
        await websocket.close()
        return

    # Tello streams on UDP port 11111
    drone_ip = drone_connection.ip_address
    cap = cv2.VideoCapture(f"udp://@0.0.0.0:11111", cv2.CAP_FFMPEG)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    if not cap.isOpened():
        await websocket.send_json({"error": "Could not open video stream"})
        await websocket.close()
        return

    try:
        loop = asyncio.get_running_loop()
        while True:
            ret, frame = await loop.run_in_executor(None, cap.read)
            if not ret:
                await asyncio.sleep(0.03)
                continue

            # Encode frame as JPEG
            _, buffer = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 60])
            jpg_b64 = base64.b64encode(buffer).decode("utf-8")

            await websocket.send_text(jpg_b64)
            await asyncio.sleep(0.03)  # ~30 fps
    except WebSocketDisconnect:
        pass
    finally:
        cap.release()


@app.websocket("/rc")
async def rc_control(websocket: WebSocket):
    """WebSocket for real-time RC joystick control and telemetry updates."""
    await websocket.accept()

    # Log connection attempt
    print(f"[DEBUG] WebSocket /rc requested. drone_connection.connected={drone_connection.connected}")

    if not drone_connection.connected or control is None:
        print("[DEBUG] Closing WebSocket /rc: Drone not connected or control not initialized")
        await websocket.send_json({"error": "Not connected"})
        await websocket.close()
        return

    # Task to send telemetry every second
    async def send_telemetry():
        try:
            while True:
                if websocket.client_state.value == 1:
                    if telemetry:
                        data = telemetry.get_all_telemetry()
                        await websocket.send_json({"type": "telemetry", "data": data})
                else:
                    break
                await asyncio.sleep(1)
        except:
            pass

    # Start telemetry sender as background task
    tele_task = asyncio.create_task(send_telemetry())

    last_rc = {"a": 0, "b": 0, "c": 0, "d": 0}

    # Tello benötigt rc-Updates für Bewegungen. Zu schnelle Updates (z.B. 20Hz) führen oft zu Pufferlaufzeiten 
    # und Ruckeln/Lag (Drohne fliegt "hin und her" und hängt nach). 10Hz (0.1s) reicht völlig aus!
    async def continuous_rc_sender():
        try:
            while websocket.client_state.value == 1:
                if not auto_flight_active:
                    control.send_rc(last_rc["a"], last_rc["b"], last_rc["c"], last_rc["d"])
                await asyncio.sleep(0.1) # Auf 10 Hz limitiert für eine stabilere Verbindung
        except:
            pass

    rc_task = asyncio.create_task(continuous_rc_sender())

    try:
        while True:
            data = await websocket.receive_text()
            
            # --- NEU: Wenn Ein automatischer Kurs läuft, ignoriere Tastatur-Befehle! ---
            if auto_flight_active:
                continue 
            # --------------------------------------------------------------------------
            
            msg = json.loads(data)
            
            # Check for high-level commands first
            cmd = msg.get("command")
            if cmd:
                if cmd == "takeoff":
                    threading.Thread(target=control.takeoff, daemon=True).start()
                elif cmd == "land":
                    threading.Thread(target=control.land, daemon=True).start()
                elif cmd == "emergency":
                    control.emergency_stop()
                continue  # Skip RC values if it's a discrete command

            # Normal RC control
            last_rc["a"] = int(msg.get("a", 0))
            last_rc["b"] = int(msg.get("b", 0))
            last_rc["c"] = int(msg.get("c", 0))
            last_rc["d"] = int(msg.get("d", 0))
            
    except WebSocketDisconnect:
        print("[DEBUG] WebSocket /rc disconnected")
        # Nur anhalten, wenn kein Kurs fliegt
        if not auto_flight_active:
             control.send_rc(0, 0, 0, 0)
    finally:
        tele_task.cancel()
        rc_task.cancel()



if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)

@app.get("/drohnen")
def get_drohnen():
    if not DB_AVAILABLE:
        return {"success": False, "error": "Database not available"}
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT id, name, ip_adresse, mac_adresse, erstellt_am FROM drohne ORDER BY erstellt_am DESC")
        rows = cur.fetchall()
        cur.close()
        conn.close()
        
        result = []
        for r in rows:
            result.append({
                "id": r[0],
                "name": r[1],
                "ip_adresse": r[2],
                "mac_adresse": r[3],
                "erstellt_am": r[4].isoformat() if r[4] else None
            })
        return {"success": True, "drohnen": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/drohnen")
def add_drohne(data: dict):
    if not DB_AVAILABLE:
        return {"success": False, "error": "Database not available"}
    try:
        name = data.get("name")
        ip_adresse = data.get("ip_adresse")
        mac_adresse = data.get("mac_adresse")
        
        if not ip_adresse or not name:
            return {"success": False, "error": "Name and IP are required"}
            
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            """INSERT INTO drohne (name, ip_adresse, mac_adresse) 
               VALUES (%s, %s, %s) RETURNING id, erstellt_am""",
            (name, ip_adresse, mac_adresse)
        )
        row = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        return {"success": True, "id": row[0], "erstellt_am": row[1].isoformat() if row[1] else None}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.delete("/drohnen/{drohnen_id}")
def delete_drohne(drohnen_id: int):
    if not DB_AVAILABLE:
        return {"success": False, "error": "Database not available"}
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("DELETE FROM drohne WHERE id = %s RETURNING id", (drohnen_id,))
        deleted = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        if deleted:
            return {"success": True}
        return {"success": False, "error": "Drohne nicht gefunden"}
    except Exception as e:
        return {"success": False, "error": str(e)}
