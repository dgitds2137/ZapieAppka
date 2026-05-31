## Follow-up data po weekendzie (checkpoint)

Ten dokument zbiera otwarte punkty, ktore sa juz przygotowane technicznie i czekaja na finalne dane (ceny, gramatury, assety, transze).

Status legend:
- `[ ]` do uzupelnienia
- `[x]` gotowe

## Checklist wykonawcza

### 1) Opakowanie termiczne do udek (runtime fee)

- [ ] Ustawic runtime setting `udka_thermal_packaging_fee` na wartosc produkcyjna.
- [x] Backend czyta wartosc i zwraca ja w `/checkout/udka-availability`.
- [x] Frontend dolicza pozycje `Opakowanie termiczne do udek` przy opcji `Na wynos`.
- [x] Doplata jest w subtotalu i payloadzie checkoutu.

Pliki:
- `my_fastapi_project/checkout_service.py`
- `zapieapp/lib/features/dashboard/dashboard_screen.dart`

Weryfikacja:
1. Wlaczyc `Na wynos` dla pozycji `Udka`.
2. Sprawdzic, czy pojawia sie koszt opakowania i zwieksza podsumowanie.
3. Wyslac checkout i potwierdzic pozycje kosztowa w payloadzie.

### 2) Dodatkowe zdjecie udek w kubeczku

- [ ] Ustawic runtime setting `udka_secondary_photo_url` na finalny asset URL.
- [x] Backend wystawia `secondary_photo_url` w modelu pozycji.
- [x] Frontend pokazuje sekcje `Dodatkowe zdjecie` w podgladzie produktu.

Pliki:
- `my_fastapi_project/main.py`
- `zapieapp/lib/features/dashboard/dashboard_screen.dart`

Weryfikacja:
1. Otworzyc podglad `Udka`.
2. Potwierdzic, ze jest glowny obraz + `Dodatkowe zdjecie`.

### 3) Finalne ceny i gramatury VAC

- [ ] Ustawic finalne ceny dla VAC:
  - `Zapiekanka VAC pieczarka`
  - `Zapiekanka VAC salami`
  - `Zapiekanka VAC hawajska`
  - `Zapiekanka VAC grecka`
- [ ] Ustawic finalne kalorie/gramatury.
- [ ] Doprecyzowac opisy skladu, jesli beda finalne korekty biznesowe.

Plik:
- `my_fastapi_project/sql/menu_positions.sql`

Weryfikacja:
1. Otworzyc katalog i sekcje VAC.
2. Sprawdzic ceny i wartosci odzywcze.
3. Potwierdzic komunikat `Sosy do zapiekanek VAC sa platne`.

### 4) Finalne dane dostepnosci udek

- [ ] Podmienic dane transz wypieku na finalne dane operacyjne.
- [x] Model obsluguje:
  - dostepne teraz
  - wypiekane
  - najblizsza transza
  - kolejna transza
  - rezerwacje po oplaceniu

Pliki:
- `my_fastapi_project/models.py`
- `my_fastapi_project/checkout_service.py`

Weryfikacja:
1. Sprawdzic panel dostepnosci `Udka`.
2. Potwierdzic, ze czasy i ilosci zgadzaja sie z finalnymi danymi.
3. Potwierdzic scenariusz mieszany: czesc gotowa teraz, czesc w kolejnych transzach.

## Minimalna kolejnosc wdrozenia po dostarczeniu danych

1. `udka_thermal_packaging_fee` (krytyczne dla poprawnych podsumowan kosztu).
2. `udka_secondary_photo_url` (domkniecie UX produktu `Udka`).
3. Finalne ceny/gramatury VAC w SQL.
4. Finalne transze `Udka` i test scenariusza rezerwacji.
