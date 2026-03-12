import asyncio
import websockets
import json
import sys
from pynput import keyboard

# URL für RC-Control-WebSocket
WS_URI_RC = "ws://127.0.0.1:8000/rc"

async def test_rc_interactive():
    """Testet den RC-Control-WebSocket interaktiv mit Tastendruck."""
    print(f"Versuche Verbindung zu {WS_URI_RC}...")
    
    try:
        async with websockets.connect(WS_URI_RC) as websocket:
            print("[OK] Verbunden mit RC-WebSocket.")
            print("\n--- Steuerung via WebSocket (Tastatur) ---")
            print("W/S: Vorwärts/Rückwärts | A/D: Links/Rechts")
            print("I/K: Hoch/Runter          | J/L: Drehen")
            print("Esc: Beenden")
            print("------------------------------------------")

            rc_state = {"a": 0, "b": 0, "c": 0, "d": 0}
            SPEED = 40

            def on_press(key):
                nonlocal rc_state
                try:
                    k = key.char.lower()
                    if k == 'w': rc_state["b"] = SPEED
                    elif k == 's': rc_state["b"] = -SPEED
                    elif k == 'a': rc_state["a"] = -SPEED
                    elif k == 'd': rc_state["a"] = SPEED
                    elif k == 'i': rc_state["c"] = SPEED
                    elif k == 'k': rc_state["c"] = -SPEED
                    elif k == 'j': rc_state["d"] = -SPEED
                    elif k == 'l': rc_state["d"] = SPEED
                except AttributeError:
                    if key == keyboard.Key.esc:
                        return False

            def on_release(key):
                nonlocal rc_state
                try:
                    k = key.char.lower()
                    if k in ['w', 's']: rc_state["b"] = 0
                    if k in ['a', 'd']: rc_state["a"] = 0
                    if k in ['i', 'k']: rc_state["c"] = 0
                    if k in ['j', 'l']: rc_state["d"] = 0
                except AttributeError:
                    pass

            # Listener aktiv halten
            with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
                while listener.running:
                    await websocket.send(json.dumps(rc_state))
                    sys.stdout.write(f"\rSende RC: {rc_state}   ")
                    sys.stdout.flush()
                    await asyncio.sleep(0.1)

            print("\n[OK] Test beendet.")
            
    except Exception as e:
        print(f"\n[FEHLER] Verbindung fehlgeschlagen: {e}")

if __name__ == "__main__":
    try:
        asyncio.run(test_rc_interactive())
    except KeyboardInterrupt:
        pass
