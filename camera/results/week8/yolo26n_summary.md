# yolo26n on 114 photos (53 with phone, 61 without)

Mean latency: 56.7 ms per image (CPU, this machine)

## Threshold sweep (image level)

| Phone threshold | Phones caught (recall) | False phone alarms | Precision | Accuracy |
|---|---|---|---|---|
| 0.10 | 34/53 (64%) | 0/61 (0%) | 100% | 83% |
| 0.15 (current) | 29/53 (55%) | 0/61 (0%) | 100% | 79% |
| 0.20 | 25/53 (47%) | 0/61 (0%) | 100% | 75% |
| 0.25 | 24/53 (45%) | 0/61 (0%) | 100% | 75% |
| 0.30 | 22/53 (42%) | 0/61 (0%) | 100% | 73% |
| 0.35 | 22/53 (42%) | 0/61 (0%) | 100% | 73% |
| 0.40 | 20/53 (38%) | 0/61 (0%) | 100% | 71% |
| 0.50 | 18/53 (34%) | 0/61 (0%) | 100% | 69% |

## Per scenario at the current 0.15 threshold

| Scenario | Phone in photo | Photos | Flagged as phone | Person found |
|---|---|---|---|---|
| head_turn_headphones_off | no | 23 | 0 | 23 |
| head_turn_headphones_on | no | 22 | 0 | 22 |
| open_palm_over_face | no | 16 | 0 | 16 |
| phone_back_over_face | yes | 17 | 16 | 17 |
| phone_edge_on_left | yes | 20 | 8 | 20 |
| phone_vertical_at_edge | yes | 16 | 5 | 16 |
