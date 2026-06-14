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

## 2026-06-13 19:10:00 +02:00 - Apple Sign In foundation preparation

- Zakres: przygotowanie po naszej stronie fundamentu `Sign in with Apple` bez finalnej konfiguracji w Apple Developer.
- Backend:
  - dodano `GET /apple-auth/start`
  - dodano `POST /apple-auth/callback`
  - dodano backendowy bridge callback `GET|POST /apple-auth/return`, zeby Apple moglo wrocic przez server-side redirect do frontendu
  - dodano konfiguracje `APPLE_AUTH_*` w `config.py`
  - dodano serwis `AppleOAuthService` z podpisanym `state`, `nonce`, wymiana `code -> token`, budowa Apple `client_secret` JWT i walidacja Apple `id_token`
  - flow po sukcesie konczy sie standardowa sesja aplikacji, tak samo jak przy Google
  - workflow deployu API w Azure Container Apps umie teraz opcjonalnie utrzymac `APPLE_AUTH_*` przy kolejnych deployach, bez wywalania srodowiska gdy Apple jeszcze nie jest skonfigurowany
  - helper tworzenia/uzycia kont social auth zostal uogolniony z nazewnictwa `google_*` do provider-neutral `oauth/social auth`
- Frontend:
  - przycisk Apple przestaje skladac URL lokalnie i korzysta z backendowego `apple-auth/start`
  - Apple nie wymaga juz wpisania e-maila przed uruchomieniem flow
  - callback frontendowy wykorzystuje istniejacy generic flow `/${provider}-auth/callback`
  - frontend dostaje osobny `APPLE_AUTH_REDIRECT_URI`, zeby Apple moglo miec dedykowany redirect niezalezny od Google
  - callback screen wysyla teraz poprawny provider-specific `redirect_uri`, wiec Apple nie polega juz przypadkiem na bazowym redirect URI Google
  - callback screen umie tez przejac `user` z pierwszego logowania Apple i przekazac `name` do backendu przy finalizacji sesji
- Testy:
  - dopisano backendowe foundation/endpoint tests dla Apple start + callback
  - dopisano backendowy test bridge callbacku `apple-auth/return`
  - dopisano tez test POST/form dla `apple-auth/return`, zeby nie polegac tylko na query-string variant
  - dopisano frontendowy contract test dla `startAppleAuth(...)`
  - dopisano widget test sukcesu callbacku Apple
  - dopisano widget regression pod provider-specific Apple redirect URI w callback exchange
  - nieuruchomione w tym watku; przygotowane pod `python my_fastapi_project/tests/run_google_oauth_foundation_suite.py` oraz `flutter test`
- Pliki:
  - `my_fastapi_project/config.py`
  - `my_fastapi_project/models.py`
  - `my_fastapi_project/oauth_router.py`
  - `my_fastapi_project/oauth_service.py`
  - `my_fastapi_project/.env.example`
  - `my_fastapi_project/tests/test_google_oauth_foundations.py`
  - `my_fastapi_project/tests/test_google_oauth_endpoints.py`
  - `my_fastapi_project/tests/run_google_oauth_foundation_suite.py`
  - `zapieapp/lib/data/repositories/social_auth_repository.dart`
  - `zapieapp/lib/features/auth/auth_callback_screen.dart`
  - `zapieapp/lib/data/models/social_auth.dart`
  - `zapieapp/lib/features/auth/login_screen.dart`
  - `zapieapp/test/widget_test.dart`
  - `zapieapp/test/qa/qa_frontend_flow_contract_test.dart`
  - `APPLE_AUTH_PREP.md`
- Uwagi do kolejnych watkow:
  - z naszej strony zostaje glownie konfiguracja danych z Apple Developer: `Services ID`, `Team ID`, `Key ID`, `.p8 private key`, redirect URIs
  - po uzyskaniu konta Apple Developer trzeba wpisac env na Azure i wykonac pierwszy realny smoke test Apple loginu

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

## 2026-06-14 13:10:00 +02:00 - ETA zapiekanek doprecyzowane do sztuk duzych pozycji

- Zakres: uporzadkowanie specyfikacji ETA zapiekanek i zblizenie implementacji do realnej logiki kuchni.
- Dokumentacja:
  - `TIME_ZAPIEKANKI_LOGIC.md` przepisane na czysta, aktualna specyfikacje
  - usunieto historyczny opis, ktory mieszal target biznesowy z dawnym stanem wdrozenia
