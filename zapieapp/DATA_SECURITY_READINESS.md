# Data & Security Readiness Review for Google Play

This review summarizes what the app already does and what still needs a product/security decision before Google Play submission.

Official references used:
- Google Play User Data policy: https://support.google.com/googleplay/android-developer/answer/10144311
- Google Play Data safety form: https://support.google.com/googleplay/android-developer/answer/10787469
- Google Play account deletion requirements: https://support.google.com/googleplay/android-developer/answer/13327111
- Android cleartext communication guidance: https://developer.android.com/privacy-and-security/risks/cleartext-communications
- Android security checklist: https://developer.android.com/privacy-and-security/security-tips

## Executive summary

The app is close to being Play-ready from a manifest/permissions perspective, but it still has several release blockers around disclosures and account/data lifecycle:

- [ ] Publish a public privacy policy URL and add a privacy policy link or text inside the app.
- [ ] Complete the Play Console Data safety form based on real backend behavior and any SDKs enabled for production.
- [x] Add an in-app account deletion/request path because users can now register from the app.
- [ ] Decide whether auth/session tokens may remain in `SharedPreferences`, or migrate sensitive session storage to platform secure storage before production.
- [ ] Avoid sending session tokens in query strings; prefer an `Authorization` header or another non-URL transport.
- [ ] Make production builds use HTTPS-only backend URLs and keep cleartext HTTP limited to the `dev` flavor.

## What the repo already has

### Android permissions are minimal

Current Android manifest declares `android.permission.INTERNET` only, plus intent/query declarations needed for browser/OAuth redirects. No location, camera, contacts, microphone, SMS, or storage permissions are declared.

Relevant files:
- `android/app/src/main/AndroidManifest.xml`
- `GOOGLE_PLAY_RELEASE_CHECKLIST.md`

### Production cleartext is disabled

Production and default Android flavors set `usesCleartextTraffic=false`; `dev` keeps cleartext enabled for local backend testing.

