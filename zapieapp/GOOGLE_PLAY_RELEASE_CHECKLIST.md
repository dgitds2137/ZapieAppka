# Google Play Release Checklist

Checklist for uploading the `prod` Android flavor of Zapie Appka to Google Play.

Official references used for this checklist:
- Target API level: https://developer.android.com/google/play/requirements/target-sdk
- Android App Bundle: https://developer.android.com/guide/app-bundle
- Play App Signing: https://support.google.com/googleplay/android-developer/answer/9842756
- Prepare and roll out a release: https://support.google.com/googleplay/android-developer/answer/9859348
- Sensitive permissions and APIs: https://support.google.com/googleplay/android-developer/answer/9888170

## 0. Current repo status

- [x] Production Android package id is `pl.zapieapp.mobile`.
- [x] Separate `dev` package id exists: `pl.zapieapp.mobile.dev`.
- [x] Unflavored Android builds are blocked; always build with `--flavor dev` or `--flavor prod`.
- [x] Release signing is wired through `android/key.properties` and `android/key.properties.example`.
- [x] Keystore files and `android/key.properties` are ignored by git.
- [x] Production builds target Android 15 / API 35 for Google Play submissions.
- [x] `prodRelease` Android builds fail fast when `android/key.properties` is missing, preventing accidental Play uploads signed with the debug key.
- [x] The app declares only `INTERNET` plus OAuth/browser query support in `AndroidManifest.xml`.

## 1. One-time Google Play Console setup

- [ ] Create or open the Play Console app with package name `pl.zapieapp.mobile`.
- [ ] Enroll in Play App Signing.
- [ ] Decide who owns the upload key and where the backup is stored.
- [ ] Configure app category, contact email, website, and privacy policy URL.
- [ ] Prepare store listing assets:
  - [ ] App name: `Zapie Appka`.
  - [ ] Short description.
  - [ ] Full description.
  - [ ] App icon.
  - [ ] Feature graphic.
  - [ ] Phone screenshots.
  - [ ] Optional tablet screenshots if tablet distribution is enabled.
- [ ] Complete Google Play questionnaires:
  - [ ] App access.
  - [ ] Ads declaration.
  - [ ] Content rating.
  - [ ] Target audience.
  - [ ] Data safety.
  - [ ] Privacy policy.
  - [ ] Sensitive permissions review, if Google flags anything in future builds.

## 2. Upload key and signing files

Do this locally only. Never commit real secrets.

- [ ] Create or obtain the upload keystore.
- [ ] Copy the template:

```powershell
cd C:\FFApi\zapieapp
Copy-Item android\key.properties.example android\key.properties
```

- [ ] Fill `android/key.properties` with real values:

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=../keystores/zapieapp-upload.jks
```

- [ ] Confirm the keystore file exists at the path from `storeFile`.
- [ ] Store a secure backup of the keystore and passwords outside the repo.
- [ ] In Play Console, copy the upload certificate SHA-1/SHA-256 if Google login needs Android OAuth credentials.

## 3. Release configuration before every upload

- [ ] Confirm `pubspec.yaml` has a new version code suffix, for example:

```yaml
version: 0.1.0+1
```

- [ ] Increment the value after `+` for every new Play upload.
- [ ] Confirm backend URL for production:

```text
API_BASE_URL=https://<production-api-host>
```

- [ ] Confirm social login config, if enabled for the release:

```text
GOOGLE_AUTH_CLIENT_ID=<google-client-id>
APPLE_AUTH_CLIENT_ID=<apple-services-id>
AUTH_REDIRECT_URI=zapieapp://auth/callback
```

- [ ] Confirm backend callback endpoints are deployed and reachable:
  - [ ] `POST /google-auth/callback`
  - [ ] `POST /apple-auth/callback`

## 4. Local verification commands

Run from `zapieapp/`.

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
```

Recommended Android smoke test on a physical device:

```powershell
flutter run -d <device-id> --flavor prod --profile --dart-define=API_BASE_URL=https://<production-api-host>
```

If using OAuth in the smoke test, include:

```powershell
--dart-define=GOOGLE_AUTH_CLIENT_ID=<google-client-id> --dart-define=APPLE_AUTH_CLIENT_ID=<apple-services-id> --dart-define=AUTH_REDIRECT_URI=zapieapp://auth/callback
```

Manual checks:

- [ ] App launches as `Zapie Appka`, not `Zapie Appka DEV`.
- [ ] Login with e-mail/password works.
- [ ] Registration with e-mail/password works and creates a user session.
- [ ] Profile deletion action shows a confirmation popup and deletes the account.
- [ ] Google login opens the official Google page and handles cancellation/error.
- [ ] Apple login opens the official Apple page and handles cancellation/error, if enabled.
- [ ] Dashboard loads menu data from the production backend.
- [ ] Checkout/order flow works against the production or staging backend selected for the build.
- [ ] Logout returns to login screen.
- [ ] No debug banners, demo-only URLs, or test credentials are exposed in production listing screenshots.

## 5. Build the Play artifact

Build an Android App Bundle for the production flavor:

```powershell
cd C:\FFApi\zapieapp
flutter build appbundle --flavor prod --release --dart-define=API_BASE_URL=https://<production-api-host> --dart-define=GOOGLE_AUTH_CLIENT_ID=<google-client-id> --dart-define=APPLE_AUTH_CLIENT_ID=<apple-services-id> --dart-define=AUTH_REDIRECT_URI=zapieapp://auth/callback
```

Expected output:

```text
build\app\outputs\bundle\prodRelease\app-prod-release.aab
```

Before upload:

- [ ] Confirm the `.aab` file exists.
- [ ] Confirm it was built with `--flavor prod`.
- [ ] Confirm `android/key.properties` existed during the build; `bundleProdRelease` should fail without it.
- [ ] Archive the exact command and git commit SHA used for the release.

## 6. Play Console release flow

Recommended first rollout path:

1. Upload `app-prod-release.aab` to `Internal testing`.
2. Add release notes in Polish and English if both listings are enabled.
3. Roll out to internal testers.
4. Install from Google Play Internal Testing, not from USB.
5. Test login, ordering, and push/browser/OAuth redirects if enabled.
6. Promote to `Closed testing` or `Production` only after internal testing passes.

Production rollout:

- [ ] Use staged rollout for the first public release if available.
- [ ] Monitor Android vitals, crashes, ANRs, and backend logs.
- [ ] Keep the previous release artifact and git SHA documented for rollback context.

## 7. Data safety draft for current app behavior

Use `DATA_SECURITY_READINESS.md` as the detailed data/security gap review before submitting this form. Verify with the final backend and policies before submitting:

- Likely collected data:
  - [ ] E-mail address for account login/session.
  - [ ] Order/cart details for checkout and order history.
  - [ ] Authentication/session tokens stored on device.
- Current Android manifest permissions:
  - [ ] `android.permission.INTERNET`.
- No current manifest access to:
  - [ ] Location.
  - [ ] Camera.
  - [ ] Contacts.
  - [ ] Microphone.
  - [ ] SMS/phone.

Use this only as a starting point; the Play Console Data safety form must match the real production backend, analytics, crash reporting, and any future SDKs.
