# ZapieApp API na Azure

Najprostszy pasujacy wariant na ten etap: Azure App Service for Linux z Pythonem.
Backend jest pojedyncza aplikacja FastAPI, a App Service daje publiczny HTTPS, App Settings
na sekrety i prosty deploy bez Kubernetes ani osobnej orkiestracji.

## Lokalnie

```powershell
cd C:\FFApi\my_fastapi_project
python -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements.txt
Copy-Item .env.example .env
```

W `.env` ustaw prawdziwe `MSSQL_CONN_STR` i `JWT_SECRET_KEY`, potem uruchom API:

```powershell
.\.venv\Scripts\python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Sprawdzenie:

```powershell
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/health/db
```

## Azure App Service

Uruchamiaj deploy z katalogu `my_fastapi_project`, bo tam jest `requirements.txt`.

```powershell
cd C:\FFApi\my_fastapi_project

$RG="rg-zapieapp-dev"
$APP="zapieapp-api-dev-alpha"
$LOCATION="westeurope"

az login
az webapp up `
  --resource-group $RG `
  --name $APP `
  --location $LOCATION `
  --runtime "PYTHON:3.11" `
  --sku B1 `
  --logs

az webapp config set `
  --resource-group $RG `
  --name $APP `
  --startup-file "bash startup.sh"

az webapp config appsettings set `
  --resource-group $RG `
  --name $APP `
  --settings `
    APP_ENV=production `
    SCM_DO_BUILD_DURING_DEPLOYMENT=true `
    JWT_SECRET_KEY="TU_DLUGI_LOSOWY_SECRET" `
    MSSQL_CONN_STR="mssql+pyodbc://USER:PASSWORD@SERVER.database.windows.net:1433/DATABASE?driver=ODBC+Driver+18+for+SQL+Server&Encrypt=yes&TrustServerCertificate=no&loginTimeout=1200" `
    CORS_ALLOW_ORIGIN_REGEX="^https?://(localhost|127\.0\.0\.1)(:\d+)?$"

az webapp restart --resource-group $RG --name $APP
```

Adres API:

```text
https://<nazwa-app-service>.azurewebsites.net
```

Healthcheck:

```text
https://<nazwa-app-service>.azurewebsites.net/health
https://<nazwa-app-service>.azurewebsites.net/health/db
```

## Flutter z lokalnym albo publicznym API

Android emulator do lokalnego backendu:

```powershell
cd C:\FFApi\zapieapp
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Telefon fizyczny w tej samej sieci Wi-Fi:

```powershell
ipconfig
flutter run --dart-define=API_BASE_URL=http://ADRES_IP_KOMPUTERA:8000
```

Azure:

```powershell
flutter run --dart-define=API_BASE_URL=https://<nazwa-app-service>.azurewebsites.net
```

Domyslnie aplikacja Flutter nadal uzywa `http://127.0.0.1:8000`, jesli nie podasz
`API_BASE_URL`.

## Uwaga o SQL Server ODBC

Projekt uzywa `mssql+pyodbc`. Jezeli App Service zwroci blad typu `Can't open lib
'ODBC Driver 18 for SQL Server'`, najprostsze sa dwie sciezki:

1. zmienic driver w `MSSQL_CONN_STR` na dostepny w runtime, np. `ODBC Driver 17 for SQL Server`;
2. przejsc na kontener w App Service albo Azure Container Apps i zainstalowac sterownik ODBC
   w Dockerfile.
