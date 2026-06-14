# TIME ZAPIEKANKI - Phase 2 Proof Runbook

## Cel

Ten plik sluzy do jednego konkretnego zadania:
- przejsc przez testy i smoke Phase 2,
- zapisac twarde wyniki,
- miec material do finalnego audytu zamkniecia.

To nie jest kolejny plan wdrozenia.

To jest instrukcja wykonawcza: co odpalic, w jakiej kolejnosci, czego oczekiwac i jak zapisac outcome.

---

## 1. Zasada pracy

Phase 2 nie moze byc uznana za zakonczona tylko dlatego, ze:
- kod istnieje,
- testy sa dopisane,
- dokumentacja wyglada spojnie.

Potrzebne sa trzy warstwy dowodu:

1. `kod istnieje`
2. `testy przechodza`
3. `runtime smoke potwierdza zachowanie`

Ten runbook dotyczy warstw `2` i `3`.

---

## 2. Kolejnosc wykonania

Trzymaj sie tej kolejnosci:

1. backend test runner
2. frontend `flutter test`
3. healthcheck backendu Azure
4. smoke ETA preview na API
5. smoke frontend `Chrome + Azure backend`
6. smoke panelu admina
7. wpis wynikow do audytu

Powod:
- najpierw tanie dowody lokalne,
- potem dopiero runtime,
- dopiero po runtime decyzja, czy poprawiamy kod, czy zamykamy temat.

---

## 3. Etap A - backend tests

## Komenda

```powershell
cd C:\FFApi\my_fastapi_project
python tests\run_time_zapiekanki_phase2_suite.py
```

## Co to ma potwierdzic

- batch metrics dzialaja,
- preview ETA dziala,
- endpoint `/checkout/eta-preview` dziala,
- admin kitchen ETA endpoint nie ma regresji,
- wykluczenia `kids / VAC / 25cm / frozen` nie rozwalaja logiki.

## Wynik oczekiwany

- caly runner przechodzi bez faila

## Jesli sa faile

Zapisz:
- nazwe testu
- pierwsza realna przyczyne
- czy fail dotyczy:
  - liczenia batchy
  - preview ETA
  - admin kitchen ETA
  - mapowania payloadu

## Format notatki

```text
Backend tests:
- status: PASS / FAIL
- failing tests:
  - ...
- note:
  - ...
```

---

## 4. Etap B - frontend tests

## Komenda

```powershell
cd C:\FFApi\zapieapp
flutter test
```

## Co to ma potwierdzic

- kontrakt repo `/checkout/eta-preview`,
- kontrakty auth/social flow nie zostaly rozjechane,
- widgety callback/auth nie dostaly regresji,
- QA flow contract tests nadal sa spojne.

## Wynik oczekiwany

- `flutter test` przechodzi w calosci

## Jesli sa faile

Zapisz:
- plik testu
- test case
- czy to:
  - bledne mapowanie modelu
  - bledny payload requestu
  - regresja widgetu
  - brak zgodnosci copy/UI

## Format notatki

```text
Frontend tests:
- status: PASS / FAIL
- failing tests:
  - ...
- note:
  - ...
```

---

## 5. Etap C - healthcheck Azure backend

## Komendy

```powershell
curl https://zapieapp-api-dev-alpha.ambitiousstone-9e7294a6.polandcentral.azurecontainerapps.io/health
curl https://zapieapp-api-dev-alpha.ambitiousstone-9e7294a6.polandcentral.azurecontainerapps.io/health/db
```

## Co to ma potwierdzic

- backend dziala
- baza odpowiada
- nie testujemy ETA na martwym lub czesciowo martwym srodowisku

## Wynik oczekiwany

- `health -> ok`
- `health/db -> ok`

## Format notatki

```text
Azure health:
- /health: PASS / FAIL
- /health/db: PASS / FAIL
- note:
  - ...
```

---

## 6. Etap D - API smoke dla preview ETA

Ten etap ma potwierdzic, ze runtime backend zwraca sensowne ETA jeszcze przed klikiem finalnego checkoutu.

## Minimalne scenariusze

### D1. Jedna duza zapiekanka przy pustej kolejce
Oczekiwanie:
- `eta_minutes = 6` albo wynik zgodny z aktualnym override, jesli override nie jest `0`

### D2. Cztery duze zapiekanki
Oczekiwanie:
- bez dodatkowego override: `10 min`

### D3. Siedem duzych zapiekanek
Oczekiwanie:
- bez dodatkowego override: `15 min`

### D4. Koszyk tylko `VAC` lub tylko `25cm`
Oczekiwanie:
- koszyk nie powinien wejsc w logike duzych zapiekanek kuchni

### D5. Override `+10`
Oczekiwanie:
- wynik jest o `10 min` wyzszy od automatu
- nadal z capem `60`

## Co zapisac przy kazdym scenariuszu

```text
Scenario:
- name:
- input:
- expected:
- actual:
- pass: YES / NO
- note:
```

## Na co patrzec w odpowiedzi

- `eta_minutes`
- `kitchen_eta_minutes`
- `kitchen_batch_index`
- `kitchen_batch_count`
- `kitchen_current_oven_load`
- `kitchen_queue_pieces_before_order`
- `kitchen_slots_before_order`
- `kitchen_slots_used_by_order`

