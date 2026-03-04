import time
from robomaster import robot
import keyboard

class Control:

    def __init__(self, drone):
        self.drone = drone
        self.running = False

    def takeoff(self):
        self.drone.flight.takeoff()
    
    def land(self):
        self.drone.flight.land()

    def send_rc(self, forward, right, up, yaw):
        self.drone.flight.rc(forward, right, up, yaw)

    
    def keyboard_control(self, speed=50):
        print(
            "Steuerung:\n"
            "W=Vorwärts\n"
            "S=Rückwärts\n"
            "A=Links\n"
            "D=Rechts\n"
            "Pfeil Hoch = Steigen\n"
            "Pfeil Runter = Sinken\n"
            "Pfeil Links/Rechts = Drehen\n"
            "E = Start\n"
            "Q = Landen\n"
            "ESC = STOPP\n"
        )

        self.running = True

        while self.running:
            forward = 0
            right = 0
            up = 0
            yaw = 0

            if keyboard.is_pressed('w'):
                forward = speed
            if keyboard.is_pressed('s'):
                forward = -speed

            if keyboard.is_pressed('a'):
                right = -speed
            if keyboard.is_pressed('d'):
                right = speed

            if keyboard.is_pressed('up'):
                up = speed
            if keyboard.is_pressed("down"):
                up = -speed

            if keyboard.is_pressed("left"):
                yaw = -speed
            if keyboard.is_pressed("right"):
                yaw = speed
            
            if keyboard.is_pressed("e"):
                self.takeoff()
                time.sleep(1)

            if keyboard.is_pressed('q'):
                self.land()
                time.sleep(1)

            if keyboard.is_pressed('esc'):
                self.emergency_stop()
                break

            self.send_rc(forward, right, up, yaw)
            time.sleep(0.05)

    