# Drohnen

Projekt mit Flutter Frontend und Python Backend.

## Setup nach dem Klonen

### Backend (Python)

1. Navigiere ins Backend-Verzeichnis:
   ```bash
   cd Backend
   ```

2. Erstelle eine virtuelle Umgebung:
   ```bash
   python -m venv .venv
   ```

3. Aktiviere die virtuelle Umgebung:
   - **Windows PowerShell:**
     ```powershell
     .venv\Scripts\Activate.ps1
     ```
   - **Windows CMD:**
     ```cmd
     .venv\Scripts\activate.bat
     ```
   - **Linux/Mac:**
     ```bash
     source .venv/bin/activate
     ```

4. Installiere die Python-Abhängigkeiten:
   ```bash
   pip install djitellopy fastapi uvicorn
   ```

### Frontend (Flutter)

1. Navigiere ins Frontend-Verzeichnis:
   ```bash
   cd Frontend
   ```

2. Installiere die Flutter-Abhängigkeiten:
   ```bash
   flutter pub get
   ```

3. Starte die Anwendung:
   ```bash
   flutter run
   ```

## Entwicklung

- **Backend starten:** Im Backend-Verzeichnis mit aktivierter venv
- **Flutter Hot Reload:** Automatisch aktiv beim `flutter run`

## Benötigte Software

- Python 3.8 oder höher
- Flutter SDK
- Git