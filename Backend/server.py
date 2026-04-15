import asyncio
import json
import threading
import cv2
import base64
import time
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

# Eigene Module
from connection import DroneConnection
from controls import Control
from telemetry import Telemetry
from vision import VisionManager  # NEU: Vision Import

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

drone_connection = DroneConnection()
vision_manager = VisionManager()  # NEU: Vision Manager Instanz
control = None
telemetry = None

# Video stream state
video_streaming = False

@app.post("/connect")
async def connect(data: dict):
    global control, telemetry
    
    ip = data.get("ip", "192.168.10.1") # Standard Tello IP
    print(f"[DEBUG] Connect request for IP: {ip}")

    success = drone_connection.connect(ip)
    print(f"[DEBUG] Connect success: {success}")

    if success:
        drone_connection.send_command("command")
        drone_connection.send_command("streamon")
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
    
    vision_manager.stop_recording() # Sicherstellen, dass Aufnahme stoppt
    drone_connection.disconnect()
    control = None
    telemetry = None
    return {"success": True}

# --- NEUE ENDPUNKTE FÜR VISION & RECORDING ---

@app.post("/vision/toggle_ai")
async def toggle_ai(data: dict):
    state = data.get("enabled", False)
    vision_manager.toggle_ai(state)
    print(f"[VISION] AI Detection: {state}")
    return {"ai_enabled": state}

@app.post("/vision/toggle_record")
async def toggle_record(data: dict):
    state = data.get("recording", False)
    if state:
        # Flag setzen, Start erfolgt im Video-Loop
        vision_manager.is_recording = True
    else:
        vision_manager.stop_recording()
    print(f"[VISION] Recording: {state}")
    return {"recording": state}

# --------------------------------------------

@app.post("/command")
async def send_command(data: dict):
    if not drone_connection.connected or control is None:
        return {"success": False, "error": "Not connected"}

    cmd = data.get("command", "")
    args = data.get("args", {})

    try:
        if cmd == "takeoff": control.takeoff()
        elif cmd == "land": control.land()
        elif cmd == "emergency": control.emergency_stop()
        elif cmd == "forward": control.forward(args.get("distance", 50))
        elif cmd == "backward": control.backward(args.get("distance", 50))
        elif cmd == "left": control.left(args.get("distance", 50))
        elif cmd == "right": control.right(args.get("distance", 50))
        elif cmd == "up": control.up(args.get("distance", 30))
        elif cmd == "down": control.down(args.get("distance", 30))
        elif cmd == "rotate_left": control.rotate_left(args.get("angle", 45))
        elif cmd == "rotate_right": control.rotate_right(args.get("angle", 45))
        return {"success": True}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.websocket("/video")
async def video_stream(websocket: WebSocket):
    """Stream verarbeitete Video-Frames (KI & Recording) an das Frontend."""
    await websocket.accept()

    if not drone_connection.connected:
        await websocket.send_json({"error": "Not connected"})
        await websocket.close()
        return

    # Tello Video-Stream via UDP
    cap = cv2.VideoCapture("udp://@0.0.0.0:11111", cv2.CAP_FFMPEG)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    if not cap.isOpened():
        await websocket.send_json({"error": "Could not open video stream"})
        await websocket.close()
        return

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                await asyncio.sleep(0.01)
                continue

            # --- BILDVERARBEITUNG ---
            # Aufnahme initialisieren falls vom User aktiviert
            if vision_manager.is_recording and vision_manager.video_writer is None:
                h, w, _ = frame.shape
                vision_manager.start_recording(w, h)

            # Bild durch VisionManager schicken (KI-Boxen zeichnen & Recording)
            processed_frame = vision_manager.process_frame(frame)
            # ------------------------

            # Frame als JPEG komprimieren (Qualität 60 für flüssigen Stream)
            _, buffer = cv2.imencode(".jpg", processed_frame, [cv2.IMWRITE_JPEG_QUALITY, 60])
            jpg_b64 = base64.b64encode(buffer).decode("utf-8")

            await websocket.send_text(jpg_b64)
            await asyncio.sleep(0.03)  # Ziel: ca. 30 FPS
            
    except WebSocketDisconnect:
        print("[DEBUG] Video WebSocket disconnected")
    finally:
        cap.release()

@app.websocket("/rc")
async def rc_control(websocket: WebSocket):
    await websocket.accept()
    
    if not drone_connection.connected or control is None:
        await websocket.send_json({"error": "Not connected"})
        await websocket.close()
        return

    async def send_telemetry():
        try:
            while True:
                if telemetry:
                    data = telemetry.get_all_telemetry()
                    await websocket.send_json({"type": "telemetry", "data": data})
                await asyncio.sleep(1)
        except:
            pass

    tele_task = asyncio.create_task(send_telemetry())

    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)
            
            cmd = msg.get("command")
            if cmd:
                if cmd == "takeoff": control.takeoff()
                elif cmd == "land": control.land()
                elif cmd == "emergency": control.emergency_stop()
                continue 

            control.send_rc(
                int(msg.get("a", 0)),
                int(msg.get("b", 0)),
                int(msg.get("c", 0)),
                int(msg.get("d", 0))
            )
    except WebSocketDisconnect:
        control.send_rc(0, 0, 0, 0)
    finally:
        tele_task.cancel()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)