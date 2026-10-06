# Aperture Web API — SQL Server diagram edition

This version targets **ApertureDB** created by `Aperture_Diagram_Database.sql` (included beside the solution). The project targets **.NET 8 / ASP.NET Core** and runs on macOS, Linux and Windows. Back up `App_Data/ContentFiles` (created automatically on first share, under the project folder) **with** the SQL database: SQL holds metadata, not file bytes.

## Running locally

Requirements: the .NET 8 SDK and Docker Desktop. On Apple Silicon, Docker runs the x86-64 SQL Server image through Rosetta.

1. Start SQL Server and create the schema: `docker compose up -d`, run in this folder. On the first start, the one-shot `db-init` service runs `Aperture_Diagram_Database.sql`; on later starts it sees the tables and does nothing. `docker compose down` stops it and keeps the data; `docker compose down -v` deletes the data too.
2. Run the API: `dotnet run --project "Aperture WebAPI"`. It listens on `https://localhost:44353` (the URL the desktop client expects) and `http://localhost:5080`. For HTTPS without warnings, trust the development certificate once with `dotnet dev-certs https --trust`.
3. Open Swagger at <http://localhost:5080/swagger> (Development only) to browse and try every route; the OpenAPI spec is at `/swagger/v1/swagger.json`. Log in with `POST /api/auth/login`, click **Authorize**, and paste the `Token`. You can also use `Aperture WebAPI.http` (VS Code REST Client extension), or point the desktop client at the API.

In VS Code, the **Web API (ASP.NET Core)** launch configuration builds and debugs the API, and the `webapi: start database` task runs step 1.

The Development connection string in `appsettings.Development.json` uses the container's local-only `sa` login. The password is a development default shared with `docker-compose.yml`; override both together with `APERTURE_SA_PASSWORD` and `ConnectionStrings__Database`. `appsettings.json` keeps the Windows default (`Trusted_Connection` to a local SQL Server). Any environment can override the `Database` connection string and `IpGeolocationUrl` with environment variables.

The UI supports account creation and login, text and PNG/JPEG sharing (maximum image size 5 MB), recipient dashboard, start/expiry time, optional one-view limit, approved-device requirement, viewing sessions bound to the opening client IP, rechecks every five seconds, owner pause/resume and revocation, and request/audit and environment-check records. Camera viewing/capture is not included. Viewing images is for already-selected local image files.

The diagram has no token table. Login bearer tokens and the viewing-session-to-device association are held **in the API process's memory**; restarting the API invalidates logins and viewers. Run a single instance for the demo. `MaximumViews` is `BIT` in the supplied diagram, so `1` means **one view** and `0` means unlimited. A recipient can register a device, but registration starts untrusted. The locally stored device identifier is a demo identifier and can be copied; it is not hardware attestation. An administrator can explicitly approve it with SQL (SSMS, Azure Data Studio, or `docker compose exec db /opt/mssql-tools18/bin/sqlcmd -C -U sa`):

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

## Continuous IP verification

When a recipient opens content, the API records the client IP observed by the server for that in-memory viewing session. Every `/check` request must arrive from the same normalized address. A change writes an `EnvironmentCheck` row with `LocationVerified = 0`, `PolicySatisfied = 0`, and `ViolationType = 'Client IP address changed during the viewing session.'`; the API then revokes that viewing session and the desktop closes its viewer. Loopback IPv4 and IPv6 are normalized together for local testing.

The implementation deliberately does **not** trust `X-Forwarded-For`. If the API is later deployed behind a reverse proxy, the API will see the proxy IP until a specific trusted-proxy configuration is designed. Do not blindly accept forwarded headers, because clients can spoof them. Mobile networks, VPN changes, DHCP changes, and switching Wi-Fi may legitimately change a public IP and will terminate the session. IP verification is an additional signal, not proof of identity or physical location. The binding is in memory because the approved schema has no session-IP column; an API restart invalidates it just like the existing in-memory login/session state.

## Geographic restrictions by IP

The Share dialog accepts an optional country, state/region, and city. Country accepts either a name such as `United States` or a code such as `US`; state/region accepts a full name such as `Florida` or a provider region code such as `FL`; city is an exact case-insensitive name. Blank levels are unrestricted. The policy is JSON stored in `AccessPolicy.RequiredLocation` and is evaluated on session open and every five-second check.

The API looks up the server-observed IP through the HTTPS endpoint configured by `IpGeolocationUrl` in `appsettings.json`. The included development setting uses ipapi.co and caches a result for 15 minutes to avoid a lookup every five seconds. If the provider times out, rejects the IP, exhausts its quota, returns invalid data, or the geographic fields do not match, access fails closed and the session is revoked. For localhost/private-LAN testing, the provider sees the API machine's outbound public IP because private addresses cannot be geolocated. In a real direct deployment, the recipient's public source IP is used.

The free provider is intended only for development/testing and documents a quota. Replace `IpGeolocationUrl` or the service implementation for production. The server intentionally ignores `X-Forwarded-For`; deployment behind a reverse proxy requires an explicit trusted-proxy design. IP location is approximate and may be wrong for VPNs, mobile networks, corporate gateways, or ISP routing. It does not prove a physical address.
