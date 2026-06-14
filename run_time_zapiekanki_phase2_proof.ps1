param(
    [string]$ApiBaseUrl = "https://zapieapp-api-dev-alpha.ambitiousstone-9e7294a6.polandcentral.azurecontainerapps.io",
    [string]$ExecutionLogPath = "C:\FFApi\TIME_ZAPIEKANKI_PHASE2_EXECUTION_LOG.md",
    [switch]$SkipBackendTests,
    [switch]$SkipFlutterTests,
    [switch]$SkipHealthChecks,
    [switch]$SkipApiSmoke,
    [switch]$StrictApiSmoke,
    [int]$ApiSmokeOverrideMinutes = -1,
    [string]$AdminSessionToken = "",
    [string]$AdminEmail = "",
    [switch]$LaunchChrome
)

$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$artifactRoot = Join-Path $repoRoot "artifacts\time_zapiekanki_phase2"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $artifactRoot $timestamp
$summaryPath = Join-Path $runDir "summary.txt"
$executionLogSnapshotPath = Join-Path $runDir "execution-log.snapshot.md"
$backendVenvPython = Join-Path $repoRoot "my_fastapi_project\.venv\Scripts\python.exe"
$pythonCommand = if (Test-Path $backendVenvPython) { $backendVenvPython } else { "python" }

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$summary = [System.Collections.Generic.List[string]]::new()
$summary.Add("TIME_ZAPIEKANKI Phase 2 proof run")
$summary.Add("timestamp=$timestamp")
$summary.Add("api_base_url=$ApiBaseUrl")
$summary.Add("")

function Write-StepHeader {
    param(
        [string]$Title
    )

    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Add-Summary {
    param(
        [string]$Line
    )

    $summary.Add($Line)
}

function Set-FileContentWithRegex {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Replacement
    )

    if (-not (Test-Path $Path)) {
        return
    }

    $content = Get-Content -Path $Path -Raw
    $updated = [regex]::Replace($content, $Pattern, $Replacement, 1)
    Set-Content -Path $Path -Value $updated
}

function Initialize-ExecutionLog {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return
    }

    Set-FileContentWithRegex -Path $Path -Pattern '(?m)^- Data:.*$' -Replacement "- Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
    Set-FileContentWithRegex -Path $Path -Pattern '(?m)^- Srodowisko backend:.*$' -Replacement "- Srodowisko backend: $ApiBaseUrl"
    Set-FileContentWithRegex -Path $Path -Pattern '(?m)^- Srodowisko frontend:.*$' -Replacement "- Srodowisko frontend: Flutter web / Chrome"
    Set-FileContentWithRegex -Path $Path -Pattern '(?m)^- Wersja branch/commit:.*$' -Replacement "- Wersja branch/commit: local workspace"
    Set-FileContentWithRegex -Path $Path -Pattern '(?m)^- Override kuchni na start:.*$' -Replacement "- Override kuchni na start: do sprawdzenia runtime"
}

function Update-ExecutionLogBackendTests {
    param(
        [string]$Path,
        [string]$Status,
        [string]$Start,
        [string]$End,
        [string]$Note
    )

    $replacement = @"
`$1- Status: ``$Status``
- Start: $Start
- Koniec: $End

### Notatki

- $Note

### Failures

- 
"@
    Set-FileContentWithRegex -Path $Path -Pattern '(?s)(## 1\. Backend tests.*?### Wynik\r?\n\r?\n)- Status: `.*?`\r?\n- Start:.*?\r?\n- Koniec:.*?\r?\n\r?\n### Notatki\r?\n\r?\n- .*?\r?\n\r?\n### Failures\r?\n\r?\n- .*?(?=\r?\n---)' -Replacement $replacement
}

function Update-ExecutionLogFrontendTests {
    param(
        [string]$Path,
        [string]$Status,
        [string]$Start,
        [string]$End,
        [string]$Note
    )

    $replacement = @"
`$1- Status: ``$Status``
- Start: $Start
- Koniec: $End

### Notatki

- $Note

### Failures

- 
"@
    Set-FileContentWithRegex -Path $Path -Pattern '(?s)(## 2\. Frontend tests.*?### Wynik\r?\n\r?\n)- Status: `.*?`\r?\n- Start:.*?\r?\n- Koniec:.*?\r?\n\r?\n### Notatki\r?\n\r?\n- .*?\r?\n\r?\n### Failures\r?\n\r?\n- .*?(?=\r?\n---)' -Replacement $replacement
}

