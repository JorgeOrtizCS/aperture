import cv2, mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
import time

base_options = python.BaseOptions(model_asset_path='models/efficientdet_lite0.tflite')
options = vision.ObjectDetectorOptions(base_options=base_options, score_threshold=0.15, category_allowlist=['cell phone'])
detector = vision.ObjectDetector.create_from_options(options)

cap = cv2.VideoCapture(0)

# rolling buffer so a single noisy frame doesn't tank the reported confidence
recent_scores = []
BUFFER_SIZE = 5

while True:
    ret, frame = cap.read()
    if not ret: break
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))

    start = time.time()
    result = detector.detect(mp_image)
    latency_ms = (time.time() - start) * 1000

    if result.detections:
        for d in result.detections:
            score = d.categories[0].score
            recent_scores.append(score)
            if len(recent_scores) > BUFFER_SIZE:
                recent_scores.pop(0)
            avg_score = sum(recent_scores) / len(recent_scores)
            print(f"{d.categories[0].category_name} raw={score:.3f} avg={avg_score:.3f} latency={latency_ms:.1f}ms")
    else:
        print(f"no detection latency={latency_ms:.1f}ms")

    cv2.imshow('feed', frame)
    if cv2.waitKey(1) & 0xFF == ord('q'): break

cap.release()
cv2.destroyAllWindows()