# Patch plan - aplikacja mobilna do zamawiania jedzenia

## Status

Dokument roboczy dodany do repo 2026-05-30.

## Cel patcha

Wprowadzic poprawki w strukturze produktow, personalizacji sosow/dodatkow oraz prezentacji dostepnosci wybranych pozycji w aplikacji mobilnej.

---

## 1. Zapiekanki 0,5 m - kolejnosc produktow

Ustawic kolejnosc zapiekanek 0,5 m w katalogu zgodnie z ponizsza lista:

1. Pieczarka
2. Szynka
3. Hawajska
4. Salami
5. Jalapeno salami
6. Wiejska
7. Goralska
8. Grecka

---

## 2. Sosy do zapiekanek 0,5 m

### Logika biznesowa

Dla kazdej zapiekanki 0,5 m jeden sos powinien byc dostepny gratis.

Sosy maja byc pakowane osobno i wybierane przez uzytkownika w koszyku.

### Zmiana UX

Nie uzywac obecnej personalizacji przez ikone pedzelka, poniewaz moze byc nieczytelna dla uzytkownika.

Zamiast tego w koszyku dodac osobna sekcje:

**Wybierz sosy do zapiekanki**

Sekcja powinna pokazywac:

- ile sosow jest gratis dla danej pozycji,
- ktore sosy zostaly juz wybrane jako gratisowe,
- ceny dodatkowych sosow po przekroczeniu limitu gratisowego.

### Przyklad dzialania

Jezeli uzytkownik ma jedna zapiekanke 0,5 m:

- 1 sos = gratis,
- kazdy kolejny sos = platny zgodnie z cennikiem.

---

## 3. Kategorie / przelaczanie produktow

W widoku produktu lub w glownej nawigacji kategorii dodac mozliwosc szybkiego przelaczania miedzy sekcjami, np.:

- Zapiekanki
- Zapiekanki 25 cm
- Dodatki
- Napoje
- Frytki

### Wazne

Kategoria **Dodatki** powinna byc widoczna normalnie na gorze, jako osobna pozycja/kategoria, a nie ukryta glebiej.

Kategoria **Zapiekanki kids** powinna zostac przemianowana na:

**Zapiekanki 25 cm**

Dobrze byloby, aby **Dodatki** znajdowaly sie bezposrednio obok / po kategorii **Zapiekanki 25 cm**.

---

## 4. Dodatki - ceny

Wszystkie dodatki musza miec jawnie widoczne ceny.

Dotyczy to zarowno listy dodatkow, jak i ewentualnego wyboru dodatkow w koszyku lub w konfiguracji produktu.

---

## 5. Zapiekanki do wypieku w domu / VAC

Dodac osobna sekcje produktowa:

**Zapiekanki do wypieku w domu (VAC)**

Produkty w tej sekcji:

1. Pieczarka
2. Salami
3. Hawajska
4. Grecka

### Sosy dla VAC

Przy zapiekankach VAC sosy sa platne.

Nalezy dodac informacje przy tej sekcji / produktach:

**Sosy do zapiekanek VAC sa platne.**

---

## 6. Goralska - korekta skladnika

W skladnikach zapiekanki **Goralska** zmienic nazwe skladnika:

Z:

**oscypek**

Na:

**ser wedzony a'la oscypek**

Powod: zgodnosc z faktycznym skladnikiem uzywanym w produkcie.

---

## 7. Udka - zmiana produktu i dostepnosci

### Zdjecie

Zmienic zdjecie produktu "Udka" na zdjecie przedstawiajace cala noge.

### Porcja

Zmienic ilosc w porcji:

Z:

**3 sztuki**

Na:

**1 sztuka / jedna cala noga**

---

## 8. Udka - dostepnosc i rezerwacja

Dodac mechanizm prezentowania dostepnosci udek.

W produkcie powinny byc widoczne informacje:

- ile udek jest dostepnych "na juz",
- ile udek jest aktualnie wypiekanych,
- na ktora godzine beda gotowe,
- mozliwosc rezerwacji po oplaceniu zamowienia.

### Scenariusz

Moze wystapic sytuacja, ze:

- czesc udek jest juz gotowa,
- czesc bedzie gotowa w kolejnych transzach, np. co 30 minut.

Aplikacja powinna umozliwiac pokazanie takiej dostepnosci w sposob czytelny dla uzytkownika.

### Przyklad UI

**Dostepne teraz:** 4 szt.  
**Wypiekane:** 8 szt.  
**Najblizsza transza gotowa o:** 16:30  
**Kolejna transza:** 17:00

---

## 9. Udka - polewa / sos

Dodac mozliwosc wyboru polewy/sosu do udek w koszyku, analogicznie jak wybor sosow do zapiekanek.

Dodac informacje, ze uzytkownik moze wybrac polewe w koszyku.

---

