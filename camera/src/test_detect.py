import cv2, mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
import time
import csv
import os
from datetime import datetime

# --- Task 4.3: configurable threshold for sweep testing ---
# Change this and rerun to test different values against the same scenarios.
SCORE_THRESHOLD = 0.15

# --- Task 4.1: optional frame resize for speed comparison ---
# Set to None to test at full camera resolution, or a (width, height) tuple
# to resize before detection and compare latency against the baseline.
RESIZE_TO = None # e.g. (320, 240) for a speed test run

# --- Scenario labels ---
# Click the feed window, then press a number key to label everything that follows.
# Press 0 while you reposition so setup time can be excluded from the analysis.
SCENARIOS = {
    ord('0'): 'transition',
    ord('1'): 'clean',
    ord('2'): 'open_palm_over_face',
    ord('3'): 'head_turn_headphones_on',
    ord('4'): 'head_turn_headphones_off',
    ord('5'): 'phone_back_bottom_of_frame',
    ord('6'): 'phone_back_over_face',
    ord('7'): 'phone_vertical_at_edge',
    ord('8'): 'phone_screen_side_half_face',
    ord('9'): 'phone_edge_on_left',
}
scenario = 'transition'

base_options = python.BaseOptions(model_asset_path='models/efficientdet_lite0.tflite')
options = vision.ObjectDetectorOptions(base_options=base_options, score_threshold=SCORE_THRESHOLD, category_allowlist=['cell phone'])
detector = vision.ObjectDetector.create_from_options(options)

cap = cv2.VideoCapture(0)

recent_scores = []
BUFFER_SIZE = 5

# --- Task 4.2: log every frame's result to a CSV instead of just printing ---
# One row per frame. If several boxes are found in a frame, the best score is logged.
os.makedirs('logs', exist_ok=True)
log_path = f"logs/run_{datetime.now().strftime('%Y%m%d_%H%M%S')}_thresh{SCORE_THRESHOLD}_labeled.csv"
log_file = open(log_path, 'w', newline='')
log_writer = csv.writer(log_file)
log_writer.writerow(['frame_number', 'timestamp', 'detected', 'raw_score', 'avg_score', 'latency_ms', 'resized',
                     'num_detections', 'scenario', 'detect_size'])

frame_number = 0

print(f"Logging to {log_path}")
print(f"Threshold: {SCORE_THRESHOLD}, Resize: {RESIZE_TO}")
print("Keys: 0=transition 1=clean 2=palm 3=head turn (hp on) 4=head turn (hp off) "
      "5=phone bottom 6=phone over face 7=phone vertical edge 8=phone screen-side 9=phone edge-on, q=quit")

try:
    while True:
        ret, frame = cap.read()
        if not ret: break
        frame_number += 1

        detect_frame = frame
        if RESIZE_TO is not None:
            detect_frame = cv2.resize(frame, RESIZE_TO)
        h, w = detect_frame.shape[:2]
        detect_size = f"{w}x{h}"

        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(detect_frame, cv2.COLOR_BGR2RGB))

        # NOTE: this timer only covers detector.detect(), not the resize or color conversion.
        start = time.time()
        result = detector.detect(mp_image)
        latency_ms = (time.time() - start) * 1000

        if result.detections:
            best = max(result.detections, key=lambda d: d.categories[0].score)
            score = best.categories[0].score
            recent_scores.append(score)
            if len(recent_scores) > BUFFER_SIZE:
                recent_scores.pop(0)
            avg_score = sum(recent_scores) / len(recent_scores)
            print(f"[{scenario}] {best.categories[0].category_name} raw={score:.3f} avg={avg_score:.3f} latency={latency_ms:.1f}ms")
            log_writer.writerow([frame_number, datetime.now().isoformat(), True, f"{score:.3f}", f"{avg_score:.3f}",
                                 f"{latency_ms:.2f}", RESIZE_TO is not None, len(result.detections), scenario, detect_size])
        else:
            print(f"[{scenario}] no detection latency={latency_ms:.1f}ms")
            log_writer.writerow([frame_number, datetime.now().isoformat(), False, "", "", f"{latency_ms:.2f}",
                                 RESIZE_TO is not None, 0, scenario, detect_size])

        # Show the active label on the feed window so you can see which scenario is being recorded.
        cv2.putText(frame, scenario, (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
        cv2.imshow('feed', frame)

        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'): break
        if key in SCENARIOS:
            scenario = SCENARIOS[key]
            print(f">>> scenario: {scenario}")
finally:
    cap.release()
    cv2.destroyAllWindows()
    log_file.close()
    print(f"Done. {frame_number} frames logged to {log_path}")