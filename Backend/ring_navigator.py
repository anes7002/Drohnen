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
    LOST_TOLERANCE: int = 8      # Frames (~0.8 s), die ein verlorener Ring überbrückt wird
    APPROACH_RADIUS: int = 90    # ring radius (px) at which we switch to PASSING
    COMMIT_FACTOR: float = 0.6   # Ring nah verloren (>= 60 % vom Pass-Radius) → blind durch
    FORWARD_MAX: int = 40        # max forward speed during approach
    FORWARD_MIN: int = 20        # min forward speed when nearly at the ring
    SEARCH_YAW: int = 25         # yaw speed while searching
    PASS_SPEED: int = 40         # forward speed while passing through
    PASS_DURATION: float = 2.5   # seconds to fly forward through the ring
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
            self._ring = ring_data

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
            time.sleep(0.1)

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

    def _step(self, ring: tuple | None) -> tuple:
        cx_frame = self.fw // 2
        cy_frame = self.fh // 2

        # ── SEARCHING ────────────────────────────────────────────────────────
        if self.state == RingState.SEARCHING:
            if ring is None:
                self._detection_streak = 0
                return (0, 0, 0, self.SEARCH_YAW)  # Drehen bis Ring gefunden
            # Ring gesehen — erst nach 4 stabilen Frames (≈ 0.4 s) wechseln
            self._detection_streak += 1
            if self._detection_streak >= 4:
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
                self._last_ring = None
                self.state = RingState.SEARCHING
                return (0, 0, 0, self.SEARCH_YAW)
            ring = self._last_ring  # weiter mit letzter bekannter Position
            if ring is None:
                self.state = RingState.SEARCHING
                return (0, 0, 0, self.SEARCH_YAW)
        else:
            self._lost_count = 0
            self._last_ring = ring

        # ── ALIGNING ─────────────────────────────────────────────────────────
        if self.state == RingState.ALIGNING:
            cx, cy, _radius = ring
            err_x = cx - cx_frame   # positive = ring is right of center
            err_y = cy - cy_frame   # positive = ring is below center (image coords)

            # Reine Zentrierung — NICHT vorwärts (sonst driftet sie beim Ausrichten weg)
            a = self._clamp(err_x * self.KP_LATERAL, -40, 40)
            c = self._clamp(-err_y * self.KP_VERTICAL, -40, 40)  # invert: ring below → fly down

            if abs(err_x) < self.ALIGN_THRESH and abs(err_y) < self.ALIGN_THRESH:
                self.state = RingState.APPROACHING

            return (a, 0, c, 0)

        # ── APPROACHING ───────────────────────────────────────────────────────
        if self.state == RingState.APPROACHING:
            cx, cy, radius = ring

            # Ring beim Heranfliegen verloren, aber wir waren schon nah dran →
            # er füllt das Bild / ist aus dem Sichtfeld gerutscht → blind durchfliegen.
            if self._lost_count > 0 and radius >= self.APPROACH_RADIUS * self.COMMIT_FACTOR:
                self.state = RingState.PASSING
                self._pass_start = time.time()
                self._reset_tracking()
                return (0, self.PASS_SPEED, 0, 0)

            err_x = cx - cx_frame
            err_y = cy - cy_frame

            # Zu weit daneben → zurück zum reinen Ausrichten. Vertikal enger als
            # horizontal, damit die Drohne NICHT über/unter den Ring fliegt.
            if abs(err_x) > self.ALIGN_THRESH * 2.5 or abs(err_y) > self.ALIGN_THRESH * 1.5:
                self.state = RingState.ALIGNING
                return (0, 0, 0, 0)

            # Ring groß genug → Durchflug
            if radius >= self.APPROACH_RADIUS:
                self.state = RingState.PASSING
                self._pass_start = time.time()
                self._reset_tracking()
                return (0, self.PASS_SPEED, 0, 0)

            # Zentrieren mit VOLLER Verstärkung — das Loch exakt anvisieren.
            a = self._clamp(err_x * self.KP_LATERAL, -35, 35)
            c = self._clamp(-err_y * self.KP_VERTICAL, -35, 35)

            # Nur vorwärts, wenn zentriert; je weiter von der Mitte weg, desto
            # langsamer. So fliegt die Drohne durch die MITTE statt über den Ring.
            centering_error = max(abs(err_x), abs(err_y))
            if centering_error > self.ALIGN_THRESH:
                forward = 0  # erst sauber auf die Mitte zentrieren
            else:
                progress = radius / self.APPROACH_RADIUS  # 0 fern → 1 nah
                forward = int(self.FORWARD_MAX - progress * (self.FORWARD_MAX - self.FORWARD_MIN))
                forward = int(forward * (1.0 - centering_error / self.ALIGN_THRESH))
            return (a, forward, c, 0)

        return (0, 0, 0, 0)
