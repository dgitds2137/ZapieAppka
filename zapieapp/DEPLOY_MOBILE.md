# Mobile Deploy

## Flavors

Application has two flavors on both mobile platforms:

- `prod`
  - Android package: `pl.zapieapp.mobile`
  - iOS bundle id: `pl.zapieapp.mobile`
  - visible app name: `Zapie Appka`
- `dev`
  - Android package: `pl.zapieapp.mobile.dev`
  - iOS bundle id: `pl.zapieapp.mobile.dev`
  - visible app name: `Zapie Appka DEV`

This lets testers install `DEV` next to production without replacing it.

## Android

### Signing

1. Copy `android/key.properties.example` to `android/key.properties`.
2. Fill it with the real upload keystore values.
3. Put the keystore file in a safe local path, for example `android/keystores/`.

If `android/key.properties` is missing, release builds fall back to the debug key.
That is acceptable only for local smoke testing, not for Play upload.

### Build DEV for testers

```powershell
cd C:\FFApi\zapieapp
flutter build appbundle --flavor dev --release
```

Output:

```text
build\app\outputs\bundle\devRelease\app-dev-release.aab
```

Recommended distribution target: Google Play `Internal testing`.

### Build PROD

```powershell
cd C:\FFApi\zapieapp
flutter build appbundle --flavor prod --release
```

Output:

```text
build\app\outputs\bundle\prodRelease\app-prod-release.aab
```

Recommended distribution target: Google Play `Production`.

## iOS

### Xcode prerequisites

1. Open `ios/Runner.xcworkspace` on macOS.
2. Log into the Apple Developer account in Xcode.
3. For target `Runner`, assign the Apple Team.
4. Ensure both bundle identifiers exist in Apple Developer:
   - `pl.zapieapp.mobile`
   - `pl.zapieapp.mobile.dev`
5. Keep signing on `Automatic`, unless you manage profiles manually.

### Shared schemes

Project contains two shared schemes:

- `prod`
- `dev`

### Build DEV IPA

```bash
cd /path/to/FFApi/zapieapp
flutter build ipa --flavor dev --release
```

Recommended distribution target: TestFlight for internal testers.

### Build PROD IPA

```bash
cd /path/to/FFApi/zapieapp
flutter build ipa --flavor prod --release
```

Recommended distribution target: TestFlight first, then App Store release.

## Notes

- If you own a different production domain or App Store namespace, replace the bundle ids in:
  - `android/app/build.gradle.kts`
  - `ios/Flutter/*.xcconfig`
- `dev` and `prod` are isolated package identities. Login state, storage and installed app icons stay separate on devices.
