# Sprawozdanie wdrozenia logiki czasu zapiekanek

## Cel zmiany

Celem bylo uporzadkowanie czasu przygotowania zapiekanek tak, zeby aplikacja lepiej odzwierciedlala realna prace kuchni, pieca i kolejnosci wsadow.

Wczesniej czas byl zbyt ogolny i bardziej patrzyl na sama liczbe zamowien. Po zmianie system patrzy przede wszystkim na to, ile duzych, goracych zapiekanek faktycznie trzeba zrobic.

## Jaka logika zostala wprowadzona

System liczy czas na podstawie liczby duzych zapiekanek, ktore rzeczywiscie obciazaja piec.

Obecnie obowiazuje taki model:

- pierwsza pojedyncza duza zapiekanka: `6 min`
- od `1 do 3` duzych zapiekanek w kolejce: `7 min`
- od `4 do 6` duzych zapiekanek: `10 min`
- od `7 do 13` duzych zapiekanek: `15 min`
- od `14` wzwyz: `20 min`

To oznacza, ze system jest blizej realnej pracy kuchni:

- male obciazenie daje bardzo szybki czas
- srednie obciazenie utrzymuje sensowny czas pieca
- wiekszy ruch stopniowo podnosi ETA, ale w kontrolowanych progach

## Czego system nie wrzuca do tej kolejki

Z tej logiki zostaly wykluczone pozycje, ktore nie powinny sztucznie wydluzac czasu duzych zapiekanek:

- `kids`
- `25 cm`
- `VAC`
- `mrozone`

Dzieki temu system nie traktuje kazdej pozycji tak samo. Liczy tylko to, co faktycznie zajmuje piec pod duze, gorace zapiekanki.

## Rola kuchni

Zostawilismy tez mozliwosc recznego podbicia czasu przez obsluge, jesli sytuacja na lokalu tego wymaga.

Mozliwe reczne narzuty to:

- `0 min`
- `10 min`
- `20 min`
- `30 min`
- `40 min`

Limit maksymalny koncowego czasu pozostaje na poziomie `60 min`.

To daje dwa tryby pracy jednoczesnie:

- automatyka dziala w standardowym ruchu
- kuchnia nadal moze zareagowac recznie przy awarii, skoku ruchu albo opoznieniach operacyjnych

## Co to poprawia operacyjnie

Najwazniejsze efekty tej zmiany:

- czas jest liczony pod realna liczbe duzych zapiekanek, a nie pod sama liczbe zamowien
- male pozycje i produkty poboczne nie zawyzaja sztucznie ETA
- pojedyncze zamowienia nie wygladaja juz tak, jakby lokal byl mocno zapchany
- przy duzym ruchu system zaczyna zachowywac sie bardziej jak realny piec i realna kolejka
- kuchnia zachowuje kontrole awaryjna przez reczny narzut

## Wniosek

Wdrozone podejscie jest duzo blizsze praktyce gastronomicznej niz poprzedni model.

System:

- lepiej rozpoznaje, co rzeczywiscie obciaza piec
- lepiej odroznia lekki ruch od duzego oblozenia
- daje bardziej wiarygodny czas dla klienta
- nadal pozwala obsludze przejac kontrole, gdy sytuacja na lokalu tego wymaga
