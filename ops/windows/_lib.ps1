#Requires -Version 5.1
<#
.SYNOPSIS
    PolyTrader Shared PowerShell Library
.DESCRIPTION
    Common functions for all installation and management scripts.
    Must be dot-sourced at the start of each script.
#>

# ============================================================================
# CONFIGURATION
# ============================================================================
$script:POLYTRADER_ROOT = Join-Path $env:USERPROFILE "Desktop\PolyTrader"
$script:LOG_DIR = Join-Path $script:POLYTRADER_ROOT "install-logs"
$script:DATA_DIR = Join-Path $script:POLYTRADER_ROOT "data"
$script:MARKER_DIR = $script:DATA_DIR

# Ensure directories exist
if (-not (Test-Path $script:LOG_DIR)) { New-Item -ItemType Directory -Path $script:LOG_DIR -Force | Out-Null }
if (-not (Test-Path $script:DATA_DIR)) { New-Item -ItemType Directory -Path $script:DATA_DIR -Force | Out-Null }

# Colors
$script:Colors = @{
    Header  = "Cyan"
    Ok      = "Green"
    Warn    = "Yellow"
    Fail    = "Red"
    Info    = "White"
    Dim     = "DarkGray"
}

# Current log file
$script:CurrentLogFile = $null
$script:StepName = $null

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

function Start-Log {
    <#
    .SYNOPSIS
        Starts logging for a step
    .PARAMETER StepNumber
        Step number (e.g., "00", "01")
    .PARAMETER StepName
        Step name (e.g., "preflight_check")
    #>
    param(
        [Parameter(Mandatory)][string]$StepNumber,
        [Parameter(Mandatory)][string]$StepName
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:StepName = $StepName
    $script:CurrentLogFile = Join-Path $script:LOG_DIR "STEP${StepNumber}_${StepName}_${timestamp}.log"
    
    # Initialize log file
    $header = @"
================================================================================
PolyTrader Installation Log
Step: $StepNumber - $StepName
Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
User: $env:USERNAME
Computer: $env:COMPUTERNAME
================================================================================

"@
    Set-Content -Path $script:CurrentLogFile -Value $header -Encoding UTF8
    
    return $script:CurrentLogFile
}

function Stop-Log {
    <#
    .SYNOPSIS
        Finalizes the current log
    #>
    param(
        [Parameter(Mandatory)][bool]$Success
    )
    
    if ($script:CurrentLogFile -and (Test-Path $script:CurrentLogFile)) {
        $footer = @"

================================================================================
Completed: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Status: $(if ($Success) { "SUCCESS" } else { "FAILED" })
================================================================================
"@
        Add-Content -Path $script:CurrentLogFile -Value $footer -Encoding UTF8
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes to both console and log file
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"
    
    if ($script:CurrentLogFile) {
        Add-Content -Path $script:CurrentLogFile -Value $logLine -Encoding UTF8
    }
    
    $color = switch ($Level) {
        "OK"    { $script:Colors.Ok }
        "WARN"  { $script:Colors.Warn }
        "ERROR" { $script:Colors.Fail }
        "FAIL"  { $script:Colors.Fail }
        default { $script:Colors.Info }
    }
    
    Write-Host $logLine -ForegroundColor $color
}

# ============================================================================
# OUTPUT FUNCTIONS
# ============================================================================

function Write-StepHeader {
    <#
    .SYNOPSIS
        Writes a prominent step header
    #>
    param(
        [Parameter(Mandatory)][string]$StepNumber,
        [Parameter(Mandatory)][string]$Title
    )
    
    $border = "=" * 70
    $header = @"

$border
  STEP $StepNumber : $Title
$border

"@
    Write-Host $header -ForegroundColor $script:Colors.Header
    Write-Log "=== STEP $StepNumber : $Title ===" -Level "INFO"
}

function Write-Status {
    <#
    .SYNOPSIS
        Writes a status message with optional icon
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("Info", "Check", "Arrow", "Warning", "Error")][string]$Icon = "Info"
    )
    
    $icons = @{
        Info    = "[*]"
        Check   = "[+]"
        Arrow   = "[>]"
        Warning = "[!]"
        Error   = "[X]"
    }
    
    $prefix = $icons[$Icon]
    Write-Host "  $prefix $Message" -ForegroundColor $script:Colors.Info
    Write-Log "$prefix $Message"
}

