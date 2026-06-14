# TIME ZAPIEKANKI - Phase 2 Execution Plan

## Cel operacyjny

Doprowadzic logike czasu zapiekanek od obecnego modelu bucketowego do modelu zgodnego z realna praca kuchni:
- system ma rozumiec piec jako zasob o ograniczonej pojemnosci,
- ETA ma wynikac nie tylko z liczby aktywnych duzych zapiekanek, ale tez z tego, czy nowe pozycje mieszcza sie jeszcze w biezacym wsadzie,
- admin ma miec czytelna diagnostyke, dlaczego dane zamowienie dostalo taki czas,
- reczny override kuchni ma nadal dzialac, ale jako kontrolowany narzut na logike automatyczna,
- frontend klienta i panel admina maja pokazywac spojnosc tego modelu.

Ten plik ma sluzyc jako roboczy plan wykonawczy pod dluzszy goal, a nie tylko jako opis koncepcji.

---

## Stan wyjsciowy po Phase 1

Na dzis wdrozone i potwierdzone sa nastepujace elementy:
- ETA dla duzych goracych zapiekanek jest liczone po sztukach, a nie po liczbie zamowien.
- Z kolejki wykluczane sa pozycje `kids`, `25cm`, `VAC`, `frozen`.
- Dziala wyjatek `0 aktywnych + 1 nowa duza zapiekanka = 6 min`.
- Buckety automatyczne sa ustawione jako:
  - `1-3 -> 7 min`
  - `4-6 -> 10 min`
  - `7-13 -> 15 min`
  - `14+ -> 20 min`
- Dziala reczny override kuchni z capem koncowego ETA do `60 min`.
- Istnieja testy backendowe dla tej warstwy i dokumentacja biznesowa `TIME_ZAPIEKANKI_LOGIC.md`.

To jest dobra baza, ale jeszcze nie jest to pelny model kuchni oparty o realny wsad pieca.

---

## Gdzie sa obecnie luki

### 1. Model ETA nadal jest zbyt plaski
Obecna logika patrzy glownie na laczna liczbe duzych zapiekanek w aktywnej kolejce. Nie odroznia wystarczajaco dobrze:
- pozycji juz bedacych w piecu,
- pozycji czekajacych przed piecem,
- pozycji, ktore mieszcza sie jeszcze w biezacym wsadzie,
- pozycji, ktore wymuszaja wejscie na kolejny wsad.

### 2. Admin nie widzi przyczyny czasu
Panel powinien umiec odpowiedziec na pytania typu:
- ile sztuk jest przed tym zamowieniem,
- czy zamowienie miesci sie jeszcze w pierwszym wsadzie,
- w ktory batch wpada,
- ile batchy zajmuje,
- jaki jest realny load pieca.

### 3. Front klienta nie zawsze pokazuje ETA zgodne z logika zamowienia
Szczegolnie przy wiekszych koszykach trzeba dopilnowac, zeby preview, checkout i aktywne zamowienie poslugiwaly sie tym samym modelem ETA.

### 4. Brakuje testow stricte pod batching pieca
Sa testy bucketow, ale Phase 2 wymaga osobnych regresji dla:
- mieszczenia sie w aktualnym wsadzie,
- wejscia na drugi wsad,
- zamowien rozpinajacych sie na wiecej niz jeden batch,
- relacji miedzy aktywnym loadem pieca a pozycja zamowienia w kolejce.

---

## Target biznesowy dla Phase 2

Docelowy model ma dzialac tak:
- duze gorace zapiekanki sa jedynymi pozycjami, ktore obciazaja piec,
- piec ma pojemnosc logiczna `N` sztuk jednoczesnie,
- system odroznia:
  - sztuki juz w piecu,
  - sztuki czekajace,
  - sztuki z nowego zamowienia,
- dla nowego zamowienia system liczy:
  - ile sztuk jest przed nim,
  - czy miesci sie jeszcze w pierwszym batchu,
  - czy zaczyna sie od drugiego batchu,
  - czy samo zamowienie rozpina sie na kilka batchy,
- klient dostaje ETA zgodne z ta pozycja w kolejce,
- admin widzi diagnostyke i moze swiadomie uzyc override,
- frontend nie pokazuje juz rozjazdow miedzy koszykiem, checkoutem i aktywnym zamowieniem.

---

## Zakres Phase 2

