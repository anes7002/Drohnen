import time

class StatusLED:
    def __init__(self, connection, ip="192.168.0.104"):
        self.connection = connection
        self.ip = ip
        self.port = 8889

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
        # Tello Talent: Das Erweiterungskommando MUSS gross 'EXT' sein
        # (kleines 'ext' -> Drohne antwortet "unknown command: ext").
        # send_command sendet nur, wenn bereits verbunden -> stoert den
        # Handshake nicht (waehrend "connecting" ist connected noch False).
        self.connection.send_command(f"EXT led {r} {g} {b}")

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
