from __future__ import annotations

import cv2
import numpy as np

# ─────────────────────────────────────────────────────────────────────────────
# Global state (read/written by server.py)
# ─────────────────────────────────────────────────────────────────────────────

enabled: bool = False
ring: tuple | None = None   # (cx, cy, radius_px) in original frame coords, or None
frame_count: int = 0
DETECT_EVERY_N: int = 2

# Rot in HSV liegt an zwei Stellen der Farbskala (Wraparound bei 0/180 Grad):
#   unterer Bereich: H=0..10   (reines Rot / leicht Orange-Rot)
#   oberer Bereich:  H=170..180 (reines Rot / leicht Violett-Rot)
# Beide Masken werden kombiniert → zuverlässige Rot-Erkennung.
_red_lower1 = np.array([0,   80, 80], dtype=np.uint8)
_red_upper1 = np.array([10, 255, 255], dtype=np.uint8)
_red_lower2 = np.array([170,  80, 80], dtype=np.uint8)
_red_upper2 = np.array([180, 255, 255], dtype=np.uint8)

# Einzelbereich für set_color() (falls Nicht-Rot-Farben konfiguriert werden)
_single_lower: np.ndarray | None = None
_single_upper: np.ndarray | None = None

_SCALE: float = 0.4        # Resize-Faktor für schnellere Verarbeitung
_MIN_AREA: int = 600        # Min. Konturenfläche auf dem skalierten Frame
_MIN_ASPECT: float = 0.35   # Min. Ellipsen-Aspektverhältnis — schräg angeflogene Ringe erlauben
_MIN_HOLE_RATIO: float = 0.04  # Loch muss mind. 4 % der Gesamtfläche sein (Ring hat Loch)


# ─────────────────────────────────────────────────────────────────────────────
# Farbkonfiguration
# ─────────────────────────────────────────────────────────────────────────────

def set_color(
    h_low: int, h_high: int,
    s_low: int = 80, s_high: int = 255,
    v_low: int = 80, v_high: int = 255,
) -> None:
    """
    Setzt einen einzelnen HSV-Bereich (für nicht-rote Ringe).
    Für Rot: set_color_red() aufrufen.
    """
    global _single_lower, _single_upper
    _single_lower = np.array([h_low, s_low, v_low], dtype=np.uint8)
    _single_upper = np.array([h_high, s_high, v_high], dtype=np.uint8)


def set_color_red(
    s_low: int = 80, v_low: int = 80,
) -> None:
    """Stellt den Standard-Rot-Doppelbereich wieder her."""
    global _red_lower1, _red_upper1, _red_lower2, _red_upper2, _single_lower, _single_upper
    _red_lower1 = np.array([0,   s_low, v_low], dtype=np.uint8)
    _red_upper1 = np.array([10,  255,   255],   dtype=np.uint8)
    _red_lower2 = np.array([170, s_low, v_low], dtype=np.uint8)
    _red_upper2 = np.array([180, 255,   255],   dtype=np.uint8)
    _single_lower = None
    _single_upper = None


def _build_mask(hsv) -> np.ndarray:
    """Erstellt die kombinierte Farbmaske (Rot-Doppelbereich oder Einzelbereich)."""
    if _single_lower is not None and _single_upper is not None:
        return cv2.inRange(hsv, _single_lower, _single_upper)
    # Standard: Rot (beide Bereiche vereinigen)
    mask1 = cv2.inRange(hsv, _red_lower1, _red_upper1)
    mask2 = cv2.inRange(hsv, _red_lower2, _red_upper2)
    return cv2.bitwise_or(mask1, mask2)


# ─────────────────────────────────────────────────────────────────────────────
# Erkennung
# ─────────────────────────────────────────────────────────────────────────────

