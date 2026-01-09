"""
PolyTrader Price Service
Fetches and stores real-time price data from Coinbase.
"""

import asyncio
import json
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from typing import Dict, List, Optional, Any

import httpx
import structlog
from sqlalchemy import select, func, desc
from sqlalchemy.dialects.postgresql import insert

from app.core.config import settings
from app.db.database import get_db_session
from app.db.models.models import Price, Candle

logger = structlog.get_logger(__name__)


class PriceService:
    """Service for fetching and storing Coinbase price data."""
    
    def __init__(self):
        self.base_url = settings.COINBASE_API_URL
        self.ws_url = settings.COINBASE_WS_URL
        self.pairs = settings.coinbase_pairs
        self.assets = settings.TRADING_ASSETS
        
        self._running = False
        self._ws_task: Optional[asyncio.Task] = None
        self._polling_task: Optional[asyncio.Task] = None
        
        # In-memory cache for latest prices
        self._latest_prices: Dict[str, Dict[str, Any]] = {}
        self._last_candle_fetch: Dict[str, datetime] = {}
    
    async def start_streaming(self) -> None:
        """Start price streaming and polling."""
        if self._running:
            return
        
        self._running = True
        logger.info("Starting price service", pairs=self.pairs)
        
        # Start polling task (WebSocket can be added later for real-time)
        self._polling_task = asyncio.create_task(self._poll_prices())
        
        # Fetch initial candles
        await self._fetch_all_candles()
    
    async def stop_streaming(self) -> None:
        """Stop price streaming."""
        self._running = False
        
        if self._polling_task:
            self._polling_task.cancel()
            try:
                await self._polling_task
            except asyncio.CancelledError:
                pass
        
        if self._ws_task:
            self._ws_task.cancel()
            try:
                await self._ws_task
            except asyncio.CancelledError:
                pass
        
        logger.info("Price service stopped")
    
    async def _poll_prices(self) -> None:
        """Poll prices at regular intervals."""
        while self._running:
            try:
                await self._fetch_latest_prices()
                
                # Fetch candles every 5 minutes
                now = datetime.now(timezone.utc)
                for pair in self.pairs:
                    symbol = pair.replace("-USD", "")
                    last_fetch = self._last_candle_fetch.get(symbol)
                    if not last_fetch or (now - last_fetch) > timedelta(minutes=5):
                        await self._fetch_candles(pair)
                        self._last_candle_fetch[symbol] = now
                
                await asyncio.sleep(5)  # Poll every 5 seconds
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error("Price polling error", error=str(e))
                await asyncio.sleep(10)
    
    async def _fetch_latest_prices(self) -> None:
        """Fetch latest prices from Coinbase."""
        async with httpx.AsyncClient(timeout=10.0) as client:
            for pair in self.pairs:
                try:
                    # Use Coinbase API v2 for spot prices
                    url = f"{self.base_url}/v2/prices/{pair}/spot"
                    response = await client.get(url)
                    response.raise_for_status()
                    
                    data = response.json()
                    price_str = data.get("data", {}).get("amount")
                    
                    if price_str:
                        price = Decimal(price_str)
                        symbol = pair.replace("-USD", "")
                        timestamp = datetime.now(timezone.utc)
                        
                        # Update cache
                        self._latest_prices[symbol] = {
                            "price": float(price),
                            "timestamp": timestamp.isoformat(),
                            "symbol": symbol,
                        }
                        
                        # Store in database
                        await self._store_price(symbol, price, timestamp)
                        
                except Exception as e:
                    logger.error("Failed to fetch price", pair=pair, error=str(e))
    
    async def _store_price(
        self, symbol: str, price: Decimal, timestamp: datetime
    ) -> None:
        """Store price in database."""
        try:
            async with get_db_session() as session:
                price_record = Price(
                    symbol=symbol,
                    price=price,
                    timestamp=timestamp,
                    source="coinbase",
                )
                session.add(price_record)
                await session.commit()
        except Exception as e:
            logger.error("Failed to store price", symbol=symbol, error=str(e))
    
    async def _fetch_candles(self, pair: str) -> None:
        """Fetch 15-minute candles from Coinbase."""
        async with httpx.AsyncClient(timeout=30.0) as client:
            try:
                symbol = pair.replace("-USD", "")
                
                # Coinbase Exchange API for candles
                # granularity=900 for 15-minute candles
                url = f"https://api.exchange.coinbase.com/products/{pair}/candles"
                params = {
                    "granularity": 900,  # 15 minutes in seconds
                }
                
                response = await client.get(url, params=params)
                response.raise_for_status()
                
                candles = response.json()
                
                # Coinbase returns: [timestamp, low, high, open, close, volume]
                for candle in candles:
                    if len(candle) >= 6:
                        await self._store_candle(
                            symbol=symbol,
                            open_time=datetime.fromtimestamp(candle[0], tz=timezone.utc),
                            open_price=Decimal(str(candle[3])),
                            high=Decimal(str(candle[2])),
                            low=Decimal(str(candle[1])),
                            close=Decimal(str(candle[4])),
                            volume=Decimal(str(candle[5])),
                        )
                
                logger.debug("Fetched candles", symbol=symbol, count=len(candles))
                
            except Exception as e:
                logger.error("Failed to fetch candles", pair=pair, error=str(e))
    
    async def _fetch_all_candles(self) -> None:
        """Fetch candles for all pairs."""
        for pair in self.pairs:
            await self._fetch_candles(pair)
            self._last_candle_fetch[pair.replace("-USD", "")] = datetime.now(timezone.utc)
    
    async def _store_candle(
        self,
        symbol: str,
        open_time: datetime,
        open_price: Decimal,
        high: Decimal,
        low: Decimal,
        close: Decimal,
        volume: Decimal,
    ) -> None:
        """Store candle in database with upsert."""
        try:
            close_time = open_time + timedelta(minutes=15)
            
            async with get_db_session() as session:
                stmt = insert(Candle).values(
                    symbol=symbol,
                    timeframe="15m",
                    open_time=open_time,
                    close_time=close_time,
                    open=open_price,
                    high=high,
                    low=low,
                    close=close,
                    volume=volume,
                ).on_conflict_do_update(
                    index_elements=["symbol", "timeframe", "open_time"],
                    set_={
                        "high": high,
                        "low": low,
                        "close": close,
                        "volume": volume,
                    }
                )
                await session.execute(stmt)
                await session.commit()
        except Exception as e:
            logger.error("Failed to store candle", symbol=symbol, error=str(e))
    
    def get_latest_price(self, symbol: str) -> Optional[Dict[str, Any]]:
        """Get latest price from cache."""
        return self._latest_prices.get(symbol)
    
    def get_all_latest_prices(self) -> Dict[str, Dict[str, Any]]:
        """Get all latest prices from cache."""
        return self._latest_prices.copy()
    
    async def get_latest_prices_from_db(self) -> List[Dict[str, Any]]:
        """Get latest prices from database."""
        async with get_db_session() as session:
            subquery = (
                select(Price.symbol, func.max(Price.timestamp).label("max_ts"))
                .group_by(Price.symbol)
                .subquery()
            )
            
            result = await session.execute(
                select(Price)
                .join(
                    subquery,
                    (Price.symbol == subquery.c.symbol) & 
                    (Price.timestamp == subquery.c.max_ts)
                )
            )
            prices = result.scalars().all()
            
            return [
                {
                    "symbol": p.symbol,
                    "price": float(p.price),
                    "timestamp": p.timestamp.isoformat(),
                    "source": p.source,
                }
                for p in prices
            ]
    
    async def get_candles(
        self, symbol: str, limit: int = 100
    ) -> List[Dict[str, Any]]:
        """Get candles from database."""
        async with get_db_session() as session:
            result = await session.execute(
                select(Candle)
                .where(Candle.symbol == symbol, Candle.timeframe == "15m")
                .order_by(desc(Candle.open_time))
                .limit(limit)
            )
            candles = result.scalars().all()
            
            return [
                {
                    "symbol": c.symbol,
                    "timeframe": c.timeframe,
                    "open_time": c.open_time.isoformat(),
                    "close_time": c.close_time.isoformat(),
                    "open": float(c.open),
                    "high": float(c.high),
                    "low": float(c.low),
                    "close": float(c.close),
                    "volume": float(c.volume),
                }
                for c in reversed(candles)
            ]
    
    async def get_price_change_15m(self, symbol: str) -> Optional[float]:
        """Calculate 15-minute price change percentage."""
        async with get_db_session() as session:
            # Get last two candles
            result = await session.execute(
                select(Candle)
                .where(Candle.symbol == symbol, Candle.timeframe == "15m")
                .order_by(desc(Candle.open_time))
                .limit(2)
            )
            candles = result.scalars().all()
            
            if len(candles) >= 2:
                current = float(candles[0].close)
                previous = float(candles[1].close)
                if previous > 0:
                    return ((current - previous) / previous) * 100
            
            return None
    
    def is_data_stale(self, symbol: str, threshold_seconds: int = 60) -> bool:
        """Check if price data is stale."""
        latest = self._latest_prices.get(symbol)
        if not latest:
            return True
        
        try:
            timestamp = datetime.fromisoformat(latest["timestamp"].replace("Z", "+00:00"))
            age = (datetime.now(timezone.utc) - timestamp).total_seconds()
            return age > threshold_seconds
        except:
            return True