function Write-Ok {
    <#
    .SYNOPSIS
        Writes a success message
    #>
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor $script:Colors.Ok
    Write-Log "[OK] $Message" -Level "OK"
}

function Write-Warn {
    <#
    .SYNOPSIS
        Writes a warning message
    #>
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor $script:Colors.Warn
    Write-Log "[WARN] $Message" -Level "WARN"
}

function Write-Fail {
    <#
    .SYNOPSIS
        Writes a failure message
    #>
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor $script:Colors.Fail
    Write-Log "[FAIL] $Message" -Level "FAIL"
}

function Write-Section {
    <#
    .SYNOPSIS
        Writes a section header
    #>
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ""
    Write-Host "  --- $Title ---" -ForegroundColor $script:Colors.Header
    Write-Log "--- $Title ---"
}

# ============================================================================
# COMMAND EXECUTION
# ============================================================================

function Invoke-LoggedCommand {
    <#
    .SYNOPSIS
        Executes a command and captures all output
    .PARAMETER Command
        The command to execute
    .PARAMETER Description
        Description for logging
    .PARAMETER WorkingDirectory
        Optional working directory
    .PARAMETER ContinueOnError
        If true, don't throw on non-zero exit
    .OUTPUTS
        PSCustomObject with ExitCode, Stdout, Stderr, Success
    #>
    param(
        [Parameter(Mandatory)][string]$Command,
        [string]$Description = "",
        [string]$WorkingDirectory = $null,
        [switch]$ContinueOnError
    )
    
    if ($Description) {
        Write-Status $Description -Icon "Arrow"
    }
    
    Write-Log "Executing: $Command"
    
    $tempOut = [System.IO.Path]::GetTempFileName()
    $tempErr = [System.IO.Path]::GetTempFileName()
    
    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "cmd.exe"
        $pinfo.Arguments = "/c $Command"
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        
        if ($WorkingDirectory) {
            $pinfo.WorkingDirectory = $WorkingDirectory
        }
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $pinfo
        $process.Start() | Out-Null
        
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        $result = [PSCustomObject]@{
            ExitCode = $process.ExitCode
            Stdout   = $stdout
            Stderr   = $stderr
            Success  = ($process.ExitCode -eq 0)
        }
        
        # Log output
        if ($stdout) {
            Write-Log "STDOUT: $stdout"
        }
        if ($stderr) {
            Write-Log "STDERR: $stderr" -Level "WARN"
        }
        Write-Log "Exit code: $($result.ExitCode)"
        
        if (-not $result.Success -and -not $ContinueOnError) {
            throw "Command failed with exit code $($result.ExitCode): $Command"
        }
        
        return $result
    }
    finally {
        if (Test-Path $tempOut) { Remove-Item $tempOut -Force }
        if (Test-Path $tempErr) { Remove-Item $tempErr -Force }
    }
}

function Invoke-PowerShellCommand {
    <#
    .SYNOPSIS
        Executes a PowerShell command/scriptblock with logging
    #>
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [string]$Description = ""
    )
    
    if ($Description) {
        Write-Status $Description -Icon "Arrow"
    }
    
    Write-Log "Executing PowerShell: $ScriptBlock"
    
    try {
        $result = & $ScriptBlock 2>&1
        Write-Log "Result: $result"
        return $result
    }
    catch {
        Write-Log "Error: $_" -Level "ERROR"
        throw
    }
}

# ============================================================================
# ASSERTION FUNCTIONS
# ============================================================================

