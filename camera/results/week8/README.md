# Week 8 camera detection results (Tasks 8.1 and 8.2)

Dataset: the 114 labeled Week 7 photos (53 with a phone, 61 without), same set as Roboflow.
Script: `camera/tools/evaluate_dataset.py`. Image level, because the apps act on the per-frame
`phone_detected` flag, not on individual boxes.

## Current model vs swap candidates (phone threshold 0.15)

| Model | Phones caught | False phone alarms | Accuracy | CPU latency (this test machine) |
|---|---|---|---|---|
| efficientdet_lite0 (current) | 32/53 (60%) | 27/61 (44%) | 58% | 25.8 ms |
| yolo11n (COCO) | 34/53 (64%) | 3/61 (5%) | 81% | 66.7 ms |
| yolo26n (COCO) | 29/53 (55%) | 0/61 (0%) | 79% | 56.7 ms |

Best operating points: yolo11n at 0.10 catches 70% with 8% false alarms; yolo26n at 0.10 catches
64% with 0% false alarms. EfficientDet at 0.10 catches 81% but false-alarms on 54% of no-phone photos.

## What this says

- Threshold tuning can't fix EfficientDet. Every threshold that cuts its false alarms to a usable
  level also drops recall under 25%. The face and hand false positives (open palm 12/16,
  headphones 10/22) are the same failure family as the glasses false positives Rylee saw on iPhone.
- Both YOLO models almost eliminate face/hand false alarms, which would stop content getting
  locked for no reason.
- Nobody catches edge-on or vertical-at-edge phones reliably (5 to 10 of 16-20). That is a
  training data problem, so a model swap alone won't fix it. That needs fine-tuning on the
  labeled boxes.

## Decision

Keep efficientdet_lite0 in production for the demo (it's what desktop and mobile both run today
and the contract is built around it). Move to a YOLO nano model (yolo26n first, yolo11n backup)
fine-tuned on the Roboflow set, once it's measured on a physical phone and stays under the
sponsor's 200 ms limit. Desktop latency for both is well under that.

## Files

- `efficientdet_lite0_per_image.csv` - per-photo scores for the current model. This is also the
  reference file for desktop/mobile parity: the native mobile detector run on the same photos
  should produce the same phone_detected / person_count results.
- `yolo11n_*`, `yolo26n_*` - same evaluation for the swap candidates.

## Integration fix (Task 8.2)

Colby's "camera detection stopped" error on his laptop was the detector's Python not having the
camera packages. Fixed by `camera/setup.ps1` (creates camera/venv from requirements.txt and test
loads the model) plus the desktop client now picking camera/venv automatically and naming the
missing package in the error. Verified the pinned requirements install cleanly (`pip check` clean)
and the detector loads and runs on a blank frame and a phone photo in a fresh environment.
