"""
PolyTrader Configuration Routes
"""

from datetime import datetime, timezone
from typing import Dict, Any

import structlog
from fastapi import APIRouter, HTTPException, Body
from pydantic import BaseModel
from sqlalchemy import select

from app.db.database import get_db_session
from app.db.models.models import Config, AuditLog
from app.services.risk_service import RiskManager
from app.core.config import settings

logger = structlog.get_logger(__name__)
router = APIRouter()

risk_manager = RiskManager()


class ConfigUpdateRequest(BaseModel):
    """Request body for config updates."""
    value: Any
    user: str = "api"


@router.get("/")
async def get_all_config() -> Dict[str, Any]:
    """Get all configuration values."""
    config = await risk_manager.load_config(force=True)
    
    # Add descriptions
    descriptions = {
        "portfolio_trade_pct": "Percentage of portfolio per trade",
        "max_market_usd": "Maximum USD per market",
        "max_market_portfolio_pct": "Maximum portfolio percentage per market",
        "correlation_max_basket_pct": "Maximum correlated basket exposure",
        "daily_loss_limit_usd": "Daily loss limit in USD",
        "take_profit_pct": "Take profit percentage",
        "stop_loss_pct": "Stop loss percentage",
        "min_liquidity_usd": "Minimum market liquidity",
        "market_close_buffer_minutes": "Buffer before market close",
        "stale_data_threshold_seconds": "Stale data threshold",
        "max_open_positions": "Maximum open positions",
        "llm_advisor_enabled": "LLM advisory enabled",
    }
    
    return {
        "config": {
            key: {
                "value": value,
                "description": descriptions.get(key, ""),
            }
            for key, value in config.items()
        },
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/{key}")
async def get_config_value(key: str) -> Dict[str, Any]:
    """Get a specific configuration value."""
    value = await risk_manager.get_config_value(key)
    
    if value is None:
        raise HTTPException(status_code=404, detail=f"Config key '{key}' not found")
    
    return {
        "key": key,
        "value": value,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.put("/{key}")
async def update_config_value(
    key: str,
    request: ConfigUpdateRequest = Body(...),
) -> Dict[str, Any]:
    """Update a configuration value."""
    async with get_db_session() as session:
        result = await session.execute(
            select(Config).where(Config.key == key)
        )
        config = result.scalar_one_or_none()
        
        if not config:
            raise HTTPException(status_code=404, detail=f"Config key '{key}' not found")
        
        old_value = config.value
        config.value = request.value
        config.updated_by = request.user
        
        # Audit log
        audit = AuditLog(
            event_type="config_update",
            details={
                "key": key,
                "old_value": old_value,
                "new_value": request.value,
            },
            user_id=request.user,
        )
        session.add(audit)
        
        await session.commit()
    
    # Clear config cache
    await risk_manager.load_config(force=True)
    
    logger.info(
        "Config updated",
        key=key,
        old_value=old_value,
        new_value=request.value,
        user=request.user,
    )
    
    return {
        "key": key,
        "value": request.value,
        "previous_value": old_value,
        "updated_by": request.user,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/defaults/safe")
async def get_safe_defaults() -> Dict[str, Any]:
    """Get safe default configuration for $500 portfolio."""
    return {
        "defaults": {
            "portfolio_trade_pct": 5,
            "max_market_usd": 100,
            "max_market_portfolio_pct": 20,
            "correlation_max_basket_pct": 35,
            "daily_loss_limit_usd": 25,
            "take_profit_pct": 8,
            "stop_loss_pct": 5,
            "min_liquidity_usd": 500,
            "market_close_buffer_minutes": 2,
            "stale_data_threshold_seconds": 60,
            "max_open_positions": 5,
            "llm_advisor_enabled": False,
        },
        "portfolio_size": 500,
        "description": "Conservative defaults for $500 portfolio",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/recommended/{portfolio_size}")
async def get_recommended_settings(portfolio_size: float) -> Dict[str, Any]:
    """Get recommended settings based on portfolio size."""
    
    # Scale settings based on portfolio size
    # Base: $500 portfolio
    scale = portfolio_size / 500.0
    
    # Calculate recommended values
    if portfolio_size <= 100:
        # Very small portfolio - ultra conservative
        trade_size = max(5, portfolio_size * 0.05)
        max_market = max(10, portfolio_size * 0.15)
        daily_loss = max(5, portfolio_size * 0.05)
        max_positions = 2
    elif portfolio_size <= 500:
        # Small portfolio - conservative
        trade_size = portfolio_size * 0.04
        max_market = portfolio_size * 0.20
        daily_loss = portfolio_size * 0.05
        max_positions = 3
    elif portfolio_size <= 2000:
        # Medium portfolio - balanced
        trade_size = portfolio_size * 0.03
        max_market = portfolio_size * 0.15
        daily_loss = portfolio_size * 0.04
        max_positions = 5
    elif portfolio_size <= 10000:
        # Large portfolio - can take more positions
        trade_size = portfolio_size * 0.02
        max_market = portfolio_size * 0.10
        daily_loss = portfolio_size * 0.03
        max_positions = 8
    else:
        # Very large portfolio
        trade_size = portfolio_size * 0.015
        max_market = min(portfolio_size * 0.08, 5000)
        daily_loss = portfolio_size * 0.02
        max_positions = 10
    
    recommended = {
        "trade_size_usd": round(trade_size, 2),
        "max_position_per_market": round(max_market, 2),
        "daily_loss_limit_usd": round(daily_loss, 2),
        "max_open_positions": max_positions,
        "take_profit_pct": 8.0,
        "stop_loss_pct": 5.0,
        "correlation_cap_pct": 35.0,
        "min_liquidity_usd": max(200, portfolio_size * 0.5),
        "confidence_threshold": 0.6,
        "min_edge_required": 0.02,
    }
    
    return {
        "portfolio_size": portfolio_size,
        "recommended": recommended,
        "risk_level": "conservative" if portfolio_size <= 500 else "balanced" if portfolio_size <= 2000 else "aggressive",
        "notes": [
            f"Trade size: ${recommended['trade_size_usd']:.2f} per trade (~{(recommended['trade_size_usd']/portfolio_size)*100:.1f}% of portfolio)",
            f"Max {max_positions} positions open at once",
            f"Daily loss limit: ${recommended['daily_loss_limit_usd']:.2f} ({(recommended['daily_loss_limit_usd']/portfolio_size)*100:.1f}%)",
            "Stop loss at 5% protects against sudden moves",
            "Take profit at 8% locks in gains",
        ],
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.post("/apply-recommended/{portfolio_size}")
async def apply_recommended_settings(portfolio_size: float) -> Dict[str, Any]:
    """Apply recommended settings for a portfolio size."""
    
    # Get recommended settings
    rec_response = await get_recommended_settings(portfolio_size)
    recommended = rec_response["recommended"]
    
    applied = []
    errors = []
    
    async with get_db_session() as session:
        for key, value in recommended.items():
            try:
                result = await session.execute(
                    select(Config).where(Config.key == key)
                )
                config = result.scalar_one_or_none()
                
                if config:
                    old_value = config.value
                    config.value = str(value)
                    config.updated_by = "auto_recommended"
                    applied.append({"key": key, "old": old_value, "new": str(value)})
                else:
                    # Create new config entry
                    new_config = Config(
                        key=key,
                        value=str(value),
                        description=f"Auto-set for ${portfolio_size} portfolio",
                        updated_by="auto_recommended",
                    )
                    session.add(new_config)
                    applied.append({"key": key, "old": None, "new": str(value)})
                    
            except Exception as e:
                errors.append({"key": key, "error": str(e)})
        
        # Also save portfolio size
        result = await session.execute(
            select(Config).where(Config.key == "portfolio_size_usd")
        )
        portfolio_config = result.scalar_one_or_none()
        if portfolio_config:
            portfolio_config.value = str(portfolio_size)
        else:
            session.add(Config(
                key="portfolio_size_usd",
                value=str(portfolio_size),
                description="Total portfolio size in USD",
                updated_by="auto_recommended",
            ))
        
        # Audit log
        audit = AuditLog(
            event_type="apply_recommended_settings",
            details={
                "portfolio_size": portfolio_size,
                "applied": applied,
                "errors": errors,
            },
            user_id="dashboard",
        )
        session.add(audit)
        
        await session.commit()
    
    # Clear config cache
    await risk_manager.load_config(force=True)
    
    logger.info(
        "Applied recommended settings",
        portfolio_size=portfolio_size,
        applied_count=len(applied),
    )
    
    return {
        "success": True,
        "portfolio_size": portfolio_size,
        "applied": applied,
        "errors": errors,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/network")
async def get_network_config() -> Dict[str, Any]:
    """Get network configuration (proxy, RPC)."""
    return {
        "proxy_enabled": settings.PROXY_ENABLED,
        "proxy_url": settings.PROXY_URL[:20] + "..." if settings.PROXY_URL and len(settings.PROXY_URL) > 20 else settings.PROXY_URL,  # Mask for security
        "polygon_rpc_url": settings.POLYGON_RPC_URL,
        "polymarket_clob_url": settings.POLYMARKET_CLOB_URL,
        "polymarket_gamma_url": settings.POLYMARKET_GAMMA_URL,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.put("/network")
async def update_network_config(
    request: Dict[str, Any] = Body(...),
) -> Dict[str, Any]:
    """Update network configuration. Note: Requires service restart to take effect."""
    import os
    
    updates = []
    env_path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__)))), ".env")
    
    # Read existing .env
    env_lines = []
    if os.path.exists(env_path):
        with open(env_path, "r") as f:
            env_lines = f.readlines()
    
    # Update values
    keys_to_update = {
        "proxy_url": "PROXY_URL",
        "proxy_enabled": "PROXY_ENABLED",
        "polygon_rpc_url": "POLYGON_RPC_URL",
    }
    
    for req_key, env_key in keys_to_update.items():
        if req_key in request:
            value = request[req_key]
            if isinstance(value, bool):
                value = "true" if value else "false"
            
            # Find and update or append
            found = False
            for i, line in enumerate(env_lines):
                if line.startswith(f"{env_key}="):
                    env_lines[i] = f"{env_key}={value}\n"
                    found = True
                    break
            
            if not found:
                env_lines.append(f"{env_key}={value}\n")
            
            updates.append({"key": env_key, "value": value if env_key != "PROXY_URL" else "***"})
    
    # Write back
    with open(env_path, "w") as f:
        f.writelines(env_lines)
    
    logger.info("Network config updated", updates=updates)
    
    return {
        "success": True,
        "updates": updates,
        "message": "Settings saved. Restart services to apply changes.",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }