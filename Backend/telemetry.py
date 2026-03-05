class Telemetry:
    def __init__(self, drone):
        self.drone = drone

    def get_all_telemetry(self):
        return {
            "battery": self.get_battery(),
            "height": self.get_height(),
            "temp": self.get_temperature(),
            "speed": self.get_speed(),
            "flight_time": self.get_flight_time(),
            "attitude": self.get_attitude()
        }
    def get_height(self):
        try:
            # Robomaster SDK
            return self.drone.height.get_height()
        except Exception:
            # Tello SDK / DroneConnection
            if hasattr(self.drone, "send_command_with_response"):
                return self.drone.send_command_with_response("height?")
            return "N/A"
        
    def get_temperature(self):
        try:
            return self.drone.temperature.get_temperature()
        except Exception:
            if hasattr(self.drone, "send_command_with_response"):
                return self.drone.send_command_with_response("temp?")
            return "N/A"
        
    def get_speed(self):
        try:
            return self.drone.speed.get_speed()
        except Exception:
            if hasattr(self.drone, "send_command_with_response"):
                return self.drone.send_command_with_response("speed?")
            return "N/A"

    def get_flight_time(self):
        try:
            return self.drone.flight_time.get_flight_time()
        except Exception:
            if hasattr(self.drone, "send_command_with_response"):
                return self.drone.send_command_with_response("time?")
            return "N/A"
        
    def get_attitude(self):
        try:
            return self.drone.attitude.get_attitude()
        except Exception:
            if hasattr(self.drone, "send_command_with_response"):
                return self.drone.send_command_with_response("attitude?")
            return "N/A"
    

    def get_battery(self):
        try:
            # Robomaster EP/S1
            return self.drone.battery.get_percentage()
        except Exception:
            try:
                # Robomaster TT / Tello SDK
                # Falls drone eine DroneConnection ist, sende Befehl 'battery?'
                if hasattr(self.drone, "send_command_with_response"):
                    return self.drone.send_command_with_response("battery?")
                return "N/A"
            except Exception:
                return "N/A"
