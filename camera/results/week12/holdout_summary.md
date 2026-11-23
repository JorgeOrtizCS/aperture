# Held-out photos: 34 (12 with phone, 22 without)

Fine-tuned mean CPU latency: 49.3 ms

| Model | Threshold | Phones caught | False alarms | Accuracy |
|---|---|---|---|---|
| efficientdet_lite0 | 0.15 | 11/12 | 13/22 | 59% |
| efficientdet_lite0 | 0.25 | 7/12 | 8/22 | 62% |
| efficientdet_lite0 | 0.5 | 3/12 | 1/22 | 71% |
| yolo11n_coco | 0.15 | 11/12 | 1/22 | 94% |
| yolo11n_coco | 0.25 | 9/12 | 1/22 | 88% |
| yolo11n_coco | 0.5 | 7/12 | 0/22 | 85% |
| yolo26n_coco | 0.15 | 9/12 | 0/22 | 91% |
| yolo26n_coco | 0.25 | 9/12 | 0/22 | 91% |
| yolo26n_coco | 0.5 | 8/12 | 0/22 | 88% |
| finetuned | 0.15 | 12/12 | 1/22 | 97% |
| finetuned | 0.25 | 12/12 | 1/22 | 97% |
| finetuned | 0.5 | 12/12 | 1/22 | 97% |

## Per scenario at 0.15 (finetuned vs efficientdet vs yolo26n_coco)

- head_turn_headphones_off (5): finetuned 0, efficientdet_lite0 2, yolo26n_coco 0 flagged
- head_turn_headphones_on (10): finetuned 0, efficientdet_lite0 4, yolo26n_coco 0 flagged
- open_palm_over_face (7): finetuned 1, efficientdet_lite0 7, yolo26n_coco 0 flagged
- phone_back_over_face (7): finetuned 7, efficientdet_lite0 7, yolo26n_coco 7 flagged
- phone_edge_on_left (2): finetuned 2, efficientdet_lite0 2, yolo26n_coco 0 flagged
- phone_vertical_at_edge (3): finetuned 3, efficientdet_lite0 2, yolo26n_coco 2 flagged