class Telemetry:
    def __init__(self, drone):
        self.drone = drone

    def get_all_telemetry(self):
        return {
            "battery": self.get_battery(),
        }

    def get_battery(self):
        try:
            # Robomaster EP/S1
            return self.drone.battery.get_percentage()
        except Exception:
            try:
                # Robomaster TT
                return self.drone.get_battery()
            except Exception:
                return "N/A"
