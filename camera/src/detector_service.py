"""
Aperture camera detection service (Week 6, Task 6.1).

This is the piece the other apps plug into. It runs the same efficientdet_lite0
model and thresholds as test_detect.py, but instead of drawing a window and
writing a CSV it prints ONE JSON line per camera frame to stdout:

    {"phone_detected": true, "phone_confidence": 0.31, "person_count": 1,
     "latency_ms": 17.4, "timestamp": "2026-10-16T01:30:12.512"}

That line is the whole contract. The desktop client (and later the mobile
bridge) only has to read these five values and decide what to do with them
(blur, lock, warn). The detector doesn't need to know anything about the apps.

Usage:
    python detector_service.py                 # stream from webcam 0
    python detector_service.py --camera 1      # pick a different webcam
    python detector_service.py --preview       # also show the camera feed with boxes (testing/demos)
    python detector_service.py --image x.jpg   # one-shot check on a photo (for testing)

Anything that isn't detection output (startup info, errors) goes to stderr so
the stdout stream stays clean, one JSON object per line.
"""
import argparse
import json
import os
import sys
import time
from datetime import datetime

import cv2
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

# Same values as test_detect.py so the service behaves exactly like the harness
# that was tested in Weeks 4-5.
SCORE_THRESHOLD = 0.15          # phone: kept low on purpose, a missed phone can leak content
PERSON_SCORE_THRESHOLD = 0.5    # person: stricter, weak person false positives score low

# Resolve the model path relative to this file so the service works no matter
# what folder the desktop client launches it from.
HERE = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(HERE, '..', 'models', 'efficientdet_lite0.tflite')


class CameraDetector:
    """Wraps the MediaPipe detector and turns raw detections into the 5-value result."""

    def __init__(self, model_path=MODEL_PATH):
        base_options = python.BaseOptions(model_asset_path=model_path)
        options = vision.ObjectDetectorOptions(base_options=base_options,
                                               score_threshold=SCORE_THRESHOLD,
                                               category_allowlist=['cell phone', 'person'])
        self.detector = vision.ObjectDetector.create_from_options(options)
        self.last_boxes = []

    def check(self, frame_bgr):
        """Run detection on one BGR frame (what OpenCV gives you) and return the result dict."""
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB))

        # Same as the harness: the timer only covers detector.detect().
        start = time.time()
        result = self.detector.detect(mp_image)
        latency_ms = (time.time() - start) * 1000

        phone_dets = [d for d in result.detections if d.categories[0].category_name == 'cell phone']
        person_dets = [d for d in result.detections if d.categories[0].category_name == 'person'
                       and d.categories[0].score >= PERSON_SCORE_THRESHOLD]

        # Same rule as the Week 4 harness: any phone box that clears the model's 0.15
        # threshold counts as a detection for this frame. Smoothing over time is NOT done
        # here on purpose (an earlier version averaged in zero frames and that dragged real
        # phones under the threshold). The app decides how long to keep content hidden, the
        # desktop client waits for 10 clear frames in a row before showing it again.
        best = max((d.categories[0].score for d in phone_dets), default=0.0)
        self.last_boxes = phone_dets + person_dets   # used by --preview only

        return {
            'phone_detected': len(phone_dets) > 0,
            'phone_confidence': round(best, 3),
            'person_count': len(person_dets),
            'latency_ms': round(latency_ms, 2),
            'timestamp': datetime.now().isoformat(timespec='milliseconds'),
        }


def draw_preview(frame, detector, result):
    """Same overlay as test_detect.py: phones in red, people in blue, status in the corner."""
    for det in detector.last_boxes:
        bbox = det.bounding_box
        name = det.categories[0].category_name
        color = (0, 0, 255) if name == 'cell phone' else (255, 0, 0)
        x1, y1 = int(bbox.origin_x), int(bbox.origin_y)
        x2, y2 = x1 + int(bbox.width), y1 + int(bbox.height)
        cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
        label_y = y1 - 10 if y1 - 10 > 10 else y1 + 20
        cv2.putText(frame, f"{name} {det.categories[0].score:.2f}", (x1, label_y),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)
    status = 'PHONE DETECTED' if result['phone_detected'] else 'clear'
    cv2.putText(frame, f"{status} | persons={result['person_count']} | {result['latency_ms']:.1f} ms",
                (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7,
                (0, 0, 255) if result['phone_detected'] else (0, 255, 0), 2)
    cv2.imshow('Aperture detector (preview)', frame)
    return (cv2.waitKey(1) & 0xFF) != ord('q')


def emit(result):
    # flush=True matters: without it Python buffers stdout when it's piped into
    # another program, and the desktop app would get results in delayed chunks.
    print(json.dumps(result), flush=True)


def main():
    parser = argparse.ArgumentParser(description='Aperture camera detection service')
    parser.add_argument('--camera', type=int, default=0, help='webcam index (default 0)')
    parser.add_argument('--image', help='run once on an image file instead of the webcam')
    parser.add_argument('--preview', action='store_true',
                        help='also show the camera feed with boxes (for testing/demos, press q to quit)')
    args = parser.parse_args()

    detector = CameraDetector()

    if args.image:
        frame = cv2.imread(args.image)
        if frame is None:
            print(f'Could not read image: {args.image}', file=sys.stderr)
            sys.exit(1)
        emit(detector.check(frame))
        return

    cap = cv2.VideoCapture(args.camera)
    if not cap.isOpened():
        print(f'Could not open camera {args.camera}', file=sys.stderr)
        sys.exit(1)
    print(f'Aperture detector running on camera {args.camera}', file=sys.stderr)

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                print('Camera stopped returning frames', file=sys.stderr)
                break
            result = detector.check(frame)
            emit(result)
            if args.preview and not draw_preview(frame, detector, result):
                break
    except (KeyboardInterrupt, BrokenPipeError):
        # BrokenPipeError = the app that launched us closed, so just exit quietly.
        pass
    finally:
        cap.release()
        if args.preview:
            cv2.destroyAllWindows()


if __name__ == '__main__':
    main()
