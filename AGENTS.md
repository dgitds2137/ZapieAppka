# Projekt: ZapieAppka (FastAPI backend + Flutter frontend)

## 1) Co to jest
Repo ma dwa glowne komponenty:
- `my_fastapi_project/` - backend API (FastAPI) + migracje/seedy SQL + testy smoke/e2e.
- `zapieapp/` - aplikacja Flutter (klient mobilny/web), ktora konsumuje ten backend.

Backend i frontend sa juz polaczone i uzywane na Azure Container Apps (`zapieapp-api-dev-alpha`) z baza SQL.

Pliki kontekstowe dla kolejnych watkow:
- `AGENTS.md` - stan projektu, architektura, endpointy, onboarding.
- `CHANGELOG_AGENT.md` - ostatnie zmiany z timestampami, zeby szybko dojsc co bylo robione i co zostalo po drodze ustalone.
- `APPLE_AUTH_PREP.md` - techniczne przygotowanie Apple Sign In po naszej stronie + smoke plan na moment, gdy pojawi sie konto Apple Developer i sekret-y.
  - zawiera tez gotowy Azure CLI skeleton do ustawienia `apple-auth-*` secretow i rolloutu env

## 2) Backend szybki przeglad
- Glowne wejscie: `my_fastapi_project/main.py` (`FastAPI(...)`, `/health`, `/health/db`, `app.include_router(routes(...))`).
- Router API: `my_fastapi_project/router.py`.
- Logika domenowa:
  - `my_fastapi_project/checkout_service.py` - caly lifecycle zamowien, role, statusy, kalkulacje.
  - `my_fastapi_project/checkout_repository.py`, `api_gateway.py`, `notification_service.py`, `kitchen_service.py` - oddzielne uslugi procesowe.
  - `my_fastapi_project/models.py` - modele SQLAlchemy + stale rol/statusow.
- Konfiguracja:
  - `my_fastapi_project/config.py` czyta `APP_ENV`, `APP_NAME`, `JWT_SECRET_KEY`, `MSSQL_CONN_STR` (`DATABASE_URL` fallback), CORS i startup flags.
  - `ensure_database_schema()` (`db.py`) uruchamia skrypty SQL z `my_fastapi_project/sql/` i seed.

## 3) Najwazniejsze endpointy
### Public / klient
- `GET /health`, `GET /health/db`
- `GET /google-auth/start`
- `POST /google-auth/callback`
- `GET /apple-auth/start`
- `POST /apple-auth/callback`
- `GET|POST /apple-auth/return`
- `GET /positions`
- `GET /position/{position_id}/addons`
- `GET /opening-hours`
- `GET /checkout/delivery-estimate`
- `GET /checkout/pickup-location`
- `POST /checkout/udka-availability`
- `POST /checkout/validate-delivery-address`
- `POST /checkout/pickup-slot-estimate`
- `POST /checkout/verification`
- `GET /checkout/active`
- `GET /checkout/history`
- `POST /checkout/cancel`
- `GET|POST /checkout/orders/{checkout_order_id}/messages`
- `POST /checkout/orders/{checkout_order_id}/messages/read`
- `POST /checkout/confirm-receipt`
- `GET|POST /register`, `/login`, `DELETE /account`

### Admin / pracownik / driver
- `GET /admin/dashboard`
- `GET /admin/staff-presence`
- `GET /admin/catalog`
- `PATCH /admin/catalog/*` (positions/addons/delivery-minimum/delivery-radius/opening-hours/delivery-origin-address)
- `GET /admin/prep-time-settings`, `PATCH /admin/prep-time-settings/{group_key}`
- `GET /admin/orders/history`
- `PATCH /admin/orders/{id}/processing-status`

Role w app backendu to: `user`, `employee`, `driver`, `admin`.

## 4) Auth i flow
- `POST /login` i `POST /register` przyjmuja `Form` + base64 password (front to koduje po stronie klienta).
- `UserService` zwraca `jwt`, `session_token`, `role`, `user_id`, `email`.
- Wiele endpointow przyjmuje `session_token` i/lub `email` jako identyfikatory uzytkownika.
- Fundament Google OAuth jest juz dodany:
  - backend startuje flow przez `GET /google-auth/start`
  - frontend otwiera URL autoryzacji dostarczony przez backend
  - callback wraca na `zapieapp://auth/callback` albo webowy `/auth/callback`
  - backend finalizuje logowanie przez `POST /google-auth/callback`
  - po sukcesie koncowym artefaktem nadal jest standardowa sesja aplikacji (`jwt` + `session_token`)
- Fundament Apple Sign In jest w przygotowaniu po tej samej architekturze backend-first:
  - backend startuje flow przez `GET /apple-auth/start`
  - frontend otwiera URL autoryzacji dostarczony przez backend
  - Apple wraca najpierw na backendowy bridge callback `GET|POST /apple-auth/return`
  - backend przekierowuje dalej na frontendowy callback `zapieapp://auth/callback` albo webowy `/auth/callback`
  - backend finalizuje logowanie przez `POST /apple-auth/callback`
  - frontend umie przejac dodatkowy `user` payload z pierwszego logowania Apple i przekazac nazwe uzytkownika do backendu
  - po sukcesie koncowym artefaktem nadal jest standardowa sesja aplikacji (`jwt` + `session_token`)
- Konfiguracja Google OAuth siedzi w `.env` backendu:
  - `GOOGLE_AUTH_CLIENT_ID`
  - `GOOGLE_AUTH_CLIENT_SECRET`
  - `GOOGLE_AUTH_DEFAULT_REDIRECT_URI`
  - `GOOGLE_AUTH_ALLOWED_REDIRECT_URIS`
  - `GOOGLE_AUTH_STATE_TTL_SECONDS`
