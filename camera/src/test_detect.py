import cv2, mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

base_options = python.BaseOptions(model_asset_path='models/efficientdet_lite0.tflite')
options = vision.ObjectDetectorOptions(base_options=base_options, score_threshold=0.5)
detector = vision.ObjectDetector.create_from_options(options)

cap = cv2.VideoCapture(0)
while True:
    ret, frame = cap.read()
    if not ret: break
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
    result = detector.detect(mp_image)
    for d in result.detections:
        print(d.categories[0].category_name, d.categories[0].score)
    cv2.imshow('feed', frame)
    if cv2.waitKey(1) & 0xFF == ord('q'): break