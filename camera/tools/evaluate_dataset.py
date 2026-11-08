"""
Aperture camera detection: dataset accuracy evaluation (Week 8, Task 8.1).

Runs a detector over the labeled Week 7 dataset and reports, per scenario and
per phone threshold, how often it catches a real phone and how often it flags a
phone that isn't there. Ground truth comes from the scenario folder name: every
folder that starts with "phone_" has a phone in every photo, every other folder
has none (same rule prelabel.py used before the boxes were checked in Roboflow).

This is an image-level check, which is what the apps actually act on: the
detector's phone_detected flag is per frame, not per box.

Usage:
    python evaluate_dataset.py DATASET_DIR                       # current model (efficientdet_lite0)
    python evaluate_dataset.py DATASET_DIR --model yolo --weights yolo11n.pt
    python evaluate_dataset.py DATASET_DIR --only review_checklist.csv   # restrict to the 114 Roboflow photos
    python evaluate_dataset.py DATASET_DIR --out results/week8

Writes <out>/<model>_per_image.csv and <out>/<model>_summary.md, and prints the summary.
"""
import argparse
import csv
import os
import statistics
import sys
import time

import cv2

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_MODEL = os.path.join(HERE, '..', 'models', 'efficientdet_lite0.tflite')

# Thresholds to sweep. 0.15 is the production value in detector_service.py and the contract.
THRESHOLDS = [0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.50]
PERSON_THRESHOLD = 0.5
FLOOR = min(THRESHOLDS)  # ask the model for everything above the lowest threshold, filter after


class EfficientDetRunner:
    """Same model/options as detector_service.py, but with a lower floor so we can sweep."""
    name = 'efficientdet_lite0'

    def __init__(self, model_path):
        import mediapipe as mp
        from mediapipe.tasks import python
        from mediapipe.tasks.python import vision
        self.mp = mp
        options = vision.ObjectDetectorOptions(
            base_options=python.BaseOptions(model_asset_path=model_path),
            score_threshold=FLOOR,
            category_allowlist=['cell phone', 'person'])
        self.detector = vision.ObjectDetector.create_from_options(options)

    def __call__(self, bgr):
        img = self.mp.Image(image_format=self.mp.ImageFormat.SRGB, data=cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
        t = time.time()
        res = self.detector.detect(img)
        ms = (time.time() - t) * 1000
        phones = [d.categories[0].score for d in res.detections if d.categories[0].category_name == 'cell phone']
        people = [d.categories[0].score for d in res.detections if d.categories[0].category_name == 'person']
        return phones, people, ms


class YoloRunner:
    """Ultralytics YOLO with COCO weights (class 67 = cell phone, 0 = person). Used for the swap comparison."""

    def __init__(self, weights):
        from ultralytics import YOLO
        self.model = YOLO(weights)
        self.name = os.path.splitext(os.path.basename(weights))[0]
        self.model.predict(_blank(), verbose=False, device='cpu')  # warm-up so the first photo's latency is fair

    def __call__(self, bgr):
        t = time.time()
        r = self.model.predict(bgr, conf=FLOOR, classes=[0, 67], verbose=False, device='cpu')[0]
        ms = (time.time() - t) * 1000
        cls = r.boxes.cls.tolist()
        conf = r.boxes.conf.tolist()
        phones = [c for k, c in zip(cls, conf) if int(k) == 67]
        people = [c for k, c in zip(cls, conf) if int(k) == 0]
        return phones, people, ms


def _blank():
    import numpy as np
    return np.zeros((480, 640, 3), dtype='uint8')


def load_images(root, only_csv):
    allowed = None
    if only_csv:
        with open(only_csv, newline='') as f:
            allowed = {(r['folder'], r['file']) for r in csv.DictReader(f)}
    items = []
    for folder in sorted(os.listdir(root)):
        path = os.path.join(root, folder)
        if not os.path.isdir(path):
            continue
        for name in sorted(os.listdir(path)):
            if not name.lower().endswith(('.jpg', '.jpeg', '.png')):
                continue
            if allowed is not None and (folder, name) not in allowed:
                continue
            items.append((folder, name, os.path.join(path, name), folder.startswith('phone_')))
    return items


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('dataset')
    ap.add_argument('--model', choices=['efficientdet', 'yolo'], default='efficientdet')
    ap.add_argument('--weights', default=DEFAULT_MODEL, help='.tflite for efficientdet, .pt for yolo')
    ap.add_argument('--only', help='CSV with folder,file columns (e.g. review_checklist.csv) to restrict images')
    ap.add_argument('--out', default=os.path.join(HERE, '..', 'results', 'week8'))
    args = ap.parse_args()

    runner = EfficientDetRunner(args.weights) if args.model == 'efficientdet' else YoloRunner(args.weights)
    items = load_images(args.dataset, args.only)
    if not items:
        sys.exit('No images found')
    os.makedirs(args.out, exist_ok=True)

    rows = []
    for folder, name, path, has_phone in items:
        bgr = cv2.imread(path)
        phones, people, ms = runner(bgr)
        rows.append({'folder': folder, 'file': name, 'phone_in_photo': has_phone,
                     'best_phone_score': round(max(phones, default=0.0), 3),
                     'phone_boxes_at_0.15': sum(s >= 0.15 for s in phones),
                     'person_count': sum(s >= PERSON_THRESHOLD for s in people),
                     'latency_ms': round(ms, 2)})

    per_image = os.path.join(args.out, f'{runner.name}_per_image.csv')
    with open(per_image, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    pos = [r for r in rows if r['phone_in_photo']]
    neg = [r for r in rows if not r['phone_in_photo']]
    lines = [f'# {runner.name} on {len(rows)} photos ({len(pos)} with phone, {len(neg)} without)', '',
             f'Mean latency: {statistics.mean(r["latency_ms"] for r in rows):.1f} ms per image (CPU, this machine)', '',
             '## Threshold sweep (image level)', '',
             '| Phone threshold | Phones caught (recall) | False phone alarms | Precision | Accuracy |',
             '|---|---|---|---|---|']
    for t in THRESHOLDS:
        tp = sum(r['best_phone_score'] >= t for r in pos)
        fp = sum(r['best_phone_score'] >= t for r in neg)
        prec = tp / (tp + fp) if tp + fp else 0
        acc = (tp + len(neg) - fp) / len(rows)
        mark = ' (current)' if t == 0.15 else ''
        lines.append(f'| {t:.2f}{mark} | {tp}/{len(pos)} ({tp / len(pos):.0%}) | {fp}/{len(neg)} ({fp / len(neg):.0%}) '
                     f'| {prec:.0%} | {acc:.0%} |')
    lines += ['', '## Per scenario at the current 0.15 threshold', '',
              '| Scenario | Phone in photo | Photos | Flagged as phone | Person found |', '|---|---|---|---|---|']
    for folder in sorted({r['folder'] for r in rows}):
        rs = [r for r in rows if r['folder'] == folder]
        flagged = sum(r['best_phone_score'] >= 0.15 for r in rs)
        people = sum(r['person_count'] >= 1 for r in rs)
        lines.append(f'| {folder} | {"yes" if rs[0]["phone_in_photo"] else "no"} | {len(rs)} | {flagged} | {people} |')
    summary = '\n'.join(lines) + '\n'
    with open(os.path.join(args.out, f'{runner.name}_summary.md'), 'w') as f:
        f.write(summary)
    print(summary)


if __name__ == '__main__':
    main()