- Backend:
  - ETA dla zapiekanek liczy teraz sztuki duzych, goracych zapiekanek zamiast samej liczby zamowien z zapiekankami
  - z kolejki wykluczane sa pozycje `kids`, `25cm`, `VAC`, `frozen`
  - zachowano wyjatek `0 aktywnych + 1 nowa duza zapiekanka = 6 min`
  - kolejne buckety sa liczone po lacznej liczbie sztuk: `1-3 -> 7`, `4-6 -> 10`, `7-13 -> 15`, `14+ -> 20`
  - reczny override kuchni pozostaje bez zmian: `0/10/20/30/40`, cap finalnego ETA `60`
- Testy:
  - zaktualizowano `my_fastapi_project/tests/test_kitchen_eta_logic.py`
  - dopisano scenariusze dla liczenia sztuk, wykluczen `kids/VAC` i pierwszej pojedynczej zapiekanki za `6 min`

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

## 2026-06-14 16:40:00 +02:00 - ETA zapiekanek Phase 2 slice 1: batch metrics + admin diagnostics MVP

- Zakres: pierwszy wykonawczy slice Phase 2 oparty o model batchy pieca dla duzych zapiekanek.
- Backend:
  - dodano metryki batchowe zapiekanek rozrozniajace `current_oven_load`, `waiting_queue`, `slots_before_order`, `slots_used_by_order`
  - checkout ETA dla zapiekanek korzysta teraz z modelu batchowego zamiast prostego sumowania aktywnej kolejki
  - aktywne opoznienie zamowienia (`remaining_eta_minutes` z queue delay) jest liczone po pozycji batchowej, nie tylko po overflow
  - API checkout i admin dashboard zwraca nowe pola diagnostyczne `kitchen_*`
  - backend blokuje przejscie na `in_oven`, gdy zamowienie nie miesci sie jeszcze w aktualnym wsadzie
- Frontend:
  - model `AdminDashboardOrder` mapuje nowe pola `kitchen_*`
  - karty zamowien admina pokazuja lekki sygnal batchu pieca
  - dialog szczegolow zamowienia pokazuje sekcje `Diagnostyka pieca` z loadem, kolejka przed zamowieniem, batchem, slotami i automatycznym ETA
  - komunikat o braku miejsca w piecu korzysta teraz z danych batchowych zamiast tylko z prostego `oven_load/oven_capacity`
- Testy:
  - rozszerzono backendowe testy `test_kitchen_eta_logic.py` o scenariusze batch metrics i queue delay
  - nieuruchomione w tym watku
- Pliki:
  - `my_fastapi_project/checkout_service.py`
  - `my_fastapi_project/models.py`
  - `my_fastapi_project/tests/test_kitchen_eta_logic.py`
  - `zapieapp/lib/data/models/admin_dashboard.dart`
  - `zapieapp/lib/features/admin/admin_dashboard_screen.dart`
- Uwagi do kolejnych watkow:
  - kolejny sensowny slice to frontend klienta: spiac koszyk / checkout / active order z nowymi danymi ETA i sprawdzic duze koszyki 4/7/10 sztuk

## 2026-06-14 17:05:00 +02:00 - ETA zapiekanek Phase 2 slice 2: klient korzysta z backendowego ETA aktywnego zamowienia

- Zakres: dopiecie warstwy klienta tak, aby aktywne zamowienie i tracking nie opieraly sie juz tylko na historycznym `received_order.eta_minutes`.
- Frontend:
  - `CheckoutVerificationResponse` mapuje nowe pola `kitchen_*` z backendu i udostepnia helpery `effectiveBaseEtaMinutes` oraz `effectiveRemainingEtaMinutes`
  - pasek aktywnego zamowienia w dashboardzie klienta liczy progres i display ETA z nowych helperow
  - ekran trackingu zamowienia pokazuje ETA z `effectiveRemainingEtaMinutes`, a nie z surowego payloadu wyslanego przy checkoutcie
  - copy koszyka zostalo zmiekczone do `ok.` / `Szacunek`, bo przed checkoutem frontend nadal nie ma osobnego endpointu do pelnej batchowej kalkulacji kolejki
- Testy:
  - nieuruchomione w tym watku
