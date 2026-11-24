# Week 7 mobile wrap-up

Reviewed October 19, 2026 (America/New_York). Implementation head:
`30a8ed664dc08694085a726f1f054d10256c68e1`.

## Completion and PR status

[Draft PR #8](https://github.com/JorgeOrtizCS/aperture/pull/8) targets `main` from
`rylee/mobile-secure-viewing`. Its two approved implementation commits are:

- `f81a5b3d9504850aede266959c34b0c976fe8e85`: secure viewing requirements/states.
- `30a8ed664dc08694085a726f1f054d10256c68e1`: Week 7 native camera detection.

At the recorded implementation-head snapshot, GitHub reports `MERGEABLE` /
`CLEAN`. There are no submitted reviews, requested
reviewers, conversation comments or inline review comments at this snapshot.
There are zero check runs, zero commit-status records and zero Actions workflow
runs for the head. The REST combined-status endpoint returns `pending` when its
status list is empty; this is not evidence of a queued or running check. No CI
pass is claimed. The branch contains no `.github/workflows` files.

The PR is ready for human implementation review and remains **DRAFT**. Device
acceptance and Jorge's decisions remain open; mergeability does not establish
runtime correctness or approval. No PR review request or message was sent.

## Evidence reconciliation

The reviewed source still matches the published head, apart from the excluded
local Xcode signing settings. The Week 7 commit changes exactly the 27 approved
mobile files. The implementation snapshot contains 39 changed mobile paths
across those two commits; this documentation follow-up adds two new documentation
paths and updates two existing documentation files.
Personal signing-team/bundle-ID settings are absent from the committed Xcode
project and remain unstaged locally.

The retained `build/week7/logs/final-review-*.log` evidence confirms:

| Check | Verified result and limit |
| --- | --- |
| Flutter analysis | No issues. |
| Flutter unit/widget suite | 125 passed; includes camera, violation, policy and capture regressions. |
| Android compile/package | Kotlin compilation and standard debug APK assembly passed. |
| Unsigned iPhone build | Passed; does not establish signing or deployment. |
| iOS ARM simulator native model test | One passed on a gray image; no accuracy claim. |
| iOS camera-unavailable integration | One passed, two live-camera checks intentionally skipped. |
| Android model instrumentation | One attempted, one failed with native SIGILL; no inference pass. |
| Android local JVM tests | NO-SOURCE; not a test pass. |
| Physical camera/latency acceptance | Not performed on either platform. |

The model was compared again with Jorge's `94c6aed` artifact. SHA-256 remains
`0720bf247bd76e6594ea28fa9c6f7c5242be774818997dbbeffc4da460c723bb`.
Both native bridges still use phone threshold 0.15, person threshold 0.5, the
`cell phone`/`person` allowlist and the five-field contract plus `session_id`.
The independent ARM instruction probe and crash/disassembly logs continue to
support an emulator/native CPU-dispatch compatibility diagnosis, not an app-code
fix or a physical Android pass.

No implementation source changed in this wrap-up, so the matching recorded tests
were inspected rather than rerun. No independently verified production defect
requiring a code change was found. The pre-commit inventory in the validation
report is now explicitly historical; its earlier claim that nothing had yet been
committed/pushed must not be read as current publication status.

Snapshot evidence: ignored `build/week7/wrap-up-pr-evidence.json`. Existing local
build logs and result bundles are not committed evidence hosted on GitHub.

## Jorge review brief — prepared, not sent

| Topic | Current mobile behavior | Requested decision/evidence |
| --- | --- | --- |
| Thresholds | Any retained phone score >= 0.15 ends the session; persons count only at >= 0.5. No temporal confidence averaging. | Confirm both thresholds, no smoothing, label set and model hash match the intended detector baseline. |
| Behavioral parity | Same model bytes; native MediaPipe 1.1.1 versus Python's recorded 1.0.1. Python rounds scores; mobile retains precision. UTC mobile timestamps differ from local Python timestamps. | Select shared labeled images and expected results; agree tolerances for confidence/count differences and threshold-boundary cases. Approve UTC/precision conventions. Do not infer numerical parity from gray-image smoke tests. |
| Camera coverage | Front camera only, orientation handling, about 5 Hz inference, no preview or stored frames. | Confirm intended coverage, required distances/angles/light levels, missed-phone/false-positive acceptance and supported device/OS matrix. Agree whether front-only coverage is sufficient. |
| Recovery policy | Phone/screenshot violations permanently end the current viewer/controller session. Clear frames and rechecks cannot revive it. A new flow creates a new session. Camera failures may retry with fresh checks; recording recovery requires policy revalidation. | Confirm session-ending behavior rather than desktop's ten-clear-frame automatic recovery, and whether any future account/server-level lockout is required. No server-level persistent violation record is implemented here. |

For parity, use identical decoded RGB pixels, orientation and model bytes on each
runtime. Record runtime versions, `phone_detected`, highest phone confidence and
`person_count` per fixture; do not compare live front-camera frames against a
different desktop webcam scene. Compare latency as separate measurements and
timestamps as format/timezone fields, not equal values. The mobile native test
currently supplies only a gray image; arbitrary-image parity fixtures/harness
and agreed expected outputs are still future verification work.

## Remaining ownership

- Mobile/device testing: execute [device acceptance](WEEK7_DEVICE_ACCEPTANCE.md)
  on an available iPhone and compatible physical Android device. Keep all results
  NOT RUN until observed. Record actual latency and camera shutdown behavior.
- Jorge/team: approve the four decisions above and the parity/coverage criteria.
- Existing separate project work: real authentication/authorization provider,
  content delivery/decryption and persistent server enforcement. The demo is a
  placeholder; these are not made complete by the mobile detector integration.

## Week 7 progress report — ready to paste

Completed the mobile implementation for all four Week 7 tasks: connected typed
detection events to Flutter, implemented native iOS/Android bridges using Jorge's
EfficientDet Lite0 model and contract, displayed detection state/metrics with
phone-violation lockout in the secure viewer, and added camera permissions,
lifecycle cleanup and integration/regression coverage. Existing screenshot and
screen-recording protections are preserved.

Validation completed: Flutter analysis clean; 125 tests passed; unsigned iOS build,
iOS simulator model inference, iOS camera-unavailable protection, and Android
Kotlin/APK builds passed. Android ARM-emulator inference still fails with native
SIGILL; an independent instruction probe reproduces the emulator capability
problem. Physical iPhone/Android inference, physical latency and real capture
behavior remain unverified. Threshold/contract alignment is verified; behavioral
parity and final sign-off with Jorge remain pending.

Both implementation commits are published in draft PR #8 targeting main, with a
separate documentation finalization commit. The implementation-head snapshot
reports no merge conflicts, no review comments and no configured/running checks. The PR is ready for review, with hardware acceptance and teammate
decisions explicitly outstanding. No merge, additional implementation commit or
personal signing changes were made during this wrap-up.

## Documentation delivery

This file, `WEEK7_DEVICE_ACCEPTANCE.md`, `WEEK7_VALIDATION_REPORT.md` and
`README.md` form the four-file documentation-only follow-up to the published
implementation. Commit message:
`docs(mobile): finalize Week 7 validation and acceptance plans`.
The follow-up preserves the implementation source, personal signing settings and
PR #8's draft state. No physical test or teammate decision is marked complete by
publishing these procedures.
