# ZapieApp â€“ Dynamic ETA Based on Oven Load

## Change Summary

Implement automatic order ETA calculation based on the current oven workload and the number of large zapiekanki currently queued for preparation.

The goal is to provide realistic preparation times to customers while minimizing manual intervention from kitchen staff.

---

## Business Rules

### Initial State (Low Traffic)

When there are no active orders in progress:

* ETA = 6 minutes
* Applies to a single large zapiekanka order.
* This is the minimum ETA that can be displayed.

---

### Automatic ETA Progression

The system should automatically increase ETA based on the number of large zapiekanki currently awaiting preparation.

| Large Zapiekanki In Queue | Customer ETA |
| ------------------------- | ------------ |
| 1 - 3                     | 7 min        |
| 4 - 8                     | 10 min       |
| 9 - 13                    | 15 min       |
| 14+                       | 20 min       |

Notes:

* ETA should never automatically exceed 20 minutes.
* 20 minutes is considered the maximum automatic ETA.
* Queue size should be calculated from active, unpaid-cancelled orders only.
* Completed, cancelled or refunded orders must not be included.

---

## Manual Kitchen Override

Kitchen staff must be able to manually increase ETA during exceptional situations such as:

* Equipment failure
* Staff shortage
* Unexpected rush
* Supply issues
* Any operational disruption

Manual override values:

| Override Level | Final ETA |
| -------------- | --------- |
| None           | Automatic |
| +10 min        | 30 min    |
| +20 min        | 40 min    |
| +30 min        | 50 min    |
| +40 min        | 60 min    |

Maximum allowed ETA:

* 60 minutes

---

## ETA Calculation Formula

Pseudo-logic:

```text
IF active_queue_count = 0
    ETA = 6

ELSE IF active_queue_count <= 3
    ETA = 7

ELSE IF active_queue_count <= 8
    ETA = 10

ELSE IF active_queue_count <= 13
    ETA = 15

ELSE
    ETA = 20
```

Then:

```text
Final ETA = Automatic ETA + Kitchen Override
```

Examples:

* Automatic ETA = 20
* Kitchen Override = +10

Result:

```text
Final ETA = 30
```

---

## Admin Panel Requirements

Add a new kitchen setting:

```text
Kitchen ETA Override
```

Available values:

```text
0 minutes
+10 minutes
+20 minutes
+30 minutes
+40 minutes
```

Default:

```text
0 minutes
```

Changes should take effect immediately for newly created orders.

Existing orders should retain the ETA assigned at order creation.

---

## Customer Application Requirements

The customer should always see:

* Current estimated preparation time (ETA)
* Estimated ready-at timestamp
* Live ETA updates before order confirmation

Example:

```text
Estimated preparation time: 15 min
Ready around: 18:42
```

The ETA shown during checkout must match the ETA stored with the order at the moment the order is submitted.

---

## Future Enhancement (Optional)

Introduce a kitchen mode switch:

### Automatic Mode

ETA calculated using queue size rules described above.

### Manual Mode

Kitchen staff directly selects:

```text
10 min
15 min
20 min
30 min
40 min
50 min
60 min
```

When Manual Mode is enabled, queue-based calculations are ignored entirely.

---

## Rzeczywista implementacja - co mamy teraz i co blokuje

Obecny stan backendu (na dziĹ›) nie liczy jeszcze ETA klienta z kolejki duzych zapiekanek bezposrednio przy zapisie zamowienia.

Co juz dziala:

- Weryfikacja i zapis zamowienia: `_calculate_checkout_eta_minutes` liczy ETA glownie z `ProductPrepTimeSettings` i otwarcia lokalu.
- Jest logika opoznienia kolejkowego dla postepu realizacji (`_oven_queue_delay_minutes`), ale to jest doliczane do `remaining_eta` podczas statusu zamowienia, a nie do etapu tworzenia ETA klienta.
- Sa rowniez ustawienia runtime (`AppRuntimeSettings`) i helpery do zapisu/odczytu wartosci.

Co trzeba dopiac:

