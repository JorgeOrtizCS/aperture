# Week 7 mobile device acceptance procedures

Prepared October 19, 2026. **All physical tests below are NOT RUN.** These are
procedures, not results. Validate implementation baseline
`30a8ed664dc08694085a726f1f054d10256c68e1` or its documentation-only descendant;
record the actual tested revision.
Use the existing placeholder demo and no sensitive content.

## Recording and pass/fail rules

Record tester/date, device model, OS/build, app commit, debug/release mode,
MediaPipe version, model hash, trial ID, lighting, phone position/distance,
observed warning/exit/recovery, logs and PASS/FAIL/BLOCKED/NOT RUN for each row.
Never convert a skipped test, successful APK build or unavailable device into a
runtime pass. Keep live-camera and synthetic-image results separate.

The fixed trial durations/repetition counts below define a proposed reproducible
test protocol, not previously agreed product latency/accuracy requirements.
Jorge must approve coverage and performance budgets before full acceptance.
Use a fresh complete Secure Viewer flow between tests unless a step explicitly
checks persistence within the same flow. A violation is latched for the current
viewer/controller session, not across new flows, app restarts or accounts.

Run commands from the repository's `mobile/` directory. Choose IDs from actual
tool output; do not run placeholder IDs. Logs belong under ignored `build/week7/`.

```sh
mkdir -p build/week7/device
flutter devices
git rev-parse HEAD
shasum -a 256 assets/models/efficientdet_lite0.tflite
```

Expected model SHA-256:
`0720bf247bd76e6594ea28fa9c6f7c5242be774818997dbbeffc4da460c723bb`.

## iPhone setup and native-camera smoke test

1. Connect/trust an available physical iPhone and enable developer access as
   prompted. Configure development signing locally in `ios/Runner.xcworkspace`.
   Keep personal team/bundle-ID edits unstaged. An unsigned build cannot be
   installed as a signed device acceptance build.
2. Set the actual device ID and run the app:

   ```sh
   IPHONE_DEVICE_ID='replace-with-actual-flutter-device-id'
   set -o pipefail
   flutter run --debug -d "$IPHONE_DEVICE_ID" 2>&1 | tee build/week7/device/iphone-live.log
   ```

3. Tap **Get Started**. The current login screen is a placeholder that accepts
   nonempty values; use `week7-demo` / `placeholder`, not a real account password.
   Open **Project Document**, then **Open Demo Preview** before pressing
   **Check Conditions**. This is deliberately a placeholder-only route.
4. Grant Camera. Keep other phones outside the front camera's field of view.
   Permission prompts can interrupt startup; if content stays hidden afterward,
   use **Retry camera protection** once permissions are granted. Record whether
   a retry was necessary. Require a new valid frame before content appears.
5. Close the demo, confirm the camera stops, and quit `flutter run` with `q`.
   Camera permission remains available for the native integration test.
6. Run the existing device test with the simulator-only flag explicitly false:

   ```sh
   flutter test integration_test/camera_detection_device_test.dart \
     -d "$IPHONE_DEVICE_ID" --dart-define=APERTURE_EXPECT_NO_CAMERA=false \
     --reporter expanded 2>&1 | tee build/week7/device/iphone-integration.log
   ```

**PASS:** two live-camera tests pass and only the simulator camera-failure test is
skipped. The service collects at least ten finite/nonnegative live-camera latency
samples within its 30-second test timeout, emits valid contract fields, reports
stopped after stop acknowledgement, and the viewer removes its protected subtree
on route exit. The log contains `[ApertureDeviceTest]` live-camera statistics.
**FAIL:** native crash, stream/startup error, timeout, protected content before a
valid result, or any live-camera test unexpectedly skipped. A no-camera simulator
run is a separate test and cannot satisfy this gate.

The integration suite assumes camera permission is already granted and a clear
scene. It does not exercise the initial permission dialog, a real phone-positive
trial, hardware screenshot behavior or the camera indicator. Test those below.

## Android setup, native inference and live-camera smoke test

Use a physical Android device with developer/USB debugging enabled and authorize
the computer. The known Android 15 ARM emulator SIGILL is a failed runtime result,
not a compatible test substitute. Only target the selected device.

```sh
adb devices -l
ANDROID_DEVICE_ID='replace-with-actual-adb-and-flutter-device-id'
set -o pipefail
flutter build apk --debug
adb -s "$ANDROID_DEVICE_ID" install -r build/app/outputs/flutter-apk/app-debug.apk
```

**PASS setup:** app installs/launches on that physical device. Build success alone
does not pass inference. The committed Android application ID is
`com.example.aperture`.

Build/install the instrumented model test, then execute only its class:

