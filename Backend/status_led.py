import socket
import time


class StatusLED:
    def __init__(self, connection=None, ip="192.168.0.104"):
        self.connection = connection
        self.ip = ip
        self.port = 8889

    def _send_raw_command(self, cmd):
        """
        Sendet LED-Befehle direkt per UDP.
        Funktioniert nur bei Tello Talent (TT) mit ESP32 Erweiterungsmodul.
        """
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.settimeout(3)

            # SDK-Modus aktivieren
            sock.sendto(b"command", (self.ip, self.port))
            response, _ = sock.recvfrom(1024)
            print("[DEBUG] command:", response.decode())

            time.sleep(0.5)

            # Erweiterungsmodul aktivieren
            sock.sendto(b"mon", (self.ip, self.port))
            response, _ = sock.recvfrom(1024)
            print("[DEBUG] mon:", response.decode())

            time.sleep(0.5)

            # LED-Befehl senden
            sock.sendto(cmd.encode("utf-8"), (self.ip, self.port))
            response, _ = sock.recvfrom(1024)
            print("[DEBUG] LED:", response.decode())

            sock.close()

        except socket.timeout:
            print("[LED] Keine Antwort von der Drohne erhalten.")
        except Exception as e:
            print(f"[LED] Fehler beim Senden des Raw-Befehls: {e}")

    def connecting(self):
        print("[LED] Verbindung wird aufgebaut (Blau)")
        self.set_color(0, 255, 0)

    def connected(self):
        print("[LED] Verbunden (Grün)")
        self.set_color(0, 0, 255)

    def error(self):
        print("[LED] Fehler (Rot)")
        self.set_color(255, 0, 0)

    def warning(self):
        print("[LED] Warnung (Gelb)")
        self.set_color(255, 255, 0)

    def set_color(self, r, g, b):
        
        
        cmd = f"EXT led {r} {g} {b}"

        if self.connection and hasattr(self.connection, "connected") and self.connection.connected:
            try:
                response = self.connection.send_command(cmd)
                print("[DEBUG] Verbindung aktiv:", response)
            except Exception as e:
                print("[LED] Fehler über connection:", e)
        else:
            self._send_raw_command(cmd)

    def off(self):
        print("[LED] Aus")
        self.set_color(0, 0, 0)

    def on(self, r=255, g=255, b=255):
        print(f"[LED] An ({r}, {g}, {b})")
        self.set_color(r, g, b)

    def blink(self, r, g, b, times=5, interval=0.3):
        print(f"[LED] Blinken Farbe ({r}, {g}, {b}) x{times}")
        for _ in range(times):
            self.set_color(r, g, b)
            time.sleep(interval)
            self.off()
            time.sleep(interval)