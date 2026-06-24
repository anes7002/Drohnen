# Drohnen – RoboMaster TT Control

Steuerungssystem für die **DJI Tello Talent / RoboMaster TT** Drohne, bestehend aus
einem Python-Backend (FastAPI) und einem Flutter-Frontend. Das System erlaubt Live-Steuerung
per Joystick, Live-Videostream, KI-gestützte Objekterkennung, autonomen Ring-Flug,
Steuerung der LED-Matrix, Videoaufnahmen sowie das Aufzeichnen und Abspielen von Flugkursen.

## Inhaltsverzeichnis

- [Architektur](#architektur)
- [Funktionen](#funktionen)
- [Voraussetzungen](#voraussetzungen)
- [Setup](#setup)
  - [Datenbank (PostgreSQL via Docker)](#datenbank-postgresql-via-docker)
  - [Backend (Python / FastAPI)](#backend-python--fastapi)
  - [Frontend (Flutter)](#frontend-flutter)
- [Verwendung](#verwendung)
- [API-Übersicht](#api-übersicht)
- [Projektstruktur](#projektstruktur)
- [Fehlerbehebung](#fehlerbehebung)

## Architektur

```
┌──────────────────┐        HTTP / WebSocket        ┌──────────────────┐        UDP (Tello SDK)        ┌─────────────┐
│  Flutter Frontend │ ◄────────────────────────────► │  FastAPI Backend  │ ◄───────────────────────────► │  Drohne (TT) │
│  (Joystick, UI,   │      Port 8000 (REST + WS)     │  (server.py)      │   Port 8889 / 8890 / 11111    │             │
│   Videostream)    │                                 └────────┬─────────┘                               └─────────────┘
└──────────────────┘                                          │ psycopg2
                                                      ┌────────▼─────────┐
                                                      │  PostgreSQL (DB)  │
                                                      │   Port 5432       │
                                                      └──────────────────┘
```

- **Frontend** kommuniziert ausschließlich über HTTP/WebSocket mit dem Backend.
- **Backend** spricht die Drohne direkt über das Tello-UDP-Protokoll an (rohe Sockets, kein
  externes SDK) und persistiert Drohnen, Flugkurse und Aufnahmen in PostgreSQL.

## Funktionen

- **Live-Steuerung** – Echtzeit-RC-Steuerung über zwei virtuelle Joysticks (WebSocket `/rc`).
- **Live-Videostream** – H.264-Stream der Drohnenkamera, ausgeliefert über WebSocket `/video`.
- **KI-Objekterkennung** – Personen- (HOG) und Gesichtserkennung (Haar-Cascade) via OpenCV.
- **Autonomer Ring-Flug** – Erkennung roter Ringe und automatisches Anfliegen/Durchfliegen
  (Zustandsautomat: searching → aligning → approaching → passing).
- **LED-Matrix** – Anzeige von Mustern und scrollendem Text auf der 8×8-LED-Matrix.
- **Videoaufnahmen** – Start/Stopp von Aufnahmen, Speichern und erneutes Abspielen.
- **Flugkurse** – Aufzeichnen einer Befehlssequenz und automatisches Wiederabspielen.
- **Telemetrie** – Live-Anzeige von Akku, Höhe, Geschwindigkeit, Flugzeit und Temperatur.
- **Drohnen-Verwaltung** – Mehrere Drohnen per IP anlegen, auswählen und löschen.

## Voraussetzungen

- **Python** 3.8 (Robomaster unterstützt keine höhere Versionen)
- **Flutter SDK** 3.11 oder höher (Dart SDK ^3.11.0)
- **Docker** & Docker Compose (für die PostgreSQL-Datenbank)
- **Git**
- Eine **DJI Tello Talent / RoboMaster TT** Drohne im selben Netzwerk
  (Direkt-WLAN der Drohne oder gemeinsames WLAN)

## Setup

> Reihenfolge: Erst die Datenbank starten, dann das Backend, zuletzt das Frontend.

### Datenbank (PostgreSQL via Docker)

Die Datenbank wird per Docker Compose bereitgestellt und initialisiert sich beim ersten Start
automatisch über `init.sql`.

```bash
cd Backend/db
docker compose up -d
```

Standard-Zugangsdaten (siehe `Backend/db/docker-compose.yml`):

| Parameter | Wert       |
|-----------|------------|
| Host      | `localhost`|
| Port      | `5432`     |
| Benutzer  | `user`     |
| Passwort  | `password` |

Angelegte Tabellen: `drohne`, `flugkurs`, `video`, `recordings`.

### Backend (Python / FastAPI)

1. Ins Backend-Verzeichnis wechseln:
   ```bash
   cd Backend
   ```

2. Virtuelle Umgebung erstellen:
   ```bash
   python -m venv .venv
   ```

3. Virtuelle Umgebung aktivieren:
   - **Linux/Mac:**
     ```bash
     source .venv/bin/activate
     ```
   - **Windows PowerShell:**
     ```powershell
     .venv\Scripts\Activate.ps1
     ```
   - **Windows CMD:**
     ```cmd
     .venv\Scripts\activate.bat
     ```

4. Abhängigkeiten installieren:
   ```bash
   pip install -r requirements.txt
   ```

5. Server starten:
   ```bash
   python main.py
   ```
   Das Backend läuft anschließend unter `http://0.0.0.0:8000` (mit aktiviertem Auto-Reload).
   Alternativ: `uvicorn server:app --host 0.0.0.0 --port 8000 --reload`.

### Frontend (Flutter)

1. Ins Frontend-Verzeichnis wechseln:
   ```bash
   cd Frontend/drohnen_fronted
   ```

2. Abhängigkeiten installieren:
   ```bash
   flutter pub get
   ```

3. Anwendung starten:
   ```bash
   flutter run
   ```
   Die App startet im Querformat. Beim Start wird die IP-Adresse des Backends bzw. der Drohne
   abgefragt (`IpEntryScreen`).

## Verwendung

1. Drohne einschalten und mit dem WLAN verbinden, in dem auch der Backend-Rechner ist.
2. Datenbank und Backend wie oben starten.
3. Frontend starten und im Startbildschirm die IP-Adresse eingeben.
4. Über das Dashboard:
   - Drohne verbinden, starten (Takeoff) und landen
   - Per Joystick steuern und den Live-Videostream beobachten
   - KI-Erkennung oder Ring-Modus aktivieren
   - LED-Matrix-Muster/Text setzen
   - Aufnahmen starten/stoppen und Flugkurse aufzeichnen/abspielen

## API-Übersicht

Das Backend stellt eine REST-API sowie zwei WebSocket-Endpunkte bereit (Auszug):

| Methode | Endpunkt                          | Beschreibung                                  |
|---------|-----------------------------------|-----------------------------------------------|
| POST    | `/connect`                        | Verbindung zur Drohne aufbauen                |
| POST    | `/disconnect`                     | Verbindung trennen                            |
| POST    | `/command`                        | Einzelnen Steuerbefehl senden                 |
| GET     | `/telemetry`                      | Aktuelle Telemetriedaten abrufen              |
| POST    | `/led`                            | Status-LED setzen                             |
| POST    | `/mled` / `/mled/text`            | LED-Matrix-Muster bzw. scrollender Text       |
| POST    | `/detection/toggle`               | KI-Objekterkennung ein-/ausschalten           |
| GET     | `/detection/status`               | Status der Objekterkennung                    |
| POST    | `/ring/toggle` / `/ring/config`   | Ring-Flug umschalten / konfigurieren          |
| GET     | `/ring/status`                    | Status des Ring-Flugs                         |
| GET/POST/DELETE | `/drohnen` (`/{id}`)      | Drohnen verwalten                             |
| GET/POST/DELETE | `/flugkurs` (`/{id}`)     | Flugkurse verwalten                           |
| POST    | `/flugkurs/{id}/execute`          | Flugkurs abspielen                            |
| POST    | `/recordings/start` / `/stop`     | Videoaufnahme starten/stoppen                 |
| GET     | `/recordings` / `/{id}/video`     | Aufnahmen auflisten / Video abrufen           |
| WS      | `/video`                          | Live-Videostream                              |
| WS      | `/rc`                             | Echtzeit-RC-Steuerung                         |

Vollständige Definitionen siehe `Backend/server.py`.

## Projektstruktur

```
Drohnen/
├── Backend/                      # Python / FastAPI Backend
│   ├── main.py                   # Einstiegspunkt (startet uvicorn)
│   ├── server.py                 # FastAPI-App: REST- & WebSocket-Endpunkte
│   ├── dronemanager.py           # Verwaltung mehrerer Drohnen
│   ├── detection.py              # Personen-/Gesichtserkennung (OpenCV)
│   ├── ring_detection.py         # Erkennung roter Ringe
│   ├── ring_navigator.py         # Zustandsautomat für autonomen Ring-Flug
│   ├── telemetry_viewer.py       # Telemetrie-Hilfswerkzeug
│   ├── requirements.txt          # Python-Abhängigkeiten
│   ├── recordings/               # Gespeicherte Videoaufnahmen
│   ├── drone/                    # Drohnen-Kommunikation (Tello-UDP)
│   │   ├── connection.py         # UDP-Verbindung & State-Listener
│   │   ├── controls.py           # Steuerbefehle (takeoff, rc, ...)
│   │   ├── telemetry.py          # Telemetrie-Auswertung
│   │   └── status_led.py         # Status-LED-Steuerung
│   └── db/
│       ├── docker-compose.yml    # PostgreSQL-Container
│       └── init.sql              # Schema-Initialisierung
│
└── Frontend/drohnen_fronted/     # Flutter Frontend
    ├── pubspec.yaml              # Dart/Flutter-Abhängigkeiten
    └── lib/
        ├── main.dart             # App-Einstiegspunkt
        ├── video_stream_view.dart
        ├── screens/              # IP-Eingabe & Dashboard
        ├── models/               # Datenmodelle (Flugkurs, Recording, ...)
        └── widgets/              # UI-Komponenten (Joystick, LED-Matrix, Dialoge)
```

## Fehlerbehebung

- **Takeoff schlägt fehl** – Die Tello startet bei Überhitzung (~90 °C+) oder niedrigem
  Akku nicht. Drohne abkühlen lassen bzw. laden. Akku-/Temperaturwerte werden im
  Backend-Log ausgegeben.
- **Keine Verbindung zur Drohne** – Sicherstellen, dass Rechner und Drohne im selben
  Netzwerk sind und die Ports 8889 (Befehle), 8890 (State) und 11111 (Video) erreichbar sind.
- **Datenbankfehler** – Prüfen, ob der Docker-Container `drone_db` läuft
  (`docker compose ps` im Verzeichnis `Backend/db`).
- **Frontend findet Backend nicht** – Im IP-Eingabe-Bildschirm die korrekte
  Backend-IP eingeben; Backend muss auf `0.0.0.0:8000` erreichbar sein.
