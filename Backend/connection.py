import socket

class DroneConnection:
    DRONE_PORT = 8889
    CONNECTION_TIMEOUT = 10

    def __init__(self):
        self.ip_address = None
        self.socket = None
        self.connected = False

    def connect(self, ip_address: str) -> bool:
        try:
            self.ip_address = ip_address
            print(f"[INFO] Connecting to drone at {ip_address}:{self.DRONE_PORT}")
            
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.socket.settimeout(self.CONNECTION_TIMEOUT)
            
            self.socket.sendto(b"command", (ip_address, self.DRONE_PORT))
            
            response, _ = self.socket.recvfrom(1024)
            if response.decode("utf-8").strip() == "ok":
                print(f"[OK] Connection to {ip_address} confirmed.")
                self.connected = True
                return True
            else:
                print(f"[ERROR] Unexpected response: {response}")
                return False
        except Exception as e:
            print(f"[ERROR] Connection failed: {e}")
            self.connected = False
            return False

    def send_command(self, command: str):
        if self.connected and self.socket:
            self.socket.sendto(f"{command}".encode("utf-8"), (self.ip_address, self.DRONE_PORT))

    def send_command_with_response(self, command: str) -> str:
        if self.connected and self.socket:
            try:
                self.socket.sendto(command.encode("utf-8"), (self.ip_address, self.DRONE_PORT))
                response, _ = self.socket.recvfrom(1024)
                return response.decode("utf-8").strip()
            except Exception as e:
                print(f"[ERROR] Command failed: {e}")
                return "N/A"
        return "N/A"

    def disconnect(self):
        if self.socket:
            self.socket.close()
        self.connected = False