### Backend
- wprowadzenie metryk batchowych dla zapiekanek,
- rozdzielenie `in oven` vs `waiting queue`,
- nowy model wyliczania pozycji zamowienia wzgledem batchy,
- wzbogacenie odpowiedzi API o pola diagnostyczne,
- poprawa logiki opoznienia aktywnego zamowienia,
- utrzymanie kompatybilnosci z recznym override.

### Frontend klienta
- wykorzystanie nowych pol diagnostycznych tam, gdzie potrzebne,
- dopilnowanie, zeby duzy koszyk od razu pokazywal poprawny czas,
- ewentualne copy / UI dla bardziej czytelnego komunikatu ETA.

### Frontend admin
- pokazanie danych diagnostycznych pieca i batchy,
- wsparcie operatora przy decyzji, czy wsadzic zamowienie do pieca teraz czy nie,
- lepsza obsluga przypadkow granicznych.

### Testy
- backendowe testy jednostkowe batch model,
- backendowe testy endpointowe odpowiedzi z metrykami,
- frontendowe regresje checkout / active order / admin dashboard,
- manualny smoke duzych koszykow.

---

## Proponowany goal structure

### Goal A - Backend batch model foundation
Cel:
Zmienic model ETA tak, aby opieral sie na realnej pozycji zamowienia wzgledem pojemnosci pieca i kolejek waiting/in-oven.

Done criteria:
- backend rozroznia `current_oven_load` i `waiting_queue_pieces`,
- backend wylicza `batch_index` i `batch_count`,
- nowe zamowienie 1 sztuka przy pustej kuchni dalej daje `6 min`,
- zamowienia mieszczace sie w pierwszym wsadzie nie sa sztucznie opozniane,
- zamowienia wchodzace na kolejny batch dostaja wyzszy ETA zgodny z logika.

### Goal B - API diagnostics and admin visibility
Cel:
Wystawic do API komplet danych potrzebnych do diagnozy i obslugi kuchni.

Done criteria:
- odpowiedzi checkout / active order / admin dashboard zwracaja pola diagnostyczne,
- admin widzi, ile sztuk jest przed danym zamowieniem,
- admin widzi czy zamowienie miesci sie w biezacym batchu,
- logika `can_mark_in_oven` nie dopuszcza ewidentnych konfliktow.

### Goal C - Frontend consistency
Cel:
Doprowadzic frontend klienta i admina do spojnosc z nowym modelem backendu.

Done criteria:
- preview koszyka pokazuje ETA zgodne z backendem,
- checkout confirmation pokazuje ten sam ETA,
- aktywne zamowienie nie ma nielogicznych skokow czasu,
- admin dashboard nie wprowadza operatora w blad.

### Goal D - Regression coverage and rollout safety
Cel:
Zamknac testy i rollout tak, zeby zmiana nie rozwalila glownej sciezki zamowien.

Done criteria:
- backendowe testy zielone,
- smoke duzych zamowien przechodzi,
- nie ma regresji dla `kids`, `25cm`, `VAC`, `frozen`,
- reczny override nadal dziala.

---

## Szczegolowy backlog wykonawczy

## Workstream 0 - Freeze spec i slownik pojec

### Zadania
- potwierdzic, ze `TIME_ZAPIEKANKI_LOGIC.md` jest jedynym zrodlem prawdy biznesowej dla ETA,
- ustalic roboczy slownik:
  - `oven load` = sztuki aktualnie w piecu,
  - `waiting queue` = sztuki czekajace na wejscie do pieca,
  - `slots before order` = wszystkie sloty przed nowym zamowieniem,
  - `slots used by order` = ile slotow zajmuje dane zamowienie,
  - `batch index` = od ktorego wsadu zaczyna sie zamowienie,
  - `batch count` = ile wsadow obejmuje samo zamowienie.

### Efekt
- brak dalszych sporow definicyjnych podczas implementacji.

---

## Workstream 1 - Backend batch metrics foundation

### Zadania
- dodac helpery liczace:
  - liste aktywnych zamowien zapiekankowych oczekujacych przed piecem,
  - liczbe sztuk oczekujacych przed piecem,
  - liczbe sztuk oczekujacych przed konkretnym zamowieniem,
  - puste metryki batchowe,
  - kompletne metryki batchowe dla nowego zamowienia,
  - kompletne metryki batchowe dla istniejacego zamowienia,
- rozdzielic w logice backendu:
  - `current_oven_load`,
  - `waiting_queue_pieces`,
  - `slots_before_order`,
  - `slots_used_by_order`.

