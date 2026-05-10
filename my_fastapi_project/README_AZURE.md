# ZapieApp API na Azure

Rekomendowany wariant dla ciaglego developmentu: Azure Container Apps + Azure
Container Registry + GitHub Actions. Backend jest budowany z `Dockerfile`, wiec
systemowe zaleznosci, w tym ODBC Driver 18 dla SQL Server, sa wersjonowane razem
z aplikacja. Push do `main` buduje obraz i publikuje nowa rewizje API.

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

## Azure Container Apps CI/CD

Workflow jest w `.github/workflows/deploy-api-containerapp.yml`.

W GitHub ustaw repository variables:

```text
AZURE_RESOURCE_GROUP=rg-zapieapp-dev
AZURE_CONTAINER_REGISTRY_NAME=<unikalna-nazwa-acr>
AZURE_CONTAINER_APP_ENVIRONMENT=zapieapp-api-env
AZURE_CONTAINER_APP_NAME=zapieapp-api-dev-alpha
```

W GitHub ustaw repository secrets:

```text
AZURE_CLIENT_ID=<client id aplikacji Entra z federated credential>
AZURE_TENANT_ID=<tenant id>
AZURE_SUBSCRIPTION_ID=<subscription id>
```

Sekrety runtime trzymaj w Azure Container App, nie w repo:

```text
mssql-conn-str
jwt-secret-key
```

Jednorazowy setup najlepiej uruchomic w Azure Cloud Shell:

```powershell
$RG="rg-zapieapp-dev"
$APP="zapieapp-api-dev-alpha"
$ENV="zapieapp-api-env"
$ACR="<unikalna-nazwa-acr>"
$LOCATION="westeurope"
$REPO="dgitds2137/ZapieAppka"

az login
az extension add --name containerapp --upgrade
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights

az group create --name $RG --location $LOCATION
az acr create --resource-group $RG --name $ACR --sku Basic
az containerapp env create --resource-group $RG --name $ENV --location $LOCATION

$MSSQL_CONN_STR="mssql+pyodbc://USER:PASSWORD@SERVER.database.windows.net:1433/DATABASE?driver=ODBC+Driver+18+for+SQL+Server&Encrypt=yes&TrustServerCertificate=no&loginTimeout=1200"
$JWT_SECRET_KEY="TU_DLUGI_LOSOWY_SECRET"

az containerapp create `
  --resource-group $RG `
  --name $APP `
  --environment $ENV `
  --image mcr.microsoft.com/azuredocs/containerapps-helloworld:latest `
  --ingress external `
  --target-port 8000 `
  --secrets "mssql-conn-str=$MSSQL_CONN_STR" "jwt-secret-key=$JWT_SECRET_KEY" `
  --env-vars `
    APP_ENV=production `
    PORT=8000 `
    REQUIRE_DATABASE_ON_STARTUP=false `
    MSSQL_CONN_STR=secretref:mssql-conn-str `
    JWT_SECRET_KEY=secretref:jwt-secret-key

az containerapp identity assign `
  --resource-group $RG `
  --name $APP `
  --system-assigned

$ACR_ID=$(az acr show --resource-group $RG --name $ACR --query id --output tsv)
$PRINCIPAL_ID=$(az containerapp identity show --resource-group $RG --name $APP --query principalId --output tsv)

az role assignment create `
  --assignee-object-id $PRINCIPAL_ID `
  --assignee-principal-type ServicePrincipal `
  --role AcrPull `
  --scope $ACR_ID

az containerapp registry set `
  --resource-group $RG `
  --name $APP `
  --server "$ACR.azurecr.io" `
  --identity system

$APPREG="zapieapp-github-actions"
$APP_ID=$(az ad app create --display-name $APPREG --query appId --output tsv)
az ad sp create --id $APP_ID

$SUBSCRIPTION_ID=$(az account show --query id --output tsv)
$TENANT_ID=$(az account show --query tenantId --output tsv)

az role assignment create `
  --assignee $APP_ID `
  --role Contributor `
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG"

az role assignment create `
  --assignee $APP_ID `
  --role AcrPush `
  --scope $ACR_ID

@{
  name = "github-main"
  issuer = "https://token.actions.githubusercontent.com"
  subject = "repo:$REPO`:ref:refs/heads/main"
  audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json | Out-File federated-credential.json -Encoding utf8

az ad app federated-credential create --id $APP_ID --parameters federated-credential.json

Write-Output "Set GitHub secret AZURE_CLIENT_ID=$APP_ID"
Write-Output "Set GitHub secret AZURE_TENANT_ID=$TENANT_ID"
Write-Output "Set GitHub secret AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
```

Adres API:

```text
https://<container-app-fqdn>
```

Healthcheck:

```text
https://<container-app-fqdn>/health
https://<container-app-fqdn>/health/db
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
flutter run --dart-define=API_BASE_URL=https://<container-app-fqdn>
```

Domyslnie aplikacja Flutter nadal uzywa `http://127.0.0.1:8000`, jesli nie podasz
`API_BASE_URL`.

## Release flow

1. Commituj zmiany do `main`.
2. GitHub Actions odpala walidacje backendu.
3. Workflow buduje obraz z `my_fastapi_project/Dockerfile`.
4. Obraz trafia do ACR z tagiem commit SHA.
5. Azure Container Apps tworzy nowa rewizje i smoke test sprawdza `/health`.
