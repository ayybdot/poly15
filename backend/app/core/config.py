"""
PolyTrader Configuration
Application settings loaded from environment variables.
"""

from functools import lru_cache
from typing import Optional

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings."""
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )
    
    # Database
    DATABASE_URL: str = "postgresql://polytrader:polytrader@localhost:5432/polytrader"
    DB_HOST: str = "localhost"
    DB_PORT: int = 5432
    DB_NAME: str = "polytrader"
    DB_USER: str = "polytrader"
    DB_PASSWORD: str = "polytrader"
    
    # API Server
    API_HOST: str = "0.0.0.0"
    API_PORT: int = 8000
    
    # Polymarket API
    POLYMARKET_API_KEY: str = ""
    POLYMARKET_API_SECRET: str = ""
    POLYMARKET_API_PASSPHRASE: str = ""
    POLYMARKET_PRIVATE_KEY: str = ""
    POLYMARKET_FUNDER_ADDRESS: str = ""
    
    # Polymarket endpoints
    POLYMARKET_GAMMA_URL: str = "https://gamma-api.polymarket.com"
    POLYMARKET_CLOB_URL: str = "https://clob.polymarket.com"
    POLYMARKET_CLOB_WS_URL: str = "wss://ws-subscriptions-clob.polymarket.com/ws"
    
    # Proxy settings (for bypassing Cloudflare blocks)
    PROXY_URL: str = ""  # e.g., "http://user:pass@proxy.example.com:8080"
    PROXY_ENABLED: bool = False
    
    # Custom RPC endpoint for Polygon
    POLYGON_RPC_URL: str = "https://polygon-rpc.com"  # Default public RPC
    
    # Coinbase
    COINBASE_API_URL: str = "https://api.coinbase.com"
    COINBASE_WS_URL: str = "wss://ws-feed.exchange.coinbase.com"
    
    # Risk Management
    PORTFOLIO_TRADE_PCT: float = 5.0
    MAX_MARKET_USD: float = 100.0
    MAX_MARKET_PORTFOLIO_PCT: float = 20.0
    CORRELATION_MAX_BASKET_PCT: float = 35.0
    DAILY_LOSS_LIMIT_USD: float = 25.0
    TAKE_PROFIT_PCT: float = 8.0
    STOP_LOSS_PCT: float = 5.0
    MIN_LIQUIDITY_USD: float = 500.0
    MARKET_CLOSE_BUFFER_MINUTES: int = 2
    STALE_DATA_THRESHOLD_SECONDS: int = 60
    MAX_OPEN_POSITIONS: int = 5
    
    # LLM Advisory
    LLM_ADVISOR_ENABLED: bool = False
    OPENAI_API_KEY: str = ""
    
    # Logging
    LOG_LEVEL: str = "INFO"
    LOG_FORMAT: str = "json"
    
    # Environment
    ENVIRONMENT: str = "production"
    
    # Trading assets
    TRADING_ASSETS: list[str] = Field(default=["BTC", "ETH", "SOL"])
    
    @property
    def coinbase_pairs(self) -> list[str]:
        """Get Coinbase trading pairs."""
        return [f"{asset}-USD" for asset in self.TRADING_ASSETS]
    
    @property
    def async_database_url(self) -> str:
        """Get async database URL for asyncpg."""
        return self.DATABASE_URL.replace("postgresql://", "postgresql+asyncpg://")


@lru_cache
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()


settings = get_settings()