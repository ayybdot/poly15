#Requires -Version 5.1
<#
.SYNOPSIS
    Step 03: Setup Database
.DESCRIPTION
    Creates the PostgreSQL database, user, and all required tables for PolyTrader.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\_lib.ps1"

if (-not (Test-Marker -Name "repo_ok")) {
    Write-Host "ERROR: Repository not set up. Run 02_setup_repo.ps1 first." -ForegroundColor Red
    exit 1
}

$logFile = Start-Log -StepNumber "03" -StepName "setup_database"
Write-StepHeader "03" "SETUP DATABASE"

$root = Get-PolyTraderRoot
$dataDir = Join-Path $root "data"
$backendDir = Join-Path $root "backend"

$DB_NAME = "polytrader"
$DB_USER = "polytrader"
$DB_HOST = "localhost"
$DB_PORT = "5432"

# Check if we already have credentials from a previous run
$credFile = Join-Path $dataDir "db_credentials.txt"
$envFile = Join-Path $backendDir ".env"

if ((Test-Path $credFile) -and (Test-Path $envFile)) {
    # Extract existing password from .env file
    $envContent = Get-Content $envFile -Raw
    if ($envContent -match 'DATABASE_URL=postgresql://polytrader:([^@]+)@') {
        $DB_PASSWORD = $Matches[1]
        Write-Host "  [i] Using existing database password from .env" -ForegroundColor Cyan
    }
    else {
        $DB_PASSWORD = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 20 | ForEach-Object { [char]$_ })
        Write-Host "  [i] Generated new database password" -ForegroundColor Cyan
    }
}
else {
    $DB_PASSWORD = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 20 | ForEach-Object { [char]$_ })
    Write-Host "  [i] Generated new database password" -ForegroundColor Cyan
}

try {
    Write-Section "Check PostgreSQL Service"
    
    $pgService = Get-Service -Name "postgresql*" -ErrorAction SilentlyContinue
    if ($pgService) {
        Write-Ok "PostgreSQL service found: $($pgService.Name)"
        if ($pgService.Status -ne "Running") {
            Start-Service $pgService.Name
            Start-Sleep -Seconds 3
        }
        Write-Ok "PostgreSQL service is running"
    }
    else {
        Write-Warn "PostgreSQL service not found - assuming manual installation"
    }
    
    Write-Section "Locate PostgreSQL Client"
    
    $psqlPath = $null
    $psqlCmd = Get-Command psql -ErrorAction SilentlyContinue
    if ($psqlCmd) {
        $psqlPath = $psqlCmd.Source
    }
    else {
        $commonPaths = @(
            "C:\Program Files\PostgreSQL\16\bin\psql.exe",
            "C:\Program Files\PostgreSQL\15\bin\psql.exe",
            "C:\Program Files\PostgreSQL\14\bin\psql.exe"
        )
        foreach ($path in $commonPaths) {
            if (Test-Path $path) {
                $psqlPath = $path
                break
            }
        }
    }
    
    if (-not $psqlPath) {
        throw "PostgreSQL client (psql) not found"
    }
    Write-Ok "Found psql at: $psqlPath"
    
    Write-Section "PostgreSQL Authentication"
    
    $pgPasswordFile = Join-Path $dataDir ".pgpassword"
    $pgPassword = "postgres"
    if (Test-Path $pgPasswordFile) {
        $pgPassword = (Get-Content $pgPasswordFile -Raw).Trim()
    }
    $env:PGPASSWORD = $pgPassword
    
    # Test postgres connection first
    Write-Status "Testing postgres admin connection..." -Icon "Arrow"
    $testConn = & $psqlPath -h $DB_HOST -p $DB_PORT -U postgres -t -c "SELECT 1;" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  Cannot connect to PostgreSQL as 'postgres' user." -ForegroundColor Red
        Write-Host "  Please save your postgres password to: $pgPasswordFile" -ForegroundColor Yellow
        Write-Host ""
        throw "PostgreSQL admin authentication failed. Create file $pgPasswordFile with your postgres password."
    }
    Write-Ok "PostgreSQL admin connection OK"
    
    Write-Section "Create Database and User"
    
    # Create user (drop first if exists to ensure clean password)
    Write-Status "Creating database user..." -Icon "Arrow"
    
    # Temporarily allow errors so NOTICE messages don't terminate the script
    $ErrorActionPreference = "Continue"
    
    $dropResult = & $psqlPath -h $DB_HOST -p $DB_PORT -U postgres -c "DROP USER IF EXISTS $DB_USER;" 2>&1
    Write-Log "Drop user output: $dropResult"
    
    $createUserResult = & $psqlPath -h $DB_HOST -p $DB_PORT -U postgres -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';" 2>&1
    Write-Log "Create user output: $createUserResult"
    
    # Restore strict error handling
    $ErrorActionPreference = "Stop"
    
    # Check if it actually failed (not just a notice/warning)
    if ($createUserResult -match "ERROR:") {
        throw "Failed to create database user: $createUserResult"
    }
    Write-Ok "Created user: $DB_USER"
    
    # Create database
    Write-Status "Creating database..." -Icon "Arrow"
    
    $ErrorActionPreference = "Continue"
    $dbExists = & $psqlPath -h $DB_HOST -p $DB_PORT -U postgres -t -c "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';" 2>&1
    $ErrorActionPreference = "Stop"
    
    if ($dbExists -notmatch "1") {
        $ErrorActionPreference = "Continue"
        $createDbResult = & $psqlPath -h $DB_HOST -p $DB_PORT -U postgres -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>&1
        $ErrorActionPreference = "Stop"
        
        if ($createDbResult -match "ERROR:") {
            Write-Log "Create database output: $createDbResult"
            throw "Failed to create database: $createDbResult"
        }
        Write-Ok "Created database: $DB_NAME"
    }
    else {
        Write-Ok "Database already exists: $DB_NAME"
        $ErrorActionPreference = "Continue"
        & $psqlPath -h $DB_HOST -p $DB_PORT -U postgres -c "ALTER DATABASE $DB_NAME OWNER TO $DB_USER;" 2>&1 | Out-Null
        $ErrorActionPreference = "Stop"
    }
    
    # Grant privileges
    Write-Status "Granting privileges..." -Icon "Arrow"
    $ErrorActionPreference = "Continue"
    & $psqlPath -h $DB_HOST -p $DB_PORT -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" 2>&1 | Out-Null
    & $psqlPath -h $DB_HOST -p $DB_PORT -U postgres -d $DB_NAME -c "GRANT ALL ON SCHEMA public TO $DB_USER;" 2>&1 | Out-Null
    $ErrorActionPreference = "Stop"
    Write-Ok "Privileges granted"
    
    Write-Section "Create Database Tables"
    $env:PGPASSWORD = $DB_PASSWORD
    
    $schemaSql = @"
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS bot_state (
    id SERIAL PRIMARY KEY,
    state VARCHAR(50) NOT NULL DEFAULT 'STOPPED',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_by VARCHAR(100),
    reason TEXT
);
INSERT INTO bot_state (state, reason) SELECT 'STOPPED', 'Initial state' WHERE NOT EXISTS (SELECT 1 FROM bot_state);

