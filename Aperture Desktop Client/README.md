# Desktop viewing protection

Build `Aperture Desktop Client.sln` with Visual Studio/MSBuild (.NET Framework 4.7.2).
The viewer launches the existing `../camera/src/detector_service.py` as a hidden
background process and reads its JSON frame results. No Python files are modified.

From the repository root, initialize the camera environment once:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File camera\setup.ps1
```

The setup creates `camera/venv`, installs the pinned dependencies, and verifies
imports plus model inference without accessing the webcam. Rebuild and restart
the desktop client after setup. It selects `camera/venv/Scripts/python.exe`
automatically; activation is unnecessary. If no local environment exists, it uses
`python` from PATH. The model at `camera/models/efficientdet_lite0.tflite` and a
working webcam are needed for live detection. To check the webcam explicitly:

```powershell
& .\camera\venv\Scripts\python.exe .\camera\src\detector_service.py --check
```

`No module named cv2` means OpenCV is absent from the selected interpreter.
Run setup instead of installing packages into an unrelated Python environment.
Only `opencv-contrib-python` is installed because OpenCV distributions share the
same `cv2` module. `APERTURE_PYTHON`, if set, overrides the local environment.

For another environment or a deployed app, set these environment variables before
starting the desktop client:

- `APERTURE_PYTHON`: full path to the Python executable.
- `APERTURE_DETECTOR`: full path to the existing detector_service.py.

Content stays hidden during camera startup, on phones or multiple people, and on
camera errors or more than five seconds without valid frames. Ten consecutive
clear frames release the camera block. Server restrictions are checked when the
viewer opens and every five seconds thereafter. A server denial or connection
failure hides and clears content while the viewer stays open and retries.
Camera recovery cannot override a server denial, or vice versa.

Recoverable location, IP or device failures suspend the existing session. The desktop
keeps its session ID, hides and clears the content, and resumes after a passing check
without consuming another view. Expiry has a five-minute grace period for the owner
to extend the time window; revocation and terminal failures still end the session.

In a sent item's Manage dialog, use **Edit time window** or **Set allowed area**.
The Share dialog also supports latitude, longitude and radius in meters, saved
atomically with the content. Recipients can enable **Share device location** in
the viewer; Windows location permission is required. Missing or stale fixes keep
precise-location content hidden. **Hide for 30 seconds** holds the existing session
on the server; the next passing check after the hold restores it.

Run the guard regression checks after a Debug build:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\CameraPython.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\CameraGuard.Tests.ps1
```

For a live camera check without the API/login, launch the built desktop executable
with `--camera-test`. Test a phone, a second person, removing them, and a missing
or unavailable camera. For an API check, open text/image content with an expiration
and verify it becomes hidden at the next check while the viewer stays open. Also
verify access before the start time, policy pause/resume, and API disconnection.

## Sender-defined camera restrictions

In **Share New Content**, enable **Require camera-based detection for all viewers**
and select the phone, multiple-person, and/or missing-viewer rules. These choices
are saved with that item's server policy. Recipients have no camera settings that
can override the sender's rules. Existing time, location, device and view-limit
restrictions continue to apply. When camera protection is required, startup,
camera failures and stale frames also keep content hidden. The viewer remains
open and requires ten consecutive safe frames before showing content again.
With camera protection off for an item, the viewer does not launch Python.

The API stays on .NET Framework 4.7.2 and uses the existing MySQL database,
with camera and situational rules stored together in `AccessPolicy.Requirements`.
No database schema changes are required. Deploy the updated API and desktop together.
Unsupported clients are denied camera-restricted content.

Camera-policy support is declared by the client (`CameraPolicyVersion = 1`);
the API stores and distributes the rules and the desktop enforces frame results.
This is not camera attestation or protection against a modified client. Mobile
camera enforcement is not implemented; unsupported clients are denied these items.
The Python detector is unchanged.

Run `Aperture WebAPI/tests/SituationalAwareness.Tests.ps1` after building the API.
`Run-SituationalApiTests.ps1` in that folder runs end-to-end checks using a disposable
local MySQL server and IIS Express; it never changes the configured application database.
The older CameraPolicy.Api test targets the historical SQL Server schema.