```sh
(cd android && ./gradlew :app:assembleDebugAndroidTest)
adb -s "$ANDROID_DEVICE_ID" install -r build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s "$ANDROID_DEVICE_ID" shell am instrument -w -r \
  -e class com.example.aperture.CameraModelInstrumentedTest \
  com.example.aperture.test/androidx.test.runner.AndroidJUnitRunner \
  2>&1 | tee build/week7/device/android-model-test.log
adb -s "$ANDROID_DEVICE_ID" logcat -b crash -d > build/week7/device/android-crash.log
```

Use the JDK selected for the successful existing Gradle build if Gradle cannot
start. **PASS native inference:** `OK (1 test)` with all five detect calls returned,
no process crash and valid assertions. This is gray-image runtime compatibility,
not physical-camera accuracy. **FAIL:** SIGILL, JNI load failure, instrumentation
process crash, assertion failure or missing completion. Inspect the failure; do
not downgrade or patch the production binary simply to obtain a green test.

Pre-grant Camera for the automated tests, then run both live-camera checks:

```sh
adb -s "$ANDROID_DEVICE_ID" shell pm grant com.example.aperture android.permission.CAMERA
flutter test integration_test/camera_detection_device_test.dart \
  -d "$ANDROID_DEVICE_ID" --dart-define=APERTURE_EXPECT_NO_CAMERA=false \
  --reporter expanded 2>&1 | tee build/week7/device/android-integration.log
```

**PASS:** both live-camera tests pass, only the iOS simulator-only test is skipped,
valid live frames/latencies arrive, stop acknowledgement prevents more events,
and the viewer exits cleanly. **FAIL:** crash, timeout, invalid events, false
phone-positive in the controlled clear scene, unexpected skip, or content shown
without a fresh result. Run manual tests in the ordinary app afterward:

```sh
flutter run --debug -d "$ANDROID_DEVICE_ID" 2>&1 | tee build/week7/device/android-live.log
```

Use the same placeholder login/demo navigation as iOS. To test initial permission
denial separately, exit the viewer, revoke Camera in Android app settings, return
and open a new flow. Do not use pre-granted permission as evidence that denial
handling works.

## Manual acceptance matrix for each platform

| ID | Exact trial | PASS / FAIL criterion |
| --- | --- | --- |
| M1 Startup gate | Open a new demo with no phones in view; observe startup and one fresh result. | PASS only if placeholder stays hidden while checking, then camera status is active with metrics. No valid event or any early reveal is FAIL. A permitted fail-closed retry must be recorded. |
| M2 No-phone baseline | In ordinary indoor light, remain in a clear scene for 30 seconds; repeat in three new flows. | PASS if camera metrics continue with no phone violation, crash or stall in all three trials. Any false phone violation fails that baseline trial. Person count alone is not authorization. |
| M3 Positive/lockout | In a new flow, show a second phone face-on at approximately 0.5 m for up to 10 seconds. Repeat three times, each in a new flow. | PASS per trial if a real phone event hides the placeholder and ends the flow while the phone is shown. No detection during the observation window is FAIL for that scenario. No claim of a 10-second product response-time requirement is made. |
| M4 Violation persistence | After M3, remove the phone; wait at least ten seconds, attempt preflight recheck, then background/resume without leaving the ended Secure Viewer flow. | PASS only if the same flow remains access denied, phone reason is retained and clear frames/recheck/resume cannot reopen it. New full flows are separate sessions. Any same-flow reveal is FAIL. |
| M5 Permission denial/revoke | With Camera denied in system settings, open a new demo; try Retry. Then grant Camera and retry in an unviolated flow. | PASS if denial keeps content hidden with an appropriate unavailable/permission warning and no camera activity; grant alone cannot reveal before fresh checks. Crash or reveal while denied is FAIL. |
| M6 Foreground lifecycle | With a clear scene and active demo, send app Home, return, then repeat once with a system interruption/control panel. | PASS if protected content is hidden while inactive, camera use stops, and resume waits for fresh monitoring/checks. Use the five-second cleanup observation window below; any stale reveal or continued own-camera use after cleanup is FAIL. |
| M7 Route cleanup | From active monitoring, tap Back/Close viewer. Wait five seconds, then open a fresh demo and close it again. | PASS if no protected subtree persists during the outgoing transition, own-camera activity ends within the observation window, and a fresh flow can acquire/release the camera. A stuck indicator or new camera-busy failure is FAIL. |
| M8 iOS screenshot | In a new active demo, take a hardware screenshot. | PASS current design if a screenshot warning ends the flow and recheck cannot reopen it. The first screenshot may already contain the placeholder: this mechanism is reactive and does not pass preventive screenshot blocking. Missing notification/lockout is FAIL. |
| M9 iOS recording/mirroring | Start recording before opening a fresh demo; separately start recording while active. Inspect the saved test recording. Test mirroring if a receiver is available. | PASS if protected content stays hidden/locks on capture and no protected placeholder remains in captured frames after the capture-state change is handled. After capture stops, require a condition recheck before reveal; camera frames alone cannot release the lock. Any exposure after handling is FAIL. Note transition timing and the already-documented reactive limit. Mirroring with no receiver is BLOCKED, not PASS. |
| M10 Android capture | In a new active demo, attempt a hardware screenshot and a system screen recording; inspect actual artifacts. | PASS if FLAG_SECURE prevents capture or renders the protected app surface blank. Android does not promise a screenshot-event warning/session latch. A readable protected app surface is FAIL. Reopen the viewer for each trial if recording controls interrupt it. |
| M11 Multiple orientations | In three fresh clear flows, rotate portrait -> landscape left -> landscape right; then perform a face-on phone-positive trial in each orientation. | PASS if monitoring survives rotation, never reveals during an invalid state, and each positive trial triggers lockout. Record rotation-related failures separately from general detector misses. |

