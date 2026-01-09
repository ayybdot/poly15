"""
PolyTrader Trading Worker
Main worker process that runs the trading loop.
"""

import asyncio
import signal
import sys
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Optional

import structlog

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from app.core.config import settings
from app.core.logging import setup_logging
from app.db.database import create_tables, get_db_session
from app.services.price_service import PriceService
from app.services.market_service import MarketService
from app.services.strategy_service import StrategyService
from app.services.trading_service import TradingService
from app.services.risk_service import RiskManager

setup_logging()
logger = structlog.get_logger(__name__)


class TradingWorker:
    """Main trading worker that executes the strategy loop."""
    
    def __init__(self):
        self.price_service = PriceService()
        self.market_service = MarketService()
        self.strategy_service = StrategyService()
        self.trading_service = TradingService()
        self.risk_manager = RiskManager()
        
        self._running = False
        self._shutdown_event = asyncio.Event()
        
        self.loop_interval = 60  # seconds
        self.analysis_interval = 300  # seconds
        self._last_analysis: dict[str, datetime] = {}
        
        # Portfolio value (would be fetched from actual balance in production)
        self.portfolio_value = 500.0
    
    async def start(self):
        """Start the trading worker."""
        logger.info("Starting trading worker")
        
        # Initialize database
        await create_tables()
        
        # Start price streaming
        await self.price_service.start_streaming()
        
        # Initial market discovery
        await self.market_service.discover_markets()
        
        self._running = True
        
        # Setup signal handlers (Unix only - skip on Windows)
        import sys
        if sys.platform != "win32":
            for sig in (signal.SIGTERM, signal.SIGINT):
                asyncio.get_event_loop().add_signal_handler(
                    sig, lambda: asyncio.create_task(self.shutdown())
                )
        
        logger.info("Trading worker started")
        
        # Run main loop
        await self._main_loop()
    
    async def shutdown(self):
        """Graceful shutdown."""
        logger.info("Shutting down trading worker")
        self._running = False
        self._shutdown_event.set()
        
        # Cancel all orders
        await self.trading_service.cancel_all_orders()
        
        # Stop price streaming
        await self.price_service.stop_streaming()
        
        logger.info("Trading worker shutdown complete")
    
    async def _main_loop(self):
        """Main trading loop."""
        while self._running:
            try:
                loop_start = datetime.now(timezone.utc)
                
                # Check bot state
                can_trade, reason = await self.risk_manager.can_trade()
                
                if can_trade:
                    await self._trading_cycle()
                else:
                    logger.debug("Trading disabled", reason=reason)
                
                # Calculate sleep time
                elapsed = (datetime.now(timezone.utc) - loop_start).total_seconds()
                sleep_time = max(0, self.loop_interval - elapsed)
                
                # Wait for next cycle or shutdown
                try:
                    await asyncio.wait_for(
                        self._shutdown_event.wait(),
                        timeout=sleep_time
                    )
                    break  # Shutdown requested
                except asyncio.TimeoutError:
                    pass  # Normal timeout, continue loop
                    
            except Exception as e:
                logger.error("Error in trading loop", error=str(e), exc_info=True)
                await asyncio.sleep(10)  # Back off on error
    
    async def _trading_cycle(self):
        """Execute one trading cycle."""
        now = datetime.now(timezone.utc)
        
        # Refresh market discovery periodically
        await self.market_service.discover_markets()
        
        # Process each asset
        for asset in settings.TRADING_ASSETS:
            try:
                await self._process_asset(asset, now)
            except Exception as e:
                logger.error("Error processing asset", asset=asset, error=str(e))
        
        # Update positions and check exits
        await self._check_position_exits()
        
        # Record risk metrics
        await self.risk_manager.record_risk_metrics(self.portfolio_value)
    
    async def _process_asset(self, asset: str, now: datetime):
        """Process trading for a single asset."""
        # Check if it's time to analyze
        last = self._last_analysis.get(asset)
        should_analyze = not last or (now - last).total_seconds() >= self.analysis_interval
        
        if not should_analyze:
            return
        
        # Check for stale data
        if self.price_service.is_data_stale(asset, settings.STALE_DATA_THRESHOLD_SECONDS):
            await self.risk_manager.trip_breaker("stale_data", f"Stale data for {asset}")
            return
        
        # Analyze asset
        analysis = await self.strategy_service.analyze_asset(asset)
        self._last_analysis[asset] = now
        
        # Check signal strength
        if analysis["signal"] == "NEUTRAL" or analysis["confidence"] < 0.5:
            logger.debug("No trade signal", asset=asset, signal=analysis["signal"])
            return
        
        # Get tradable market
        market = await self.market_service.get_tradable_market(asset)
        if not market:
            logger.debug("No tradable market", asset=asset)
            return
        
        # Determine token to trade
        if analysis["signal"] == "UP":
            token_id = market["yes_token_id"]
            token_type = "YES"
        else:
            token_id = market["no_token_id"]
            token_type = "NO"
        
        if not token_id:
            logger.warning("No token ID", asset=asset, signal=analysis["signal"])
            return
        
        # Check liquidity
        has_liquidity = await self.market_service.check_liquidity(
            token_id, settings.MIN_LIQUIDITY_USD
        )
        if not has_liquidity:
            logger.debug("Insufficient liquidity", asset=asset)
            return
        
        # Calculate position size
        size_usd = self._calculate_position_size(analysis["confidence"])
        
        # Risk check
        passed, risk_result = await self.risk_manager.check_position_risk(
            asset=asset,
            size_usd=size_usd,
            portfolio_value=self.portfolio_value,
        )
        
        if not passed:
            logger.info(
                "Risk check failed",
                asset=asset,
                reasons=risk_result["reasons"],
            )
            return
        
        # Place order
        logger.info(
            "Placing trade",
            asset=asset,
            signal=analysis["signal"],
            confidence=analysis["confidence"],
            size_usd=size_usd,
            token_type=token_type,
        )
        
        result = await self.trading_service.place_marketable_limit_order(
            token_id=token_id,
            side="BUY",
            size=Decimal(str(size_usd)),
            market_id=market["id"],
        )
        
        if result and result.get("status") != "error":
            logger.info("Order placed", order_id=result.get("order_id"), asset=asset)
        else:
            logger.warning("Order failed", asset=asset, result=result)
    
    def _calculate_position_size(self, confidence: float) -> float:
        """Calculate position size based on confidence and portfolio."""
        base_pct = settings.PORTFOLIO_TRADE_PCT / 100
        
        # Scale by confidence (50% to 100% of base size)
        confidence_factor = 0.5 + (confidence * 0.5)
        
        size = self.portfolio_value * base_pct * confidence_factor
        
        # Apply max market limit
        size = min(size, settings.MAX_MARKET_USD)
        
        return round(size, 2)
    
    async def _check_position_exits(self):
        """Check open positions for exit conditions."""
        positions = await self.trading_service.get_positions(status="open")
        
        for position in positions:
            try:
                # Get current price from orderbook
                orderbook = await self.market_service.fetch_orderbook(position["token_id"])
                if not orderbook:
                    continue
                
                # Use mid price
                best_bid = orderbook.get("best_bid")
                best_ask = orderbook.get("best_ask")
                if not best_bid or not best_ask:
                    continue
                
                current_price = (best_bid + best_ask) / 2
                
                # Check exit conditions
                should_exit, exit_reason = self.risk_manager.should_exit_position(
                    entry_price=position["avg_entry_price"],
                    current_price=current_price,
                    side=position["side"],
                )
                
                if should_exit:
                    logger.info(
                        "Exiting position",
                        position_id=position["id"],
                        reason=exit_reason,
                        entry=position["avg_entry_price"],
                        current=current_price,
                    )
                    
                    # Place exit order
                    await self.trading_service.place_marketable_limit_order(
                        token_id=position["token_id"],
                        side="SELL",
                        size=Decimal(str(position["size"])),
                        market_id=position["market_id"],
                    )
                    
            except Exception as e:
                logger.error(
                    "Error checking position exit",
                    position_id=position.get("id"),
                    error=str(e),
                )


async def main():
    """Main entry point."""
    worker = TradingWorker()
    await worker.start()


if __name__ == "__main__":
    asyncio.run(main())