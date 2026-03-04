class DroneManager:
    def __init__(self):
        self.drone_ips = []
        self.active_drone = None

    def add_drone(self, ip):
        self.drone_ips.append(ip)
        print(f"Drohne hinzugefügt: {ip}")
    
    def show_drones(self):
        print("Gespeicherte Drohnen:")
        for i, ip in enumerate(self.drone_ips):
            print(f"{i}: {ip}")
   
    def select_drone(self, index):
        if 0 <= index < len(self.drone_ips):
            self.active_drone = self.drone_ips[index]
            print(f"Aktive Drohne: {self.active_drone}")
        else:
            print("Ungültige Auswahl!")

    def get_active_drone(self):
        return self.active_drone