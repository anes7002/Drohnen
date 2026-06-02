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
    ALIGN_THRESH: int = 30       # pixel error below which the ring is "centered"
    APPROACH_RADIUS: int = 100   # ring radius (px) at which we switch to PASSING
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
        while True:
            with self._lock:
                if not self._running:
                    break
                ring = self._ring

            a, b, c, d = self._step(ring)
            if self.control:
                self.control.send_rc(a, b, c, d)

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

    def _step(self, ring: tuple | None) -> tuple:
        cx_frame = self.fw // 2
        cy_frame = self.fh // 2

        # ── SEARCHING ────────────────────────────────────────────────────────
        if self.state == RingState.SEARCHING:
            if ring is None:
                return (0, 0, 0, self.SEARCH_YAW)  # Rotate slowly to scan
            self.state = RingState.ALIGNING
            return (0, 0, 0, 0)  # Stop rotating — ring found

        # ── ALIGNING ─────────────────────────────────────────────────────────
        if self.state == RingState.ALIGNING:
            if ring is None:
                self.state = RingState.SEARCHING
                return (0, 0, 0, self.SEARCH_YAW)

            cx, cy, _radius = ring
            err_x = cx - cx_frame   # positive = ring is right of center
            err_y = cy - cy_frame   # positive = ring is below center (image coords)

            # Proportional correction (+ slow forward to keep closing in)
            a = self._clamp(err_x * self.KP_LATERAL, -40, 40)
            c = self._clamp(-err_y * self.KP_VERTICAL, -40, 40)  # invert: ring below → fly down

            if abs(err_x) < self.ALIGN_THRESH and abs(err_y) < self.ALIGN_THRESH:
                self.state = RingState.APPROACHING

            return (a, 15, c, 0)

        # ── APPROACHING ───────────────────────────────────────────────────────
        if self.state == RingState.APPROACHING:
            if ring is None:
                self.state = RingState.ALIGNING
                return (0, 0, 0, 0)

            cx, cy, radius = ring
            err_x = cx - cx_frame
            err_y = cy - cy_frame

            # Too far off center — re-align before continuing
            if abs(err_x) > self.ALIGN_THRESH * 2.5 or abs(err_y) > self.ALIGN_THRESH * 2.5:
                self.state = RingState.ALIGNING
                return (0, 0, 0, 0)

            # Ring large enough → transition to pass-through
            if radius >= self.APPROACH_RADIUS:
                self.state = RingState.PASSING
                self._pass_start = time.time()
                return (0, self.PASS_SPEED, 0, 0)

            # Slow down as we get closer (radius grows)
            progress = radius / self.APPROACH_RADIUS  # 0 (far) → 1 (close)
            forward = int(self.FORWARD_MAX - progress * (self.FORWARD_MAX - self.FORWARD_MIN))

            a = self._clamp(err_x * self.KP_LATERAL * 0.5, -30, 30)
            c = self._clamp(-err_y * self.KP_VERTICAL * 0.5, -30, 30)
            return (a, forward, c, 0)

        # ── PASSING ───────────────────────────────────────────────────────────
        if self.state == RingState.PASSING:
            elapsed = time.time() - self._pass_start
            if elapsed >= self.PASS_DURATION:
                self.state = RingState.SEARCHING  # Look for the next ring
                return (0, 0, 0, 0)
            return (0, self.PASS_SPEED, 0, 0)

        return (0, 0, 0, 0)
