import time

class StatusLED:

    def __init__(self, drone):
      
        self.drone = drone
        self.led = drone.led

    def connecting(self):
        print("[LED] Verbindung wird aufgebaut (Blau)")
        self.set_color(0, 0, 255)

    def connected(self):
        print("[LED] Verbunden (Grün)")
        self.set_color(0, 255, 0)

    def error(self):
        print("[LED] Fehler (Rot)")
        self.set_color(255, 0, 0)

    
