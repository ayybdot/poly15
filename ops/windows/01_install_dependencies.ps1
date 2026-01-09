#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Step 01: Install Dependencies
.DESCRIPTION
    Installs all required software: Python, Node.js, PostgreSQL, Git, NSSM.
    Uses winget where available, falls back to direct downloads.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Get script directory and load library
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\_lib.ps1"

# Verify preflight completed
if (-not (Test-Marker -Name "preflight_ok")) {
    Write-Host "ERROR: Preflight check not completed. Run 00_preflight_check.ps1 first." -ForegroundColor Red
    exit 1
}

# Start logging
$logFile = Start-Log -StepNumber "01" -StepName "install_dependencies"
Write-StepHeader "01" "INSTALL DEPENDENCIES"

$root = Get-PolyTraderRoot
$toolsDir = Join-Path $root "tools"

try {
    # ========================================================================
    # WINGET CHECK
    # ========================================================================
    Write-Section "Package Manager Check"
    
    $hasWinget = Get-Command winget -ErrorAction SilentlyContinue
    if ($hasWinget) {
        Write-Ok "winget is available"
    }
    else {
        Write-Status "winget not available - will use direct downloads" -Icon "Warning"
    }
    
    # ========================================================================
    # PYTHON 3.11+
    # ========================================================================
    Write-Section "Python Installation"
    
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    $needPython = $true
    
    if ($pythonCmd) {
        $versionOutput = & python --version 2>&1
        if ($versionOutput -match "Python 3\.1[1-9]|Python 3\.[2-9]") {
            Write-Ok "Python already installed: $versionOutput"
            $needPython = $false
        }
        else {
            Write-Warn "Python version too old: $versionOutput (need 3.11+)"
        }
    }
    
    if ($needPython) {
        Write-Status "Installing Python 3.11..." -Icon "Arrow"
        
        if ($hasWinget) {
            $result = Invoke-LoggedCommand -Command "winget install Python.Python.3.11 --accept-package-agreements --accept-source-agreements" -ContinueOnError
        }
        else {
            # Direct download
            $pythonUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
            $pythonInstaller = Join-Path $toolsDir "python-installer.exe"
            
            Write-Status "Downloading Python from $pythonUrl" -Icon "Arrow"
            Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonInstaller -UseBasicParsing
            
            Write-Status "Running Python installer" -Icon "Arrow"
            Start-Process -FilePath $pythonInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
            Remove-Item $pythonInstaller -Force
        }
        
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Verify
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
        if ($pythonCmd) {
            $versionOutput = & python --version 2>&1
            Write-Ok "Python installed: $versionOutput"
        }
        else {
            throw "Python installation failed"
        }
    }
    
    # ========================================================================
    # PIP UPGRADE
    # ========================================================================
    Write-Section "Pip Upgrade"
    
    Invoke-LoggedCommand -Command "python -m pip install --upgrade pip" -Description "Upgrading pip"
    Write-Ok "Pip upgraded"
    
    # ========================================================================
    # NODE.JS 20+
    # ========================================================================
    Write-Section "Node.js Installation"
    
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    $needNode = $true
    
    if ($nodeCmd) {
        $nodeVersion = & node --version 2>&1
        if ($nodeVersion -match "v2[0-9]|v[3-9][0-9]") {
            Write-Ok "Node.js already installed: $nodeVersion"
            $needNode = $false
        }
        else {
            Write-Warn "Node.js version too old: $nodeVersion (need 20+)"
        }
    }
    
    if ($needNode) {
        Write-Status "Installing Node.js 20 LTS..." -Icon "Arrow"
        
        if ($hasWinget) {
            Invoke-LoggedCommand -Command "winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements" -ContinueOnError
        }
        else {
            $nodeUrl = "https://nodejs.org/dist/v20.11.0/node-v20.11.0-x64.msi"
            $nodeInstaller = Join-Path $toolsDir "node-installer.msi"
            
            Write-Status "Downloading Node.js from $nodeUrl" -Icon "Arrow"
            Invoke-WebRequest -Uri $nodeUrl -OutFile $nodeInstaller -UseBasicParsing
            
            Write-Status "Running Node.js installer" -Icon "Arrow"
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$nodeInstaller`" /quiet" -Wait
            Remove-Item $nodeInstaller -Force
        }
        
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Verify
        $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
        if ($nodeCmd) {
            $nodeVersion = & node --version 2>&1
            Write-Ok "Node.js installed: $nodeVersion"
        }
        else {
            throw "Node.js installation failed"
        }
    }
    
    # ========================================================================
    # NPM UPDATE
    # ========================================================================
    Write-Section "NPM Update"
    
    Invoke-LoggedCommand -Command "npm install -g npm@latest" -Description "Updating npm" -ContinueOnError
    $npmVersion = & npm --version 2>&1
    Write-Ok "npm version: $npmVersion"
    
    # ========================================================================
    # POSTGRESQL
    # ========================================================================
    Write-Section "PostgreSQL Installation"
    
    $pgService = Get-Service -Name "postgresql*" -ErrorAction SilentlyContinue
    $pgCmd = Get-Command psql -ErrorAction SilentlyContinue
    
    if ($pgService -or $pgCmd) {
        Write-Ok "PostgreSQL already installed"
    }
    else {
        Write-Status "Installing PostgreSQL 16..." -Icon "Arrow"
        
        if ($hasWinget) {
            Invoke-LoggedCommand -Command "winget install PostgreSQL.PostgreSQL --accept-package-agreements --accept-source-agreements" -ContinueOnError
        }
        else {
            # Direct download
            $pgUrl = "https://get.enterprisedb.com/postgresql/postgresql-16.2-1-windows-x64.exe"
            $pgInstaller = Join-Path $toolsDir "postgresql-installer.exe"
            
            Write-Status "Downloading PostgreSQL from $pgUrl" -Icon "Arrow"
            Invoke-WebRequest -Uri $pgUrl -OutFile $pgInstaller -UseBasicParsing
            
            # Generate random password for postgres user
            $pgPassword = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
            
            Write-Status "Running PostgreSQL installer" -Icon "Arrow"
            $pgArgs = "--mode unattended --superpassword `"$pgPassword`" --serverport 5432"
            Start-Process -FilePath $pgInstaller -ArgumentList $pgArgs -Wait
            
            # Save password
            $pgPasswordFile = Join-Path $root "data\.pgpassword"
            Set-Content -Path $pgPasswordFile -Value $pgPassword -Encoding UTF8
            Write-Status "PostgreSQL password saved to $pgPasswordFile" -Icon "Info"
            
            Remove-Item $pgInstaller -Force
        }
        
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Add PostgreSQL to PATH if not already there
        $pgPath = "C:\Program Files\PostgreSQL\16\bin"
        if (Test-Path $pgPath) {
            if ($env:Path -notlike "*$pgPath*") {
                $env:Path = "$env:Path;$pgPath"
                [System.Environment]::SetEnvironmentVariable("Path", $env:Path, "Machine")
            }
        }
        
        Write-Ok "PostgreSQL installed"
    }
    
    # ========================================================================
    # GIT
    # ========================================================================
    Write-Section "Git Installation"
    
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    
    if ($gitCmd) {
        $gitVersion = & git --version 2>&1
        Write-Ok "Git already installed: $gitVersion"
    }
    else {
        Write-Status "Installing Git..." -Icon "Arrow"
        
        if ($hasWinget) {
            Invoke-LoggedCommand -Command "winget install Git.Git --accept-package-agreements --accept-source-agreements" -ContinueOnError
        }
        else {
            $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.44.0.windows.1/Git-2.44.0-64-bit.exe"
            $gitInstaller = Join-Path $toolsDir "git-installer.exe"
            
            Write-Status "Downloading Git from $gitUrl" -Icon "Arrow"
            Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
            
            Write-Status "Running Git installer" -Icon "Arrow"
            Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART" -Wait
            Remove-Item $gitInstaller -Force
        }
        
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        $gitCmd = Get-Command git -ErrorAction SilentlyContinue
        if ($gitCmd) {
            $gitVersion = & git --version 2>&1
            Write-Ok "Git installed: $gitVersion"
        }
        else {
            Write-Warn "Git installation may require restart"
        }
    }
    
    # ========================================================================
    # NSSM (Non-Sucking Service Manager)
    # ========================================================================
    Write-Section "NSSM Installation"
    
    $nssmPath = Join-Path $toolsDir "nssm.exe"
    
    if (Test-Path $nssmPath) {
        Write-Ok "NSSM already present"
    }
    else {
        Write-Status "Downloading NSSM..." -Icon "Arrow"
        
        # Multiple download sources for reliability
        $nssmUrls = @(
            "https://github.com/kirillkovalenko/nssm/releases/download/v2.24-101/nssm-2.24-101.zip",
            "https://github.com/win-nssm/nssm/releases/download/2.24/nssm-2.24.zip",
            "https://nssm.cc/release/nssm-2.24.zip"
        )
        $nssmZip = Join-Path $toolsDir "nssm.zip"
        $nssmExtract = Join-Path $toolsDir "nssm-extract"
        
        $downloaded = $false
        foreach ($nssmUrl in $nssmUrls) {
            try {
                Write-Status "Trying: $nssmUrl" -Icon "Arrow"
                Invoke-WebRequest -Uri $nssmUrl -OutFile $nssmZip -UseBasicParsing -TimeoutSec 30
                $downloaded = $true
                Write-Ok "Downloaded from $nssmUrl"
                break
            }
            catch {
                Write-Warn "Failed to download from $nssmUrl, trying next..."
            }
        }
        
        if (-not $downloaded) {
            throw "Failed to download NSSM from all sources. Please download manually from https://nssm.cc/download and place nssm.exe in $toolsDir"
        }
        Expand-Archive -Path $nssmZip -DestinationPath $nssmExtract -Force
        
        # Find and copy the 64-bit exe
        $nssmExe = Get-ChildItem -Path $nssmExtract -Recurse -Filter "nssm.exe" | 
                   Where-Object { $_.DirectoryName -match "win64" } | 
                   Select-Object -First 1
        
        if ($nssmExe) {
            Copy-Item -Path $nssmExe.FullName -Destination $nssmPath -Force
            Write-Ok "NSSM installed to $nssmPath"
        }
        else {
            throw "Could not find nssm.exe in downloaded archive"
        }
        
        # Cleanup
        Remove-Item $nssmZip -Force
        Remove-Item $nssmExtract -Recurse -Force
    }
    
    # ========================================================================
    # VERIFY ALL DEPENDENCIES
    # ========================================================================
    Write-Section "Dependency Verification"
    
    $verified = $true
    
    # Python
    $pythonCheck = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCheck) {
        Write-Ok "Python: $(& python --version 2>&1)"
    }
    else {
        Write-Fail "Python not found in PATH"
        $verified = $false
    }
    
    # Node
    $nodeCheck = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCheck) {
        Write-Ok "Node.js: $(& node --version 2>&1)"
    }
    else {
        Write-Fail "Node.js not found in PATH"
        $verified = $false
    }
    
    # npm
    $npmCheck = Get-Command npm -ErrorAction SilentlyContinue
    if ($npmCheck) {
        Write-Ok "npm: $(& npm --version 2>&1)"
    }
    else {
        Write-Fail "npm not found in PATH"
        $verified = $false
    }
    
    # PostgreSQL
    $pgCheck = Get-Command psql -ErrorAction SilentlyContinue
    if ($pgCheck) {
        Write-Ok "PostgreSQL client available"
    }
    else {
        Write-Warn "PostgreSQL client not in PATH (may need restart)"
    }
    
    # Git
    $gitCheck = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCheck) {
        Write-Ok "Git: $(& git --version 2>&1)"
    }
    else {
        Write-Warn "Git not in PATH (may need restart)"
    }
    
    # NSSM
    if (Test-Path $nssmPath) {
        Write-Ok "NSSM: Present at $nssmPath"
    }
    else {
        Write-Fail "NSSM not found"
        $verified = $false
    }
    
    # ========================================================================
    # SUMMARY
    # ========================================================================
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Cyan
    
    if ($verified) {
        Write-Ok "All dependencies installed successfully!"
        Set-Marker -Name "deps_ok"
        
        Write-Host ""
        Write-Host "  NOTE: You may need to restart your terminal/PowerShell session" -ForegroundColor Yellow
        Write-Host "        for PATH changes to take effect." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Next step: Run 02_setup_repo.ps1" -ForegroundColor Green
        Write-Host ""
    }
    else {
        Write-Fail "Some dependencies failed to install"
        Write-Host ""
        Write-Host "  Please resolve the issues above before continuing." -ForegroundColor Red
        Write-Host ""
    }
    
    Stop-Log -Success $verified
    
    if (-not $verified) {
        exit 1
    }
}
catch {
    Write-Fail "Dependency installation failed: $_"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Stop-Log -Success $false
    
    Write-Host ""
    Write-Host "  Check log file for details: $logFile" -ForegroundColor Red
    Write-Host ""
    
    exit 1
}