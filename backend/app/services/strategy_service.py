"""
PolyTrader Strategy Service
Generates trading signals based on Coinbase price data analysis.
"""

import asyncio
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from typing import Dict, List, Optional, Any, Tuple

import numpy as np
import structlog
from sqlalchemy import select, desc

from app.core.config import settings
from app.db.database import get_db_session
from app.db.models.models import Candle, Decision
from app.services.price_service import PriceService
from app.services.market_service import MarketService

logger = structlog.get_logger(__name__)


class StrategyService:
    """Strategy service for generating trading signals."""
    
    def __init__(self):
        self.price_service = PriceService()
        self.market_service = MarketService()
        
        # Feature configuration
        self.lookback_periods = 20  # Number of candles for analysis
        self.momentum_periods = [3, 5, 10]  # Momentum calculation periods
        self.ma_periods = [5, 10, 20]  # Moving average periods
        self.rsi_period = 14
        self.volatility_period = 14
        self.zscore_period = 20
    
    async def analyze_asset(self, asset: str) -> Dict[str, Any]:
        """Analyze an asset and generate trading signal."""
        logger.info("Analyzing asset", asset=asset)
        
        # Get candle data from database
        candles = await self.price_service.get_candles(asset, limit=50)
        
        if len(candles) < self.lookback_periods:
            logger.warning("Insufficient candle data", asset=asset, count=len(candles))
            return {
                "asset": asset,
                "signal": "NEUTRAL",
                "confidence": 0.0,
                "reason": "Insufficient data",
                "features": {},
            }
        
        # Extract close prices
        closes = np.array([c["close"] for c in candles])
        highs = np.array([c["high"] for c in candles])
        lows = np.array([c["low"] for c in candles])
        volumes = np.array([c["volume"] for c in candles])
        
        # Calculate features
        features = self._calculate_features(closes, highs, lows, volumes)
        
        # Generate signal
        signal, confidence = self._generate_signal(features)
        
        # Store decision
        await self._store_decision(asset, signal, confidence, features)
        
        return {
            "asset": asset,
            "signal": signal,  # "UP", "DOWN", or "NEUTRAL"
            "confidence": confidence,
            "features": features,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "last_price": float(closes[-1]),
        }
    
    def _calculate_features(
        self,
        closes: np.ndarray,
        highs: np.ndarray,
        lows: np.ndarray,
        volumes: np.ndarray,
    ) -> Dict[str, float]:
        """Calculate all technical features."""
        features = {}
        
        # Returns
        returns = np.diff(closes) / closes[:-1]
        features["return_1"] = float(returns[-1]) if len(returns) > 0 else 0
        features["return_3"] = float(np.sum(returns[-3:])) if len(returns) >= 3 else 0
        features["return_5"] = float(np.sum(returns[-5:])) if len(returns) >= 5 else 0
        
        # Momentum
        for period in self.momentum_periods:
            if len(closes) > period:
                momentum = (closes[-1] - closes[-period-1]) / closes[-period-1]
                features[f"momentum_{period}"] = float(momentum)
        
        # Moving Averages
        for period in self.ma_periods:
            if len(closes) >= period:
                ma = np.mean(closes[-period:])
                features[f"ma_{period}"] = float(ma)
                features[f"price_vs_ma_{period}"] = float((closes[-1] - ma) / ma)
        
        # MA Crossovers
        if "ma_5" in features and "ma_10" in features:
            features["ma_5_10_cross"] = 1.0 if features["ma_5"] > features["ma_10"] else -1.0
        if "ma_5" in features and "ma_20" in features:
            features["ma_5_20_cross"] = 1.0 if features["ma_5"] > features["ma_20"] else -1.0
        
        # RSI
        features["rsi"] = self._calculate_rsi(closes, self.rsi_period)
        
        # Volatility (Standard deviation of returns)
        if len(returns) >= self.volatility_period:
            features["volatility"] = float(np.std(returns[-self.volatility_period:]))
        
        # Z-Score of current price
        if len(closes) >= self.zscore_period:
            mean = np.mean(closes[-self.zscore_period:])
            std = np.std(closes[-self.zscore_period:])
            if std > 0:
                features["zscore"] = float((closes[-1] - mean) / std)
        
        # Price range position (where price is in high-low range)
        recent_high = np.max(highs[-self.lookback_periods:])
        recent_low = np.min(lows[-self.lookback_periods:])
        if recent_high > recent_low:
            features["range_position"] = float(
                (closes[-1] - recent_low) / (recent_high - recent_low)
            )
        
        # Volume analysis
        if len(volumes) >= 10:
            avg_volume = np.mean(volumes[-10:])
            if avg_volume > 0:
                features["volume_ratio"] = float(volumes[-1] / avg_volume)
        
        # Trend strength (slope of linear regression)
        if len(closes) >= 10:
            x = np.arange(10)
            slope, _ = np.polyfit(x, closes[-10:], 1)
            features["trend_slope"] = float(slope / closes[-10])
        
        return features
    
    def _calculate_rsi(self, closes: np.ndarray, period: int) -> float:
        """Calculate Relative Strength Index."""
        if len(closes) < period + 1:
            return 50.0
        
        deltas = np.diff(closes)
        gains = np.where(deltas > 0, deltas, 0)
        losses = np.where(deltas < 0, -deltas, 0)
        
        avg_gain = np.mean(gains[-period:])
        avg_loss = np.mean(losses[-period:])
        
        if avg_loss == 0:
            return 100.0
        
        rs = avg_gain / avg_loss
        rsi = 100 - (100 / (1 + rs))
        
        return float(rsi)
    
    def _generate_signal(
        self, features: Dict[str, float]
    ) -> Tuple[str, float]:
        """Generate trading signal from features."""
        # Scoring system
        bullish_score = 0.0
        bearish_score = 0.0
        total_weight = 0.0
        
        # Momentum signals (weight: 2)
        momentum_weight = 2.0
        for period in self.momentum_periods:
            key = f"momentum_{period}"
            if key in features:
                total_weight += momentum_weight
                if features[key] > 0.005:  # 0.5% threshold
                    bullish_score += momentum_weight
                elif features[key] < -0.005:
                    bearish_score += momentum_weight
        
        # MA crossover signals (weight: 1.5)
        ma_weight = 1.5
        if "ma_5_10_cross" in features:
            total_weight += ma_weight
            if features["ma_5_10_cross"] > 0:
                bullish_score += ma_weight
            else:
                bearish_score += ma_weight
        
        if "ma_5_20_cross" in features:
            total_weight += ma_weight
            if features["ma_5_20_cross"] > 0:
                bullish_score += ma_weight
            else:
                bearish_score += ma_weight
        
        # RSI signals (weight: 1.5)
        rsi_weight = 1.5
        if "rsi" in features:
            total_weight += rsi_weight
            rsi = features["rsi"]
            if rsi < 30:  # Oversold - bullish
                bullish_score += rsi_weight
            elif rsi > 70:  # Overbought - bearish
                bearish_score += rsi_weight
        
        # Z-Score signals (weight: 1)
        zscore_weight = 1.0
        if "zscore" in features:
            total_weight += zscore_weight
            zscore = features["zscore"]
            if zscore < -1.5:  # Below average - potential reversal up
                bullish_score += zscore_weight
            elif zscore > 1.5:  # Above average - potential reversal down
                bearish_score += zscore_weight
        
        # Trend slope (weight: 2)
        trend_weight = 2.0
        if "trend_slope" in features:
            total_weight += trend_weight
            if features["trend_slope"] > 0:
                bullish_score += trend_weight
            elif features["trend_slope"] < 0:
                bearish_score += trend_weight
        
        # Calculate confidence
        if total_weight == 0:
            return "NEUTRAL", 0.0
        
        net_score = (bullish_score - bearish_score) / total_weight
        confidence = abs(net_score)
        
        # Determine signal
        if net_score > 0.3:
            signal = "UP"
        elif net_score < -0.3:
            signal = "DOWN"
        else:
            signal = "NEUTRAL"
            confidence = 0.0
        
        # Cap confidence at 0.95
        confidence = min(confidence, 0.95)
        
        logger.info(
            "Signal generated",
            signal=signal,
            confidence=confidence,
            bullish_score=bullish_score,
            bearish_score=bearish_score,
        )
        
        return signal, confidence
    
    async def _store_decision(
        self,
        asset: str,
        signal: str,
        confidence: float,
        features: Dict[str, float],
    ) -> int:
        """Store decision in database."""
        async with get_db_session() as session:
            decision = Decision(
                asset=asset,
                direction=signal,
                confidence=Decimal(str(confidence)),
                features=features,
                signal_source="technical",
                executed=False,
            )
            session.add(decision)
            await session.commit()
            await session.refresh(decision)
            return decision.id
    
    async def get_latest_decision(self, asset: str) -> Optional[Dict[str, Any]]:
        """Get the most recent decision for an asset."""
        async with get_db_session() as session:
            result = await session.execute(
                select(Decision)
                .where(Decision.asset == asset)
                .order_by(desc(Decision.timestamp))
                .limit(1)
            )
            decision = result.scalar_one_or_none()
            
            if decision:
                return {
                    "id": decision.id,
                    "asset": decision.asset,
                    "direction": decision.direction,
                    "confidence": float(decision.confidence),
                    "features": decision.features,
                    "timestamp": decision.timestamp.isoformat(),
                    "executed": decision.executed,
                }
            return None
    
    async def get_decisions(
        self, asset: Optional[str] = None, limit: int = 50
    ) -> List[Dict[str, Any]]:
        """Get recent decisions."""
        async with get_db_session() as session:
            query = select(Decision).order_by(desc(Decision.timestamp)).limit(limit)
            
            if asset:
                query = query.where(Decision.asset == asset)
            
            result = await session.execute(query)
            decisions = result.scalars().all()
            
            return [
                {
                    "id": d.id,
                    "asset": d.asset,
                    "direction": d.direction,
                    "confidence": float(d.confidence) if d.confidence else 0,
                    "features": d.features,
                    "timestamp": d.timestamp.isoformat(),
                    "executed": d.executed,
                }
                for d in decisions
            ]


class LLMAdvisor:
    """Optional LLM-based advisory (disabled by default)."""
    
    def __init__(self):
        self.enabled = settings.LLM_ADVISOR_ENABLED
        self.api_key = settings.OPENAI_API_KEY
    
    async def get_advisory(
        self,
        asset: str,
        features: Dict[str, float],
        signal: str,
        confidence: float,
    ) -> Optional[Dict[str, Any]]:
        """Get LLM advisory opinion (advisory only, cannot trade)."""
        if not self.enabled or not self.api_key:
            return None
        
        # This would integrate with OpenAI API for advisory
        # Implementation left as placeholder since it's disabled by default
        logger.info("LLM advisory requested but disabled")
        
        return {
            "enabled": False,
            "message": "LLM advisor is disabled by default",
        }
