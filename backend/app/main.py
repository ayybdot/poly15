"""
PolyTrader Backend API
Main FastAPI application entry point.
"""

import asyncio
import logging
from contextlib import asynccontextmanager
from datetime import datetime, timezone

import structlog
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.core.config import settings
from app.core.logging import setup_logging
from app.db.database import engine, create_tables
from app.api.routes import (
    health,
    prices,
    markets,
    trading,
    admin,
    config,
    install,
    positions,
    decisions,
)
from app.services.price_service import PriceService
from app.services.market_service import MarketService

# Setup structured logging
setup_logging()
logger = structlog.get_logger(__name__)

# Global service instances
price_service: PriceService | None = None
market_service: MarketService | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager."""
    global price_service, market_service
    
    logger.info("Starting PolyTrader API", version="1.0.0")
    
    # Create database tables
    await create_tables()
    logger.info("Database tables initialized")
    
    # Initialize services
    price_service = PriceService()
    market_service = MarketService()
    
    # Start background tasks
    app.state.price_service = price_service
    app.state.market_service = market_service
    
    # Start price streaming
    asyncio.create_task(price_service.start_streaming())
    logger.info("Price streaming started")
    
    yield
    
    # Cleanup
    logger.info("Shutting down PolyTrader API")
    if price_service:
        await price_service.stop_streaming()
    logger.info("Shutdown complete")


# Create FastAPI application
app = FastAPI(
    title="PolyTrader API",
    description="Polymarket Autotrader for BTC/ETH/SOL 15-minute markets",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Request logging middleware
@app.middleware("http")
async def log_requests(request: Request, call_next):
    """Log all incoming requests."""
    start_time = datetime.now(timezone.utc)
    
    response = await call_next(request)
    
    duration_ms = (datetime.now(timezone.utc) - start_time).total_seconds() * 1000
    
    logger.info(
        "request_completed",
        method=request.method,
        path=request.url.path,
        status_code=response.status_code,
        duration_ms=round(duration_ms, 2),
    )
    
    return response


# Exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Global exception handler."""
    logger.error(
        "unhandled_exception",
        path=request.url.path,
        error=str(exc),
        exc_info=True,
    )
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error", "error": str(exc)},
    )


# Include routers
app.include_router(health.router, prefix="/v1/health", tags=["Health"])
app.include_router(prices.router, prefix="/v1/prices", tags=["Prices"])
app.include_router(markets.router, prefix="/v1/markets", tags=["Markets"])
app.include_router(trading.router, prefix="/v1/trading", tags=["Trading"])
app.include_router(positions.router, prefix="/v1/positions", tags=["Positions"])
app.include_router(decisions.router, prefix="/v1/decisions", tags=["Decisions"])
app.include_router(admin.router, prefix="/v1/admin", tags=["Admin"])
app.include_router(config.router, prefix="/v1/config", tags=["Config"])
app.include_router(install.router, prefix="/v1/install", tags=["Install"])


@app.get("/")
async def root():
    """Root endpoint."""
    return {
        "name": "PolyTrader API",
        "version": "1.0.0",
        "status": "running",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


if __name__ == "__main__":
    import uvicorn
    
    uvicorn.run(
        "app.main:app",
        host=settings.API_HOST,
        port=settings.API_PORT,
        reload=settings.ENVIRONMENT == "development",
    )