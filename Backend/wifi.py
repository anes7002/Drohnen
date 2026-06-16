from robomaster import robot
import time

# 1. Verbinde deinen Computer mit dem WLAN der Drohne (RoboMaster-XXXX)
# 2. Führe dieses Skript aus:

drone = robot.Drone()

# Initialisiere die Verbindung zur Drohne in ihrem eigenen WLAN
drone.initialize(conn_type="ap")

print("Sende Konfigurationsbefehl an die Drohne...")

# Hier werden die Zugangsdaten deines Handy-Hotspots eingetragen
# Stelle sicher, dass "Kompatibilität maximieren" am iPhone an ist!
r = drone.config_sta("King", "oscarluli187")

print(f"Befehl wurde gesendet. Rückmeldung: {r}")

# WICHTIG: Die Drohne braucht nach diesem Befehl einen Moment zum Neustart
print("Drohne startet neu... bitte warte 30 Sekunden.")
drone.close()