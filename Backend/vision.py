import cv2
import numpy as np
import time
import os
from datetime import datetime

class VisionManager:
    def __init__(self):
        self.is_recording = False
        self.ai_enabled = False
        self.video_writer = None
        
        # Lade vortrainiertes Modell für Objekterkennung (MobileNet-SSD)
        # Hinweis: Du benötigst die Dateien 'deploy.prototxt' und 'res10_300x300_ssd_iter_140000.caffemodel'
        # Alternativ nutzen wir hier den einfachen HOG-Descriptor für Menschenerkennung (Standard in OpenCV)
        self.hog = cv2.HOGDescriptor()
        self.hog.setSVMDetector(cv2.HOGDescriptor_getDefaultPeopleDetector())

    def toggle_ai(self, state: bool):
        self.ai_enabled = state

    def start_recording(self, width, height):
        if not self.is_recording:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"drone_record_{timestamp}.avi"
            fourcc = cv2.VideoWriter_fourcc(*'XVID')
            self.video_writer = cv2.VideoWriter(filename, fourcc, 20.0, (width, height))
            self.is_recording = True
            print(f"[INFO] Aufnahme gestartet: {filename}")

    def stop_recording(self):
        self.is_recording = False
        if self.video_writer:
            self.video_writer.release()
            self.video_writer = None
            print("[INFO] Aufnahme beendet.")

    def process_frame(self, frame):
        """Bearbeitet das Bild: Erkennt Objekte und zeichnet Markierungen."""
        if frame is None:
            return None

        processed_frame = frame.copy()

        # 5.4 & 5.5: Objekterkennung (Menschen)
        if self.ai_enabled:
            # Bild verkleinern für schnellere Erkennung
            gray = cv2.cvtColor(processed_frame, cv2.COLOR_BGR2GRAY)
            boxes, weights = self.hog.detectMultiScale(processed_frame, winStride=(8,8))
            
            for (x, y, w, h) in boxes:
                # Zeichne Rahmen
                cv2.rectangle(processed_frame, (x, y), (x + w, y + h), (0, 255, 0), 2)
                # Beschriftung
                cv2.putText(processed_frame, "Mensch", (x, y - 10), 
                            cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)

        # 5.2: In Datei speichern
        if self.is_recording and self.video_writer:
            self.video_writer.write(processed_frame)

        return processed_frame