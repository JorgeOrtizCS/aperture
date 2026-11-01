"""Pre-label the Week 4 failure-case photos with the current detector (Pascal VOC, for Roboflow import).

Folder name = ground truth about whether a phone is in the photo:
  phone_*      -> a phone IS present. Model phone boxes are only counted, not kept (spot checks
                  showed they land on a thumb or lens, not the whole phone), so every phone
                  box is drawn by hand in Roboflow. review_checklist.csv lists which photos.
  everything else (hands / headphones) -> hard negatives, NO phone. Any model phone box is
                  a known false positive, so it is dropped (and counted).
Person boxes use the same 0.5 threshold as the detector service.
"""
import csv, os, shutil, sys, xml.etree.ElementTree as ET
import cv2, mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

src, out, model = sys.argv[1], sys.argv[2], sys.argv[3]
det = vision.ObjectDetector.create_from_options(vision.ObjectDetectorOptions(
    base_options=python.BaseOptions(model_asset_path=model), score_threshold=0.15,
    category_allowlist=['cell phone', 'person']))

def voc(path, w, h, boxes):
    a = ET.Element('annotation')
    ET.SubElement(a, 'filename').text = os.path.basename(path)
    s = ET.SubElement(a, 'size')
    for k, v in (('width', w), ('height', h), ('depth', 3)):
        ET.SubElement(s, k).text = str(v)
    for name, x1, y1, x2, y2 in boxes:
        o = ET.SubElement(a, 'object')
        ET.SubElement(o, 'name').text = name
        ET.SubElement(o, 'difficult').text = '0'
        b = ET.SubElement(o, 'bndbox')
        for k, v in (('xmin', x1), ('ymin', y1), ('xmax', x2), ('ymax', y2)):
            ET.SubElement(b, k).text = str(v)
    return ET.tostring(a, encoding='unicode')

rows = []
for folder in sorted(os.listdir(src)):
    fdir = os.path.join(src, folder)
    if not os.path.isdir(fdir):
        continue
    has_phone = folder.startswith('phone_')
    os.makedirs(os.path.join(out, folder), exist_ok=True)
    for f in sorted(os.listdir(fdir)):
        if not f.lower().endswith('.jpg'):
            continue
        img = cv2.imread(os.path.join(fdir, f))
        h, w = img.shape[:2]
        res = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(img, cv2.COLOR_BGR2RGB)))
        boxes, phone_found, phone_dropped, best = [], 0, 0, 0.0
        for d in res.detections:
            name, score = d.categories[0].category_name, d.categories[0].score
            bb = d.bounding_box
            x1, y1 = max(0, bb.origin_x), max(0, bb.origin_y)
            x2, y2 = min(w, bb.origin_x + bb.width), min(h, bb.origin_y + bb.height)
            if name == 'person':
                if score >= 0.5:
                    boxes.append(('person', x1, y1, x2, y2))
            elif has_phone:
                # Spot checks showed the model's phone boxes usually land on a small part
                # (thumb, camera lens) instead of the whole phone, so they are NOT kept.
                # They are only counted; the phone box gets drawn by hand in Roboflow.
                phone_found += 1
                best = max(best, score)
            else:
                phone_dropped += 1
        shutil.copy2(os.path.join(fdir, f), os.path.join(out, folder, f))  # original file, no re-encode
        with open(os.path.join(out, folder, f[:-4] + '.xml'), 'w') as x:
            x.write(voc(f, w, h, boxes))
        if has_phone:
            action = 'DRAW a box around the whole phone' + ('' if phone_found else ' (model missed it completely)')
        elif phone_dropped:
            action = 'none (fake phone box removed)'
        else:
            action = 'none'
        rows.append([folder, f, 'yes' if has_phone else 'no', phone_found, f'{best:.2f}' if phone_found else '',
                     phone_dropped, sum(1 for b in boxes if b[0] == 'person'), action])

with open(os.path.join(out, 'review_checklist.csv'), 'w', newline='') as c:
    wr = csv.writer(c)
    wr.writerow(['folder', 'file', 'phone_in_photo', 'model_phone_boxes', 'best_phone_score',
                 'false_phone_boxes_removed', 'person_boxes', 'what_you_need_to_do'])
    wr.writerows(rows)
print(len(rows), 'images')
