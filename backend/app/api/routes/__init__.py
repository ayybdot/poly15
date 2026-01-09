"""
PolyTrader API Routes
"""

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

__all__ = [
    "health",
    "prices",
    "markets",
    "trading",
    "admin",
    "config",
    "install",
    "positions",
    "decisions",
]
