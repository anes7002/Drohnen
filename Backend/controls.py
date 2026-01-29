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

    



    