function Update-ExecutionLogHealth {
    param(
        [string]$Path,
        [string]$HealthStatus,
        [string]$HealthDbStatus,
        [string]$Note
    )

    $replacement = @"
`$1- `/health`: ``$HealthStatus``
- `/health/db`: ``$HealthDbStatus``

### Notatki

- $Note
"@
    Set-FileContentWithRegex -Path $Path -Pattern '(?s)(## 3\. Azure health.*?### Wynik\r?\n\r?\n)- `/health`: `.*?`\r?\n- `/health/db`: `.*?`\r?\n\r?\n### Notatki\r?\n\r?\n- .*?(?=\r?\n---)' -Replacement $replacement
}

function Set-ExecutionLogNextStep {
    param(
        [string]$Path,
        [string]$NextStep
    )

    Set-FileContentWithRegex -Path $Path -Pattern '(?m)^- Kolejny ruch.*$' -Replacement "- Kolejny ruch"
    Set-FileContentWithRegex -Path $Path -Pattern '(?s)(### Kolejny ruch\r?\n\r?\n)- .*?(?=\r?\n---)' -Replacement "`$1- $NextStep"
}

function Update-ExecutionLogApiScenario {
    param(
        [string]$Path,
        [string]$ScenarioRegexLabel,
        [string]$Input,
        [string]$Expected,
        [string]$Actual,
        [string]$Status,
        [string]$Note
    )

    $replacement = @"
`$1- Input: $Input
- Expected: $Expected
- Actual: $Actual
- Status: ``$Status``
- Notes: $Note
"@
    Set-FileContentWithRegex `
        -Path $Path `
        -Pattern "(?s)(### $ScenarioRegexLabel\r?\n\r?\n)- Input:.*?\r?\n- Expected:.*?\r?\n- Actual:.*?\r?\n- Status: `.*?`\r?\n- Notes:.*?(?=\r?\n\r?\n###|\r?\n---)" `
        -Replacement $replacement
}

