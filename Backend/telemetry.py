import djitellopy as tello

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