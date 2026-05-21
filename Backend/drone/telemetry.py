import math


class Telemetry:
    def __init__(self, drone):
        self.drone = drone

    @property
    def _state(self) -> dict:
        """Liefert den aktuellen Drohnen-Zustand oder ein leeres Dict."""
        return getattr(self.drone, "last_state", {}) or {}

    def get_all_telemetry(self) -> dict:
        try:
            return {
                "battery":     self.get_battery(),
                "height":      self.get_height(),
                "temp":        self.get_temperature(),
                "speed":       self.get_speed(),
                "flight_time": self.get_flight_time(),
                "attitude":    self.get_attitude(),
                "velocity":    self.get_velocity(),
            }
        except Exception:
            return {}

    def get_height(self) -> str:
        try:
            return f"{self._state.get('h', '0')} cm"
        except Exception:
            return "---"

    def get_battery(self) -> str:
        try:
            return f"{self._state.get('bat', '0')}%"
        except Exception:
            return "---"

    def get_temperature(self) -> str:
        try:
            temph = int(self._state.get("temph", 0))
            templ = int(self._state.get("templ", 0))
            return f"{(temph + templ) // 2}°C"
        except Exception:
            return "---"

    def get_speed(self) -> str:
        try:
            vgx = int(self._state.get("vgx", 0))
            vgy = int(self._state.get("vgy", 0))
            vgz = int(self._state.get("vgz", 0))
            speed = math.sqrt(vgx**2 + vgy**2 + vgz**2)
            return f"{speed:.1f} cm/s"
        except Exception:
            return "---"

    def get_flight_time(self) -> str:
        try:
            return f"{self._state.get('time', '0')}s"
        except Exception:
            return "---"

    def get_attitude(self) -> dict:
        try:
            return {
                "pitch": float(self._state.get("pitch", 0)),
                "roll":  float(self._state.get("roll",  0)),
                "yaw":   float(self._state.get("yaw",   0)),
            }
        except Exception:
            return {"pitch": 0.0, "roll": 0.0, "yaw": 0.0}

    def get_velocity(self) -> dict:
        try:
            return {
                "vgx": float(int(self._state.get("vgx", 0))),
                "vgy": float(int(self._state.get("vgy", 0))),
                "vgz": float(int(self._state.get("vgz", 0))),
            }
        except Exception:
            return {"vgx": 0.0, "vgy": 0.0, "vgz": 0.0}
