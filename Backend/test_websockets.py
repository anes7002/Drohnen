import asyncio
import websockets
import json

# Die URL deines Servers
WS_URI_VIDEO = "ws://127.0.0.1:8000/video"
WS_URI_RC = "ws://127.0.0.1:8000/rc"

async def test_video_stream():
    """Testet den Video-WebSocket (erwartet Base64-Strings)"""
    print(f"Connecting to {WS_URI_VIDEO}...")
    try:
        async with websockets.connect(WS_URI_VIDEO) as websocket:
            print("Connected to Video Stream. Receiving frames (Press Ctrl+C to stop)...")
            # Wir empfangen nur die ersten 5 Frames zum Testen
            for i in range(5):
                message = await websocket.recv()
                # Da es Base64 JPEGs sind, ist die Nachricht ein langer String
                print(f"Frame {i+1} received. Length: {len(message)} characters.")
            print("Video stream test successful (received 5 frames).")
    except Exception as e:
        print(f"Video Stream Error: {e}")

async def test_rc_control():
    """Testet den RC-Control-WebSocket (sendet Steuerbefehle)"""
    print(f"\nConnecting to {WS_URI_RC}...")
    try:
        async with websockets.connect(WS_URI_RC) as websocket:
            print("Connected to RC Control.")
            # Wir senden einen neutralen RC-Befehl (alles 0)
            cmd = {"a": 0, "b": 0, "c": 0, "d": 0}
            await websocket.send(json.dumps(cmd))
            print(f"Sent RC command: {cmd}")
            # Kurz warten, um zu sehen ob die Verbindung stabil bleibt
            await asyncio.sleep(1)
            print("RC control test successful.")
    except Exception as e:
        print(f"RC Control Error: {e}")

async def main():
    # Zuerst Video, dann RC
    await test_video_stream()
    await test_rc_control()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
