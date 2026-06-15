import select
import socket
import threading
import time


class DroneConnection:
    DRONE_PORT = 8889
    STATE_PORT = 8890
    CONNECTION_TIMEOUT = 10   # Antwort-Timeout für Befehle (z. B. land dauert lange)
    HANDSHAKE_TIMEOUT = 3     # Timeout pro Verbindungsversuch — im LAN reicht das locker

    def __init__(self):
        self.ip_address = None
        self.socket = None
        self.state_socket = None
        self.connected = False
        self.last_state = {}
        self.state_thread = None
        # Serialisiert Befehl+Antwort-Operationen auf dem geteilten Socket.
        # Ohne diesen Lock kollidieren parallele Befehle (z. B. mehrfaches
        # Takeoff-Tippen) → "[WinError 10035] nicht blockierender Socketvorgang".
        self._cmd_lock = threading.Lock()

    def _state_listener(self):
        """Hintergrund-Thread: empfängt Tello-Statusmeldungen auf Port 8890."""
        print(f"[INFO] State-Listener gestartet auf Port {self.STATE_PORT}")
        while self.connected and self.state_socket:
            try:
                data, _ = self.state_socket.recvfrom(1024)
                state_str = data.decode("utf-8").strip()
                # Tello-Format: "pitch:0;roll:0;yaw:0;vgx:0;vgy:0;vgz:0;..."
                new_state = {}
                for item in state_str.split(";"):
                    if ":" in item:
                        key, val = item.split(":")
                        new_state[key] = val
                self.last_state = new_state
            except Exception:
                if not self.connected:
                    break
                time.sleep(0.1)

    def _close_sockets(self):
        """Schließt offene Sockets, damit Port 8890 für einen neuen Versuch frei wird."""
        for sock_attr in ("socket", "state_socket"):
            sock = getattr(self, sock_attr)
            if sock:
                try:
                    sock.close()
                except Exception:
                    pass
                setattr(self, sock_attr, None)

    def connect(self, ip_address: str) -> bool:
        try:
            # Reste eines vorherigen (fehlgeschlagenen) Versuchs aufräumen,
            # sonst schlägt das erneute Binden von Port 8890 fehl.
            self.connected = False
            self._close_sockets()

            self.ip_address = ip_address
            print(f"[INFO] Verbinde mit Drohne {ip_address}:{self.DRONE_PORT}")

            self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.socket.settimeout(self.HANDSHAKE_TIMEOUT)

            self.state_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.state_socket.bind(("", self.STATE_PORT))

            for attempt in range(1, 4):
                self.socket.sendto(b"command", (ip_address, self.DRONE_PORT))
                try:
                    response, _ = self.socket.recvfrom(1024)
                except socket.timeout:
                    print(f"[WARN] Keine Antwort (Versuch {attempt}/3)")
                    continue

                if response.decode("utf-8", errors="replace").strip() == "ok":
                    print(f"[OK] Verbindung zu {ip_address} bestätigt")
                    self.socket.settimeout(self.CONNECTION_TIMEOUT)
                    self.connected = True
                    self.state_thread = threading.Thread(
                        target=self._state_listener, daemon=True
                    )
                    self.state_thread.start()
                    return True

                # Veraltete/fremde Antwort (z.B. von einem früheren Befehl) –
                # ignorieren und Handshake erneut versuchen.
                print(f"[WARN] Unerwartete Antwort (Versuch {attempt}/3): {response}")

            print("[ERROR] Verbindung fehlgeschlagen: keine gültige Antwort der Drohne")
            self._close_sockets()
            return False
        except Exception as e:
            print(f"[ERROR] Verbindung fehlgeschlagen: {e}")
            self.connected = False
            self._close_sockets()
            return False

    def send_command(self, command: str):
        """Sendet einen Befehl ohne auf eine Antwort zu warten."""
        if self.connected and self.socket:
            self.socket.sendto(command.encode("utf-8"), (self.ip_address, self.DRONE_PORT))

    def set_ledm(self, led_string: str):
        """Zeigt ein Muster auf der 8x8-LED-Matrix (Tello Talent).

        Wichtig: Das Erweiterungskommando muss mit GROSSEM 'EXT' gesendet werden,
        sonst ignoriert die Tello-Talent-Firmware den Matrix-Befehl.
        led_string: Pixel als String aus '0' (aus), 'r' (rot), 'b' (blau), 'p' (lila).
        """
        if self.connected and self.socket:
            message = f"EXT mled g {led_string}"
            self.socket.sendto(message.encode("utf-8"), (self.ip_address, self.DRONE_PORT))
            print(f"[MLED] {message}")

    def send_command_with_response(self, command: str, timeout=None) -> str:
        """
        Sendet einen Befehl und wartet auf die Antwort der Drohne ("ok" / "error").

        Nutzt select() statt den Blockier-Modus des Sockets umzuschalten — so
        kann es auch bei parallelen Aufrufen nicht mehr zu WinError 10035 kommen.
        Der Lock serialisiert konkurrierende Befehle; fire-and-forget RC-Befehle
        (send_command) bleiben absichtlich ungesperrt, damit der Ring-/RC-Takt
        nicht hinter einem langen 'land' wartet.
        """
        if not (self.connected and self.socket):
            return "N/A"
        timeout = timeout if timeout is not None else self.CONNECTION_TIMEOUT
        sock = self.socket
        with self._cmd_lock:
            try:
                # Veraltete Antworten verwerfen (ohne Moduswechsel des Sockets)
                while select.select([sock], [], [], 0)[0]:
                    try:
                        sock.recvfrom(1024)
                    except OSError:
                        break

                sock.sendto(command.encode("utf-8"), (self.ip_address, self.DRONE_PORT))

                # Auf Antwort warten — select liefert das Timeout, recvfrom
                # kehrt danach sofort zurück (kein Blockieren).
                if select.select([sock], [], [], timeout)[0]:
                    response, _ = sock.recvfrom(1024)
                    return response.decode("utf-8", errors="replace").strip()
                print(f"[WARN] Keine Antwort auf '{command}' (Timeout {timeout}s)")
                return "N/A"
            except Exception as e:
                print(f"[ERROR] Befehl '{command}' fehlgeschlagen: {e}")
                return "N/A"

    def disconnect(self):
        self.connected = False
        self._close_sockets()
