import time
import socket

class Control:
    def __init__(self, connection):
        """
        Initialisiert die Steuerung mit einem DroneConnection Objekt.
        connection.socket ist der UDP-Socket, connection.ip_address das Ziel.
        """
        self.connection = connection
        self.socket = connection.socket
        self.address = (connection.ip_address, connection.DRONE_PORT)

    def send_command(self, command: str):
        """Sendet einen Textbefehl an die Drohne via UDP."""
        try:
            print(f"[DEBUG] Sende Befehl: {command}")
            self.socket.sendto(command.encode('utf-8'), self.address)
            # Optional: Antwort empfangen (Tello antwortet meist mit 'ok')
            # response, _ = self.socket.recvfrom(1024)
            # return response.decode().strip()
        except Exception as e:
            print(f"[FEHLER] Konnte Befehl '{command}' nicht senden: {e}")

    def takeoff(self):
        self.send_command("takeoff")

    def land(self):
        self.send_command("land")

    def forward(self, distance=50):
        self.send_command(f"forward {distance}")

    def backward(self, distance=50):
        self.send_command(f"back {distance}")

    def left(self, distance=50):
        self.send_command(f"left {distance}")

    def right(self, distance=50):
        self.send_command(f"right {distance}")

    def up(self, distance=30):
        self.send_command(f"up {distance}")

    def down(self, distance=30):
        self.send_command(f"down {distance}")

    def rotate_left(self, angle=45):
        self.send_command(f"ccw {angle}")

    def rotate_right(self, angle=45):
        self.send_command(f"cw {angle}")

    def send_rc(self, a, b, c, d):
        """
        a: links/rechts (-100 bis 100)
        b: vor/zurück (-100 bis 100)
        c: hoch/runter (-100 bis 100)
        d: gieren (yaw) (-100 bis 100)
        """
        self.send_command(f"rc {a} {b} {c} {d}")

    def emergency_stop(self):
        print("[NOT-STOPP]")
        self.send_command("emergency")
