#Requires -Version 5.1
<#
.SYNOPSIS
    Step 00: Preflight Check
.DESCRIPTION
    Validates system prerequisites before installation.
    Checks: OS, PowerShell, admin rights, ports, disk space, network.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Get script directory and load library
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\_lib.ps1"

# Start logging
$logFile = Start-Log -StepNumber "00" -StepName "preflight_check"
Write-StepHeader "00" "PREFLIGHT CHECK"

$allPassed = $true

try {
    # ========================================================================
    # OS CHECK
    # ========================================================================
    Write-Section "Operating System"
    
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Status "OS: $($os.Caption)" -Icon "Info"
    Write-Status "Version: $($os.Version)" -Icon "Info"
    Write-Status "Architecture: $($os.OSArchitecture)" -Icon "Info"
    
    if ($os.Caption -match "Windows Server 2019" -or $os.Caption -match "Windows Server 2022" -or $os.Caption -match "Windows 10" -or $os.Caption -match "Windows 11") {
        Write-Ok "OS is supported"
    }
    else {
        Write-Warn "OS may not be fully supported (expected Windows Server 2019+)"
    }
    
    # ========================================================================
    # POWERSHELL VERSION
    # ========================================================================
    Write-Section "PowerShell Version"
    
    $psVersion = $PSVersionTable.PSVersion
    Write-Status "PowerShell: $psVersion" -Icon "Info"
    
    if ($psVersion.Major -ge 5) {
        Write-Ok "PowerShell version is adequate (5.1+)"
    }
    else {
        Write-Fail "PowerShell 5.1+ required"
        $allPassed = $false
    }
    
    # ========================================================================
    # ADMIN RIGHTS
    # ========================================================================
    Write-Section "Administrator Privileges"
    
    if (Test-IsAdmin) {
        Write-Ok "Running with administrator privileges"
    }
    else {
        Write-Warn "Not running as administrator - some operations may fail"
        Write-Status "Re-run as Administrator for full functionality" -Icon "Warning"
    }
    
    # ========================================================================
    # DIRECTORY SETUP
    # ========================================================================
    Write-Section "Directory Setup"
    
    $root = Get-PolyTraderRoot
    Write-Status "PolyTrader root: $root" -Icon "Info"
    
    if (-not (Test-Path $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Write-Ok "Created root directory"
    }
    else {
        Write-Ok "Root directory exists"
    }
    
    # Create subdirectories
    $subdirs = @("data", "logs", "install-logs", "tools", "backend", "dashboard", "venv")
    foreach ($subdir in $subdirs) {
        $path = Join-Path $root $subdir
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
    Write-Ok "All subdirectories created"
    
    # ========================================================================
    # DISK SPACE
    # ========================================================================
    Write-Section "Disk Space"
    
    $drive = (Get-Item $root).PSDrive
    $freeGB = [math]::Round($drive.Free / 1GB, 2)
    Write-Status "Free space on $($drive.Name): $freeGB GB" -Icon "Info"
    
    if ($freeGB -ge 5) {
        Write-Ok "Sufficient disk space available"
    }
    else {
        Write-Fail "At least 5 GB free space recommended"
        $allPassed = $false
    }
    
    # ========================================================================
    # PORT AVAILABILITY
    # ========================================================================
    Write-Section "Port Availability"
    
    $ports = @(
        @{Port = 3000; Service = "Dashboard (Next.js)"},
        @{Port = 8000; Service = "API (FastAPI)"},
        @{Port = 5432; Service = "PostgreSQL"}
    )
    
    foreach ($portInfo in $ports) {
        $listener = Get-NetTCPConnection -LocalPort $portInfo.Port -ErrorAction SilentlyContinue
        if ($listener) {
            $process = Get-Process -Id $listener[0].OwningProcess -ErrorAction SilentlyContinue
            $processName = if ($process) { $process.ProcessName } else { "Unknown" }
            Write-Warn "Port $($portInfo.Port) ($($portInfo.Service)) in use by $processName"
        }
        else {
            Write-Ok "Port $($portInfo.Port) ($($portInfo.Service)) is available"
        }
    }
    
    # ========================================================================
    # NETWORK CONNECTIVITY
    # ========================================================================
    Write-Section "Network Connectivity"
    
    $endpoints = @(
        @{Url = "https://api.coinbase.com"; Name = "Coinbase API"},
        @{Url = "https://gamma-api.polymarket.com"; Name = "Polymarket Gamma API"},
        @{Url = "https://clob.polymarket.com"; Name = "Polymarket CLOB API"}
    )
    
    foreach ($endpoint in $endpoints) {
        try {
            $response = Invoke-WebRequest -Uri $endpoint.Url -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            Write-Ok "$($endpoint.Name) reachable"
        }
        catch {
            Write-Warn "$($endpoint.Name) unreachable: $($_.Exception.Message)"
        }
    }
    
    # ========================================================================
    # EXISTING TOOLS CHECK
    # ========================================================================
    Write-Section "Existing Tools (Optional)"
    
    # Python
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        $pythonVersion = & python --version 2>&1
        Write-Ok "Python found: $pythonVersion"
    }
    else {
        Write-Status "Python not found (will be installed)" -Icon "Info"
    }
    
    # Node.js
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCmd) {
        $nodeVersion = & node --version 2>&1
        Write-Ok "Node.js found: $nodeVersion"
    }
    else {
        Write-Status "Node.js not found (will be installed)" -Icon "Info"
    }
    
    # PostgreSQL
    $pgCmd = Get-Command psql -ErrorAction SilentlyContinue
    if ($pgCmd) {
        Write-Ok "PostgreSQL client found"
    }
    else {
        Write-Status "PostgreSQL not found (will be installed)" -Icon "Info"
    }
    
    # Git
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        $gitVersion = & git --version 2>&1
        Write-Ok "Git found: $gitVersion"
    }
    else {
        Write-Status "Git not found (will be installed)" -Icon "Info"
    }
    
    # ========================================================================
    # ENVIRONMENT VARIABLES
    # ========================================================================
    Write-Section "Environment"
    
    Write-Status "USERPROFILE: $env:USERPROFILE" -Icon "Info"
    Write-Status "COMPUTERNAME: $env:COMPUTERNAME" -Icon "Info"
    Write-Status "USERNAME: $env:USERNAME" -Icon "Info"
    
    # ========================================================================
    # SUMMARY
    # ========================================================================
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Cyan
    
    if ($allPassed) {
        Write-Ok "All preflight checks passed!"
        Set-Marker -Name "preflight_ok"
        
        Write-Host ""
        Write-Host "  Next step: Run 01_install_dependencies.ps1" -ForegroundColor Green
        Write-Host ""
    }
    else {
        Write-Fail "Some preflight checks failed"
        Write-Host ""
        Write-Host "  Please resolve the issues above before continuing." -ForegroundColor Red
        Write-Host ""
    }
    
    Stop-Log -Success $allPassed
    
    if (-not $allPassed) {
        exit 1
    }
}
catch {
    Write-Fail "Preflight check failed with error: $_"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Stop-Log -Success $false
    
    Write-Host ""
    Write-Host "  Check log file for details: $logFile" -ForegroundColor Red
    Write-Host ""
    
    exit 1
}
