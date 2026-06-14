# Apple Sign In - przygotowanie po naszej stronie

Ten plik zbiera to, co jest juz przygotowane w repo oraz co zostaje do uzupelnienia po uzyskaniu Apple Developer setup.

## Co jest juz gotowe

- Backend:
  - `GET /apple-auth/start`
  - `GET|POST /apple-auth/return`
  - `POST /apple-auth/callback`
  - podpisany `state`
  - `nonce` dla Apple auth
  - wymiana `authorization code -> token`
  - budowa Apple `client_secret` JWT z `APPLE_AUTH_TEAM_ID`, `APPLE_AUTH_KEY_ID`, `APPLE_AUTH_PRIVATE_KEY`
  - walidacja Apple `id_token`
  - backendowy bridge callback, ktory odbiera odpowiedz Apple i przekierowuje dalej do frontendowego callbacku
  - finalizacja do standardowej sesji aplikacji (`jwt`, `session_token`, `role`, `email`)
- Frontend:
  - przycisk Apple korzysta z backendowego `apple-auth/start`
  - callback screen umie wyslac kod na `/apple-auth/callback`
  - Apple ma osobny `APPLE_AUTH_REDIRECT_URI`, niezalezny od Google
  - callback screen umie przejac `user` z pierwszego logowania Apple i przekazac nazwe uzytkownika do backendu
- Infra:
  - workflow API deployu na Azure Container Apps umie opcjonalnie utrzymac `APPLE_AUTH_*`
  - workflow nie wywala deployu, jesli Apple nie jest jeszcze skonfigurowany
  - workflow zatrzyma deploy, jesli Apple secret-y beda tylko czesciowo ustawione

## Co trzeba pozniej uzupelnic z Apple Developer

- `APPLE_AUTH_CLIENT_ID`
- `APPLE_AUTH_TEAM_ID`
- `APPLE_AUTH_KEY_ID`
- `APPLE_AUTH_PRIVATE_KEY`
- `APPLE_AUTH_CALLBACK_BRIDGE_URI`
- `APPLE_AUTH_DEFAULT_REDIRECT_URI`
- `APPLE_AUTH_ALLOWED_REDIRECT_URIS`

## Azure Container App secrets do ustawienia

Nazwy secretow, ktore workflow juz rozumie:

- `apple-auth-client-id`
- `apple-auth-team-id`
- `apple-auth-key-id`
- `apple-auth-private-key`
- `apple-auth-callback-bridge-uri`
- `apple-auth-default-redirect-uri`
- `apple-auth-allowed-redirect-uris`

### Przykladowy Azure CLI rollout po uzyskaniu danych z Apple

Ustaw swoje srodowisko:

```bash
export APP_NAME="zapieapp-api-dev-alpha"
export RESOURCE_GROUP="zapieapp-rg"
```

Ustaw sekrety:

```bash
az containerapp secret set \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --secrets \
    apple-auth-client-id="<APPLE_AUTH_CLIENT_ID>" \
    apple-auth-team-id="<APPLE_AUTH_TEAM_ID>" \
    apple-auth-key-id="<APPLE_AUTH_KEY_ID>" \
    apple-auth-private-key="<APPLE_AUTH_PRIVATE_KEY>" \
    apple-auth-callback-bridge-uri="<APPLE_AUTH_CALLBACK_BRIDGE_URI>" \
    apple-auth-default-redirect-uri="<APPLE_AUTH_DEFAULT_REDIRECT_URI>" \
    apple-auth-allowed-redirect-uris="<APPLE_AUTH_ALLOWED_REDIRECT_URIS>"
```

Wymus ponowne ustawienie env, jesli chcesz zrobic rollout bez czekania na kolejny deploy:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --set-env-vars \
    APP_ENV=production \
    PORT=8000 \
    REQUIRE_DATABASE_ON_STARTUP=false \
    MSSQL_CONN_STR=secretref:mssql-conn-str \
    JWT_SECRET_KEY=secretref:jwt-secret-key \
    GOOGLE_AUTH_CLIENT_ID=secretref:google-auth-client-id \
    GOOGLE_AUTH_CLIENT_SECRET=secretref:google-auth-client-secret \
    GOOGLE_AUTH_DEFAULT_REDIRECT_URI=secretref:google-auth-default-redirect-uri \
    GOOGLE_AUTH_ALLOWED_REDIRECT_URIS=secretref:google-auth-allowed-redirect-uris \
    GOOGLE_AUTH_STATE_TTL_SECONDS=600 \
    APPLE_AUTH_CLIENT_ID=secretref:apple-auth-client-id \
    APPLE_AUTH_TEAM_ID=secretref:apple-auth-team-id \
    APPLE_AUTH_KEY_ID=secretref:apple-auth-key-id \
    APPLE_AUTH_PRIVATE_KEY=secretref:apple-auth-private-key \
    APPLE_AUTH_CALLBACK_BRIDGE_URI=secretref:apple-auth-callback-bridge-uri \
    APPLE_AUTH_DEFAULT_REDIRECT_URI=secretref:apple-auth-default-redirect-uri \
    APPLE_AUTH_ALLOWED_REDIRECT_URIS=secretref:apple-auth-allowed-redirect-uris \
    APPLE_AUTH_STATE_TTL_SECONDS=600
