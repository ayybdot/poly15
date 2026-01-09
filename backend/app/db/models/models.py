"""
PolyTrader Database Models
SQLAlchemy ORM models for all database tables.
"""

from datetime import datetime, timezone
from decimal import Decimal
from typing import Optional

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import relationship

from app.db.database import Base


def utc_now() -> datetime:
    """Get current UTC timestamp."""
    return datetime.now(timezone.utc)


class BotState(Base):
    """Bot state tracking table."""
    
    __tablename__ = "bot_state"
    
    id = Column(Integer, primary_key=True)
    state = Column(String(50), nullable=False, default="STOPPED")
    updated_at = Column(DateTime(timezone=True), default=utc_now, onupdate=utc_now)
    updated_by = Column(String(100))
    reason = Column(Text)


class AuditLog(Base):
    """Audit log for all system events."""
    
    __tablename__ = "audit_log"
    
    id = Column(Integer, primary_key=True)
    timestamp = Column(DateTime(timezone=True), default=utc_now)
    event_type = Column(String(100), nullable=False)
    details = Column(JSONB)
    user_id = Column(String(100))
    ip_address = Column(String(50))
    
    __table_args__ = (
        Index("idx_audit_log_timestamp", "timestamp"),
        Index("idx_audit_log_event_type", "event_type"),
    )


class Price(Base):
    """Real-time price data from Coinbase."""
    
    __tablename__ = "prices"
    
    id = Column(Integer, primary_key=True)
    symbol = Column(String(20), nullable=False)
    price = Column(Numeric(20, 8), nullable=False)
    timestamp = Column(DateTime(timezone=True), default=utc_now)
    source = Column(String(50), default="coinbase")
    
    __table_args__ = (
        Index("idx_prices_symbol_ts", "symbol", "timestamp"),
    )


class Candle(Base):
    """OHLCV candle data."""
    
    __tablename__ = "candles"
    
    id = Column(Integer, primary_key=True)
    symbol = Column(String(20), nullable=False)
    timeframe = Column(String(10), default="15m")
    open_time = Column(DateTime(timezone=True), nullable=False)
    close_time = Column(DateTime(timezone=True), nullable=False)
    open = Column(Numeric(20, 8), nullable=False)
    high = Column(Numeric(20, 8), nullable=False)
    low = Column(Numeric(20, 8), nullable=False)
    close = Column(Numeric(20, 8), nullable=False)
    volume = Column(Numeric(30, 8), default=0)
    created_at = Column(DateTime(timezone=True), default=utc_now)
    
    __table_args__ = (
        UniqueConstraint("symbol", "timeframe", "open_time"),
        Index("idx_candles_symbol_time", "symbol", "timeframe", "open_time"),
    )


class Market(Base):
    """Polymarket market information."""
    
    __tablename__ = "markets"
    
    id = Column(Integer, primary_key=True)
    condition_id = Column(String(100), unique=True, nullable=False)
    question_id = Column(String(100))
    slug = Column(String(255))
    title = Column(Text, nullable=False)
    description = Column(Text)
    asset = Column(String(20), nullable=False)
    market_type = Column(String(50))
    end_date = Column(DateTime(timezone=True))
    resolution_date = Column(DateTime(timezone=True))
    active = Column(Boolean, default=True)
    yes_token_id = Column(String(100))
    no_token_id = Column(String(100))
    created_at = Column(DateTime(timezone=True), default=utc_now)
    updated_at = Column(DateTime(timezone=True), default=utc_now, onupdate=utc_now)
    
    # Relationships
    snapshots = relationship("MarketSnapshot", back_populates="market")
    orders = relationship("Order", back_populates="market")
    trades = relationship("Trade", back_populates="market")
    positions = relationship("Position", back_populates="market")
    decisions = relationship("Decision", back_populates="market")
    
    __table_args__ = (
        Index("idx_markets_asset", "asset"),
        Index("idx_markets_active", "active"),
        Index("idx_markets_end_date", "end_date"),
    )


