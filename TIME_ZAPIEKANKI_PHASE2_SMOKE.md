# TIME ZAPIEKANKI - Phase 2 Smoke Plan

## Cel

Potwierdzic w runtime, ze Phase 2 dziala zgodnie z nowa logika batchowa pieca:
- koszyk pokazuje ETA z backendowego preview,
- checkout finalny nie rozjezdza sie z preview,
- aktywne zamowienie i tracking trzymaja ETA z backendu,
- admin widzi diagnostyke pieca i batchu,
- duze koszyki wpadaja w poprawne progi czasu.

---

## Zakres sprawdzenia

### Backend
- `POST /checkout/eta-preview`
- `POST /checkout/verification`
- `GET /checkout/active`
- `GET /admin/dashboard`

### Frontend klienta
- ekran koszyka / podsumowania
- ekran po checkoutcie
- pasek aktywnego zamowienia
- tracking zamowienia

### Frontend admin
- karta zamowienia
- dialog szczegolow zamowienia
- komunikat o braku miejsca w piecu

---

## Wymagane warunki wstepne

- backend Azure ma wdrozone aktualne zmiany Phase 2,
- frontend lokalny odpala sie przeciwko temu backendowi,
- w bazie nie wisza stare aktywne zamowienia, ktore zaburza testy,
- test duzych zapiekanek wykonujemy bez udek, bez VAC i bez `25cm`,
- reczny override kuchni ustawiony na `0`, jesli chcemy najpierw sprawdzic czysta automatyke.

---

## Scenariusz 0 - przygotowanie stanu

### Cel
Wyzerowac zaklocenia przed testem bucketow.

### Kroki
1. Zalogowac sie do panelu admina.
2. Sprawdzic, czy nie ma aktywnych zamowien w piecu ani w kolejce.
3. Ustawic `kitchen_eta_override_minutes = 0`.
4. Jesli sa aktywne zamowienia testowe, zakonczyc je albo anulowac.

### Oczekiwany wynik
- piec zapiekanek ma realnie pusty stan,
- kolejka przed pierwszym testem jest pusta,
- override nie podbija czasu.

---

## Scenariusz 1 - 1 duza zapiekanka przy pustej kuchni

### Kroki
1. Otworzyc frontend klienta.
2. Dodac 1 duza goraca zapiekanke 50 cm.
3. Otworzyc ekran podsumowania koszyka.
4. Zanotowac ETA z preview.
5. Zlozyc checkout.
6. Sprawdzic ETA po checkoutcie i w active order.
7. Otworzyc panel admina i szczegoly zamowienia.

### Oczekiwany wynik
- koszyk preview: `6 min`
- checkout: `6 min`
- active order / tracking: `6 min` lub male odliczanie od tej wartosci
- admin diagnostics:
  - `queue before order = 0`
  - `slots used by order = 1`
  - `batch = 1`
  - `kitchen_eta_minutes = 6`

---

## Scenariusz 2 - 4 duze zapiekanki przy pustej kuchni

### Kroki
1. Wyczyscic poprzedni test.
2. Dodac 4 duze gorace zapiekanki.
3. Otworzyc ekran podsumowania koszyka.
4. Zlozyc checkout.
5. Sprawdzic admin diagnostics.

### Oczekiwany wynik
- preview koszyka: `10 min`
- checkout: `10 min`
- active order: start od `10 min`
- admin diagnostics:
  - `slots used by order = 4`
  - `batch = 1`
  - `batch count = 1`
  - `kitchen_eta_minutes = 10`

---

## Scenariusz 3 - 7 duzych zapiekanek przy pustej kuchni

### Kroki
1. Wyczyscic poprzedni test.
2. Dodac 7 duzych goracych zapiekanek.
3. Otworzyc ekran podsumowania koszyka.
4. Zlozyc checkout.
5. Sprawdzic admin diagnostics.

### Oczekiwany wynik
- preview koszyka: `15 min`
- checkout: `15 min`
- active order: start od `15 min`
- admin diagnostics:
  - `slots used by order = 6` albo logiczny limit batchowego zajecia w pierwszym wsadzie zaleznosci od implementacji slot count,
  - `batch index = 1`
  - `batch count >= 1`
  - jesli model uznaje spill do kolejnego batchu, admin powinien to pokazac w `batch label`
- najwazniejsze: nie moze zostac `10 min`.

---

## Scenariusz 4 - 10 duzych zapiekanek przy pustej kuchni