- Pliki:
  - `zapieapp/lib/data/models/checkout_verification.dart`
  - `zapieapp/lib/features/dashboard/dashboard_screen.dart`
  - `zapieapp/lib/features/orders/order_tracking_screen.dart`
- Uwagi do kolejnych watkow:
  - aby domknac pelna spojnosc ETA klienta jeszcze przed kliknieciem platnosci, warto dodac osobny backendowy endpoint preview dla checkoutu albo reuse w lekkiej formie istniejacej logiki weryfikacji bez finalnego zapisu zamowienia

## 2026-06-14 17:35:00 +02:00 - ETA zapiekanek Phase 2 slice 3: backend preview ETA + integracja koszyka

- Zakres: domkniecie glownej luki Phase 2 przed finalnym checkoutem, czyli backendowego preview ETA dla koszyka bez zapisu zamowienia.
- Backend:
  - dodano `POST /checkout/eta-preview`
  - endpoint przyjmuje payload checkoutu, ale nie tworzy zamowienia; zwraca finalny preview ETA oraz pola `kitchen_*`
  - preview reuse'uje te same helpery co realny checkout: aktywnosc pozycji, planned pickup dla udek, opening delay, batch model zapiekanek, delivery buffer
- Frontend:
  - dodano model `CheckoutEtaPreviewResponse`
  - `CheckoutRepository` umie wywolac `/checkout/eta-preview`
  - ekran podsumowania koszyka odpytuje backend o preview ETA przy starcie i po zmianach koszyka / fulfillment / adresu
  - etykiety ETA w koszyku preferuja wynik preview z backendu zamiast lokalnego przyblizenia, gdy preview jest dostepny
  - aktywne zamowienie i tracking nadal korzystaja z backendowego `effectiveRemainingEtaMinutes`
- Testy:
  - nieuruchomione w tym watku
- Pliki:
  - `my_fastapi_project/models.py`
  - `my_fastapi_project/checkout_service.py`
  - `my_fastapi_project/router.py`
  - `zapieapp/lib/data/models/checkout_verification.dart`
  - `zapieapp/lib/data/repositories/checkout_repository.dart`
  - `zapieapp/lib/features/dashboard/dashboard_screen.dart`
- Uwagi do kolejnych watkow:
  - bottom bar live-cart poza ekranem podsumowania nadal pokazuje lokalny szacunek; jesli bedzie potrzeba, mozna go pozniej przepiac na ten sam preview flow
  - kolejny praktyczny krok to uruchomienie smoke na Chrome / Azure i sprawdzenie scenariuszy 1 / 4 / 7 / 10 duzych zapiekanek

## 2026-06-14 17:50:00 +02:00 - ETA zapiekanek Phase 2 slice 3a: endpoint tests dla preview ETA

- Zakres: regresje backendowe dla nowego endpointu preview ETA przed finalnym checkoutem.
- Testy:
  - dodano `test_checkout_eta_preview_endpoint.py`
  - scenariusz sukcesu sprawdza mapowanie payloadu i odpowiedz `kitchen_*`
  - scenariusz bledu sprawdza propagacje `409` z backendu
  - testy nieuruchomione w tym watku
- Pliki:
  - `my_fastapi_project/tests/test_checkout_eta_preview_endpoint.py`
- Uwagi do kolejnych watkow:
  - runtime smoke nadal jest potrzebny, ale kontrakt endpointu `/checkout/eta-preview` ma juz dedykowany test routera

## 2026-06-14 18:05:00 +02:00 - ETA zapiekanek Phase 2 smoke protocol prepared

- Zakres: przygotowanie gotowego protokolu walidacji runtime dla Phase 2 bez odpalania testow w tym watku.
- Dokumentacja:
  - dodano `TIME_ZAPIEKANKI_PHASE2_SMOKE.md`
  - dokument zawiera scenariusze 1 / 4 / 7 / 10 / 14+ duzych zapiekanek, koszyki mieszane, `kids/25cm/VAC`, override kuchni oraz checkliste mismatchow
- Uwagi do kolejnych watkow:
  - nastepny praktyczny krok to przejscie przez smoke na `Chrome + Azure backend`, a potem ewentualne poprawki juz na bazie konkretnych odchylen

## 2026-06-14 18:20:00 +02:00 - ETA zapiekanek Phase 2 smoke commands prepared

