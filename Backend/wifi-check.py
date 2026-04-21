from robomaster import robot

# Initialisiere die Drohne im Netzwerkmodus (STA)
drone = robot.Drone()
drone.initialize(conn_type="sta") 

# Wenn dies ohne Fehler durchläuft, ist die Drohne erreichbar
print("Drohne erfolgreich verbunden!")

# IP und SN abfragen
sn = drone.get_sn()
print(f"Seriennummer der Drohne: {sn}")

drone.close()