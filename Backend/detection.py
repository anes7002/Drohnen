import cv2

# ---------------------------------------------------------------------------
# Initialisierung der Erkennungsmodelle
# ---------------------------------------------------------------------------

# HOG-Deskriptor für Vollkörper-Personenerkennung (in OpenCV eingebaut)
_hog = cv2.HOGDescriptor()
_hog.setSVMDetector(cv2.HOGDescriptor_getDefaultPeopleDetector())

# Haar-Cascade für frontale Gesichtserkennung (in OpenCV eingebaut)
_face_cascade = cv2.CascadeClassifier(
    cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
)

# Farben pro Erkennungsklasse (BGR)
_COLORS = {
    "Person":  (0, 255,   0),   # Grün
    "Gesicht": (0, 120, 255),   # Orange
}

# ---------------------------------------------------------------------------
# Erkennungs-Zustand
# ---------------------------------------------------------------------------

enabled = False
boxes: list = []          # Letzte Erkennungsergebnisse (werden zwischen Frames wiederverwendet)
frame_count = 0
DETECT_EVERY_N = 3        # Nur jeden 3. Frame neu berechnen


# ---------------------------------------------------------------------------
# Erkennungs-Logik
# ---------------------------------------------------------------------------

def detect(frame) -> list:
    """
    Erkennt Personen (HOG) und Gesichter (Haar) auf einem auf 320×240 skalierten Frame.
    Gibt eine Liste von (x, y, w, h, label)-Tupeln zurück.
    """
    h, w = frame.shape[:2]
    scale_w, scale_h = w / 320, h / 240
    small = cv2.resize(frame, (320, 240))
    gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)

    results = []

    person_boxes, _ = _hog.detectMultiScale(
        small, winStride=(8, 8), padding=(4, 4), scale=1.05
    )
    for (x, y, bw, bh) in person_boxes:
        results.append((
            int(x * scale_w), int(y * scale_h),
            int(bw * scale_w), int(bh * scale_h),
            "Person",
        ))

    face_boxes = _face_cascade.detectMultiScale(
        gray, scaleFactor=1.1, minNeighbors=5, minSize=(20, 20)
    )
    for (x, y, bw, bh) in face_boxes:
        results.append((
            int(x * scale_w), int(y * scale_h),
            int(bw * scale_w), int(bh * scale_h),
            "Gesicht",
        ))

    return results


def draw(frame, detection_boxes: list) -> None:
    """Zeichnet Bounding-Boxes und Labels direkt in den Frame (in-place)."""
    for (x, y, w, h, label) in detection_boxes:
        color = _COLORS.get(label, (255, 255, 0))
        cv2.rectangle(frame, (x, y), (x + w, y + h), color, 2)
        cv2.putText(
            frame, label, (x, max(y - 6, 12)),
            cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 2, cv2.LINE_AA,
        )