- Brak nowego settingu do manual overlay (`+10/+20/...`) w `AppRuntimeSettings`.
- Brak endpointu administracyjnego do zmiany tego overlayu.
- Brak jednoznacznego licznika kolejki `duzych zapiekanek czekajacych na przygotowanie` zgodnego z opisem dokumentu.
- Wykrywanie kolejkowe dla czasu do pieca dziaĹ‚a obecnie tylko dla stage'ow `in_oven` i `oven`, a dokument zaklada etapowanie â€žoczekujace na przygotowanieâ€ť dla `accepted`/`assigned`.

---

## Proponowany plan wdrozenia (minimalny, ale kompletny)

### Etap 1: model danych (runtime settings)

1. W `my_fastapi_project/sql/app_runtime_settings.sql` dodac seed:
   - `kitchen_eta_override_minutes = 0` (domyslnie brak zwiekszenia)
   - opcjonalnie `kitchen_eta_mode = auto` (tylko jesli bedzie potrzebny calkowicie reczny tryb)
2. W `CheckoutService` dodac helpery:
   - `_get_kitchen_eta_override_minutes()`
   - `_kitchen_eta_auto_bucket_minutes(oven_queue_count)`
3. Zabezpieczyc walidacje overlayu (0 / 10 / 20 / 30 / 40), Ĺ‚Ä…czny cap 60.

### Etap 2: automatyczny ETA przy tworzeniu zamowienia

1. Dodatkowa funkcja:
   - `_count_active_zapiekanki_queue_for_oven()`:
     - liczy aktywne zamowienia do przygotowania
     - wyklucza completed/cancelled
     - uwzglednia tylko zapiekanki (bez udek)
2. W `_calculate_checkout_eta_minutes`:
   - dla zamowien nie-udka:
     - bazowe ETA z bucketow:
       - 0 => 6
       - 1..3 => 7
       - 4..8 => 10
       - 9..13 => 15
       - 14+ => 20
     - `final_eta = min(base + overlay, 60)` (lub overlay 60-guard)
3. Zachowac zachowania biznesowe:
   - istniejÄ…ce zamĂłwienia nie zmieniaja `eta_minutes` po utworzeniu
   - pickup sloty i zamkniecie lokalu pozostaja w swoim calku.

### Etap 3: panel admina i API ustawien

1. W `models.py` dodac pola w `AdminCatalogOut` i payload:
   - `kitchen_eta_override_minutes`
   - `AdminCatalogKitchenEtaOverrideUpdateIn`
2. W `router.py` dodac endpoint:
   - `PATCH /admin/catalog/kitchen-eta`
3. W `CheckoutService` dodac metodÄ™:
   - `update_kitchen_eta_override(...)`
4. `get_admin_catalog` zwracac aktualna wartosc overlayu, by UI od razu je odpalalo.

Status: **zrobione**.

## Status wdrozenia (2026-06-07)

### Backend
- Etap 1: zrobione (`kitchen_eta_override_minutes`, overlay helperzy, walidacja).
- Etap 2: zrobione (automatyczny bazowy ETA przy tworzeniu zamĂłwienia oparty o kolejkÄ™ duĹĽych zapiekanek + cap 60).
- Etap 3: zrobione (`PATCH /admin/catalog/kitchen-eta`, zwrot overlay w `AdminCatalogOut`).

### Frontend
- Etap 4: wstÄ™pnie zrobione (w dashboardzie admina jest sterowanie overlayem, dane przepĹ‚ywajÄ… przez repozytoria i modele).
- Do domkniÄ™cia: przetestowaÄ‡ UX/tekst w checkoutie i potwierdziÄ‡ koĹ„cowy wording â€žready around / gotowe okoĹ‚oâ€ť.

### Testy (WYNIKI)
- `test_20_admin_kitchen_eta_override.py`: PASS
- `run_smoke_order_flow.py`: PASS
- caĹ‚y batch `my_fastapi_project/qa/tests/test_*.py` (01â€“20): PASS
- testy ETA i endpointu:
  - `my_fastapi_project/tests/test_kitchen_eta_logic.py`
  - `my_fastapi_project/tests/test_admin_kitchen_eta_endpoint.py`
  - uruchomione bez `pytest`, jako bezpoĹ›rednie wywoĹ‚anie funkcji `test_*`: PASS

