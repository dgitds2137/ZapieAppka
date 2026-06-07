# Projekt: ZapieAppka (FastAPI backend + Flutter frontend)

## 1) Co to jest
Repo ma dwa glowne komponenty:
- `my_fastapi_project/` - backend API (FastAPI) + migracje/seedy SQL + testy smoke/e2e.
- `zapieapp/` - aplikacja Flutter (klient mobilny/web), ktora konsumuje ten backend.

Backend i frontend sa juz polaczone i uzywane na Azure Container Apps (`zapieapp-api-dev-alpha`) z baza SQL.

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

## 5) Frontend skrot (Flutter)
- Punkt wejscia API: `zapieapp/lib/core/config/app_config.dart` -> `API_BASE_URL` (domyslnie `http://127.0.0.1:8000`).
- Router UI: `zapieapp/lib/router/app_router.dart`.
- Ekran logowania/rejestracji: `zapieapp/lib/features/auth/login_screen.dart`.
- Dashboard klienta: `zapieapp/lib/features/dashboard/dashboard_screen.dart`.
- Dashboard admin/staff/driver: `zapieapp/lib/features/admin/admin_dashboard_screen.dart`.
- Repozytorium HTTP checkout/admin: `zapieapp/lib/data/repositories/checkout_repository.dart`, `admin_dashboard_repository.dart`.

## 6) QA / testy
- Testy funkcjonalne backendu: `my_fastapi_project/qa/tests/*.py`.
- Scenariusze i smoke:
  - `my_fastapi_project/qa/scenarios/`
  - `my_fastapi_project/qa/run_e2e_smoke.ps1`
  - `my_fastapi_project/qa/run_e2e_smoke.sh`
  - `my_fastapi_project/qa/run_smoke_order_flow.py`
- Aktualnie pokrywane scenariusze skupiaja sie na glownej sciezce: user -> employee -> driver.

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

## 8) Deploy i infra (skrot)
- CI dla API: `.github/workflows/deploy-api-containerapp.yml` (trigger: push do main + workflow_dispatch).
- GitHub Actions uzywa federated credentials (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) + variables ACA/ACR.
- Azure Container App secrets:
  - `mssql-conn-str`
  - `jwt-secret-key`
- Healthcheck po deployu: `https://<container-app-fqdn>/health` oraz `https://<container-app-fqdn>/health/db`.

## 9) Przydatne uwagi operacyjne
- Sprawdzaj zgodnosc subskrypcji i resource group przed zmianami.
- Nie zapisuj sekretow w kodzie repo.
- Przy zmianach migracyjnych/seedu uruchom najpierw /health/db, potem glowne endpointy klienta i order flow.
