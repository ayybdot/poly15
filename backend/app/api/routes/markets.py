"""
PolyTrader Markets Routes
Polymarket market discovery and information.
"""

from datetime import datetime, timezone
from typing import Dict, List, Any, Optional

import structlog
from fastapi import APIRouter, Query, HTTPException

from app.services.market_service import MarketService
from app.core.config import settings

logger = structlog.get_logger(__name__)
router = APIRouter()

market_service = MarketService()


@router.get("/")
async def get_markets(
    asset: Optional[str] = Query(default=None),
    active_only: bool = Query(default=True),
) -> Dict[str, Any]:
    """Get all discovered markets."""
    if asset:
        asset = asset.upper()
        if asset not in settings.TRADING_ASSETS:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid asset. Supported: {settings.TRADING_ASSETS}",
            )
    
    markets = await market_service.get_active_markets(asset=asset)
    
    return {
        "markets": markets,
        "count": len(markets),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/discover")
async def discover_markets() -> Dict[str, Any]:
    """Trigger market discovery."""
    logger.info("Manual market discovery triggered")
    
    markets = await market_service.discover_markets()
    
    return {
        "discovered": len(markets),
        "markets": markets,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/tradable/{asset}")
async def get_tradable_market(asset: str) -> Dict[str, Any]:
    """Get the current tradable market for an asset."""
    asset = asset.upper()
    
    if asset not in settings.TRADING_ASSETS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid asset. Supported: {settings.TRADING_ASSETS}",
        )
    
    market = await market_service.get_tradable_market(asset)
    
    if not market:
        raise HTTPException(
            status_code=404,
            detail=f"No tradable market found for {asset}",
        )
    
    return {
        "asset": asset,
        "market": market,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/{market_id}")
async def get_market(market_id: int) -> Dict[str, Any]:
    """Get market by ID."""
    market = await market_service.get_market_by_id(market_id)
    
    if not market:
        raise HTTPException(status_code=404, detail="Market not found")
    
    return market


@router.get("/{market_id}/orderbook")
async def get_orderbook(market_id: int) -> Dict[str, Any]:
    """Get orderbook for a market."""
    market = await market_service.get_market_by_id(market_id)
    
    if not market:
        raise HTTPException(status_code=404, detail="Market not found")
    
    # Get orderbook for YES token
    yes_token = market.get("yes_token_id")
    no_token = market.get("no_token_id")
    
    orderbooks = {}
    
    if yes_token:
        yes_book = await market_service.fetch_orderbook(yes_token)
        if yes_book:
            orderbooks["yes"] = yes_book
    
    if no_token:
        no_book = await market_service.fetch_orderbook(no_token)
        if no_book:
            orderbooks["no"] = no_book
    
    return {
        "market_id": market_id,
        "orderbooks": orderbooks,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/{market_id}/liquidity")
async def check_liquidity(market_id: int) -> Dict[str, Any]:
    """Check market liquidity."""
    market = await market_service.get_market_by_id(market_id)
    
    if not market:
        raise HTTPException(status_code=404, detail="Market not found")
    
    min_liquidity = settings.MIN_LIQUIDITY_USD
    
    yes_token = market.get("yes_token_id")
    no_token = market.get("no_token_id")
    
    yes_ok = False
    no_ok = False
    
    if yes_token:
        yes_ok = await market_service.check_liquidity(yes_token, min_liquidity)
    
    if no_token:
        no_ok = await market_service.check_liquidity(no_token, min_liquidity)
    
    return {
        "market_id": market_id,
        "min_liquidity_usd": min_liquidity,
        "yes_sufficient": yes_ok,
        "no_sufficient": no_ok,
        "tradable": yes_ok and no_ok,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
