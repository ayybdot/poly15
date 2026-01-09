"""
PolyTrader Positions Routes
"""

from datetime import datetime, timezone
from typing import Dict, Any, Optional

import structlog
from fastapi import APIRouter, Query

from app.services.trading_service import TradingService
from app.services.risk_service import RiskManager

logger = structlog.get_logger(__name__)
router = APIRouter()

trading_service = TradingService()
risk_manager = RiskManager()


@router.get("/")
async def get_positions(
    status: str = Query(default="open"),
) -> Dict[str, Any]:
    """Get positions."""
    positions = await trading_service.get_positions(status=status)
    
    return {
        "positions": positions,
        "count": len(positions),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/exposure")
async def get_exposure() -> Dict[str, Any]:
    """Get current exposure by asset."""
    from app.core.config import settings
    
    exposure = {}
    total = 0.0
    
    for asset in settings.TRADING_ASSETS:
        asset_exposure = await risk_manager.get_asset_exposure(asset)
        exposure[asset] = asset_exposure
        total += asset_exposure
    
    metrics = await risk_manager.get_latest_risk_metrics()
    
    return {
        "exposure": exposure,
        "total_exposure": total,
        "risk_metrics": metrics,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/pnl")
async def get_pnl() -> Dict[str, Any]:
    """Get PnL summary."""
    from sqlalchemy import select, desc
    from app.db.database import get_db_session
    from app.db.models.models import DailyPnL
    
    daily_loss = await risk_manager.get_daily_loss()
    
    async with get_db_session() as session:
        result = await session.execute(
            select(DailyPnL).order_by(desc(DailyPnL.date)).limit(30)
        )
        daily_records = result.scalars().all()
    
    return {
        "today_loss": daily_loss,
        "daily_limit": settings.DAILY_LOSS_LIMIT_USD,
        "daily_history": [
            {
                "date": d.date.isoformat() if d.date else None,
                "realized_pnl": float(d.realized_pnl) if d.realized_pnl else 0,
                "fees_paid": float(d.fees_paid) if d.fees_paid else 0,
                "trade_count": d.trade_count,
                "win_count": d.win_count,
                "loss_count": d.loss_count,
            }
            for d in daily_records
        ],
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


from app.core.config import settings