function Assert-CommandExists {
    <#
    .SYNOPSIS
        Verifies a command is available
    #>
    param(
        [Parameter(Mandatory)][string]$Command,
        [string]$Message = ""
    )
    
    $exists = Get-Command $Command -ErrorAction SilentlyContinue
    
    if ($exists) {
        Write-Ok "Command '$Command' found: $($exists.Source)"
        return $true
    }
    else {
        $msg = if ($Message) { $Message } else { "Command '$Command' not found" }
        Write-Fail $msg
        return $false
    }
}

function Assert-PortFree {
    <#
    .SYNOPSIS
        Verifies a TCP port is not in use
    #>
    param(
        [Parameter(Mandatory)][int]$Port,
        [switch]$AllowInUse
    )
    
    $listener = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    
    if ($listener) {
        $process = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
        $processName = if ($process) { $process.ProcessName } else { "Unknown" }
        
        if ($AllowInUse) {
            Write-Warn "Port $Port in use by $processName (PID: $($listener.OwningProcess))"
            return $false
        }
        else {
            Write-Fail "Port $Port in use by $processName (PID: $($listener.OwningProcess))"
            return $false
        }
    }
    else {
        Write-Ok "Port $Port is available"
        return $true
    }
}

function Assert-PortListening {
    <#
    .SYNOPSIS
        Verifies a TCP port is listening
    #>
    param(
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutSeconds = 30
    )
    
    $endTime = (Get-Date).AddSeconds($TimeoutSeconds)
    
    while ((Get-Date) -lt $endTime) {
        $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        if ($listener) {
            Write-Ok "Port $Port is listening"
            return $true
        }
        Start-Sleep -Milliseconds 500
    }
    
    Write-Fail "Port $Port not listening after $TimeoutSeconds seconds"
    return $false
}

function Assert-Url200 {
    <#
    .SYNOPSIS
        Verifies a URL returns HTTP 200
    #>
    param(
        [Parameter(Mandatory)][string]$Url,
        [int]$TimeoutSeconds = 30,
        [int]$RetryCount = 5
    )
    
    for ($i = 1; $i -le $RetryCount; $i++) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSeconds -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Write-Ok "URL $Url returned 200 OK"
                return $true
            }
        }
        catch {
            Write-Log "Attempt $i/$RetryCount for $Url failed: $_" -Level "WARN"
            if ($i -lt $RetryCount) {
                Start-Sleep -Seconds 2
            }
        }
    }
    
    Write-Fail "URL $Url did not return 200 after $RetryCount attempts"
    return $false
}

function Assert-FileExists {
    <#
    .SYNOPSIS
        Verifies a file exists
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Message = ""
    )
    
    if (Test-Path $Path) {
        Write-Ok "File exists: $Path"
        return $true
    }
    else {
        $msg = if ($Message) { $Message } else { "File not found: $Path" }
        Write-Fail $msg
        return $false
    }
}

function Assert-DirectoryExists {
    <#
    .SYNOPSIS
        Verifies a directory exists, optionally creating it
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Create
    )
    
    if (Test-Path $Path -PathType Container) {
        Write-Ok "Directory exists: $Path"
        return $true
    }
    elseif ($Create) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Ok "Created directory: $Path"
        return $true
    }
    else {
        Write-Fail "Directory not found: $Path"
        return $false
    }
}

function Assert-ServiceExists {
    <#
    .SYNOPSIS
        Verifies a Windows service exists
    #>
    param(
        [Parameter(Mandatory)][string]$ServiceName
    )
    
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    
    if ($service) {
        Write-Ok "Service '$ServiceName' exists (Status: $($service.Status))"
        return $true
    }
    else {
        Write-Fail "Service '$ServiceName' not found"
        return $false
    }
}

function Assert-ServiceRunning {
    <#
    .SYNOPSIS
        Verifies a Windows service is running
    #>
    param(
        [Parameter(Mandatory)][string]$ServiceName,
        [int]$TimeoutSeconds = 30
    )
    
    $endTime = (Get-Date).AddSeconds($TimeoutSeconds)
    
    while ((Get-Date) -lt $endTime) {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            Write-Ok "Service '$ServiceName' is running"
            return $true
        }
        Start-Sleep -Seconds 1
    }
    
    Write-Fail "Service '$ServiceName' not running after $TimeoutSeconds seconds"
    return $false
}

