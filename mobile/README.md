# Mobile (Flutter)

## Week 7 camera detection

The latest results and remaining acceptance checks are in
[Week 7 mobile validation report](WEEK7_VALIDATION_REPORT.md).
[Final wrap-up and Jorge review brief](WEEK7_WRAP_UP.md) and
[physical-device acceptance procedures](WEEK7_DEVICE_ACCEPTANCE.md) provide the
remaining handoff in the documentation-only follow-up to draft PR #8.

The secure content route now runs a native MediaPipe Object Detector on the front
camera on iOS and Android. Frames stay in memory: there is no preview, frame
storage, image logging, or camera upload. The current protected rendering area is
still the application's existing placeholder; real authorization and decrypted
content delivery remain separate project work.

### Week 7 task mapping

| Task | Implementation |
| --- | --- |
| 1. Connect detection to Flutter | `CameraDetectionService` owns serialized detector sessions and typed `DetectionEvent` values. |
| 2. Coordinate the native bridge | Dedicated method/event channels preserve Jorge's five detector fields and add a run ID to reject stale callbacks. Both native implementations use MediaPipe. |
| 3. Display detection events | The content route displays camera state, phone confidence, person count, and inference latency. Phone detection hides content and ends the shared viewing session. |
| 4. Prepare mobile integration | Permissions, model bundling, dependencies, foreground lifecycle handling, camera/inference cleanup, failure warnings, and regression tests are included. |

### Model and detector contract

Source: `jorge-camera-detection`, commit
`94c6aeddaf89f81c5d10bdfe14a90e9f9e36817b`,
`camera/models/efficientdet_lite0.tflite` and `camera/src/detector_service.py`.
The mobile copy is `assets/models/efficientdet_lite0.tflite`; its SHA-256 is
`0720bf247bd76e6594ea28fa9c6f7c5242be774818997dbbeffc4da460c723bb`.
Neither the original model nor Python/desktop/WebAPI/database sources were changed.

The actual FlatBuffer has:

- UINT8 input `[1,320,320,3]`.
- FLOAT32 scores `[1,19206,90]` and locations `[1,19206,4]`.
- Embedded `labels.txt`: `person` at index 0, `cell phone` at index 76.
- `DETECTOR_METADATA` with the decoding/anchor metadata for MediaPipe's
  two-output postprocessing path. There is no in-model DetectionPostProcess op.

