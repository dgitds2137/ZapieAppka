# Social Auth Setup

Obecny stan:
- aplikacja ma trwałe zapisywanie sesji na urządzeniu,
- ekran logowania ma przyciski `Google` i `Apple`,
- ekran wymaga wpisanego e-maila i otwiera oficjalne endpointy OAuth providerów,
- aplikacja ma route callback `/auth/callback` oraz custom scheme `zapieapp://auth/callback`,
- backend ma docelowo przyjąć endpointy `/google-auth/callback` i `/apple-auth/callback`.

Aktualnie social login nie jest jeszcze aktywny end-to-end. Żeby go dokończyć, trzeba:

## Flutter

Uruchamiać aplikację z konfiguracją:

```powershell
flutter run --dart-define=GOOGLE_AUTH_CLIENT_ID=twoj-google-client-id.apps.googleusercontent.com --dart-define=APPLE_AUTH_CLIENT_ID=twoj-apple-services-id --dart-define=AUTH_REDIRECT_URI=zapieapp://auth/callback
```

## Android

Dodać:
- `google-services.json`
- konfigurację Google OAuth Client ID dla aplikacji Android
- redirect URI zgodny z `AUTH_REDIRECT_URI` albo obsługę custom scheme `zapieapp://auth/callback`

Pliki z sekretami są ignorowane przez `.gitignore`.

## iOS

Dodać:
- `GoogleService-Info.plist`
- URL schemes i wpisy Apple / Google w `Info.plist`
- Services ID dla Apple ustawiony jako `APPLE_AUTH_CLIENT_ID`

Pliki z sekretami są ignorowane przez `.gitignore`.

## Backend

Docelowo endpointy:
- `POST /google-auth/callback`
- `POST /apple-auth/callback`

powinny:
1. przyjąć `code`, `state`, opcjonalny `email` oraz `redirect_uri`,
2. wymienić `code` po stronie backendu na tokeny providera,
3. zweryfikować tokeny providera,
4. znaleźć lub utworzyć lokalnego użytkownika dla e-maila z tokenu albo ze `state`,
5. zwrócić standardową sesję aplikacji: `jwt`, `session_token`, `role`, `email`, `loyalty_points`.

Oficjalne endpointy otwierane przez aplikację:
- Google: `https://accounts.google.com/o/oauth2/v2/auth`
- Apple: `https://appleid.apple.com/auth/authorize`

## Pamięć sesji

Sesja użytkownika jest zapisywana lokalnie na urządzeniu z TTL kontrolowanym przez:

```text
PERSISTED_LOGIN_DAYS
```

Domyślnie: `30` dni.