CREATE TABLE IF NOT EXISTS audit_log (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    event_type VARCHAR(100) NOT NULL,
    details JSONB,
    user_id VARCHAR(100),
    ip_address VARCHAR(50)
);
CREATE INDEX IF NOT EXISTS idx_audit_log_ts ON audit_log(timestamp DESC);

CREATE TABLE IF NOT EXISTS prices (
    id SERIAL PRIMARY KEY,
    symbol VARCHAR(20) NOT NULL,
    price DECIMAL(20, 8) NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    source VARCHAR(50) DEFAULT 'coinbase'
);
CREATE INDEX IF NOT EXISTS idx_prices_symbol_ts ON prices(symbol, timestamp DESC);

CREATE TABLE IF NOT EXISTS candles (
    id SERIAL PRIMARY KEY,
    symbol VARCHAR(20) NOT NULL,
    timeframe VARCHAR(10) DEFAULT '15m',
    open_time TIMESTAMP WITH TIME ZONE NOT NULL,
    close_time TIMESTAMP WITH TIME ZONE NOT NULL,
    open DECIMAL(20, 8) NOT NULL,
    high DECIMAL(20, 8) NOT NULL,
    low DECIMAL(20, 8) NOT NULL,
    close DECIMAL(20, 8) NOT NULL,
    volume DECIMAL(30, 8) DEFAULT 0,
    UNIQUE(symbol, timeframe, open_time)
);
CREATE INDEX IF NOT EXISTS idx_candles_sym_tf_ot ON candles(symbol, timeframe, open_time DESC);

