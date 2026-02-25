def get_all_telemetry(self):
    if not self.connected:
        raise Exception("Drone is not connected")
    
    return {
        "battery": self.drone.get_battery(),
        "height": self.drone.get_height(),
        "speed": self.drone.get_speed(),
        "pitch": self.drone.get_pitch(),
        "roll": self.drone.get_roll(),
        "yaw": self.drone.get_yaw(),
        "flight_time": self.drone.get_flight_time(),
    }

def get_battery(self):
    if not self.connected:
        raise Exception("Drone is not connected")
    
    return self.drone.get_battery()

def get_height(self):
    if not self.connected:
        raise Exception("Drone is not connected")
    
    return self.drone.get_height()

def get_speed(self):
    if not self.connected:
        raise Exception("Drone is not connected")
    
    return self.drone.get_speed()

def get_pitch(self):
    if not self.connected:
        raise Exception("Drone is not connected")
    
    return self.drone.get_pitch()

def get_roll(self):
    if not self.connected:
        raise Exception("Drone is not connected")
    
    return self.drone.get_roll()

def get_yaw(self):
    if not self.connected:
        raise Exception("Drone is not connected")
    
    return self.drone.get_yaw()

def get_flight_time(self):
    if not self.connected:
        raise Exception("Drone is not connected")
    
    return self.drone.get_flight_time()