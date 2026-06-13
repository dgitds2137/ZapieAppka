# Changelog Agent

## Cel

Ten plik jest operacyjnym dziennikiem zmian dla kolejnych watkow z Codexem.

Uzycie:
- `AGENTS.md` traktuj jako stan projektu i szybki onboarding.
- `CHANGELOG_AGENT.md` traktuj jako os czasu: co zostalo zrobione, kiedy i gdzie w kodzie.
- W nowym watku najlepiej wskazywac oba pliki, jesli potrzebny jest szybki kontekst bez ponownego przekopywania calego repo.

## Format wpisu

Kazdy wpis powinien miec:
- timestamp w czasie lokalnym
- krotki tytul
- zakres backend/frontend/infra/testy
- najwazniejsze pliki lub endpointy
- status walidacji, jesli byla

Szablon:

```md
## YYYY-MM-DD HH:mm:ss +TZ - Tytul zmiany

- Zakres:
- Backend:
- Frontend:
- Testy:
- Pliki:
- Uwagi do kolejnych watkow:
```

---

## 2026-06-13 11:45:00 +02:00 - Frontend callback success-path testability

- Zakres: domkniecie testowalnosci success path `Google OAuth callback -> save session -> dashboard` po stronie Flutter web/frontend.
- Backend:
  - bez zmian
- Frontend:
  - `AuthCallbackScreen` przyjmuje wstrzykiwany `http.Client`, bez zmiany flow produkcyjnego
  - dopisano widget test sukcesu callbacku, ktory sprawdza:
    - `POST /google-auth/callback`
    - zapis `AuthSession`
    - redirect na dashboard
- Testy:
  - `flutter test`
  - wynik: `15 tests passed`
- Pliki:
  - `zapieapp/lib/features/auth/auth_callback_screen.dart`
  - `zapieapp/test/widget_test.dart`
- Uwagi do kolejnych watkow:
  - Google auth frontend ma teraz pokrycie dla error path i success path callbacku bez potrzeby klikania w realny ekran Google

## 2026-06-13 12:25:00 +02:00 - Android Google Sign-In foundation

- Zakres: przygotowanie poprawnej sciezki Google login dla Androida bez browserowego custom-scheme OAuth callback.
- Backend:
  - dodano `POST /google-auth/mobile`
  - endpoint przyjmuje Google ID token, weryfikuje go po stronie backendu i konczy standardowa sesja aplikacji
  - dodano regresje backendowe dla mobile Google auth
- Frontend:
  - Android przestaje polegac na browserowym `zapieapp://auth/callback` dla Google
  - dodano natywny `google_sign_in` dla Androida
  - frontend wysyla Google ID token do backendu i zapisuje `AuthSession` bez callback screen
  - dodano frontendowy contract test repo dla `POST /google-auth/mobile`
- Testy:
  - przygotowane do odpalenia `python my_fastapi_project/tests/run_google_oauth_foundation_suite.py`
  - przygotowane do odpalenia `flutter test`
- Pliki:
  - `my_fastapi_project/models.py`
  - `my_fastapi_project/oauth_router.py`
  - `my_fastapi_project/oauth_service.py`
  - `my_fastapi_project/requirements.txt`
  - `my_fastapi_project/tests/test_google_oauth_foundations.py`
  - `my_fastapi_project/tests/test_google_oauth_endpoints.py`
  - `my_fastapi_project/tests/run_google_oauth_foundation_suite.py`
  - `zapieapp/pubspec.yaml`
  - `zapieapp/lib/data/repositories/social_auth_repository.dart`
  - `zapieapp/lib/features/auth/login_screen.dart`
  - `zapieapp/test/qa/qa_frontend_flow_contract_test.dart`
- Uwagi do kolejnych watkow:
  - do pelnego uruchomienia Androida w Google Cloud trzeba jeszcze utworzyc Android OAuth client dla `pl.zapieapp.mobile` / `pl.zapieapp.mobile.dev` z poprawnym SHA-1

## 2026-06-07 22:40:36 +02:00 - Google OAuth foundations

- Zakres: postawienie technicznych fundamentow pod `Login with Google` bez pelnego prod rollout.
- Backend:
  - dodano `GET /google-auth/start`
  - dodano `POST /google-auth/callback`
  - backend generuje podpisany `state`, waliduje `redirect_uri` i whitelistuje `GOOGLE_AUTH_ALLOWED_REDIRECT_URIS`
  - callback finalizuje flow do standardowej sesji aplikacji (`jwt` + `session_token`)
  - dodano helper `UserService.login_or_register_google_user(...)`
- Frontend:
  - ekran logowania Google pobiera `authorization_url` z backendu zamiast skladac URL lokalnie
  - callback auth wysyla JSON do backendu
  - frontend umie odczytac `state` w formacie JWT payload, nie tylko prosty base64 JSON
  - dodano `SocialAuthRepository`