class MarketSnapshot(Base):
    """Orderbook snapshots for markets."""
    
    __tablename__ = "market_snapshots"
    
    id = Column(Integer, primary_key=True)
    market_id = Column(Integer, ForeignKey("markets.id"))
    timestamp = Column(DateTime(timezone=True), default=utc_now)
    best_bid = Column(Numeric(10, 4))
    best_ask = Column(Numeric(10, 4))
    bid_depth = Column(Numeric(20, 2))
    ask_depth = Column(Numeric(20, 2))
    spread = Column(Numeric(10, 6))
    volume_24h = Column(Numeric(20, 2))
    
    # Relationships
    market = relationship("Market", back_populates="snapshots")
    
    __table_args__ = (
        Index("idx_snapshots_market_ts", "market_id", "timestamp"),
    )


class Decision(Base):
    """Trading decisions made by the strategy."""
    
    __tablename__ = "decisions"
    
    id = Column(Integer, primary_key=True)
    timestamp = Column(DateTime(timezone=True), default=utc_now)
    asset = Column(String(20), nullable=False)
    market_id = Column(Integer, ForeignKey("markets.id"))
    direction = Column(String(10), nullable=False)  # UP or DOWN
    confidence = Column(Numeric(5, 4))
    features = Column(JSONB)
    risk_checks = Column(JSONB)
    signal_source = Column(String(50))
    executed = Column(Boolean, default=False)
    execution_id = Column(String(100))
    
    # Relationships
    market = relationship("Market", back_populates="decisions")
    orders = relationship("Order", back_populates="decision")
    
    __table_args__ = (
        Index("idx_decisions_timestamp", "timestamp"),
        Index("idx_decisions_asset", "asset"),
    )


class Order(Base):
    """Trading orders."""
    
    __tablename__ = "orders"
    
    id = Column(Integer, primary_key=True)
    order_id = Column(String(100), unique=True, nullable=False)
    market_id = Column(Integer, ForeignKey("markets.id"))
    decision_id = Column(Integer, ForeignKey("decisions.id"))
    side = Column(String(10), nullable=False)  # BUY or SELL
    token_id = Column(String(100), nullable=False)
    price = Column(Numeric(10, 4), nullable=False)
    size = Column(Numeric(20, 8), nullable=False)
    filled_size = Column(Numeric(20, 8), default=0)
    status = Column(String(50), default="pending")
    order_type = Column(String(20), default="limit")
    created_at = Column(DateTime(timezone=True), default=utc_now)
    updated_at = Column(DateTime(timezone=True), default=utc_now, onupdate=utc_now)
    filled_at = Column(DateTime(timezone=True))
    cancelled_at = Column(DateTime(timezone=True))
    error_message = Column(Text)
    
    # Relationships
    market = relationship("Market", back_populates="orders")
    decision = relationship("Decision", back_populates="orders")
    trades = relationship("Trade", back_populates="order")
    
    __table_args__ = (
        Index("idx_orders_status", "status"),
        Index("idx_orders_market", "market_id"),
        Index("idx_orders_created", "created_at"),
    )


class Trade(Base):
    """Executed trades (fills)."""
    
    __tablename__ = "trades"
    
    id = Column(Integer, primary_key=True)
    trade_id = Column(String(100), unique=True, nullable=False)
    order_id = Column(Integer, ForeignKey("orders.id"))
    market_id = Column(Integer, ForeignKey("markets.id"))
    side = Column(String(10), nullable=False)
    price = Column(Numeric(10, 4), nullable=False)
    size = Column(Numeric(20, 8), nullable=False)
    fee = Column(Numeric(20, 8), default=0)
    timestamp = Column(DateTime(timezone=True), default=utc_now)
    asset = Column(String(20))
    
    # Relationships
    order = relationship("Order", back_populates="trades")
    market = relationship("Market", back_populates="trades")
    
    __table_args__ = (
        Index("idx_trades_timestamp", "timestamp"),
        Index("idx_trades_market", "market_id"),
    )