# ============================================================================
# MARKER FILE FUNCTIONS
# ============================================================================

function Set-Marker {
    <#
    .SYNOPSIS
        Creates a marker file indicating step completion
    #>
    param(
        [Parameter(Mandatory)][string]$Name
    )
    
    $markerPath = Join-Path $script:MARKER_DIR "$Name.txt"
    $content = @"
Step: $Name
Completed: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
User: $env:USERNAME
Computer: $env:COMPUTERNAME
"@
    Set-Content -Path $markerPath -Value $content -Encoding UTF8
    Write-Ok "Marker set: $Name"
}

function Test-Marker {
    <#
    .SYNOPSIS
        Tests if a marker file exists
    #>
    param(
        [Parameter(Mandatory)][string]$Name
    )
    
    $markerPath = Join-Path $script:MARKER_DIR "$Name.txt"
    return (Test-Path $markerPath)
}

function Get-MarkerTime {
    <#
    .SYNOPSIS
        Gets the timestamp of a marker file
    #>
    param(
        [Parameter(Mandatory)][string]$Name
    )
    
    $markerPath = Join-Path $script:MARKER_DIR "$Name.txt"
    if (Test-Path $markerPath) {
        return (Get-Item $markerPath).LastWriteTime
    }
    return $null
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Get-PolyTraderRoot {
    return $script:POLYTRADER_ROOT
}

function Get-LogDirectory {
    return $script:LOG_DIR
}

function Get-DataDirectory {
    return $script:DATA_DIR
}

function Get-LatestLog {
    <#
    .SYNOPSIS
        Gets the most recent log file for a step
    #>
    param(
        [Parameter(Mandatory)][string]$StepPattern
    )
    
    $logs = Get-ChildItem -Path $script:LOG_DIR -Filter "STEP${StepPattern}*.log" | 
            Sort-Object LastWriteTime -Descending
    
    if ($logs) {
        return $logs[0].FullName
    }
    return $null
}

function Show-LogTail {
    <#
    .SYNOPSIS
        Shows the last N lines of a log file
    #>
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [int]$Lines = 50
    )
    
    if (Test-Path $LogPath) {
        Write-Host ""
        Write-Host "Last $Lines lines of $(Split-Path $LogPath -Leaf):" -ForegroundColor $script:Colors.Header
        Write-Host ("-" * 60) -ForegroundColor $script:Colors.Dim
        Get-Content $LogPath -Tail $Lines | ForEach-Object {
            Write-Host $_ -ForegroundColor $script:Colors.Dim
        }
        Write-Host ("-" * 60) -ForegroundColor $script:Colors.Dim
    }
}

