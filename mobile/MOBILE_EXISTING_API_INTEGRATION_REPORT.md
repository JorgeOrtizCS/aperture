# Aperture mobile integration against the existing API

Local branch `rylee/mobile-integration` is based on draft PR #16 at `9f5d4a2b81948e549e232c670fbd60b7d22423bf`. The API reference is remote `main` at `9c7996fcf610948d18cc24a6b986458e050a12d9`. Contract checks used the C# controllers, DTOs, storage implementation, checked-in HTTP examples, and situational-awareness tests. [Published baseline](https://github.com/JorgeOrtizCS/aperture/pull/16) · [API source revision](https://github.com/JorgeOrtizCS/aperture/tree/9c7996fcf610948d18cc24a6b986458e050a12d9)

## Functionality connected

| Workflow | Local implementation and verification |
| --- | --- |
| Sender draft and PNG creation | The normal draft now retains and reviews an optional start time and the service-approved-device requirement. Zoned input is serialized as UTC. The existing native PNG picker and M01 fixture submission send the flat `POST /api/content` DTO with `StartTime`, `ExpiresAt`, `RequireTrustedDevice`, PNG Base64, recipient, and the previously supported policy fields. The fixture uses the source acknowledgement shape `{"id": 41}`. A draft regression exercises both new inputs together through dispatch. |
| Recipient open, check, and end | The existing authenticated session lifecycle now recognizes documented policy denials and the check endpoint's explicit HTTP 403 session expiry. Mobile shows local copy for recognized reasons and a generic denial for opaque responses. It keeps session termination, fresh account and identity checks, and default-deny behavior. Arbitrary response text and payload fields are discarded by the access-decision model. |
| Existing-content owner time edits | Content Status opens the owner-only editor. The editor first reads lowercase `startTime` and `expiresAt` from `GET /api/situational/content/{id}/time`. The POST sends PascalCase nullable `StartTime` and `ExpiresAt` with explicit null for a removed bound. A `{"success": true}` acknowledgement is followed by a dedicated read-back and a listing refresh. The UI distinguishes matching read-back, failed or different read-back, and an unconfirmed write. |
| Owner ordering and stale results | Time edits use the same account/content hold as Pause, Resume, Revoke, and area edits. A potentially dispatched write stays unconfirmed across route exit, same-account relogin, and GET requests. Refresh remains read-only, and unrelated items or accounts stay independent. Terminal revocation regressions still pass. |

## Files changed

- Sender draft and UI under `lib/screens/viewing_requirements_screen.dart`, `lib/services/share_upload_draft.dart`, `lib/widgets/content_restrictions_section.dart`, and `lib/widgets/content_restrictions_summary.dart`.
- Contract and session handling under `lib/models/api_models.dart`, `lib/services/api_service.dart`, `lib/services/api_session.dart`, and `lib/services/api_viewing_conditions.dart`.
- Owner navigation and time editing under `lib/screens/api_content_screens.dart` and the new `lib/screens/api_time_edit_screen.dart`.
- Regression coverage under `test/secure_upload_test.dart`, `test/viewing_requirements_test.dart`, `test/api_viewing_security_test.dart`, `test/api_session_test.dart`, and `test/api_ui_test.dart`.

## Verification

- Flutter analysis reported no issues.
- The final focused run passed 312 tests across sender upload and policy, responsive layout, account and owner controls, location edits, and recipient lifecycle and security.
- The complete host suite passed 919 tests, up from 909 on the published baseline. Dart format and `git diff --check` passed.

The normal entry point remains `lib/main.dart`. Normal **Share Securely** stays disabled and protected rendering stays locked. Android and iOS camera, capture, biometric, location, and picker integrations were preserved. This run used synthetic fixtures and made no hosted API calls, physical-device runs, or deployments.

## Source mismatches and remaining work

