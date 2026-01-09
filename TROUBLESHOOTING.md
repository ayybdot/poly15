# PolyTrader Troubleshooting Guide

## Installation Issues

### PowerShell Script Errors

#### "Script cannot be loaded because running scripts is disabled"
```powershell
# Solution: Set execution policy for current session
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# Or permanently (requires admin)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
```

#### "Access denied" or "Requires administrator"
- Right-click PowerShell → "Run as Administrator"
- Some scripts (01, 07) require admin privileges

### Dependency Installation

#### Python installation fails
```powershell
# Manual installation
1. Download from https://www.python.org/downloads/
2. Run installer with "Add to PATH" checked
3. Restart PowerShell
4. Verify: python --version
```

#### Node.js installation fails
```powershell
# Manual installation
1. Download LTS from https://nodejs.org/
2. Run installer
3. Restart PowerShell
4. Verify: node --version && npm --version
```

#### PostgreSQL installation fails
```powershell
# Manual installation
1. Download from https://www.postgresql.org/download/windows/
2. Run installer
3. Note the password you set for 'postgres' user
4. Save password to data\.pgpassword
```

### Port Conflicts

#### "Port 8000 already in use"
```powershell
# Find process using port
Get-NetTCPConnection -LocalPort 8000 | Select-Object OwningProcess
Get-Process -Id <process_id>

# Kill if safe
Stop-Process -Id <process_id> -Force
```

#### "Port 5432 already in use"
PostgreSQL may already be running from a previous installation.
```powershell
# Check PostgreSQL service
Get-Service postgresql*
```

### Database Issues

#### "Connection refused" to PostgreSQL
```powershell
# 1. Check service is running
Get-Service postgresql*
Start-Service postgresql-x64-16  # or your version

# 2. Check port is listening
Test-NetConnection -ComputerName localhost -Port 5432

# 3. Verify credentials
# Check data\db_credentials.txt
```

#### "Authentication failed"
```powershell
# Reset password via psql as postgres user
psql -U postgres
ALTER USER polytrader WITH PASSWORD 'new_password';
\q

# Update backend\.env with new password
```

#### "Database does not exist"
```powershell
# Create database manually
psql -U postgres
CREATE DATABASE polytrader;
CREATE USER polytrader WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE polytrader TO polytrader;
\q
```

### npm/Node Issues

#### "npm ERR! code ENOENT"
```powershell
# Clear npm cache and reinstall
cd dashboard
Remove-Item -Recurse -Force node_modules
Remove-Item package-lock.json
npm cache clean --force
npm install
```

#### Build fails with TypeScript errors
```powershell
# Check TypeScript version
npx tsc --version

# Try rebuilding
npm run build 2>&1 | Tee-Object build.log
```

## Runtime Issues

### API Issues

#### API returns 500 Internal Server Error
1. Check `logs\api_stderr.log` for stack trace
2. Common causes:
   - Database connection failed
   - Missing environment variable
   - Import error

```powershell
# Test database connection
$env:PYTHONPATH = "$PWD\backend"
python -c "from app.db.database import engine; print('OK')"
```

#### API health check fails
```powershell
# Test directly
Invoke-WebRequest http://localhost:8000/health

# Check if uvicorn is running
Get-Process | Where-Object {$_.ProcessName -like "*python*"}
```

### Dashboard Issues

#### Dashboard shows blank page
1. Check browser console (F12) for errors
2. Verify API is accessible: http://localhost:8000/health
3. Check `logs\ui_stderr.log`

#### "Failed to fetch" errors
```javascript
// CORS issue - verify API allows localhost:3000
// Check next.config.js rewrites configuration
```

#### Dashboard stuck on "Loading..."
1. API not running
2. Network/firewall blocking
3. Wrong API URL in environment

### Trading Issues

#### Bot won't start trading
1. **Check state**: Should be `RUNNING`
   ```bash
   GET http://localhost:8000/v1/admin/bot/state
   ```

2. **Check circuit breakers**: None should be tripped
   ```bash
   GET http://localhost:8000/v1/admin/circuit-breakers
   ```

3. **Check credentials**: Polymarket keys must be configured
   - Verify in `backend\.env`

