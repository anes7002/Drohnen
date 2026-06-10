from __future__ import annotations

import threading
import time
from enum import Enum


class RingState(Enum):
    IDLE = "idle"
    SEARCHING = "searching"
    ALIGNING = "aligning"
    APPROACHING = "approaching"
    PASSING = "passing"


class RingNavigator:
    """
    Autonomous ring-flight state machine.

    States:
      SEARCHING  — slowly rotates until a ring appears in the frame.
      ALIGNING   — centers the ring in the frame (lateral + vertical correction).
      APPROACHING — ring is centered, drone flies toward it while maintaining alignment.
      PASSING    — ring fills enough of the frame; drone flies straight through at full speed.
      After PASSING the state returns to SEARCHING (to look for the next ring).

    RC mapping (Tello EDU):
      a = left/right  (-100 left … +100 right)
      b = back/forward (-100 back … +100 forward)
      c = down/up     (-100 down … +100 up)
      d = yaw left/right (-100 ccw … +100 cw)
    """

    # ── Tunable parameters ────────────────────────────────────────────────────
    KP_LATERAL: float = 0.25     # proportional gain: lateral (left/right) correction
    KP_VERTICAL: float = 0.25    # proportional gain: vertical (up/down) correction
    ALIGN_THRESH: int = 60       # pixel error below which the ring is "centered"
    # Die Tello-Frontkamera ist ~10° nach UNTEN geneigt. Ring in der Bildmitte
    # bedeutet daher: Drohne hängt ÜBER dem Ring → sie fliegt oben drüber.
    # Der vertikale Zielpunkt muss deshalb ÜBER der Bildmitte liegen
    # (≈ f·tan(10°) ≈ 110 px bei 960×720).
    TARGET_OFFSET_Y: int = 100   # px: Ring wird so weit ÜBER der Bildmitte gehalten
    # Beim Vorwärtsflug nickt die Drohne nach vorn → Kamera zeigt noch weiter
    # nach unten → Ring wandert im Bild nach oben → Regler würde steigen.
    # Ausgleich: Zielpunkt pro Einheit Vorwärtsgeschwindigkeit weiter anheben.
    PITCH_COMP: float = 0.5      # px Ziel-Anhebung pro Einheit Vorwärts-Speed
    LOST_TOLERANCE: int = 16     # Regel-Ticks (~0.8 s bei 20 Hz), die ein verlorener Ring überbrückt wird
    APPROACH_RADIUS: int = 90    # ring radius (px) at which we switch to PASSING
    COMMIT_FACTOR: float = 0.6   # Ring nah verloren (>= 60 % vom Pass-Radius) → blind durch
    FORWARD_MAX: int = 40        # max forward speed during approach
    FORWARD_MIN: int = 20        # min forward speed when nearly at the ring
    SEARCH_YAW: int = 25         # yaw speed while searching
    PASS_SPEED: int = 40         # forward speed while passing through
    PASS_DURATION: float = 2.5   # seconds to fly forward through the ring
    # Anti-Stehenbleiben: Ist der Ring nah (>= APPROACH_RADIUS), darf maximal so
    # lange nachzentriert werden — danach wird der Durchflug erzwungen. Sonst
    # hängt die Drohne bei leichtem Zittern ewig vor dem Ring.
    NEAR_COMMIT_TIMEOUT: float = 1.2
    # Glättung der Ringposition: Einzelbild-Detektionen zittern (Rauschen,
    # H.264-Artefakte). Ein exponentieller Filter + Ausreißer-Verwurf macht
    # die Regelung ruhig und das Anvisieren der Ringmitte präzise.
    SMOOTH_ALPHA: float = 0.5    # Gewicht der NEUEN Messung (1.0 = keine Glättung)
    JUMP_REJECT_PX: int = 220    # Positionssprung > x px = Ausreißer (max. 2 in Folge verwerfen)
    # ─────────────────────────────────────────────────────────────────────────

    def __init__(self, control, frame_width: int = 960, frame_height: int = 720):
        self.control = control
        self.fw = frame_width
        self.fh = frame_height

        self.state = RingState.IDLE
        self._ring: tuple | None = None
        self._lock = threading.Lock()
        self._running = False
        self._thread: threading.Thread | None = None
        self._pass_start: float = 0.0
        self._detection_streak: int = 0  # Wie viele Frames der Ring schon stabil sichtbar ist
        self._lost_count: int = 0        # Wie viele Frames der Ring in Folge fehlt
        self._last_ring: tuple | None = None  # Letzte bekannte Ring-Position (zum Überbrücken)
        self._last_forward: int = 0      # Zuletzt gesendeter Vorwärts-Speed (für Nick-Ausgleich)
        self._smoothed: tuple | None = None   # Geglättete Ringposition (EMA)
        self._outlier_count: int = 0     # Verworfene Ausreißer in Folge
        self._near_since: float | None = None  # Seit wann der Ring "nah" ist (Anti-Stall)

        # Public status dict — read by the /ring/status endpoint.
        # Written by the background thread; read by the async event loop.
        # Python's GIL makes simple dict reads safe without an explicit lock.
        self.status: dict = {"state": "idle", "ring_detected": False}

    # ── Public API ────────────────────────────────────────────────────────────

    def set_frame_size(self, width: int, height: int) -> None:
        """Update expected frame dimensions (call after the first video frame arrives)."""
        self.fw = width
        self.fh = height

    def start(self) -> None:
        with self._lock:
            if self._running:
                return
            self._running = True
            self.state = RingState.SEARCHING
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        with self._lock:
            self._running = False
        self.state = RingState.IDLE
        self.status = {"state": "idle", "ring_detected": False}
        if self.control:
            self.control.send_rc(0, 0, 0, 0)

    def update_ring(self, ring_data: tuple | None) -> None:
        """Feed the latest detection result from the video pipeline."""
        with self._lock:
            self._ring = self._smooth(ring_data)

    def _smooth(self, ring: tuple | None) -> tuple | None:
        """
        Exponentielle Glättung der Ringposition + Ausreißer-Verwurf.

        - Erste Messung (oder während der Suche): direkt übernehmen.
        - Springt die Position um mehr als JUMP_REJECT_PX, wird die Messung
          bis zu 2× verworfen (Fehl-Detektion). Bleibt der Sprung, ist es
          eine echte Bewegung → neue Position übernehmen.
        """
        if ring is None:
            self._outlier_count = 0
            return None
        if self._smoothed is None or self.state == RingState.SEARCHING:
            self._smoothed = ring
            self._outlier_count = 0
            return self._smoothed

        dx = ring[0] - self._smoothed[0]
        dy = ring[1] - self._smoothed[1]
        if (dx * dx + dy * dy) ** 0.5 > self.JUMP_REJECT_PX:
            if self._outlier_count < 2:
                self._outlier_count += 1
                return self._smoothed  # Ausreißer ignorieren, alte Position halten
            self._smoothed = ring      # Sprung ist echt → übernehmen
            self._outlier_count = 0
            return self._smoothed

        self._outlier_count = 0
        a = self.SMOOTH_ALPHA
        self._smoothed = (
            a * ring[0] + (1 - a) * self._smoothed[0],
            a * ring[1] + (1 - a) * self._smoothed[1],
            a * ring[2] + (1 - a) * self._smoothed[2],
        )
        return self._smoothed

    def get_status(self) -> dict:
        return dict(self.status)

    # ── Internal loop ─────────────────────────────────────────────────────────

    def _run(self) -> None:
        prev_state = None
        while True:
            with self._lock:
                if not self._running:
                    break
                ring = self._ring

            a, b, c, d = self._step(ring)

            # Vor dem Senden erneut prüfen: Falls inzwischen gestoppt wurde (z. B.
            # Not-Aus), kein veraltetes RC-Kommando mehr an die Drohne schicken.
            with self._lock:
                if not self._running:
                    break
            if self.control:
                self.control.send_rc(a, b, c, d)

            # Debug: Zustandswechsel und Ring-Position ins Log schreiben
            if self.state.value != prev_state:
                ring_info = (
                    f"Ring@({int(ring[0])},{int(ring[1])}) r={int(ring[2])}"
                    if ring else "kein Ring"
                )
                print(f"[RING] {prev_state} → {self.state.value} | {ring_info} | rc={a,b,c,d}")
                prev_state = self.state.value

            self.status = {
                "state": self.state.value,
                "ring_detected": ring is not None,
                "cx": int(ring[0]) if ring else 0,
                "cy": int(ring[1]) if ring else 0,
                "radius": int(ring[2]) if ring else 0,
                "rc": [a, b, c, d],
            }
            time.sleep(0.05)  # 20 Hz Regeltakt — schnellere Reaktion auf Abweichungen

        if self.control:
            self.control.send_rc(0, 0, 0, 0)

    # ── State machine ─────────────────────────────────────────────────────────

    @staticmethod
    def _clamp(value: float, lo: int = -100, hi: int = 100) -> int:
        return max(lo, min(hi, int(value)))

    def _reset_tracking(self) -> None:
        """Setzt Erkennungs-Zähler zurück (bei Zustandswechsel zu PASSING/SEARCHING)."""
        self._detection_streak = 0
        self._lost_count = 0
        self._last_ring = None
        self._last_forward = 0
        self._smoothed = None
        self._outlier_count = 0
        self._near_since = None

    def _errors(self, ring: tuple) -> tuple[float, float]:
        """
        Pixel-Fehler zum ZIELPUNKT (nicht zur Bildmitte!).

        Vertikal liegt der Zielpunkt TARGET_OFFSET_Y über der Bildmitte
        (Kamera-Neigung) plus Nick-Ausgleich beim Vorwärtsflug. Nur so endet
        die Drohne auf Ring-Höhe statt darüber.
        """
        cx, cy, _ = ring
        target_y = (
            self.fh // 2
            - self.TARGET_OFFSET_Y
            - self.PITCH_COMP * self._last_forward
        )
        err_x = cx - self.fw // 2   # positiv = Ring rechts vom Ziel
        err_y = cy - target_y       # positiv = Ring unter dem Ziel → sinken
        return err_x, err_y

    def _step(self, ring: tuple | None) -> tuple:
        # ── SEARCHING ────────────────────────────────────────────────────────
        if self.state == RingState.SEARCHING:
            self._last_forward = 0
            if ring is None:
                # Einzelner Aussetzer während der Bestätigung verwirft den
                # Fortschritt nicht komplett — erst bei streak 0 weiterdrehen.
                self._detection_streak = max(0, self._detection_streak - 1)
                if self._detection_streak > 0:
                    return (0, 0, 0, 0)  # kurz warten, Ring war gerade noch da
                return (0, 0, 0, self.SEARCH_YAW)  # Drehen bis Ring gefunden
            # Ring gesehen — erst nach 6 stabilen Ticks (≈ 0.3 s bei 20 Hz) wechseln
            self._detection_streak += 1
            if self._detection_streak >= 6:
                self._detection_streak = 0
                self._lost_count = 0
                self._last_ring = ring
                self.state = RingState.ALIGNING
            return (0, 0, 0, 0)  # Stopp während der Bestätigung

        # ── PASSING ───────────────────────────────────────────────────────────
        # Rein zeitbasiert — ignoriert die Ring-Erkennung komplett (die Drohne ist
        # mitten im Durchflug, der Ring ist außerhalb des Sichtfelds). MUSS vor der
        # Ring-Verlust-Logik stehen, sonst bricht der Durchflug sofort ab.
        if self.state == RingState.PASSING:
            if time.time() - self._pass_start >= self.PASS_DURATION:
                self._reset_tracking()
                self.state = RingState.SEARCHING  # Nächsten Ring suchen
                return (0, 0, 0, 0)
            return (0, self.PASS_SPEED, 0, 0)

        # Ring-Verlust in ALIGNING/APPROACHING tolerieren: kurze Aussetzer
        # (Video-Rauschen) mit der letzten bekannten Position überbrücken.
        if ring is None:
            self._lost_count += 1
            if self._lost_count > self.LOST_TOLERANCE:
                # Ring wirklich weg → von vorne suchen
                self._reset_tracking()
                self.state = RingState.SEARCHING
                return (0, 0, 0, self.SEARCH_YAW)
            ring = self._last_ring  # weiter mit letzter bekannter Position
            if ring is None:
                self._reset_tracking()
                self.state = RingState.SEARCHING
                return (0, 0, 0, self.SEARCH_YAW)
        else:
            self._lost_count = 0
            self._last_ring = ring

        # ── ALIGNING ─────────────────────────────────────────────────────────
        if self.state == RingState.ALIGNING:
            self._last_forward = 0
            err_x, err_y = self._errors(ring)

            # Reine Zentrierung — NICHT vorwärts (sonst driftet sie beim Ausrichten weg)
            a = self._clamp(err_x * self.KP_LATERAL, -40, 40)
            c = self._clamp(-err_y * self.KP_VERTICAL, -40, 40)  # invert: ring below → fly down

            if abs(err_x) < self.ALIGN_THRESH and abs(err_y) < self.ALIGN_THRESH:
                self.state = RingState.APPROACHING

            return (a, 0, c, 0)

        # ── APPROACHING ───────────────────────────────────────────────────────
        if self.state == RingState.APPROACHING:
            radius = ring[2]

            # Ring beim Heranfliegen verloren, aber wir waren schon nah dran →
            # er füllt das Bild / ist aus dem Sichtfeld gerutscht → blind durchfliegen.
            if self._lost_count > 0 and radius >= self.APPROACH_RADIUS * self.COMMIT_FACTOR:
                self.state = RingState.PASSING
                self._pass_start = time.time()
                self._reset_tracking()
                return (0, self.PASS_SPEED, 0, 0)

            err_x, err_y = self._errors(ring)
            centering_error = max(abs(err_x), abs(err_y))

            # Zu weit daneben → zurück zum reinen Ausrichten. Vertikal enger als
            # horizontal, damit die Drohne NICHT über/unter den Ring fliegt.
            if abs(err_x) > self.ALIGN_THRESH * 2.5 or abs(err_y) > self.ALIGN_THRESH * 1.5:
                self._last_forward = 0
                self.state = RingState.ALIGNING
                return (0, 0, 0, 0)

            # Ring groß genug → Durchflug, sobald die Mitte sauber anvisiert ist.
            # Anti-Stall: Hängt die Drohne länger als NEAR_COMMIT_TIMEOUT vor dem
            # Ring (oder rutscht er gleich aus dem Bild), wird der Durchflug
            # erzwungen — lieber leicht außermittig durch als stehen bleiben.
            if radius >= self.APPROACH_RADIUS:
                if self._near_since is None:
                    self._near_since = time.time()
                commit = (
                    centering_error <= self.ALIGN_THRESH * 1.2
                    or radius >= self.APPROACH_RADIUS * 1.3
                    or time.time() - self._near_since > self.NEAR_COMMIT_TIMEOUT
                )
                if commit:
                    self.state = RingState.PASSING
                    self._pass_start = time.time()
                    self._reset_tracking()
                    return (0, self.PASS_SPEED, 0, 0)
                # Kurz nachzentrieren — aber langsam WEITER vorwärts, nie stehen
                a = self._clamp(err_x * self.KP_LATERAL, -35, 35)
                c = self._clamp(-err_y * self.KP_VERTICAL, -35, 35)
                self._last_forward = 10
                return (a, 10, c, 0)
            self._near_since = None

            # Zentrieren mit VOLLER Verstärkung — das Loch exakt anvisieren.
            a = self._clamp(err_x * self.KP_LATERAL, -35, 35)
            c = self._clamp(-err_y * self.KP_VERTICAL, -35, 35)

            # Vorwärts mit Mindesttempo: je weiter von der Mitte weg, desto
            # langsamer — aber nie ganz stehen bleiben, solange der Fehler nicht
            # massiv ist. Korrigiert wird WÄHREND des Fliegens.
            if centering_error > self.ALIGN_THRESH * 2:
                forward = 0  # sehr weit daneben → erst grob zentrieren
            else:
                progress = min(1.0, radius / self.APPROACH_RADIUS)  # 0 fern → 1 nah
                base = self.FORWARD_MAX - progress * (self.FORWARD_MAX - self.FORWARD_MIN)
                scale = max(0.35, 1.0 - centering_error / (self.ALIGN_THRESH * 2.0))
                forward = max(int(base * scale), 8)
            self._last_forward = forward
            return (a, forward, c, 0)

        return (0, 0, 0, 0)
