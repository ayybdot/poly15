"""
PolyTrader Admin Routes
Bot state control and management.
"""

from datetime import datetime, timezone
from decimal import Decimal
from typing import Dict, Any

import structlog
from fastapi import APIRouter, HTTPException, Body
from pydantic import BaseModel
from sqlalchemy import select, func

from app.services.risk_service import RiskManager
from app.services.trading_service import TradingService
from app.db.database import get_db_session
from app.db.models.models import Config, Position

logger = structlog.get_logger(__name__)
router = APIRouter()

risk_manager = RiskManager()
trading_service = TradingService()


class StateChangeRequest(BaseModel):
    """Request body for state changes."""
    reason: str = ""
    user: str = "api"


@router.get("/wallet/balance")
async def get_wallet_balance() -> Dict[str, Any]:
    """Get wallet balance from Polymarket."""
    from app.core.config import settings
    import httpx
    
    balance = Decimal("0")
    available = Decimal("0")
    in_positions = Decimal("0")
    source = "unknown"
    error_msg = None
    
    # Method 1: Try py-clob-client
    if settings.POLYMARKET_PRIVATE_KEY:
        try:
            from py_clob_client.client import ClobClient
            
            host = "https://clob.polymarket.com"
            chain_id = 137  # Polygon mainnet
            
            client = ClobClient(
                host=host,
                chain_id=chain_id,
                key=settings.POLYMARKET_PRIVATE_KEY,
            )
            
            # Derive API credentials
            client.set_api_creds(client.create_or_derive_api_creds())
            
            # Get balance info
            balance_info = client.get_balance_allowance()
            
            if balance_info:
                raw_balance = Decimal(str(balance_info.get("balance", 0)))
                balance = raw_balance / Decimal("1000000")
                
                raw_allowance = Decimal(str(balance_info.get("allowance", 0)))
                available = min(balance, raw_allowance / Decimal("1000000"))
                
                source = "polymarket"
                
        except Exception as e:
            error_msg = str(e)
            logger.warning("py-clob-client failed", error=str(e))
    
    # Method 2: Query USDC balance via Polygon RPC
    if source == "unknown" and settings.POLYMARKET_FUNDER_ADDRESS:
        try:
            async with httpx.AsyncClient(timeout=10.0) as http_client:
                # USDC contract on Polygon
                usdc_contract = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"
                wallet = settings.POLYMARKET_FUNDER_ADDRESS.lower().replace("0x", "")
                
                # ERC20 balanceOf function selector + padded address
                data = f"0x70a08231000000000000000000000000{wallet}"
                
                # Use public Polygon RPC
                response = await http_client.post(
                    "https://polygon-rpc.com",
                    json={
                        "jsonrpc": "2.0",
                        "method": "eth_call",
                        "params": [
                            {
                                "to": usdc_contract,
                                "data": data
                            },
                            "latest"
                        ],
                        "id": 1
                    },
                    headers={"Content-Type": "application/json"}
                )
                
                if response.status_code == 200:
                    result = response.json()
                    if "result" in result and result["result"] != "0x":
                        hex_balance = result["result"]
                        raw_balance = int(hex_balance, 16)
                        balance = Decimal(raw_balance) / Decimal("1000000")  # USDC has 6 decimals
                        available = balance
                        source = "polygon_rpc"
                        error_msg = None
                        
        except Exception as e:
            if error_msg is None:
                error_msg = str(e)
            logger.warning("Polygon RPC failed", error=str(e))
    
    # Method 3: Fall back to config
    if source == "unknown":
        async with get_db_session() as session:
            config_result = await session.execute(
                select(Config).where(Config.key == "portfolio_size_usd")
            )
            config = config_result.scalar_one_or_none()
            
            if config and config.value:
                try:
                    balance = Decimal(config.value)
                    source = "config"
                except:
                    balance = Decimal("500.00")
                    source = "default"
            else:
                balance = Decimal("500.00")
                source = "default"
            
            available = balance
    
    # Get positions from DB
    async with get_db_session() as session:
        positions_result = await session.execute(
            select(func.coalesce(func.sum(Position.size), 0)).where(Position.status == "OPEN")
        )
        in_positions = Decimal(str(positions_result.scalar() or 0))
    
    return {
        "balance": float(balance),
        "available": float(available),
        "in_positions": float(in_positions),
        "currency": "USDC",
        "source": source,
        "error": error_msg,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/bot/state")
async def get_bot_state() -> Dict[str, Any]:
    """Get current bot state."""
    state = await risk_manager.get_bot_state()
    can_trade, reason = await risk_manager.can_trade()
    
    return {
        "state": state,
        "can_trade": can_trade,
        "reason": reason,
        "valid_states": list(risk_manager.STATES.keys()),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.post("/bot/start")
async def start_bot(
    request: StateChangeRequest = Body(default=StateChangeRequest()),
) -> Dict[str, Any]:
    """Start the trading bot."""
    current_state = await risk_manager.get_bot_state()
    
    if current_state == "RUNNING":
        return {
            "success": True,
            "state": "RUNNING",
            "message": "Bot is already running",
        }
    
    # Check if we can start
    if current_state in ["HALTED_DAILY_LOSS", "HALTED_CIRCUIT_BREAKER"]:
        tripped = await risk_manager.get_tripped_breakers()
        if tripped:
            raise HTTPException(
                status_code=400,
                detail=f"Cannot start: Circuit breakers tripped: {tripped}",
            )
    
    await risk_manager.set_bot_state(
        "RUNNING",
        reason=request.reason or "Started via API",
        user=request.user,
    )
    
    logger.info("Bot started", user=request.user, reason=request.reason)
    
    return {
        "success": True,
        "state": "RUNNING",
        "message": "Bot started successfully",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.post("/bot/pause")
async def pause_bot(
    request: StateChangeRequest = Body(default=StateChangeRequest()),
) -> Dict[str, Any]:
    """Pause the trading bot (no new trades, keep positions)."""
    current_state = await risk_manager.get_bot_state()
    
    if current_state == "PAUSED":
        return {
            "success": True,
            "state": "PAUSED",
            "message": "Bot is already paused",
        }
    
    await risk_manager.set_bot_state(
        "PAUSED",
        reason=request.reason or "Paused via API",
        user=request.user,
    )
    
    logger.info("Bot paused", user=request.user, reason=request.reason)
    
    return {
        "success": True,
        "state": "PAUSED",
        "message": "Bot paused successfully",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.post("/bot/stop")
async def stop_bot(
    request: StateChangeRequest = Body(default=StateChangeRequest()),
) -> Dict[str, Any]:
    """Stop the trading bot and cancel all open orders."""
    # Cancel all open orders
    cancelled = await trading_service.cancel_all_orders()
    
    await risk_manager.set_bot_state(
        "STOPPED",
        reason=request.reason or "Stopped via API",
        user=request.user,
    )
    
    logger.info(
        "Bot stopped",
        user=request.user,
        reason=request.reason,
        cancelled_orders=cancelled,
    )
    
    return {
        "success": True,
        "state": "STOPPED",
        "message": "Bot stopped successfully",
        "cancelled_orders": cancelled,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/circuit-breakers")
async def get_circuit_breakers() -> Dict[str, Any]:
    """Get all circuit breaker statuses."""
    breakers = await risk_manager.get_all_breakers()
    tripped = await risk_manager.get_tripped_breakers()
    
    return {
        "breakers": breakers,
        "tripped_count": len(tripped),
        "tripped_names": tripped,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.post("/circuit-breakers/{breaker_name}/reset")
async def reset_circuit_breaker(
    breaker_name: str,
    request: StateChangeRequest = Body(default=StateChangeRequest()),
) -> Dict[str, Any]:
    """Reset a circuit breaker."""
    await risk_manager.reset_breaker(breaker_name)
    
    logger.info(
        "Circuit breaker reset",
        breaker=breaker_name,
        user=request.user,
    )
    
    return {
        "success": True,
        "breaker": breaker_name,
        "message": f"Circuit breaker '{breaker_name}' reset",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.post("/emergency-stop")
async def emergency_stop() -> Dict[str, Any]:
    """Emergency stop - cancel all orders and halt bot immediately."""
    # Cancel all orders
    cancelled = await trading_service.cancel_all_orders()
    
    # Halt bot
    await risk_manager.set_bot_state(
        "HALTED_CIRCUIT_BREAKER",
        reason="Emergency stop triggered",
        user="emergency",
    )
    
    # Trip emergency breaker
    await risk_manager.trip_breaker("emergency", "Manual emergency stop")
    
    logger.warning("EMERGENCY STOP triggered", cancelled_orders=cancelled)
    
    return {
        "success": True,
        "state": "HALTED_CIRCUIT_BREAKER",
        "message": "Emergency stop executed",
        "cancelled_orders": cancelled,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/audit-log")
async def get_audit_log(
    limit: int = 100,
    event_type: str = None,
) -> Dict[str, Any]:
    """Get audit log entries."""
    from sqlalchemy import select, desc
    from app.db.database import get_db_session
    from app.db.models.models import AuditLog
    
    async with get_db_session() as session:
        query = select(AuditLog).order_by(desc(AuditLog.timestamp)).limit(limit)
        
        if event_type:
            query = query.where(AuditLog.event_type == event_type)
        
        result = await session.execute(query)
        logs = result.scalars().all()
        
        return {
            "logs": [
                {
                    "id": log.id,
                    "timestamp": log.timestamp.isoformat(),
                    "event_type": log.event_type,
                    "details": log.details,
                    "user_id": log.user_id,
                }
                for log in logs
            ],
            "count": len(logs),
        }