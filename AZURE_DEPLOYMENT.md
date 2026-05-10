# Azure Deployment Runbook

## Aktualny backend

Publiczny adres API:

```text
https://zapieapp-api-dev-alpha.gentlewave-09e4c100.westeurope.azurecontainerapps.io
```

Healthchecki:

```text
https://zapieapp-api-dev-alpha.gentlewave-09e4c100.westeurope.azurecontainerapps.io/health
https://zapieapp-api-dev-alpha.gentlewave-09e4c100.westeurope.azurecontainerapps.io/health/db
```

Na moment spisania oba endpointy odpowiadaja poprawnie, a `/health/db`
potwierdza polaczenie z Azure SQL.

## Zasoby Azure

```text
Resource group: rg-zapieapp-dev
Region: westeurope
Azure Container Registry: zapieappapidevalpha
ACR login server: zapieappapidevalpha.azurecr.io
Container Apps environment: zapieapp-api-env
Container App: zapieapp-api-dev-alpha
```

Backend dziala jako Azure Container App. Obraz backendu jest budowany z:

```text
my_fastapi_project/Dockerfile
```

Dockerfile instaluje `msodbcsql18`, wiec zaleznosc ODBC dla SQL Server jest
kontrolowana w obrazie kontenera, a nie przez host Azure.

## Sekrety

Sekrety runtime sa ustawione w Azure Container App, nie w repo:

```text
mssql-conn-str
jwt-secret-key
```

Nie commitujemy prawdziwych connection stringow, hasel SQL, tokenow ani plikow
providerow social auth.

## Obecny model deployu

Na ten moment deploy backendu jest manualny z Azure Cloud Shell. Powod: konto ma
role `Contributor`, ale nie ma `Owner` ani `User Access Administrator`, wiec nie
moze nadawac rol IAM (`roleAssignments/write`) dla pelnego GitHub Actions OIDC.

ACR admin credentials zostaly wlaczone jako obejscie dla pullowania obrazu przez
Container App.

## Manualny deploy patcha backendu

Po zmergowaniu zmian do `main`:

```powershell
$RG="rg-zapieapp-dev"
$ACR="zapieappapidevalpha"
$APP="zapieapp-api-dev-alpha"

cd ~/ZapieAppka
git pull origin main

cd ~/ZapieAppka/my_fastapi_project
$TAG="manual-$(Get-Date -Format 'yyyyMMddHHmmss')"

az acr build `
  --registry $ACR `
  --image "zapieapp-api:$TAG" `
  .

az containerapp update `
  --resource-group $RG `
  --name $APP `
  --image "$ACR.azurecr.io/zapieapp-api:$TAG"

$FQDN=$(az containerapp show --resource-group $RG --name $APP --query properties.configuration.ingress.fqdn --output tsv)
curl "https://$FQDN/health"
curl "https://$FQDN/health/db"
```

## Flutter lokalnie z backendem Azure

Desktop Windows:

```powershell
cd C:\FFApi\zapieapp
flutter run -d windows --dart-define=API_BASE_URL=https://zapieapp-api-dev-alpha.gentlewave-09e4c100.westeurope.azurecontainerapps.io
```

Chrome:

```powershell
cd C:\FFApi\zapieapp
flutter run -d chrome --dart-define=API_BASE_URL=https://zapieapp-api-dev-alpha.gentlewave-09e4c100.westeurope.azurecontainerapps.io
```

Telefon przez USB:

```powershell
cd C:\FFApi\zapieapp
flutter run --dart-define=API_BASE_URL=https://zapieapp-api-dev-alpha.gentlewave-09e4c100.westeurope.azurecontainerapps.io
```

## GitHub Actions

Workflow jest w repo:

```text
.github/workflows/deploy-api-containerapp.yml
```

Jest przygotowany pod docelowe CI/CD z Azure Container Apps. Do pelnej
automatyzacji trzeba nadac app registration `zapieapp-github-actions` role:

```text
Contributor na rg-zapieapp-dev
AcrPush na zapieappapidevalpha
```

Nadanie tych rol wymaga uprawnien `Owner` albo `User Access Administrator`.
