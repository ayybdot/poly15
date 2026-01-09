"""
PolyTrader Decisions Routes
Strategy decisions and analysis.
"""

from datetime import datetime, timezone
from typing import Dict, Any, Optional

import structlog
from fastapi import APIRouter, Query, HTTPException

from app.services.strategy_service import StrategyService
from app.core.config import settings

logger = structlog.get_logger(__name__)
router = APIRouter()

strategy_service = StrategyService()


@router.get("/")
async def get_decisions(
    asset: Optional[str] = Query(default=None),
    limit: int = Query(default=50, ge=1, le=200),
) -> Dict[str, Any]:
    """Get recent trading decisions."""
    if asset:
        asset = asset.upper()
        if asset not in settings.TRADING_ASSETS:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid asset. Supported: {settings.TRADING_ASSETS}",
            )
    
    decisions = await strategy_service.get_decisions(asset=asset, limit=limit)
    
    return {
        "decisions": decisions,
        "count": len(decisions),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/latest/{asset}")
async def get_latest_decision(asset: str) -> Dict[str, Any]:
    """Get latest decision for an asset."""
    asset = asset.upper()
    
    if asset not in settings.TRADING_ASSETS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid asset. Supported: {settings.TRADING_ASSETS}",
        )
    
    decision = await strategy_service.get_latest_decision(asset)
    
    if not decision:
        raise HTTPException(
            status_code=404,
            detail=f"No decisions found for {asset}",
        )
    
    return decision


@router.post("/analyze/{asset}")
async def analyze_asset(asset: str) -> Dict[str, Any]:
    """Trigger analysis for an asset."""
    asset = asset.upper()
    
    if asset not in settings.TRADING_ASSETS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid asset. Supported: {settings.TRADING_ASSETS}",
        )
    
    result = await strategy_service.analyze_asset(asset)
    
    return {
        "analysis": result,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.post("/analyze-all")
async def analyze_all_assets() -> Dict[str, Any]:
    """Trigger analysis for all assets."""
    results = {}
    
    for asset in settings.TRADING_ASSETS:
        try:
            result = await strategy_service.analyze_asset(asset)
            results[asset] = result
        except Exception as e:
            results[asset] = {"error": str(e)}
    
    return {
        "analyses": results,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/{decision_id}")
async def get_decision(decision_id: int) -> Dict[str, Any]:
    """Get a specific decision by ID."""
    from sqlalchemy import select
    from app.db.database import get_db_session
    from app.db.models.models import Decision
    
    async with get_db_session() as session:
        result = await session.execute(
            select(Decision).where(Decision.id == decision_id)
        )
        decision = result.scalar_one_or_none()
        
        if not decision:
            raise HTTPException(status_code=404, detail="Decision not found")
        
        return {
            "id": decision.id,
            "asset": decision.asset,
            "direction": decision.direction,
            "confidence": float(decision.confidence) if decision.confidence else 0,
            "features": decision.features,
            "risk_checks": decision.risk_checks,
            "signal_source": decision.signal_source,
            "timestamp": decision.timestamp.isoformat(),
            "executed": decision.executed,
            "execution_id": decision.execution_id,
        }