CREATE TABLE IF NOT EXISTS markets (
    id SERIAL PRIMARY KEY,
    condition_id VARCHAR(100) UNIQUE NOT NULL,
    question_id VARCHAR(100),
    slug VARCHAR(255),
    title TEXT NOT NULL,
    description TEXT,
    asset VARCHAR(20) NOT NULL,
    market_type VARCHAR(50),
    end_date TIMESTAMP WITH TIME ZONE,
    active BOOLEAN DEFAULT true,
    yes_token_id VARCHAR(100),
    no_token_id VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_markets_asset ON markets(asset);
CREATE INDEX IF NOT EXISTS idx_markets_active ON markets(active);

CREATE TABLE IF NOT EXISTS market_snapshots (
    id SERIAL PRIMARY KEY,
    market_id INTEGER REFERENCES markets(id),
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    best_bid DECIMAL(10, 4),
    best_ask DECIMAL(10, 4),
    bid_depth DECIMAL(20, 2),
    ask_depth DECIMAL(20, 2),
    spread DECIMAL(10, 6),
    volume_24h DECIMAL(20, 2)
);
CREATE INDEX IF NOT EXISTS idx_snapshots_market_ts ON market_snapshots(market_id, timestamp DESC);

CREATE TABLE IF NOT EXISTS decisions (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    asset VARCHAR(20) NOT NULL,
    market_id INTEGER REFERENCES markets(id),
    direction VARCHAR(10) NOT NULL,
    confidence DECIMAL(5, 4),
    features JSONB,
    risk_checks JSONB,
    signal_source VARCHAR(50),
    executed BOOLEAN DEFAULT false,
    execution_id VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_decisions_ts ON decisions(timestamp DESC);

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    order_id VARCHAR(100) UNIQUE NOT NULL,
    market_id INTEGER REFERENCES markets(id),
    decision_id INTEGER REFERENCES decisions(id),
    side VARCHAR(10) NOT NULL,
    token_id VARCHAR(100) NOT NULL,
    price DECIMAL(10, 4) NOT NULL,
    size DECIMAL(20, 8) NOT NULL,
    filled_size DECIMAL(20, 8) DEFAULT 0,
    status VARCHAR(50) DEFAULT 'pending',
    order_type VARCHAR(20) DEFAULT 'limit',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    filled_at TIMESTAMP WITH TIME ZONE,
    cancelled_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT
);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);

CREATE TABLE IF NOT EXISTS trades (
    id SERIAL PRIMARY KEY,
    trade_id VARCHAR(100) UNIQUE NOT NULL,
    order_id INTEGER REFERENCES orders(id),
    market_id INTEGER REFERENCES markets(id),
    side VARCHAR(10) NOT NULL,
    price DECIMAL(10, 4) NOT NULL,
    size DECIMAL(20, 8) NOT NULL,
    fee DECIMAL(20, 8) DEFAULT 0,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    asset VARCHAR(20)
);
CREATE INDEX IF NOT EXISTS idx_trades_ts ON trades(timestamp DESC);

CREATE TABLE IF NOT EXISTS positions (
    id SERIAL PRIMARY KEY,
    market_id INTEGER REFERENCES markets(id),
    token_id VARCHAR(100) NOT NULL,
    side VARCHAR(10) NOT NULL,
    size DECIMAL(20, 8) NOT NULL,
    avg_entry_price DECIMAL(10, 4) NOT NULL,
    current_price DECIMAL(10, 4),
    unrealized_pnl DECIMAL(20, 8),
    realized_pnl DECIMAL(20, 8) DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    opened_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    closed_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(20) DEFAULT 'open'
);
CREATE INDEX IF NOT EXISTS idx_positions_status ON positions(status);