Jesli finalne `eta_minutes` i `kitchen_eta_minutes` roznia sie, trzeba ustalic dlaczego:
- override,
- delivery buffer,
- scheduled pickup,
- inna warstwa biznesowa.

---

## 7. Etap E - frontend smoke `Chrome + Azure backend`

## Uruchomienie

```powershell
cd C:\FFApi\zapieapp
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 3001 --dart-define API_BASE_URL=https://zapieapp-api-dev-alpha.ambitiousstone-9e7294a6.polandcentral.azurecontainerapps.io
```

## Co trzeba sprawdzic

### E1. Preview koszyka
Sprawdz:
- czy po dodaniu duzych zapiekanek czas zmienia sie zgodnie z bucketem
- czy dla `7` sztuk nie zostaje stare `10 min`
- czy mieszany koszyk nie psuje ETA

### E2. Finalny checkout
Sprawdz:
- czy czas przy przejsciu z koszyka do finalizacji nie skacze bez powodu
- czy utworzone zamowienie zachowuje ten sam porzadek logiczny ETA

### E3. Active order
Sprawdz:
- czy aktywne zamowienie pokazuje sensowny `remaining ETA`
- czy nie ma absurdalnego skoku typu `preview 10` -> `active 40` bez uzasadnienia kolejka/override

### E4. Tracking
Sprawdz:
- czy tracking pokazuje ten sam model ETA co active order

## Format notatki

```text
Frontend Chrome smoke:
- preview cart: PASS / FAIL
- checkout consistency: PASS / FAIL
- active order consistency: PASS / FAIL
- tracking consistency: PASS / FAIL
- note:
  - ...
```

---

## 8. Etap F - admin smoke

## Co sprawdzic

### F1. Diagnostyka pieca
Admin powinien widziec:
- `w piecu teraz`
- `przed tym zamowieniem`
- `batch`
- `ETA automatyczne`

### F2. Sens danych
Sprawdz:
- czy wartosci nie sa sprzeczne
- czy np. `slots_used_by_order` nie przeczy liczbie sztuk z zamowienia
- czy `batch index` jest zgodny z obciazeniem kolejki

### F3. `can_mark_in_oven`
Sprawdz:
- czy panel nie pozwala wprowadzic zamowienia do pieca, gdy nie ma miejsca
- albo czy przynajmniej komunikat bardzo jasno to tlumaczy

## Format notatki

```text
Admin smoke:
- kitchen diagnostics visible: PASS / FAIL
- diagnostics coherent: PASS / FAIL
- in_oven guard coherent: PASS / FAIL
- note:
  - ...
```

---

## 9. Kiedy wynik uznajemy za akceptowalny

Phase 2 przechodzi proof tylko wtedy, gdy:

1. backend test runner przechodzi
2. `flutter test` przechodzi
3. Azure health jest zielony
4. preview ETA na API daje wyniki zgodne z bucketami i override
5. frontend `Chrome + Azure` nie pokazuje krytycznych rozjazdow
6. admin diagnostics nie sa sprzeczne i wspieraja obsluge

Jesli jeden z tych punktow pada, Phase 2 nie jest zamknieta.

---

## 10. Co jest krytycznym rozjazdem

Za krytyczny rozjazd uznaj:

- `7` duzych zapiekanek nadal pokazuje `10 min`
- preview koszyka i finalny checkout pokazuja rozne czasy bez uzasadnienia
- active order skacze na mocno wyzszy ETA bez logicznego powodu
- `VAC` lub `25cm` wlacza logike duzych zapiekanek
- override nie dziala albo dziala niespojnie
- admin widzi dane sprzeczne z zachowaniem systemu

To sa przypadki do poprawy przed zamknieciem celu.

---

## 11. Co nie musi blokowac zamkniecia

Nie wszystko musi byc blockerem.

Moga pozostac jako swiadomie zaakceptowane odchylenia:
- mniej istotne copy typu `ok.` vs `do`
- drobne roznice w prezentacji, jesli liczba minut jest poprawna
- miejsca poza glowna sciezka checkoutu, ktore nadal pokazuja lokalny szacunek, o ile sa opisane i nie wprowadzaja mocno w blad

Ale to trzeba wpisac do finalnego audytu jako:
- `accepted gap`
- z uzasadnieniem

---

## 12. Szablon wpisu do finalnego audytu

Po przejsciu runbooka dopisz do audytu wynik w takiej strukturze:

```text
Proof summary:

1. Backend tests
- status:
- notes:

2. Frontend tests
- status:
- notes:

3. Azure health
- status:
- notes:

4. API preview smoke
- status:
- notes:

5. Frontend Chrome smoke
- status:
- notes:

6. Admin smoke
- status:
- notes:

Open gaps:
- ...

Decision:
- complete / continue fixing
```

---

## 13. Rekomendacja praktyczna

Jesli ten goal ma byc domkniety bez chaosu, nie mieszaj etapow.

Najpierw:
1. testy
2. health
3. preview API
4. frontend Chrome
5. admin
6. audit

To jest najkrotsza droga do realnego dowodu, czy Phase 2 jest gotowa, czy tylko wyglada na gotowa.
