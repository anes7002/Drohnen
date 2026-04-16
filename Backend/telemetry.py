import math

class Telemetry:
    def __init__(self, drone):
        self.drone = drone

    def get_all_telemetry(self):
        try:
            data = {
                "battery": self.get_battery(),
                "height": self.get_height(),
                "temp": self.get_temperature(),
                "speed": self.get_speed(),
                "flight_time": self.get_flight_time(),
                "attitude": self.get_attitude()
            }
            return data
        except:
            return {}

    def get_height(self):
        try:
            if hasattr(self.drone, "last_state") and self.drone.last_state:
                val = self.drone.last_state.get('h', '0')
                return f"{val} cm"
            return "---"
        except Exception:
            return "---"

    def get_battery(self):
        try:
            if hasattr(self.drone, "last_state") and self.drone.last_state:
                val = self.drone.last_state.get('bat', '0')
                return f"{val}%"
            return "---"
        except Exception:
            return "---"

    def get_temperature(self):
        try:
            if hasattr(self.drone, "last_state") and self.drone.last_state:
                temph = int(self.drone.last_state.get('temph', 0))
                templ = int(self.drone.last_state.get('templ', 0))
                return f"{(temph + templ) // 2}°C"
            return "---"
        except Exception:
            return "---"

    def get_speed(self):
        try:
            if hasattr(self.drone, "last_state") and self.drone.last_state:
                vgx = int(self.drone.last_state.get('vgx', 0))
                vgy = int(self.drone.last_state.get('vgy', 0))
                vgz = int(self.drone.last_state.get('vgz', 0))
                speed = math.sqrt(vgx**2 + vgy**2 + vgz**2)
                return f"{speed:.1f} cm/s"
            return "---"
        except Exception:
            return "---"

    def get_flight_time(self):
        try:
            if hasattr(self.drone, "last_state") and self.drone.last_state:
                time_s = self.drone.last_state.get('time', '0')
                return f"{time_s}s"
            return "---"
        except Exception:
            return "---"

    def get_attitude(self):
        try:
            if hasattr(self.drone, "last_state") and self.drone.last_state:
                pitch = self.drone.last_state.get('pitch', 0)
                roll = self.drone.last_state.get('roll', 0)
                yaw = self.drone.last_state.get('yaw', 0)
                return {"pitch": float(pitch), "roll": float(roll), "yaw": float(yaw)}
            return {"pitch": 0.0, "roll": 0.0, "yaw": 0.0}
        except Exception:
            return {"pitch": 0.0, "roll": 0.0, "yaw": 0.0}
