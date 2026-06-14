# ZapieApp - ETA duzych zapiekanek

## Cel

Ten dokument jest aktualna specyfikacja logiki ETA dla duzych, wypiekanych na miejscu zapiekanek.

Nie opisuje historii wdrozenia. Opisuje docelowe zasady, ktore backend ma realizowac.

## Zakres

Logika dotyczy tylko duzych zapiekanek przygotowywanych przez lokalna kuchnie.

Do tej kolejki nie wchodza:

- pozycje `kids`
- pozycje `25cm`
- pozycje `VAC`
- pozycje `frozen`
- udka
- inne dodatki, lody, napoje itp.

## Reguly automatycznego ETA

### Stan pustej kolejki

Jesli nie ma aktywnej kolejki duzych zapiekanek i klient zamawia jedna duza zapiekanke:

- ETA = `6 min`

To jest jedyny przypadek, w ktorym pokazujemy `6 min`.

### Buckety kolejkowe

W pozostalych przypadkach ETA liczy sie po lacznej liczbie duzych zapiekanek:

- juz aktywnych w kolejce
- plus duze zapiekanki z aktualnie skladanego zamowienia

Mapa bucketow:

| Laczna liczba duzych zapiekanek | ETA |
| --- | --- |
| 1-3 | 7 min |
| 4-6 | 10 min |
| 7-13 | 15 min |
| 14+ | 20 min |

Zasady:

- automatyczne ETA nigdy nie przekracza `20 min`
- aktywna kolejka nie uwzglednia zamowien zakonczonych ani anulowanych
- liczymy sztuki duzych zapiekanek, nie liczbe zamowien

## Reczna korekta kuchni

Kuchnia moze dolozyc reczny narzut do ETA dla nowych zamowien:

- `0 min`
- `+10 min`
- `+20 min`
- `+30 min`
- `+40 min`

Finalne ETA:

```text
final_eta = min(automatic_eta + override_minutes, 60)
```

Zasady:

- reczna korekta dziala tylko na nowe zamowienia
- juz utworzone zamowienia zachowuja zapisane `eta_minutes`
- finalne ETA nigdy nie przekracza `60 min`

## Przyklady

### Przyklad 1

- aktywna kolejka: `0`
- nowe zamowienie: `1` duza zapiekanka

Wynik:

- `6 min`

### Przyklad 2

- aktywna kolejka: `2`
- nowe zamowienie: `1` duza zapiekanka

Lacznie:

- `3`

Wynik:

- `7 min`

### Przyklad 3

- aktywna kolejka: `5`
- nowe zamowienie: `2` duze zapiekanki

Lacznie:

- `7`

Wynik:

- `15 min`

### Przyklad 4

- automat: `20 min`
- reczna korekta: `+20 min`

Wynik:

- `40 min`

### Przyklad 5

- automat: `20 min`
- reczna korekta: `+40 min`

Wynik:

- `60 min`

## Wymagania backendowe

Backend musi:

1. rozpoznawac, czy pozycja jest duza zapiekanka kuchni
2. zliczac aktywne sztuki duzych zapiekanek w kolejce
3. doliczac sztuki z nowego zamowienia
4. wyliczac bucket ETA wedlug tabeli powyzej
5. dokladac reczny override kuchni
6. obcinac finalny wynik do `60 min`

## Wymagania panelu admina

Admin panel utrzymuje jedno ustawienie:

- `Kitchen ETA Override`

Dozwolone wartosci:

- `0`
- `10`
- `20`
- `30`
- `40`

Zmiana ma dzialac natychmiast dla nowo tworzonych zamowien.

## Wymagania testowe

Testy powinny potwierdzac co najmniej:

1. `0 aktywnych + 1 nowa duza` -> `6`
2. `1-3 lacznie` -> `7`
3. `4-6 lacznie` -> `10`
4. `7-13 lacznie` -> `15`
5. `14+ lacznie` -> `20`
6. `override + cap 60`
7. `kids / 25cm / VAC / frozen` nie wchodza do tej kolejki
