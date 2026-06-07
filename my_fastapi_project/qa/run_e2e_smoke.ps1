#Requires -Version 5.1

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script = Join-Path $Root "run_smoke_order_flow.py"

if (-not $env:BASE_URL) {
    Write-Host "Missing BASE_URL env var. Example:"
    Write-Host "  `$env:BASE_URL='https://zapieapp-api-dev-alpha.ambitiousstone-9e7294a6.polandcentral.azurecontainerapps.io'"
    Write-Host "  `$env:EMPLOYEE_EMAIL='employee@zapieapp.pl'"
    Write-Host "  `$env:EMPLOYEE_PASSWORD='...'`n"
    exit 1
}

if (-not $env:EMPLOYEE_EMAIL -or -not $env:EMPLOYEE_PASSWORD) {
    Write-Host "Missing EMPLOYEE_EMAIL/EMPLOYEE_PASSWORD"
    exit 1
}

if (-not $env:DRIVER_EMAIL -or -not $env:DRIVER_PASSWORD) {
    Write-Host "Missing DRIVER_EMAIL/DRIVER_PASSWORD"
    exit 1
}

python $Script
exit $LASTEXITCODE