def detect(frame) -> tuple | None:
    """
    Erkennt das größte ringförmige Objekt in der konfigurierten Farbe.

    Schlüsselidee: Ein Ring hat ein LOCH. Ein Mensch in roter Kleidung ist ein
    solider Fleck. Über die Kontur-Hierarchie (RETR_CCOMP) erkennen wir, ob eine
    rote Form innen ein echtes Loch hat — nur dann ist es ein Ring.

    Ablauf:
      1. Frame auf _SCALE verkleinern (Geschwindigkeit).
      2. HSV-Farb-Doppelmaske (Rot-Wraparound).
      3. Leichte morphologische Bereinigung (Loch NICHT zuschließen).
      4. Konturen MIT Hierarchie finden.
      5. Außenkonturen behalten, die ein ausreichend großes Loch (Kind-Kontur) haben.
      6. Nach Fläche, Rundheit und Loch-Größe filtern + bewerten.
    """
    h_orig, w_orig = frame.shape[:2]
    sw, sh = int(w_orig * _SCALE), int(h_orig * _SCALE)
    small = cv2.resize(frame, (sw, sh))

    hsv = cv2.cvtColor(small, cv2.COLOR_BGR2HSV)
    mask = _build_mask(hsv)

    # Rauschen entfernen, dann Lücken im Ringband kräftig schließen — nur ein
    # GESCHLOSSENES Band umschließt das Loch, das der Hole-Check verlangt.
    # Das große Loch in der Mitte ist viel größer als der Kernel und bleibt offen.
    kernel_small = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel_small)
    kernel_close = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel_close, iterations=2)

    contours, hierarchy = cv2.findContours(
        mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE
    )
    if hierarchy is None:
        return None
    hierarchy = hierarchy[0]  # Form: (N, 4) → [next, prev, first_child, parent]

    best: tuple | None = None
    best_score: float = 0.0

    for i, cnt in enumerate(contours):
        # Nur Außenkonturen (kein Elternteil) betrachten
        if hierarchy[i][3] != -1:
            continue

        area = cv2.contourArea(cnt)
        if area < _MIN_AREA or len(cnt) < 5:
            continue

        ellipse = cv2.fitEllipse(cnt)
        (cx, cy), (minor_ax, major_ax), _ = ellipse
        if major_ax == 0:
            continue

        aspect = minor_ax / major_ax  # 1.0 = Kreis, 0.0 = Linie
        if aspect < _MIN_ASPECT:
            continue  # zu schräg / länglich — kein Ring

        # Größtes Loch (Kind-Kontur) dieser Außenkontur suchen
        hole_area = 0.0
        child = hierarchy[i][2]
        while child != -1:
            hole_area = max(hole_area, cv2.contourArea(contours[child]))
            child = hierarchy[child][0]  # nächstes Geschwister-Loch

        # Ein echter Ring hat ein deutliches Loch (Loch/Gesamtfläche groß genug)
        if hole_area / area < _MIN_HOLE_RATIO:
            continue

        # größer + runder + größeres Loch = besser
        score = area * aspect * (hole_area / area)
        if score > best_score:
            best_score = score
            radius_px = (major_ax + minor_ax) / 4
            best = (cx / _SCALE, cy / _SCALE, radius_px / _SCALE)

    return best


# ─────────────────────────────────────────────────────────────────────────────
# Overlay-Zeichnung
# ─────────────────────────────────────────────────────────────────────────────

def draw(frame, ring_data: tuple | None) -> None:
    """Zeichnet Ring-Overlay direkt in den Frame (in-place)."""
    if ring_data is None:
        return
    cx, cy, radius = int(ring_data[0]), int(ring_data[1]), int(ring_data[2])
    red    = (0, 0, 220)
    yellow = (0, 255, 255)
    cv2.circle(frame, (cx, cy), radius, red, 3)
    cv2.circle(frame, (cx, cy), 5, yellow, -1)
    cv2.line(frame, (cx - 15, cy), (cx + 15, cy), yellow, 2)
    cv2.line(frame, (cx, cy - 15), (cx, cy + 15), yellow, 2)
    cv2.putText(
        frame, f"Ring r={radius:.0f}px",
        (cx - 50, max(cy - radius - 10, 15)),
        cv2.FONT_HERSHEY_SIMPLEX, 0.55, red, 2, cv2.LINE_AA,
    )
