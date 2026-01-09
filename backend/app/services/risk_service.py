"""
PolyTrader Risk Management Service
Enforces all risk limits and circuit breakers.
"""

import asyncio
from datetime import datetime, timezone, timedelta, date
from decimal import Decimal
from typing import Dict, List, Optional, Any, Tuple

import structlog
from sqlalchemy import select, func, and_, update

from app.core.config import settings
from app.db.database import get_db_session
from app.db.models.models import (
    BotState,
    Config,
    CircuitBreaker,
    DailyPnL,
    Position,
    Trade,
    RiskMetrics,
    AuditLog,
)

logger = structlog.get_logger(__name__)


class RiskManager:
    """Risk management and circuit breaker service."""
    
    STATES = {
        "RUNNING": "Bot is actively trading",
        "PAUSED": "Bot is paused - no new trades",
        "STOPPED": "Bot is stopped - no trading",
        "HALTED_DAILY_LOSS": "Halted due to daily loss limit",
        "HALTED_CIRCUIT_BREAKER": "Halted due to circuit breaker",
    }
    
    def __init__(self):
        self._config_cache: Dict[str, Any] = {}
        self._last_config_load: Optional[datetime] = None
    
    async def load_config(self, force: bool = False) -> Dict[str, Any]:
        """Load configuration from database."""
        if not force and self._config_cache and self._last_config_load:
            if (datetime.now(timezone.utc) - self._last_config_load).seconds < 60:
                return self._config_cache
        
        async with get_db_session() as session:
            result = await session.execute(select(Config))
            configs = result.scalars().all()
            self._config_cache = {c.key: c.value for c in configs}
            self._last_config_load = datetime.now(timezone.utc)
        
        return self._config_cache
    
    async def get_config_value(self, key: str, default: Any = None) -> Any:
        """Get a specific config value."""
        config = await self.load_config()
        return config.get(key, default)
    
    async def get_bot_state(self) -> str:
        """Get current bot state."""
        async with get_db_session() as session:
            result = await session.execute(
                select(BotState).order_by(BotState.id.desc()).limit(1)
            )
            state = result.scalar_one_or_none()
            return state.state if state else "STOPPED"
    
    async def set_bot_state(
        self, state: str, reason: str = "", user: str = "system"
    ) -> bool:
        """Set bot state."""
        if state not in self.STATES:
            raise ValueError(f"Invalid state: {state}")
        
        async with get_db_session() as session:
            result = await session.execute(
                select(BotState).order_by(BotState.id.desc()).limit(1)
            )
            bot_state = result.scalar_one_or_none()
            
            if bot_state:
                bot_state.state = state
                bot_state.reason = reason
                bot_state.updated_by = user
                bot_state.updated_at = datetime.now(timezone.utc)
            else:
                bot_state = BotState(state=state, reason=reason, updated_by=user)
                session.add(bot_state)
            
            audit = AuditLog(
                event_type="bot_state_change",
                details={"new_state": state, "reason": reason},
                user_id=user,
            )
            session.add(audit)
            await session.commit()
        
        logger.info("Bot state changed", state=state, reason=reason, user=user)
        return True
    
    async def can_trade(self) -> Tuple[bool, str]:
        """Check if trading is allowed."""
        state = await self.get_bot_state()
        
        if state != "RUNNING":
            return False, f"Bot state is {state}"
        
        # Check circuit breakers
        tripped = await self.get_tripped_breakers()
        if tripped:
            return False, f"Circuit breakers tripped: {', '.join(tripped)}"
        
        # Check daily loss limit
        daily_loss = await self.get_daily_loss()
        limit = float(await self.get_config_value("daily_loss_limit_usd", 25))
        if daily_loss >= limit:
            await self.set_bot_state("HALTED_DAILY_LOSS", f"Daily loss ${daily_loss:.2f} >= ${limit:.2f}")
            return False, "Daily loss limit reached"
        
        return True, "Trading allowed"
    
    async def check_position_risk(
        self,
        asset: str,
        size_usd: float,
        portfolio_value: float,
    ) -> Tuple[bool, Dict[str, Any]]:
        """Check if a new position passes risk checks."""
        config = await self.load_config()
        
        checks = {
            "max_trade_size": True,
            "max_market_exposure": True,
            "correlation_limit": True,
            "max_positions": True,
            "daily_loss": True,
        }
        reasons = []
        
        # Check trade size vs portfolio percentage
        max_trade_pct = float(config.get("portfolio_trade_pct", 5))
        max_trade_usd = portfolio_value * max_trade_pct / 100
        if size_usd > max_trade_usd:
            checks["max_trade_size"] = False
            reasons.append(f"Trade size ${size_usd:.2f} > max ${max_trade_usd:.2f} ({max_trade_pct}%)")
        
        # Check absolute max per market
        max_market_usd = float(config.get("max_market_usd", 100))
        if size_usd > max_market_usd:
            checks["max_market_exposure"] = False
            reasons.append(f"Trade size ${size_usd:.2f} > max market ${max_market_usd:.2f}")
        
        # Check correlation basket (BTC + ETH + SOL combined)
        correlation_max_pct = float(config.get("correlation_max_basket_pct", 35))
        current_exposure = await self.get_asset_exposure(asset)
        total_crypto_exposure = await self.get_total_crypto_exposure()
        new_total = total_crypto_exposure + size_usd
        max_correlated = portfolio_value * correlation_max_pct / 100
        if new_total > max_correlated:
            checks["correlation_limit"] = False
            reasons.append(f"Crypto exposure ${new_total:.2f} > max ${max_correlated:.2f}")
        
        # Check max open positions
        max_positions = int(config.get("max_open_positions", 5))
        open_positions = await self.get_open_position_count()
        if open_positions >= max_positions:
            checks["max_positions"] = False
            reasons.append(f"Open positions {open_positions} >= max {max_positions}")
        
        # Check daily loss
        daily_loss = await self.get_daily_loss()
        daily_limit = float(config.get("daily_loss_limit_usd", 25))
        if daily_loss >= daily_limit * 0.8:  # Warn at 80%
            if daily_loss >= daily_limit:
                checks["daily_loss"] = False
                reasons.append(f"Daily loss ${daily_loss:.2f} >= limit ${daily_limit:.2f}")
        
        passed = all(checks.values())
        
        return passed, {
            "passed": passed,
            "checks": checks,
            "reasons": reasons,
            "size_usd": size_usd,
            "portfolio_value": portfolio_value,
        }
    
    async def get_asset_exposure(self, asset: str) -> float:
        """Get current exposure for an asset."""
        async with get_db_session() as session:
            from app.db.models.models import Market
            
            result = await session.execute(
                select(func.sum(Position.size * Position.avg_entry_price))
                .join(Market, Position.market_id == Market.id)
                .where(
                    and_(
                        Market.asset == asset,
                        Position.status == "open",
                    )
                )
            )
            exposure = result.scalar()
            return float(exposure) if exposure else 0.0
    
    async def get_total_crypto_exposure(self) -> float:
        """Get total exposure across all crypto assets."""
        total = 0.0
        for asset in ["BTC", "ETH", "SOL"]:
            total += await self.get_asset_exposure(asset)
        return total
    
    async def get_open_position_count(self) -> int:
        """Get count of open positions."""
        async with get_db_session() as session:
            result = await session.execute(
                select(func.count(Position.id)).where(Position.status == "open")
            )
            return result.scalar() or 0
    
    async def get_daily_loss(self) -> float:
        """Get today's realized loss."""
        today = date.today()
        
        async with get_db_session() as session:
            result = await session.execute(
                select(DailyPnL).where(func.date(DailyPnL.date) == today)
            )
            daily = result.scalar_one_or_none()
            
            if daily and daily.realized_pnl < 0:
                return abs(float(daily.realized_pnl))
            return 0.0
    
    async def update_daily_pnl(
        self, realized_pnl: Decimal, fees: Decimal, is_win: bool
    ) -> None:
        """Update daily PnL record."""
        today = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
        
        async with get_db_session() as session:
            result = await session.execute(
                select(DailyPnL).where(func.date(DailyPnL.date) == today.date())
            )
            daily = result.scalar_one_or_none()
            
            if daily:
                daily.realized_pnl = Decimal(str(daily.realized_pnl or 0)) + realized_pnl
                daily.fees_paid = Decimal(str(daily.fees_paid or 0)) + fees
                daily.trade_count = (daily.trade_count or 0) + 1
                if is_win:
                    daily.win_count = (daily.win_count or 0) + 1
                else:
                    daily.loss_count = (daily.loss_count or 0) + 1
            else:
                daily = DailyPnL(
                    date=today,
                    realized_pnl=realized_pnl,
                    fees_paid=fees,
                    trade_count=1,
                    win_count=1 if is_win else 0,
                    loss_count=0 if is_win else 1,
                )
                session.add(daily)
            
            await session.commit()
    
    # Circuit Breaker Methods
    async def trip_breaker(self, name: str, reason: str) -> None:
        """Trip a circuit breaker."""
        async with get_db_session() as session:
            result = await session.execute(
                select(CircuitBreaker).where(CircuitBreaker.breaker_name == name)
            )
            breaker = result.scalar_one_or_none()
            
            if breaker:
                breaker.is_tripped = True
                breaker.trip_reason = reason
                breaker.trip_count = (breaker.trip_count or 0) + 1
                breaker.last_trip = datetime.now(timezone.utc)
            else:
                breaker = CircuitBreaker(
                    breaker_name=name,
                    is_tripped=True,
                    trip_reason=reason,
                    trip_count=1,
                    last_trip=datetime.now(timezone.utc),
                )
                session.add(breaker)
            
            audit = AuditLog(
                event_type="circuit_breaker_tripped",
                details={"breaker": name, "reason": reason},
            )
            session.add(audit)
            await session.commit()
        
        logger.warning("Circuit breaker tripped", breaker=name, reason=reason)
        
        # Check if we should halt
        if name in ["daily_loss_limit", "reconciliation_mismatch"]:
            await self.set_bot_state("HALTED_CIRCUIT_BREAKER", f"Circuit breaker: {name}")
    
    async def reset_breaker(self, name: str) -> None:
        """Reset a circuit breaker."""
        async with get_db_session() as session:
            result = await session.execute(
                select(CircuitBreaker).where(CircuitBreaker.breaker_name == name)
            )
            breaker = result.scalar_one_or_none()
            
            if breaker:
                breaker.is_tripped = False
                breaker.last_reset = datetime.now(timezone.utc)
                
                audit = AuditLog(
                    event_type="circuit_breaker_reset",
                    details={"breaker": name},
                )
                session.add(audit)
                await session.commit()
        
        logger.info("Circuit breaker reset", breaker=name)
    
    async def get_tripped_breakers(self) -> List[str]:
        """Get list of tripped circuit breakers."""
        async with get_db_session() as session:
            result = await session.execute(
                select(CircuitBreaker).where(CircuitBreaker.is_tripped == True)
            )
            breakers = result.scalars().all()
            return [b.breaker_name for b in breakers]
    
    async def get_all_breakers(self) -> List[Dict[str, Any]]:
        """Get all circuit breaker statuses."""
        async with get_db_session() as session:
            result = await session.execute(select(CircuitBreaker))
            breakers = result.scalars().all()
            
            return [
                {
                    "name": b.breaker_name,
                    "is_tripped": b.is_tripped,
                    "trip_reason": b.trip_reason,
                    "trip_count": b.trip_count,
                    "last_trip": b.last_trip.isoformat() if b.last_trip else None,
                    "last_reset": b.last_reset.isoformat() if b.last_reset else None,
                }
                for b in breakers
            ]
    
    # Risk Metrics
    async def record_risk_metrics(self, portfolio_value: float) -> None:
        """Record current risk metrics."""
        btc_exposure = await self.get_asset_exposure("BTC")
        eth_exposure = await self.get_asset_exposure("ETH")
        sol_exposure = await self.get_asset_exposure("SOL")
        total_exposure = btc_exposure + eth_exposure + sol_exposure
        
        daily_loss = await self.get_daily_loss()
        
        # Simple correlation risk (placeholder)
        correlation_risk = total_exposure / portfolio_value if portfolio_value > 0 else 0
        
        async with get_db_session() as session:
            metrics = RiskMetrics(
                total_exposure=Decimal(str(total_exposure)),
                btc_exposure=Decimal(str(btc_exposure)),
                eth_exposure=Decimal(str(eth_exposure)),
                sol_exposure=Decimal(str(sol_exposure)),
                correlation_risk=Decimal(str(correlation_risk)),
                daily_loss=Decimal(str(daily_loss)),
                portfolio_value=Decimal(str(portfolio_value)),
            )
            session.add(metrics)
            await session.commit()
    
    async def get_latest_risk_metrics(self) -> Optional[Dict[str, Any]]:
        """Get most recent risk metrics."""
        async with get_db_session() as session:
            result = await session.execute(
                select(RiskMetrics).order_by(RiskMetrics.timestamp.desc()).limit(1)
            )
            metrics = result.scalar_one_or_none()
            
            if metrics:
                return {
                    "timestamp": metrics.timestamp.isoformat(),
                    "total_exposure": float(metrics.total_exposure) if metrics.total_exposure else 0,
                    "btc_exposure": float(metrics.btc_exposure) if metrics.btc_exposure else 0,
                    "eth_exposure": float(metrics.eth_exposure) if metrics.eth_exposure else 0,
                    "sol_exposure": float(metrics.sol_exposure) if metrics.sol_exposure else 0,
                    "correlation_risk": float(metrics.correlation_risk) if metrics.correlation_risk else 0,
                    "daily_loss": float(metrics.daily_loss) if metrics.daily_loss else 0,
                    "portfolio_value": float(metrics.portfolio_value) if metrics.portfolio_value else 0,
                }
            return None
    
    # Take Profit / Stop Loss
    def calculate_exit_prices(
        self, entry_price: Decimal, side: str
    ) -> Dict[str, Decimal]:
        """Calculate take profit and stop loss prices."""
        tp_pct = Decimal(str(settings.TAKE_PROFIT_PCT)) / 100
        sl_pct = Decimal(str(settings.STOP_LOSS_PCT)) / 100
        
        # For Polymarket, prices are between 0 and 1
        # Account for fees in calculation
        fee_rate = Decimal("0.02")  # 2% taker fee
        
        if side == "YES":  # Long
            tp_price = entry_price * (1 + tp_pct + fee_rate)
            sl_price = entry_price * (1 - sl_pct - fee_rate)
        else:  # Short / NO
            tp_price = entry_price * (1 - tp_pct - fee_rate)
            sl_price = entry_price * (1 + sl_pct + fee_rate)
        
        # Clamp to valid range
        tp_price = max(Decimal("0.01"), min(Decimal("0.99"), tp_price))
        sl_price = max(Decimal("0.01"), min(Decimal("0.99"), sl_price))
        
        return {
            "take_profit": tp_price,
            "stop_loss": sl_price,
            "entry_price": entry_price,
        }
    
    def should_exit_position(
        self, entry_price: float, current_price: float, side: str
    ) -> Tuple[bool, str]:
        """Check if position should be exited."""
        exits = self.calculate_exit_prices(Decimal(str(entry_price)), side)
        
        tp = float(exits["take_profit"])
        sl = float(exits["stop_loss"])
        
        if side == "YES":
            if current_price >= tp:
                return True, "take_profit"
            if current_price <= sl:
                return True, "stop_loss"
        else:
            if current_price <= tp:
                return True, "take_profit"
            if current_price >= sl:
                return True, "stop_loss"
        
        return False, ""
