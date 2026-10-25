# Camera Detection Contract

Owner: Jorge Ortiz (camera detection subsystem)
Used by: desktop client (Colby), mobile app (Rylee), situational-access-control (Daniel), Web API access policy (Colby, Kyra)
Status: v1. Fields, thresholds and timestamp format are final. Items marked **Team decision** still need sign-off.

## 1. What the detector sends

One result per analyzed camera frame. Every platform produces the exact same five fields.

| Field | Type | Meaning |
| --- | --- | --- |
| `phone_detected` | bool | `true` if any `cell phone` box in this frame scored at or above **0.15** |
| `phone_confidence` | number, 0 to 1 | highest `cell phone` score in this frame, `0` if none |
| `person_count` | int, 0 or more | number of `person` boxes scoring at or above **0.5** |
| `latency_ms` | number, 0 or more | time spent inside the model's detect call only (not camera capture or color conversion) |
| `timestamp` | string | ISO 8601 in **UTC** with a `Z`, millisecond precision, e.g. `2026-10-25T22:24:43.080Z` |

Example:

```json
{"phone_detected": true, "phone_confidence": 0.312, "person_count": 1, "latency_ms": 18.4, "timestamp": "2026-10-25T22:24:43.080Z"}
```

Rules that every implementation follows:

- **Model:** `camera/models/efficientdet_lite0.tflite` (EfficientDet-Lite0, int8, COCO). All platforms load these exact bytes.
- **Labels:** only `cell phone` and `person`. Every other COCO class is ignored.
- **Thresholds:** phone **0.15**, person **0.5**. The phone threshold is low on purpose. Week 4 testing showed no single threshold separates real phones from false positives, and a missed phone leaks content while a false positive only hides it.
- **No smoothing in the detector.** Each result describes one frame only. Deciding how long to keep content hidden is the app's job (see section 3).
- Confidence values may be rounded to 3 decimals. Apps must not depend on more precision than that.

Where each implementation lives:

| Platform | Implementation | How the app gets results |
| --- | --- | --- |
| Desktop (Windows) | `camera/src/detector_service.py` (Python, MediaPipe) | one JSON line per frame on stdout, read by `Services/CameraDetectionService.cs` |
| iOS / Android | Rylee's native bridges (MediaPipe Tasks, Swift / Kotlin) | typed detection events into Flutter |

## 2. How the results map to the sender's restrictions

The sender picks camera restrictions when sharing content. They are stored in the `AccessPolicy` table and returned to the client with the session.

| AccessPolicy flag | Hide the content when |
| --- | --- |
| `CameraDetectionEnabled` | turns camera checks on for this content. If off, the camera is never started. |
| `BlockPhones` | `phone_detected == true` |
| `BlockMultiplePeople` | `person_count > 1` |
| `RequireViewer` | `person_count == 0` |

Fail closed. When `CameraDetectionEnabled` is on, the content also stays hidden when:

- the camera hasn't produced a valid result yet (startup)
- no valid result has arrived for **5 seconds**
- the camera or detector fails (no webcam, permission denied, detector crashed)

Camera checks run on the client, because the server can't see the camera. They sit next to Daniel's situational-access-control checks (location, time). They don't replace them. Content is visible only when **every** server check and **every** enabled camera check passes.

## 3. Decisions (answers to the mobile Week 7 review brief)

| Topic | Decision |
| --- | --- |
| Thresholds and labels | **Confirmed:** phone 0.15, person 0.5, labels `cell phone` and `person` only, no averaging across frames, same model bytes on every platform. |
| Timestamps | **Confirmed:** UTC with `Z`. The Python detector was changed to emit UTC to match mobile. |
| Precision | **Confirmed:** compare confidences to 3 decimals. Mobile may keep full precision internally. |
| Behavioral parity | **Confirmed method:** compare platforms on the same still images, not live camera frames. Fixture set = the labeled Roboflow dataset (114 photos across the six Week 4 scenarios). Pass if `phone_detected` matches on at least 95% of fixtures, `phone_confidence` is within 0.05, and `person_count` matches exactly on at least 95%. Latency is measured separately per device, never compared as equal values. |
| Camera coverage | **Confirmed:** front camera only is enough. The threat is a second phone pointed at the screen, which sits in front of the viewer, on the same side as the front camera. Target conditions: normal indoor light, about 0.3 to 1.5 m from the screen. About 5 frames per second on mobile is acceptable, since each frame is still checked well within the sponsor's 200 ms budget. Required accuracy rates get set in Week 8 after testing against the labeled dataset. |
| Recovery after a phone violation | **Team decision, not final.** Today mobile ends the viewing session on a phone violation, and desktop hides the content and brings it back after 10 clear frames in a row. Proposal: keep screenshot and screen-recording violations session-ending on both platforms. For camera violations, use the desktop behavior (hide, then recover after 10 clear frames) on both platforms until the model's false positives (open palm, glasses, headphones) are reduced, because ending the session on a false positive would kick legitimate viewers out constantly. Revisit once Week 8 accuracy results are in. To confirm with the team and the sponsor (meeting 11/4/26). |
| Server-side violation record | **Team decision, not final.** Proposal: the client includes its latest camera state (`phone_detected`, `person_count`) in the existing 5-second session check, so the server can log violations next to Daniel's situational checks. Needs Daniel's and Colby's agreement before anyone builds it. |

## 4. Known limitations (as of 10/25/26)

- **False positives:** open palm near the face, headphones during head turns, and glasses (seen on Rylee's iPhone test). In the 61 no-phone dataset photos, the model put 32 false phone boxes on 27 photos.
- **Missed and misplaced phones:** phones held edge-on or vertical at the frame edge are often missed. When the model does flag a phone in those poses, the box usually lands on a small part, like a thumb or camera lens, instead of the whole phone.
- **Mobile latency on real hardware hasn't been measured yet.** Google's published average for this model (int8) is 29.31 ms on a Pixel 6 CPU. Desktop measured about 17.5 to 19 ms per frame.

## 5. Checking your setup (desktop)

```
python camera/src/detector_service.py --check     # tests packages, model and webcam, then exits
python camera/src/detector_service.py --preview   # live window with boxes, press q to quit
```

If the desktop client says `Camera detector stopped: ...`, the text after the colon is the actual error from the detector, for example a missing package or a webcam that another app is using.
