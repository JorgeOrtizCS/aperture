"""Image-level eval on the Roboflow valid+test photos (not used for training).
Compares fine-tuned yolo26n vs the Week 8 COCO results on the exact same photos."""
import csv, glob, os, sys, time, statistics
import cv2
from ultralytics import YOLO
W8 = sys.argv[1]; FT = sys.argv[2]; RF = sys.argv[3]; OUT = sys.argv[4]
ref = {}
for m in ['efficientdet_lite0', 'yolo26n', 'yolo11n']:
    for r in csv.DictReader(open(os.path.join(W8, m + '_per_image.csv'))):
        ref.setdefault(r['file'], {'folder': r['folder'], 'phone': r['phone_in_photo'] == 'True'})[m] = float(r['best_phone_score'])
imgs = sorted(glob.glob(f'{RF}/valid/images/*.jpg') + glob.glob(f'{RF}/test/images/*.jpg'))
model = YOLO(FT); model.predict(cv2.imread(imgs[0]), verbose=False, device='cpu')
rows = []
for p in imgs:
    orig = os.path.basename(p).split('_jpg.rf.')[0] + '.jpg'
    b = cv2.imread(p); t = time.time()
    r = model.predict(b, conf=0.05, verbose=False, device='cpu')[0]; ms = (time.time() - t) * 1000
    ph = [c for k, c in zip(r.boxes.cls.tolist(), r.boxes.conf.tolist()) if int(k) == 0]
    d = ref[orig]
    rows.append({'file': orig, 'folder': d['folder'], 'phone_in_photo': d['phone'], 'finetuned': round(max(ph, default=0), 3),
                 'yolo26n_coco': d['yolo26n'], 'efficientdet_lite0': d['efficientdet_lite0'], 'yolo11n_coco': d['yolo11n'], 'ft_latency_ms': round(ms, 1)})
os.makedirs(OUT, exist_ok=True)
with open(f'{OUT}/holdout_per_image.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
pos = [r for r in rows if r['phone_in_photo']]; neg = [r for r in rows if not r['phone_in_photo']]
L = [f'# Held-out photos: {len(rows)} ({len(pos)} with phone, {len(neg)} without)', '',
     f'Fine-tuned mean CPU latency: {statistics.mean(r["ft_latency_ms"] for r in rows):.1f} ms', '',
     '| Model | Threshold | Phones caught | False alarms | Accuracy |', '|---|---|---|---|---|']
for m in ['efficientdet_lite0', 'yolo11n_coco', 'yolo26n_coco', 'finetuned']:
    for t in [0.15, 0.25, 0.5]:
        tp = sum(r[m] >= t for r in pos); fp = sum(r[m] >= t for r in neg)
        L.append(f'| {m} | {t} | {tp}/{len(pos)} | {fp}/{len(neg)} | {(tp+len(neg)-fp)/len(rows):.0%} |')
L += ['', '## Per scenario at 0.15 (finetuned vs efficientdet vs yolo26n_coco)', '']
for fo in sorted({r['folder'] for r in rows}):
    g = [r for r in rows if r['folder'] == fo]
    L.append(f'- {fo} ({len(g)}): ' + ', '.join(f"{m} {sum(r[m]>=0.15 for r in g)}" for m in ['finetuned', 'efficientdet_lite0', 'yolo26n_coco']) + ' flagged')
open(f'{OUT}/holdout_summary.md', 'w').write('\n'.join(L)); print('\n'.join(L))