- Zakres: przygotowanie wykonawczego playbooka komend pod walidacje runtime `Chrome + Azure`.
- Dokumentacja:
  - dodano `TIME_ZAPIEKANKI_PHASE2_SMOKE_COMMANDS.md`
  - zawiera komendy healthcheck, uruchomienie Flutter web, przyklady `POST /checkout/eta-preview`, admin dashboard API oraz update override kuchni
- Uwagi do kolejnych watkow:
  - majac ten plik i `TIME_ZAPIEKANKI_PHASE2_SMOKE.md`, mozna przejsc koncowy smoke bez ponownego skladania procedury od zera

## 2026-06-14 18:35:00 +02:00 - ETA zapiekanek Phase 2 consolidated test runner

- Zakres: wygodny lokalny runner testow dla calej warstwy ETA zapiekanek Phase 2.
- Testy:
  - dodano `my_fastapi_project/tests/run_time_zapiekanki_phase2_suite.py`
  - runner zbiera w jednym miejscu:
    - testy bucketow i batch metrics
    - testy preview ETA na poziomie serwisu
    - testy endpointu admin kitchen eta
    - testy endpointu `/checkout/eta-preview`
- Uwagi do kolejnych watkow:
  - przed runtime smoke mozna lokalnie odpalic jedna komende zamiast skladac recznie zestaw testow

## 2026-06-14 18:45:00 +02:00 - ETA zapiekanek Phase 2 completion audit prepared

- Zakres: przygotowanie finalnego audytu stanu Phase 2 z rozdzieleniem implementacji od brakujacego proof runtime.
- Dokumentacja:
  - dodano `TIME_ZAPIEKANKI_PHASE2_COMPLETION_AUDIT.md`
  - plik wskazuje, co jest juz w kodzie i czego nadal brakuje do uczciwego oznaczenia celu jako `complete`
- Uwagi do kolejnych watkow:
  - nastepny ruch powinien juz przejsc z etapu implementacji do etapu dowodzenia: test runner + smoke runtime + poprawki z obserwacji

## 2026-06-14 19:05:00 +02:00 - ETA zapiekanek Phase 2 frontend contract coverage for preview ETA

- Zakres: domkniecie brakujacej warstwy kontraktowej Flutter repo dla backendowego preview ETA.
- Frontend:
  - dopisano test repo `HttpCheckoutRepository.previewCheckoutEta(...)`
  - test sprawdza payload `POST /checkout/eta-preview`
  - test sprawdza mapowanie odpowiedzi `eta_minutes`, `available_from` oraz pol `kitchen_*`
  - test pilnuje, ze preview ETA nie zapisuje `cachedActiveCheckout`
- Dokumentacja:
  - audit Phase 2 doprecyzowany o frontendowy kontrakt preview ETA
  - audit wyraznie rozroznia teraz istnienie testu od braku dowodu jego wykonania
- Pliki:
  - `zapieapp/test/qa/qa_frontend_flow_contract_test.dart`
  - `TIME_ZAPIEKANKI_PHASE2_COMPLETION_AUDIT.md`
- Uwagi do kolejnych watkow:
  - kolejnym ruchem powinno byc juz odpalenie `flutter test` oraz backendowego runnera, a potem runtime smoke na `Chrome + Azure`

## 2026-06-14 19:20:00 +02:00 - ETA zapiekanek Phase 2 execution backlog hardened

- Zakres: przelozenie stanu wdrozenia Phase 2 na bardziej wykonawczy backlog z priorytetami, kontraktami danych i warunkami zamkniecia.
- Dokumentacja:
  - dodano `TIME_ZAPIEKANKI_PHASE2_BACKLOG.md`
  - backlog rozdziela:
    - co jest juz wdrozone,
    - co nadal wymaga proof wykonania,
    - jaka jest rekomendowana kolejnosc prac
  - dopisano tez sekcje roboczego kontraktu danych `kitchen_*`, zeby backend, frontend i admin operowaly tym samym slownikiem
- Pliki:
  - `TIME_ZAPIEKANKI_PHASE2_BACKLOG.md`
- Uwagi do kolejnych watkow:
  - przy dalszym goalu nie trzeba juz wracac do poziomu ogolnego planu; ten backlog nadaje sie bezposrednio do odpalania etapow proof/test/smoke

## 2026-06-14 19:35:00 +02:00 - ETA zapiekanek Phase 2 proof runbook prepared

