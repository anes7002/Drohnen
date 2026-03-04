from connection import DroneConnection

class DroneManager:
    def __init__(self):
        self.drone_ips = []       # 7.1
        self.active_drone = None  # 7.3
        self.connection = None

    
    def add_drone(self, ip):
        if ip not in self.drone_ips:
            self.drone_ips.append(ip)
            print(f"[INFO] Drohne hinzugefügt: {ip}")

    
    def list_drones(self):
        print("\nGespeicherte Drohnen:")
        for i, ip in enumerate(self.drone_ips):
            print(f"{i}: {ip}")

    
    def select_drone(self, index):
        if index < 0 or index >= len(self.drone_ips):
            print("[FEHLER] Ungültiger Index")
            return False

        ip = self.drone_ips[index]

        
        if self.connection:
            self.connection.disconnect()

        
        self.connection = DroneConnection()
        if self.connection.connect(ip):
            self.active_drone = ip
            print(f"[INFO] Aktive Drohne: {ip}")
            return True
        else:
            print("[FEHLER] Verbindung fehlgeschlagen")
            return False

    def get_active(self):
        return self.active_drone