### Pola diagnostyczne do dodania po backendzie
- `kitchen_eta_minutes`
- `kitchen_batch_index`
- `kitchen_batch_count`
- `kitchen_capacity`
- `kitchen_current_oven_load`
- `kitchen_queue_pieces_before_order`
- `kitchen_slots_before_order`
- `kitchen_slots_used_by_order`

### Efekt
- backend ma nowy model obliczeniowy, ale jeszcze bez wymuszania zmian UI.

---

## Workstream 2 - Checkout ETA calculation rewrite

### Zadania
- przepiac liczenie ETA dla nowych zapiekanek z modelu `total active queue only` na model batchowy,
- zachowac przypadek specjalny `0 + 1 -> 6 min`,
- utrzymac obecne buckety jako warstwe mapowania obciazenia na minuty,
- nakladac reczny override dopiero na wynik automatyczny,
- nie zmieniac logiki pozycji nieobciazajacych pieca.

### Acceptance checks
- 1 duza zapiekanka przy pustej kuchni = `6 min`,
- 3 duze sztuki lacznie = `7 min`,
- 4-6 duzych sztuk lacznie = `10 min`,
- 7-13 duzych sztuk lacznie = `15 min`,
- 14+ = `20 min`,
- jesli nowe zamowienie wpada juz na kolejny batch, ma dostac odpowiednio wyzsza pozycje.

---

## Workstream 3 - Active order ETA / queue delay rewrite

### Problem
Obecny model opoznienia aktywnego zamowienia patrzy zbyt uproszczenie na overflow wzgledem aktualnego loadu pieca. To nie oddaje prawdziwej pozycji zamowienia, jezeli przed nim sa juz inne czekajace zamowienia.

### Zadania
- przepiac `_oven_queue_delay_minutes()` na logike batchowa,
- opoznienie ma wynikac z tego, w ktorym batchu konczy sie zamowienie,
- pierwsza pelna partia nie dostaje dodatkowego delay,
- kolejny batch doklada kolejny krok opoznienia,
- zamowienie rozciagniete na 2 batchy tez ma to odzwierciedlac.

### Efekt
- aktywne zamowienia przestaja pokazywac nielogiczne opoznienia.

---

## Workstream 4 - Admin API i panel operacyjny

### Zadania backend
- dorzucic nowe pola do modelu odpowiedzi admin dashboardu,
- poprawic `can_mark_in_oven`, zeby nie pozwalac zaznaczyc `in oven`, gdy zamowienie realnie nie miesci sie w aktualnym batchu.

### Zadania frontend
- pokazac dane diagnostyczne w karcie zamowienia admina,
- minimum MVP:
  - `w piecu teraz: X / capacity`,
  - `przed tym zamowieniem: Y szt.`,
  - `batch: A z B`,
  - `ETA automatyczne: Z min`,
- jezeli UI bedzie za ciezki, pokazac te dane najpierw w expanded details, nie na glownej karcie.

### Efekt
- operator kuchni widzi przyczyne i moze lepiej zarzadzac ruchem.

---

## Workstream 5 - Frontend klienta

### Zadania
- sprawdzic, z ktorych odpowiedzi frontend bierze ETA:
  - koszyk / preview,
  - verification / checkout,
  - aktywne zamowienie,
- dopilnowac, zeby dla zapiekanek frontend bral spojnosc z backendowego wyniku, nie z lokalnych uproszczen,
- ewentualnie dodac male copy rozrozniajace:
  - `do 10 min`,
  - `ok. 15 min`,
  - `ok. 20 min`,
  ale bez zmiany modelu biznesowego.

### Efekt
- klient nie widzi rozjazdu typu: koszyk 10 min, zamowienie po chwili 40 min bez zrozumialego powodu.

---

## Workstream 6 - Regression tests

### Backend tests
Do dopisania lub rozszerzenia:
- batch metrics dla pierwszej pojedynczej zapiekanki,
- batch metrics dla zamowienia mieszczacego sie jeszcze w pierwszym wsadzie,
- batch metrics dla zamowienia wchodzacego na drugi batch,
- batch metrics dla zamowienia zajmujacego dwa batche,
- ETA dla `kids` only bez wejscia w logike pieca,
- ETA dla `VAC` only bez wejscia w logike pieca,
- aktywne opoznienie dla zamowienia w batchu 1,
- aktywne opoznienie dla zamowienia w batchu 2,
- aktywne opoznienie dla zamowienia spanning 2 batches.