class Position(Base):
    """Open and closed positions."""
    
    __tablename__ = "positions"
    
    id = Column(Integer, primary_key=True)
    market_id = Column(Integer, ForeignKey("markets.id"))
    token_id = Column(String(100), nullable=False)
    side = Column(String(10), nullable=False)  # YES or NO
    size = Column(Numeric(20, 8), nullable=False)
    avg_entry_price = Column(Numeric(10, 4), nullable=False)
    current_price = Column(Numeric(10, 4))
    unrealized_pnl = Column(Numeric(20, 8))
    realized_pnl = Column(Numeric(20, 8), default=0)
    opened_at = Column(DateTime(timezone=True), default=utc_now)
    updated_at = Column(DateTime(timezone=True), default=utc_now, onupdate=utc_now)
    closed_at = Column(DateTime(timezone=True))
    status = Column(String(20), default="open")
    
    # Relationships
    market = relationship("Market", back_populates="positions")
    
    __table_args__ = (
        Index("idx_positions_status", "status"),
        Index("idx_positions_market", "market_id"),
    )


class DailyPnL(Base):
    """Daily profit/loss summary."""
    
    __tablename__ = "daily_pnl"
    
    id = Column(Integer, primary_key=True)
    date = Column(DateTime(timezone=True), unique=True, nullable=False)
    realized_pnl = Column(Numeric(20, 8), default=0)
    unrealized_pnl = Column(Numeric(20, 8), default=0)
    fees_paid = Column(Numeric(20, 8), default=0)
    trade_count = Column(Integer, default=0)
    win_count = Column(Integer, default=0)
    loss_count = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), default=utc_now)
    updated_at = Column(DateTime(timezone=True), default=utc_now, onupdate=utc_now)


class RiskMetrics(Base):
    """Risk metrics snapshots."""
    
    __tablename__ = "risk_metrics"
    
    id = Column(Integer, primary_key=True)
    timestamp = Column(DateTime(timezone=True), default=utc_now)
    total_exposure = Column(Numeric(20, 8))
    btc_exposure = Column(Numeric(20, 8))
    eth_exposure = Column(Numeric(20, 8))
    sol_exposure = Column(Numeric(20, 8))
    correlation_risk = Column(Numeric(10, 4))
    daily_loss = Column(Numeric(20, 8))
    portfolio_value = Column(Numeric(20, 8))
    
    __table_args__ = (
        Index("idx_risk_timestamp", "timestamp"),
    )


class Config(Base):
    """Configuration key-value store."""
    
    __tablename__ = "config"
    
    id = Column(Integer, primary_key=True)
    key = Column(String(100), unique=True, nullable=False)
    value = Column(JSONB, nullable=False)
    description = Column(Text)
    updated_at = Column(DateTime(timezone=True), default=utc_now, onupdate=utc_now)
    updated_by = Column(String(100))


class CircuitBreaker(Base):
    """Circuit breaker status."""
    
    __tablename__ = "circuit_breakers"
    
    id = Column(Integer, primary_key=True)
    breaker_name = Column(String(100), unique=True, nullable=False)
    is_tripped = Column(Boolean, default=False)
    trip_reason = Column(Text)
    trip_count = Column(Integer, default=0)
    last_trip = Column(DateTime(timezone=True))
    last_reset = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), default=utc_now)


class HealthCheck(Base):
    """Health check results."""
    
    __tablename__ = "health_checks"
    
    id = Column(Integer, primary_key=True)
    component = Column(String(100), nullable=False)
    status = Column(String(20), nullable=False)
    message = Column(Text)
    latency_ms = Column(Integer)
    checked_at = Column(DateTime(timezone=True), default=utc_now)
    
    __table_args__ = (
        Index("idx_health_component_ts", "component", "checked_at"),
    )
