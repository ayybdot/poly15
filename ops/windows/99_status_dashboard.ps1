#Requires -Version 5.1
<#
.SYNOPSIS
    PolyTrader Status Dashboard
.DESCRIPTION
    Read-only status check for all PolyTrader components.
.PARAMETER TailOnFailure
    Show last 50 lines of failing step's log
#>

param(
    [switch]$TailOnFailure
)

$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\_lib.ps1"

$root = Get-PolyTraderRoot

# Define all installation steps
$steps = @(
    @{Step = "00"; Name = "preflight_check"; Marker = "preflight_ok"; Desc = "Preflight Check"},
    @{Step = "01"; Name = "install_dependencies"; Marker = "deps_ok"; Desc = "Dependencies"},
    @{Step = "02"; Name = "setup_repo"; Marker = "repo_ok"; Desc = "Repository"},
    @{Step = "03"; Name = "setup_database"; Marker = "db_ok"; Desc = "Database"},
    @{Step = "04"; Name = "setup_api"; Marker = "api_ok"; Desc = "API"},
    @{Step = "05"; Name = "setup_worker"; Marker = "worker_dry_ok"; Desc = "Worker"},
    @{Step = "06"; Name = "setup_dashboard"; Marker = "ui_ok"; Desc = "Dashboard"},
    @{Step = "07"; Name = "register_services"; Marker = "services_ok"; Desc = "Services"},
    @{Step = "08"; Name = "final_verification"; Marker = "final_ok"; Desc = "Verification"}
)

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "  PolyTrader Status Dashboard" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# INSTALLATION STEPS
# ============================================================================

Write-Host "INSTALLATION STEPS" -ForegroundColor Yellow
Write-Host "-" * 70 -ForegroundColor Gray

$failedStep = $null
$nextStep = $null

Write-Host ("{0,-6} {1,-25} {2,-15} {3,-25}" -f "Step", "Description", "Status", "Last Updated") -ForegroundColor White

foreach ($step in $steps) {
    $markerExists = Test-Marker -Name $step.Marker
    $markerTime = Get-MarkerTime -Name $step.Marker
    
    $status = if ($markerExists) { "DONE" } else { "NOT DONE" }
    $timeStr = if ($markerTime) { $markerTime.ToString("yyyy-MM-dd HH:mm") } else { "-" }
    
    # Check for failure evidence
    if (-not $markerExists) {
        $latestLog = Get-LatestLog -StepPattern $step.Step
        if ($latestLog) {
            $content = Get-Content $latestLog -Tail 100 -ErrorAction SilentlyContinue
            if ($content -match "FAIL|ERROR") {
                $status = "LIKELY FAILED"
                if (-not $failedStep) { $failedStep = $step }
            }
        }
        if (-not $nextStep -and $status -ne "LIKELY FAILED") {
            $nextStep = $step
        }
    }
    
    $statusColor = switch ($status) {
        "DONE" { "Green" }
        "NOT DONE" { "Gray" }
        "LIKELY FAILED" { "Red" }
        default { "White" }
    }
    
    Write-Host ("{0,-6} {1,-25} " -f $step.Step, $step.Desc) -NoNewline
    Write-Host ("{0,-15} " -f $status) -ForegroundColor $statusColor -NoNewline
    Write-Host ("{0,-25}" -f $timeStr) -ForegroundColor Gray
}

Write-Host ""

# ============================================================================
# SERVICES
# ============================================================================

Write-Host "SERVICES" -ForegroundColor Yellow
Write-Host "-" * 70 -ForegroundColor Gray

$services = @("PolyTrader-API", "PolyTrader-Worker", "PolyTrader-UI")

foreach ($svcName in $services) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    
    if ($svc) {
        $status = $svc.Status
        $statusColor = switch ($status) {
            "Running" { "Green" }
            "Stopped" { "Yellow" }
            default { "Red" }
        }
        Write-Host "  $svcName : " -NoNewline
        Write-Host $status -ForegroundColor $statusColor
    }
    else {
        Write-Host "  $svcName : " -NoNewline
        Write-Host "NOT REGISTERED" -ForegroundColor Gray
    }
}

Write-Host ""

# ============================================================================
# PORTS
# ============================================================================

Write-Host "PORTS" -ForegroundColor Yellow
Write-Host "-" * 70 -ForegroundColor Gray

$ports = @(
    @{Port = 8000; Name = "API"},
    @{Port = 3000; Name = "Dashboard"},
    @{Port = 5432; Name = "PostgreSQL"}
)

foreach ($portInfo in $ports) {
    $listener = Get-NetTCPConnection -LocalPort $portInfo.Port -State Listen -ErrorAction SilentlyContinue
    
    Write-Host ("  {0,-5} ({1,-12}): " -f $portInfo.Port, $portInfo.Name) -NoNewline
    
    if ($listener) {
        Write-Host "LISTENING" -ForegroundColor Green
    }
    else {
        Write-Host "NOT LISTENING" -ForegroundColor Gray
    }
}

Write-Host ""

# ============================================================================
# ENDPOINTS
# ============================================================================

Write-Host "ENDPOINTS" -ForegroundColor Yellow
Write-Host "-" * 70 -ForegroundColor Gray

$endpoints = @(
    @{Url = "http://localhost:8000/health"; Name = "API Health"},
    @{Url = "http://localhost:3000"; Name = "Dashboard"}
)

foreach ($endpoint in $endpoints) {
    Write-Host ("  {0,-15}: " -f $endpoint.Name) -NoNewline
    
    try {
        $response = Invoke-WebRequest -Uri $endpoint.Url -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "OK" -ForegroundColor Green
        }
        else {
            Write-Host "Status $($response.StatusCode)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "UNREACHABLE" -ForegroundColor Red
    }
}

Write-Host ""

# ============================================================================
# RECOMMENDATIONS
# ============================================================================

Write-Host "RECOMMENDATIONS" -ForegroundColor Yellow
Write-Host "-" * 70 -ForegroundColor Gray

if ($failedStep) {
    Write-Host "  [!] Step $($failedStep.Step) ($($failedStep.Desc)) appears to have failed." -ForegroundColor Red
    Write-Host "      Check log and re-run: $($failedStep.Step)_$($failedStep.Name).ps1" -ForegroundColor Gray
    
    if ($TailOnFailure) {
        $failedLog = Get-LatestLog -StepPattern $failedStep.Step
        if ($failedLog) {
            Write-Host ""
            Show-LogTail -LogPath $failedLog -Lines 50
        }
    }
}
elseif ($nextStep) {
    Write-Host "  [>] Next step to run: $($nextStep.Step)_$($nextStep.Name).ps1" -ForegroundColor Cyan
}
else {
    Write-Host "  [OK] All installation steps complete!" -ForegroundColor Green
    
    # Check if services are running
    $apiRunning = (Get-Service -Name "PolyTrader-API" -ErrorAction SilentlyContinue).Status -eq "Running"
    $uiRunning = (Get-Service -Name "PolyTrader-UI" -ErrorAction SilentlyContinue).Status -eq "Running"
    
    if (-not $apiRunning -or -not $uiRunning) {
        Write-Host "  [>] Start services with: start_services.bat" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""