### Frontend tests
- preview koszyka dla duzego koszyka 7 sztuk,
- checkout verification pokazujacy nowe ETA,
- active order card z poprawnym remaining ETA,
- admin dashboard rendering danych diagnostycznych.

### Manual smoke
- 1 klient, 1 duza zapiekanka,
- 1 klient, 4 duze zapiekanki,
- 1 klient, 7 duzych zapiekanek,
- 2 klientow: 4 + 6,
- mieszany koszyk: zapiekanki + frytki,
- koszyk tylko `25cm` albo tylko `VAC`.

---

## Workstream 7 - Rollout i obserwowalnosc

### Zadania
- po deployu na Azure wykonac kontrolowany smoke na web Chrome,
- potem smoke na Androidzie,
- logowac przypadki, gdzie admin override jest czesto uzywany,
- zebrane obserwacje wykorzystac do decyzji, czy Phase 3 ma isc w:
  - pelna automatyzacje,
  - tryb hybrydowy,
  - tryb bardziej manualny.

### Minimalne KPI po rollout
- brak absurdalnych skokow ETA dla duzych koszykow,
- admin rozumie, czemu system daje taki czas,
- klient rzadziej widzi rozjazd miedzy obietnica a praktyka,
- override kuchni jest wyjatkiem, a nie norma.

---

## Kolejnosc wdrazania - rekomendowana

### Krok 1
Backend foundation:
- helpery batch metrics,
- nowe pola modeli,
- przepiecie checkout ETA,
- przepiecie active order delay,
- backend tests.

### Krok 2
Admin diagnostics MVP:
- API fields,
- minimalny rendering danych w panelu,
- poprawa `can_mark_in_oven`.

### Krok 3
Frontend client consistency:
- preview koszyka,
- checkout,
- aktywne zamowienie,
- regresje UI.

### Krok 4
Manual smoke on Azure:
- Chrome,
- Android,
- duze koszyki,
- zamkniecie otwartych zamowien po testach.

### Krok 5
Decision point:
- czy zostajemy przy obecnych bucketach jako mapowaniu,
- czy w Phase 3 wchodzimy w bardziej granularny model pieca / produkcji.

---

## Konkretne pliki do ruszenia w pierwszym slicie

### Backend
- `my_fastapi_project/checkout_service.py`
- `my_fastapi_project/models.py`
- `my_fastapi_project/tests/test_kitchen_eta_logic.py`

### Potem admin/frontend
- `zapieapp/lib/features/admin/admin_dashboard_screen.dart`
- `zapieapp/lib/data/repositories/checkout_repository.dart`
- ewentualnie widoki klienta, ktore renderuja ETA koszyka i aktywnego zamowienia

---

## Ryzyka

### Ryzyko 1 - Za duza zlozonosc na raz
Jesli od razu dopniemy backend, admin UI, klienta i rollout, trudno bedzie wskazac zrodlo regresji.

Mitigacja:
- robic to slicami backend-first.

### Ryzyko 2 - Operatorzy nie beda ufali automatyce
Nawet dobra logika moze nie byc intuicyjna przy peak hours.

Mitigacja:
- pokazac diagnostyke, nie tylko finalny numer minut.

### Ryzyko 3 - Buckety nie beda odpowiadaly realnej wydajnosci kuchni
To nie jest problem implementacji, tylko kalibracji biznesowej.

Mitigacja:
- po rollout zbierac obserwacje i ewentualnie poprawic wartosci bucketow, nie sam model batchowy.

---

## Definition of done dla calej Phase 2

Phase 2 uznajemy za zakonczona, gdy jednoczesnie sa spelnione wszystkie warunki:
- backend liczy ETA zapiekanek w modelu batchowym,
- admin dostaje dane diagnostyczne i moze nimi operowac,
- frontend klienta pokazuje spojny ETA w koszyku, checkout i aktywnym zamowieniu,
- testy backendowe i kluczowe frontendowe sa zielone,
- manualny smoke na Azure potwierdza sensowne zachowanie dla duzych koszykow,
- dokumentacja i changelog sa uzupelnione.

---

## Rekomendacja startowa do dlugiego goala

Najrozsadniejszy start to nie UI, tylko backendowy slice techniczny:
1. batch metrics helpers,
2. nowe pola modeli API,
3. rewrite checkout ETA,
4. rewrite active order queue delay,
5. backend regression tests.

To da fundament, na ktorym dopiero warto spokojnie budowac admin UI i frontend klienta.
