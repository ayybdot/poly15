'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'

interface ConfigItem {
  value: any
  description: string
}

// Recommended defaults based on portfolio size
const getRecommendedDefaults = (portfolioSize: number) => {
  return {
    portfolio_trade_pct: 5,
    max_market_usd: Math.min(portfolioSize * 0.2, 500), // 20% of portfolio, max $500
    daily_loss_limit_usd: portfolioSize * 0.05, // 5% of portfolio
    correlation_max_basket_pct: 35,
    take_profit_pct: 8,
    stop_loss_pct: 5,
    min_liquidity_usd: 500,
    market_close_buffer_minutes: 2,
    stale_data_threshold_seconds: 60,
  }
}

export default function ConfigPage() {
  const [config, setConfig] = useState<{ [key: string]: ConfigItem }>({})
  const [loading, setLoading] = useState(true)
  const [editKey, setEditKey] = useState<string | null>(null)
  const [editValue, setEditValue] = useState<string>('')
  const [portfolioSize, setPortfolioSize] = useState<number>(500)
  const [applying, setApplying] = useState(false)

  const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000'

  const recommendedDefaults = getRecommendedDefaults(portfolioSize)

  useEffect(() => {
    fetchConfig()
  }, [])

  const fetchConfig = async () => {
    try {
      const res = await fetch(`${API_URL}/v1/config/`)
      if (res.ok) {
        const data = await res.json()
        setConfig(data.config || {})
      }
    } catch (error) {
      console.error('Failed to fetch config:', error)
    } finally {
      setLoading(false)
    }
  }

  const updateConfig = async (key: string, value: any) => {
    try {
      const res = await fetch(`${API_URL}/v1/config/${key}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ value, user: 'dashboard' })
      })
      if (res.ok) {
        await fetchConfig()
        setEditKey(null)
      }
    } catch (error) {
      console.error('Failed to update config:', error)
    }
  }

  const applyRecommendedDefaults = async () => {
    setApplying(true)
    try {
      // Apply each recommended setting
      for (const [key, value] of Object.entries(recommendedDefaults)) {
        await fetch(`${API_URL}/v1/config/${key}`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ value, user: 'dashboard' })
        })
      }
      await fetchConfig()
      alert(`Applied recommended defaults for $${portfolioSize} portfolio!`)
    } catch (error) {
      console.error('Failed to apply defaults:', error)
      alert('Failed to apply some settings. Please try again.')
    } finally {
      setApplying(false)
    }
  }

  const startEdit = (key: string, currentValue: any) => {
    setEditKey(key)
    setEditValue(String(currentValue))
  }

  const saveEdit = () => {
    if (editKey) {
      // Try to parse as number or boolean
      let value: any = editValue
      if (editValue === 'true') value = true
      else if (editValue === 'false') value = false
      else if (!isNaN(Number(editValue))) value = Number(editValue)
      
      updateConfig(editKey, value)
    }
  }

  if (loading) {
    return <div className="min-h-screen p-8 flex items-center justify-center">Loading...</div>
  }

  return (
    <main className="min-h-screen p-8">
      <div className="max-w-4xl mx-auto">
        <div className="flex justify-between items-center mb-8">
          <h1 className="text-3xl font-bold">Configuration</h1>
          <Link href="/" className="text-primary-400 hover:text-primary-300">← Back to Dashboard</Link>
        </div>

        {/* Recommended Defaults - Moved to top */}
        <div className="card mb-8 border border-primary-500/30">
          <div className="flex justify-between items-start mb-4">
            <div>
              <h2 className="text-xl font-semibold">Recommended Defaults</h2>
              <p className="text-sm text-gray-400 mt-1">Settings optimized for your portfolio size</p>
            </div>
            <div className="flex items-center gap-3">
              <label className="text-sm text-gray-400">Portfolio Size:</label>
              <select
                value={portfolioSize}
                onChange={(e) => setPortfolioSize(Number(e.target.value))}
                className="bg-slate-700 border border-slate-600 rounded px-3 py-1.5 text-sm"
              >
                <option value={100}>$100</option>
                <option value={250}>$250</option>
                <option value={500}>$500</option>
                <option value={1000}>$1,000</option>
                <option value={2500}>$2,500</option>
                <option value={5000}>$5,000</option>
                <option value={10000}>$10,000</option>
                <option value={25000}>$25,000</option>
              </select>
            </div>
          </div>
          
          <div className="grid grid-cols-2 gap-4 text-sm mb-6 bg-slate-700/30 p-4 rounded-lg">
            <div className="flex justify-between">
              <span className="text-gray-400">Trade Size:</span>
              <span className="font-medium">{recommendedDefaults.portfolio_trade_pct}% (~${(portfolioSize * recommendedDefaults.portfolio_trade_pct / 100).toFixed(0)})</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Max per Market:</span>
              <span className="font-medium">${recommendedDefaults.max_market_usd}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Daily Loss Limit:</span>
              <span className="font-medium">${recommendedDefaults.daily_loss_limit_usd}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Correlation Cap:</span>
              <span className="font-medium">{recommendedDefaults.correlation_max_basket_pct}%</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Take Profit:</span>
              <span className="font-medium">{recommendedDefaults.take_profit_pct}%</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Stop Loss:</span>
              <span className="font-medium">{recommendedDefaults.stop_loss_pct}%</span>
            </div>
          </div>

          <button
            onClick={applyRecommendedDefaults}
            disabled={applying}
            className="w-full bg-primary-600 hover:bg-primary-500 disabled:bg-primary-800 disabled:cursor-not-allowed text-white px-4 py-3 rounded-lg font-medium transition-colors"
          >
            {applying ? 'Applying...' : `Apply Recommended Settings for $${portfolioSize.toLocaleString()} Portfolio`}
          </button>
        </div>

        {/* Risk Settings */}
        <div className="card mb-8">
          <h2 className="text-xl font-semibold mb-4">Current Settings</h2>
          <p className="text-gray-400 mb-4">Configure trading risk parameters. Changes take effect immediately.</p>
          
          <div className="space-y-4">
            {Object.entries(config).map(([key, item]) => (
              <div key={key} className="flex items-center justify-between p-4 bg-slate-700/30 rounded-lg">
                <div className="flex-1">
                  <h3 className="font-medium">{key.replace(/_/g, ' ')}</h3>
                  <p className="text-sm text-gray-400">{item.description}</p>
                </div>
                <div className="flex items-center gap-2 ml-4">
                  {editKey === key ? (
                    <>
                      <input
                        type="text"
                        value={editValue}
                        onChange={(e) => setEditValue(e.target.value)}
                        className="bg-slate-800 border border-slate-600 rounded px-3 py-1 w-32 text-right"
                        autoFocus
                      />
                      <button
                        onClick={saveEdit}
                        className="bg-green-600 hover:bg-green-500 px-3 py-1 rounded text-sm"
                      >
                        Save
                      </button>
                      <button
                        onClick={() => setEditKey(null)}
                        className="bg-slate-600 hover:bg-slate-500 px-3 py-1 rounded text-sm"
                      >
                        Cancel
                      </button>
                    </>
                  ) : (
                    <>
                      <span className="font-mono text-lg">
                        {typeof item.value === 'boolean' ? (item.value ? 'Yes' : 'No') : item.value}
                      </span>
                      <button
                        onClick={() => startEdit(key, item.value)}
                        className="bg-slate-600 hover:bg-slate-500 px-3 py-1 rounded text-sm"
                      >
                        Edit
                      </button>
                    </>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </main>
  )
}