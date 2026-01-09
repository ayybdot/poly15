"""
PolyTrader Trading Service
Handles order placement, management, and execution via Polymarket CLOB API.
"""

import asyncio
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Dict, List, Optional, Any

import httpx
import structlog
from sqlalchemy import select, and_, or_
from eth_account import Account
from eth_account.messages import encode_defunct

from app.core.config import settings
from app.db.database import get_db_session
from app.db.models.models import Order, Trade, Position, AuditLog

logger = structlog.get_logger(__name__)


class TradingService:
    """Service for executing trades on Polymarket."""
    
    CLOB_BASE_URL = settings.POLYMARKET_CLOB_URL
    
    # Polymarket fee structure (approximate)
    MAKER_FEE = Decimal("0.00")  # 0% maker fee
    TAKER_FEE = Decimal("0.02")  # 2% taker fee
    
    def __init__(self):
        self.api_key = settings.POLYMARKET_API_KEY
        self.api_secret = settings.POLYMARKET_API_SECRET
        self.private_key = settings.POLYMARKET_PRIVATE_KEY
        self.funder_address = settings.POLYMARKET_FUNDER_ADDRESS
        
        self._account = None
        if self.private_key:
            try:
                self._account = Account.from_key(self.private_key)
            except Exception as e:
                logger.error("Failed to initialize account", error=str(e))
    
    def _get_http_client(self, timeout: float = 30.0) -> httpx.AsyncClient:
        """Get HTTP client with optional proxy support."""
        proxy = settings.PROXY_URL if settings.PROXY_ENABLED and settings.PROXY_URL else None
        return httpx.AsyncClient(timeout=timeout, proxy=proxy)
    
    def _get_headers(self) -> Dict[str, str]:
        """Get API headers."""
        return {
            "Content-Type": "application/json",
        }
    
    def _sign_order(self, order_data: Dict) -> str:
        """Sign order with private key."""
        if not self._account:
            raise ValueError("Account not initialized - private key required")
        
        # Create message to sign (simplified - actual implementation would follow Polymarket spec)
        message = str(order_data)
        message_hash = encode_defunct(text=message)
        signed = self._account.sign_message(message_hash)
        
        return signed.signature.hex()
    
    async def place_limit_order(
        self,
        token_id: str,
        side: str,  # "BUY" or "SELL"
        price: Decimal,
        size: Decimal,
        market_id: int,
        decision_id: Optional[int] = None,
    ) -> Optional[Dict[str, Any]]:
        """Place a limit order on Polymarket."""
        order_id = str(uuid.uuid4())
        
        logger.info(
            "Placing limit order",
            order_id=order_id,
            token_id=token_id,
            side=side,
            price=float(price),
            size=float(size),
        )
        
        # Validate inputs
        if price <= 0 or price >= 1:
            raise ValueError(f"Invalid price: {price}. Must be between 0 and 1.")
        
        if size <= 0:
            raise ValueError(f"Invalid size: {size}. Must be positive.")
        
        # Store order in database first
        async with get_db_session() as session:
            order = Order(
                order_id=order_id,
                market_id=market_id,
                decision_id=decision_id,
                side=side,
                token_id=token_id,
                price=price,
                size=size,
                status="pending",
                order_type="limit",
            )
            session.add(order)
            await session.commit()
            
            # Log audit
            audit = AuditLog(
                event_type="order_placed",
                details={
                    "order_id": order_id,
                    "token_id": token_id,
                    "side": side,
                    "price": float(price),
                    "size": float(size),
                },
            )
            session.add(audit)
            await session.commit()
        
        # Place order via CLOB API
        try:
            if not self.api_key or not self.private_key:
                logger.warning("API credentials not configured - order not sent to exchange")
                return {
                    "order_id": order_id,
                    "status": "simulated",
                    "message": "API credentials not configured",
                }
            
            order_payload = {
                "tokenID": token_id,
                "price": str(price),
                "size": str(size),
                "side": side,
                "feeRateBps": "0",  # Maker order
                "nonce": str(int(datetime.now(timezone.utc).timestamp() * 1000)),
                "expiration": "0",  # No expiration
            }
            
            # Sign the order
            signature = self._sign_order(order_payload)
            order_payload["signature"] = signature
            
            async with self._get_http_client(timeout=30.0) as client:
                response = await client.post(
                    f"{self.CLOB_BASE_URL}/order",
                    json=order_payload,
                    headers=self._get_headers(),
                )
                
                if response.status_code == 200:
                    result = response.json()
                    
                    # Update order with exchange order ID
                    async with get_db_session() as session:
                        db_order = await session.execute(
                            select(Order).where(Order.order_id == order_id)
                        )
                        db_order = db_order.scalar_one_or_none()
                        if db_order:
                            db_order.status = "open"
                            await session.commit()
                    
                    logger.info("Order placed successfully", order_id=order_id)
                    
                    return {
                        "order_id": order_id,
                        "exchange_order_id": result.get("orderID"),
                        "status": "open",
                    }
                else:
                    error_msg = response.text
                    logger.error(
                        "Order placement failed",
                        order_id=order_id,
                        status=response.status_code,
                        error=error_msg,
                    )
                    
                    # Update order status
                    async with get_db_session() as session:
                        db_order = await session.execute(
                            select(Order).where(Order.order_id == order_id)
                        )
                        db_order = db_order.scalar_one_or_none()
                        if db_order:
                            db_order.status = "rejected"
                            db_order.error_message = error_msg
                            await session.commit()
                    
                    return {
                        "order_id": order_id,
                        "status": "rejected",
                        "error": error_msg,
                    }
                    
        except Exception as e:
            logger.error("Order placement error", order_id=order_id, error=str(e))
            
            # Update order status
            async with get_db_session() as session:
                db_order = await session.execute(
                    select(Order).where(Order.order_id == order_id)
                )
                db_order = db_order.scalar_one_or_none()
                if db_order:
                    db_order.status = "error"
                    db_order.error_message = str(e)
                    await session.commit()
            
            return {
                "order_id": order_id,
                "status": "error",
                "error": str(e),
            }
    
    async def place_marketable_limit_order(
        self,
        token_id: str,
        side: str,
        size: Decimal,
        market_id: int,
        decision_id: Optional[int] = None,
        slippage_bps: int = 100,  # 1% slippage
    ) -> Optional[Dict[str, Any]]:
        """Place a marketable limit order (aggressive limit that should fill immediately)."""
        from app.services.market_service import MarketService
        
        market_service = MarketService()
        orderbook = await market_service.fetch_orderbook(token_id)
        
        if not orderbook:
            raise ValueError("Could not fetch orderbook")
        
        # Calculate aggressive price based on side
        if side == "BUY":
            # Buy at best ask + slippage
            best_ask = orderbook.get("best_ask")
            if not best_ask:
                raise ValueError("No asks in orderbook")
            price = Decimal(str(best_ask)) + Decimal(slippage_bps) / Decimal("10000")
            price = min(price, Decimal("0.99"))  # Cap at 0.99
        else:
            # Sell at best bid - slippage
            best_bid = orderbook.get("best_bid")
            if not best_bid:
                raise ValueError("No bids in orderbook")
            price = Decimal(str(best_bid)) - Decimal(slippage_bps) / Decimal("10000")
            price = max(price, Decimal("0.01"))  # Floor at 0.01
        
        return await self.place_limit_order(
            token_id=token_id,
            side=side,
            price=price,
            size=size,
            market_id=market_id,
            decision_id=decision_id,
        )
    
    async def cancel_order(self, order_id: str) -> bool:
        """Cancel an open order."""
        logger.info("Cancelling order", order_id=order_id)
        
        try:
            async with self._get_http_client(timeout=30.0) as client:
                response = await client.delete(
                    f"{self.CLOB_BASE_URL}/order/{order_id}",
                    headers=self._get_headers(),
                )
                
                success = response.status_code == 200
                
                # Update order in database
                async with get_db_session() as session:
                    db_order = await session.execute(
                        select(Order).where(Order.order_id == order_id)
                    )
                    db_order = db_order.scalar_one_or_none()
                    if db_order:
                        db_order.status = "cancelled" if success else db_order.status
                        db_order.cancelled_at = datetime.now(timezone.utc) if success else None
                        await session.commit()
                
                return success
                
        except Exception as e:
            logger.error("Cancel order error", order_id=order_id, error=str(e))
            return False
    
    async def cancel_all_orders(self) -> int:
        """Cancel all open orders."""
        logger.info("Cancelling all open orders")
        
        cancelled = 0
        
        async with get_db_session() as session:
            result = await session.execute(
                select(Order).where(
                    or_(Order.status == "open", Order.status == "pending")
                )
            )
            orders = result.scalars().all()
            
            for order in orders:
                if await self.cancel_order(order.order_id):
                    cancelled += 1
        
        logger.info("Cancelled orders", count=cancelled)
        
        # Log audit
        async with get_db_session() as session:
            audit = AuditLog(
                event_type="cancel_all_orders",
                details={"cancelled_count": cancelled},
            )
            session.add(audit)
            await session.commit()
        
        return cancelled
    
    async def get_open_orders(self) -> List[Dict[str, Any]]:
        """Get all open orders."""
        async with get_db_session() as session:
            result = await session.execute(
                select(Order).where(
                    or_(Order.status == "open", Order.status == "pending")
                ).order_by(Order.created_at.desc())
            )
            orders = result.scalars().all()
            
            return [
                {
                    "order_id": o.order_id,
                    "market_id": o.market_id,
                    "side": o.side,
                    "token_id": o.token_id,
                    "price": float(o.price),
                    "size": float(o.size),
                    "filled_size": float(o.filled_size),
                    "status": o.status,
                    "created_at": o.created_at.isoformat(),
                }
                for o in orders
            ]
    
    async def get_order_history(
        self, limit: int = 100
    ) -> List[Dict[str, Any]]:
        """Get order history."""
        async with get_db_session() as session:
            result = await session.execute(
                select(Order)
                .order_by(Order.created_at.desc())
                .limit(limit)
            )
            orders = result.scalars().all()
            
            return [
                {
                    "order_id": o.order_id,
                    "market_id": o.market_id,
                    "side": o.side,
                    "token_id": o.token_id,
                    "price": float(o.price),
                    "size": float(o.size),
                    "filled_size": float(o.filled_size),
                    "status": o.status,
                    "created_at": o.created_at.isoformat(),
                    "filled_at": o.filled_at.isoformat() if o.filled_at else None,
                }
                for o in orders
            ]
    
    async def reconcile_orders(self) -> Dict[str, Any]:
        """Reconcile local orders with exchange state."""
        logger.info("Starting order reconciliation")
        
        # This would fetch orders from the Data API and compare
        # For now, return placeholder
        return {
            "reconciled": True,
            "mismatches": 0,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    
    async def update_position(
        self,
        market_id: int,
        token_id: str,
        side: str,
        size_change: Decimal,
        price: Decimal,
    ) -> None:
        """Update or create position."""
        async with get_db_session() as session:
            # Find existing open position
            result = await session.execute(
                select(Position).where(
                    and_(
                        Position.market_id == market_id,
                        Position.token_id == token_id,
                        Position.status == "open",
                    )
                )
            )
            position = result.scalar_one_or_none()
            
            if position:
                # Update existing position
                new_size = position.size + size_change
                if new_size <= 0:
                    # Close position
                    position.status = "closed"
                    position.closed_at = datetime.now(timezone.utc)
                    position.size = Decimal("0")
                else:
                    # Update average price
                    total_value = position.size * position.avg_entry_price + size_change * price
                    position.avg_entry_price = total_value / new_size
                    position.size = new_size
            else:
                # Create new position
                position = Position(
                    market_id=market_id,
                    token_id=token_id,
                    side=side,
                    size=size_change,
                    avg_entry_price=price,
                    status="open",
                )
                session.add(position)
            
            await session.commit()
    
    async def get_positions(
        self, status: str = "open"
    ) -> List[Dict[str, Any]]:
        """Get positions."""
        async with get_db_session() as session:
            result = await session.execute(
                select(Position).where(Position.status == status)
            )
            positions = result.scalars().all()
            
            return [
                {
                    "id": p.id,
                    "market_id": p.market_id,
                    "token_id": p.token_id,
                    "side": p.side,
                    "size": float(p.size),
                    "avg_entry_price": float(p.avg_entry_price),
                    "current_price": float(p.current_price) if p.current_price else None,
                    "unrealized_pnl": float(p.unrealized_pnl) if p.unrealized_pnl else None,
                    "realized_pnl": float(p.realized_pnl) if p.realized_pnl else None,
                    "opened_at": p.opened_at.isoformat(),
                    "status": p.status,
                }
                for p in positions
            ]
    
    def calculate_order_value(
        self, price: Decimal, size: Decimal, is_maker: bool = True
    ) -> Dict[str, Decimal]:
        """Calculate order value including fees."""
        fee_rate = self.MAKER_FEE if is_maker else self.TAKER_FEE
        gross_value = price * size
        fee = gross_value * fee_rate
        net_value = gross_value - fee
        
        return {
            "gross_value": gross_value,
            "fee": fee,
            "net_value": net_value,
            "fee_rate": fee_rate,
        }