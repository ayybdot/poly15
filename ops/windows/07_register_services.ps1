#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Step 07: Register Windows Services
.DESCRIPTION
    Registers PolyTrader services using NSSM.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\_lib.ps1"

if (-not (Test-Marker -Name "ui_ok")) {
    Write-Host "ERROR: Dashboard not set up. Run 06_setup_dashboard.ps1 first." -ForegroundColor Red
    exit 1
}

$logFile = Start-Log -StepNumber "07" -StepName "register_services"
Write-StepHeader "07" "REGISTER SERVICES"

$root = Get-PolyTraderRoot
$nssmPath = Join-Path $root "tools\nssm.exe"
$venvPython = Join-Path $root "venv\Scripts\python.exe"
$backendDir = Join-Path $root "backend"
$dashboardDir = Join-Path $root "dashboard"
$logsDir = Join-Path $root "logs"

try {
    Write-Section "Verify Prerequisites"
    
    if (-not (Test-Path $nssmPath)) {
        throw "NSSM not found at $nssmPath"
    }
    Write-Ok "NSSM found"
    
    if (-not (Test-IsAdmin)) {
        throw "Administrator privileges required for service registration"
    }
    Write-Ok "Running as administrator"
    
    # Ensure logs directory exists
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    }
    
    Write-Section "Register PolyTrader-API Service"
    
    $apiServiceName = "PolyTrader-API"
    
    # Remove existing service if present
    $existingService = Get-Service -Name $apiServiceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Status "Removing existing $apiServiceName service..." -Icon "Arrow"
        & $nssmPath stop $apiServiceName 2>$null
        & $nssmPath remove $apiServiceName confirm 2>$null
        Start-Sleep -Seconds 2
    }
    
    Write-Status "Installing $apiServiceName..." -Icon "Arrow"
    
    $uvicornPath = Join-Path $root "venv\Scripts\uvicorn.exe"
    $apiArgs = "app.main:app --host 0.0.0.0 --port 8000"
    
    & $nssmPath install $apiServiceName $uvicornPath $apiArgs
    & $nssmPath set $apiServiceName AppDirectory $backendDir
    & $nssmPath set $apiServiceName AppEnvironmentExtra "PYTHONPATH=$backendDir"
    & $nssmPath set $apiServiceName Description "PolyTrader FastAPI Backend"
    & $nssmPath set $apiServiceName AppStdout (Join-Path $logsDir "api_stdout.log")
    & $nssmPath set $apiServiceName AppStderr (Join-Path $logsDir "api_stderr.log")
    & $nssmPath set $apiServiceName AppStdoutCreationDisposition 4
    & $nssmPath set $apiServiceName AppStderrCreationDisposition 4
    & $nssmPath set $apiServiceName AppRestartDelay 5000
    & $nssmPath set $apiServiceName Start SERVICE_AUTO_START
    
    Write-Ok "$apiServiceName registered"
    
    Write-Section "Register PolyTrader-Worker Service"
    
    $workerServiceName = "PolyTrader-Worker"
    
    # Remove existing service if present
    $existingService = Get-Service -Name $workerServiceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Status "Removing existing $workerServiceName service..." -Icon "Arrow"
        & $nssmPath stop $workerServiceName 2>$null
        & $nssmPath remove $workerServiceName confirm 2>$null
        Start-Sleep -Seconds 2
    }
    
    Write-Status "Installing $workerServiceName..." -Icon "Arrow"
    
    $workerArgs = "-m app.workers.trading_worker"
    
    & $nssmPath install $workerServiceName $venvPython $workerArgs
    & $nssmPath set $workerServiceName AppDirectory $backendDir
    & $nssmPath set $workerServiceName AppEnvironmentExtra "PYTHONPATH=$backendDir"
    & $nssmPath set $workerServiceName Description "PolyTrader Trading Worker"
    & $nssmPath set $workerServiceName AppStdout (Join-Path $logsDir "worker_stdout.log")
    & $nssmPath set $workerServiceName AppStderr (Join-Path $logsDir "worker_stderr.log")
    & $nssmPath set $workerServiceName AppStdoutCreationDisposition 4
    & $nssmPath set $workerServiceName AppStderrCreationDisposition 4
    & $nssmPath set $workerServiceName AppRestartDelay 10000
    & $nssmPath set $workerServiceName Start SERVICE_DEMAND_START  # Manual start - requires credentials
    
    Write-Ok "$workerServiceName registered"
    
    Write-Section "Register PolyTrader-UI Service"
    
    $uiServiceName = "PolyTrader-UI"
    
    # Remove existing service if present
    $existingService = Get-Service -Name $uiServiceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Status "Removing existing $uiServiceName service..." -Icon "Arrow"
        & $nssmPath stop $uiServiceName 2>$null
        & $nssmPath remove $uiServiceName confirm 2>$null
        Start-Sleep -Seconds 2
    }
    
    Write-Status "Installing $uiServiceName..." -Icon "Arrow"
    
    $npmPath = (Get-Command npm -ErrorAction SilentlyContinue).Source
    if (-not $npmPath) {
        $npmPath = "C:\Program Files\nodejs\npm.cmd"
    }
    
    & $nssmPath install $uiServiceName $npmPath "run start"
    & $nssmPath set $uiServiceName AppDirectory $dashboardDir
    & $nssmPath set $uiServiceName Description "PolyTrader Next.js Dashboard"
    & $nssmPath set $uiServiceName AppStdout (Join-Path $logsDir "ui_stdout.log")
    & $nssmPath set $uiServiceName AppStderr (Join-Path $logsDir "ui_stderr.log")
    & $nssmPath set $uiServiceName AppStdoutCreationDisposition 4
    & $nssmPath set $uiServiceName AppStderrCreationDisposition 4
    & $nssmPath set $uiServiceName AppRestartDelay 5000
    & $nssmPath set $uiServiceName Start SERVICE_AUTO_START
    
    Write-Ok "$uiServiceName registered"
    
    Write-Section "Verify Services"
    
    $services = @($apiServiceName, $workerServiceName, $uiServiceName)
    $allRegistered = $true
    
    foreach ($svcName in $services) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            Write-Ok "$svcName registered (Status: $($svc.Status))"
        }
        else {
            Write-Fail "$svcName not found"
            $allRegistered = $false
        }
    }
    
    Write-Section "Create Service Management Scripts"
    
    # Start all services
    $startAllScript = @"