- Zakres: przygotowanie wykonawczej instrukcji dowodowej do test runnera, `flutter test` i smoke runtime.
- Dokumentacja:
  - dodano `TIME_ZAPIEKANKI_PHASE2_PROOF_RUNBOOK.md`
  - runbook ustala:
    - dokladna kolejnosc uruchomien
    - kryteria PASS/FAIL
    - definicje krytycznych rozjazdow
    - szablon wpisu do finalnego audytu
- Pliki:
  - `TIME_ZAPIEKANKI_PHASE2_PROOF_RUNBOOK.md`
- Uwagi do kolejnych watkow:
  - majac ten plik, kolejny etap goalu powinien juz przejsc z dokumentacji do rzeczywistego proof execution albo do poprawek wynikajacych z uruchomionych testow

## 2026-06-14 19:50:00 +02:00 - ETA zapiekanek Phase 2 execution log template added

- Zakres: dodanie roboczego dziennika wykonania pod realne wpisy z test runnera i smoke runtime.
- Dokumentacja:
  - dodano `TIME_ZAPIEKANKI_PHASE2_EXECUTION_LOG.md`
  - plik ma gotowe sekcje pod:
    - backend tests
    - frontend tests
    - Azure health
    - API preview smoke
    - frontend Chrome smoke
    - admin smoke
    - otwarte odchylenia
    - decyzje zamykajace
- Pliki:
  - `TIME_ZAPIEKANKI_PHASE2_EXECUTION_LOG.md`
- Uwagi do kolejnych watkow:
  - przy realnym proof execution mozna juz wpisywac wyniki bezposrednio do jednego pliku, a potem strescic je do completion audytu

## 2026-06-14 20:05:00 +02:00 - ETA zapiekanek Phase 2 frontend model coverage strengthened

- Zakres: dopiecie lekkiej, ale praktycznej warstwy regresji Flutter dla modeli Phase 2 bez wchodzenia jeszcze w ciezsze widgety admina.
- Frontend:
  - dodano testy modelowe `CheckoutVerificationResponse` dla:
    - mapowania `kitchen_*`
    - `effectiveBaseEtaMinutes`
    - `effectiveRemainingEtaMinutes`
    - `hasKitchenDiagnostics`
  - dodano test modelowy `AdminDashboardOrder` dla mapowania diagnostyki pieca i flag operatora
- Dokumentacja:
  - audit Phase 2 doprecyzowany o frontendowe testy modelowe dla warstwy `kitchen_*`
- Pliki:
  - `zapieapp/test/qa/qa_time_zapiekanki_phase2_models_test.dart`
  - `TIME_ZAPIEKANKI_PHASE2_COMPLETION_AUDIT.md`
- Uwagi do kolejnych watkow:
  - ten slice nie zastępuje runtime smoke, ale zmniejsza ryzyko cichych regresji w mapowaniu danych backend -> frontend

## 2026-06-14 20:20:00 +02:00 - ETA zapiekanek Phase 2 backend admin guard coverage strengthened

- Zakres: dopiecie regresji backendowych dla najbardziej ryzykownych elementow adminowego flow kuchni w Phase 2.
- Backend:
  - dodano test helpera `_build_admin_order(...)`, ktory sprawdza mapowanie `kitchen_*` i wylaczenie `can_mark_in_oven` dla zamowienia wpadajacego poza pierwszy batch
  - dodano test `update_admin_order_status(...)`, ktory potwierdza `409`, gdy operator probuje oznaczyc `in_oven` zamowienie niemieszczace sie w aktualnym wsadzie
  - runner `run_time_zapiekanki_phase2_suite.py` obejmuje teraz takze te dwa przypadki
- Dokumentacja:
  - audit Phase 2 doprecyzowany o backendowe regresje dla guardu `in_oven`
- Pliki:
  - `my_fastapi_project/tests/test_kitchen_eta_logic.py`
  - `my_fastapi_project/tests/run_time_zapiekanki_phase2_suite.py`
  - `TIME_ZAPIEKANKI_PHASE2_COMPLETION_AUDIT.md`
- Uwagi do kolejnych watkow:
  - po tym slicie glowne ryzyko kodowe Phase 2 jest juz bardziej po stronie runtime smoke niz po stronie brakujacych regresji jednostkowych

