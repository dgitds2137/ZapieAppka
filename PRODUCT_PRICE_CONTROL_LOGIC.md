# ZapieApp - Dynamic Product Price Control

## Change Summary

Implement a simple admin-only price control mechanism for existing catalog items.

The goal is operational flexibility without introducing a new product-management domain. We keep the current product repository and add one narrow capability: change the price of an existing menu position or add-on directly from the admin catalog.

---

## Business Rules

### Scope of Change

Admin can update prices for:

- existing `MenuPositions`
- existing `MenuAddons`

This feature does **not** create new products, remove products, or introduce historical price versioning.

---

### Permissions

Only role `admin` may change prices.

Employees, drivers and regular users:

- must not be allowed to update catalog prices through API
- should not get an editable price control in admin UI

---

### Price Validation

Accepted rules:

- price may be updated independently from availability
- price is normalized to 2 decimal places
- allowed range: `0.00` to `999.00`

Rejected cases:

- missing both `is_active` and `price` in update payload
- negative price
- absurdly high values above allowed catalog cap

---

## Admin Panel Requirements

Price control should live in the same catalog card area as availability management, so operator context stays local to the product being edited.

For each product/add-on card:

- current availability remains visible
- current price remains visible
- admin gets a direct `Cena` edit action
- control sits next to or directly under the availability control block

This keeps the interaction fast:

```text
produkt -> widac status -> widac cene -> klik edytuj -> wpisz nowa cene -> zapisz
```

---

## Backend Requirements

Two existing admin catalog endpoints cover the scope:

- `PATCH /admin/catalog/positions/{position_id}`
- `PATCH /admin/catalog/addons/{addon_id}`

Payload model:

```text
AdminCatalogItemUpdateIn
```

Fields:

- `session_token`
- `user_email`
- optional `is_active`
- optional `price`

Expected behavior:

- authenticate operator
- require `admin`
- update only fields passed in payload
- return updated object

---

## Frontend Requirements

Frontend should not invent separate catalog write paths.

It should use the existing admin repository methods:

- `updatePositionActive(...)`
- `updateAddonActive(...)`

Those methods already support partial updates with:

- `isActive`
- `price`

So the frontend patch stays intentionally small:

- open price dialog
- parse decimal amount
- send PATCH
- replace updated item in local catalog state

---

## Rzeczywista implementacja - co mamy teraz i co bylo potrzebne

Stan wyjsciowy repo byl juz blisko celu:

- backend admin catalog mial osobne endpointy dla pozycji i dodatkow
- payload aktualizacji wspieral `is_active`
- frontend mial katalog admina i lokalny update itemow

Czego brakowalo z punktu widzenia funkcjonalnosci:

- jawnego opisu biznesowego dla kontroli cen
- testu backendowego potwierdzajacego admin-only + walidacje ceny
- testu frontendowego potwierdzajacego, ze repo wysyla `price`
- lekkiego dopiecia UX, zeby cena byla wyraznie obok kontroli dostepnosci

---

## Proponowany plan wdrozenia (minimalny, ale kompletny)

### Etap 1: backend API i walidacja

1. Rozszerzyc `AdminCatalogItemUpdateIn` o `price`.
2. W `CheckoutService` dopiac:
   - update ceny pozycji
   - update ceny dodatku
   - normalizacje do 2 miejsc
   - walidacje zakresu
3. Zostawic istniejace endpointy PATCH zamiast tworzyc nowe.
4. Wymusic `_require_admin_role(...)` dla obu przypadkow.

Status: **zrobione**.

### Etap 2: frontend admin catalog

1. W repo Flutter zostawic jeden write path dla itemu:
   - `updatePositionActive(...)`
   - `updateAddonActive(...)`
2. Dodac dialog edycji kwoty.
3. Po sukcesie podmienic tylko zmieniony rekord w lokalnym state.
4. Umiescic akcje ceny przy sekcji dostepnosci w karcie katalogowej.

Status: **zrobione**.

### Etap 3: QA i kontrakt

1. Backend:
   - admin moze zmienic cene pozycji
   - admin moze zmienic cene dodatku
   - employee dostaje `403`
   - cena ujemna daje `400`
2. Frontend:
   - repo wysyla `price` do poprawnych endpointow
   - odpowiedz mapuje sie do modelu katalogu bez regresji

Status: **zrobione**.

---

## Status wdrozenia (2026-06-07)

### Backend

- `my_fastapi_project/models.py`
  - `AdminCatalogItemUpdateIn` wspiera `price`
- `my_fastapi_project/router.py`
  - PATCH dla pozycji i dodatkow wykorzystuje wspolny payload update
- `my_fastapi_project/checkout_service.py`
  - update ceny pozycji i dodatku
  - walidacja `400` przy braku zmian
  - walidacja zakresu ceny
  - enforcement roli `admin`

### Frontend

- `zapieapp/lib/data/repositories/admin_dashboard_repository.dart`
  - repo wspiera partial update z `price`
- `zapieapp/lib/features/admin/admin_dashboard_screen.dart`
  - akcja `Cena` jest przy kontroli dostepnosci
  - dialog zapisuje nowa wartosc i odswieza lokalny katalog

### Testy

- backend:
  - `my_fastapi_project/qa/tests/test_21_admin_catalog_price_update.py`
- frontend:
  - `zapieapp/test/qa/qa_frontend_flow_contract_test.dart`

---

## Co warto zrobic pozniej, ale nie teraz

Ta wersja jest dobra operacyjnie, ale swiadomie nie robi jeszcze kilku rzeczy:

- historii zmian cen
- informacji kto zmienil cene i kiedy
- schedulowanych cen promocyjnych
- masowej edycji wielu rekordow naraz
- rozdzielenia uprawnien typu `catalog_manager`

To sa osobne decyzje produktowe. Na teraz celem jest prosty, szybki i bezpieczny override ceny dla admina.

---

## Weryfikacja po deployu

Po wdrozeniu warto sprawdzic:

- `GET /admin/catalog` zwraca poprawne ceny
- admin moze zmienic cene pozycji
- admin moze zmienic cene dodatku
- employee nie moze wykonac PATCH na cenie
- UI pokazuje kontrole ceny przy dostepnosci
- zmieniona cena jest widoczna po ponownym pobraniu katalogu i na froncie klienta
