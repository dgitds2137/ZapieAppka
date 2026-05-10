# zapieapp_flutter_starter

## Backend API

Adres backendu jest czytany z `--dart-define=API_BASE_URL`.

Lokalny backend na Android emulatorze:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Lokalny backend na telefonie fizycznym w tej samej sieci Wi-Fi:

```powershell
flutter run --dart-define=API_BASE_URL=http://ADRES_IP_KOMPUTERA:8000
```

Backend na Azure:

```powershell
flutter run --dart-define=API_BASE_URL=https://<nazwa-app-service>.azurewebsites.net
```

Bez `API_BASE_URL` aplikacja uzywa domyslnie `http://127.0.0.1:8000`.
