# PolyTrader

Production-grade Polymarket autotrader for BTC/ETH/SOL 15-minute markets.

## Overview

PolyTrader is a complete trading system that:
- Discovers and trades Polymarket 15-minute crypto prediction markets
- Uses Coinbase price data for technical analysis
- Provides a web dashboard for monitoring and control
- Implements comprehensive risk management
- Runs as Windows services for production deployment

## Features

### Trading
- **LIVE Trading** on Polymarket via official CLOB API
- **Technical Analysis** using Coinbase 15-minute candles
- **Maker-first execution** with smart order management
- **Automatic position exit** with take-profit and stop-loss

### Risk Management
- Configurable position sizes (default: 5% of portfolio)
- Maximum per-market exposure limits
- Correlation basket caps across BTC/ETH/SOL
- Daily loss limits with automatic halt
- Circuit breakers for system issues

### Dashboard
- Real-time price display with 15m change
- Bot control (Start/Pause/Stop)
- Trade history and attribution
- Exposure and risk metrics
- System health monitoring
- Installation status page

## Quick Start

### Prerequisites
- Windows Server 2019+ or Windows 10/11
- Administrator access
- Internet connection (for Coinbase and Polymarket APIs)

### Installation

1. Extract `PolyTrader.zip` to `C:\Users\<YOU>\Desktop\PolyTrader\`

2. Open PowerShell as Administrator

3. Run installation scripts in order:
```powershell
cd Desktop\PolyTrader\ops\windows

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

4. Configure Polymarket credentials in `backend\.env`

5. Start services and access dashboard at http://localhost:3000

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Dashboard (Next.js)                      │
│                        http://localhost:3000                     │
└─────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                         API (FastAPI)                            │
│                        http://localhost:8000                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │  Prices  │ │ Markets  │ │ Trading  │ │  Admin   │           │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘           │
└─────────────────────────────────────────────────────────────────┘
                                  │
         ┌────────────────────────┼────────────────────────┐
         ▼                        ▼                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Price Service  │    │ Market Service  │    │ Trading Worker  │
│   (Coinbase)    │    │  (Polymarket)   │    │   (Strategy)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                        │                        │
         └────────────────────────┼────────────────────────┘
                                  ▼
                    ┌─────────────────────────┐
                    │      PostgreSQL         │
                    │   (Prices, Candles,     │
                    │   Markets, Orders,      │
                    │   Positions, Config)    │
                    └─────────────────────────┘
```

## Configuration

### Environment Variables (backend/.env)

```bash
# Database
DATABASE_URL=postgresql://polytrader:password@localhost:5432/polytrader

# Polymarket (REQUIRED for live trading)
POLYMARKET_API_KEY=your_api_key
POLYMARKET_API_SECRET=your_api_secret
POLYMARKET_PRIVATE_KEY=your_private_key
POLYMARKET_FUNDER_ADDRESS=your_address

# Risk Settings
PORTFOLIO_TRADE_PCT=5
MAX_MARKET_USD=100
DAILY_LOSS_LIMIT_USD=25
TAKE_PROFIT_PCT=8
STOP_LOSS_PCT=5
```

### Risk Configuration (Database)

| Parameter | Default | Description |
|-----------|---------|-------------|
| portfolio_trade_pct | 5 | % of portfolio per trade |
| max_market_usd | 100 | Max USD per market |
| correlation_max_basket_pct | 35 | Max crypto basket exposure |
| daily_loss_limit_usd | 25 | Daily loss halt threshold |
| take_profit_pct | 8 | Take profit % (net of fees) |
| stop_loss_pct | 5 | Stop loss % (net of fees) |

## API Endpoints

### Health
- `GET /health` - Basic health check
- `GET /health/detailed` - Detailed component status

### Prices
- `GET /v1/prices/latest` - All latest prices
- `GET /v1/prices/latest/{symbol}` - Specific asset price
- `GET /v1/prices/candles/{symbol}` - 15-minute candles

### Markets
- `GET /v1/markets/` - All discovered markets
- `GET /v1/markets/discover` - Trigger market discovery
- `GET /v1/markets/tradable/{asset}` - Get tradable market

### Trading
- `POST /v1/trading/orders` - Place order
- `DELETE /v1/trading/orders/{id}` - Cancel order
- `GET /v1/trading/orders` - Get orders

### Admin
- `GET /v1/admin/bot/state` - Get bot state
- `POST /v1/admin/bot/start` - Start bot
- `POST /v1/admin/bot/pause` - Pause bot
- `POST /v1/admin/bot/stop` - Stop bot
- `POST /v1/admin/emergency-stop` - Emergency stop

### Config
- `GET /v1/config/` - All configuration
- `PUT /v1/config/{key}` - Update config value

### Install Status
- `GET /v1/install/status` - Installation status
- `GET /v1/install/logs/tail` - Log tail

## Services

| Service | Port | Description |
|---------|------|-------------|
| PolyTrader-API | 8000 | FastAPI backend |
| PolyTrader-Worker | - | Trading engine |
| PolyTrader-UI | 3000 | Next.js dashboard |

### Service Management

```batch
# Start all services
start_services.bat

# Stop all services
stop_services.bat

# Check status
service_status.bat
```

## Bot States

| State | Description |
|-------|-------------|
| RUNNING | Actively trading |
| PAUSED | No new trades, monitoring only |
| STOPPED | Completely stopped |
| HALTED_DAILY_LOSS | Stopped due to daily loss limit |
| HALTED_CIRCUIT_BREAKER | Stopped due to system issue |

## Circuit Breakers

- `stale_data` - Price data too old
- `websocket_disconnect` - Connection lost
- `high_error_rate` - Too many errors
- `reconciliation_mismatch` - Order state mismatch
- `daily_loss_limit` - Loss limit reached
- `api_rate_limit` - API rate limited

## File Structure

```
PolyTrader/
├── ops/windows/          # Installation scripts
│   ├── _lib.ps1          # Shared functions
│   ├── 00-08_*.ps1       # Install steps
│   ├── 90_build_zip.ps1  # ZIP builder
│   └── 99_status_dashboard.ps1
├── backend/
│   ├── app/
│   │   ├── main.py       # FastAPI app
│   │   ├── api/routes/   # API endpoints
│   │   ├── core/         # Config, logging
│   │   ├── db/           # Database models
│   │   ├── services/     # Business logic
│   │   └── workers/      # Trading worker
│   ├── requirements.txt
│   └── .env
├── dashboard/
│   ├── src/app/          # Next.js pages
│   ├── src/components/   # React components
│   └── package.json
├── data/                 # Marker files
├── logs/                 # Service logs
├── install-logs/         # Installation logs
├── tools/                # NSSM, etc.
├── README.md
├── RUNBOOK.md
└── TROUBLESHOOTING.md
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues.

### Quick Checks

```powershell
# Run status dashboard
.\ops\windows\99_status_dashboard.ps1

# With log tail on failure
.\ops\windows\99_status_dashboard.ps1 -TailOnFailure
```

## License

Proprietary - All Rights Reserved

## Disclaimer

This software is for educational purposes. Trading involves significant risk of loss. Past performance does not guarantee future results. Use at your own risk.
