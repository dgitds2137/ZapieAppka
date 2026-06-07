## Follow-up data po weekendzie (checkpoint)

Ten dokument zbiera otwarte punkty, ktore sa juz przygotowane technicznie i czekaja na finalne dane (ceny, gramatury, assety, transze).

Status legend:
- `TODO` do uzupelnienia
- `[x]` gotowe

## Checklist wykonawcza

### 1) Opakowanie termiczne do udek (runtime fee)

- [x] Ustawiony runtime setting `udka_thermal_packaging_fee = 3.00`.
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

- [x] Ustawiony runtime setting `udka_secondary_photo_url = assets/images/chickenLegCup.png`.
- [x] Backend wystawia `secondary_photo_url` w modelu pozycji.
- [x] Frontend pokazuje sekcje `Dodatkowe zdjecie` w podgladzie produktu.

Pliki:
- `my_fastapi_project/main.py`
- `zapieapp/lib/features/dashboard/dashboard_screen.dart`

Weryfikacja:
1. Otworzyc podglad `Udka`.
2. Potwierdzic, ze jest glowny obraz + `Dodatkowe zdjecie`.

### 3) Finalne ceny i gramatury VAC

- [x] Ustawione ceny VAC:
  - `Zapiekanka VAC pieczarka`
  - `Zapiekanka VAC salami`
  - `Zapiekanka VAC hawajska`
  - `Zapiekanka VAC grecka`
- [x] Ustawione kalorie i gramatura (`200 g` w opisie kazdej pozycji).
- [x] Opisy skladu doprecyzowane i ujednolicone.

Plik:
- `my_fastapi_project/sql/menu_positions.sql`

Weryfikacja:
1. Otworzyc katalog i sekcje VAC.
2. Sprawdzic ceny i wartosci odzywcze.
3. Potwierdzic komunikat `Sosy do zapiekanek VAC sa platne`.

### 4) Finalne dane dostepnosci udek

- [x] Podmienione dane transz wypieku na finalne dane operacyjne przez runtime settings:
  - `udka_pickup_slots = 12:00,15:00,18:00`
  - `udka_oven_capacity = 16`
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

## Status

Wszystkie pozycje checklisty sa domkniete technicznie i ustawione w seedach/runtime. Dalsze zmiany beda juz tylko korektami wartosci biznesowych (bez zmian architektury).
