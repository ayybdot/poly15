"""
PolyTrader Health Check Routes
"""

from datetime import datetime, timezone
from typing import Dict, Any

import structlog
from fastapi import APIRouter, Depends
from sqlalchemy import text, select, desc
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_session
from app.services.risk_service import RiskManager

logger = structlog.get_logger(__name__)
router = APIRouter()

risk_manager = RiskManager()


@router.get("/")
async def health_check(
    session: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    """Basic health check endpoint."""
    checks = {
        "api": "ok",
        "database": "unknown",
        "bot_state": "unknown",
    }
    
    # Database check
    try:
        await session.execute(text("SELECT 1"))
        checks["database"] = "ok"
    except Exception as e:
        checks["database"] = f"error: {str(e)}"
    
    # Bot state check
    try:
        state = await risk_manager.get_bot_state()
        checks["bot_state"] = state
    except Exception as e:
        checks["bot_state"] = f"error: {str(e)}"
    
    overall = "healthy" if all(
        v == "ok" or v in risk_manager.STATES 
        for v in checks.values()
    ) else "unhealthy"
    
    return {
        "status": overall,
        "checks": checks,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "version": "1.0.0",
    }


@router.get("/detailed")
async def detailed_health_check(
    session: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    """Detailed health check with all component statuses."""
    from app.services.price_service import PriceService
    from app.core.config import settings
    
    components = {}
    
    # Database
    try:
        result = await session.execute(text("SELECT COUNT(*) FROM config"))
        count = result.scalar()
        components["database"] = {
            "status": "ok",
            "config_count": count,
        }
    except Exception as e:
        components["database"] = {"status": "error", "error": str(e)}
    
    # Price data freshness
    try:
        price_service = PriceService()
        stale_assets = []
        for asset in settings.TRADING_ASSETS:
            if price_service.is_data_stale(asset, settings.STALE_DATA_THRESHOLD_SECONDS):
                stale_assets.append(asset)
        
        components["price_data"] = {
            "status": "ok" if not stale_assets else "stale",
            "stale_assets": stale_assets,
        }
    except Exception as e:
        components["price_data"] = {"status": "error", "error": str(e)}
    
    # Bot state
    try:
        state = await risk_manager.get_bot_state()
        can_trade, reason = await risk_manager.can_trade()
        components["bot"] = {
            "status": "ok" if can_trade else "restricted",
            "state": state,
            "can_trade": can_trade,
            "reason": reason,
        }
    except Exception as e:
        components["bot"] = {"status": "error", "error": str(e)}
    
    # Circuit breakers
    try:
        tripped = await risk_manager.get_tripped_breakers()
        components["circuit_breakers"] = {
            "status": "ok" if not tripped else "tripped",
            "tripped": tripped,
        }
    except Exception as e:
        components["circuit_breakers"] = {"status": "error", "error": str(e)}
    
    # Overall status
    statuses = [c.get("status", "unknown") for c in components.values()]
    if all(s == "ok" for s in statuses):
        overall = "healthy"
    elif any(s == "error" for s in statuses):
        overall = "unhealthy"
    else:
        overall = "degraded"
    
    return {
        "status": overall,
        "components": components,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/services")
async def get_services_health(
    session: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    """Get health status of all services for dashboard."""
    import httpx
    from app.core.config import settings
    
    services = []
    
    # API Server - always healthy if we're responding
    services.append({
        "name": "api",
        "status": "healthy",
        "lastCheck": datetime.now(timezone.utc).isoformat(),
    })
    
    # Database
    try:
        await session.execute(text("SELECT 1"))
        services.append({
            "name": "database",
            "status": "healthy",
            "lastCheck": datetime.now(timezone.utc).isoformat(),
        })
    except Exception as e:
        services.append({
            "name": "database",
            "status": "down",
            "lastCheck": datetime.now(timezone.utc).isoformat(),
            "error": str(e),
        })
    
    # Worker - check if recent activity in logs or candles
    try:
        from app.db.models.models import Candle
        from sqlalchemy import select, desc
        
        result = await session.execute(
            select(Candle).order_by(desc(Candle.open_time)).limit(1)
        )
        latest_candle = result.scalar_one_or_none()
        
        if latest_candle:
            age = (datetime.now(timezone.utc) - latest_candle.open_time.replace(tzinfo=timezone.utc)).total_seconds()
            if age < 120:  # Less than 2 minutes old
                services.append({
                    "name": "worker",
                    "status": "healthy",
                    "lastCheck": datetime.now(timezone.utc).isoformat(),
                })
            else:
                services.append({
                    "name": "worker",
                    "status": "degraded",
                    "lastCheck": datetime.now(timezone.utc).isoformat(),
                    "message": f"Last candle {int(age)}s ago",
                })
        else:
            services.append({
                "name": "worker",
                "status": "degraded",
                "lastCheck": datetime.now(timezone.utc).isoformat(),
                "message": "No candles found",
            })
    except Exception as e:
        services.append({
            "name": "worker",
            "status": "down",
            "lastCheck": datetime.now(timezone.utc).isoformat(),
            "error": str(e),
        })
    
    # Polymarket API
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get("https://gamma-api.polymarket.com/markets?limit=1")
            if response.status_code == 200:
                services.append({
                    "name": "polymarket",
                    "status": "healthy",
                    "lastCheck": datetime.now(timezone.utc).isoformat(),
                })
            else:
                services.append({
                    "name": "polymarket",
                    "status": "degraded",
                    "lastCheck": datetime.now(timezone.utc).isoformat(),
                    "message": f"Status {response.status_code}",
                })
    except Exception as e:
        services.append({
            "name": "polymarket",
            "status": "down",
            "lastCheck": datetime.now(timezone.utc).isoformat(),
            "error": str(e),
        })
    
    # Prices - check if we have recent price data
    try:
        from app.db.models.models import Candle
        
        result = await session.execute(
            select(Candle).order_by(desc(Candle.open_time)).limit(1)
        )
        candle = result.scalar_one_or_none()
        
        if candle:
            age = (datetime.now(timezone.utc) - candle.open_time.replace(tzinfo=timezone.utc)).total_seconds()
            if age < 60:
                services.append({
                    "name": "prices",
                    "status": "healthy",
                    "lastCheck": datetime.now(timezone.utc).isoformat(),
                })
            else:
                services.append({
                    "name": "prices",
                    "status": "degraded",
                    "lastCheck": datetime.now(timezone.utc).isoformat(),
                    "message": f"Last update {int(age)}s ago",
                })
        else:
            services.append({
                "name": "prices",
                "status": "degraded",
                "lastCheck": datetime.now(timezone.utc).isoformat(),
                "message": "No price data",
            })
    except Exception as e:
        services.append({
            "name": "prices",
            "status": "down",
            "lastCheck": datetime.now(timezone.utc).isoformat(),
            "error": str(e),
        })
    
    return {
        "services": services,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }