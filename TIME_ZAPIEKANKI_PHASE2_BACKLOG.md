# TIME ZAPIEKANKI - Phase 2 Backlog wykonawczy

## Cel tego pliku

Ten plik nie opisuje samej logiki ETA.

On ma odpowiedziec na pytanie:
- co w ramach Phase 2 jest juz zrobione,
- co jest jeszcze do dopiecia,
- w jakiej kolejnosci to domykac,
- po czym poznac, ze etap jest zakonczony.

To jest roboczy backlog wykonawczy pod dluzszy goal.

---

## 1. Kontekst biznesowy

Phase 1 ustalila bazowa logike ETA:
- liczymy tylko duze gorace zapiekanki,
- `kids / 25cm / VAC / frozen / udka / dodatki` nie obciazaja tej kolejki,
- przy pustej kolejce `1 duza = 6 min`,
- potem dzialaja buckety:
  - `1-3 -> 7 min`
  - `4-6 -> 10 min`
  - `7-13 -> 15 min`
  - `14+ -> 20 min`
- kuchnia moze dolozyc override `0/10/20/30/40`,
- cap finalnego ETA to `60 min`.

Phase 2 nie kasuje tego kontraktu biznesowego.

Phase 2 doklada warstwe operacyjna:
- model batchowy pieca,
- rozroznienie `w piecu teraz` vs `czeka przed piecem`,
- preview ETA przed finalnym checkoutem,
- diagnostyke dla admina,
- spojnosc miedzy koszykiem, checkoutem, active order i trackingiem.

---

## 2. Aktualny status prac

### 2.1 Backend core
Status: `wdrozone w kodzie`

Juz jest:
- metryka `current_oven_load`,
- metryka `waiting_queue_pieces_before_order`,
- metryka `slots_before_order`,
- metryka `slots_used_by_order`,
- metryka `kitchen_batch_index`,
- metryka `kitchen_batch_count`,
- wyliczenie ETA checkoutu w modelu batchowym,
- przepiecie opoznienia active order na logike batchowa,
- blokada `in_oven`, gdy zamowienie nie miesci sie w aktualnym batchu.

Dowod w kodzie:
- `my_fastapi_project/checkout_service.py`
- `my_fastapi_project/models.py`

### 2.2 Backend API
Status: `wdrozone w kodzie`

Juz jest:
- pola `kitchen_*` w odpowiedzi checkout verification,
- pola `kitchen_*` w active order,
- pola `kitchen_*` w admin dashboard order,
- endpoint `POST /checkout/eta-preview`.

Dowod w kodzie:
- `my_fastapi_project/models.py`
- `my_fastapi_project/router.py`

### 2.3 Frontend klienta
Status: `wdrozone w kodzie, wymaga jeszcze proof runtime`

Juz jest:
- repo `previewCheckoutEta(...)`,
- model `CheckoutEtaPreviewResponse`,
- ekran podsumowania koszyka korzysta z backendowego preview ETA,
- aktywne zamowienie korzysta z backendowego ETA,
- tracking korzysta z backendowego ETA.

Dowod w kodzie:
- `zapieapp/lib/data/repositories/checkout_repository.dart`
- `zapieapp/lib/data/models/checkout_verification.dart`
- `zapieapp/lib/features/dashboard/dashboard_screen.dart`
- `zapieapp/lib/features/orders/order_tracking_screen.dart`

### 2.4 Frontend admin
Status: `wdrozone MVP w kodzie`

Juz jest:
- mapowanie danych `kitchen_*`,
- batch chip na karcie zamowienia,
- sekcja `Diagnostyka pieca` w szczegolach zamowienia,
- komunikat o pojemnosci pieca oparty o logike batchowa.

Dowod w kodzie:
- `zapieapp/lib/data/models/admin_dashboard.dart`
- `zapieapp/lib/features/admin/admin_dashboard_screen.dart`

### 2.5 Testy
Status: `dopiete w kodzie, bez dowodu wykonania`

Juz jest:
- backendowe testy batch metrics,
- backendowe testy preview ETA,
- backendowy test routera `/checkout/eta-preview`,
- frontendowy contract test repo dla `/checkout/eta-preview`,
- runner `run_time_zapiekanki_phase2_suite.py`.

Dowod w kodzie:
- `my_fastapi_project/tests/test_kitchen_eta_logic.py`
- `my_fastapi_project/tests/test_checkout_eta_preview_endpoint.py`
- `my_fastapi_project/tests/run_time_zapiekanki_phase2_suite.py`
- `zapieapp/test/qa/qa_frontend_flow_contract_test.dart`

---

## 3. Kontrakty danych, ktore Phase 2 wprowadza

To jest roboczy model danych, ktory powinien pozostac stabilny w tej fazie.

### 3.1 Pola diagnostyczne `kitchen_*`

| Pole | Znaczenie |
| --- | --- |
| `kitchen_eta_minutes` | automatyczne ETA wynikajace z logiki kuchni |
| `kitchen_batch_index` | od ktorego batchu zaczyna sie zamowienie |
| `kitchen_batch_count` | ile batchy obejmuje dane zamowienie |
| `kitchen_capacity` | logiczna pojemnosc pieca |
| `kitchen_current_oven_load` | ile sztuk jest aktualnie w piecu |
| `kitchen_queue_pieces_before_order` | ile sztuk czeka przed tym zamowieniem |
| `kitchen_slots_before_order` | ile slotow jest zajetych przed tym zamowieniem |
| `kitchen_slots_used_by_order` | ile slotow konsumuje samo zamowienie |

### 3.2 Gdzie te pola maja byc spojne

Te same znaczenia musza byc zachowane w:
- checkout verification,
- active checkout,
- admin dashboard,
- eta preview.

Jesli w runtime te pola beda rozumiane inaczej miedzy warstwami, Phase 2 nie jest domknieta.

---

## 4. Backlog zamykajacy Phase 2

Ponizej jest backlog nie wszystkiego, co byloby mile, tylko tego, co realnie jest potrzebne do uczciwego zamkniecia celu.

### P0. Proof test execution
Status: `otwarte`

Do zrobienia:
- odpalic `python my_fastapi_project/tests/run_time_zapiekanki_phase2_suite.py`
- odpalic `flutter test`
- zapisac wynik wykonania jako dowod, nie tylko zalozenie

Done criteria:
- testy przechodza albo mamy liste konkretnych faili do poprawy

### P0. Runtime smoke dla glownej sciezki klienta
Status: `otwarte`

Do zrobienia:
- przejsc smoke na `Chrome + Azure backend`
- przejsc scenariusze:
  - `1` duza
  - `4` duze
  - `7` duzych
  - `10` duzych
  - `14+`
  - `kids/25cm/VAC`
  - override `+10`
- sprawdzic preview koszyka vs finalny checkout vs active order

Done criteria:
- brak krytycznych rozjazdow ETA miedzy warstwami

### P0. Runtime smoke dla panelu admina
Status: `otwarte`

Do zrobienia:
- sprawdzic, czy admin widzi dane `kitchen_*`
- sprawdzic, czy `can_mark_in_oven` blokuje przypadek przepełnienia batchu
- sprawdzic, czy komunikaty sa zrozumiale dla operatora

Done criteria:
- panel nie pokazuje sprzecznych danych i nie pozwala na oczywisty konflikt pieca

### P1. Audit miejsc z lokalnym ETA fallback
Status: `otwarte`

Cel:
znalezc wszystkie miejsca, gdzie frontend jeszcze moze pokazywac lokalny szacunek zamiast backendowego wyniku.

Do sprawdzenia:
- dolny live-cart poza summary,
- szybkie kafle / skróty,
- ewentualne stale tekstowe typu `do 10 min`,
- fallback po bledzie preview endpointu.

Done criteria:
- mamy liste miejsc:
  - swiadomie zostawionych,
  - poprawionych,
  - poza zakresem Phase 2

### P1. Ujednolicenie copy ETA
Status: `otwarte`

Cel:
ustalic, gdzie chcemy komunikaty:
- `6 min`
- `do 10 min`
- `ok. 15 min`
- `ok. 20 min`

To nie jest duzy backend task, ale to mocno wplywa na odbior systemu przez klienta.

Done criteria:
- copy nie wprowadza w blad przy przejsciu miedzy ekranami

### P1. Audit zgodnosci z `TIME_ZAPIEKANKI_LOGIC.md`
Status: `otwarte`

Cel:
upewnic sie, ze Phase 2 rozszerza dokument biznesowy, a nie stoi z nim w konflikcie.

Do ustalenia:
- czy `TIME_ZAPIEKANKI_LOGIC.md` zostaje jako spec kontraktu biznesowego,
- czy trzeba dopisac do niego aneks o modelu batchowym,
- czy batching jest tylko warstwa techniczna, czy nowym elementem specyfikacji biznesowej.

Done criteria:
- brak sprzecznosci miedzy dokumentem biznesowym a zachowaniem systemu

### P2. Rozszerzenie frontend tests pod rendering diagnostyki
Status: `otwarte`

Juz sa contract tests repo, ale nadal warto dopiac:
- rendering admin diagnostics,
- preview koszyka dla duzego koszyka,
- active order card z backendowym ETA.

To nie jest blocker do samego smoke, ale jest mocnym domknieciem bezpieczenstwa zmiany.

Done criteria:
- najwazniejsze widgety majace ETA lub `kitchen_*` maja regresje

---

## 5. Kolejnosc realizacji - rekomendowana

### Etap 1 - Dowody zamiast dalszego kodu
Najpierw:
1. backend test runner
2. `flutter test`
3. smoke `Chrome + Azure`

Powod:
na tym etapie najwieksze ryzyko nie polega juz na braku kodu, tylko na tym, ze cos jest wdrozone tylko pozornie.

### Etap 2 - Poprawki wynikajace ze smoke
Jesli smoke wykaze rozjazdy:
1. poprawki backendowe
2. poprawki repo / modelu
3. poprawki UI i copy
4. ponowny smoke

### Etap 3 - Finalny audit i decyzja o Phase 3
Po green smoke:
1. completion audit
2. lista swiadomie odlozonych tematow
3. backlog Phase 3

---

## 6. Najbardziej prawdopodobne miejsca odchylen

To sa miejsca, gdzie runtime najlatwiej moze jeszcze pokazac problem:

### 6.1 Preview vs live cart
Summary checkout juz korzysta z backend preview.

Ryzyko:
inne miejsca w UI nadal opieraja sie na lokalnym przyblizeniu.

### 6.2 Override kuchni
Ryzyko:
preview, finalny checkout i admin moga roznie interpretowac override, jesli ktoras warstwa bierze stare pole lub lokalny fallback.

### 6.3 Mieszane koszyki
Ryzyko:
frytki, dodatki i inne pozycje nie powinny psuc logiki zapiekanek, ale UI moze miec uproszczenie renderujace ETA po calym koszyku w sposob mylacy.

### 6.4 Status `in_oven`
Ryzyko:
backend blokuje logicznie konflikt, ale frontend admina moze nadal niekompletnie tlumaczyc operatorowi, dlaczego przycisk nie powinien byc uzyty.

---

## 7. Definition of done dla zamkniecia Phase 2

Phase 2 mozna uznac za zamknieta dopiero, gdy sa jednoczesnie spelnione warunki:

1. backendowy model batchowy dziala w kodzie,
2. frontend klienta korzysta z backendowego preview ETA tam, gdzie to krytyczne,
3. admin widzi i rozumie dane diagnostyczne,
4. `flutter test` i backendowy runner nie wykazuja regresji,
5. smoke runtime na `Chrome + Azure backend` potwierdza sensowne zachowanie,
6. wszystkie otwarte rozjazdy sa:
   - poprawione, albo
   - opisane jako swiadomie poza zakresem tej fazy.

---

## 8. Co robic dalej, jesli ten goal ma jeszcze trwac kilka godzin

Najrozsadniejsza sekwencja:

1. odpalic backend runner,
2. odpalic `flutter test`,
3. przejsc runtime smoke,
4. poprawic realne odchylenia,
5. uzupelnic finalny audit,
6. dopiero wtedy decydowac, czy wchodzimy w Phase 3.

Jesli po smoke wszystko jest zielone, nastepny sensowny temat nie bedzie juz Phase 2, tylko:
- kalibracja bucketow,
- lepsza obserwowalnosc kuchni,
- bardziej granularna logika produkcyjna,
- albo tryb hybrydowy manual + auto.
