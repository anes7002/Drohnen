import socket
import time

class StatusLED:
    def __init__(self, connection, ip="192.168.0.104"):
        self.connection = connection
        self.ip = ip
        self.port = 8889

    def _send_raw_command(self, cmd):
        # Wenn die Drohne noch nicht offiziell via connection.connect() verbunden ist
        # (oder fehlgeschlagen ist), schicken wir ein raw UDP Paket an die IP.
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            # Tello muss im SDK-Modus sein, um ext Befehle zu empfangen
            sock.sendto(b"command", (self.ip, self.port))
            # Kurzer Delay, damit 'command' verarbeitet weden kann bevor 'ext led' kommt
            time.sleep(0.1)
            sock.sendto(cmd.encode("utf-8"), (self.ip, self.port))
            sock.close()
        except Exception as e:
            print(f"[LED] Fehler beim Senden des Raw-Befehls: {e}")

    def connecting(self):
        print("[LED] Verbindung wird aufgebaut (Blau)")
        self.set_color(0, 0, 255)

    def connected(self):
        print("[LED] Verbunden (Grün)")
        self.set_color(0, 255, 0)

    def error(self):
        print("[LED] Fehler (Rot)")
        self.set_color(255, 0, 0)

    def set_color(self, r, g, b):
        cmd = f"ext led {r} {g} {b}"
        if self.connection and self.connection.connected:
            self.connection.send_command(cmd)
        else:
            self._send_raw_command(cmd)

    def off(self):
        self.set_color(0, 0, 0)

    def on(self, r=255, g=255, b=255):
        self.set_color(r, g, b)

    def blink(self, r, g, b, times=5, interval=0.3):
        for _ in range(times):
            self.set_color(r, g, b)
            time.sleep(interval)
            self.off()
            time.sleep(interval)
