# PolyTrader Runbook

## Installation

### Prerequisites

- Windows Server 2019 Datacenter (or Windows 10/11)
- Administrator access
- Internet connection
- At least 5GB free disk space

### Step-by-Step Installation

```powershell
# 1. Extract PolyTrader.zip to Desktop
# 2. Open PowerShell as Administrator
# 3. Navigate to scripts directory
cd $env:USERPROFILE\Desktop\PolyTrader\ops\windows

# 4. Run installation scripts in order
.\00_preflight_check.ps1      # System validation
.\01_install_dependencies.ps1  # Python, Node.js, PostgreSQL
.\02_setup_repo.ps1           # Virtual environment, npm packages
.\03_setup_database.ps1       # Database schema
.\04_setup_api.ps1            # FastAPI backend
.\05_setup_worker.ps1         # Trading worker
.\06_setup_dashboard.ps1      # Next.js dashboard
.\07_register_services.ps1    # Windows services
.\08_final_verification.ps1   # Final checks
```

### Post-Installation

1. **Configure Polymarket Credentials**
   ```
   Edit: backend\.env
   
   POLYMARKET_API_KEY=your_key_here
   POLYMARKET_API_SECRET=your_secret_here
   POLYMARKET_PRIVATE_KEY=your_private_key_here
   POLYMARKET_FUNDER_ADDRESS=your_address_here
   ```

2. **Review Risk Settings**
   - Access: http://localhost:3000/config
   - Adjust for your risk tolerance

3. **Start Trading**
   - Click "Start" button in dashboard
   - Or: `POST http://localhost:8000/v1/admin/bot/start`

## Daily Operations

### Starting the System

```batch
# Option 1: Use batch file
start_services.bat

# Option 2: Manual service start
net start PolyTrader-API
net start PolyTrader-UI
net start PolyTrader-Worker  # Only after configuring credentials
```

### Stopping the System

```batch
# Option 1: Use batch file
stop_services.bat

# Option 2: Via dashboard
# Click "Stop" button (cancels all open orders)

# Option 3: Emergency stop
POST http://localhost:8000/v1/admin/emergency-stop
```

### Monitoring

#### Dashboard URLs
- **Overview**: http://localhost:3000
- **Trades**: http://localhost:3000/trades
- **Exposure**: http://localhost:3000/exposure
- **Health**: http://localhost:3000/health
- **Config**: http://localhost:3000/config

#### API Health Endpoints
```bash
# Basic health
GET http://localhost:8000/health

# Detailed health
GET http://localhost:8000/health/detailed

# Bot state
GET http://localhost:8000/v1/admin/bot/state
```

### Checking Status

```powershell
# Run status dashboard
.\ops\windows\99_status_dashboard.ps1

# With log output on failure
.\ops\windows\99_status_dashboard.ps1 -TailOnFailure
```

## Configuration Management

### Viewing Current Config

```bash
GET http://localhost:8000/v1/config/
```

### Updating Config

```bash
PUT http://localhost:8000/v1/config/daily_loss_limit_usd
Content-Type: application/json

{
  "value": 30,
  "user": "admin"
}
```

### Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `portfolio_trade_pct` | 5 | % of portfolio per trade |
| `max_market_usd` | 100 | Maximum USD per market |
| `daily_loss_limit_usd` | 25 | Daily loss halt threshold |
| `take_profit_pct` | 8 | Take profit percentage |
| `stop_loss_pct` | 5 | Stop loss percentage |
| `max_open_positions` | 5 | Maximum concurrent positions |

## Risk Management

### Circuit Breakers

Circuit breakers automatically halt trading when issues are detected:

| Breaker | Trigger | Resolution |
|---------|---------|------------|
| `stale_data` | Price data > 60s old | Wait for data refresh |
| `websocket_disconnect` | Connection lost | Automatic reconnect |
| `high_error_rate` | >10% error rate | Investigate logs |
| `reconciliation_mismatch` | Order state mismatch | Manual review |
| `daily_loss_limit` | Loss >= limit | Next trading day |

### Resetting Circuit Breakers

```bash
POST http://localhost:8000/v1/admin/circuit-breakers/stale_data/reset
```

### Daily Loss Tracking

```bash
# Check today's PnL
GET http://localhost:8000/v1/positions/pnl
```

## Troubleshooting

### Common Issues

#### Services Won't Start
```powershell
# Check service status
Get-Service PolyTrader-*

# Check logs
Get-Content logs\api_stderr.log -Tail 50
Get-Content logs\worker_stderr.log -Tail 50
```

#### API Returns 500 Errors
1. Check database connection
2. Verify `.env` configuration
3. Review `logs\api_stderr.log`

#### Dashboard Shows "Loading..."
1. Verify API is running: `curl http://localhost:8000/health`
2. Check browser console for errors
3. Verify CORS configuration

#### Bot Not Trading
1. Check bot state is `RUNNING`
2. Verify no circuit breakers tripped
3. Confirm Polymarket credentials configured
4. Check worker service is running

### Log Locations

| Log | Location |
|-----|----------|
| Install logs | `install-logs\STEP*.log` |
| API stdout | `logs\api_stdout.log` |
| API stderr | `logs\api_stderr.log` |
| Worker stdout | `logs\worker_stdout.log` |
| Worker stderr | `logs\worker_stderr.log` |
| UI stdout | `logs\ui_stdout.log` |

## Maintenance

### Database Backup

```powershell
# Backup database
pg_dump -U polytrader polytrader > backup.sql

# Restore
psql -U polytrader polytrader < backup.sql
```

### Log Rotation

Logs are appended continuously. Periodically archive old logs:

```powershell
# Archive logs older than 7 days
Get-ChildItem logs\*.log | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-7)} | Move-Item -Destination logs\archive\
```

### Updating Configuration

1. Stop trading (Pause or Stop)
2. Update `.env` or database config
3. Restart affected service
4. Resume trading

## Emergency Procedures

### Complete System Halt

```bash
# 1. Emergency stop (cancels all orders)
POST http://localhost:8000/v1/admin/emergency-stop

# 2. Stop all services
stop_services.bat
```

### Recovery from Halt

1. Identify cause of halt (check logs)
2. Resolve underlying issue
3. Reset circuit breakers if needed
4. Start services
5. Start bot via dashboard

### Manual Order Cancellation

```bash
# Cancel specific order
DELETE http://localhost:8000/v1/trading/orders/{order_id}

# Cancel all orders
POST http://localhost:8000/v1/trading/orders/cancel-all
```