### Kroki
1. Wyczyscic poprzedni test.
2. Dodac 10 duzych goracych zapiekanek.
3. Otworzyc ekran podsumowania koszyka.
4. Zlozyc checkout.
5. Sprawdzic admin diagnostics i komunikat o batchu.

### Oczekiwany wynik
- preview koszyka: `15 min`
- checkout: `15 min`
- active order: `15 min`
- admin diagnostics musi jasno pokazywac, ze zamowienie nie miesci sie w jednej malej partii i/lub przechodzi przez kolejne batche

Uwagi:
- to nadal nie powinno wskakiwac na `20 min`, bo prog `20` zaczyna sie od `14+` duzych sztuk lacznie.

---

## Scenariusz 5 - 14 duzych zapiekanek przy pustej kuchni

### Kroki
1. Wyczyscic poprzedni test.
2. Dodac 14 duzych goracych zapiekanek.
3. Otworzyc ekran podsumowania koszyka.
4. Zlozyc checkout.

### Oczekiwany wynik
- preview koszyka: `20 min`
- checkout: `20 min`
- active order: `20 min`
- admin diagnostics pokazuje co najmniej drugi batch / wielowsadowosc oraz wyzszy prog obciazenia

---

## Scenariusz 6 - dwa kolejne zamowienia, kumulacja kolejki

### Cel
Sprawdzic, czy drugi klient dziedziczy obciazenie po pierwszym.

### Kroki
1. Klient A sklada 4 duze zapiekanki.
2. Bez konczenia tamtego zamowienia klient B sklada 6 duzych zapiekanek.
3. Porownac ETA w obu checkoutach.
4. Sprawdzic admin diagnostics dla drugiego zamowienia.

### Oczekiwany wynik
- klient A: `10 min`
- klient B: nie mniej niz `15 min`
- admin dla klienta B pokazuje dodatnie `queue before order`
- jesli zamowienie B nie miesci sie w pierwszym batchu, `canMarkInOven` powinno byc odpowiednio zablokowane

---

## Scenariusz 7 - koszyk mieszany bez dodatkowego obciazenia pieca

### Kroki
1. Wyczyscic poprzedni test.
2. Dodac 1-2 duze zapiekanki oraz frytki / dodatki.
3. Otworzyc preview ETA.

### Oczekiwany wynik
- ETA powinno byc liczone od zapiekanek, nie od frytek,
- dodatki nie powinny sztucznie przenosic zamowienia na wyzszy batch,
- admin diagnostics powinno nadal pokazywac sloty tylko dla zapiekanek.

---

## Scenariusz 8 - koszyk tylko `25cm` / `kids` / `VAC`

### Kroki
1. Wyczyscic poprzedni test.
2. Dodac koszyk bez duzych goracych zapiekanek.
3. Otworzyc preview ETA.
4. Zlozyc checkout.

### Oczekiwany wynik
- brak batch diagnostics albo puste `kitchen_*`
- ETA nie idzie przez logike pieca zapiekanek
- admin nie pokazuje sztucznego `batch` dla tych koszykow

---

## Scenariusz 9 - override kuchni

### Kroki
1. W adminie ustawic override na `10`.
2. Powtorzyc scenariusz 1 i 2.

### Oczekiwany wynik
- 1 duza zapiekanka: `16 min`
- 4 duze zapiekanki: `20 min`
- diagnostyka admina nadal pokazuje bazowe `kitchen_eta_minutes`, a finalny klientowski czas powinien byc wyzszy o override

---

## Co zanotowac przy kazdym mismatchu

- liczba duzych sztuk w koszyku,
- czy w bazie wisialy inne aktywne zamowienia,
- czy override byl rozny od `0`,
- co pokazal preview koszyka,
- co pokazal finalny checkout,
- co pokazal active order,
- co pokazal admin diagnostics:
  - `kitchen_eta_minutes`
  - `kitchen_batch_index`
  - `kitchen_batch_count`
  - `kitchen_current_oven_load`
  - `kitchen_queue_pieces_before_order`
  - `kitchen_slots_used_by_order`

---

## Kryterium uznania Phase 2 za domknieta runtime

Phase 2 mozna uznac za zamknieta dopiero gdy:
- preview koszyka i finalny checkout sa spojne albo logicznie bliskie,
- active order i tracking korzystaja z aktualnego ETA backendu,
- admin diagnostics tlumaczy, skad wziela sie wartosc ETA,
- scenariusze `1 / 4 / 7 / 10 / 14+` zachowuja poprawne progi,
- `kids / 25cm / VAC` nie wpadaja falszywie w model batchowy,
- override nadal dziala i nie psuje diagnostyki.