The two-output format is supported by the
[MediaPipe postprocessing implementation](https://github.com/google-ai-edge/mediapipe/blob/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb/mediapipe/tasks/cc/components/processors/detection_postprocessing_graph.cc).
The native iOS inference smoke test also verifies model loading and execution.
Do not assume a four-output model based on the EfficientDet filename.

Both native detectors allow only `cell phone` and `person`, use score threshold
0.15, and count persons only at confidence >= 0.5. They report the highest retained
phone confidence without temporal averaging. Latency measures only the synchronous
MediaPipe detect call, in milliseconds, matching Jorge's measurement boundary.
Full confidence precision is retained rather than rounding before validation.

Methods on `aperture/camera_detection`:

- `start({session_id: int}) -> true`: confirms camera and detector startup.
  Flutter still requires a fresh detection event before revealing content.
- `stop({session_id: int}) -> null`: releases that run's resources.

Events on `aperture/camera_detection/events`:

```json
{
  "session_id": 1,
  "phone_detected": true,
  "phone_confidence": 0.31,
  "person_count": 1,
  "latency_ms": 17.4,
  "timestamp": "2026-10-19T12:30:15.512Z"
}
```

Native timestamps use UTC ISO 8601. The parser also accepts Jorge's local ISO
timestamps. Missing/invalid values, contradictory phone flags/scores, native
errors, stream termination, and five seconds without a fresh result keep content
hidden. Run IDs prevent old frames and permission completions authorizing a new
session. Failure recovery requires an explicit camera retry or a foreground
restart with fresh policy, capture, and camera checks.

### Security and lifecycle

The route's rendering gate requires all existing controller checks and fresh
camera monitoring. A phone detection immediately removes the protected subtree
on the next Flutter frame and ends the controller session. Later clear frames,
camera retries, lifecycle transitions, and policy rechecks cannot restore that
ended session. The existing violation flow paints its warning before leaving the
route; preflight retains the phone-specific reason.

Camera monitoring starts when the content route opens, pauses when the app is
inactive/backgrounded, and releases resources on Back/disposal. Native lifecycle
hooks independently stop camera work. Inference is limited to approximately five
frames per second with late frames dropped. Person count is telemetry; it does
not independently satisfy presence or authorization policy.

Existing iOS screenshot/recording monitoring and Android FLAG_SECURE are preserved.
The camera gate cannot override a capture lock, denial, or revalidation latch.
The iOS screenshot notification is reactive and does not retroactively prevent
the first screenshot from being saved.

### Dependencies and verification

- iOS: official MediaPipe Swift package pinned to revision
  `50505c8312c7eacb1bd411cecdc4cc9fd08d53cb` (binary release 1.1.1).
  iOS deployment target remains 15.0. Use the existing Xcode workspace.
- Android: `com.google.mediapipe:tasks-vision:1.1.1`, CameraX 1.4.2.
  Existing Flutter SDK requirements are retained.

Verification on October 19, 2026:

- `flutter analyze`: no issues.
- `flutter test`: all 125 tests passed.
- Unsigned iPhone ARM build: passed with Xcode 26.6.
- ARM iPhone 17 Pro simulator XCTest: `testBundledModelRunsNativeInference` passed.
  It loads the real model and runs inference on a synthetic gray image, without
  accessing the camera. This verifies runtime compatibility, not detection accuracy.
- Android bridge and MainActivity Kotlin compilation against resolved MediaPipe,
  CameraX, Flutter, and Android interfaces: passed in the full Gradle build.
- Android NDK 28.2.13676358: repaired using Google's SDK tools. Its
  `source.properties` and toolchain are now installed. SDK command-line tools,
  Android SDK Platform 36, and an Android 15 ARM64 test image are available.
- `flutter build apk --debug`: passed. The standard debug APK is retained at
  `build/week7/aperture-week7-debug.apk`.
- iOS native camera-failure integration: passed on the iPhone 17 Pro simulator.
  A real native camera-unavailable result kept the demo placeholder hidden and
  allowed clean route exit. The two live-camera tests were skipped in this explicit no-camera mode;
  both now support physical iOS as well as Android.
- Android native model instrumentation: failed on the Android 15 ARM64 emulator
  with SIGILL at `rdsvl` inside `libmediapipe_tasks_jni.so`, before a result was
  returned. A restart without hardware acceleration requested reproduced it.
  An independent NDK instruction probe also SIGILLs at `rdsvl` without Flutter,
  MediaPipe, a camera, or a model; the guest reports SME2 despite SME=0. The native
  failure is an emulator/dependency capability mismatch. The symptoms also match
  [MediaPipe issue 6293](https://github.com/google-ai-edge/mediapipe/issues/6293).
  This is consistent with that emulator compatibility issue; physical Android
  behavior is unverified. The pinned production dependency remains 1.1.1.
- Android local JVM unit-test task: completed with NO-SOURCE, not a native test pass.
- Generic simulator builds that also request Intel x86_64 fail with the upstream
  MediaPipe binary architecture. The tested simulator command uses `ARCHS=arm64`.

### Physical iPhone test procedure

1. From this `mobile` directory, run `flutter pub get`. Connect and trust the
   iPhone, enable Developer Mode if required, then use `flutter devices` and
   `flutter run -d <iphone-device-id>`. Alternatively open `ios/Runner.xcworkspace`
   and select your iPhone. Your existing signing team and bundle identifier have
   been preserved. Xcode resolves the pinned package; CocoaPods is not required.
2. Sign in through the existing app flow, open Project Document or Private Image,
   then choose **Open Demo Preview** before running normal preflight checks.
   This explicitly labeled route shows only the existing placeholder and permits
   camera testing without inventing authorization results. The normal route must
   remain hidden while its real policy provider is unverified.
3. Allow Camera when prompted. After the permission dialog closes, wait for
   **Camera protection active** and a fresh result. Check person count and the
   inference milliseconds shown below the viewing area. In a debug build, Xcode
   or Flutter logs show `[ApertureCamera] inference latency_ms=...`; no frames or
   protected content are logged. These are debug measurements, not release benchmarks.
4. Present a second phone to the **front camera**, with its body/screen visible.
   Confirm content disappears, **Phone detected** is reported, and the session
   ends. Removing the phone and rechecking must not restore that ended session.
   Leave the entire Secure Viewer flow and open a new session for another trial.
5. In separate sessions test Camera permission denial, camera interruption,
   screen recording/mirroring, screenshot handling, Home/app switching, and Back.
   Content must remain hidden during errors and backgrounding. Resume must wait
   for fresh camera and policy checks. The iOS camera indicator must disappear
   after the viewer closes or the app backgrounds.

The paired physical iPhone 17 was unavailable to Flutter (connection error -27).
The user chose to continue without the phone. No physical launch, camera test,
or iPhone latency samples were collected. Average, minimum, and maximum physical
inference latency therefore remain unavailable.

Android packaging is verified; runtime inference remains blocked on the tested
emulator by the native SDK crash. The Android live-camera integration tests are
prepared in `integration_test/camera_detection_device_test.dart`; the two live
checks support Android and physical iOS with Camera permission granted. Android
requires a compatible runtime. They have not passed.
Full Week 7 device validation cannot yet be marked complete. The implementation
is committed and published in [draft PR #8](https://github.com/JorgeOrtizCS/aperture/pull/8),
ready for implementation review. The report preserves the historical 27-file scope;
personal signing/bundle-ID changes remain local and unstaged. The wrap-up added
only documentation, finalized in a separate documentation commit. Production
code and the PR's draft state are unchanged.

### Follow-up with Jorge

- Confirm the mobile model hash matches his tested artifact and compare detections
  on the same labeled test images. Desktop/Python and native mobile parity has
  not been measured.
- Confirm front-camera coverage and the 0.15 phone threshold on actual phones,
  including edge-on phones, low light, reflections, and false positives.
- Agree on future recovery policy if desired. Mobile conservatively ends a phone
  violation session; it does not adopt desktop's ten-clear-frame automatic reveal.
- Confirm timestamp timezone conventions for downstream consumers. Mobile emits UTC.

### Files changed

Created:

- `lib/services/camera_detection.dart`
- `ios/Runner/CameraDetectionBridge.swift`
- `android/app/src/main/kotlin/com/example/aperture/CameraDetectionBridge.kt`
- `assets/models/efficientdet_lite0.tflite` (unchanged model copy)
- `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `test/camera_detection_test.dart`
- `test/support/camera_detection_fake.dart`
- `android/app/src/androidTest/kotlin/com/example/aperture/CameraModelInstrumentedTest.kt`
- `integration_test/camera_detection_device_test.dart`
- `WEEK7_VALIDATION_REPORT.md`

Modified:

- `README.md`
- `pubspec.yaml` and `pubspec.lock` (Flutter integration-test support)
- `lib/controllers/viewing_state_controller.dart`
- `lib/screens/secure_content_viewer_screen.dart`
- `lib/screens/secure_viewer_screen.dart`
- `lib/widgets/viewing_status_panel.dart`
- `ios/Runner/AppDelegate.swift`
- `ios/Runner/Info.plist`
- `ios/Runner.xcodeproj/project.pbxproj` (existing user signing edits preserved)
- `ios/RunnerTests/RunnerTests.swift`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/example/aperture/MainActivity.kt`
- `test/secure_content_viewer_test.dart`
- `test/warning_states_test.dart`
- `test/support/viewing_test_fakes.dart`
