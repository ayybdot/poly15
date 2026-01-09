"""
PolyTrader Trading Routes
Order management and execution.
"""

from datetime import datetime, timezone
from decimal import Decimal
from typing import Dict, Any, Optional

import structlog
from fastapi import APIRouter, HTTPException, Body, Query
from pydantic import BaseModel, Field

from app.services.trading_service import TradingService
from app.services.risk_service import RiskManager
from app.services.market_service import MarketService
from app.core.config import settings

logger = structlog.get_logger(__name__)
router = APIRouter()

trading_service = TradingService()
risk_manager = RiskManager()
market_service = MarketService()


class PlaceOrderRequest(BaseModel):
    """Request body for placing orders."""
    market_id: int
    side: str = Field(..., pattern="^(BUY|SELL)$")
    token_type: str = Field(..., pattern="^(YES|NO)$")
    price: Optional[float] = Field(None, ge=0.01, le=0.99)
    size: float = Field(..., gt=0)
    order_type: str = Field(default="limit", pattern="^(limit|marketable)$")


class CancelOrderRequest(BaseModel):
    """Request body for canceling orders."""
    order_id: str


@router.post("/orders")
async def place_order(
    request: PlaceOrderRequest = Body(...),
) -> Dict[str, Any]:
    """Place a new order."""
    # Check if trading is allowed
    can_trade, reason = await risk_manager.can_trade()
    if not can_trade:
        raise HTTPException(
            status_code=403,
            detail=f"Trading not allowed: {reason}",
        )
    
    # Get market
    market = await market_service.get_market_by_id(request.market_id)
    if not market:
        raise HTTPException(status_code=404, detail="Market not found")
    
    # Get token ID based on type
    if request.token_type == "YES":
        token_id = market.get("yes_token_id")
    else:
        token_id = market.get("no_token_id")
    
    if not token_id:
        raise HTTPException(
            status_code=400,
            detail=f"No {request.token_type} token ID for this market",
        )
    
    # Check liquidity
    has_liquidity = await market_service.check_liquidity(
        token_id, settings.MIN_LIQUIDITY_USD
    )
    if not has_liquidity:
        raise HTTPException(
            status_code=400,
            detail=f"Insufficient liquidity (min: ${settings.MIN_LIQUIDITY_USD})",
        )
    
    # Risk checks
    portfolio_value = 500.0  # Default portfolio value
    passed, risk_result = await risk_manager.check_position_risk(
        asset=market.get("asset", ""),
        size_usd=request.size,
        portfolio_value=portfolio_value,
    )
    
    if not passed:
        raise HTTPException(
            status_code=400,
            detail=f"Risk check failed: {', '.join(risk_result['reasons'])}",
        )
    
    # Place order
    if request.order_type == "marketable" or request.price is None:
        result = await trading_service.place_marketable_limit_order(
            token_id=token_id,
            side=request.side,
            size=Decimal(str(request.size)),
            market_id=request.market_id,
        )
    else:
        result = await trading_service.place_limit_order(
            token_id=token_id,
            side=request.side,
            price=Decimal(str(request.price)),
            size=Decimal(str(request.size)),
            market_id=request.market_id,
        )
    
    return {
        "order": result,
        "risk_checks": risk_result,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.delete("/orders/{order_id}")
async def cancel_order(order_id: str) -> Dict[str, Any]:
    """Cancel an order."""
    success = await trading_service.cancel_order(order_id)
    
    if not success:
        raise HTTPException(
            status_code=400,
            detail="Failed to cancel order",
        )
    
    return {
        "success": True,
        "order_id": order_id,
        "message": "Order cancelled",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.post("/orders/cancel-all")
async def cancel_all_orders() -> Dict[str, Any]:
    """Cancel all open orders."""
    cancelled = await trading_service.cancel_all_orders()
    
    return {
        "success": True,
        "cancelled_count": cancelled,
        "message": f"Cancelled {cancelled} orders",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/orders")
async def get_orders(
    status: Optional[str] = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
) -> Dict[str, Any]:
    """Get orders."""
    if status == "open":
        orders = await trading_service.get_open_orders()
    else:
        orders = await trading_service.get_order_history(limit=limit)
    
    return {
        "orders": orders,
        "count": len(orders),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/orders/{order_id}")
async def get_order(order_id: str) -> Dict[str, Any]:
    """Get a specific order."""
    from sqlalchemy import select
    from app.db.database import get_db_session
    from app.db.models.models import Order
    
    async with get_db_session() as session:
        result = await session.execute(
            select(Order).where(Order.order_id == order_id)
        )
        order = result.scalar_one_or_none()
        
        if not order:
            raise HTTPException(status_code=404, detail="Order not found")
        
        return {
            "order_id": order.order_id,
            "market_id": order.market_id,
            "side": order.side,
            "token_id": order.token_id,
            "price": float(order.price),
            "size": float(order.size),
            "filled_size": float(order.filled_size),
            "status": order.status,
            "order_type": order.order_type,
            "created_at": order.created_at.isoformat(),
            "filled_at": order.filled_at.isoformat() if order.filled_at else None,
        }


@router.get("/reconcile")
async def reconcile_orders() -> Dict[str, Any]:
    """Reconcile orders with exchange."""
    result = await trading_service.reconcile_orders()
    
    return {
        "reconciliation": result,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