function Test-IsAdmin {
    <#
    .SYNOPSIS
        Tests if running as administrator
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdminPrivileges {
    <#
    .SYNOPSIS
        Restarts the script with admin privileges
    #>
    param(
        [Parameter(Mandatory)][string]$ScriptPath
    )
    
    if (-not (Test-IsAdmin)) {
        Write-Warn "Requesting administrator privileges..."
        Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$ScriptPath`""
        exit
    }
}

function Get-FreePort {
    <#
    .SYNOPSIS
        Finds an available TCP port
    #>
    param(
        [int]$StartPort = 8000,
        [int]$EndPort = 9000
    )
    
    for ($port = $StartPort; $port -le $EndPort; $port++) {
        $listener = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if (-not $listener) {
            return $port
        }
    }
    
    throw "No free ports found in range $StartPort-$EndPort"
}

function Wait-ForCondition {
    <#
    .SYNOPSIS
        Waits for a condition to be true
    #>
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [string]$Description = "condition",
        [int]$TimeoutSeconds = 60,
        [int]$IntervalMs = 500
    )
    
    Write-Status "Waiting for $Description..." -Icon "Arrow"
    $endTime = (Get-Date).AddSeconds($TimeoutSeconds)
    
    while ((Get-Date) -lt $endTime) {
        if (& $Condition) {
            Write-Ok "$Description met"
            return $true
        }
        Start-Sleep -Milliseconds $IntervalMs
    }
    
    Write-Fail "Timeout waiting for $Description"
    return $false
}

function Get-ProcessOutput {
    <#
    .SYNOPSIS
        Gets the output of a process
    #>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )
    
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $FilePath
    $pinfo.Arguments = $ArgumentList -join " "
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $pinfo
    $process.Start() | Out-Null
    
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    
    return [PSCustomObject]@{
        ExitCode = $process.ExitCode
        Stdout   = $stdout
        Stderr   = $stderr
    }
}

# ============================================================================
# ENV FILE MANAGEMENT
# ============================================================================

function Set-EnvFile {
    <#
    .SYNOPSIS
        Creates or updates a .env file
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Values
    )
    
    $content = $Values.GetEnumerator() | ForEach-Object {
        "$($_.Key)=$($_.Value)"
    }
    
    Set-Content -Path $Path -Value ($content -join "`n") -Encoding UTF8
    Write-Ok "Created env file: $Path"
}

function Get-EnvFile {
    <#
    .SYNOPSIS
        Reads a .env file into a hashtable
    #>
    param(
        [Parameter(Mandatory)][string]$Path
    )
    
    $result = @{}
    
    if (Test-Path $Path) {
        Get-Content $Path | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') {
                $result[$matches[1]] = $matches[2]
            }
        }
    }
    
    return $result
}

# ============================================================================
# SERVICE MANAGEMENT
# ============================================================================

function Install-NssmService {
    <#
    .SYNOPSIS
        Installs a Windows service using NSSM
    #>
    param(
        [Parameter(Mandatory)][string]$ServiceName,
        [Parameter(Mandatory)][string]$Executable,
        [string]$Arguments = "",
        [string]$WorkingDirectory = "",
        [string]$Description = "",
        [string]$StdoutLog = "",
        [string]$StderrLog = ""
    )
    
    $nssmPath = Join-Path $script:POLYTRADER_ROOT "tools\nssm.exe"
    
    if (-not (Test-Path $nssmPath)) {
        throw "NSSM not found at $nssmPath"
    }
    
    # Remove existing service if present
    & $nssmPath stop $ServiceName 2>$null
    & $nssmPath remove $ServiceName confirm 2>$null
    
    # Install new service
    & $nssmPath install $ServiceName $Executable $Arguments
    
    if ($WorkingDirectory) {
        & $nssmPath set $ServiceName AppDirectory $WorkingDirectory
    }
    
    if ($Description) {
        & $nssmPath set $ServiceName Description $Description
    }
    
    if ($StdoutLog) {
        & $nssmPath set $ServiceName AppStdout $StdoutLog
        & $nssmPath set $ServiceName AppStdoutCreationDisposition 4
    }
    
    if ($StderrLog) {
        & $nssmPath set $ServiceName AppStderr $StderrLog
        & $nssmPath set $ServiceName AppStderrCreationDisposition 4
    }
    
    # Set restart behavior
    & $nssmPath set $ServiceName AppRestartDelay 5000
    & $nssmPath set $ServiceName AppThrottle 10000
    
    Write-Ok "Service '$ServiceName' installed"
}

function Start-NssmService {
    <#
    .SYNOPSIS
        Starts a service installed via NSSM
    #>
    param(
        [Parameter(Mandatory)][string]$ServiceName
    )
    
    $nssmPath = Join-Path $script:POLYTRADER_ROOT "tools\nssm.exe"
    & $nssmPath start $ServiceName
}

function Stop-NssmService {
    <#
    .SYNOPSIS
        Stops a service installed via NSSM
    #>
    param(
        [Parameter(Mandatory)][string]$ServiceName
    )
    
    $nssmPath = Join-Path $script:POLYTRADER_ROOT "tools\nssm.exe"
    & $nssmPath stop $ServiceName
}

# ============================================================================
# END OF LIBRARY
# ============================================================================
# All functions and variables are available when dot-sourced via:
#   . "$ScriptDir\_lib.ps1"