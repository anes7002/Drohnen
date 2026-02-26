import socket

class DroneConnection:
    DRONE_PORT = 8889
    CONNECTION_TIMEOUT = 5

    def __init__(self):
        self.ip_address = None
        self.socket = None
        self.connected = False

    def connect(self, ip_address: str) -> bool:
        try:
            self.ip_address = ip_address
            print(f"[INFO] Verbinde zu Drohne unter {ip_address}:{self.DRONE_PORT}...")
            # Tello nutzt UDP für Befehle auf Port 8889
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.socket.settimeout(self.CONNECTION_TIMEOUT)
            
            # Tello SDK aktivieren (Befehl 'command' senden)
            self.socket.sendto(b'command', (ip_address, self.DRONE_PORT))
            
            # Kurze Antwort abwarten zur Bestätigung
            response, _ = self.socket.recvfrom(1024)
            if response.decode().strip() == 'ok':
                print(f"[OK] Verbindung zu {ip_address} bestätigt.")
                self.connected = True
                return True
            else:
                print(f"[FEHLER] Unerwartete Antwort: {response}")
                return False
        except Exception as e:
            print(f"[FEHLER] Verbindung fehlgeschlagen: {e}")
            self.connected = False
            return False

    def disconnect(self):
        if self.socket:
            self.socket.close()
        self.connected = False

   

        
