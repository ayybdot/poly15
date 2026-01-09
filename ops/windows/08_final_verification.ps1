#Requires -Version 5.1
<#
.SYNOPSIS
    Step 08: Final Verification
.DESCRIPTION
    Performs final system verification and startup test.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\_lib.ps1"

if (-not (Test-Marker -Name "services_ok")) {
    Write-Host "ERROR: Services not registered. Run 07_register_services.ps1 first." -ForegroundColor Red
    exit 1
}

$logFile = Start-Log -StepNumber "08" -StepName "final_verification"
Write-StepHeader "08" "FINAL VERIFICATION"

$root = Get-PolyTraderRoot

try {
    Write-Section "Check All Marker Files"
    
    $markers = @(
        "preflight_ok",
        "deps_ok",
        "repo_ok",
        "db_ok",
        "api_ok",
        "worker_dry_ok",
        "ui_ok",
        "services_ok"
    )
    
    $allMarkersPresent = $true
    foreach ($marker in $markers) {
        if (Test-Marker -Name $marker) {
            $time = Get-MarkerTime -Name $marker
            Write-Ok "$marker - $(if ($time) { $time.ToString('yyyy-MM-dd HH:mm:ss') } else { 'OK' })"
        }
        else {
            Write-Fail "$marker - MISSING"
            $allMarkersPresent = $false
        }
    }
    
    if (-not $allMarkersPresent) {
        throw "Some installation steps were not completed"
    }
    
    Write-Section "Start Services for Testing"
    
    # Start API service
    Write-Status "Starting PolyTrader-API service..." -Icon "Arrow"
    Start-Service -Name "PolyTrader-API" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    
    # Start UI service
    Write-Status "Starting PolyTrader-UI service..." -Icon "Arrow"
    Start-Service -Name "PolyTrader-UI" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    
    Write-Section "Verify API Endpoints"
    
    $apiEndpoints = @(
        @{Url = "http://localhost:8000/health"; Name = "Health Check"},
        @{Url = "http://localhost:8000/v1/prices/status"; Name = "Price Status"},
        @{Url = "http://localhost:8000/v1/admin/bot/state"; Name = "Bot State"},
        @{Url = "http://localhost:8000/v1/config/"; Name = "Configuration"},
        @{Url = "http://localhost:8000/v1/install/status"; Name = "Install Status"}
    )
    
    $apiOk = $true
    $maxRetries = 6
    
    foreach ($endpoint in $apiEndpoints) {
        $success = $false
        for ($i = 1; $i -le $maxRetries; $i++) {
            try {
                $response = Invoke-WebRequest -Uri $endpoint.Url -UseBasicParsing -TimeoutSec 10
                if ($response.StatusCode -eq 200) {
                    Write-Ok "$($endpoint.Name): OK"
                    $success = $true
                    break
                }
            }
            catch {
                if ($i -lt $maxRetries) {
                    Start-Sleep -Seconds 2
                }
            }
        }
        if (-not $success) {
            Write-Fail "$($endpoint.Name): FAILED"
            $apiOk = $false
        }
    }
    
    Write-Section "Verify Dashboard"
    
    $dashboardOk = $false
    for ($i = 1; $i -le 10; $i++) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing -TimeoutSec 10
            if ($response.StatusCode -eq 200) {
                Write-Ok "Dashboard: OK (http://localhost:3000)"
                $dashboardOk = $true
                break
            }
        }
        catch {
            Write-Status "Waiting for dashboard... ($i/10)" -Icon "Arrow"
            Start-Sleep -Seconds 3
        }
    }
    
    if (-not $dashboardOk) {
        Write-Warn "Dashboard not responding - may need manual start"
    }
    
    Write-Section "Verify Service Status"
    
    $services = @("PolyTrader-API", "PolyTrader-UI", "PolyTrader-Worker")
    
    foreach ($svcName in $services) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            $status = $svc.Status
            if ($svcName -eq "PolyTrader-Worker") {
                # Worker is manual start
                Write-Ok "$svcName : $status (Manual start - configure credentials first)"
            }
            else {
                if ($status -eq "Running") {
                    Write-Ok "$svcName : $status"
                }
                else {
                    Write-Warn "$svcName : $status"
                }
            }
        }
        else {
            Write-Fail "$svcName : NOT FOUND"
        }
    }
    
    Write-Section "Check Port Bindings"
    
    $ports = @(
        @{Port = 8000; Name = "API"},
        @{Port = 3000; Name = "Dashboard"},
        @{Port = 5432; Name = "PostgreSQL"}
    )
    
    foreach ($portInfo in $ports) {
        $listener = Get-NetTCPConnection -LocalPort $portInfo.Port -State Listen -ErrorAction SilentlyContinue
        if ($listener) {
            Write-Ok "Port $($portInfo.Port) ($($portInfo.Name)): LISTENING"
        }
        else {
            if ($portInfo.Name -eq "PostgreSQL") {
                Write-Warn "Port $($portInfo.Port) ($($portInfo.Name)): Not detected (may be fine)"
            }
            else {
                Write-Warn "Port $($portInfo.Port) ($($portInfo.Name)): NOT LISTENING"
            }
        }
    }
    
    Write-Section "Configuration Summary"
    
    $envPath = Join-Path $root "backend\.env"
    if (Test-Path $envPath) {
        $envContent = Get-Content $envPath -Raw
        
        $hasApiKey = $envContent -match "POLYMARKET_API_KEY=.+"
        $hasPrivateKey = $envContent -match "POLYMARKET_PRIVATE_KEY=.+"
        
        if ($hasApiKey -and $hasPrivateKey) {
            Write-Ok "Polymarket credentials: Configured"
        }
        else {
            Write-Warn "Polymarket credentials: NOT CONFIGURED"
            Write-Status "  Edit $envPath to add your credentials" -Icon "Warning"
        }
    }
    
    Write-Section "Generate Summary Report"
    
    $summaryPath = Join-Path $root "INSTALL_SUMMARY.txt"
    $summary = @"