## 2026-06-14 20:35:00 +02:00 - ETA zapiekanek Phase 2 frontend repo contract coverage extended to active/admin API

- Zakres: dopiecie brakujacej kontraktowej warstwy Flutter dla dwoch runtime-krytycznych odpowiedzi API: aktywnego checkoutu i dashboardu admina.
- Frontend:
  - dodano test repo `fetchActiveCheckout(...)`, ktory sprawdza mapowanie `kitchen_*`, getters ETA i cache aktywnego zamowienia
  - dodano test repo `fetchDashboard(...)`, ktory sprawdza mapowanie diagnostyki pieca w `inProgressOrders`
- Dokumentacja:
  - audit Phase 2 doprecyzowany o kontrakty repo dla `/checkout/active` i `/admin/dashboard`
- Pliki:
  - `zapieapp/test/qa/qa_frontend_flow_contract_test.dart`
  - `TIME_ZAPIEKANKI_PHASE2_COMPLETION_AUDIT.md`
- Uwagi do kolejnych watkow:
  - po tym slicie glowne luki testowe Phase 2 sa juz bardziej w runtime i widgetach niz w kontraktach modeli/repo

## 2026-06-14 20:50:00 +02:00 - ETA zapiekanek Phase 2 backend active checkout endpoint coverage added

- Zakres: dopiecie backendowego kontraktu endpointowego dla runtime-krytycznej sciezki `/checkout/active`.
- Backend:
  - dodano test sukcesu `/checkout/active`, ktory sprawdza serializacje `kitchen_*`
  - dodano test pustej odpowiedzi `null`, gdy aktywne zamowienie nie istnieje
  - runner `run_time_zapiekanki_phase2_suite.py` obejmuje teraz takze ten endpoint
- Dokumentacja:
  - audit Phase 2 doprecyzowany o backendowy endpoint test `/checkout/active`
- Pliki:
  - `my_fastapi_project/tests/test_checkout_active_endpoint_phase2.py`
  - `my_fastapi_project/tests/run_time_zapiekanki_phase2_suite.py`
  - `TIME_ZAPIEKANKI_PHASE2_COMPLETION_AUDIT.md`
- Uwagi do kolejnych watkow:
  - po tym slicie glowne sensowne braki dowodowe siedza juz prawie wylacznie w uruchomieniu testow i smoke runtime

## 2026-06-14 21:05:00 +02:00 - ETA zapiekanek Phase 2 proof start pack added

- Zakres: przygotowanie najkrotszego wejscia operacyjnego w proof execution bez wracania do pelnego runbooka.
- Dokumentacja:
  - dodano `TIME_ZAPIEKANKI_PHASE2_PROOF_START_PACK.md`
  - plik zawiera:
    - 3 glowne komendy
    - 3 kluczowe scenariusze smoke
    - wskazanie jednego miejsca wpisania wynikow
- Pliki:
  - `TIME_ZAPIEKANKI_PHASE2_PROOF_START_PACK.md`
- Uwagi do kolejnych watkow:
  - przy dalszej pracy nie ma juz potrzeby rozbudowy dokumentacji; naturalny nastepny ruch to uruchomienie proof execution albo poprawki po wynikach

## 2026-06-14 21:20:00 +02:00 - ETA zapiekanek Phase 2 evidence matrix added to completion audit

- Zakres: uszczelnienie completion audytu przez rozpisanie wymagan Phase 2 na macierz dowodow.
- Dokumentacja:
  - `TIME_ZAPIEKANKI_PHASE2_COMPLETION_AUDIT.md` dostal sekcje `Macierz wymagan i aktualnych dowodow`
  - macierz rozdziela:
    - dowod istnienia kodu
    - dowod istnienia regresji
    - brak dowodu wykonania / runtime
- Pliki:
  - `TIME_ZAPIEKANKI_PHASE2_COMPLETION_AUDIT.md`
- Uwagi do kolejnych watkow:
  - dzieki tej sekcji kolejny etap nie powinien juz polegac na domyslaniu sie, czy temat jest „prawie gotowy”; widac wprost, co jest jeszcze nieudowodnione

## 2026-06-14 21:35:00 +02:00 - ETA zapiekanek Phase 2 proof runner script added

