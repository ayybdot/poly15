"""
PolyTrader Market Service
Discovers and manages Polymarket 15-minute crypto markets.
"""

import asyncio
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from typing import Dict, List, Optional, Any

import httpx
import structlog
from sqlalchemy import select, and_
from sqlalchemy.dialects.postgresql import insert

from app.core.config import settings
from app.db.database import get_db_session
from app.db.models.models import Market, MarketSnapshot

logger = structlog.get_logger(__name__)


class MarketService:
    """Service for discovering and managing Polymarket markets."""
    
    GAMMA_BASE_URL = settings.POLYMARKET_GAMMA_URL
    CLOB_BASE_URL = settings.POLYMARKET_CLOB_URL
    
    # 15-minute market slug patterns: btc-updown-15m-{timestamp}
    MARKET_SLUG_PATTERNS = {
        "BTC": "btc-updown",
        "ETH": "eth-updown",
        "SOL": "sol-updown",
    }
    
    def __init__(self):
        self._market_cache: Dict[str, Market] = {}
        self._last_discovery: Optional[datetime] = None
    
    def _get_http_client(self, timeout: float = 30.0) -> httpx.AsyncClient:
        """Get HTTP client with optional proxy support."""
        proxy = settings.PROXY_URL if settings.PROXY_ENABLED and settings.PROXY_URL else None
        return httpx.AsyncClient(timeout=timeout, proxy=proxy)
    
    async def discover_markets(self) -> List[Dict[str, Any]]:
        """Discover 15-minute crypto markets from Gamma API."""
        logger.info("Discovering Polymarket 15-minute crypto markets")
        
        discovered = []
        
        async with self._get_http_client(timeout=30.0) as client:
            # Generate potential slugs based on current time
            # 15-min markets use Unix timestamps rounded to 15-min intervals
            now = datetime.now(timezone.utc)
            current_ts = int(now.timestamp())
            
            # Round down to nearest 15-minute interval (900 seconds)
            interval = 900
            current_interval = (current_ts // interval) * interval
            
            # Check current and next interval (to catch markets that just started)
            timestamps_to_check = [
                current_interval,
                current_interval + interval,  # Next market
                current_interval - interval,  # Previous (might still be active)
            ]
            
            for asset, pattern in self.MARKET_SLUG_PATTERNS.items():
                for ts in timestamps_to_check:
                    slug = f"{pattern}-15m-{ts}"
                    
                    try:
                        url = f"{self.GAMMA_BASE_URL}/events"
                        params = {"slug": slug}
                        
                        response = await client.get(url, params=params)
                        
                        if response.status_code == 200:
                            events = response.json()
                            
                            if events and len(events) > 0:
                                event = events[0]
                                event_id = event.get("id")
                                
                                if event_id:
                                    market_info = await self._fetch_event_details(client, event_id, asset)
                                    if market_info:
                                        # Check if market is still active (not ended)
                                        end_date = market_info.get("end_date")
                                        if end_date and end_date > now:
                                            discovered.append(market_info)
                                            await self._store_market(market_info)
                                            logger.info(
                                                "Discovered market",
                                                asset=asset,
                                                slug=slug,
                                                end_date=end_date.isoformat(),
                                            )
                    except Exception as e:
                        logger.debug("Slug not found", slug=slug, error=str(e))
                        continue
            
            logger.info("Market discovery complete", found=len(discovered))
            self._last_discovery = datetime.now(timezone.utc)
        
        return discovered
    
    async def _fetch_event_details(
        self, client: httpx.AsyncClient, event_id: int, asset: str
    ) -> Optional[Dict[str, Any]]:
        """Fetch full event details including market tokens."""
        try:
            url = f"{self.GAMMA_BASE_URL}/events/{event_id}"
            response = await client.get(url)
            response.raise_for_status()
            
            event = response.json()
            markets = event.get("markets", [])
            
            if not markets:
                return None
            
            # Get the first (usually only) market
            market = markets[0]
            
            # Parse token IDs from clobTokenIds
            clob_token_ids = market.get("clobTokenIds", "")
            outcomes = market.get("outcomes", "")
            
            # Parse the token IDs (stored as JSON string array)
            up_token_id = None
            down_token_id = None
            
            if clob_token_ids:
                try:
                    import json
                    tokens = json.loads(clob_token_ids) if isinstance(clob_token_ids, str) else clob_token_ids
                    outcomes_list = json.loads(outcomes) if isinstance(outcomes, str) else outcomes
                    
                    # Match tokens to outcomes (Up/Down or Yes/No)
                    for i, outcome in enumerate(outcomes_list):
                        if i < len(tokens):
                            outcome_lower = outcome.lower()
                            if outcome_lower in ["up", "yes"]:
                                up_token_id = tokens[i]
                            elif outcome_lower in ["down", "no"]:
                                down_token_id = tokens[i]
                except Exception as e:
                    logger.error("Failed to parse token IDs", error=str(e))
            
            # Get end date
            end_date_str = event.get("endDate") or market.get("endDate")
            end_date = None
            if end_date_str:
                try:
                    end_date = datetime.fromisoformat(end_date_str.replace("Z", "+00:00"))
                except:
                    pass
            
            return {
                "condition_id": market.get("conditionId"),
                "question_id": market.get("questionID") or str(event_id),
                "slug": event.get("slug"),
                "title": event.get("title") or market.get("question", ""),
                "description": market.get("description"),
                "asset": asset,
                "market_type": "15min",
                "end_date": end_date,
                "yes_token_id": up_token_id,  # "Up" = "Yes" for our purposes
                "no_token_id": down_token_id,  # "Down" = "No" for our purposes
                "active": True,
            }
            
        except Exception as e:
            logger.error("Failed to fetch event details", event_id=event_id, error=str(e))
            return None
    
    async def _store_market(self, market_info: Dict[str, Any]) -> None:
        """Store market in database with upsert."""
        try:
            async with get_db_session() as session:
                stmt = insert(Market).values(**market_info).on_conflict_do_update(
                    index_elements=["condition_id"],
                    set_={
                        "title": market_info["title"],
                        "end_date": market_info["end_date"],
                        "yes_token_id": market_info["yes_token_id"],
                        "no_token_id": market_info["no_token_id"],
                        "active": market_info["active"],
                        "updated_at": datetime.now(timezone.utc),
                    }
                )
                await session.execute(stmt)
                await session.commit()
        except Exception as e:
            logger.error("Failed to store market", error=str(e))
    
    async def get_active_markets(
        self, asset: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Get active markets from database."""
        async with get_db_session() as session:
            query = select(Market).where(Market.active == True)
            
            if asset:
                query = query.where(Market.asset == asset)
            
            result = await session.execute(query)
            markets = result.scalars().all()
            
            return [
                {
                    "id": m.id,
                    "condition_id": m.condition_id,
                    "question_id": m.question_id,
                    "slug": m.slug,
                    "title": m.title,
                    "asset": m.asset,
                    "end_date": m.end_date.isoformat() if m.end_date else None,
                    "yes_token_id": m.yes_token_id,
                    "no_token_id": m.no_token_id,
                    "active": m.active,
                }
                for m in markets
            ]
    
    async def get_market_by_id(self, market_id: int) -> Optional[Dict[str, Any]]:
        """Get market by ID."""
        async with get_db_session() as session:
            result = await session.execute(
                select(Market).where(Market.id == market_id)
            )
            market = result.scalar_one_or_none()
            
            if market:
                return {
                    "id": market.id,
                    "condition_id": market.condition_id,
                    "question_id": market.question_id,
                    "slug": market.slug,
                    "title": market.title,
                    "asset": market.asset,
                    "end_date": market.end_date.isoformat() if market.end_date else None,
                    "yes_token_id": market.yes_token_id,
                    "no_token_id": market.no_token_id,
                    "active": market.active,
                }
            
            return None
    
    async def get_tradable_market(self, asset: str) -> Optional[Dict[str, Any]]:
        """Get the current tradable market for an asset."""
        now = datetime.now(timezone.utc)
        buffer_minutes = settings.MARKET_CLOSE_BUFFER_MINUTES
        
        async with get_db_session() as session:
            # Find market that:
            # 1. Is for the correct asset
            # 2. Is active
            # 3. Ends in the future (with buffer)
            min_end_time = now + timedelta(minutes=buffer_minutes)
            
            result = await session.execute(
                select(Market)
                .where(
                    and_(
                        Market.asset == asset,
                        Market.active == True,
                        Market.end_date > min_end_time,
                    )
                )
                .order_by(Market.end_date)
                .limit(1)
            )
            market = result.scalar_one_or_none()
            
            if market:
                return {
                    "id": market.id,
                    "condition_id": market.condition_id,
                    "yes_token_id": market.yes_token_id,
                    "no_token_id": market.no_token_id,
                    "end_date": market.end_date.isoformat() if market.end_date else None,
                    "title": market.title,
                }
            
            return None
    
    async def fetch_orderbook(
        self, token_id: str
    ) -> Optional[Dict[str, Any]]:
        """Fetch orderbook from CLOB API."""
        async with self._get_http_client(timeout=10.0) as client:
            try:
                url = f"{self.CLOB_BASE_URL}/book"
                params = {"token_id": token_id}
                
                response = await client.get(url, params=params)
                response.raise_for_status()
                
                data = response.json()
                
                # Extract best bid/ask
                bids = data.get("bids", [])
                asks = data.get("asks", [])
                
                best_bid = Decimal(bids[0]["price"]) if bids else None
                best_ask = Decimal(asks[0]["price"]) if asks else None
                
                bid_depth = sum(Decimal(b["size"]) for b in bids[:10])
                ask_depth = sum(Decimal(a["size"]) for a in asks[:10])
                
                spread = None
                if best_bid and best_ask:
                    spread = float(best_ask - best_bid)
                
                return {
                    "token_id": token_id,
                    "best_bid": float(best_bid) if best_bid else None,
                    "best_ask": float(best_ask) if best_ask else None,
                    "bid_depth": float(bid_depth),
                    "ask_depth": float(ask_depth),
                    "spread": spread,
                    "bids": bids[:10],
                    "asks": asks[:10],
                }
                
            except Exception as e:
                logger.error("Failed to fetch orderbook", token_id=token_id, error=str(e))
                return None
    
    async def store_snapshot(
        self, market_id: int, orderbook: Dict[str, Any]
    ) -> None:
        """Store market snapshot."""
        try:
            async with get_db_session() as session:
                snapshot = MarketSnapshot(
                    market_id=market_id,
                    best_bid=orderbook.get("best_bid"),
                    best_ask=orderbook.get("best_ask"),
                    bid_depth=orderbook.get("bid_depth"),
                    ask_depth=orderbook.get("ask_depth"),
                    spread=orderbook.get("spread"),
                )
                session.add(snapshot)
                await session.commit()
        except Exception as e:
            logger.error("Failed to store snapshot", error=str(e))
    
    async def check_liquidity(
        self, token_id: str, min_liquidity_usd: float
    ) -> bool:
        """Check if market has sufficient liquidity."""
        orderbook = await self.fetch_orderbook(token_id)
        
        if not orderbook:
            return False
        
        total_depth = orderbook.get("bid_depth", 0) + orderbook.get("ask_depth", 0)
        
        return total_depth >= min_liquidity_usd
    
    async def mark_market_inactive(self, market_id: int) -> None:
        """Mark a market as inactive."""
        async with get_db_session() as session:
            result = await session.execute(
                select(Market).where(Market.id == market_id)
            )
            market = result.scalar_one_or_none()
            
            if market:
                market.active = False
                await session.commit()