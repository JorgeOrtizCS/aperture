# Aperture Web

React web client for Aperture. It follows the mobile app's design and flow (welcome, sign in, dashboard, share, content status, secure viewer, notifications) and talks to the real Web API.

## Run it

1. Start the Web API and its database. See [Aperture WebAPI/README.md](../Aperture%20WebAPI/README.md); the API must answer on `http://localhost:5080`.
2. Start the web app:

   ```bash
   cd web
   npm install
   npm run dev
   ```

3. Open <http://localhost:5173>.

The dev server proxies `/api` to the Web API, so no CORS setup is needed. To point the proxy at another address, set `APERTURE_API_URL` (for example `APERTURE_API_URL=http://localhost:5080 npm run dev`).

Other scripts: `npm run build` (type-check and production build into `dist/`), `npm run lint`, and `npm run preview`.

## Pages

| Route | Mobile counterpart | What it does |
|---|---|---|
| `/` | Welcome | Entry point |
| `/login`, `/register` | Login | Sign in (`POST /api/auth/login`), create an account (`POST /api/register`) |
| `/dashboard` | Dashboard | "Shared With Me" and "My Shared Content" from `GET /api/content` |
| `/share` | Share Content | Text or a PNG/JPEG image (up to 5 MB) for one recipient, with access start, expiration, one-view limit, approved device, screenshot restriction, and a region or exact-area (GPS radius) location rule |
| `/content/:id` | Content Status | The sender's view: status, time window, pause/resume, revoke, edit the time window, set an exact area |
| `/view/:id` | Secure Viewer | The recipient's view: condition checks, register this browser as a device, open a viewing session, recheck every 5 seconds with the browser's location, hide for 30 seconds, end viewing |
| `/activity` | Notifications | Access decisions and policy changes seen by this browser |

## How the secure viewer behaves

- Opening content creates a viewing session (`POST /api/content/{id}/sessions`) with this browser's device key and, when allowed, its GPS position.
- Every 5 seconds the viewer rechecks the session (`POST .../check`), sending the latest position. The content is shown only while the server grants access:
  - When a condition fails and can recover, for example the viewer leaves the allowed area, the content is hidden and comes back automatically on the next passing check.
  - When the content is paused, revoked or expires, the session ends.
- "Hide for 30 seconds" suspends the session on the server (`POST /api/situational/sessions/{id}/suspend`).
- The content is also hidden while the browser window is in the background, it can't be printed, and dragging and the right-click menu are blocked. A browser cannot block screenshots or a photo of the screen. Content with "Screenshot protection" is therefore refused by the server in the web viewer, as in the desktop client.

## State kept in the browser

| Key | Storage | Purpose |
|---|---|---|
| `aperture.session` | sessionStorage | Bearer token and user. The API keeps logins in memory, so a restart signs everyone out and the app returns to the sign-in page. |
| `aperture.deviceKey` | localStorage | This browser's device key: a demo identifier, not hardware attestation. |
| `aperture.activity` | localStorage | The last 50 activity events for the Notifications page. |

## Not supported yet

- The mobile prototype's download and resharing toggles, and its 3- and 5-view limits, have no API behind them, so they are not offered.
- The API has no endpoint for a single item's full policy. The status page shows what the API returns: status, sharing state and time window.