@echo off
echo Starting PolyTrader services...
net start PolyTrader-API
timeout /t 5
net start PolyTrader-UI
echo.
echo API and UI services started.
echo Worker service requires manual start after configuring credentials:
echo   net start PolyTrader-Worker
pause
"@
    Set-Content -Path (Join-Path $root "start_services.bat") -Value $startAllScript -Encoding ASCII
    
    # Stop all services
    $stopAllScript = @"
@echo off
echo Stopping PolyTrader services...
net stop PolyTrader-Worker 2>nul
net stop PolyTrader-UI
net stop PolyTrader-API
echo Services stopped.
pause
"@
    Set-Content -Path (Join-Path $root "stop_services.bat") -Value $stopAllScript -Encoding ASCII
    
    # Status check
    $statusScript = @"
@echo off
echo PolyTrader Service Status:
echo ==========================
sc query PolyTrader-API | find "STATE"
sc query PolyTrader-Worker | find "STATE"
sc query PolyTrader-UI | find "STATE"
echo.
pause
"@
    Set-Content -Path (Join-Path $root "service_status.bat") -Value $statusScript -Encoding ASCII
    
    Write-Ok "Service management scripts created"
    
    if (-not $allRegistered) {
        throw "Not all services were registered"
    }
    
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Cyan
    Write-Ok "Services registered successfully!"
    Set-Marker -Name "services_ok"
    
    Write-Host ""
    Write-Host "  Services registered:" -ForegroundColor Gray
    Write-Host "    - PolyTrader-API   (Auto-start)" -ForegroundColor Gray
    Write-Host "    - PolyTrader-Worker (Manual - configure credentials first)" -ForegroundColor Gray
    Write-Host "    - PolyTrader-UI    (Auto-start)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  To start services: $root\start_services.bat" -ForegroundColor Gray
    Write-Host "  To stop services:  $root\stop_services.bat" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Next step: Run 08_final_verification.ps1" -ForegroundColor Green
    Write-Host ""
    
    Stop-Log -Success $true
}
catch {
    Write-Fail "Service registration failed: $_"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Stop-Log -Success $false
    Write-Host "  Check log file: $logFile" -ForegroundColor Red
    exit 1
}
