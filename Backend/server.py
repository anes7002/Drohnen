import asyncio
import json
import threading
import cv2
import base64
import time
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

from connection import DroneConnection
from controls import Control
from telemetry import Telemetry

app = FastAPI()

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
    ip = data.get("ip", "192.168.10.1")
    success = drone_connection.connect(ip)
    if success:
        control = Control(drone_connection)
        telemetry = Telemetry(drone_connection)
        # Enable video stream on the drone
        drone_connection.send_command("streamon")
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
    """WebSocket for real-time RC joystick control."""
    await websocket.accept()

    if not drone_connection.connected or control is None:
        await websocket.send_json({"error": "Not connected"})
        await websocket.close()
        return

    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)
            a = int(msg.get("a", 0))
            b = int(msg.get("b", 0))
            c = int(msg.get("c", 0))
            d = int(msg.get("d", 0))
            control.send_rc(a, b, c, d)
    except WebSocketDisconnect:
        control.send_rc(0, 0, 0, 0)


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