Relevant files:
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`

### Android backup is disabled

Android `allowBackup=false` is set to reduce accidental cloud/device backup exposure of local session and checkout data.

Relevant file:
- `android/app/src/main/AndroidManifest.xml`

### Local session TTL exists

Stored sessions have `persisted_at` and `expires_at`, and expired sessions are cleared with active checkout data.

Relevant file:
- `lib/data/local/session_persistence.dart`

### Secrets are not committed by design

`android/key.properties`, keystores, Google service files, and Firebase app IDs are ignored by git.

Relevant files:
- `.gitignore`
- `android/.gitignore`
- `android/key.properties.example`

## Current data handled by the app

Data visible from the Flutter client code:

- Account/login data:
  - e-mail address.
  - password sent to `/login` after base64 encoding.
  - OAuth authorization code callback data for Google/Apple.
- Authentication/session data:
  - `jwt`.
  - `session_token`.
  - role.
  - auth provider.
  - loyalty points.
- Order and checkout data:
  - active checkout details.
  - checkout history.
  - order messages/chat content.
  - order identifiers and statuses.
- Device/browser flow data:
  - OAuth deep link callback parameters.

This means the Play Console Data safety form will almost certainly need to declare at least account identifiers/contact info and app activity/order-related data, depending on final backend semantics.

## Gaps and recommended actions

### 1. Privacy policy is required

Google Play requires a privacy policy in Play Console and a privacy policy link or text within the app. The policy must describe collected/shared personal and sensitive data, secure handling, retention/deletion, contact mechanism, and must be publicly accessible.

Status:
- [ ] Missing public privacy policy URL in repo/docs.
- [ ] Missing in-app privacy policy link or screen.

Recommendation:
- Add a static privacy policy page on the production website.
- Add a `Privacy Policy` link on the login screen or settings/account screen.
- Ensure the developer/entity name in Play Console matches the privacy policy.

### 2. Account deletion path is required because account creation is available

Google Play requires an account deletion request path if the app lets users create an account. The app now exposes e-mail registration, so this must be handled before public production rollout.

Status:
- [x] In-app `Usun konto` action exists in the profile/order history screen with a confirmation popup.
- [x] Backend `DELETE /account` endpoint exists and validates the active session token.
- [ ] Public web deletion request URL is still missing for Play Console.

Recommendation:
- Add a public web URL for deletion requests for Play Console.
- Review backend retention rules for legal/accounting records; the current endpoint anonymizes checkout/order references before deleting the user row.

### 3. Data safety form needs final backend/SDK inventory

Google Play requires Data safety declarations for each package that reaches closed/open/production testing. Internal-only testing is exempt from display, but production preparation should treat the form as mandatory.

Status:
- [ ] Draft exists in `GOOGLE_PLAY_RELEASE_CHECKLIST.md`.
- [ ] Final answers require backend behavior, analytics/crash SDK decisions, and privacy policy.

Recommendation:
- Before upload, list every production SDK and backend destination.
- Complete Data safety for data collected by app code and by any SDKs.
- Keep the Data safety form consistent with the privacy policy.

### 4. Session tokens are stored in plain SharedPreferences

`SessionPersistence` stores `jwt`, `session_token`, e-mail, role, provider, and checkout data through the storage backend. On Android/iOS this currently uses `shared_preferences`, not a platform secure storage/keychain abstraction.

Status:
- [ ] Not a direct Play policy blocker by itself, but it is a security risk for authentication data.

Recommendation:
- Prefer migrating auth/session storage to platform secure storage before production, for example Android Keystore / iOS Keychain via a maintained Flutter plugin.
- If not migrated before first release, document the risk and reduce token lifetime/server-side session lifetime.
- Keep `allowBackup=false` enabled.

### 5. Session tokens are sent in query parameters

Several repository calls send `session_token` and/or e-mail in URL query parameters. URLs can be logged by proxies, servers, analytics, crash logs, and debugging tools more easily than headers.

Status:
- [ ] Security hardening gap.

Recommendation:
- Move session authentication to an `Authorization: Bearer <token>` header or a backend-supported session header.
- Avoid putting e-mail/session identifiers in GET query strings where practical.
- Redact tokens from backend/access logs.

### 6. Production must be HTTPS-only

Android guidance recommends avoiding cleartext traffic. The app now disables Android cleartext for production, but `API_BASE_URL` still must be supplied as an HTTPS production URL during release builds.

Status:
- [x] Production Android cleartext disabled.
- [ ] Build/release process must ensure `API_BASE_URL=https://...` is always provided.

Recommendation:
- Keep `dev` cleartext only for local testing.
- Fail CI/release scripts if `API_BASE_URL` is missing or starts with `http://` for `prod`.

### 7. Password handling should be reviewed

The password login request base64-encodes the password. Base64 is not encryption; confidentiality depends on HTTPS.

Status:
- [ ] Acceptable only over HTTPS.

Recommendation:
- Ensure `/login` is available only over HTTPS in production.
- Consider sending JSON over HTTPS and let the backend handle password verification; do not describe base64 as encryption in docs or policy.

## Suggested release blockers before first public production rollout

Treat these as blockers before moving beyond internal testing:

- [ ] Privacy policy URL exists and is linked in-app.
- [ ] Account deletion request path exists in-app and on the web if account creation is enabled. In-app is done; public web URL is still needed.
- [ ] Data safety form completed and reviewed against backend behavior.
- [ ] Production build uses HTTPS `API_BASE_URL`.
- [ ] Backend logs redact `jwt`, `session_token`, `code`, and OAuth callback parameters.

Treat these as high-priority hardening tasks:

- [ ] Move session tokens from plain `SharedPreferences` to platform secure storage.
- [ ] Move session token transport from query parameters to headers.
- [ ] Add a documented session revocation/logout endpoint if not already present.
- [ ] Define retention periods for accounts, sessions, orders, chat/messages, and checkout data.
