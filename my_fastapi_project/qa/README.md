# Backend QA (API smoke + e2e cases)

Ten folder trzyma pakiet testow backendu uruchamialy lokalnie i w CI. Skupiamy sie na scenariuszu: user -> employee -> driver.

Struktura:
- `README.md` - ten plik
- `scenarios/` - opisy scenariuszy manualnych
- `scenarios/order_lifecycle.md` - 3 testy do codziennego odtworzenia
- `run_smoke_order_flow.py` - skrypt automatyczny order lifecycle
- `run_e2e_smoke.ps1` - wrapper PowerShell
- `run_e2e_smoke.sh` - wrapper Bash
- `tests/` - miejsce docelowe dla przyszlych testow
- `.env.qa.example` - szablon zmiennych srodowiska

## Szybki start

1. Przygotuj konto pracownika i kierowcy w nowym środowisku.
2. Ustaw zmienne srodowiskowe i uruchom wrapper.

PowerShell:

```powershell
$env:BASE_URL = "https://zapieapp-api-dev-alpha.ambitiousstone-9e7294a6.polandcentral.azurecontainerapps.io"
$env:EMPLOYEE_EMAIL = "employee@zapieapp.pl"
$env:EMPLOYEE_PASSWORD = "..."
$env:DRIVER_EMAIL = "driver@zapieapp.pl"
$env:DRIVER_PASSWORD = "..."
./run_e2e_smoke.ps1
```

Bash:

```bash
export BASE_URL=https://zapieapp-api-dev-alpha.ambitiousstone-9e7294a6.polandcentral.azurecontainerapps.io
export EMPLOYEE_EMAIL=employee@zapieapp.pl
export EMPLOYEE_PASSWORD=...
export DRIVER_EMAIL=driver@zapieapp.pl
export DRIVER_PASSWORD=...
./run_e2e_smoke.sh
```

## Co robi skrypt
- Tworzy testowego klienta przez `POST /register`.
- Tworzy `verification` przez `POST /checkout/verification`.
- Sprawdza `GET /checkout/active`.
- Loguje worker i drivera, mapuje `verification_id` do `checkout_order_id` przez `/admin/dashboard`.
- Ustawia statusy employee: `assigned -> in_oven -> ready_for_delivery`.
- Ustawia statusy drivera: `assigned -> on_the_way -> completed`.
- Potwierdza odbior `POST /checkout/confirm-receipt`.

## Minimalne kryteria przejscia smoke
- brak blednych odpowiedzi endpointow (szczegolnie 5xx)
- expected statusy na mutacjach: 200/201
- brak blednych timeoutow/wylaczonych endpointow
- finalnie `SMOKE_OK`.

## Notatki
- Endpointy przyjmują JSON tam, gdzie to modelowa forma API. Skrypty ustawiają poprawne naglowki.
- Do rozbudowy: doklejamy tutaj kolejne scenariusze pod `scenarios/` i skrypty pod `tests/`.
