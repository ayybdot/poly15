'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'

interface Exposure {
  exposure: { [key: string]: number }
  total_exposure: number
  risk_metrics: {
    timestamp: string
    total_exposure: number
    btc_exposure: number
    eth_exposure: number
    sol_exposure: number
    correlation_risk: number
    daily_loss: number
    portfolio_value: number
  } | null
}

interface Position {
  id: number
  market_id: number
  token_id: string
  side: string
  size: number
  avg_entry_price: number
  current_price: number | null
  unrealized_pnl: number | null
  status: string
  opened_at: string
}

interface CircuitBreaker {
  name: string
  is_tripped: boolean
  trip_reason: string | null
  trip_count: number
  last_trip: string | null
}

export default function ExposurePage() {
  const [exposure, setExposure] = useState<Exposure | null>(null)
  const [positions, setPositions] = useState<Position[]>([])
  const [breakers, setBreakers] = useState<CircuitBreaker[]>([])
  const [loading, setLoading] = useState(true)

  const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000'

  useEffect(() => {
    const fetchData = async () => {
      try {
        const [exposureRes, positionsRes, breakersRes] = await Promise.all([
          fetch(`${API_URL}/v1/positions/exposure`),
          fetch(`${API_URL}/v1/positions/`),
          fetch(`${API_URL}/v1/admin/circuit-breakers`)
        ])

        if (exposureRes.ok) {
          setExposure(await exposureRes.json())
        }
        if (positionsRes.ok) {
          const data = await positionsRes.json()
          setPositions(data.positions || [])
        }
        if (breakersRes.ok) {
          const data = await breakersRes.json()
          setBreakers(data.breakers || [])
        }
      } catch (error) {
        console.error('Failed to fetch data:', error)
      } finally {
        setLoading(false)
      }
    }

    fetchData()
    const interval = setInterval(fetchData, 5000)
    return () => clearInterval(interval)
  }, [API_URL])

  const resetBreaker = async (name: string) => {
    try {
      await fetch(`${API_URL}/v1/admin/circuit-breakers/${name}/reset`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ user: 'dashboard' })
      })
      // Refresh data
      const res = await fetch(`${API_URL}/v1/admin/circuit-breakers`)
      if (res.ok) {
        const data = await res.json()
        setBreakers(data.breakers || [])
      }
    } catch (error) {
      console.error('Failed to reset breaker:', error)
    }
  }

  if (loading) {
    return <div className="min-h-screen p-8 flex items-center justify-center">Loading...</div>
  }

  return (
    <main className="min-h-screen p-8">
      <div className="max-w-7xl mx-auto">
        <div className="flex justify-between items-center mb-8">
          <h1 className="text-3xl font-bold">Exposure & Risk</h1>
          <Link href="/" className="text-primary-400 hover:text-primary-300">← Back to Dashboard</Link>
        </div>

        {/* Exposure Summary */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
          {exposure && (
            <>
              <div className="card">
                <h3 className="text-sm text-gray-400 mb-1">Total Exposure</h3>
                <p className="text-2xl font-bold">${exposure.total_exposure.toFixed(2)}</p>
              </div>
              {Object.entries(exposure.exposure).map(([asset, value]) => (
                <div key={asset} className="card">
                  <h3 className="text-sm text-gray-400 mb-1">{asset} Exposure</h3>
                  <p className="text-2xl font-bold">${value.toFixed(2)}</p>
                </div>
              ))}
            </>
          )}
        </div>

        {/* Risk Metrics */}
        {exposure?.risk_metrics && (
          <div className="card mb-8">
            <h2 className="text-xl font-semibold mb-4">Risk Metrics</h2>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div>
                <p className="text-sm text-gray-400">Portfolio Value</p>
                <p className="text-lg font-semibold">${exposure.risk_metrics.portfolio_value.toFixed(2)}</p>
              </div>
              <div>
                <p className="text-sm text-gray-400">Correlation Risk</p>
                <p className="text-lg font-semibold">{(exposure.risk_metrics.correlation_risk * 100).toFixed(1)}%</p>
              </div>
              <div>
                <p className="text-sm text-gray-400">Daily Loss</p>
                <p className={`text-lg font-semibold ${exposure.risk_metrics.daily_loss > 0 ? 'text-red-400' : ''}`}>
                  ${exposure.risk_metrics.daily_loss.toFixed(2)}
                </p>
              </div>
              <div>
                <p className="text-sm text-gray-400">Last Updated</p>
                <p className="text-sm">{new Date(exposure.risk_metrics.timestamp).toLocaleTimeString()}</p>
              </div>
            </div>
          </div>
        )}

        {/* Open Positions */}
        <div className="card mb-8">
          <h2 className="text-xl font-semibold mb-4">Open Positions</h2>
          {positions.length === 0 ? (
            <p className="text-gray-400">No open positions</p>
          ) : (
            <table className="w-full">
              <thead>
                <tr className="border-b border-slate-700">
                  <th className="text-left p-3">Market</th>
                  <th className="text-left p-3">Side</th>
                  <th className="text-left p-3">Size</th>
                  <th className="text-left p-3">Entry</th>
                  <th className="text-left p-3">Current</th>
                  <th className="text-left p-3">Unrealized PnL</th>
                </tr>
              </thead>
              <tbody>
                {positions.map(pos => (
                  <tr key={pos.id} className="border-b border-slate-700/50">
                    <td className="p-3">#{pos.market_id}</td>
                    <td className="p-3">
                      <span className={`px-2 py-1 rounded text-xs ${pos.side === 'YES' ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'}`}>
                        {pos.side}
                      </span>
                    </td>
                    <td className="p-3">{pos.size.toFixed(2)}</td>
                    <td className="p-3">${pos.avg_entry_price.toFixed(4)}</td>
                    <td className="p-3">{pos.current_price ? `$${pos.current_price.toFixed(4)}` : '-'}</td>
                    <td className={`p-3 ${(pos.unrealized_pnl || 0) >= 0 ? 'text-green-400' : 'text-red-400'}`}>
                      {pos.unrealized_pnl ? `$${pos.unrealized_pnl.toFixed(2)}` : '-'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {/* Circuit Breakers */}
        <div className="card">
          <h2 className="text-xl font-semibold mb-4">Circuit Breakers</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {breakers.map(breaker => (
              <div key={breaker.name} className={`p-4 rounded-lg ${breaker.is_tripped ? 'bg-red-500/20 border border-red-500' : 'bg-slate-700/50'}`}>
                <div className="flex justify-between items-start">
                  <div>
                    <h3 className="font-medium">{breaker.name.replace(/_/g, ' ')}</h3>
                    <p className={`text-sm ${breaker.is_tripped ? 'text-red-400' : 'text-green-400'}`}>
                      {breaker.is_tripped ? 'TRIPPED' : 'OK'}
                    </p>
                    {breaker.trip_reason && (
                      <p className="text-xs text-gray-400 mt-1">{breaker.trip_reason}</p>
                    )}
                  </div>
                  {breaker.is_tripped && (
                    <button
                      onClick={() => resetBreaker(breaker.name)}
                      className="text-xs bg-slate-600 hover:bg-slate-500 px-2 py-1 rounded"
                    >
                      Reset
                    </button>
                  )}
                </div>
                <p className="text-xs text-gray-500 mt-2">
                  Trips: {breaker.trip_count}
                </p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </main>
  )
}
