# Aperture Web API

ASP.NET Web API 2 on **.NET Framework 4.7.2**, with MySQL and Newtonsoft.Json. Open `Aperture WebAPI.sln` in Visual Studio on Windows, restore NuGet packages, and run with IIS Express (default `https://localhost:44353/`). Set the `Database` connection string in `Aperture WebAPI/Web.config` to the existing database. The hosted tables live in **APERTURE_DB**, not the empty hosted default `railway`.

No database migration is required. The API uses the existing schema in `../db/schema.sql`, with all viewing restrictions stored in **AccessPolicy.Requirements**. The SQL Server diagram and camera migration scripts are historical. Back up `App_Data/ContentFiles` with the database: MySQL stores metadata, while that directory stores the file bytes.

## Viewing conditions

Senders share text or PNG/JPEG images (up to 5 MB), setting an optional UTC start/expiry window, positive maximum views per recipient, device approval, location and camera requirements. Null maximum views means unlimited. Existing client request fields remain supported.

The location rule can use country/region/city (IP geolocation) or latitude, longitude and radius in meters (device-reported location). Precise location is saved atomically with the original share. Recipients send `X-Client-Latitude` and `X-Client-Longitude` on open and every check. Missing or invalid coordinates deny access. Distances use the haversine formula; being outside the area suspends an open session until a later check passes.

Existing sessions are checked every five seconds. A recoverable failure hides the content but retains the session ID and view count. Passing every condition restores the same session. Responses explicitly report `Suspended` and `SessionEnded`. The suspension status endpoint reports the reason, source and hold deadline.

An owner can edit the time window or precise area after sharing; JSON updates preserve camera and other rules. On expiry, an existing session hides its content for a **five-minute extension grace period**. An owner extension during that time lets the next passing check restore it. New sessions cannot open expired content. After the grace period, the session ends.

Senders or recipients can manually suspend a session for 1?3600 seconds (default 30). A manual hold never bypasses revocation, invalid policies or terminal expiry. Pause and revocation end open sessions immediately. An IP change, missing device approval, geographic mismatch or missing GPS fix can recover; malformed policies, unknown JSON versions, unsupported camera clients, screenshot requirements and geolocation-provider failures remain denied and terminate an existing session.

Camera rules come from the sender, are distributed by the API and enforced by the desktop. Compatible clients declare `CameraPolicyVersion = 1`. The React client does not claim camera support, so it cannot open camera-restricted content. Run `../camera/setup.ps1` once to set up the desktop detector; see the desktop README.

## Routes

All routes except registration and login require a bearer token.

- `POST /api/register`, `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/user/me`.
- `GET /api/content`, `POST /api/content`, `GET /api/content/capabilities`.
- `POST /api/content/{id}/policy` (owner pause/resume), `POST /api/content/{id}/revoke` (owner).
- `POST /api/devices` registers a client key as untrusted; repeated registration preserves approval. The existing schema stores `Desktop:<guid>` in `TrustedDevices.DeviceType`.
- `POST /api/content/{id}/sessions`, `POST /api/content/sessions/{sessionId}/check`, `POST /api/content/sessions/{sessionId}/end`.
- `POST /api/situational/content/{id}/time` (owner, `StartTime`/`ExpiresAt`, null removes a limit); `GET` on the same route checks the window for sender or recipient.
- `POST /api/situational/content/{id}/location` (owner, `Latitude`/`Longitude`/`RadiusMeters`).
- `POST /api/situational/sessions/{sessionId}/suspend` (sender or recipient, optional `Reason` and `DurationSeconds`); `GET /api/situational/sessions/{sessionId}/suspension`.

## State and deployment

Login tokens, session IP/device bindings and suspension details live in one IIS worker's memory. An app-pool recycle invalidates them. Use one worker for this prototype. All metadata writes and environment checks are parameterized MySQL commands. The server observes the socket peer IP and does not trust forwarded headers; a proxy deployment needs an explicit trusted-proxy design. The Vite development proxy therefore binds sessions to its own peer address.

The `IpGeolocationUrl` setting defaults to ipapi.co over HTTPS, caching successful results for 15 minutes. Private/loopback development requests use the API machine's outbound public IP. Lookup errors deny access. IP and client-reported GPS positions are approximate and spoofable; they are not physical-location attestation. The desktop cannot prevent operating-system screenshots, so screenshot-restricted content is refused. Previously copied bytes cannot be recalled.

## Validation

```powershell
msbuild "Aperture WebAPI.sln" /t:Build /p:Configuration=Debug
powershell -NoProfile -ExecutionPolicy Bypass -File tests\SituationalAwareness.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-SituationalApiTests.ps1
```

The unit checks cover GPS validation, time windows, expiry grace, suspension and JSON preservation of camera policies. The HTTP suite requires local MySQL 8, IIS Express and Python; it creates an isolated temporary database instance and site, tests real registration/sharing/viewing endpoints, then stops them and removes their files. It never connects to or modifies the database configured in Web.config. Paths can be supplied through the script parameters. The old desktop `CameraPolicy.Api.Tests.ps1` targets the historical SQL Server schema and should not be run against this version.
