#Requires -Version 5.1
<#
.SYNOPSIS
    Step 05: Setup Worker
.DESCRIPTION
    Configures and tests the trading worker process.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\_lib.ps1"

if (-not (Test-Marker -Name "api_ok")) {
    Write-Host "ERROR: API not set up. Run 04_setup_api.ps1 first." -ForegroundColor Red
    exit 1
}

$logFile = Start-Log -StepNumber "05" -StepName "setup_worker"
Write-StepHeader "05" "SETUP WORKER"

$root = Get-PolyTraderRoot
$backendDir = Join-Path $root "backend"
$venvPython = Join-Path $root "venv\Scripts\python.exe"
$workerPath = Join-Path $backendDir "app\workers\trading_worker.py"

try {
    Write-Section "Verify Worker Files"
    
    if (Test-Path $workerPath) {
        Write-Ok "Worker script found: $workerPath"
    }
    else {
        throw "Worker script not found: $workerPath"
    }
    
    Write-Section "Verify Worker Imports"
    
    $checkScript = @"
import sys
sys.path.insert(0, r'$backendDir')
try:
    from app.workers.trading_worker import TradingWorker
    from app.services.price_service import PriceService
    from app.services.strategy_service import StrategyService
    from app.services.trading_service import TradingService
    from app.services.risk_service import RiskManager
    print('OK')
except ImportError as e:
    print(f'FAIL: {e}')
    sys.exit(1)
"@
    
    $result = & $venvPython -c $checkScript 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "All worker imports successful"
    }
    else {
        Write-Fail "Worker import check failed: $result"
        throw "Import check failed"
    }
    
    Write-Section "Test Worker Initialization (Dry Run)"
    
    $dryRunScript = @"
import sys
import os
import asyncio

# Set working directory to backend so .env is found
os.chdir(r'$backendDir')
sys.path.insert(0, r'$backendDir')

from app.core.config import settings
from app.services.risk_service import RiskManager

async def dry_run():
    print(f"Trading assets: {settings.TRADING_ASSETS}")
    print(f"Portfolio trade %: {settings.PORTFOLIO_TRADE_PCT}")
    print(f"Max market USD: {settings.MAX_MARKET_USD}")
    print(f"Daily loss limit: {settings.DAILY_LOSS_LIMIT_USD}")
    
    rm = RiskManager()
    config = await rm.load_config()
    print(f"Config keys loaded: {len(config)}")
    
    state = await rm.get_bot_state()
    print(f"Bot state: {state}")
    
    print("DRY_RUN_OK")

asyncio.run(dry_run())
"@
    
    $dryRunFile = Join-Path $root "data\worker_dry_run.py"
    Set-Content -Path $dryRunFile -Value $dryRunScript -Encoding UTF8
    
    Write-Status "Running worker dry run..." -Icon "Arrow"
    
    $env:PYTHONPATH = $backendDir
    $ErrorActionPreference = "Continue"
    $result = & $venvPython $dryRunFile 2>&1
    $ErrorActionPreference = "Stop"
    
    $resultText = $result -join "`n"
    if ($resultText -match "DRY_RUN_OK") {
        Write-Ok "Worker dry run successful"
        Write-Log "Dry run output: $resultText"
    }
    else {
        Write-Fail "Worker dry run failed"
        Write-Log "Dry run output: $resultText" -Level "ERROR"
        throw "Dry run failed: $resultText"
    }
    
    Remove-Item $dryRunFile -Force -ErrorAction SilentlyContinue
    
    Write-Section "Create Worker Startup Script"
    
    $startScript = @"
@echo off
cd /d "$backendDir"
set PYTHONPATH=$backendDir
"$venvPython" -m app.workers.trading_worker
"@
    
    $startScriptPath = Join-Path $root "start_worker.bat"
    Set-Content -Path $startScriptPath -Value $startScript -Encoding ASCII
    Write-Ok "Created start_worker.bat"
    
    Write-Section "Verify Risk Configuration"
    
    $riskDefaults = @{
        "portfolio_trade_pct" = 5
        "max_market_usd" = 100
        "correlation_max_basket_pct" = 35
        "daily_loss_limit_usd" = 25
        "take_profit_pct" = 8
        "stop_loss_pct" = 5
    }
    
    Write-Status "Risk defaults for `$500 portfolio:" -Icon "Info"
    foreach ($key in $riskDefaults.Keys) {
        Write-Status "  $key = $($riskDefaults[$key])" -Icon "Check"
    }
    
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Cyan
    Write-Ok "Worker setup completed successfully!"
    Set-Marker -Name "worker_dry_ok"
    
    Write-Host ""
    Write-Host "  Worker can be started with: $startScriptPath" -ForegroundColor Gray
    Write-Host "  Or via service after step 07" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  IMPORTANT: Worker will NOT trade until:" -ForegroundColor Yellow
    Write-Host "    1. Polymarket API credentials are configured in .env" -ForegroundColor Yellow
    Write-Host "    2. Bot state is set to RUNNING via UI or API" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Next step: Run 06_setup_dashboard.ps1" -ForegroundColor Green
    Write-Host ""
    
    Stop-Log -Success $true
}
catch {
    Write-Fail "Worker setup failed: $_"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Stop-Log -Success $false
    Write-Host "  Check log file: $logFile" -ForegroundColor Red
    exit 1
}