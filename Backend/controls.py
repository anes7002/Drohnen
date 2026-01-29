import time
from robomaster import drone

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

    



    