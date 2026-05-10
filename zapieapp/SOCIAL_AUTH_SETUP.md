# Social Auth Setup

Obecny stan:
- aplikacja ma trwałe zapisywanie sesji na urządzeniu,
- ekran logowania ma przyciski `Google` i `Facebook`,
- konfiguracja providerów jest przygotowana przez `dart-define`,
- backend ma placeholder endpointy `/google-auth` i `/facebook-auth`.

Aktualnie social login nie jest jeszcze aktywny end-to-end. Żeby go dokończyć, trzeba:

## Flutter

Uruchamiać aplikację z konfiguracją:

```powershell
flutter run --dart-define=GOOGLE_AUTH_CLIENT_ID=twoj-google-client-id.apps.googleusercontent.com --dart-define=FACEBOOK_APP_ID=twoj-facebook-app-id
```

## Android

Dodać:
- `google-services.json`
- konfigurację Facebook App ID / Client Token

Pliki z sekretami są ignorowane przez `.gitignore`.

## iOS

Dodać:
- `GoogleService-Info.plist`
- URL schemes i wpisy Facebook / Google w `Info.plist`

Pliki z sekretami są ignorowane przez `.gitignore`.

## Backend

Docelowo endpointy:
- `POST /google-auth`
- `POST /facebook-auth`

powinny:
1. zweryfikować token od providera,
2. znaleźć lub utworzyć lokalnego użytkownika,
3. zwrócić standardową sesję aplikacji: `jwt`, `session_token`, `role`, `email`, `loyalty_points`.

## Pamięć sesji

Sesja użytkownika jest zapisywana lokalnie na urządzeniu z TTL kontrolowanym przez:

```text
PERSISTED_LOGIN_DAYS
```

Domyślnie: `30` dni.
