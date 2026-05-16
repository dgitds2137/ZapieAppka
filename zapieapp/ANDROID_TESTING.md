# Android Testing

## Recommended Mode

Test smoothness on a physical Android device in `--profile` mode.
Web in Chrome is useful for layout iteration, but it is not a reliable proxy for Flutter rendering performance on Android.

## Local Backend

Start the FastAPI backend on your machine so the phone can reach it.

From `C:\FFApi\my_fastapi_project`:

```powershell
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

## USB Testing

1. Enable Developer Options and USB debugging on the phone.
2. Connect the phone by cable.
3. Verify the device is visible:

```powershell
adb devices
```

4. Forward the backend port from the phone to the computer:

```powershell
adb reverse tcp:8000 tcp:8000
```

5. Run the app in profile mode:

```powershell
cd C:\FFApi\zapieapp
flutter run -d <device-id> --profile --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

This mode uses `adb reverse`. `127.0.0.1` and `localhost` point to the phone itself,
not to the computer, so a plain USB tethering connection is not enough on its own.

## USB Run With Azure Backend

Use this flow when the backend is already deployed and reachable on Azure Container Apps.

Current backend used in our runs:

```text
https://zapieapp-api-dev-alpha.gentlewave-09e4c100.westeurope.azurecontainerapps.io
```

1. On the phone, enable Developer Options and `USB debugging`.
2. Connect the phone by USB, unlock the screen, and accept the RSA authorization prompt if it appears.
3. Verify that ADB sees the device:

```powershell
C:\Users\User\AppData\Local\Android\sdk\platform-tools\adb.exe devices -l
```

Expected state:

```text
<device-id>    device
```

If Windows sees the phone as `MTP` or `ADB Interface` but `adb devices` is still empty:

1. On the phone, switch USB mode to `File transfer`.
2. Revoke USB debugging authorizations.
3. Disable and enable `USB debugging` again.
4. Reconnect the cable and accept the RSA prompt again.

4. Run Flutter on that exact device with the Azure API URL.

This project currently needs Java 17 for Android Gradle Plugin, so set it in the shell before `flutter run`:

```powershell
cd C:\FFApi\zapieapp
$env:JAVA_HOME='C:\Program Files\Java\jdk-17'
$env:Path="$env:JAVA_HOME\bin;$env:Path"
flutter run -d <device-id> --dart-define=API_BASE_URL=https://zapieapp-api-dev-alpha.gentlewave-09e4c100.westeurope.azurecontainerapps.io
```

Example from our run:

```powershell
flutter run -d 42c63095 --dart-define=API_BASE_URL=https://zapieapp-api-dev-alpha.gentlewave-09e4c100.westeurope.azurecontainerapps.io
```

5. If you want to confirm that the public backend is alive before the run:

```powershell
Invoke-RestMethod -Uri 'https://zapieapp-api-dev-alpha.gentlewave-09e4c100.westeurope.azurecontainerapps.io/health'
Invoke-RestMethod -Uri 'https://zapieapp-api-dev-alpha.gentlewave-09e4c100.westeurope.azurecontainerapps.io/health/db'
```

Notes for this mode:

- `flutter run` installs `app-debug.apk` on the phone.
- If the app launches and later `flutter run` prints `Lost connection to device`, the install and launch may still have succeeded; this usually means the USB/ADB session dropped after startup.
- If `flutter run` picks Java 11 and fails with `Android Gradle plugin requires Java 17`, repeat the run in a shell where `JAVA_HOME` points to `C:\Program Files\Java\jdk-17`.

## Wi-Fi Testing

1. Connect the phone and the computer to the same network.
2. Find the computer LAN IP, for example `192.168.0.42`.
3. Run the app in profile mode with that backend URL:

```powershell
cd C:\FFApi\zapieapp
flutter run -d <device-id> --profile --dart-define=API_BASE_URL=http://192.168.0.42:8000
```

## Performance Overlay

To inspect frame timing and jank on device, enable the Flutter performance overlay:

```powershell
flutter run -d <device-id> --profile --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=SHOW_PERFORMANCE_OVERLAY=true
```

For Wi-Fi testing, replace the API URL with the LAN address of the computer.

## Notes

- `--profile` is the best balance for animation and scrolling checks.
- `--debug` is fine for feature work, but it distorts performance.
- If you are using USB tethering instead of `adb reverse`, use the computer IP
  from the tethered network instead of `127.0.0.1`, and start FastAPI with
  `--host 0.0.0.0`.
- If the phone cannot reach the backend over Wi-Fi, verify that Windows Firewall allows inbound traffic on port `8000`.
- If you change prep times or backend logic during testing, restart or hot-restart the Flutter app so new `/positions` data is fetched again.