| Requirement | Source evidence and minimum needed | Owners |
| --- | --- | --- |
| Pre-transmission encryption and conditional release, SRS §1 and §3.1.5 | `ContentController.Create` accepts readable PNG Base64 and `ContentStorage.Write` encrypts it with `MachineKey.Protect` after receipt. `Open` and `Check` return readable payload after the server's checks. A reviewed encrypted create and conditional release flow must bind the item, recipient, policy, and current authorization before mobile can enable either protected path. | Colby and Kyra for API and storage, Rylee for mobile |
| Screenshot, camera and authoritative device/location checks | `ContentController.Evaluate` refuses all screenshot-restricted viewing and requires camera protocol v1 when the policy enables it. Mobile advertises 0. The server uses a registered `Desktop:<guid>` key, and `LocationCheck` uses coordinate headers without mobile freshness and accuracy evidence. Verify mobile-compatible capture and camera capabilities, approved device and biometric assurance, and the authoritative location rule before protected release. | Colby and Daniel, with Jorge for camera, Kyra for device provisioning, and Rylee for mobile verification |
| Recipient consent and recovery, SRS §3.1.3, §3.1.4 and §3.1.6 | Session requests carry the device key and camera version, with no consent bound to the policy shown to the recipient. The server can suspend an expired window for five minutes. Mobile ends that session and requires a fresh open. Agree how to bind recipient consent, resume an eligible session with fresh checks, and distinguish suspension from terminal denial. Temporary access request and approval, sender notifications, nearby-device checks, and external-display enforcement remain open. | Daniel and Colby for policy and API, Jorge and Rylee for device signals and mobile |
| Uncertain writes and urgent revocation | The owner endpoints expose resource read-back and acknowledgement. A matching resource GET cannot prove the outcome of a particular unacknowledged write. The local hold blocks competing writes, including Revoke, for that content. An authoritative outcome or emergency revocation decision needs team agreement. | Colby, Kyra, and Daniel, with Rylee for mobile |
| Deployment and device acceptance | The checked-in create route also takes one recipient per request. Multi-recipient sharing, live listing propagation, authorization and cleanup, and device behavior still require separate acceptance. Use synthetic owner, recipient and outsider accounts on a confirmed disposable HTTPS environment. | Colby and Kyra for setup, Rylee for mobile execution |

**Next step.** With approval for disposable writes, exercise the new owner time route on the pinned API revision. Read a seeded item's window, change a bound, confirm the dedicated GET and listing agree, verify that a recipient cannot POST the change, and test a separate already-open fixture session on its next check. Keep protected uploads and rendering locked while the encrypted delivery work is reviewed.

## Integration continuation

- **Account creation and device approval.** The normal HTTPS sign-in screen now uses the existing `POST /api/register` contract. Only a confirmed acknowledgement returns to sign-in. The dashboard can register a configured device key and recheck the service's approval via `POST /api/devices` without opening a viewing session. Approval remains separate from recipient authorization.
- **Sender draft and owner policy.** The draft validates the exact recipient username locally and supports the API's country, region, and city fields as an alternative to GPS coordinates. Owner status and the area editor explain the listed location policy. An acknowledged area edit replaces a network restriction with the new GPS area.
- **Recipient review and account isolation.** Recipients can review listed time, view limit, device, screenshot, and location requirements. An observed policy change invalidates authorization from an older response and closes any late fixture session. Sender and recipient listing actions remain scoped to the issuing account.

Flutter analysis reported no issues. The continuation passed 375 targeted tests and a 137-test location and area run. The final complete host suite passed **930 tests**, up from 919 at the start of the continuation. Formatting and `git diff --check` passed. All new work is local and uncommitted.

### Remaining dependencies

| Required workflow | Current API gap and minimum needed | Owner |
| --- | --- | --- |
| Choose recipients and share with several at once | `POST /api/content` accepts one exact username and returns one item ID. Flutter supports that input now. Verified lookup and a single authoritative multi-recipient operation need API support. | Colby and Kyra |
| Enforce recipient consent and restore eligible access | Session Open/Check has a device key, camera version, and access result. It cannot bind consent to the policy the recipient read. Session suspension is a timed hold. It cannot submit a recipient access request or record a sender decision. Authoritative consent and recovery need policy support. | Daniel and Colby |
| Enforce idle sign-out and device approval | Login supplies an absolute expiry. Idle expiry needs a defined server idle policy. Device registration returns `trusted` and leaves initial approval to the service. The installed app needs an approved device key and the account needs a provisioned approval for acceptance. | Colby and Kyra |
| Verify real protected PNG sharing | The current Create and Open/Check routes carry readable payloads. Keep the Flutter gates in place until the backend/security team's protected path is available and verified. Validate one synthetic sender, recipient, and outsider over approved HTTPS, then run the Android and iOS lifecycle acceptance. | Backend/security team and Rylee |
