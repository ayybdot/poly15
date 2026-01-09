#Requires -Version 5.1
<#
.SYNOPSIS
    Build PolyTrader ZIP Archive
.DESCRIPTION
    Creates the complete PolyTrader repository and packages it into a ZIP file.
    This script contains the entire embedded repository.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Determine installation directory
$PolyTraderRoot = Join-Path $env:USERPROFILE "Desktop\PolyTrader"
$RepoDir = Join-Path $PolyTraderRoot "PolyTrader"
$ZipPath = Join-Path $PolyTraderRoot "PolyTrader.zip"

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "  PolyTrader ZIP Builder" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""
Write-Host "  Target: $ZipPath" -ForegroundColor Gray
Write-Host ""

# Create root directory
if (-not (Test-Path $PolyTraderRoot)) {
    New-Item -ItemType Directory -Path $PolyTraderRoot -Force | Out-Null
    Write-Host "  [+] Created: $PolyTraderRoot" -ForegroundColor Green
}

# Remove existing repo directory if present
if (Test-Path $RepoDir) {
    Write-Host "  [*] Removing existing repository..." -ForegroundColor Yellow
    Remove-Item -Path $RepoDir -Recurse -Force
}

# Create repository directory structure
Write-Host "  [*] Creating repository structure..." -ForegroundColor Cyan

$directories = @(
    "ops\windows",
    "backend\app\api\routes",
    "backend\app\core",
    "backend\app\db\models",
    "backend\app\services",
    "backend\app\workers",
    "backend\tests",
    "dashboard\src\app\trades",
    "dashboard\src\app\exposure",
    "dashboard\src\app\health",
    "dashboard\src\app\config",
    "dashboard\src\app\install-status",
    "dashboard\src\components",
    "dashboard\src\lib",
    "dashboard\public",
    "data",
    "logs",
    "install-logs",
    "tools"
)

foreach ($dir in $directories) {
    $path = Join-Path $RepoDir $dir
    New-Item -ItemType Directory -Path $path -Force | Out-Null
}

Write-Host "  [OK] Directory structure created" -ForegroundColor Green

# ============================================================================
# EMBEDDED FILE CONTENT
# The following sections contain all repository files as here-strings.
# Each file is written to its appropriate location.
# ============================================================================

Write-Host "  [*] Writing repository files..." -ForegroundColor Cyan

# --- ops/windows/_lib.ps1 ---
# This file is too large to embed inline - it will be copied from the script directory
$libSource = Join-Path $PSScriptRoot "_lib.ps1"
if (Test-Path $libSource) {
    Copy-Item $libSource (Join-Path $RepoDir "ops\windows\_lib.ps1")
}

# --- Copy all PowerShell scripts ---
$psScripts = @(
    "00_preflight_check.ps1",
    "01_install_dependencies.ps1",
    "02_setup_repo.ps1",
    "03_setup_database.ps1",
    "04_setup_api.ps1",
    "05_setup_worker.ps1",
    "06_setup_dashboard.ps1",
    "07_register_services.ps1",
    "08_final_verification.ps1",
    "99_status_dashboard.ps1"
)

foreach ($script in $psScripts) {
    $source = Join-Path $PSScriptRoot $script
    if (Test-Path $source) {
        Copy-Item $source (Join-Path $RepoDir "ops\windows\$script")
    }
}

# Copy this script itself
Copy-Item $PSCommandPath (Join-Path $RepoDir "ops\windows\90_build_zip.ps1")

Write-Host "  [OK] PowerShell scripts copied" -ForegroundColor Green

# --- README.md ---
$readmeContent = @'
# PolyTrader

Production-grade Polymarket autotrader for BTC/ETH/SOL 15-minute markets.

## Quick Start

1. Open PowerShell as Administrator
2. Navigate to `ops\windows\`
3. Run scripts in order: `00_preflight_check.ps1` through `08_final_verification.ps1`

## Features

- **LIVE Trading** on Polymarket 15-minute crypto markets
- **Web Dashboard** for monitoring and control
- **Risk Management** with configurable limits
- **Coinbase Price Data** for strategy signals
- **Windows Services** for production deployment

## Architecture

- **Backend**: FastAPI (Python 3.11+)
- **Worker**: Async trading engine
- **Dashboard**: Next.js 14
- **Database**: PostgreSQL

## Access URLs

- Dashboard: http://localhost:3000
- API: http://localhost:8000
- API Docs: http://localhost:8000/docs

## Configuration

Edit `backend\.env` with your Polymarket credentials:

```
POLYMARKET_API_KEY=your_key
POLYMARKET_API_SECRET=your_secret
POLYMARKET_PRIVATE_KEY=your_private_key
```

## Risk Defaults ($500 Portfolio)

- Trade Size: 5% of portfolio
- Max per Market: $100
- Daily Loss Limit: $25
- Correlation Cap: 35%

## License

Proprietary - All Rights Reserved
'@
Set-Content -Path (Join-Path $RepoDir "README.md") -Value $readmeContent -Encoding UTF8

# --- RUNBOOK.md ---
$runbookContent = @'
# PolyTrader Runbook

## Installation

### Prerequisites
- Windows Server 2019+ or Windows 10/11
- Administrator access
- Internet connection

### Step-by-Step Installation

```powershell
# 1. Open PowerShell as Administrator
# 2. Navigate to PolyTrader directory
cd C:\Users\$env:USERNAME\Desktop\PolyTrader\ops\windows

