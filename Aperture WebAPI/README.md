# Aperture Web API — SQL Server diagram edition

This version targets **ApertureDB** created by `Aperture_Diagram_Database.sql` (included beside the solution). Use SQL Server Management Studio to run that script against a fresh server/database. The project targets .NET Framework 4.7.2 and ASP.NET Web API 2; open `Aperture WebAPI.sln` in Visual Studio on Windows, restore NuGet packages, and launch with IIS Express. Set `Web.config`'s `Database` connection string to your instance. The desktop project's `Program.cs` must point to the resulting API HTTPS URL (default `https://localhost:44353/`). Grant the IIS Express/app pool identity write access to `App_Data/ContentFiles`; it is created automatically on first share. Back up that directory **with** the SQL database: SQL holds metadata, not file bytes.

The UI supports account creation and login, text and PNG/JPEG sharing (maximum image size 5 MB), recipient dashboard, start/expiry time, optional one-view limit, approved-device requirement, viewing sessions, rechecks every five seconds, owner pause/resume and revocation, and request/audit and environment-check records. Camera viewing/capture is not included. Viewing images is for already-selected local image files.

The diagram has no token table. Login bearer tokens and the viewing-session-to-device association are held **in one IIS worker's memory**; recycling the worker invalidates logins and viewers. Use one worker process for the demo. `MaximumViews` is `BIT` in the supplied diagram, so `1` means **one view** and `0` means unlimited. A recipient can register a device, but registration starts untrusted. The locally stored device identifier is a demo identifier and can be copied; it is not hardware attestation. An administrator can explicitly approve it in SSMS:

```sql
USE ApertureDB;
SELECT DeviceID, UserID, DeviceName, DeviceIdentifier, IsTrusted FROM dbo.TrustedDevices;
-- Review the user and device first; replace the ID below.
UPDATE dbo.TrustedDevices SET IsTrusted = 1 WHERE DeviceID = 123;
```

The desktop cannot reliably prove location or prevent screenshots. If a policy's `RequiredLocation` or `ScreenshotRestriction` is set in SQL or by another client, this API **denies** viewing rather than claiming that it verified the requirement. Text and image bytes already displayed or copied cannot be remotely erased; recurring checks control continued display in this app, not previously obtained copies. Do not expose the server's `App_Data` directory or use this prototype to protect real confidential documents.

## Routes

- `POST /api/register`: `{ "firstName":"A", "lastName":"B", "username":"ab", "password":"..." }`
- `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/user/me`.
- Authenticated `GET /api/content` and `POST /api/content` to list and share.
- Authenticated `POST /api/content/{id}/policy` to pause/resume and `POST /api/content/{id}/revoke` (owner only).
- Authenticated `POST /api/devices` registers the current desktop device as **untrusted**.
- Authenticated `POST /api/content/{id}/sessions` opens a recipient session, `POST /api/content/sessions/{sessionId}/check` rechecks, `POST /api/content/sessions/{sessionId}/end` closes.

Run this version with the *diagram* database script, not the previous prototype schema drafts. Previous content data is not migrated.