The five-second cleanup observation window is a proposed test cutoff, not an OS
indicator timing guarantee. Ensure no other app is using the camera. On Android
versions with a camera privacy indicator, verify it; otherwise inspect camera
service ownership (`adb -s "$ANDROID_DEVICE_ID" shell dumpsys media.camera`)
before/during/after. Returning from a real interruption may require retry; it must
remain fail-closed. Do not fabricate a production stream error by injecting fake
clear events: stream errors/stalls are covered by existing automated tests.

For capture transitions, record whether any placeholder frame was captured before
the app handled the OS notification. Such a result documents a reactive-protection
limitation; it cannot be presented as zero-frame capture prevention. Final security
acceptance of that limitation belongs to the team.

## Camera coverage worksheet — Jorge to approve

For each platform record three new-flow trials per chosen condition: distances
0.3/0.6/1.0 m; face-on/45-degree/edge-on phone; lit/dark screen; ordinary/dim/backlit
scene; portrait/landscape. Change one factor at a time from the baseline and
record actual distance/light description. Use the ten-second M3 observation
window. Mark each trial detected/not detected and record false-positive baseline
trials with no phone. These are proposed coverage probes, not agreed product
requirements. Do not average away missed trials or declare overall accuracy
accepted until Jorge selects the required cells and acceptance rates. The app
does not save camera frames; any shared fixtures need separate explicit consent.

## Physical inference latency measurement

The smoke test's `[ApertureDeviceTest]` summary is at least ten **live-camera**
samples. Record count/average/minimum/maximum separately for each device.
For a more repeatable sample, run the ordinary debug app in a stationary clear
scene for at least 60 seconds using `iphone-live.log` or `android-live.log` above.
Do not background it or introduce a phone during collection. Collect the first
110 native `[ApertureCamera]`/`ApertureCamera` inference log lines, discard ten
warm-up samples, and summarize the next 100:

```sh
python3 - build/week7/device/iphone-live.log <<'PY'
import json, math, re, statistics, sys
from pathlib import Path
values = []
for line in Path(sys.argv[1]).read_text(errors='replace').splitlines():
    if 'ApertureCamera' not in line or 'ApertureCameraTest' in line:
        continue
    match = re.search(r'inference latency_ms=([^\s]+)', line)
    if match:
        value = float(match.group(1))
        if not math.isfinite(value) or value < 0:
            raise SystemExit('FAIL: invalid sample')
        values.append(value)
if len(values) < 110:
    raise SystemExit(f'INCOMPLETE: {len(values)} samples; need 110')
samples = values[10:110]
print(json.dumps({'input': 'live_camera', 'build_mode': 'debug',
                 'warmup_discarded': 10, 'count': len(samples),
                 'average_ms': statistics.mean(samples),
                 'minimum_ms': min(samples), 'maximum_ms': max(samples)}, indent=2))
PY
```

For Android substitute `build/week7/device/android-live.log`. If native logs are
not forwarded into the Flutter log, collect the same app's native logs with
Xcode (iOS) or `adb logcat` (Android); keep other runs and synthetic-test lines
out of the input. **PASS measurement validity:** at least 110 real-camera native
samples, 100 summarized after warm-up, finite/nonnegative values, device/build
metadata attached, no mixed synthetic results. Otherwise INCOMPLETE/FAIL.
No numerical latency budget has been agreed: performance acceptance stays PENDING
Jorge/team approval. Inference timing excludes capture, transport, Flutter paint
and time-to-lockout; measure those separately before making response-time claims.

## Result sheet (leave blank until executed)

| Device / OS / app commit | Native smoke | Live tests | M1–M11 applicable results | Latency n / avg / min / max | Coverage / reviewer decision |
| --- | --- | --- | --- | --- | --- |
| iPhone: NOT RUN | NOT RUN | NOT RUN | NOT RUN | No physical samples | PENDING |
| Android: NOT RUN | NOT RUN | NOT RUN | NOT RUN | No physical samples | PENDING |

Attach actual logs, results and failure details when executed. The Android emulator
failure remains recorded in `WEEK7_VALIDATION_REPORT.md`; it is not overwritten by
this blank physical-device worksheet.
