# efficientdet_lite0 on 114 photos (53 with phone, 61 without)

Mean latency: 25.8 ms per image (CPU, this machine)

## Threshold sweep (image level)

| Phone threshold | Phones caught (recall) | False phone alarms | Precision | Accuracy |
|---|---|---|---|---|
| 0.10 | 43/53 (81%) | 33/61 (54%) | 57% | 62% |
| 0.15 (current) | 32/53 (60%) | 27/61 (44%) | 54% | 58% |
| 0.20 | 23/53 (43%) | 22/61 (36%) | 51% | 54% |
| 0.25 | 19/53 (36%) | 16/61 (26%) | 54% | 56% |
| 0.30 | 17/53 (32%) | 13/61 (21%) | 57% | 57% |
| 0.35 | 13/53 (25%) | 8/61 (13%) | 62% | 58% |
| 0.40 | 10/53 (19%) | 5/61 (8%) | 67% | 58% |
| 0.50 | 8/53 (15%) | 4/61 (7%) | 67% | 57% |

## Per scenario at the current 0.15 threshold

| Scenario | Phone in photo | Photos | Flagged as phone | Person found |
|---|---|---|---|---|
| head_turn_headphones_off | no | 23 | 5 | 23 |
| head_turn_headphones_on | no | 22 | 10 | 21 |
| open_palm_over_face | no | 16 | 12 | 16 |
| phone_back_over_face | yes | 17 | 16 | 17 |
| phone_edge_on_left | yes | 20 | 9 | 20 |
| phone_vertical_at_edge | yes | 16 | 7 | 16 |
