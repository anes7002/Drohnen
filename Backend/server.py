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

# Video stream state
video_streaming = False
video_cap = None


@app.post("/connect")
async def connect(data: dict):
    global control, telemetry
    
    ip = data.get("ip", "192.168.0.104")
    print(f"[DEBUG] Connect request for IP: {ip}")

    success = drone_connection.connect(ip)
    print(f"[DEBUG] Connect success: {success}")

    if success:
        drone_connection.send_command("command")   # WICHTIG
        drone_connection.send_command("streamon")
        # Set speed to maximum (100) on connection
        drone_connection.send_command("speed 100")

        control = Control(drone_connection)
        telemetry = Telemetry(drone_connection)
        print("[DEBUG] Control and Telemetry initialized")

    return {"success": success}


@app.post("/disconnect")
async def disconnect():
    global control, telemetry, video_streaming
    video_streaming = False
    if drone_connection.connected:
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
        return {"success": False, "error": str(e)}


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
        return {"success": False, "error": str(e)}


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
        return {"success": False, "error": str(e)}


@app.post("/flugkurs/{course_id}/execute")
async def execute_flugkurs(course_id: int):
    """Execute a saved timed flight course via RC control."""
    if not drone_connection.connected or control is None:
        return {"success": False, "error": "Not connected"}
    if not DB_AVAILABLE:
        return {"success": False, "error": "Datenbank nicht verfügbar (psycopg2 fehlt)"}
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT commands FROM flugkurs WHERE id = %s", (course_id,))
        row = cur.fetchone()
        cur.close()
        conn.close()
    except Exception as e:
        return {"success": False, "error": str(e)}

    if not row:
        return {"success": False, "error": "Flugkurs nicht gefunden"}

    commands = row[0]
    speed = 50  # RC speed value (0–100)

    # Direction → (left_right, fwd_back, up_down, yaw) mapping
    _direction_rc = {
        "forward":      (0,      speed,  0,     0),
        "backward":     (0,     -speed,  0,     0),
        "left":         (-speed, 0,      0,     0),
        "right":        (speed,  0,      0,     0),
        "up":           (0,      0,      speed, 0),
        "down":         (0,      0,     -speed, 0),
        "rotate_left":  (0,      0,      0,    -speed),
        "rotate_right": (0,      0,      0,     speed),
    }

    def run_course():
        for cmd in commands:
            direction = cmd.get("direction", "")
            seconds = float(cmd.get("seconds", 1))
            rc_values = _direction_rc.get(direction)
            if rc_values:
                control.send_rc(*rc_values)
                time.sleep(seconds)
                control.send_rc(0, 0, 0, 0)
                time.sleep(0.2)  # Brief pause between steps

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
        while True:
            ret, frame = cap.read()
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

    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)
            
            # Check for high-level commands first
            cmd = msg.get("command")
            if cmd:
                if cmd == "takeoff":
                    control.takeoff()
                elif cmd == "land":
                    control.land()
                elif cmd == "emergency":
                    control.emergency_stop()
                continue  # Skip RC values if it's a discrete command

            # Normal RC control
            a = int(msg.get("a", 0))
            b = int(msg.get("b", 0))
            c = int(msg.get("c", 0))
            d = int(msg.get("d", 0))
            control.send_rc(a, b, c, d)
    except WebSocketDisconnect:
        print("[DEBUG] WebSocket /rc disconnected")
        control.send_rc(0, 0, 0, 0)
    finally:
        tele_task.cancel()



if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
