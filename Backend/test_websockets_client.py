import asyncio
import websockets
import json
import sys
import termios
import tty

def get_key():
    """Reads a single key press from the terminal (Linux/macOS)."""
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(sys.stdin.fileno())
        ch = sys.stdin.read(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    return ch

async def test_rc_interactive():
    uri_rc = "ws://localhost:8000/rc"
    
    print("\n" + "="*40)
    print(" WebSocket Drone Control Client")
    print("="*40)
    print("Connecting to /rc WebSocket...")

    try:
        async with websockets.connect(uri_rc) as ws_rc:
            print("Connected to /rc! Real-time control active.")
            print("\nCONTROLS:")
            print("  T: Takeoff          L: Land           E: Emergency")
            print("  W/S: Forward/Back   A/D: Left/Right")
            print("  I/K: Up/Down        J/L: Rotate L/R")
            print("  Q: Quit")
            print("-" * 40)
            
            while True:
                # Get key from terminal
                loop = asyncio.get_event_loop()
                key = await loop.run_in_executor(None, get_key)
                key = key.lower()

                cmd = None
                
                # Command mapping
                if   key == 't': cmd = {"command": "takeoff"}
                elif key == 'l': cmd = {"command": "land"}
                elif key == 'e': cmd = {"command": "emergency"}
                elif key == 'w': cmd = {"a": 0,  "b": 60, "c": 0,  "d": 0}
                elif key == 's': cmd = {"a": 0,  "b": -60,"c": 0,  "d": 0}
                elif key == 'a': cmd = {"a": -60,"b": 0,  "c": 0,  "d": 0}
                elif key == 'd': cmd = {"a": 60, "b": 0,  "c": 0,  "d": 0}
                elif key == 'i': cmd = {"a": 0,  "b": 0,  "c": 60, "d": 0}
                elif key == 'k': cmd = {"a": 0,  "b": 0,  "c": -60,"d": 0}
                elif key == 'j': cmd = {"a": 0,  "b": 0,  "c": 0,  "d": -60}
                elif key == 'l': cmd = {"a": 0,  "b": 0,  "c": 0,  "d": 60}
                elif key == 'q':
                    print("\nQuitting...")
                    break
                else:
                    # Optional: Hover on other keys
                    cmd = {"a": 0, "b": 0, "c": 0, "d": 0}

                if cmd:
                    try:
                        await ws_rc.send(json.dumps(cmd))
                        # For RC movements (a/b/c/d), send a stop/hover command shortly after 
                        # so the drone doesn't fly away indefinitely on a single tap.
                        if "a" in cmd and any(v != 0 for v in cmd.values()):
                            await ws_rc.send(json.dumps({"a": 0, "b": 0, "c": 0, "d": 0}))
                    except websockets.exceptions.ConnectionClosed:
                        print("\nConnection closed by server. Is the drone connected?")
                        break

    except Exception as e:
        print(f"\nError connecting to server: {e}")
        print("Make sure 'uvicorn server:app' is running.")

if __name__ == "__main__":
    asyncio.run(test_rc_interactive())