4. **Check worker service**: Must be running
   ```powershell
   Get-Service PolyTrader-Worker
   ```

#### Orders not being placed
1. Check risk limits not exceeded
2. Verify market has sufficient liquidity
3. Check position limits not reached
4. Review `logs\worker_stderr.log`

#### Stale data warnings
```powershell
# Check price service
GET http://localhost:8000/v1/prices/status

# Causes:
# - Coinbase API unreachable
# - Network issues
# - Rate limiting
```

### Service Issues

#### Service won't start
```powershell
# Check service configuration
sc.exe qc PolyTrader-API

# Check NSSM configuration
.\tools\nssm.exe dump PolyTrader-API

# Check Event Viewer
Get-EventLog -LogName Application -Source "PolyTrader*" -Newest 20
```

#### Service keeps restarting
1. Check `logs\*_stderr.log` for crash reason
2. Common causes:
   - Missing dependencies
   - Configuration errors
   - Resource exhaustion

```powershell
# Monitor service status
while($true) { 
    Get-Service PolyTrader-* | Format-Table Name, Status
    Start-Sleep 5
}
```

#### Service stops unexpectedly
```powershell
# Check Windows Event Log
Get-EventLog -LogName System -Source "Service Control Manager" -Newest 20 | 
    Where-Object {$_.Message -like "*PolyTrader*"}
```

## Performance Issues

### High CPU usage
1. Check for infinite loops in logs
2. Verify polling intervals are appropriate
3. Check database query performance

### High memory usage
```powershell
# Monitor process memory
Get-Process | Where-Object {$_.ProcessName -like "*python*" -or $_.ProcessName -like "*node*"} | 
    Select-Object ProcessName, WorkingSet64
```

### Slow API responses
1. Check database indexes
2. Monitor PostgreSQL performance
3. Review query patterns

## Network Issues

### Cannot reach Coinbase API
```powershell
# Test connectivity
Test-NetConnection -ComputerName api.coinbase.com -Port 443

# Check firewall
Get-NetFirewallRule | Where-Object {$_.DisplayName -like "*python*"}
```

### Cannot reach Polymarket API
```powershell
# Test connectivity
Test-NetConnection -ComputerName clob.polymarket.com -Port 443

# Check if API key is valid
# Review API response in logs
```

### WebSocket disconnections
1. Check network stability
2. Verify firewall allows WebSocket
3. Check for proxy interference

## Diagnostic Commands

### Quick Health Check
```powershell
# All-in-one status
.\ops\windows\99_status_dashboard.ps1 -TailOnFailure
```

### Database Diagnostics
```sql
-- Connect to database
psql -U polytrader -d polytrader

-- Check table sizes
SELECT relname, pg_size_pretty(pg_total_relation_size(relid))
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC;

-- Check recent prices
SELECT * FROM prices ORDER BY timestamp DESC LIMIT 10;

-- Check bot state
SELECT * FROM bot_state ORDER BY id DESC LIMIT 1;

-- Check circuit breakers
SELECT * FROM circuit_breakers;
```

### Log Analysis
```powershell
# Find errors in all logs
Get-ChildItem logs\*.log | ForEach-Object {
    $errors = Select-String -Path $_.FullName -Pattern "ERROR|FAIL|Exception" -Context 2,2
    if ($errors) {
        Write-Host "`n=== $($_.Name) ===" -ForegroundColor Red
        $errors
    }
}

# Monitor logs in real-time
Get-Content logs\api_stderr.log -Wait -Tail 50
```

## Getting Help

### Information to Collect
1. Output of `99_status_dashboard.ps1`
2. Relevant log files from `logs\` and `install-logs\`
3. Configuration (redact sensitive values)
4. Steps to reproduce the issue

### Log Collection Script
```powershell
# Create diagnostic bundle
$diagDir = "diagnostics_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory $diagDir

# Copy logs
Copy-Item logs\*.log $diagDir\
Copy-Item install-logs\*.log $diagDir\

# System info
Get-ComputerInfo | Out-File "$diagDir\system_info.txt"
Get-Service PolyTrader-* | Out-File "$diagDir\services.txt"

# Create ZIP
Compress-Archive $diagDir "$diagDir.zip"
Remove-Item -Recurse $diagDir
```
