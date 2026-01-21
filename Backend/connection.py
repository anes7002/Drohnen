import socket

class DroneConnection:
    DRONE_PORT = 8888
    CONNECTION_TIMEOUT = 5

    def __init__(self):
        self.socket = None
        self.connected = False

    def connect(self, ip_address: str) -> bool:
        try:
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.settimeout(self.CONNECTION_TIMEOUT)
            self.socket.connect((ip_address, self.DRONE_PORT))
            self.connected = True
            return True
        except Exception as e:
            print(f"[FEHLER] Verbindung fehlgeschlagen: {e}")
            self.connected = False
            return False

    def disconnect(self):
        if self.socket:
            self.socket.close()
        self.connected = False

   

        
