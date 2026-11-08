# yolo11n on 114 photos (53 with phone, 61 without)

Mean latency: 66.7 ms per image (CPU, this machine)

## Threshold sweep (image level)

| Phone threshold | Phones caught (recall) | False phone alarms | Precision | Accuracy |
|---|---|---|---|---|
| 0.10 | 37/53 (70%) | 5/61 (8%) | 88% | 82% |
| 0.15 (current) | 34/53 (64%) | 3/61 (5%) | 92% | 81% |
| 0.20 | 29/53 (55%) | 3/61 (5%) | 91% | 76% |
| 0.25 | 26/53 (49%) | 3/61 (5%) | 90% | 74% |
| 0.30 | 22/53 (42%) | 3/61 (5%) | 88% | 70% |
| 0.35 | 21/53 (40%) | 2/61 (3%) | 91% | 70% |
| 0.40 | 18/53 (34%) | 2/61 (3%) | 90% | 68% |
| 0.50 | 18/53 (34%) | 0/61 (0%) | 100% | 69% |

## Per scenario at the current 0.15 threshold

| Scenario | Phone in photo | Photos | Flagged as phone | Person found |
|---|---|---|---|---|
| head_turn_headphones_off | no | 23 | 3 | 23 |
| head_turn_headphones_on | no | 22 | 0 | 20 |
| open_palm_over_face | no | 16 | 0 | 16 |
| phone_back_over_face | yes | 17 | 15 | 16 |
| phone_edge_on_left | yes | 20 | 9 | 20 |
| phone_vertical_at_edge | yes | 16 | 10 | 16 |
