# Scenariusze testowe: User › Obs³uga › Kierowca

## Test 1: Order lifecycle – klient sk³ada zamówienie dostawy i czeka na podjêcie przez obs³ugê

**Cel:** weryfikacja przejœcia: brak zamówienia › utworzenie zamówienia › aktywny checkout klienta.

### Kroki:
1. `POST /register` lub `POST /login` jako klient.
2. Wybierz jedn¹ pozycjê z `GET /positions`.
3. Wyœlij `POST /checkout/verification` z:
   - `fulfillment_method`: `dostawa`
   - `fulfillment_option_index`: `0`
   - `address_option_index`: `0`
   - `session_token`: token klienta
   - `total_amount`: >0
4. PotwierdŸ w `GET /checkout/active` ten sam `verification_id`.

### Kryteria sukcesu:
- odpowiedŸ verification: status 200, zawiera `verification_id`, `processing_status=unassigned`, `status=active`.
- `/checkout/active` zawiera to samo `verification_id`.

---

## Test 2: Order lifecycle – pracownik przejmuje i przygotowuje zamówienie

**Cel:** obs³uga przejmuje zamówienie i aktualizuje status.

### Kroki:
1. Zaloguj siê jako `employee` / `admin`.
2. ZnajdŸ `checkout_order_id` w dashboardzie (admin).
3. PATCH `/admin/orders/{id}/processing-status`:
   - `processing_status=assigned`
   - `session_token=token operatora`
4. PATCH `/admin/orders/{id}/processing-status`:
   - `processing_status=assigned`
   - `verification_stage=in_oven`
   - `session_token=token operatora`
5. PATCH `/admin/orders/{id}/processing-status`:
   - `processing_status=assigned`
   - `verification_stage=ready_for_delivery`
   - `session_token=token operatora`

### Kryteria sukcesu:
- Po kroku 2: przynajmniej `verification_stage=assigned`.
- Po kroku 3: `processing_status=assigned`, `assigned_to_user` ustawiony.
- Po kroku 5: `verification_stage=ready_for_delivery`, `processing_status` mo¿e byæ `unassigned` (logika „ready for delivery” oddaje zlecenie do kierowcy).

---

## Test 3: Order lifecycle – kierowca realizuje i potwierdzenie odbioru

**Cel:** zakoñczenie œcie¿ki po stronie dostawcy.

### Kroki:
1. Zaloguj siê jako `driver`.
2. PATCH `/admin/orders/{id}/processing-status`:
   - `processing_status=assigned`
   - `session_token=token driver`
3. PATCH `/admin/orders/{id}/processing-status`:
   - `processing_status=assigned`
   - `verification_stage=on_the_way`
   - `session_token=token driver`
4. PATCH `/admin/orders/{id}/processing-status`:
   - `processing_status=completed`
   - `session_token=token driver`
5. `GET /checkout/active?session_token=<klient>` – powinien pokazaæ etap oczekuj¹cy na potwierdzenie.
6. `POST /checkout/confirm-receipt` jako klient:
   - `{ "received": true, "session_token": "..." }`

### Kryteria sukcesu:
- kierowca mo¿e wykonaæ kroki 1–4.
- zamówienie koñczy w statusie kompletacji dla klienta.
- `GET /checkout/history` zawiera zamówienie jako zamkniête.

---

### Uwagi:
- Dla dostaw `ready_for_delivery` jest wymaganym etapem do przejêcia przez kierowcê.
- Testy wykonuj¹ zarówno biznesowe poprawnoœci, jak i waliduj¹ b³êdne przejœcia (opcjonalnie).