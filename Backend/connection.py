import socket

class DroneConnection:
    DRONE_PORT = 8889
    STATE_PORT = 8890
    CONNECTION_TIMEOUT = 10

    def __init__(self):
        self.ip_address = None
        self.socket = None
        self.state_socket = None
        self.connected = False
        self.last_state = {}
        self.state_thread = None

    def _state_listener(self):
        """Internal thread to listen for Tello state strings on port 8890."""
        print(f"[INFO] State listener started on port {self.STATE_PORT}")
        while self.connected and self.state_socket:
            try:
                data, _ = self.state_socket.recvfrom(1024)
                state_str = data.decode("utf-8").strip()
                # Tello state looks like: "mid:0;x:0;y:0;z:0;mpry:0,0,0;pitch:0;roll:0;yaw:0;vgx:0;vgy:0;vgz:0;..."
                new_state = {}
                for item in state_str.split(';'):
                    if ':' in item:
                        key, val = item.split(':')
                        new_state[key] = val
                self.last_state = new_state
            except Exception:
                if not self.connected:
                    break
                time.sleep(0.1)

    def connect(self, ip_address: str) -> bool:
        try:
            self.ip_address = ip_address
            print(f"[INFO] Connecting to drone at {ip_address}:{self.DRONE_PORT}")
            
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.socket.settimeout(self.CONNECTION_TIMEOUT)
            
            # Setup state socket
            self.state_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.state_socket.bind(('', self.STATE_PORT))
            
            self.socket.sendto(b"command", (ip_address, self.DRONE_PORT))
            
            response, _ = self.socket.recvfrom(1024)
            if response.decode("utf-8").strip() == "ok":
                print(f"[OK] Connection to {ip_address} confirmed.")
                self.connected = True
                
                # Start background state listener
                import threading
                import time
                self.state_thread = threading.Thread(target=self._state_listener, daemon=True)
                self.state_thread.start()
                
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
