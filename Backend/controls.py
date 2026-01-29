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
y
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


    #Keyboard Steuerung
    def keyboard_control(self, speed=50):

    print("WASD = Beweegen, Pfeile = Höhe / Drehung , E = Start, Q = Landen, ESC = Beenden")

    self.running = True

    forward = 0
    right = 0
    up = 0
    yaw = 0

    


    