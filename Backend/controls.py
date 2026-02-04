import time
from robomaster import robot
import keyboard

class Control:

    def __init__(self, drone):
        self.drone = drone

    #Starten
    def takeoff(self):
        self.drone.flight.takeoff()

    #Landen
    def land(self):
        self.drone.flight.land()

    #Bewegen
    def forward(self, distance=50):
        self.drone.flight.forward(distance)

    def backward(self, distance=50):
        self.drone.flight.backward(distance)

    def left(self, distance=50):
        self.drone.flight.left(distance)

    def right(self, distance=50):
        self.drone.flight.right(distance)

    #Steigen und Sinken
    def up(self, distance=30):
        self.drone.flight.up(distance)

    def down(self, distance=30):
        self.drone.flight.down(distance)

    #Drehung 
      def rotate_left(self, angle=45):
        self.drone.flight.turn_left(angle)

    def rotate_right(self, angle=45):
        self.drone.flight.turn_right(angle)

    #Stopp function
    def emergency_stop(self):
        print("[NOT-STOPP]")
        self.drone.flight.rc(0, 0, 0, 0)
        self.drone.flight.land()
        self.running = False

     def send_rc(self, forward, right, up, yaw):
        self.drone.flight.rc(forward, right, up, yaw)
    
    #Keyboard Steuerung
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
        if keyboard.is_pressed("right")
            yaw = speed
        
        if keyboard.is_pressed("e")
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


    


    