# TIME ZAPIEKANKI - Phase 2 Completion Audit

## Cel audytu

Ten plik rozdziela dwie rzeczy:
- co zostalo juz zaimplementowane w kodzie,
- czego nadal brakuje jako dowodu wykonania, zanim temat mozna uczciwie uznac za zamkniety.

Nie jest to backlog. To jest stan domkniecia celu.

---

## 1. Zakres docelowy Phase 2

Phase 2 miala doprowadzic logike ETA zapiekanek do modelu bardziej zgodnego z praca kuchni:
- model batchowy pieca,
- rozroznienie `in_oven` vs `waiting queue`,
- diagnostyka dla admina,
- spojne ETA w checkout / active order / tracking,
- preview ETA jeszcze przed finalnym checkoutem,
- regresje testowe dla tej warstwy.

---

## 1A. Macierz wymagan i aktualnych dowodow

| Wymaganie | Aktualny dowod | Status |
| --- | --- | --- |
| Model batchowy pieca istnieje w backendzie | helpery i logika w `checkout_service.py`, testy `test_kitchen_eta_logic.py`, proof `api-preview-smoke=PASS` | `kod: TAK / runtime API: TAK / UI smoke: NIE` |
| Rozroznienie `in_oven` vs `waiting queue` wplywa na ETA | `_get_current_oven_load`, `_count_waiting_zapiekanki_queue_pieces`, batch metrics, proof scenariuszy `1/4/7/10/14` | `kod: TAK / runtime API: TAK / UI smoke: NIE` |
| Preview ETA przed finalnym checkoutem istnieje | `POST /checkout/eta-preview`, test endpointu backend, test repo Flutter, proof Azure | `kod: TAK / runtime API: TAK / UI smoke: NIE` |
| Active checkout niesie `kitchen_*` | `GET /checkout/active`, backend test endpointu, frontend contract test repo | `kod: TAK / dowod testowy: TAK / runtime UI: NIE` |
| Admin dashboard niesie `kitchen_*` | `_build_admin_order`, mapowanie modelu Flutter, contract test repo admin dashboard | `kod: TAK / dowod testowy: TAK / runtime UI: NIE` |
| Guard `in_oven` blokuje konflikt batchu | `update_admin_order_status(...)`, backend regression test 409, endpoint phase2 test | `kod: TAK / dowod testowy: TAK / runtime UI: NIE` |
| Front klienta uzywa backendowego ETA w krytycznych miejscach | `dashboard_screen.dart`, `order_tracking_screen.dart`, testy modeli/repo | `kod: TAK / dowod testowy: TAK / runtime UI: NIE` |
| Front admina interpretuje diagnostyke pieca | `admin_dashboard_screen.dart`, model mapping, kontrakty repo | `kod: TAK / dowod testowy: TAK / runtime UI: NIE` |
| Regressions sa dopisane dla warstwy backendowej | suite `run_time_zapiekanki_phase2_suite.py` + testy endpointowe/service, proof `backend-tests=PASS` | `kod: TAK / wykonanie: TAK` |
| Regressions sa dopisane dla warstwy Flutter repo/model | `qa_frontend_flow_contract_test.dart`, `qa_time_zapiekanki_phase2_models_test.dart`, proof `flutter-tests=PASS` | `kod: TAK / wykonanie: TAK` |

Interpretacja:
- `kod: TAK` oznacza, ze istnieje bezposredni dowod w plikach i testach statycznych.
- `runtime: NIE` lub `wykonanie: NIE` oznacza brak twardego dowodu z uruchomienia.

---

## 2. Co jest juz zaimplementowane

### Backend core
Status: `zaimplementowane`

- batch metrics dla zapiekanek istnieja w backendzie,
- backend liczy:
  - `current_oven_load`
  - `waiting_queue_pieces_before_order`
  - `slots_before_order`
  - `slots_used_by_order`
  - `kitchen_batch_index`
  - `kitchen_batch_count`
- ETA checkoutu zapiekanek liczy sie przez model batchowy,
- active order queue delay liczy sie po pozycji batchowej,
- backend blokuje `in_oven`, gdy zamowienie nie miesci sie w aktualnym wsadzie.

### Backend API surface
Status: `zaimplementowane`

- `CheckoutVerificationOut` zwraca pola `kitchen_*`,
- `AdminDashboardOrderOut` zwraca pola `kitchen_*`,
- istnieje endpoint `POST /checkout/eta-preview`,
- preview ETA reuse'uje logike backendu bez tworzenia zamowienia.

### Frontend admin
Status: `zaimplementowane`

- model admin dashboard mapuje pola `kitchen_*`,
- karty zamowien admina sygnalizuja batch,
- dialog szczegolow ma sekcje `Diagnostyka pieca`,
- komunikat o braku miejsca w piecu korzysta z danych batchowych.

### Frontend klient
Status: `zaimplementowane czesciowo + wystarczajaco dla celu`

