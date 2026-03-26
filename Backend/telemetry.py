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
            # Robomaster SDK
            return self.drone.height.get_height()
        except Exception:
            # Tello SDK / DroneConnection
            if hasattr(self.drone, "send_command_with_response"):
                res = self.drone.send_command_with_response("height?")
                # Tello returns something like '15dm' or '0'
                if isinstance(res, str):
                    lower_res = res.lower().strip()
                    # Filter out non-numeric noise like "ok", "error", or attitude strings
                    if lower_res == "ok" or ";" in res or ":" in res:
                        return "---"
                    
                    import re
                    match = re.search(r'(-?\d+)', res)
                    if match:
                        val = int(match.group(1))
                        # Tello height command often returns dm, convert to cm
                        if "dm" in res.lower():
                            return f"{val * 10} cm"
                        return f"{val} cm"
                return "0 cm"
            return "0 cm"
        
    def get_temperature(self):
        try:
            return self.drone.temperature.get_temperature()
        except Exception:
            if hasattr(self.drone, "send_command_with_response"):
                res = self.drone.send_command_with_response("temp?")
                if not isinstance(res, str):
                    return "0 °C"
                
                # Filter out corrupted attitude/battery/height strings
                if ";" in res or ":" in res or "dm" in res or "ok" in res:
                    return "---"

                # Tello returns '85~88C'
                if "~" in res:
                    try:
                        parts = res.replace('C', '').split('~')
                        avg = (int(parts[0]) + int(parts[1])) // 2
                        return f"{avg} °C"
                    except:
                        pass
                # Extract any number found
                import re
                match = re.search(r'(\d+)', str(res))
                return f"{match.group(1)} °C" if match else "0 °C"
            return "0 °C"
        
    def get_speed(self):
        try:
            # Check if we have live state from the background thread
            if hasattr(self.drone, "last_state") and self.drone.last_state:
                # Tello state has vgx, vgy, vgz (velocity in x, y, z)
                # We calculate the vector speed for the ground (horizontal)
                vx = int(self.drone.last_state.get('vgx', 0))
                vy = int(self.drone.last_state.get('vgy', 0))
                # Pythagorean theorem for horizontal speed
                import math
                speed = math.sqrt(vx**2 + vy**2)
                return f"{speed:.1f} cm/s"
            
            return self.drone.speed.get_speed()
        except Exception:
            if hasattr(self.drone, "send_command_with_response"):
                # Fallback to the set speed if live velocity fails
                res = self.drone.send_command_with_response("speed?")
                if isinstance(res, str):
                    import re
                    match = re.search(r'(\d+)', res)
                    if match:
                        return f"{match.group(1)} (set)"
                return "0"
            return "0"

    def get_flight_time(self):
        try:
            return self.drone.flight_time.get_flight_time()
        except Exception:
            if hasattr(self.drone, "send_command_with_response"):
                res = self.drone.send_command_with_response("time?")
                if isinstance(res, str):
                    lower_res = res.lower().strip()
                    if lower_res == "ok" or ";" in res or ":" in res:
                        return "0s"
                    import re
                    match = re.search(r'(\d+)', res)
                    return f"{match.group(1)}s" if match else "0s"
                return f"{res}s" if res else "0s"
            return "0s"
        
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
            return f"{self.drone.battery.get_percentage()}%"
        except Exception:
            try:
                # Robomaster TT / Tello SDK
                if hasattr(self.drone, "send_command_with_response"):
                    res = self.drone.send_command_with_response("battery?")
                    if isinstance(res, str):
                        lower_res = res.lower().strip()
                        # Filter out corrupted strings or "ok" confirmation
                        if lower_res == "ok" or ";" in res or ":" in res or "~" in res or "dm" in res:
                            return "---"
                        
                        import re
                        match = re.search(r'(\d+)', res)
                        return f"{match.group(1)}%" if match else "---"
                    return f"{res}%" if res else "---"
                return "---"
            except Exception:
                return "---"