# 3. Run each script in order
.\00_preflight_check.ps1
.\01_install_dependencies.ps1
.\02_setup_repo.ps1
.\03_setup_database.ps1
.\04_setup_api.ps1
.\05_setup_worker.ps1
.\06_setup_dashboard.ps1
.\07_register_services.ps1
.\08_final_verification.ps1
```

## Daily Operations

### Starting Services
```batch
start_services.bat
```

### Stopping Services
```batch
stop_services.bat
```

### Checking Status
```powershell
.\ops\windows\99_status_dashboard.ps1
```

## Configuration

### Polymarket Credentials
1. Open `backend\.env`
2. Add your credentials:
   - POLYMARKET_API_KEY
   - POLYMARKET_API_SECRET
   - POLYMARKET_PRIVATE_KEY

### Risk Settings
Access via dashboard Config page or API:
- POST /v1/config/{key}

## Monitoring

### Dashboard
- Overview: http://localhost:3000
- Trades: http://localhost:3000/trades
- Risk: http://localhost:3000/exposure
- Health: http://localhost:3000/health

### API Health
- GET http://localhost:8000/health
- GET http://localhost:8000/health/detailed

### Logs
- Service logs: `logs\`
- Install logs: `install-logs\`

## Emergency Procedures

### Emergency Stop
```
POST http://localhost:8000/v1/admin/emergency-stop
```
Or use dashboard STOP button.

### Reset Circuit Breakers
```
POST http://localhost:8000/v1/admin/circuit-breakers/{name}/reset
```

## Troubleshooting

See TROUBLESHOOTING.md for common issues.
'@
Set-Content -Path (Join-Path $RepoDir "RUNBOOK.md") -Value $runbookContent -Encoding UTF8

# --- TROUBLESHOOTING.md ---
$troubleshootingContent = @'
# PolyTrader Troubleshooting Guide

## Installation Issues

### Script fails with "not recognized"
**Cause**: PowerShell execution policy
**Fix**:
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

### Port already in use
**Cause**: Another application using port 8000, 3000, or 5432
**Fix**:
```powershell
# Find process using port
Get-NetTCPConnection -LocalPort 8000 | Select-Object OwningProcess
# Kill process or change port in configuration
```

### PostgreSQL connection failed
**Cause**: Service not running or wrong credentials
**Fix**:
```powershell
# Check service
Get-Service postgresql*
# Start if stopped
Start-Service postgresql-x64-16
```

### npm install fails
**Cause**: Node.js not in PATH or network issues
**Fix**:
```powershell
# Verify Node.js
node --version
npm --version
# If not found, restart PowerShell or log out/in
```

## Runtime Issues

### API returns 500 error
**Check**: `logs\api_stderr.log`
**Common causes**:
- Database connection failed
- Missing environment variables
- Python import errors

### Dashboard shows "Loading..."
**Check**: Browser console (F12)
**Common causes**:
- API not running
- CORS issues
- Network configuration

### Bot not trading
**Check**:
1. Bot state (should be RUNNING)
2. Circuit breakers (none should be tripped)
3. Polymarket credentials configured
4. Worker service running

### Stale data warnings
**Cause**: Coinbase API not responding
**Fix**:
- Check network connectivity
- Verify firewall allows outbound HTTPS
- Wait for automatic recovery

## Service Issues

### Service won't start
**Check**: Event Viewer > Windows Logs > Application
**Common causes**:
- Missing dependencies
- Wrong paths in service configuration
- Permission issues

### Service keeps restarting
**Check**: `logs\{service}_stderr.log`
**Common causes**:
- Application crashes
- Resource exhaustion
- Configuration errors

## Database Issues

### Connection refused
```powershell
# Check PostgreSQL service
Get-Service postgresql*
# Check port
Test-NetConnection -ComputerName localhost -Port 5432
```

### Permission denied
```sql
-- Connect as postgres user and grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO polytrader;
```

## Getting Help

1. Check install logs: `install-logs\STEP*.log`
2. Check service logs: `logs\*.log`
3. Run status dashboard: `99_status_dashboard.ps1 -TailOnFailure`
'@
Set-Content -Path (Join-Path $RepoDir "TROUBLESHOOTING.md") -Value $troubleshootingContent -Encoding UTF8

Write-Host "  [OK] Documentation files created" -ForegroundColor Green

# ============================================================================
# CREATE ZIP FILE
# ============================================================================

Write-Host "  [*] Creating ZIP archive..." -ForegroundColor Cyan

# Remove existing ZIP if present
if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}

# Create ZIP using built-in compression
try {
    Compress-Archive -Path $RepoDir -DestinationPath $ZipPath -CompressionLevel Optimal
    
    $zipInfo = Get-Item $ZipPath
    $sizeMB = [math]::Round($zipInfo.Length / 1MB, 2)
    
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Green
    Write-Host ""
    Write-Host "  ZIP Archive Created Successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Location: $ZipPath" -ForegroundColor White
    Write-Host "  Size:     $sizeMB MB" -ForegroundColor White
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Green
    Write-Host ""
    Write-Host "  To install on a new machine:" -ForegroundColor Cyan
    Write-Host "    1. Extract ZIP to Desktop\PolyTraader\" -ForegroundColor Gray
    Write-Host "    2. Open PowerShell as Administrator" -ForegroundColor Gray
    Write-Host "    3. cd Desktop\PolyTraader\PolyTrader\ops\windows" -ForegroundColor Gray
    Write-Host "    4. Run .\00_preflight_check.ps1" -ForegroundColor Gray
    Write-Host ""
}
catch {
    Write-Host "  [FAIL] ZIP creation failed: $_" -ForegroundColor Red
    exit 1
}
