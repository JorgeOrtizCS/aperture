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

# Person detection gets its own, stricter threshold. Unlike phone (where real and
# false detections overlap in score and threshold tuning alone can't separate them,
# see Week 4 Task 4.3), weak person false positives (background objects, reflections)
# tend to score much lower than real people in frame, so a higher bar filters them
# out cleanly without the same tradeoff. Model-level SCORE_THRESHOLD above stays low
# so phone detection isn't affected.
PERSON_SCORE_THRESHOLD = 0.5

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
options = vision.ObjectDetectorOptions(base_options=base_options, score_threshold=SCORE_THRESHOLD, category_allowlist=['cell phone', 'person'])
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
                     'num_detections', 'scenario', 'detect_size', 'person_count'])

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

        # Phone stats stay separate from person stats so the CSV's "detected"/"raw_score"/"avg_score"
        # columns keep meaning exactly what they meant in Week 4 (phone confidence), now that
        # the model is also returning person detections mixed into result.detections.
        phone_dets = [d for d in result.detections if d.categories[0].category_name == 'cell phone']
        person_dets = [d for d in result.detections if d.categories[0].category_name == 'person'
                       and d.categories[0].score >= PERSON_SCORE_THRESHOLD]
        person_count = len(person_dets)

        if phone_dets:
            best = max(phone_dets, key=lambda d: d.categories[0].score)
            score = best.categories[0].score
            recent_scores.append(score)
            if len(recent_scores) > BUFFER_SIZE:
                recent_scores.pop(0)
            avg_score = sum(recent_scores) / len(recent_scores)
            print(f"[{scenario}] cell phone raw={score:.3f} avg={avg_score:.3f} persons={person_count} latency={latency_ms:.1f}ms")
            log_writer.writerow([frame_number, datetime.now().isoformat(), True, f"{score:.3f}", f"{avg_score:.3f}",
                                 f"{latency_ms:.2f}", RESIZE_TO is not None, len(phone_dets), scenario, detect_size, person_count])
        else:
            print(f"[{scenario}] no phone detection persons={person_count} latency={latency_ms:.1f}ms")
            log_writer.writerow([frame_number, datetime.now().isoformat(), False, "", "", f"{latency_ms:.2f}",
                                 RESIZE_TO is not None, 0, scenario, detect_size, person_count])

        # --- Visual overlay: draw a box + label for every detection on the displayed frame. ---
        # Detection coordinates come from detect_frame (which may be resized), so scale them
        # back up to the original frame's size before drawing, otherwise boxes are offset/wrong-sized
        # whenever RESIZE_TO is set.
        sx = frame.shape[1] / detect_frame.shape[1]
        sy = frame.shape[0] / detect_frame.shape[0]
        for det in phone_dets + person_dets:
            bbox = det.bounding_box
            x1 = int(bbox.origin_x * sx)
            y1 = int(bbox.origin_y * sy)
            x2 = int((bbox.origin_x + bbox.width) * sx)
            y2 = int((bbox.origin_y + bbox.height) * sy)
            det_score = det.categories[0].score
            det_name = det.categories[0].category_name
            # Phones in red (the thing we actually care about catching), people in blue,
            # so it's obvious at a glance which is which on screen.
            color = (0, 0, 255) if det_name == 'cell phone' else (255, 0, 0)
            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
            label = f"{det_name} {det_score:.2f}"
            label_y = y1 - 10 if y1 - 10 > 10 else y1 + 20
            cv2.putText(frame, label, (x1, label_y), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)

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