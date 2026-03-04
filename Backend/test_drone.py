import ipaddress
import time
import threading
from connection import DroneConnection
from controls import Control
from telemetry import Telemetry
from pynput import keyboard

def ask_for_ip() -> str:
    default_ip = "192.168.0.104"
    while True:
        ip_input = input(f"Bitte gib die IP-Adresse der Drohne ein [Standard: {default_ip}]: ").strip()
        if not ip_input:
            return default_ip
        try:
            ipaddress.ip_address(ip_input)
            return ip_input
        except ValueError:
            print(f"[FEHLER] Ungültige IP-Adresse. Beispiel: {default_ip}")

def main():
    connection = DroneConnection()
    ip_address = ask_for_ip()

    if connection.connect(ip_address):
        print("[OK] Verbindung zur Drohne erfolgreich hergestellt.")
        
        # Instanziierung der Control-Klasse mit dem Connection-Objekt
        controls = Control(connection)
        telemetry = Telemetry(connection)
        
        def display_telemetry():
            while connection.connected:
                data = telemetry.get_all_telemetry()
                output = (
                    f"\r[TELEMETRY] "
                    f"BAT: {data['battery']}% | "
                    f"H: {data['height']}cm | "
                    f"SPD: {data['speed']}cm/s | "
                    f"TIME: {data['flight_time']}s | "
                    f"TEMP: {data['temp']}°C | "
                    f"ATT: {data['attitude']}"
                )
                # Auffüllen mit Leerzeichen um Reste alter (längerer) Zeilen zu löschen
                print(output.ljust(120), end="", flush=True)
                time.sleep(1)

        telemetry_thread = threading.Thread(target=display_telemetry, daemon=True)
        telemetry_thread.start()
        
        print("\n--- Tastatursteuerung Aktiv ---")
        print("W: Vorwärts | S: Rückwärts | A: Links | D: Rechts")
        print("I: Hoch      | K: Runter     | J: Drehen Links | L: Drehen Rechts")
        print("T: Takeoff   | G: Landen     | E: Not-Stopp")
        print("Esc: Beenden")
        print("-------------------------------")

        # Aktueller Status der Achsen (links/rechts, vor/zurück, hoch/runter, yaw)
        rc_state = [0, 0, 0, 0]
        SPEED = 50
        def update_rc():
            controls.send_rc(rc_state[0], rc_state[1], rc_state[2], rc_state[3])

        def on_press(key):
            try:
                k = key.char.lower()
                if k == 'w': rc_state[1] = SPEED
                elif k == 's': rc_state[1] = -SPEED
                elif k == 'a': rc_state[0] = -SPEED
                elif k == 'd': rc_state[0] = SPEED
                elif k == 'i': rc_state[2] = SPEED
                elif k == 'k': rc_state[2] = -SPEED
                elif k == 'j': rc_state[3] = -SPEED
                elif k == 'l': rc_state[3] = SPEED
                elif k == 't': controls.takeoff()
                elif k == 'g': controls.land()
                elif k == 'e': controls.emergency_stop()
                update_rc()
            except AttributeError:
                if key == keyboard.Key.esc:
                    return False

        def on_release(key):
            try:
                k = key.char.lower()
                if k in ['w', 's']: rc_state[1] = 0
                if k in ['a', 'd']: rc_state[0] = 0
                if k in ['i', 'k']: rc_state[2] = 0
                if k in ['j', 'l']: rc_state[3] = 0
                update_rc()
            except AttributeError:
                pass

        with keyboard.Listener(on_press=on_press, on_release=on_release, suppress=True) as listener:
            listener.join()

        print("[OK] Test abgeschlossen.")
    else:
        print("[FEHLER] Verbindung zur Drohne konnte nicht hergestellt werden.")

if __name__ == "__main__":
    main()