function Update-ExecutionLogApiSmokeFromSummary {
    param(
        [string]$Path,
        [string]$SummaryJsonPath
    )

    if (-not (Test-Path $Path) -or -not (Test-Path $SummaryJsonPath)) {
        return
    }

    $summaryJson = Get-Content -Path $SummaryJsonPath -Raw | ConvertFrom-Json
    $scenarioMap = @{
        "one_large_clean_queue" = 'Scenario 4\.1 - 1 duza przy pustej kolejce'
        "four_large_clean_queue" = 'Scenario 4\.2 - 4 duze'
        "seven_large_clean_queue" = 'Scenario 4\.3 - 7 duzych'
        "ten_large_clean_queue" = 'Scenario 4\.4 - 10 duzych'
        "fourteen_large_clean_queue" = 'Scenario 4\.5 - 14\+ duzych'
        "vac_and_25cm_non_kitchen" = 'Scenario 4\.6 - tylko `VAC` lub `25cm`'
    }

    foreach ($result in $summaryJson.results) {
        $scenarioName = [string]$result.name
        if ($scenarioName.StartsWith("override_")) {
            $label = 'Scenario 4\.7 - override `\+10`'
        }
        elseif ($scenarioMap.ContainsKey($scenarioName)) {
            $label = $scenarioMap[$scenarioName]
        }
        else {
            continue
        }

        $status = if ($null -eq $result.passed) { "INFO" } elseif ([bool]$result.passed) { "PASS" } else { "FAIL" }
        $expected = "eta=$($result.expected_eta_minutes); kitchen_eta=$($result.expected_kitchen_eta_minutes); batch=$($result.expected_kitchen_batch_index); slots=$($result.expected_kitchen_slots_used_by_order)"
        $actual = "eta=$($result.actual_eta_minutes); kitchen_eta=$($result.actual_kitchen_eta_minutes); batch=$($result.actual_kitchen_batch_index); slots=$($result.actual_kitchen_slots_used_by_order)"
        $input = $scenarioName
        $note = [string]$result.note

        Update-ExecutionLogApiScenario `
            -Path $Path `
            -ScenarioRegexLabel $label `
            -Input $input `
            -Expected $expected `
            -Actual $actual `
            -Status $status `
            -Note $note
    }
}

function Invoke-NativeLoggedStep {
    param(
        [string]$Title,
        [string]$WorkingDirectory,
        [string]$LogFileName,
        [scriptblock]$Command,
        [scriptblock]$OnSuccess,
        [scriptblock]$OnFailure
    )

    Write-StepHeader $Title
    $logPath = Join-Path $runDir $LogFileName
    $startedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Push-Location $WorkingDirectory
    try {
        & $Command *>&1 | Tee-Object -FilePath $logPath
        if ($LASTEXITCODE -ne 0) {
            throw "$Title failed with exit code $LASTEXITCODE"
        }
        Add-Summary("$Title=PASS log=$logPath")
        if ($OnSuccess) {
            & $OnSuccess $startedAt (Get-Date -Format "yyyy-MM-dd HH:mm:ss") $logPath
        }
    }
    catch {
        Add-Summary("$Title=FAIL log=$logPath")
        if ($OnFailure) {
            & $OnFailure $startedAt (Get-Date -Format "yyyy-MM-dd HH:mm:ss") $logPath $_
        }
        throw
    }
    finally {
        Pop-Location
    }
}

function Invoke-WebHealthCheck {
    param(
        [string]$Title,
        [string]$Url,
        [string]$LogFileName
    )

    Write-StepHeader $Title
    $logPath = Join-Path $runDir $LogFileName

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
        $body = $response.Content
        @(
            "status_code=$($response.StatusCode)"
            "url=$Url"
            "body=$body"
        ) | Tee-Object -FilePath $logPath
        if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
            throw "$Title failed with HTTP $($response.StatusCode)"
        }
        Add-Summary("$Title=PASS log=$logPath")
        return @{
            Status = "PASS"
            LogPath = $logPath
        }
    }
    catch {
        $statusCode = $null
        $body = $null
        $response = $_.Exception.Response
        if ($response) {
            try {
                $statusCode = [int]$response.StatusCode
            }
            catch {
                $statusCode = $null
            }

            try {
                $stream = $response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $body = $reader.ReadToEnd()
                    $reader.Dispose()
                    $stream.Dispose()
                }
            }
            catch {
                $body = $null
            }
        }

        @(
            "status_code=$statusCode"
            "url=$Url"
            "body=$body"
            "error=$($_.Exception.Message)"
        ) | Tee-Object -FilePath $logPath
        Add-Summary("$Title=FAIL log=$logPath")
        throw
    }
}

try {
    Initialize-ExecutionLog -Path $ExecutionLogPath

    if (-not $SkipBackendTests) {
        Invoke-NativeLoggedStep `
            -Title "backend-tests" `
            -WorkingDirectory (Join-Path $repoRoot "my_fastapi_project") `
            -LogFileName "backend-tests.log" `
            -Command { & $pythonCommand tests\run_time_zapiekanki_phase2_suite.py } `
            -OnSuccess {
                param($startedAt, $endedAt, $logPath)
                Update-ExecutionLogBackendTests `
                    -Path $ExecutionLogPath `
                    -Status "PASS" `
                    -Start $startedAt `
                    -End $endedAt `
                    -Note "Runner przeszedl. Log: $logPath"
            } `
            -OnFailure {
                param($startedAt, $endedAt, $logPath, $errorRecord)
                Update-ExecutionLogBackendTests `
                    -Path $ExecutionLogPath `
                    -Status "FAIL" `
                    -Start $startedAt `
                    -End $endedAt `
                    -Note "Runner fail. Log: $logPath. Error: $($errorRecord.Exception.Message)"
            }
    }
    else {
        Add-Summary("backend-tests=SKIPPED")
        Update-ExecutionLogBackendTests `
            -Path $ExecutionLogPath `
            -Status "SKIPPED" `
            -Start "-" `
            -End "-" `
            -Note "Krok pominiety przez parametr -SkipBackendTests"
    }

    if (-not $SkipFlutterTests) {
        Invoke-NativeLoggedStep `
            -Title "flutter-tests" `
            -WorkingDirectory (Join-Path $repoRoot "zapieapp") `
            -LogFileName "flutter-tests.log" `
            -Command { flutter test } `
            -OnSuccess {
                param($startedAt, $endedAt, $logPath)
                Update-ExecutionLogFrontendTests `
                    -Path $ExecutionLogPath `
                    -Status "PASS" `
                    -Start $startedAt `
                    -End $endedAt `
                    -Note "Flutter test przeszedl. Log: $logPath"
            } `
            -OnFailure {
                param($startedAt, $endedAt, $logPath, $errorRecord)
                Update-ExecutionLogFrontendTests `
                    -Path $ExecutionLogPath `
                    -Status "FAIL" `
                    -Start $startedAt `
                    -End $endedAt `
                    -Note "Flutter test fail. Log: $logPath. Error: $($errorRecord.Exception.Message)"
            }
    }
    else {
        Add-Summary("flutter-tests=SKIPPED")
        Update-ExecutionLogFrontendTests `
            -Path $ExecutionLogPath `
            -Status "SKIPPED" `
            -Start "-" `
            -End "-" `
            -Note "Krok pominiety przez parametr -SkipFlutterTests"
    }

    if (-not $SkipHealthChecks) {
        $health = Invoke-WebHealthCheck `
            -Title "azure-health" `
            -Url "$ApiBaseUrl/health" `
            -LogFileName "azure-health.log"

        $healthDb = Invoke-WebHealthCheck `
            -Title "azure-health-db" `
            -Url "$ApiBaseUrl/health/db" `
            -LogFileName "azure-health-db.log"

        Update-ExecutionLogHealth `
            -Path $ExecutionLogPath `
            -HealthStatus $health.Status `
            -HealthDbStatus $healthDb.Status `
            -Note "Healthchecki przeszly. Logi: $($health.LogPath), $($healthDb.LogPath)"
    }
    else {
        Add-Summary("azure-health=SKIPPED")
        Add-Summary("azure-health-db=SKIPPED")
        Update-ExecutionLogHealth `
            -Path $ExecutionLogPath `
            -HealthStatus "SKIPPED" `
            -HealthDbStatus "SKIPPED" `
            -Note "Krok pominiety przez parametr -SkipHealthChecks"
    }

    $apiSmokeSummaryPath = Join-Path $runDir "api-smoke-summary.json"
    if (-not $SkipApiSmoke) {
        $apiSmokeArgs = @(
            ".\run_time_zapiekanki_phase2_api_smoke.py",
            "--api-base-url", $ApiBaseUrl,
            "--output-path", $apiSmokeSummaryPath
        )
        if ($StrictApiSmoke) {
            $apiSmokeArgs += "--strict-clean-queue"
        }
        if ($ApiSmokeOverrideMinutes -ge 0) {
            $apiSmokeArgs += "--override-minutes"
            $apiSmokeArgs += "$ApiSmokeOverrideMinutes"
        }
        if ($AdminSessionToken.Trim()) {
            $apiSmokeArgs += "--admin-session-token"
            $apiSmokeArgs += $AdminSessionToken
        }
        if ($AdminEmail.Trim()) {
            $apiSmokeArgs += "--admin-email"
            $apiSmokeArgs += $AdminEmail
        }

        Invoke-NativeLoggedStep `
            -Title "api-preview-smoke" `
            -WorkingDirectory $repoRoot `
            -LogFileName "api-preview-smoke.log" `
            -Command { & $pythonCommand @apiSmokeArgs } `
            -OnSuccess {
                param($startedAt, $endedAt, $logPath)
                Update-ExecutionLogApiSmokeFromSummary `
                    -Path $ExecutionLogPath `
                    -SummaryJsonPath $apiSmokeSummaryPath
            } `
            -OnFailure {
                param($startedAt, $endedAt, $logPath, $errorRecord)
                Update-ExecutionLogApiSmokeFromSummary `
                    -Path $ExecutionLogPath `
                    -SummaryJsonPath $apiSmokeSummaryPath
            }
    }
    else {
        Add-Summary("api-preview-smoke=SKIPPED")
    }

    $chromeCommand = @(
        "cd C:\FFApi\zapieapp",
        "flutter run -d chrome --web-hostname 127.0.0.1 --web-port 3001 --dart-define API_BASE_URL=$ApiBaseUrl"
    )

    Add-Summary("chrome-smoke-entry=READY")
    Add-Summary("execution-log-target=$ExecutionLogPath")

    Write-StepHeader "chrome-smoke-entrypoint"
    $chromeCommand | Tee-Object -FilePath (Join-Path $runDir "chrome-smoke-command.txt")

    if ($LaunchChrome) {
        Push-Location (Join-Path $repoRoot "zapieapp")
        try {
            flutter run -d chrome --web-hostname 127.0.0.1 --web-port 3001 --dart-define "API_BASE_URL=$ApiBaseUrl"
        }
        finally {
            Pop-Location
        }
    }

    Add-Summary("")
    Add-Summary("next_step=uzupelnij TIME_ZAPIEKANKI_PHASE2_EXECUTION_LOG.md wynikami smoke")
    Set-ExecutionLogNextStep `
        -Path $ExecutionLogPath `
        -NextStep "Uruchom smoke na Chrome, a potem uzupelnij sekcje 4-9 na podstawie logow z $runDir"
}
finally {
    $summary | Set-Content -Path $summaryPath
    if (Test-Path $ExecutionLogPath) {
        Copy-Item -Path $ExecutionLogPath -Destination $executionLogSnapshotPath -Force
    }
    Write-Host ""
    Write-Host "Summary saved to $summaryPath" -ForegroundColor Green
}