```

Sprawdz finalny FQDN:

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query 'properties.configuration.ingress.fqdn' \
  -o tsv
```

Jesli workflow GitHub Actions odpali sie po pushu do `main`, zwykle wystarczy sam `secret set`, bo deploy workflow jest juz przygotowany do podchwycenia Apple env.

## Frontend env

- `AUTH_REDIRECT_URI`
  - bazowy redirect, obecnie uzywany przez Google
- `APPLE_AUTH_REDIRECT_URI`
  - dedykowany redirect dla Apple
  - jesli nieustawiony, fallbackuje do `AUTH_REDIRECT_URI`

## Rozdzial odpowiedzialnosci redirectow Apple

- `APPLE_AUTH_CALLBACK_BRIDGE_URI`
  - publiczny endpoint backendu
  - to jego trzeba wpisac po stronie Apple jako return/callback URL
  - Apple wraca tutaj, a backend dopiero przekierowuje dalej do frontendu
  - endpoint jest przygotowany zarówno na `GET`, jak i `POST form`, z naciskiem na scenariusz `POST`
- `APPLE_AUTH_DEFAULT_REDIRECT_URI`
  - finalny callback aplikacji frontendowej
  - np. `zapieapp://auth/callback` albo `http://127.0.0.1:3001/auth/callback`

## Minimalny smoke plan po konfiguracji Apple

### 1. Backend health

Sprawdz:

```bash
curl -i "https://<API_FQDN>/health"
curl -i "https://<API_FQDN>/health/db"
```

Oczekiwane:

- `200 OK`
- backend i DB zdrowe

### 2. Apple start endpoint

Sprawdz:

```bash
curl -i -G "https://<API_FQDN>/apple-auth/start" \
  --data-urlencode "redirect_uri=<APPLE_REDIRECT_URI>"
```

Oczekiwane:

- `200 OK`
- JSON zawiera:
  - `provider=apple`
  - `authorization_url`
  - `redirect_uri`
  - `state`
  - `nonce`
- `authorization_url` powinien zawierac backendowy `APPLE_AUTH_CALLBACK_BRIDGE_URI` jako `redirect_uri`
- realny callback od Apple moze przyjsc przez backendowy bridge jako `POST form`, nie tylko query string

### 3. Frontend local/manual test

Uruchom frontend z poprawnym API i Apple redirectem.

Przyklad:

```powershell
cd C:\FFApi\zapieapp
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 3001 --dart-define API_BASE_URL=https://<API_FQDN> --dart-define AUTH_REDIRECT_URI=http://127.0.0.1:3001/auth/callback --dart-define APPLE_AUTH_REDIRECT_URI=http://127.0.0.1:3001/auth/callback
```

### 4. Manualne klikniecie Apple

W UI:

- kliknij `Kontynuuj z Apple`
- przejdz przez login Apple
- poczekaj na powrot do callbacku

Oczekiwane:

- frontend wraca na callback
- frontend wywoluje `POST /apple-auth/callback`
- backend zwraca sesje aplikacji
- sesja zapisuje sie lokalnie
- user laduje na dashboardzie

### 5. Negatywne symptomy, ktore oznaczaja problem w konfiguracji

- `400` z `/apple-auth/start`
  - zwykle zly `redirect_uri` albo brak `APPLE_AUTH_ALLOWED_REDIRECT_URIS`
- `400` z `/apple-auth/callback`
  - zwykle mismatch `redirect_uri`, `state`, `nonce` albo blad po stronie Apple token exchange
- `503` z `/apple-auth/callback`
  - brak kompletu `APPLE_AUTH_*`
- powrot do loginu bez sesji
  - najpierw sprawdzic, czy callback wyslal dobry `redirect_uri` dla Apple

## Wazna uwaga

Apple auth jest przygotowany jako backend-first flow. To oznacza, ze finalny sukces zalezy glownie od:

- poprawnego Apple Developer setup
- zgodnosci redirect URI
- poprawnego wpisania `APPLE_AUTH_*` do Azure

Po naszej stronie kod aplikacji i deploy sa juz przygotowane pod ten etap.
