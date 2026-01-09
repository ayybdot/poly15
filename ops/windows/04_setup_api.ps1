#Requires -Version 5.1
<#
.SYNOPSIS
    Step 04: Setup API
.DESCRIPTION
    Configures and tests the FastAPI backend.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\_lib.ps1"

if (-not (Test-Marker -Name "db_ok")) {
    Write-Host "ERROR: Database not set up. Run 03_setup_database.ps1 first." -ForegroundColor Red
    exit 1
}

$logFile = Start-Log -StepNumber "04" -StepName "setup_api"
Write-StepHeader "04" "SETUP API"

$root = Get-PolyTraderRoot
$backendDir = Join-Path $root "backend"
$venvPython = Join-Path $root "venv\Scripts\python.exe"

try {
    Write-Section "Verify Backend Structure"
    
    $requiredFiles = @(
        "app\main.py",
        "app\core\config.py",
        "app\db\database.py",
        "app\api\routes\health.py",
        "requirements.txt",
        ".env"
    )
    
    foreach ($file in $requiredFiles) {
        $path = Join-Path $backendDir $file
        if (Test-Path $path) {
            Write-Ok "Found: $file"
        }
        else {
            Write-Fail "Missing: $file"
            throw "Required file missing: $file"
        }
    }
    
    Write-Section "Verify Python Environment"
    
    if (-not (Test-Path $venvPython)) {
        throw "Python virtual environment not found at $venvPython"
    }
    Write-Ok "Virtual environment found"
    
    # Check key imports
    Write-Status "Checking Python imports..." -Icon "Arrow"
    
    $checkScript = @"
import sys
sys.path.insert(0, r'$backendDir')
try:
    from fastapi import FastAPI
    from sqlalchemy import create_engine
    import httpx
    import structlog
    print('OK')
except ImportError as e:
    print(f'FAIL: {e}')
    sys.exit(1)
"@
    
    $result = & $venvPython -c $checkScript 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "All Python imports successful"
    }
    else {
        Write-Fail "Python import check failed: $result"
        throw "Import check failed"
    }
    
    Write-Section "Test API Startup"
    
    # Check if port is free
    $portInUse = Get-NetTCPConnection -LocalPort 8000 -ErrorAction SilentlyContinue
    if ($portInUse) {
        Write-Warn "Port 8000 is in use - will attempt to use it if it's our API"
    }
    
    # Start API in background for testing
    Write-Status "Starting API for verification..." -Icon "Arrow"
    
    $env:PYTHONPATH = $backendDir
    $apiProcess = Start-Process -FilePath $venvPython `
        -ArgumentList "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8000" `
        -WorkingDirectory $backendDir `
        -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $root "logs\api_test_stdout.log") `
        -RedirectStandardError (Join-Path $root "logs\api_test_stderr.log")
    
    Write-Status "Waiting for API to start (PID: $($apiProcess.Id))..." -Icon "Arrow"
    
    # Wait for API to be ready
    $maxWait = 30
    $waited = 0
    $apiReady = $false
    
    while ($waited -lt $maxWait) {
        Start-Sleep -Seconds 2
        $waited += 2
        
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:8000/health" -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -eq 200) {
                $apiReady = $true
                break
            }
        }
        catch {
            Write-Status "Waiting... ($waited/$maxWait seconds)" -Icon "Arrow"
        }
    }
    
    if ($apiReady) {
        Write-Ok "API started successfully"
        
        # Test endpoints
        Write-Section "Test API Endpoints"
        
        $endpoints = @(
            @{Path = "/health"; Name = "Health Check"},
            @{Path = "/v1/prices/status"; Name = "Price Status"},
            @{Path = "/v1/admin/bot/state"; Name = "Bot State"},
            @{Path = "/v1/config/"; Name = "Configuration"}
        )
        
        foreach ($endpoint in $endpoints) {
            try {
                $response = Invoke-WebRequest -Uri "http://127.0.0.1:8000$($endpoint.Path)" -UseBasicParsing -TimeoutSec 10
                if ($response.StatusCode -eq 200) {
                    Write-Ok "$($endpoint.Name): OK"
                }
                else {
                    Write-Warn "$($endpoint.Name): Status $($response.StatusCode)"
                }
            }
            catch {
                Write-Warn "$($endpoint.Name): $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Fail "API failed to start within $maxWait seconds"
        
        # Check error log
        $errorLog = Join-Path $root "logs\api_test_stderr.log"
        if (Test-Path $errorLog) {
            $errors = Get-Content $errorLog -Tail 20
            Write-Log "API stderr: $errors" -Level "ERROR"
        }
    }
    
    # Stop test API
    if ($apiProcess -and -not $apiProcess.HasExited) {
        Write-Status "Stopping test API process..." -Icon "Arrow"
        Stop-Process -Id $apiProcess.Id -Force -ErrorAction SilentlyContinue
    }
    
    if (-not $apiReady) {
        throw "API verification failed"
    }
    
    Write-Section "Create API Startup Script"
    
    $startScript = @"
@echo off
cd /d "$backendDir"
set PYTHONPATH=$backendDir
"$venvPython" -m uvicorn app.main:app --host 0.0.0.0 --port 8000
"@
    
    $startScriptPath = Join-Path $root "start_api.bat"
    Set-Content -Path $startScriptPath -Value $startScript -Encoding ASCII
    Write-Ok "Created start_api.bat"
    
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Cyan
    Write-Ok "API setup completed successfully!"
    Set-Marker -Name "api_ok"
    
    Write-Host ""
    Write-Host "  API can be started with: $startScriptPath" -ForegroundColor Gray
    Write-Host "  Or via service after step 07" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Next step: Run 05_setup_worker.ps1" -ForegroundColor Green
    Write-Host ""
    
    Stop-Log -Success $true
}
catch {
    Write-Fail "API setup failed: $_"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Stop-Log -Success $false
    
    # Cleanup
    if ($apiProcess -and -not $apiProcess.HasExited) {
        Stop-Process -Id $apiProcess.Id -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host "  Check log file: $logFile" -ForegroundColor Red
    exit 1
}
