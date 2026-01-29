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

    

    