- aktywne zamowienie korzysta z backendowego ETA,
- tracking korzysta z backendowego ETA,
- ekran podsumowania koszyka pyta backend o preview ETA,
- etykiety ETA w koszyku preferuja preview z backendu, gdy jest dostepny,
- lokalny copy w miejscach bez finalnego preview zostal zmiekczony do `ok.` / `Szacunek`.

### Testy kodowe
Status: `zaimplementowane, ale niezweryfikowane wykonaniem`

- testy batch metrics,
- testy queue delay,
- testy preview ETA na poziomie serwisu,
- test routera `/checkout/eta-preview`,
- frontendowy contract test repo dla `/checkout/eta-preview`,
- frontendowe testy modelowe dla mapowania `kitchen_*` i getterow ETA,
- frontendowe contract testy repo dla `/checkout/active` i `/admin/dashboard` z polami `kitchen_*`,
- backendowe regresje dla `can_mark_in_oven` i guardu `in_oven` przy konflikcie batchu,
- backendowy endpoint test dla `/checkout/active` z serializacja `kitchen_*`,
- backendowy endpoint test dla `PATCH /admin/orders/{id}/processing-status` z `kitchen_*` i konfliktem `in_oven`,
- runner zbiorczy `run_time_zapiekanki_phase2_suite.py`.

### Dokumentacja operacyjna
Status: `zaimplementowane`

- plan Phase 2,
- smoke plan,
- smoke commands,
- proof runner script,
- api preview smoke runner,
- changelog z etapami wdrozenia.

---

## 3. Czego nadal brakuje jako dowodu wykonania

### A. Runtime smoke na prawdziwym backendzie
Status: `czesciowo domkniete`

Sa juz twarde wyniki runtime API na Azure:
- 1 duza zapiekanka,
- 4 duze zapiekanki,
- 7 duzych zapiekanek,
- 10 duzych zapiekanek,
- 14+ duzych zapiekanek,
- `kids / 25cm / VAC`.

Wynik:
- `api-preview-smoke=PASS`
- runner wykryl srodowiskowy `env_kitchen_eta_offset=10`
- smoke zostal dopasowany do shared Azure runtime zamiast zakladac czysta instancje bez override.

Nadal brak twardego dowodu dla:
- manualnego `Chrome + lokalny frontend + Azure backend`
- manualnego scenariusza admin dashboard / `in_oven` guard na zywej sesji
- manualnego scenariusza override kuchni na zywym backendzie

### B. Potwierdzenie spojnosci warstw
Status: `testowo TAK / manualnie NIE`

Z testow i proofu wiemy juz, ze:
- preview API jest spojne z modelami Fluttera,
- `/checkout/active` serializuje `kitchen_*`,
- `/admin/dashboard` serializuje `kitchen_*`,
- frontendowe modele i repo mapuja te pola poprawnie.

Nadal brak manualnego dowodu end-to-end, ze:
- preview koszyka,
- finalny checkout,
- active order,
- tracking,
- admin diagnostics

sa spojne na zywej sesji UI.

### C. Uruchomienie testow
Status: `domkniete`

Sa juz wyniki wykonania:
- `python my_fastapi_project/tests/run_time_zapiekanki_phase2_suite.py` -> `PASS`
- `flutter test` -> `PASS`

---

## 4. Co nie jest blockerem do runtime, ale warto swiadomie wiedziec

### Live cart outside checkout summary
Status: `swiadomie niepelne`

Dolny live-cart poza ekranem podsumowania nadal moze pokazywac bardziej lokalny szacunek, bo nie ma tak pelnego kontekstu fulfillment/address jak ekran podsumowania checkoutu.

To nie blokuje runtime domkniecia glownej sciezki klienta, jesli:
- ekran koszyka / podsumowania pokazuje poprawny preview,
- finalny checkout i active order sa spojne.

---

## 5. Jedyna uczciwa definicja konca tego goala

Temat mozna oznaczyc jako `complete` dopiero wtedy, gdy sa jednoczesnie spelnione warunki:
- implementacja kodu istnieje,
- test runner zostal odpalony i nie wykazal regresji,
- smoke runtime API zostal przeprowadzony na Azure i nie wykazal rozjazdu logiki batch,
- smoke runtime zostal przeprowadzony na `Chrome + Azure backend` albo swiadomie zaakceptowano, ze w tym goalu konczymy na proofie API + testach kontraktowych UI,
- nie ma krytycznych rozjazdow miedzy preview, checkoutem, active order i admin diagnostics,
- wszystkie odchylenia zostaly poprawione albo swiadomie zaakceptowane jako poza zakresem celu.

---

## 6. Najkrotsza sciezka do zamkniecia celu

1. Manualnie przejsc `Chrome + lokalny frontend + Azure backend`
2. Potwierdzic preview / checkout / active order / tracking
3. Potwierdzic admin diagnostics i `in_oven` guard na zywej sesji
4. Jesli te kroki nie sa wymagane w tym goalu, swiadomie zamknac temat na podstawie:
   - `backend-tests=PASS`
   - `flutter-tests=PASS`
   - `api-preview-smoke=PASS`
   - deployed Azure endpointow