- Konfiguracja Apple Sign In siedzi w `.env` backendu:
  - `APPLE_AUTH_CLIENT_ID`
  - `APPLE_AUTH_TEAM_ID`
  - `APPLE_AUTH_KEY_ID`
  - `APPLE_AUTH_PRIVATE_KEY`
  - `APPLE_AUTH_CALLBACK_BRIDGE_URI`
  - `APPLE_AUTH_DEFAULT_REDIRECT_URI`
  - `APPLE_AUTH_ALLOWED_REDIRECT_URIS`
  - `APPLE_AUTH_STATE_TTL_SECONDS`

## 5) Frontend skrot (Flutter)
- Punkt wejscia API: `zapieapp/lib/core/config/app_config.dart` -> `API_BASE_URL` (domyslnie `http://127.0.0.1:8000`).
- Redirecty auth po stronie Fluttera:
  - `AUTH_REDIRECT_URI` - bazowy redirect, obecnie uzywany przez Google
  - `APPLE_AUTH_REDIRECT_URI` - dedykowany redirect dla Apple; jesli nieustawiony, fallbackuje do `AUTH_REDIRECT_URI`
- Router UI: `zapieapp/lib/router/app_router.dart`.
- Ekran logowania/rejestracji: `zapieapp/lib/features/auth/login_screen.dart`.
- Callback auth: `zapieapp/lib/features/auth/auth_callback_screen.dart`.
- Dashboard klienta: `zapieapp/lib/features/dashboard/dashboard_screen.dart`.
- Dashboard admin/staff/driver: `zapieapp/lib/features/admin/admin_dashboard_screen.dart`.
- Repozytorium HTTP checkout/admin: `zapieapp/lib/data/repositories/checkout_repository.dart`, `admin_dashboard_repository.dart`.
- Repozytorium social auth: `zapieapp/lib/data/repositories/social_auth_repository.dart`.
- Praktyczna uwaga dla Apple:
  - Google i Apple nie musza docelowo dzielic tego samego redirect URI
  - frontend ma juz osobny `APPLE_AUTH_REDIRECT_URI`, zeby mozna bylo pozniej ustawic Apple pod dedykowany callback bez ruszania Google flow

## 6) QA / testy
- Testy funkcjonalne backendu: `my_fastapi_project/qa/tests/*.py`.
- Testy lokalne fundamentu Google OAuth:
- Testy lokalne fundamentu social auth:
  - `my_fastapi_project/tests/test_google_oauth_foundations.py`
  - `my_fastapi_project/tests/test_google_oauth_endpoints.py`
  - `my_fastapi_project/tests/run_google_oauth_foundation_suite.py`
- Scenariusze i smoke:
  - `my_fastapi_project/qa/scenarios/`
  - `my_fastapi_project/qa/run_e2e_smoke.ps1`
  - `my_fastapi_project/qa/run_e2e_smoke.sh`
  - `my_fastapi_project/qa/run_smoke_order_flow.py`
- Aktualnie pokrywane scenariusze skupiaja sie na glownej sciezce: user -> employee -> driver.
- Jedna komenda do czytelnego sprawdzenia Google + Apple auth foundation:
  - `python my_fastapi_project/tests/run_google_oauth_foundation_suite.py`

## 7) Lokalny rozwoj (backend)
- Instalacja:
  - `cd my_fastapi_project`
  - `python -m venv .venv`
  - `.venv\Scripts\python -m pip install -r requirements.txt`
  - `Copy-Item .env.example .env` i uzupelnij `MSSQL_CONN_STR`, `JWT_SECRET_KEY`
- Uruchomienie:
  - `python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload`
- Szybki check:
  - `curl http://127.0.0.1:8000/health`
  - `curl http://127.0.0.1:8000/health/db`
  - `python tests/run_google_oauth_foundation_suite.py`

## 8) Deploy i infra (skrot)
- CI dla API: `.github/workflows/deploy-api-containerapp.yml` (trigger: push do main + workflow_dispatch).
- GitHub Actions uzywa federated credentials (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) + variables ACA/ACR.
- Azure Container App secrets:
  - `mssql-conn-str`
  - `jwt-secret-key`
- Dla Google auth workflow oczekuje kompletnego zestawu secretow:
  - `google-auth-client-id`
  - `google-auth-client-secret`
  - `google-auth-default-redirect-uri`
  - `google-auth-allowed-redirect-uris`
- Dla Apple auth workflow jest przygotowany na opcjonalny, ale kompletny zestaw secretow:
  - `apple-auth-client-id`
  - `apple-auth-team-id`
  - `apple-auth-key-id`
  - `apple-auth-private-key`
  - `apple-auth-callback-bridge-uri`
  - `apple-auth-default-redirect-uri`
  - `apple-auth-allowed-redirect-uris`
- Workflow deployu API umie teraz:
  - nie wywalac deployu, jesli Apple auth nie jest jeszcze skonfigurowany
  - automatycznie podchwycic Apple env po dodaniu kompletu secretow
  - zatrzymac deploy, jesli social auth ma tylko czesc secretow i grozi polowiczna konfiguracja
- Healthcheck po deployu: `https://<container-app-fqdn>/health` oraz `https://<container-app-fqdn>/health/db`.

## 9) Przydatne uwagi operacyjne
- Sprawdzaj zgodnosc subskrypcji i resource group przed zmianami.
- Nie zapisuj sekretow w kodzie repo.
- Przy zmianach migracyjnych/seedu uruchom najpierw /health/db, potem glowne endpointy klienta i order flow.
