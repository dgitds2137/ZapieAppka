# Azure Trial Rebuild Todo

Cel: postawic od zera backend FastAPI + baze w nowej subskrypcji Azure,
zaseedowac dane i doprowadzic do dzialajacego dev environment w ramach trial
budzetu `200 USD`.

## Zasada pracy

- Uzywamy `az` CLI przez Azure Cloud Shell albo lokalnie po `az login`.
- Najpierw tworzymy infrastrukture, potem baze, potem seed, na koncu app.
- Nie wpisujemy prawdziwych danych do repo. Connection stringi i hasla ida do
  sekretow Azure.
- Wszystkie kroki robimy tak, zeby mozna je bylo powtorzyc na czysto.

## Co juz wiemy z repo

- Backend jest w `my_fastapi_project/`.
- Schema i seed siedza w `my_fastapi_project/sql/`.
- Start schema idzie przez `my_fastapi_project/db.py`.
- Docelowy hosting backendu to Azure Container Apps.

## Kolejnosc prac

### 1. Ustalic docelowy scope nowego srodowiska

- Nowa resource group dla trial.
- Nowy Azure SQL.
- Nowy Azure Container Registry.
- Nowa Azure Container App.
- Jeden zestaw sekretow runtime.

Walidacja:

- Wiemy, jak sie nazywa subscription, resource group i region.
- Wiemy, czy bazka ma byc `Azure SQL Database` czy inny wariant.

### 2. Utworzyc baze i odczytac jej parametry

- Tworzymy serwer / baze / firewall / ewentualnie private access.
- Pobieramy connection string.
- Sprawdzamy, czy uzytkownik z CLI ma prawa do wykonania seeda.

Walidacja:

- `az sql db show` / odpowiednik zwraca baze.
- Potrafimy polaczyc sie testowo z bazy z poziomu CLI lub tymczasowego kontenera.

### 3. Zaseedowac baze schematem

- Odpalamy pliki SQL z `my_fastapi_project/sql/` w sensownej kolejnosci.
- Trzymamy sie idempotentnych operacji typu `IF OBJECT_ID(...)`, `MERGE`.
- Po seeding sprawdzamy tabele kluczowe:
  - `Users`
  - `Roles`
  - `MenuPositions`
  - `MenuAddons`
  - `Sessions`
  - `CheckoutOrders`
  - `AppRuntimeSettings`
  - `PrepTimeSettings`

Walidacja:

- Schema istnieje.
- Seed nie duplikuje rekordow przy ponownym uruchomieniu.

### 4. Zbudowac i wrzucic obraz backendu

- Tworzymy ACR albo uzywamy nowego.
- Budujemy obraz z `my_fastapi_project/Dockerfile`.
- Pushujemy obraz do ACR.

Walidacja:

- Obraz istnieje w registry.
- Container App moze go pobrac.

### 5. Postawic Container App

- Tworzymy environment dla Container Apps.
- Tworzymy app z `ingress external`.
- Ustawiamy `PORT=8000`.
- Podpinamy sekrety:
  - `mssql-conn-str`
  - `jwt-secret-key`
- Ustawiamy env var `MSSQL_CONN_STR=secretref:mssql-conn-str`.
- Wlaczamy healthchecki `/health` i `/health/db`.

Walidacja:

- `/health` odpowiada.
- `/health/db` odpowiada i widzi baze.

### 6. Spiac backend z bazka

- Upewniamy sie, ze backend startuje na nowym connection stringu.
- Sprawdzamy logi Container App.
- Weryfikujemy, czy `ensure_database_schema()` nie robi problemu przy starcie.

Walidacja:

- API przechodzi boot bez recznego grzebania.
- Brak bledow ODBC / auth / schema init w logach.

### 7. Wgrac dane testowe i sprawdzic flow

- Sprawdzamy konto testowe / logowanie.
- Sprawdzamy menu.
- Sprawdzamy koszyk i checkout.
- Sprawdzamy historia zamowien.
- Sprawdzamy profile / sesje / role.

Walidacja:

- Jeden pelny flow dziala end-to-end.

### 8. Ustalic koszt i limity trial

- Sprawdzamy bieżący koszt dzienny / miesieczny.
- Ustalamy monitoring budget alert.
- Ustalamy, co mozna zamykac / stopowac poza godzinami pracy.

Walidacja:

- Mamy prosty plan, jak nie przepalic trialu przed czasem.

## Kiedy bede potrzebowal od Ciebie dostepow do bazy

Potrzebne beda dopiero w tych momentach:

1. Gdy bedziemy tworzyc nowa baze i potrzebny bedzie connection string.
2. Gdy bede wykonywal pierwszy seed na czystej bazie.
3. Gdy bede testowal realne logowanie / checkout na nowym srodowisku.

Najwygodniej bedzie, jesli podasz:

- host / server name
- nazwe bazy
- username
- haslo
- czy laczymy sie przez public access czy private endpoint

## Minimalny plan startowy

1. Tworzymy nowa resource group.
2. Tworzymy Azure SQL.
3. Sprawdzamy polaczenie.
4. Wrzucamy schema + seed.
5. Budujemy i wdrazamy backend do Container App.
6. Odpalamy smoke testy.