### NierozwiÄ…zane ryzyka
- Weryfikacja frontowych przypadkĂłw UX (etykieta ETA i gotowoĹ›Ä‡ do dostawy) nadal do manualnego sprawdzenia z realnym ekranem.

### Etap 4: front

1. Front w checkout:
   - pokazac ETA zgodna z `eta_minutes` z odpowiedzi przy potwierdzeniu zamowienia.
2. Panel pracownika/admin:
   - pole zmiany override (0/10/20/30/40), z informacja o cap 60.

### Etap 5: testy i rollout

1. Testy backend:
   - granice bucketow: 0,1,3,4,8,9,13,14
   - overlay: 0,10,20,30,40
   - gwarancja max 60
   - stare zamowienie nie zmienia ETA po zmianie overlayu
   - uprawnienia admin tylko dla endpointu overlay.
2. Smoke:
   - create order, check ETA
   - zmiana statusow przez pracownika + kierowce, check remaining ETA
   - zmiana overlay -> nastepne zamowienie z nowÄ… wartoscia.

## Ewidencja wdrozenia frontendu (aktualny stan wdrozenia)

### 1) Co wdrożono w UI i warstwie danych

- [admin_dashboard.dart: AdminCatalogData](/c:/FFApi/zapieapp/lib/data/models/admin_dashboard.dart:139)
  - pole `kitchenEtaOverrideMinutes`,
  - mapowanie `kitchen_eta_override_minutes` (`.../admin_dashboard.dart:162`).
- [admin_dashboard_repository.dart: updateKitchenEtaOverride](/c:/FFApi/zapieapp/lib/data/repositories/admin_dashboard_repository.dart:78)
  - metoda repozytorium do `PATCH /admin/catalog/kitchen-eta`,
  - payload: `minutes`, `session_token`, `user_email`,
  - zwrot: `AdminCatalogData` (`.../admin_dashboard_repository.dart:518`).
- [admin_dashboard_screen.dart: edycja overlayu](/c:/FFApi/zapieapp/lib/features/admin/admin_dashboard_screen.dart:3751)
  - dialog wyboru: `0, 10, 20, 30, 40`,
  - tile "Ręczna korekta czasu kuchni" (`.../admin_dashboard_screen.dart:4205`).
- [dashboard_screen.dart: prezentacja ETA](/c:/FFApi/zapieapp/lib/features/dashboard/dashboard_screen.dart:8939)
  - `_activeCheckoutEtaDisplay` i karta aktywnego zamówienia używają `checkout.receivedOrder.etaMinutes` oraz `remainingEtaMinutes`.

### 2) Co mamy jako dowód testowy frontu

- Utworzony folder testów: `zapieapp/test/qa/`.
- [README](/c:/FFApi/zapieapp/test/qa/README.md): zakres testów i komenda uruchomienia.
- [qa_frontend_flow_contract_test.dart](/c:/FFApi/zapieapp/test/qa/qa_frontend_flow_contract_test.dart):
  - test lifecycle: `POST /checkout/verification`, `PATCH /admin/orders/{id}/processing-status`, `POST /checkout/confirm-receipt`,
  - test mapowania `PATCH /admin/catalog/kitchen-eta` -> `kitchen_eta_override_minutes`,
  - test helperów ról `AuthSession`.

### 3) Ostatnia weryfikacja techniczna

- Komenda: `cd zapieapp && flutter test test/qa`
- Wynik: `3 tests` / `All tests passed!`.

### 4) Status względem etapów dokumentu

- Etap 4 (Frontend: overlay + przepływ ETA do UI) jest zaimplementowany na poziomie UI, repozytoriów i kontraktów testowych.
- Do domknięcia: finalna walidacja UX i ręczne smoky na urządzeniu po każdym wdrożeniu backendu.
