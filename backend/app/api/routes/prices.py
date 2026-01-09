"""
PolyTrader Price Data Routes
All price data served from database (stored from Coinbase).
"""

from datetime import datetime, timezone
from typing import Dict, List, Any, Optional

import structlog
from fastapi import APIRouter, Query, HTTPException

from app.services.price_service import PriceService
from app.core.config import settings

logger = structlog.get_logger(__name__)
router = APIRouter()

price_service = PriceService()


@router.get("/latest")
async def get_latest_prices() -> Dict[str, Any]:
    """Get latest prices for all assets from cache/database."""
    # First try cache
    cached = price_service.get_all_latest_prices()
    
    if cached:
        # Add metadata
        prices = []
        for symbol, data in cached.items():
            change_15m = await price_service.get_price_change_15m(symbol)
            is_stale = price_service.is_data_stale(symbol, settings.STALE_DATA_THRESHOLD_SECONDS)
            
            prices.append({
                **data,
                "change_15m_pct": change_15m,
                "is_stale": is_stale,
            })
        
        return {
            "prices": prices,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "source": "coinbase",
        }
    
    # Fall back to database
    db_prices = await price_service.get_latest_prices_from_db()
    
    return {
        "prices": db_prices,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "source": "coinbase",
    }


@router.get("/latest/{symbol}")
async def get_latest_price(symbol: str) -> Dict[str, Any]:
    """Get latest price for a specific asset."""
    symbol = symbol.upper()
    
    if symbol not in settings.TRADING_ASSETS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid symbol. Supported: {settings.TRADING_ASSETS}",
        )
    
    # Try cache first
    cached = price_service.get_latest_price(symbol)
    
    if cached:
        change_15m = await price_service.get_price_change_15m(symbol)
        is_stale = price_service.is_data_stale(symbol, settings.STALE_DATA_THRESHOLD_SECONDS)
        
        return {
            **cached,
            "change_15m_pct": change_15m,
            "is_stale": is_stale,
        }
    
    raise HTTPException(status_code=404, detail=f"No price data for {symbol}")


@router.get("/candles/{symbol}")
async def get_candles(
    symbol: str,
    limit: int = Query(default=100, ge=1, le=500),
) -> Dict[str, Any]:
    """Get 15-minute candles for an asset."""
    symbol = symbol.upper()
    
    if symbol not in settings.TRADING_ASSETS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid symbol. Supported: {settings.TRADING_ASSETS}",
        )
    
    candles = await price_service.get_candles(symbol, limit=limit)
    
    return {
        "symbol": symbol,
        "timeframe": "15m",
        "candles": candles,
        "count": len(candles),
        "source": "coinbase",
    }


@router.get("/change/{symbol}")
async def get_price_change(symbol: str) -> Dict[str, Any]:
    """Get 15-minute price change percentage."""
    symbol = symbol.upper()
    
    if symbol not in settings.TRADING_ASSETS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid symbol. Supported: {settings.TRADING_ASSETS}",
        )
    
    change = await price_service.get_price_change_15m(symbol)
    
    return {
        "symbol": symbol,
        "change_15m_pct": change,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/status")
async def get_price_status() -> Dict[str, Any]:
    """Get price data status for all assets."""
    status = {}
    
    for asset in settings.TRADING_ASSETS:
        latest = price_service.get_latest_price(asset)
        is_stale = price_service.is_data_stale(asset, settings.STALE_DATA_THRESHOLD_SECONDS)
        
        status[asset] = {
            "has_data": latest is not None,
            "is_stale": is_stale,
            "last_update": latest["timestamp"] if latest else None,
            "price": latest["price"] if latest else None,
        }
    
    all_ok = all(
        s["has_data"] and not s["is_stale"] 
        for s in status.values()
    )
    
    return {
        "overall_status": "ok" if all_ok else "degraded",
        "assets": status,
        "threshold_seconds": settings.STALE_DATA_THRESHOLD_SECONDS,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
