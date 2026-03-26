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
    print("BITTE ÖFFNE EIN ZWEITES TERMINAL FÜR DIE TELEMETRIE:")
    print("python Backend/telemetry_viewer.py")
    print("-" * 40)
    print("Connecting to /rc WebSocket for Control...")

    try:
        async with websockets.connect(uri_rc) as ws_rc:
            print("Connected! Steuerung ist aktiv.")
            print("\nSTEUERUNG:")
            print("  T: Starten          L: Landen         E: Not-Aus")
            print("  W/S: Vor/Zurück     A/D: Links/Rechts")
            print("  I/K: Hoch/Runter    J/L: Drehen")
            print("  Q: Beenden")
            print("-" * 40)

            while True:
                # Use a small timeout for the executor to keep the loop responsive
                try:
                    loop = asyncio.get_event_loop()
                    key = await loop.run_in_executor(None, get_key)
                    if not key:
                        continue
                    key = key.lower()
                except Exception as e:
                    print(f"\nFehler bei Eingabe: {e}")
                    break

                cmd = None
                
                # Command mapping (Increased to 100 for maximum speed)
                if   key == 't': cmd = {"command": "takeoff"}
                elif key == 'l': cmd = {"command": "land"}
                elif key == 'e': cmd = {"command": "emergency"}
                elif key == 'w': cmd = {"a": 0,   "b": 100, "c": 0,   "d": 0}
                elif key == 's': cmd = {"a": 0,   "b": -100,"c": 0,   "d": 0}
                elif key == 'a': cmd = {"a": -100,"b": 0,   "c": 0,   "d": 0}
                elif key == 'd': cmd = {"a": 100, "b": 0,   "c": 0,   "d": 0}
                elif key == 'i': cmd = {"a": 0,   "b": 0,   "c": 100, "d": 0}
                elif key == 'k': cmd = {"a": 0,   "b": 0,   "c": -100,"d": 0}
                elif key == 'j': cmd = {"a": 0,   "b": 0,   "c": 0,   "d": -100}
                elif key == 'o': cmd = {"a": 0,   "b": 0,   "c": 0,   "d": 100} # Changed rotate right to 'o' because 'l' is landing
                elif key == 'q':
                    print("\nBeende...")
                    break
                else:
                    cmd = {"a": 0, "b": 0, "c": 0, "d": 0}

                if cmd:
                    try:
                        await ws_rc.send(json.dumps(cmd))
                        # For RC movements, brief pause then stop
                        if "a" in cmd and any(v != 0 for v in cmd.values()):
                            await asyncio.sleep(0.05)
                            await ws_rc.send(json.dumps({"a": 0, "b": 0, "c": 0, "d": 0}))
                    except websockets.exceptions.ConnectionClosed:
                        print("\nVerbindung verloren.")
                        break
            
            msg_task.cancel()

    except Exception as e:
        print(f"\nError connecting to server: {e}")
        print("Make sure 'uvicorn server:app' is running.")

if __name__ == "__main__":
    asyncio.run(test_rc_interactive())
