# Desktop viewing protection

Build `Aperture Desktop Client.sln` with Visual Studio/MSBuild (.NET Framework 4.7.2).
The viewer launches the existing `../camera/src/detector_service.py` as a hidden
background process and reads its JSON frame results. No Python files are modified.

Install the camera project's requirements in your Python environment. The detector
also needs `camera/models/efficientdet_lite0.tflite` and a working webcam. By default
the client uses `python` from PATH and searches parent folders for the script.
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

The current API ends a session when a policy check fails. The desktop requests a
new authorized session on its next retry. A one-view policy can consequently keep
the content hidden after a terminated session; the desktop honors that decision.

Run the guard regression checks after a Debug build:

```powershell
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

For an existing SQL Server database, apply
`../Aperture WebAPI/Add_Camera_Restrictions.sql` before deploying the API; the
migration is safe to rerun and preserves existing content with camera checks off.
New databases use `../Aperture WebAPI/Aperture_Diagram_Database.sql`, which includes
the new columns. The local configured `localhost/ApertureDB` was migrated during
implementation. Deploy the updated API and desktop together. Older/mobile clients
without camera-policy support are denied camera-restricted content. The sender
also checks API capabilities before sharing restricted content, so an old API
cannot silently ignore the new settings.

Camera-policy support is declared by the client (`CameraPolicyVersion = 1`);
the API stores and distributes the rules and the desktop enforces frame results.
This is not camera attestation or protection against a modified client. Mobile
camera enforcement is not implemented; unsupported clients are denied these items.
The Python detector is unchanged.

After building the desktop and API, run the SQL/API regression checks as well:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\CameraPolicy.Api.Tests.ps1
```

This test needs an existing shared item in the configured local database and
rolls back all temporary policy changes. It checks stored camera flags, rejection
of unsupported clients, and preservation of the existing access restrictions.