- Zakres: dodanie praktycznego skryptu uruchomieniowego spinajacego proof execution Phase 2.
- Dokumentacja / tooling:
  - dodano `run_time_zapiekanki_phase2_proof.ps1`
  - skrypt umie:
    - odpalic backend suite
    - odpalic `flutter test`
    - sprawdzic `/health` i `/health/db`
    - zapisac logi do `artifacts/time_zapiekanki_phase2/<timestamp>/`
    - wypisac entrypoint do smoke na Chrome
- Dokumentacja:
  - audit Phase 2 doprecyzowany, ze proof runner jest juz gotowym artefaktem operacyjnym
- Pliki:
  - `run_time_zapiekanki_phase2_proof.ps1`
  - `TIME_ZAPIEKANKI_PHASE2_COMPLETION_AUDIT.md`
- Uwagi do kolejnych watkow:
  - po tym ruchu naturalny nastepny krok nie jest juz implementacyjny, tylko wykonawczy: uruchomic runner, przejsc smoke i wpisac outcome do execution logu

## 2026-06-14 21:50:00 +02:00 - ETA zapiekanek Phase 2 admin status endpoint coverage added

- Zakres: dopiecie backendowego kontraktu endpointowego dla adminowego update statusu zamowienia.
- Backend:
  - dodano test sukcesu `PATCH /admin/orders/{id}/processing-status` z mapowaniem `kitchen_*`
  - dodano test propagacji `409` dla konfliktu `in_oven`
  - runner `run_time_zapiekanki_phase2_suite.py` obejmuje teraz rowniez te dwa przypadki
- Dokumentacja:
  - audit Phase 2 doprecyzowany o endpoint adminowego statusu jako osobny dowod kontraktowy
- Pliki:
  - `my_fastapi_project/tests/test_admin_order_processing_status_phase2_endpoint.py`
  - `my_fastapi_project/tests/run_time_zapiekanki_phase2_suite.py`
  - `TIME_ZAPIEKANKI_PHASE2_COMPLETION_AUDIT.md`
- Uwagi do kolejnych watkow:
  - po tym slicie glowne luki dowodowe sa juz praktycznie tylko wykonawcze: test execution i smoke runtime

## 2026-06-14 22:05:00 +02:00 - ETA zapiekanek Phase 2 proof runner upgraded with execution log prefill

- Zakres: podniesienie proof runnera z prostego launchera do polautomatycznego narzedzia proof flow.
- Tooling:
  - `run_time_zapiekanki_phase2_proof.ps1` umie teraz:
    - uzupelnic metadane sesji proof
    - wpisac status backend tests
    - wpisac status frontend tests
    - wpisac status Azure health
    - zapisac snapshot execution logu obok artefaktow runa
- Dokumentacja:
  - `TIME_ZAPIEKANKI_PHASE2_EXECUTION_LOG.md` doprecyzowano, ktore sekcje runner uzupelnia automatycznie
- Pliki:
  - `run_time_zapiekanki_phase2_proof.ps1`
  - `TIME_ZAPIEKANKI_PHASE2_EXECUTION_LOG.md`
- Uwagi do kolejnych watkow:
  - po tym ruchu reczne przepisywanie wynikow dla testow i healthcheckow nie jest juz potrzebne; manualnie zostaje glownie runtime smoke i decyzja koncowa

## 2026-06-14 22:20:00 +02:00 - ETA zapiekanek Phase 2 API smoke runner added

- Zakres: dodanie automatycznego runnera smoke dla backendowego preview ETA.
- Tooling:
  - dodano `run_time_zapiekanki_phase2_api_smoke.py`
  - skrypt umie:
    - wykonac scenariusze `1 / 4 / 7 / 10 / 14+ / VAC-25cm`
    - zapisac wynik do `artifacts/time_zapiekanki_phase2_api_smoke/<timestamp>/summary.json`
    - dzialac w trybie raportowym lub `--strict-clean-queue`
    - opcjonalnie wykonac smoke override po podaniu admin credentials
- Dokumentacja:
  - audit Phase 2 doprecyzowany o istnienie API smoke runnera jako osobnego artefaktu operacyjnego
- Pliki:
  - `run_time_zapiekanki_phase2_api_smoke.py`
  - `TIME_ZAPIEKANKI_PHASE2_COMPLETION_AUDIT.md`
- Uwagi do kolejnych watkow:
  - po tym ruchu nawet API smoke nie wymaga juz recznego skladania payloadow; glowny brak to nadal realne wykonanie i interpretacja wyniku
