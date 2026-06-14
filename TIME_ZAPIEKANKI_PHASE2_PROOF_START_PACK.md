# TIME ZAPIEKANKI - Phase 2 Proof Start Pack

## Po co ten plik

To jest najkrotsza mozliwa wersja wejscia w proof Phase 2.

Bez backlogu.
Bez pelnego runbooka.
Bez skakania po kilku plikach.

Masz tu:
- 3 glowne komendy,
- 3 kluczowe scenariusze smoke,
- 1 miejsce wpisania wyniku.

---

## 1. Odpal po kolei

### Krok 1 - backend tests

```powershell
cd C:\FFApi\my_fastapi_project
python tests\run_time_zapiekanki_phase2_suite.py
```

### Krok 2 - frontend tests

```powershell
cd C:\FFApi\zapieapp
flutter test
```

### Krok 3 - frontend na Chrome z Azure backendem

```powershell
cd C:\FFApi\zapieapp
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 3001 --dart-define API_BASE_URL=https://zapieapp-api-dev-alpha.ambitiousstone-9e7294a6.polandcentral.azurecontainerapps.io
```

---

## 2. Sprawdz tylko te 3 scenariusze smoke

### Scenario A - 1 duza zapiekanka

Oczekiwanie:
- przy pustej kolejce `6 min`

### Scenario B - 7 duzych zapiekanek

Oczekiwanie:
- `15 min`
- nie zostaje stare `10 min`

### Scenario C - aktywne zamowienie + admin

Oczekiwanie:
- active order pokazuje spojny ETA
- admin pokazuje sensowne `kitchen_*`
- jesli zamowienie nie miesci sie w aktualnym wsadzie, `in_oven` nie powinno przejsc bez konfliktu

---

## 3. Gdzie wpisac wynik

Wyniki wpisuj tutaj:

- [TIME_ZAPIEKANKI_PHASE2_EXECUTION_LOG.md](/C:/FFApi/TIME_ZAPIEKANKI_PHASE2_EXECUTION_LOG.md)

Minimalnie uzupelnij:
- `Backend tests`
- `Frontend tests`
- `Frontend Chrome smoke`
- `Admin smoke`
- `Decision gate`

---

## 4. Kiedy uznac, ze trzeba wracac do kodu

Wracamy do kodu tylko jesli pojawi sie jeden z tych problemow:
- backend runner failuje
- `flutter test` failuje
- `7` duzych dalej pokazuje `10 min`
- active order i preview sa logicznie rozjechane
- admin pokazuje sprzeczne dane albo przepuszcza zly `in_oven`

Jesli tego nie ma, kolejny ruch to juz completion audit, a nie kolejna implementacja.