CREATE TABLE IF NOT EXISTS daily_pnl (
    id SERIAL PRIMARY KEY,
    date DATE UNIQUE NOT NULL,
    realized_pnl DECIMAL(20, 8) DEFAULT 0,
    unrealized_pnl DECIMAL(20, 8) DEFAULT 0,
    fees_paid DECIMAL(20, 8) DEFAULT 0,
    trade_count INTEGER DEFAULT 0,
    win_count INTEGER DEFAULT 0,
    loss_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS risk_metrics (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    total_exposure DECIMAL(20, 8),
    btc_exposure DECIMAL(20, 8),
    eth_exposure DECIMAL(20, 8),
    sol_exposure DECIMAL(20, 8),
    correlation_risk DECIMAL(10, 4),
    daily_loss DECIMAL(20, 8),
    portfolio_value DECIMAL(20, 8)
);
CREATE INDEX IF NOT EXISTS idx_risk_ts ON risk_metrics(timestamp DESC);

CREATE TABLE IF NOT EXISTS config (
    id SERIAL PRIMARY KEY,
    key VARCHAR(100) UNIQUE NOT NULL,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_by VARCHAR(100)
);
INSERT INTO config (key, value, description) VALUES
    ('portfolio_trade_pct', '5', 'Percentage of portfolio per trade'),
    ('max_market_usd', '100', 'Maximum USD per market'),
    ('correlation_max_basket_pct', '35', 'Maximum correlated basket exposure'),
    ('daily_loss_limit_usd', '25', 'Daily loss limit in USD'),
    ('take_profit_pct', '8', 'Take profit percentage'),
    ('stop_loss_pct', '5', 'Stop loss percentage'),
    ('min_liquidity_usd', '500', 'Minimum market liquidity'),
    ('market_close_buffer_minutes', '2', 'Buffer before market close'),
    ('stale_data_threshold_seconds', '60', 'Stale data threshold'),
    ('max_open_positions', '5', 'Maximum open positions'),
    ('llm_advisor_enabled', 'false', 'LLM advisory disabled')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS circuit_breakers (
    id SERIAL PRIMARY KEY,
    breaker_name VARCHAR(100) UNIQUE NOT NULL,
    is_tripped BOOLEAN DEFAULT false,
    trip_reason TEXT,
    trip_count INTEGER DEFAULT 0,
    last_trip TIMESTAMP WITH TIME ZONE,
    last_reset TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
INSERT INTO circuit_breakers (breaker_name) VALUES
    ('stale_data'),('websocket_disconnect'),('high_error_rate'),
    ('reconciliation_mismatch'),('daily_loss_limit'),('api_rate_limit')
ON CONFLICT (breaker_name) DO NOTHING;

CREATE TABLE IF NOT EXISTS health_checks (
    id SERIAL PRIMARY KEY,
    component VARCHAR(100) NOT NULL,
    status VARCHAR(20) NOT NULL,
    message TEXT,
    latency_ms INTEGER,
    checked_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_health_comp_ts ON health_checks(component, checked_at DESC);
"@
    
    $schemaFile = Join-Path $dataDir "schema.sql"
    Set-Content -Path $schemaFile -Value $schemaSql -Encoding UTF8
    
    try {
        & $psqlPath -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f $schemaFile 2>&1 | ForEach-Object { Write-Log $_ }
        Write-Ok "Database schema created"
    }
    catch {
        Write-Warn "Schema creation had warnings"
    }
    
    Write-Section "Create Environment Configuration"
    
    $envContent = @"
# PolyTrader Configuration - Generated $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
API_HOST=0.0.0.0
API_PORT=8000
COINBASE_API_URL=https://api.coinbase.com
POLYMARKET_API_KEY=
POLYMARKET_API_SECRET=
POLYMARKET_PRIVATE_KEY=
POLYMARKET_FUNDER_ADDRESS=
PORTFOLIO_TRADE_PCT=5
MAX_MARKET_USD=100
CORRELATION_MAX_BASKET_PCT=35
DAILY_LOSS_LIMIT_USD=25
TAKE_PROFIT_PCT=8
STOP_LOSS_PCT=5
LLM_ADVISOR_ENABLED=false
OPENAI_API_KEY=
LOG_LEVEL=INFO
ENVIRONMENT=production
"@
    
    Set-Content -Path (Join-Path $backendDir ".env") -Value $envContent -Encoding UTF8
    Write-Ok "Created .env file"
    
    $credContent = "Host: $DB_HOST`nPort: $DB_PORT`nDatabase: $DB_NAME`nUser: $DB_USER`nPassword: $DB_PASSWORD"
    Set-Content -Path (Join-Path $dataDir "db_credentials.txt") -Value $credContent -Encoding UTF8
    Write-Ok "Saved database credentials"
    
    Write-Section "Verify Database"
    
    # Ensure PGPASSWORD is set for the polytrader user
    $env:PGPASSWORD = $DB_PASSWORD
    
    $testResult = & $psqlPath -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM config;" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Database connection verified"
        Write-Ok "Config rows: $($testResult.Trim())"
    }
    else {
        Write-Warn "Database verification output: $testResult"
        throw "Database verification failed"
    }
    
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Cyan
    Write-Ok "Database setup completed successfully!"
    Set-Marker -Name "db_ok"
    
    Write-Host ""
    Write-Host "  IMPORTANT: Edit $backendDir\.env to add your Polymarket credentials" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Next step: Run 04_setup_api.ps1" -ForegroundColor Green
    Write-Host ""
    
    Stop-Log -Success $true
}
catch {
    Write-Fail "Database setup failed: $_"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Stop-Log -Success $false
    Write-Host "  Check log file: $logFile" -ForegroundColor Red
    exit 1
}