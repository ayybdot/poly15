CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS bot_state (
    id SERIAL PRIMARY KEY,
    state VARCHAR(50) NOT NULL DEFAULT 'STOPPED',
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
    execution_id VARCHAR(100)
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
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
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
    last_reset TIMESTAMP WITH TIME ZONE
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