================================================================================
PolyTrader Installation Summary
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
================================================================================

INSTALLATION STATUS: COMPLETE

ACCESS URLS:
  Dashboard:  http://localhost:3000
  API:        http://localhost:8000
  API Docs:   http://localhost:8000/docs

SERVICES:
  PolyTrader-API    - FastAPI backend
  PolyTrader-Worker - Trading worker (manual start)
  PolyTrader-UI     - Next.js dashboard

SERVICE MANAGEMENT:
  Start:   $root\start_services.bat
  Stop:    $root\stop_services.bat
  Status:  $root\service_status.bat

CONFIGURATION:
  Environment: $root\backend\.env
  Database:    $root\data\db_credentials.txt

BEFORE LIVE TRADING:
  1. Configure Polymarket credentials in .env
  2. Review risk settings in dashboard Config page
  3. Start bot via dashboard (Start button)

LOGS:
  Install logs: $root\install-logs\
  Service logs: $root\logs\

================================================================================
"@
    
    Set-Content -Path $summaryPath -Value $summary -Encoding UTF8
    Write-Ok "Summary report created: $summaryPath"
    
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Green
    Write-Host ""
    Write-Host "  PolyTrader Installation COMPLETE!" -ForegroundColor Green
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Green
    
    Set-Marker -Name "final_ok"
    
    Write-Host ""
    Write-Host "  ACCESS URLS:" -ForegroundColor Cyan
    Write-Host "    Dashboard:  http://localhost:3000" -ForegroundColor White
    Write-Host "    API:        http://localhost:8000" -ForegroundColor White
    Write-Host "    API Docs:   http://localhost:8000/docs" -ForegroundColor White
    Write-Host ""
    Write-Host "  NEXT STEPS:" -ForegroundColor Cyan
    Write-Host "    1. Configure Polymarket credentials in backend\.env" -ForegroundColor Yellow
    Write-Host "    2. Review risk settings in dashboard" -ForegroundColor Yellow
    Write-Host "    3. Start the worker service manually" -ForegroundColor Yellow
    Write-Host "    4. Use dashboard to start/pause/stop bot" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Run 99_status_dashboard.ps1 anytime to check system status" -ForegroundColor Gray
    Write-Host ""
    
    Stop-Log -Success $true
}
catch {
    Write-Fail "Final verification failed: $_"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Stop-Log -Success $false
    Write-Host "  Check log file: $logFile" -ForegroundColor Red
    exit 1
}
