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
| Model batchowy pieca istnieje w backendzie | helpery i logika w `checkout_service.py`, testy `test_kitchen_eta_logic.py` | `kod: TAK / runtime: NIE` |
| Rozroznienie `in_oven` vs `waiting queue` wplywa na ETA | `_get_current_oven_load`, `_count_waiting_zapiekanki_queue_pieces`, batch metrics, testy queue delay | `kod: TAK / runtime: NIE` |
| Preview ETA przed finalnym checkoutem istnieje | `POST /checkout/eta-preview`, test endpointu backend, test repo Flutter | `kod: TAK / runtime: NIE` |
| Active checkout niesie `kitchen_*` | `GET /checkout/active`, backend test endpointu, frontend contract test repo | `kod: TAK / runtime: NIE` |
| Admin dashboard niesie `kitchen_*` | `_build_admin_order`, mapowanie modelu Flutter, contract test repo admin dashboard | `kod: TAK / runtime: NIE` |
| Guard `in_oven` blokuje konflikt batchu | `update_admin_order_status(...)`, backend regression test 409 | `kod: TAK / runtime: NIE` |
| Front klienta uzywa backendowego ETA w krytycznych miejscach | `dashboard_screen.dart`, `order_tracking_screen.dart`, testy modeli/repo | `kod: TAK / runtime: NIE` |
| Front admina interpretuje diagnostyke pieca | `admin_dashboard_screen.dart`, model mapping, kontrakty repo | `kod: TAK / runtime: NIE` |
| Regressions sa dopisane dla warstwy backendowej | suite `run_time_zapiekanki_phase2_suite.py` + testy endpointowe/service | `kod: TAK / wykonanie: NIE` |
| Regressions sa dopisane dla warstwy Flutter repo/model | `qa_frontend_flow_contract_test.dart`, `qa_time_zapiekanki_phase2_models_test.dart` | `kod: TAK / wykonanie: NIE` |

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
Status: `brak dowodu`

Brakuje przejscia przez scenariusze runtime na `Chrome + Azure backend`:
- 1 duza zapiekanka,
- 4 duze zapiekanki,
- 7 duzych zapiekanek,
- 10 duzych zapiekanek,
- 14+ duzych zapiekanek,
- koszyk mieszany,
- `kids / 25cm / VAC`,
- override kuchni.

### B. Potwierdzenie spojnosci warstw
Status: `brak dowodu`

Trzeba jeszcze potwierdzic, ze dla tych samych scenariuszy:
- preview koszyka,
- finalny checkout,
- active order,
- tracking,
- admin diagnostics

pokazuja wyniki logicznie spojne.

### C. Uruchomienie testow
Status: `brak dowodu`

Testy sa dopisane, ale nie ma jeszcze wyniku wykonania:
- `python my_fastapi_project/tests/run_time_zapiekanki_phase2_suite.py`
- `flutter test`

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
- smoke runtime zostal przeprowadzony na `Chrome + Azure backend`,
- nie ma krytycznych rozjazdow miedzy preview, checkoutem, active order i admin diagnostics,
- wszystkie odchylenia zostaly poprawione albo swiadomie zaakceptowane jako poza zakresem celu.

---

## 6. Najkrotsza sciezka do zamkniecia celu

1. Odpalic:
   - `python my_fastapi_project/tests/run_time_zapiekanki_phase2_suite.py`
2. Przejsc `TIME_ZAPIEKANKI_PHASE2_SMOKE_COMMANDS.md`
3. Zweryfikowac wyniki wedlug `TIME_ZAPIEKANKI_PHASE2_SMOKE.md`
4. Poprawic ewentualne mismatchy
5. Dopiero wtedy zrobic finalny completion audit