## 10. Udka - sprzedaz na wynos

Dodac informacje, ze udka mozna kupic na wynos.

Jezeli wymagane jest opakowanie termiczne, aplikacja powinna doliczac koszt opakowania.

### Do pokazania uzytkownikowi

- informacja o mozliwosci zakupu na wynos,
- koszt opakowania termicznego,
- ewentualna pozycja kosztowa w koszyku.

---

## 11. Zdjecie udek w kubeczku

Dodac dodatkowe zdjecie produktu pokazujace udka / porcje w kubeczku.

Zdjecie zostanie dostarczone pozniej.

---

## 12. Frytki - ketchup gratis

Przy produkcie **Frytki** dodac informacje:

**Ketchup do frytek gratis.**

Nie musi to byc osobna platna personalizacja, wystarczy informacja przy produkcie lub w koszyku.

---

## 13. Dane do uzupelnienia pozniej

Po weekendzie zostana dostarczone:

- finalne ceny,
- gramatury,
- brakujace zdjecia,
- ewentualne szczegoly dotyczace dostepnosci udek i transz wypieku.

Na ten moment patch powinien przygotowac strukture, logike i miejsca w UI pod te dane.

---

## Wstepny plan dzialan - krok 1

### Cel kroku

Ustawic kolejnosc wyswietlania zapiekanek 0,5 m zgodnie z lista biznesowa:

1. Pieczarka
2. Szynka
3. Hawajska
4. Salami
5. Jalapeno salami
6. Wiejska
7. Goralska
8. Grecka

### Obecny stan w repo

- Frontend buduje kategorie w [zapieapp/lib/features/dashboard/dashboard_screen.dart](/C:/FFApi/zapieapp/lib/features/dashboard/dashboard_screen.dart:6584).
- Rozpoznanie kategorii odbywa sie w [zapieapp/lib/features/dashboard/dashboard_screen.dart](/C:/FFApi/zapieapp/lib/features/dashboard/dashboard_screen.dart:6649).
- Backend zwraca pozycje klientowi posortowane tylko po `position_type` i `name` w [my_fastapi_project/main.py](/C:/FFApi/my_fastapi_project/main.py:88).
- Panel admina rowniez pobiera pozycje bez dedykowanego `sort_order` w [my_fastapi_project/checkout_service.py](/C:/FFApi/my_fastapi_project/checkout_service.py:661).
- Model `MenuPositions` nie ma dzis pola `sort_order` w [my_fastapi_project/models.py](/C:/FFApi/my_fastapi_project/models.py:90).

### Wniosek

Krok 1 nie ma jeszcze trwalego mechanizmu sortowania pozycji menu. Obecny porzadek wynika ubocznie z nazwy i typu pozycji, wiec nie gwarantuje docelowej kolejnosci biznesowej.

### Rekomendowane podejscie

1. Wprowadzic trwale pole `sort_order` dla `MenuPositions` w backendzie i bazie danych.
2. Zwracac `sort_order` w endpointach katalogu klienta i admina.
3. Sortowac zapiekanki 0,5 m po `sort_order`, a nie po samej nazwie.
4. Ustawic wartosci `sort_order` dla osmiu docelowych pozycji 0,5 m zgodnie z lista biznesowa.
5. Zostawic frontendowy fallback po nazwie tylko jako zabezpieczenie na czas migracji danych.

### Proponowana implementacja techniczna

1. Backend:
   Dodac `sort_order` do `MenuPositionDB`, schematow API i serializacji katalogu.
2. SQL / seed:
   Rozszerzyc skrypt pozycji menu o aktualizacje `sort_order` dla zapiekanek 0,5 m.
3. Frontend:
   W `dashboard_screen.dart` dodac jawne sortowanie pozycji w kategorii `zapiekanki`, ograniczone do wariantow 0,5 m.
4. Admin:
   Na tym etapie minimum to odczyt `sort_order`; edycje reczna w panelu mozna odlozyc do kolejnego kroku.
5. Testy:
   Dodac test jednostkowy dla sortowania listy pozycji oraz szybki test regresyjny kategorii `zapiekanki`.

### Zakres na pierwszy commit dla kroku 1

- migracja/model backendu dla `sort_order` pozycji,
- serializacja pola do API,
- przypisanie kolejnosci dla 8 zapiekanek 0,5 m,
- sortowanie po stronie frontendu,
- testy sortowania.

### Otwarte pytania

- Jak dokladnie w danych nazywaja sie wszystkie warianty 0,5 m i czy wystepuja dodatkowe sufiksy, np. rozmiar albo opis?
- Czy kolejnosc ma dotyczyc tylko sekcji 0,5 m, czy tez wplywac na inne warianty zapiekanek?
- Czy panel admina ma od razu umozliwiac edycje `sort_order`, czy wystarczy wdrozenie wartosci domyslnych z migracji?
