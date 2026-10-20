# Aperture Week 7 mobile validation report

Validated October 19, 2026, for the Flutter application in `aperture/mobile`.
The four tasks have mobile implementations, and both iOS and Android builds pass.
Technical contract alignment is verified; joint sign-off with Jorge remains open.
Full device acceptance remains incomplete: the physical iPhone was unavailable, and
the tested Android emulator crashes inside the native MediaPipe library.

## Current publication and wrap-up

The implementation is committed and published in
[draft PR #8](https://github.com/JorgeOrtizCS/aperture/pull/8), targeting `main`
from `rylee/mobile-secure-viewing`. The PR includes the approved implementation commits
`f81a5b3d9504850aede266959c34b0c976fe8e85` and
`30a8ed664dc08694085a726f1f054d10256c68e1` (implementation baseline), followed
by a documentation-only finalization commit. The latter implementation commit retains the exact 27-file mobile scope below, without the local
personal signing-team or bundle-ID changes.

At the October 19 wrap-up snapshot, GitHub reports `MERGEABLE` / `CLEAN`, no review
comments, no submitted/requested reviews and zero check runs, commit statuses or
Actions workflow runs for the head. Empty statuses produce a combined REST state
of `pending`; no actual pending check and no CI success were observed.
The PR remains DRAFT and is ready for human review, not final device acceptance.

The existing test/build logs were reconciled with the unchanged published source;
no implementation change or repeated runtime validation was needed. The report's
pre-commit Git inventory below is retained as history, not current branch status.
See [wrap-up and Jorge review brief](WEEK7_WRAP_UP.md) and
[device procedures with pass/fail criteria](WEEK7_DEVICE_ACCEPTANCE.md).
The wrap-up documentation is finalized in a separate four-file documentation
commit for PR #8. No implementation or personal signing settings changed; no
merge or rebase was performed. The test outcomes below remain those observed
for the implementation baseline, not new device results.

## Assigned Week 7 tasks

| Assigned task | Implementation status | Verification |
| --- | --- | --- |
| Connect the detection module to Flutter | Implemented | Typed events, startup, stream errors, timeouts, ownership, and cleanup covered by automated tests. Native model execution passed on the iOS simulator. |
| Coordinate the native Flutter bridge with Jorge's contract | Technical implementation complete; joint acceptance open | All five fields, both thresholds, allowed labels, and the exact model artifact verified against 94c6aed. No direct Jorge confirmation or same-image parity results are available. Native Android and iOS code compile. |
| Display detection events in the secure viewer | Implemented | Status and metrics display, immediate content removal, warning, session termination, and permanent violation latch verified in widget tests. |
| Prepare the mobile interface and camera bridge | Implemented | Permissions, lifecycle control, model bundling, resource release, and fail-closed rendering included. A real iOS native camera-unavailable result kept the demo content hidden. |

The requested validation work has the following status:

| Validation task | Status |
| --- | --- |
| Physical iPhone testing | Deferred as instructed. Previous validation found no available iPhone; this review did not wait for or deploy to a physical device. |
| Camera detection verification | Automated security and lifecycle checks passed. Physical positive phone detection, camera indicator behavior, screenshots, and screen recording still require device acceptance. |
| Android build repair | NDK repaired; standard debug APK assembly and Kotlin compilation passed. Emulator native inference test failed with a reproduced emulator/native-runtime capability mismatch. |
| Jorge integration verification | Contract and model artifact verified from commit 94c6aed. Same-image behavioral parity and recovery policy still require coordination. |
| Final validation and reporting | Available builds, regression tests, native tests, and iOS camera-failure integration executed; results and blockers recorded here and in the mobile README. |

## Implemented features

- `CameraDetectionService` validates complete typed events and serializes native
  camera ownership. Each run has an ID so stale frames and permission callbacks
  cannot authorize a later viewer.
- Native iOS AVFoundation and Android CameraX capture feed the bundled TFLite
  model through MediaPipe, without a camera preview, saved frames, or image logs.
- Protected content requires existing policy/capture checks and a fresh camera
  result. Permission denial, stream failure, missing fields, and detector errors
  keep it hidden; a five-second frame timeout detects a stalled monitor.
- Phone detection ends the viewing session. Clear frames, camera retry,
  background/resume, and condition rechecks cannot restore an ended session.
- Camera/inference resources are released when the route closes or the app
  leaves an appropriate foreground state. Existing iOS screenshot/recording
  monitoring and Android FLAG_SECURE remain in place.

The existing viewer renders a placeholder. Real authorization, content delivery,
and decrypted rendering remain separate project work.

## Test results

| Check | Observed result |
| --- | --- |
| `flutter analyze` | Passed with no issues. |
| `flutter test` | All 125 unit/widget tests passed. |
| `flutter build ios --debug --no-codesign` | Passed for iPhone architecture; no physical deployment or signing claim. |
| Xcode iOS native XCTest on ARM iPhone 17 Pro simulator | One test passed: real bundled-model inference on a synthetic gray image. |
| Flutter iOS camera-failure integration test | One test passed; two live-camera tests skipped in the explicit camera-unavailable mode. Real native camera failure kept the protected subtree absent and the route closed cleanly. |
| `flutter build apk --debug` | Passed, including Kotlin compilation and standard APK assembly. An ARM64-specific build also passed. |
| Android instrumented model test | One test attempted in the final review and failed: process crashed with SIGILL before returning an inference result. Same native address as the prior runs; reproduced after a cold boot. |
| Android `testDebugUnitTest` | Task completed with NO-SOURCE; there are no Android local JVM test classes. |
| Android live-camera Flutter integration | Prepared but not passed; blocked by the native model-runtime crash on the available emulator. |
| Model artifact verification | Mobile model is byte-for-byte identical to commit 94c6aed; labels and thresholds match. |

The 125-test suite covers event parsing, missing/invalid fields, normal events,
phone-triggered hiding and warnings, violation persistence, startup/shutdown,
permission denial, native errors, stale callbacks, timeouts, capture interaction,
background/resume, and navigation cleanup. Platform-channel fakes in these tests
do not establish physical camera accuracy or hardware capture prevention.

The final-review suite adds three startup regressions: false/null startup
acknowledgements and timeout followed by a late acknowledgement and clear frame.
All remain unavailable and release native ownership. The two live-camera device
tests previously always skipped iOS; they now run on either mobile platform and
skip only unsupported platforms or the explicit camera-unavailable mode. This is
a test-coverage repair, not evidence of physical iOS camera success.

The iOS camera-failure integration used the native bridge with camera permission
pre-granted in Simulator. It validates camera-unavailable handling, not actual
physical permission-denial behavior or successful live inference.

## Physical iPhone results and latency

During the previous validation, `flutter devices --device-timeout 15` found macOS and Chrome but no available
physical iPhone. CoreDevice listed the paired iPhone 17 as unavailable. Flutter
reported local-network connection error -27. Wi-Fi development was discussed,
and the user then instructed continuation without the physical iPhone. This final
review kept physical testing deferred and used only explicit simulator targets.

| Physical iPhone check | Result |
| --- | --- |
| Available for development | Not established; device unavailable. |
| Build and launch using `flutter run` | Not performed; no available physical target. |
| Navigate to secure viewer demo | Not performed on a physical phone. |
| Camera permission and startup | Not observed on a physical phone. |
| Live phone violation, screenshot, and recording behavior | Not physically observed. |
| Physical inference sample count | 0 |
| Average inference latency | Not available. |
| Minimum inference latency | Not available. |
| Maximum inference latency | Not available. |

No simulator test duration or synthetic-image result is presented as an iPhone
camera latency measurement. No successful Android camera latency samples were
obtained either, because the native model test crashed before returning a result.

## Android repair and runtime blocker

The original NDK directory contained only `.installer/.installData`. Google's
checksum-verified SDK command-line tools repaired NDK 28.2.13676358, including
`source.properties`, `package.xml`, and the LLVM toolchain. The tools now reside
in the standard SDK layout. Android SDK Platform 36 and an Android 15 ARM64
system image were also installed for the builds and tests.

The app and instrumented tests compile. Flutter's integration-test plugin and the
instrumented test initially selected incompatible AndroidX runner versions under
AGP's consistent dependency resolution. Debug and instrumented-test dependencies
now agree on runner 1.6.2; release dependencies were not changed by that fix.

The instrumented test used the real model and MediaPipe 1.1.1 on the dedicated
Android 15 ARM64 emulator. It terminated with SIGILL/ILL_ILLOPC in
`libmediapipe_tasks_jni.so`, at relative address `0xcd88d4`. LLVM disassembly
identified `rdsvl x0, #1`; the guest advertised SME-related CPU features. These
observations match the symptoms described in
[MediaPipe issue 6293](https://github.com/google-ai-edge/mediapipe/issues/6293).
This upstream issue is a corroborating user report about another task/version,
not confirmation of a fix for this application or proof of physical-device behavior.

The final review independently tested the emulator without Flutter, MediaPipe,
CameraX, or a model: an NDK-built ARM64 executable forks a child that executes the
exact instruction encoding `0x04bf5820`. It reports:

```text
AT_HWCAP2=0x1a03f105383 SME=0 SME2=1
RDSVL child terminated by signal 4
```

`/proc/cpuinfo` also advertises SME2 subfeatures. Thus the guest exposes an
inconsistent capability set and cannot execute the instruction selected by the
native dependency. The real model instrumentation reproduces the same SIGILL at
`0xcd88d4`, BuildId `40cb14a6b12e6158e1e6fbb9a398041d`, during native detector
initialization, before any inference result. The minimal test bypasses the mobile
camera bridge entirely. The AAR includes its native library for all three APK
ABIs; this is not a missing-library or Gradle resolution failure.

**Finding:** a verified emulator instruction/capability problem interacting with
MediaPipe's native CPU dispatch. No Flutter or camera-bridge implementation defect
was established as the cause. Kotlin exception handlers cannot recover from this
process-level native signal. No production-code change, SDK downgrade, or binary
patch is justified by this evidence. Physical Android success remains unknown.
The isolated probe's failure is expected diagnostic evidence, not a passing
inference test.

Custom CPU masks were unsupported by the installed emulator. Restarting with
hardware acceleration disabled requested still exposed the same CPU features
and reproduced the native crash. Production MediaPipe remains pinned at 1.1.1;
its binary was not patched and the dependency was not downgraded to make tests
appear green. A compatible Android device/runtime is required for live-camera
validation.

## Jorge detector compatibility

Reference: `jorge-camera-detection`, commit
`94c6aeddaf89f81c5d10bdfe14a90e9f9e36817b`, read without modifying its code.

| Contract element | Verification |
| --- | --- |
| `phone_detected` | Boolean; mobile uses the highest retained phone score to derive the flag and validates consistency. |
| `phone_confidence` | Numeric confidence normalized to Dart double in [0,1]; highest retained phone score, or zero. |
| `person_count` | Nonnegative integer; count includes only persons at confidence >= 0.5. |
| `latency_ms` | Finite nonnegative milliseconds around the MediaPipe detect call. |
| `timestamp` | ISO 8601 timestamp; native mobile emits UTC. |
| Phone threshold | 0.15 in Python, iOS, and Android. |
| Person threshold | 0.5 in Python, iOS, and Android. |
| Allowed labels | `cell phone` and `person`; embedded indices 76 and 0 respectively. |
| Model | `efficientdet_lite0.tflite`, identical mobile/source bytes. |

Model SHA-256:
`0720bf247bd76e6594ea28fa9c6f7c5242be774818997dbbeffc4da460c723bb`.
It has a UINT8 320x320 RGB input and two FLOAT32 outputs with embedded detector
metadata. The successful iOS native test confirms runtime compatibility with
that two-output model; Android runtime verification remains blocked as above.

Behavioral differences:

- Python emits JSON lines; mobile emits native maps through EventChannel and adds
  `session_id`. Mobile performs strict field and consistency validation.
- Python rounds confidence to three decimals and latency to two; mobile retains
  full precision. Mobile timers are monotonic; Python uses `time.time()`.
- Python emits local timestamps with milliseconds. Android emits UTC with
  milliseconds; iOS currently emits UTC at second precision, so several events
  can share a timestamp. Run ownership and the frame watchdog do not rely on
  timestamp uniqueness.
- Python defaults to webcam index 0 and processes each retrieved frame. Mobile
  uses the front camera, accounts for orientation, limits inference to roughly
  five frames per second, and suspends with the viewer/app lifecycle.
- Both avoid confidence averaging. Mobile permanently ends a phone-violation
  session; the desktop's ten-clear-frame automatic recovery is not adopted.
- Jorge's recorded Python dependency is MediaPipe 1.0.1; mobile uses native 1.1.1.
  Same-image numerical parity across versions has not been established.

Questions requiring Jorge's confirmation are the shared parity fixtures and
expected outputs, whether the versioned model was used for his benchmarks,
front-camera coverage and false-positive expectations at threshold 0.15, future
recovery policy, and downstream timezone/precision requirements. No message was
sent to Jorge.

## Final implementation audit

Reviewed the Dart service, both native bridges and registrations, permissions,
model packaging, viewer/controller/status changes, capture protection, tests, and
actual Git diffs. No additional production-code defect was verified in this
review. No production source was changed during this final review.

- Startup acknowledgement alone cannot reveal content. A valid current-run frame,
  policy checks, and capture readiness are all required. Invalid fields, stale run
  IDs, startup failure, stream failure and frame timeout cannot authorize viewing.
- Native capture/inference work uses serial worker queues, bounded frame cadence,
  explicit cleanup, lifecycle shutdown and main-thread token checks. No camera
  preview, saved frames, or application camera-upload path was found.
- A phone event removes the protected subtree on the next Flutter frame and
  permanently ends the shared controller session. Camera recovery cannot release
  a recording lock or revive a security violation.
- `lib/services/screen_capture_protection.dart` is unchanged from the
  pre-integration baseline `f81a5b3`. The iOS
  capture bridge is unchanged except for adjacent camera registration; its scene
  capture observer, legacy recording/mirroring observer and screenshot notification
  remain intact. Android's enable/disable `FLAG_SECURE` handlers are unchanged.
  Regression tests retain screenshot, recording, lifecycle and denial coverage.
- iOS screenshot handling remains reactive: the first screenshot may already be
  saved. Camera monitoring is sampled at about 5 Hz and the stalled-frame watchdog
  is five seconds; these are not guarantees against every physical recording.
- The viewer still contains a placeholder, and real authorization/content delivery
  remain outside these Week 7 tasks. The non-demo route uses unverified conditions
  by default and stays hidden. Person count is telemetry, not authorization.
- Same-image model parity, front-camera accuracy and actual capture prevention
  have not been established by mocked channels or synthetic gray images.

## Pre-commit Git review (historical snapshot)

This section records the review before commit `30a8ed6`. Its former HEAD,
upstream/remote absence, file inventory and proposed message are historical.
The actual committed message is
`feat(mobile): integrate native camera detection into secure viewer`.
Use the current publication section above for present PR status. The original
27-file recommendation is preserved for traceability and matches that commit.

Remote heads were checked read-only with `git ls-remote --heads origin` during
this review. They match the locally available remote refs; no fetch, index update,
merge, rebase, commit or push was needed.

- Current branch: `rylee/mobile-secure-viewing`, HEAD
  `f81a5b3d9504850aede266959c34b0c976fe8e85`.
- No upstream is configured for this branch, and no corresponding remote branch
  is advertised. The existing `f81a5b3` viewing-state commit is already in local
  history and is not part of the proposed uncommitted Week 7 change.
- `origin/main` is `5e461210a4ffee426638887f376e89a65c02854c`.
  Relative to it, the branch has one unique commit and lacks seven commits.
  Their changed paths are desktop/WebAPI files, with no mobile overlap.
- Jorge's current detection branch is `94c6aeddaf89f81c5d10bdfe14a90e9f9e36817b`;
  the policy and situational-awareness branches also have no mobile overlap.
  This establishes no textual mobile conflict at the checked tips. It is not a
  claim of end-to-end backend compatibility or a completed merge test.
- All 17 tracked modified files and 10 untracked files are under `mobile/`.
  There are no staged changes. `git diff --check` passes.

Proposed commit message:

```text
feat(mobile): integrate native camera detection with secure viewing
```

Scope: the native model and bridges, typed Flutter session ownership, fail-closed
viewer and phone-violation handling, platform permissions/dependencies, regression
and device tests, and accurate validation documentation. The description should
explicitly retain the Android runtime failure and deferred physical acceptance.

### Exact recommended files

Paths below are relative to the repository root. Include the complete changes in
these 26 files:

- `mobile/README.md`
- `mobile/WEEK7_VALIDATION_REPORT.md`
- `mobile/android/app/build.gradle.kts`
- `mobile/android/app/src/main/AndroidManifest.xml`
- `mobile/android/app/src/main/kotlin/com/example/aperture/MainActivity.kt`
- `mobile/android/app/src/main/kotlin/com/example/aperture/CameraDetectionBridge.kt`
- `mobile/android/app/src/androidTest/kotlin/com/example/aperture/CameraModelInstrumentedTest.kt`
- `mobile/assets/models/efficientdet_lite0.tflite`
- `mobile/integration_test/camera_detection_device_test.dart`
- `mobile/ios/Runner/AppDelegate.swift`
- `mobile/ios/Runner/Info.plist`
- `mobile/ios/Runner/CameraDetectionBridge.swift`
- `mobile/ios/RunnerTests/RunnerTests.swift`
- `mobile/ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `mobile/lib/controllers/viewing_state_controller.dart`
- `mobile/lib/screens/secure_content_viewer_screen.dart`
- `mobile/lib/screens/secure_viewer_screen.dart`
- `mobile/lib/services/camera_detection.dart`
- `mobile/lib/widgets/viewing_status_panel.dart`
- `mobile/pubspec.yaml`
- `mobile/pubspec.lock`
- `mobile/test/camera_detection_test.dart`
- `mobile/test/secure_content_viewer_test.dart`
- `mobile/test/support/camera_detection_fake.dart`
- `mobile/test/support/viewing_test_fakes.dart`
- `mobile/test/warning_states_test.dart`

Include only the camera/model/package integration changes in this 27th file:

- `mobile/ios/Runner.xcodeproj/project.pbxproj`

In that project file, exclude the pre-existing personal changes that add
`DEVELOPMENT_TEAM = 47V9T6T9VJ` and change `PRODUCT_BUNDLE_IDENTIFIER` from
`com.example.aperture` to `com.ryleetexter.aperture` in Debug/Profile/Release.
Preserve them locally. The object-version bump, bridge source/model resources,
framework link and pinned Swift package declarations belong to the integration.
Do not stage that entire file indiscriminately. No generated APKs, build logs,
SDKs, DerivedData, probes or test result bundles belong in the commit.

## Files and evidence

During the pre-commit implementation review, changes were limited to:

- `test/camera_detection_test.dart`: three additional startup regressions.
- `integration_test/camera_detection_device_test.dart`: enable physical iOS live
  tests and preserve the simulator-only no-camera mode.
- `README.md` and this report: final results, findings and commit scope.

Pre-existing mobile integration and personal signing changes were preserved.
No desktop, WebAPI, database or original camera sources were modified. At that
pre-commit review point no files had yet been staged, committed or pushed, and no
merge or rebase had been performed. Publication happened afterward as recorded
in the current-status section above.

Final-review evidence is retained under ignored `build/week7/`:

- `logs/final-review-tests.log`: 125 unit/widget tests passed.
- `logs/final-review-analyze.log`: no issues.
- `logs/final-review-apk-build.log`: standard debug APK build passed.
- `final-review-apk-verification.json`: fresh APK model hash and native ABI inventory.
- `logs/final-review-ios-unsigned-build.log`: unsigned iPhone build passed.
- `logs/final-review-ios-camera-failure.log`: one passed, two live-camera checks skipped.
- `logs/final-review-camera-regressions.log`: 42 camera-service tests passed after formatting.
- `logs/final-review-android-native-tests.log`: real model test crashed.
- `logs/final-review-android-native-crash.log`: fresh native SIGILL backtrace.
- `logs/final-review-android-unit-tests.log`: JVM task NO-SOURCE.
- `logs/final-review-android-cpuinfo.log` and `logs/final-review-android-abi.log`.
- `logs/final-review-native-disassembly.log`: exact native fault instruction.
- `arm-sme-probe.c`, `arm-sme-probe` and `logs/final-review-sme-probe.log`:
  independent instruction reproduction; not production app code.
- `final-review-model-verification.json`: fresh byte identity/hash check.
- `final-review-ios-native-retry.xcresult` and its log: real iOS inference passed.

The first final-review XCTest invocation failed before running a test because
Flutter's generated configuration referenced a deleted temporary integration-test
listener. Retrying with `FLUTTER_TARGET=lib/main.dart` passed; no application source
repair was required. The failed invocation is retained in
`logs/final-review-ios-native-tests.log` and its result bundle for traceability.
Earlier evidence from the previous validation remains under the same build folder.
Xcode also generated a duplicate project-workspace package lockfile during the
review; that generated copy was removed. The pre-existing app-workspace
`Package.resolved` remains in the recommended scope. No camera frames were saved.

## Completion decision

**Implementation committed and published; ready for human review in draft PR
#8.** The exact file/hunk scope above was used. Full acceptance remains open;
no claim is made that all Week 7 device testing passed.

The four tasks have technical implementations. Direct coordination acceptance
with Jorge, same-image parity and hardware validation remain open. Physical
iPhone testing remains explicitly deferred; do not wait for a device. Outstanding
checks are real camera permission/startup, positive phone detection, false
positives/coverage, recording/mirroring/screenshot behavior, lifecycle and camera
indicator shutdown, plus physical latency samples. Android live inference must
succeed on a compatible runtime before Android runtime validation can pass.
