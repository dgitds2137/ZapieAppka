# TIME ZAPIEKANKI - Phase 2 Smoke Commands

## 1. Backend target

Uzywamy aktualnego backendu Azure Container Apps:

```powershell
$env:API_BASE_URL = 'https://zapieapp-api-dev-alpha.ambitiousstone-9e7294a6.polandcentral.azurecontainerapps.io'
```

Szybki healthcheck:

```powershell
curl.exe "$env:API_BASE_URL/health"
curl.exe "$env:API_BASE_URL/health/db"
```

---

## 2. Frontend local web na Chrome

Uruchom z katalogu `C:\FFApi\zapieapp`:

```powershell
cd C:\FFApi\zapieapp
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 3001 --dart-define API_BASE_URL=$env:API_BASE_URL
```

Jesli port 3001 jest zajety:

```powershell
Get-NetTCPConnection -LocalPort 3001 -ErrorAction SilentlyContinue | Select-Object OwningProcess,LocalAddress,LocalPort,State
Stop-Process -Id <PID> -Force
```

---

## 3. Szybki preview ETA bez klikania UI

### 3.1 1 duza zapiekanka

```powershell
$body = @{
  created_at = '2026-06-14T12:00:00Z'
  currency = 'PLN'
  subtotal_amount = 40.0
  total_amount = 40.0
  redeemed_points = 0
  redeemed_amount = 0.0
  eta_minutes = 10
  payment_method = 'blik'
  fulfillment_method = 'odbior'
  fulfillment_option_index = 1
  address_option_index = 0
  address = @{
    title = 'Sklotowa 6/9'
    subtitle = '02-220, Warszawa'
    eta_label = 'ok. 10 min.'
  }
  items = @(
    @{
      cart_entry_id = 1
      position_id = 1
      name = 'Pieczarka 50cm'
      description = 'bagietka, maslo, pieczarki 120g'
      photo_url = $null
      calories = $null
      price = 40.0
    }
  )
  session_token = $null
  user_email = $null
  notes = ''
} | ConvertTo-Json -Depth 6

Invoke-RestMethod -Method Post -Uri "$env:API_BASE_URL/checkout/eta-preview" -ContentType 'application/json' -Body $body
```

Oczekiwane przy pustej kuchni:
- `eta_minutes = 6`
- `kitchen_eta_minutes = 6`
- `kitchen_batch_index = 1`
- `kitchen_batch_count = 1`
- `kitchen_slots_used_by_order = 1`

### 3.2 4 duze zapiekanki

```powershell
$body = @{
  created_at = '2026-06-14T12:00:00Z'
  currency = 'PLN'
  subtotal_amount = 160.0
  total_amount = 160.0
  redeemed_points = 0
  redeemed_amount = 0.0
  eta_minutes = 10
  payment_method = 'blik'
  fulfillment_method = 'odbior'
  fulfillment_option_index = 1
  address_option_index = 0
  address = @{
    title = 'Sklotowa 6/9'
    subtitle = '02-220, Warszawa'
    eta_label = 'ok. 10 min.'
  }
  items = @(
    @{
      cart_entry_id = 1
      position_id = 1
      name = 'Pieczarka 50cm'
      description = 'bagietka, maslo, pieczarki 120g'
      photo_url = $null
      calories = $null
      price = 40.0
    },
    @{
      cart_entry_id = 2
      position_id = 2
      name = 'Szynka 50cm'
      description = 'bagietka, maslo, szynka 30g'
      photo_url = $null
      calories = $null
      price = 40.0
    },
    @{
      cart_entry_id = 3
      position_id = 3
      name = 'Salame 50cm'
      description = 'bagietka, maslo, salame 30g'
      photo_url = $null
      calories = $null
      price = 40.0
    },
    @{
      cart_entry_id = 4
      position_id = 4
      name = 'Kurczak 50cm'
      description = 'bagietka, maslo, kurczak 30g'
      photo_url = $null
      calories = $null
      price = 40.0
    }
  )
  session_token = $null
  user_email = $null
  notes = ''
} | ConvertTo-Json -Depth 6

Invoke-RestMethod -Method Post -Uri "$env:API_BASE_URL/checkout/eta-preview" -ContentType 'application/json' -Body $body
```

Oczekiwane przy pustej kuchni:
- `eta_minutes = 10`
- `kitchen_eta_minutes = 10`
- `kitchen_batch_index = 1`
- `kitchen_batch_count = 1`

### 3.3 7 duzych zapiekanek

Zmien powyzszy payload tak, aby `items` mialy 7 duzych pozycji albo 7 wpisow duzych zapiekanek.

Oczekiwane przy pustej kuchni:
- `eta_minutes = 15`
- `kitchen_eta_minutes = 15`
- nie moze zostac `10`

### 3.4 14 duzych zapiekanek

Analogicznie jak wyzej.

Oczekiwane przy pustej kuchni:
- `eta_minutes = 20`
- `kitchen_eta_minutes = 20`

---

## 4. Smoke admin dashboard API

Jesli masz `session_token` admina i email admina:

```powershell
$adminSessionToken = '<ADMIN_SESSION_TOKEN>'
$adminEmail = '<ADMIN_EMAIL>'
curl.exe "$env:API_BASE_URL/admin/dashboard?session_token=$adminSessionToken&user_email=$adminEmail"
```

Szukaj w odpowiedzi per order pol:
- `kitchen_eta_minutes`
- `kitchen_batch_index`
- `kitchen_batch_count`
- `kitchen_current_oven_load`
- `kitchen_queue_pieces_before_order`
- `kitchen_slots_before_order`
- `kitchen_slots_used_by_order`

---

## 5. Manual smoke z UI - minimalna kolejnosc

### Case A
- otworz frontend local web
- dodaj 1 duza zapiekanke
- wejdz do koszyka
- potwierdz, ze UI pokazuje `ok. 6 min.` lub runtimeowo bliski wynik preview
- przejdz checkout
- sprawdz active order
- sprawdz tracking
- sprawdz admin diagnostics

### Case B
- wyczysc aktywne testowe zamowienie
- dodaj 4 duze zapiekanki
- potwierdz `10 min`

### Case C
- wyczysc aktywne testowe zamowienie
- dodaj 7 duzych zapiekanek
- potwierdz `15 min`

### Case D
- wyczysc aktywne testowe zamowienie
- dodaj 14 duzych zapiekanek
- potwierdz `20 min`

### Case E
- sprawdz koszyk `kids` / `25cm` / `VAC`
- potwierdz, ze nie wpada w batch diagnostics zapiekanek

---

## 6. Przyklad update override kuchni do zera

Jesli masz dane admina:

```powershell
$body = @{
  minutes = 0
  session_token = '<ADMIN_SESSION_TOKEN>'
  user_email = '<ADMIN_EMAIL>'
} | ConvertTo-Json

Invoke-RestMethod -Method Patch -Uri "$env:API_BASE_URL/admin/catalog/kitchen-eta" -ContentType 'application/json' -Body $body
```

---

## 7. Co zapisac przy mismatchu

- ile bylo duzych sztuk
- czy byly aktywne inne zamowienia
- czy override byl ustawiony na `0`
- co pokazal `/checkout/eta-preview`
- co pokazal finalny checkout
- co pokazal active order
- co pokazal tracking
- co pokazal admin dashboard w polach `kitchen_*`
