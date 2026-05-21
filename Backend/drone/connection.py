import socket
import threading
import time


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
        """Hintergrund-Thread: empfängt Tello-Statusmeldungen auf Port 8890."""
        print(f"[INFO] State-Listener gestartet auf Port {self.STATE_PORT}")
        while self.connected and self.state_socket:
            try:
                data, _ = self.state_socket.recvfrom(1024)
                state_str = data.decode("utf-8").strip()
                # Tello-Format: "pitch:0;roll:0;yaw:0;vgx:0;vgy:0;vgz:0;..."
                new_state = {}
                for item in state_str.split(";"):
                    if ":" in item:
                        key, val = item.split(":")
                        new_state[key] = val
                self.last_state = new_state
            except Exception:
                if not self.connected:
                    break
                time.sleep(0.1)

    def connect(self, ip_address: str) -> bool:
        try:
            self.ip_address = ip_address
            print(f"[INFO] Verbinde mit Drohne {ip_address}:{self.DRONE_PORT}")

            self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.socket.settimeout(self.CONNECTION_TIMEOUT)

            self.state_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.state_socket.bind(("", self.STATE_PORT))

            self.socket.sendto(b"command", (ip_address, self.DRONE_PORT))
            response, _ = self.socket.recvfrom(1024)

            if response.decode("utf-8").strip() == "ok":
                print(f"[OK] Verbindung zu {ip_address} bestätigt")
                self.connected = True
                self.state_thread = threading.Thread(
                    target=self._state_listener, daemon=True
                )
                self.state_thread.start()
                return True
            else:
                print(f"[ERROR] Unerwartete Antwort: {response}")
                return False
        except Exception as e:
            print(f"[ERROR] Verbindung fehlgeschlagen: {e}")
            self.connected = False
            return False

    def send_command(self, command: str):
        """Sendet einen Befehl ohne auf eine Antwort zu warten."""
        if self.connected and self.socket:
            self.socket.sendto(command.encode("utf-8"), (self.ip_address, self.DRONE_PORT))

    def send_command_with_response(self, command: str) -> str:
        """
        Sendet einen Befehl und wartet auf die Antwort der Drohne ("ok" / "error").
        Leert den Puffer vorher, um veraltete Antworten zu ignorieren.
        """
        if not (self.connected and self.socket):
            return "N/A"
        try:
            # Puffer leeren, damit keine alten Antworten störend eingelesen werden
            self.socket.setblocking(False)
            try:
                while True:
                    self.socket.recvfrom(1024)
            except Exception:
                pass
            self.socket.settimeout(self.CONNECTION_TIMEOUT)

            self.socket.sendto(command.encode("utf-8"), (self.ip_address, self.DRONE_PORT))

            # Telemetrie-Pakete (enthalten ":") überspringen, echte Antwort abwarten
            while True:
                response, _ = self.socket.recvfrom(1024)
                decoded = response.decode("utf-8").strip()
                if ":" not in decoded and decoded:
                    return decoded
        except Exception as e:
            print(f"[ERROR] Befehl '{command}' fehlgeschlagen: {e}")
            return "N/A"

    def disconnect(self):
        self.connected = False
        if self.socket:
            self.socket.close()
        if self.state_socket:
            self.state_socket.close()