- Testy:
  - `python my_fastapi_project/tests/run_google_oauth_foundation_suite.py`
  - wynik: `9/9 passed`
- Pliki:
  - `my_fastapi_project/oauth_service.py`
  - `my_fastapi_project/oauth_router.py`
  - `my_fastapi_project/main.py`
  - `my_fastapi_project/config.py`
  - `my_fastapi_project/.env.example`
  - `zapieapp/lib/features/auth/login_screen.dart`
  - `zapieapp/lib/features/auth/auth_callback_screen.dart`
  - `zapieapp/lib/data/repositories/social_auth_repository.dart`
  - `my_fastapi_project/tests/test_google_oauth_foundations.py`
  - `my_fastapi_project/tests/test_google_oauth_endpoints.py`
  - `my_fastapi_project/tests/run_google_oauth_foundation_suite.py`
- Uwagi do kolejnych watkow:
  - kolejny praktyczny krok to podpiecie realnych danych z Google Cloud Console
  - trzeba ustalic finalne redirect URI dla web/dev/mobile
  - Apple login nadal jest tylko frontendowym placeholderem, nie ma jeszcze backendowego flow

## 2026-06-13 11:20:00 +02:00 - Google OAuth regression coverage for local web

- Zakres: domkniecie brakujacych regresji testowych po realnym uruchomieniu Google auth na Azure + Flutter web.
- Backend:
  - dopisano test startu Google bez `email`
  - dopisano test callbacku bez hintu e-mail
  - dopisano test odrzucenia mismatchu miedzy hintem a profilem Google
  - rozszerzono endpoint contract test o pelny payload sesji callbacku
  - zaktualizowano `run_google_oauth_foundation_suite.py`, aby nowe przypadki byly uruchamiane z jednej komendy
- Frontend:
  - zaktualizowano widget smoke pod nowy copy Google loginu
  - dopisano widget regresyjny dla route `/auth/callback?...` i ekranu bledu callbacku
  - dopisano repo contract test dla `startGoogleAuth(email: null, ...)`
- Testy:
  - nieuruchomione w tym watku; zmiany przygotowane pod lokalne odpalenie `python my_fastapi_project/tests/run_google_oauth_foundation_suite.py` oraz `flutter test`
- Pliki:
  - `my_fastapi_project/tests/test_google_oauth_foundations.py`
  - `my_fastapi_project/tests/test_google_oauth_endpoints.py`
  - `my_fastapi_project/tests/run_google_oauth_foundation_suite.py`
  - `zapieapp/test/widget_test.dart`
  - `zapieapp/test/qa/qa_frontend_flow_contract_test.dart`
- Uwagi do kolejnych watkow:
  - jesli bedzie potrzebny pelny widget test sukcesu callbacku, warto najpierw wydzielic klient HTTP z `AuthCallbackScreen`, zamiast mockowac globalny `http.post`

## 2026-06-07 22:00:00 +02:00 - Kitchen ETA controls + admin catalog QA

- Zakres: domkniecie sterowania ETA kuchni i testow katalogu admina.
- Backend:
  - dodano runtime setting `kitchen_eta_override_minutes`
  - dodano `PATCH /admin/catalog/kitchen-eta`
  - ETA dla zapiekanek liczy sie z bucketow kolejkowych + override kuchni
- Frontend:
  - dashboard admina pokazuje i edytuje reczny narzut kuchni
  - katalog admina ma dopracowane sterowanie cena i dostepnoscia
- Testy:
  - backendowe QA dla `kitchen-eta`
  - frontendowy contract test repo admin/catalog
- Pliki:
  - `TIME_ZAPIEKANKI_LOGIC.md`
  - `PRODUCT_PRICE_CONTROL_LOGIC.md`
  - `my_fastapi_project/tests/test_kitchen_eta_logic.py`
  - `my_fastapi_project/tests/test_admin_kitchen_eta_endpoint.py`
  - `my_fastapi_project/qa/tests/test_20_admin_kitchen_eta_override.py`
  - `my_fastapi_project/qa/tests/test_21_admin_catalog_price_update.py`
  - `zapieapp/lib/features/admin/admin_dashboard_screen.dart`
- Uwagi do kolejnych watkow:
  - jesli bedzie potrzeba, nastepny etap to audit trail zmian cen i zmian ETA

## 2026-06-07 21:30:00 +02:00 - Repo merged to main

- Zakres: scalono `latest-features` do `main` i wypchnieto na remote.
- Git:
  - merge commit na `main`: `47670a5`
  - ostatni feature commit przed merge: `bce5b0e`
- Uwagi do kolejnych watkow:
  - dalsze prace mozna juz opierac na `main`, a nie tylko na `latest-features`
