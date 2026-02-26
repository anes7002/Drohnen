import ipaddress
import time
from connection import DroneConnection
from controls import Control

def ask_for_ip() -> str:
    default_ip = "192.168.0.105"
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
        
        print("[INFO] Starte Test-Manöver...")
        controls.takeoff()
        time.sleep(5)
        
        controls.rotate_left(90)
        time.sleep(3)
        
        controls.land()
        print("[OK] Test abgeschlossen.")
    else:
        print("[FEHLER] Verbindung zur Drohne konnte nicht hergestellt werden.")

if __name__ == "__main__":
    main()
