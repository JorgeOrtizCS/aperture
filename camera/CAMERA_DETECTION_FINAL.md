# Aperture Camera Detection Subsystem: Final Documentation

Owner: Jorge Ortiz. Last updated 11/22/26.

## 1. What it does

The camera detection subsystem watches the viewer's front camera while protected content is open and reports, every frame, whether a phone is in view and how many people are in front of the screen. The apps use that to hide content. Detection runs on the client, not the Web API, so the decision never waits on a network round trip (sponsor latency limit is 200 ms).

| Platform | How it runs | Status |
|---|---|---|
| Desktop (C# client) | `camera/src/detector_service.py` started by `CameraDetectionService.cs`, results read line by line, `CameraGuard.cs` hides content | Working end to end (confirmed by Colby 11/1) |
| iOS (Flutter) | Same `efficientdet_lite0.tflite` model through MediaPipe natively, via Rylee's bridge | Working on physical iPhone 17 |
| Android (Flutter) | Same model and bridge | Crashes on the Android 15 ARM emulator only. Runs on a physical Galaxy S24 FE (Rylee, 11/18) |

## 2. Output contract (every frame)

Full spec: `docs/camera-detection-contract.md`.

| Field | Type | Meaning |
|---|---|---|
| phone_detected | bool | A "cell phone" box scored at or above 0.15 |
| phone_confidence | float | Highest phone score in the frame |
| person_count | int | "person" boxes at or above 0.5 |
| latency_ms | float | Time for the model's detect call only |
| timestamp | string | UTC ISO 8601 |

Policy mapping: BlockPhones uses phone_detected, BlockMultiplePeople uses person_count > 1, RequireViewer uses person_count == 0.
Fail closed: content stays hidden during startup, after 5 seconds with no valid result, and if the camera or detector stops. Desktop shows content again only after 10 clear frames in a row.

Model settings every platform must match: EfficientDet-Lite0 int8 (`camera/models/efficientdet_lite0.tflite`), classes "cell phone" and "person" only, phone threshold 0.15, person threshold 0.5, 640x480 input.

## 3. How to run it (desktop)

1. `camera/setup.ps1` builds `camera/venv` from `requirements.txt` and test loads the model. The desktop client picks up that venv automatically (or set `APERTURE_PYTHON`).
2. `python camera/src/detector_service.py --check` tests packages, model and webcam and ends in ALL GOOD.
3. Run the desktop client with `--camera-test` to open a test viewer without logging in.
4. Set `APERTURE_CAMERA_PREVIEW=1` to show the live camera feed with boxes next to the content (demo and debugging). Closing the preview stops the detector, so content stays hidden.

Tools: `camera/tools/prelabel.py` (pre-labels photos for Roboflow), `camera/tools/evaluate_dataset.py` (accuracy per scenario and threshold on the labeled set).

## 4. Measured results

| Measurement | Result |
|---|---|
| Desktop CPU latency | 17.5 ms median over 22,649 frames (Week 4), 19 ms in the 806-frame integration run (Week 7) |
| iPhone 17 latency | 41.6 ms mean, 49.9 ms p95, 84.9 ms max over 1,014 frames. All under 200 ms |
| Galaxy S24 FE latency (Rylee) | 92.04 ms mean live front camera, 63.24 ms on gray test frames |
| Accuracy, 114 labeled photos, threshold 0.15 | Catches 32 of 53 phones (60%), false alarms on 27 of 61 no-phone photos (44%) |
| yolo26n on same photos (COCO weights) | 29 of 53 phones (55%), 0 of 61 false alarms, 56.7 ms desktop CPU |
| yolo11n on same photos (COCO weights) | 34 of 53 phones (64%), 3 of 61 false alarms, 66.7 ms desktop CPU |
| yolo26n fine-tuned on Roboflow v1 (11/22), 34 held-out photos | 12 of 12 phones, 1 of 22 false alarms (97%), 49.3 ms desktop CPU. EfficientDet on the same 34: 11 of 12, 13 of 22 (59%). Photos are near-duplicate frames from one session, so this is optimistic |

## 5. Known limitations

1. **False alarms on faces and hands.** EfficientDet flags open palms (12 of 16), headphones (10 of 22) and glasses (Rylee, iPhone). Its false alarm scores (median 0.28) sit above its real phone scores (median 0.18), so no threshold fixes it. The 11/19 Samsung phone-free baseline failure (0.184 at frame 39) is the same problem. Since a false alarm only hides content, this fails safe but is annoying.
2. **Missed edge-on and vertical phones.** At threshold 0.15 all three models miss about half or more of the edge-on (11 to 12 of 20) and vertical-at-edge (6 to 11 of 16) phones. A model swap alone doesn't fix it. The fine-tuned yolo26n caught both edge-on and all 3 vertical phones in the held-out photos, but that set is small.
3. **Android emulator crash.** SIGILL on the `rdsvl` instruction (ARM SME) inside `libmediapipe_tasks_jni.so`. The emulator reports SME2 without SME, so MediaPipe picks a code path the emulated CPU can't run. Not our code, and it does not happen on the physical Samsung.
4. **Camera detection can't stop everything.** A phone held edge-on, out of frame, or a camera behind the viewer won't be seen. It's one layer next to screenshot blocking, biometrics and situational checks, not the only one.

## 6. Next steps after the showcase

1. Done 11/22: Roboflow project exported as version v1 (YOLOv8 format), yolo26n fine-tuned on the 80 training photos (`yolo26n_aperture_ft.pt`), scored with `camera/tools/eval_holdout.py`.
2. Export to TFLite/LiteRT and CoreML, measure on a physical iPhone and Android against 200 ms, then swap the model on all three platforms together so results stay matched.
3. Collect more photos from other people, rooms and lighting. The current set is one person in one room.
