'use client'

import { useState, useEffect, useCallback } from 'react'
import Navbar from '@/components/Navbar'
import { API_URL } from '@/lib/config'

// Icons
const Icons = {
  TrendingUp: () => <span>📈</span>,
  TrendingDown: () => <span>📉</span>,
  Activity: () => <span>⚡</span>,
  Wallet: () => <span>💰</span>,
  Clock: () => <span>🕐</span>,
  Check: () => <span>✅</span>,
  X: () => <span>❌</span>,
  AlertTriangle: () => <span>⚠️</span>,
  Wifi: () => <span>🌐</span>,
  RefreshCw: () => <span>🔄</span>,
}

// Types
interface Price {
  market: string
  asset: string
  last_price: number
  coinbase_price: number
  bid: number
  ask: number
  spread_pct: number
  timestamp: string
}

interface Position {
  market: string
  asset: string
  side: string
  size: number
  avg_price: number
  current_price: number
  pnl: number
  pnl_pct: number
}

interface Trade {
  id: string
  market: string
  side: string
  size: number
  price: number
  status: string
  timestamp: string
}

interface BotState {
  state: string
  trading_enabled: boolean
  last_trade_time: string | null
  uptime_seconds: number
  trades_today: number
  version: string
}

interface WalletBalance {
  balance: number
  available: number
  in_positions: number
}

interface DailyPnL {
  total_pnl: number
  realized_pnl: number
  unrealized_pnl: number
  trades_count: number
  win_rate: number
}

interface ServiceHealth {
  name: string
  status: string
  last_check: string
  details?: any
}

interface Config {
  key: string
  value: string
  description?: string
}

interface CircuitBreaker {
  name: string
  state: string
  failure_count: number
  last_failure_time: string | null
}

export default function Dashboard() {
  const [activeTab, setActiveTab] = useState('dashboard')
  const [prices, setPrices] = useState<Price[]>([])
  const [botState, setBotState] = useState<BotState | null>(null)
  const [positions, setPositions] = useState<Position[]>([])
  const [trades, setTrades] = useState<Trade[]>([])
  const [wallet, setWallet] = useState<WalletBalance>({ balance: 0, available: 0, in_positions: 0 })
  const [dailyPnL, setDailyPnL] = useState<DailyPnL | null>(null)
  const [services, setServices] = useState<ServiceHealth[]>([])
  const [configs, setConfigs] = useState<Config[]>([])
  const [circuitBreakers, setCircuitBreakers] = useState<CircuitBreaker[]>([])
  const [lastUpdate, setLastUpdate] = useState<Date | null>(null)
  const [loading, setLoading] = useState(true)
  const [autoRefresh, setAutoRefresh] = useState(true)
  const [passwordModal, setPasswordModal] = useState<{ isOpen: boolean; action: string }>({ isOpen: false, action: '' })
  
  // Auth state
  const [authenticated, setAuthenticated] = useState(false)
  const [password, setPassword] = useState('')
  const [authError, setAuthError] = useState('')

  // Check auth on mount
  useEffect(() => {
    const isAuth = localStorage.getItem('poly15_auth')
    if (isAuth === 'true') {
      setAuthenticated(true)
    }
  }, [])

  const handleLogin = (e: React.FormEvent) => {
    e.preventDefault()
    if (password === 'poly15admin') {
      setAuthenticated(true)
      setAuthError('')
      localStorage.setItem('poly15_auth', 'true')
    } else {
      setAuthError('Invalid password')
    }
  }

  const fetchData = useCallback(async () => {
    try {
      const endpoints = [
        { url: `${API_URL}/v1/prices/latest`, setter: (data: any) => setPrices(data.prices || []) },
        { url: `${API_URL}/v1/admin/bot/state`, setter: (data: any) => setBotState(data) },
        { url: `${API_URL}/v1/positions/`, setter: (data: any) => setPositions(data.positions || []) },
        { url: `${API_URL}/v1/orders/?limit=20`, setter: (data: any) => setTrades(data.orders || []) },
        { url: `${API_URL}/v1/admin/wallet/balance`, setter: (data: any) => setWallet(data) },
        { url: `${API_URL}/v1/pnl/daily`, setter: (data: any) => setDailyPnL(data) },
        { url: `${API_URL}/v1/health/services`, setter: (data: any) => setServices(data.services || []) },
        { url: `${API_URL}/v1/config/`, setter: (data: any) => {
          // Handle both array and object config formats
          if (data.config && typeof data.config === 'object' && !Array.isArray(data.config)) {
            const configArray = Object.entries(data.config).map(([key, val]: [string, any]) => ({
              key,
              value: typeof val === 'object' ? String(val.value) : String(val),
              description: typeof val === 'object' ? val.description : ''
            }))
            setConfigs(configArray)
          } else {
            setConfigs(data.configs || [])
          }
        }},
        { url: `${API_URL}/v1/admin/circuit-breakers`, setter: (data: any) => setCircuitBreakers(data.circuit_breakers || []) },
      ]

      await Promise.all(
        endpoints.map(async ({ url, setter }) => {
          try {
            const res = await fetch(url)
            if (res.ok) {
              const data = await res.json()
              setter(data)
            }
          } catch (e) {
            // Silently fail individual endpoints
          }
        })
      )
      
      setLastUpdate(new Date())
    } catch (error) {
      console.error('Failed to fetch data:', error)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    if (authenticated) {
      fetchData()
    }
  }, [authenticated, fetchData])

  useEffect(() => {
    if (!authenticated || !autoRefresh || activeTab === 'config') return
    
    const interval = setInterval(fetchData, 2000)
    return () => clearInterval(interval)
  }, [authenticated, autoRefresh, activeTab, fetchData])

  const handleBotAction = async (action: 'start' | 'pause' | 'stop') => {
    setPasswordModal({ isOpen: true, action: action.charAt(0).toUpperCase() + action.slice(1) })
  }

  const confirmBotAction = async (action: string) => {
    const actionLower = action.toLowerCase() as 'start' | 'pause' | 'stop'
    try {
      const res = await fetch(`${API_URL}/v1/admin/bot/${actionLower}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ reason: `Manual ${actionLower} from dashboard`, user: 'dashboard' })
      })
      if (res.ok) {
        const data = await res.json()
        setBotState(prev => prev ? { ...prev, state: data.state } : null)
      }
    } catch (error) {
      console.error(`Failed to ${actionLower} bot:`, error)
    }
    setPasswordModal({ isOpen: false, action: '' })
  }

  const updateConfig = async (key: string, value: string) => {
    try {
      const res = await fetch(`${API_URL}/v1/config/${key}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ value, updated_by: 'dashboard' })
      })
      if (res.ok) {
        fetchData()
      }
    } catch (error) {
      console.error('Failed to update config:', error)
    }
  }

  // Format helpers
  const formatCurrency = (val: number) => `$${val?.toFixed(2) || '0.00'}`
  const formatPct = (val: number) => `${val?.toFixed(2) || '0.00'}%`
  const formatTime = (date: Date) => date.toLocaleTimeString()
  const getStatusColor = (status: string) => {
    switch (status?.toLowerCase()) {
      case 'running': case 'healthy': case 'closed': return 'text-green-400'
      case 'paused': case 'degraded': case 'half_open': return 'text-yellow-400'
      case 'stopped': case 'unhealthy': case 'open': return 'text-red-400'
      default: return 'text-gray-400'
    }
  }

  // Login screen
  if (!authenticated) {
    return (
      <div className="min-h-screen bg-slate-950 flex items-center justify-center">
        <div className="bg-slate-900 border border-slate-700 rounded-xl p-8 w-96 shadow-2xl">
          <h1 className="text-2xl font-bold text-white mb-6 text-center">🤖 PolyTrader</h1>
          <form onSubmit={handleLogin}>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Enter password"
              className="w-full px-4 py-3 bg-slate-800 border border-slate-600 rounded-lg text-white mb-4 focus:outline-none focus:border-blue-500"
            />
            {authError && <p className="text-red-400 text-sm mb-4">{authError}</p>}
            <button
              type="submit"
              className="w-full bg-blue-600 hover:bg-blue-500 text-white py-3 rounded-lg font-semibold transition-colors"
            >
              Login
            </button>
          </form>
          <p className="text-slate-500 text-xs text-center mt-4">API: {API_URL}</p>
        </div>
      </div>
    )
  }

  // Dashboard Content
  const DashboardContent = () => (
    <div className="space-y-6">
      {/* Top Stats Row */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="card">
          <div className="flex items-center gap-2 text-gray-400 text-sm mb-1">
            <Icons.Wallet /> Balance
          </div>
          <div className="text-2xl font-bold text-green-400">{formatCurrency(wallet.balance)}</div>
          <div className="text-xs text-gray-500">Available: {formatCurrency(wallet.available)}</div>
        </div>
        <div className="card">
          <div className="flex items-center gap-2 text-gray-400 text-sm mb-1">
            <Icons.Activity /> Daily P&L
          </div>
          <div className={`text-2xl font-bold ${(dailyPnL?.total_pnl || 0) >= 0 ? 'text-green-400' : 'text-red-400'}`}>
            {formatCurrency(dailyPnL?.total_pnl || 0)}
          </div>
          <div className="text-xs text-gray-500">Win rate: {formatPct(dailyPnL?.win_rate || 0)}</div>
        </div>
        <div className="card">
          <div className="flex items-center gap-2 text-gray-400 text-sm mb-1">
            <Icons.TrendingUp /> Bot Status
          </div>
          <div className={`text-2xl font-bold ${getStatusColor(botState?.state || '')}`}>
            {botState?.state || 'Unknown'}
          </div>
          <div className="text-xs text-gray-500">Trades today: {botState?.trades_today || 0}</div>
        </div>
        <div className="card">
          <div className="flex items-center gap-2 text-gray-400 text-sm mb-1">
            <Icons.Clock /> Last Update
          </div>
          <div className="text-2xl font-bold text-blue-400">
            {lastUpdate ? formatTime(lastUpdate) : '--:--'}
          </div>
          <div className="text-xs text-gray-500">Auto-refresh: {autoRefresh ? 'ON' : 'OFF'}</div>
        </div>
      </div>

      {/* Bot Controls */}
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Bot Controls</h2>
        <div className="flex gap-3">
          <button
            onClick={() => handleBotAction('start')}
            disabled={botState?.state === 'running'}
            className="px-4 py-2 bg-green-600 hover:bg-green-500 disabled:opacity-50 disabled:cursor-not-allowed rounded-lg"
          >
            ▶️ Start
          </button>
          <button
            onClick={() => handleBotAction('pause')}
            disabled={botState?.state !== 'running'}
            className="px-4 py-2 bg-yellow-600 hover:bg-yellow-500 disabled:opacity-50 disabled:cursor-not-allowed rounded-lg"
          >
            ⏸️ Pause
          </button>
          <button
            onClick={() => handleBotAction('stop')}
            disabled={botState?.state === 'stopped'}
            className="px-4 py-2 bg-red-600 hover:bg-red-500 disabled:opacity-50 disabled:cursor-not-allowed rounded-lg"
          >
            ⏹️ Stop
          </button>
        </div>
      </div>

      {/* Prices */}
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Market Prices</h2>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-gray-400 border-b border-slate-700">
                <th className="text-left py-2">Asset</th>
                <th className="text-right py-2">Poly Price</th>
                <th className="text-right py-2">Coinbase</th>
                <th className="text-right py-2">Spread</th>
              </tr>
            </thead>
            <tbody>
              {prices.map((p, i) => (
                <tr key={i} className="border-b border-slate-800">
                  <td className="py-2 font-medium">{p.asset}</td>
                  <td className="py-2 text-right">{formatCurrency(p.last_price)}</td>
                  <td className="py-2 text-right text-gray-400">{formatCurrency(p.coinbase_price)}</td>
                  <td className={`py-2 text-right ${p.spread_pct > 1 ? 'text-yellow-400' : 'text-gray-400'}`}>
                    {formatPct(p.spread_pct)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Services & Circuit Breakers */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Services</h2>
          <div className="space-y-2">
            {services.map((s, i) => (
              <div key={i} className="flex justify-between items-center py-2 border-b border-slate-800">
                <span>{s.name}</span>
                <span className={getStatusColor(s.status)}>{s.status}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Circuit Breakers</h2>
          <div className="space-y-2">
            {circuitBreakers.map((cb, i) => (
              <div key={i} className="flex justify-between items-center py-2 border-b border-slate-800">
                <span>{cb.name}</span>
                <span className={getStatusColor(cb.state)}>{cb.state} ({cb.failure_count})</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  )

  // Positions Content
  const PositionsContent = () => (
    <div className="card">
      <h2 className="text-lg font-semibold mb-4">Open Positions</h2>
      {positions.length === 0 ? (
        <p className="text-gray-400">No open positions</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-gray-400 border-b border-slate-700">
                <th className="text-left py-2">Asset</th>
                <th className="text-left py-2">Side</th>
                <th className="text-right py-2">Size</th>
                <th className="text-right py-2">Avg Price</th>
                <th className="text-right py-2">Current</th>
                <th className="text-right py-2">P&L</th>
              </tr>
            </thead>
            <tbody>
              {positions.map((p, i) => (
                <tr key={i} className="border-b border-slate-800">
                  <td className="py-2 font-medium">{p.asset}</td>
                  <td className={`py-2 ${p.side === 'buy' ? 'text-green-400' : 'text-red-400'}`}>{p.side.toUpperCase()}</td>
                  <td className="py-2 text-right">{p.size}</td>
                  <td className="py-2 text-right">{formatCurrency(p.avg_price)}</td>
                  <td className="py-2 text-right">{formatCurrency(p.current_price)}</td>
                  <td className={`py-2 text-right ${p.pnl >= 0 ? 'text-green-400' : 'text-red-400'}`}>
                    {formatCurrency(p.pnl)} ({formatPct(p.pnl_pct)})
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )

  // Trades Content
  const TradesContent = () => (
    <div className="card">
      <h2 className="text-lg font-semibold mb-4">Recent Trades</h2>
      {trades.length === 0 ? (
        <p className="text-gray-400">No recent trades</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-gray-400 border-b border-slate-700">
                <th className="text-left py-2">Time</th>
                <th className="text-left py-2">Market</th>
                <th className="text-left py-2">Side</th>
                <th className="text-right py-2">Size</th>
                <th className="text-right py-2">Price</th>
                <th className="text-left py-2">Status</th>
              </tr>
            </thead>
            <tbody>
              {trades.map((t, i) => (
                <tr key={i} className="border-b border-slate-800">
                  <td className="py-2 text-gray-400">{new Date(t.timestamp).toLocaleString()}</td>
                  <td className="py-2 font-medium">{t.market}</td>
                  <td className={`py-2 ${t.side === 'buy' ? 'text-green-400' : 'text-red-400'}`}>{t.side.toUpperCase()}</td>
                  <td className="py-2 text-right">{t.size}</td>
                  <td className="py-2 text-right">{formatCurrency(t.price)}</td>
                  <td className={`py-2 ${getStatusColor(t.status)}`}>{t.status}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )

  // Config Content
  const ConfigContent = () => {
    const [editingConfig, setEditingConfig] = useState<string | null>(null)
    const [editValue, setEditValue] = useState('')
    const [portfolioSize, setPortfolioSize] = useState(wallet.balance || 500)
    const [recommended, setRecommended] = useState<any>(null)
    const [proxyUrl, setProxyUrl] = useState('')
    const [proxyEnabled, setProxyEnabled] = useState(false)
    const [rpcUrl, setRpcUrl] = useState('')
    const [applyingRecommended, setApplyingRecommended] = useState(false)
    const [savingNetwork, setSavingNetwork] = useState(false)

    const fetchRecommended = async (size: number) => {
      try {
        const res = await fetch(`${API_URL}/v1/config/recommended/${size}`)
        if (res.ok) {
          const data = await res.json()
          setRecommended(data)
        }
      } catch (e) {
        console.error('Failed to fetch recommended settings:', e)
      }
    }

    const fetchNetworkConfig = async () => {
      try {
        const res = await fetch(`${API_URL}/v1/config/network`)
        if (res.ok) {
          const data = await res.json()
          setProxyEnabled(data.proxy_enabled || false)
          setProxyUrl(data.proxy_url || '')
          setRpcUrl(data.polygon_rpc_url || '')
        }
      } catch (e) {
        console.error('Failed to fetch network config:', e)
      }
    }

    useEffect(() => {
      fetchRecommended(portfolioSize)
      fetchNetworkConfig()
    }, [])

    const applyRecommended = async () => {
      setApplyingRecommended(true)
      try {
        const res = await fetch(`${API_URL}/v1/config/apply-recommended/${portfolioSize}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' }
        })
        if (res.ok) {
          fetchData()
          alert('Recommended settings applied!')
        }
      } catch (e) {
        alert('Failed to apply settings')
      }
      setApplyingRecommended(false)
    }

    const saveNetworkConfig = async () => {
      setSavingNetwork(true)
      try {
        const res = await fetch(`${API_URL}/v1/config/network`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ proxy_url: proxyUrl, proxy_enabled: proxyEnabled, polygon_rpc_url: rpcUrl })
        })
        if (res.ok) alert('Network settings saved. Restart services to apply.')
      } catch (e) {
        alert('Failed to save settings')
      }
      setSavingNetwork(false)
    }

    const allConfigItems = [
      { key: 'trade_size_usd', label: 'Trade Size (USD)' },
      { key: 'max_position_per_market', label: 'Max Position/Market' },
      { key: 'daily_loss_limit_usd', label: 'Daily Loss Limit' },
      { key: 'max_open_positions', label: 'Max Open Positions' },
      { key: 'take_profit_pct', label: 'Take Profit %' },
      { key: 'stop_loss_pct', label: 'Stop Loss %' },
      { key: 'correlation_cap_pct', label: 'Correlation Cap %' },
      { key: 'confidence_threshold', label: 'Confidence Threshold' },
      { key: 'min_edge_required', label: 'Min Edge Required' },
      { key: 'min_liquidity_usd', label: 'Min Liquidity (USD)' },
    ]

    const half = Math.ceil(allConfigItems.length / 2)
    const leftItems = allConfigItems.slice(0, half)
    const rightItems = allConfigItems.slice(half)

    const renderRow = (item: { key: string; label: string }) => {
      const config = configs.find(c => c.key === item.key)
      const isEditing = editingConfig === item.key
      return (
        <tr key={item.key} className="border-b border-slate-700/50">
          <td className="py-2 text-sm">{item.label}</td>
          <td className="py-2 text-right">
            {isEditing ? (
              <div className="flex items-center justify-end gap-1">
                <input type="text" value={editValue} onChange={(e) => setEditValue(e.target.value)} className="w-20 px-2 py-1 bg-slate-800 border border-slate-600 rounded text-right text-sm" autoFocus />
                <button onClick={() => { updateConfig(item.key, editValue); setEditingConfig(null); }} className="px-2 py-1 bg-green-600 hover:bg-green-500 rounded text-xs">✓</button>
                <button onClick={() => setEditingConfig(null)} className="px-2 py-1 bg-gray-600 hover:bg-gray-500 rounded text-xs">✕</button>
              </div>
            ) : (
              <div className="flex items-center justify-end gap-2">
                <span className="font-mono text-sm">{config?.value || '--'}</span>
                <button onClick={() => { setEditingConfig(item.key); setEditValue(config?.value || ''); }} className="px-2 py-1 bg-blue-600 hover:bg-blue-500 rounded text-xs">Edit</button>
              </div>
            )}
          </td>
        </tr>
      )
    }

    return (
      <div className="space-y-4">
        {/* Recommended Settings - Compact */}
        <div className="card">
          <div className="flex items-center justify-between mb-3">
            <h2 className="font-semibold flex items-center gap-2"><Icons.TrendingUp /> Recommended Settings</h2>
            {recommended && <span className="text-xs text-gray-400 bg-slate-700 px-2 py-1 rounded">{recommended.risk_level}</span>}
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <div className="flex items-center gap-2">
              <span className="text-sm text-gray-400">Portfolio $</span>
              <input type="number" value={portfolioSize} onChange={(e) => setPortfolioSize(Number(e.target.value))} className="w-24 px-2 py-1 bg-slate-800 border border-slate-600 rounded text-sm" />
            </div>
            <button onClick={() => fetchRecommended(portfolioSize)} className="px-3 py-1 bg-blue-600 hover:bg-blue-500 rounded text-sm">Calculate</button>
            <button onClick={applyRecommended} disabled={applyingRecommended || !recommended} className="px-3 py-1 bg-green-600 hover:bg-green-500 rounded text-sm disabled:opacity-50">
              {applyingRecommended ? 'Applying...' : 'Apply All'}
            </button>
            {recommended && (
              <div className="flex gap-4 ml-auto text-sm">
                <span><span className="text-gray-400">Trade:</span> <span className="text-green-400">${recommended.recommended.trade_size_usd}</span></span>
                <span><span className="text-gray-400">Max:</span> <span className="text-blue-400">${recommended.recommended.max_position_per_market}</span></span>
                <span><span className="text-gray-400">Loss:</span> <span className="text-red-400">${recommended.recommended.daily_loss_limit_usd}</span></span>
                <span><span className="text-gray-400">Pos:</span> <span className="text-yellow-400">{recommended.recommended.max_open_positions}</span></span>
              </div>
            )}
          </div>
        </div>

        {/* Trading Parameters - Side by Side */}
        <div className="card">
          <h2 className="font-semibold mb-3">Trading Parameters</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <table className="w-full"><tbody>{leftItems.map(renderRow)}</tbody></table>
            <table className="w-full"><tbody>{rightItems.map(renderRow)}</tbody></table>
          </div>
        </div>

        {/* Network Settings - Compact */}
        <div className="card">
          <h2 className="font-semibold mb-3 flex items-center gap-2"><Icons.Wifi /> Network Settings</h2>
          <div className="grid grid-cols-1 md:grid-cols-4 gap-3 items-center">
            <div className="flex items-center gap-2">
              <span className="text-sm text-gray-400">Proxy:</span>
              <label className="relative inline-flex items-center cursor-pointer">
                <input type="checkbox" checked={proxyEnabled} onChange={(e) => setProxyEnabled(e.target.checked)} className="sr-only peer" />
                <div className="w-9 h-5 bg-gray-600 rounded-full peer peer-checked:after:translate-x-full after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:bg-blue-600"></div>
              </label>
            </div>
            <input type="text" value={proxyUrl} onChange={(e) => setProxyUrl(e.target.value)} placeholder="http://user:pass@host:port" className="px-3 py-1.5 bg-slate-800 border border-slate-600 rounded text-sm" />
            <input type="text" value={rpcUrl} onChange={(e) => setRpcUrl(e.target.value)} placeholder="Polygon RPC URL" className="px-3 py-1.5 bg-slate-800 border border-slate-600 rounded text-sm" />
            <div className="flex items-center gap-2">
              <button onClick={saveNetworkConfig} disabled={savingNetwork} className="px-3 py-1.5 bg-blue-600 hover:bg-blue-500 rounded text-sm disabled:opacity-50">{savingNetwork ? 'Saving...' : 'Save'}</button>
              <span className="text-xs text-yellow-400">⚠ Restart required</span>
            </div>
          </div>
        </div>

        {/* Debug Info */}
        <div className="text-xs text-gray-500 mt-4">
          API URL: {API_URL}
        </div>
      </div>
    )
  }

  // Password Modal
  const PasswordModal = () => {
    const [modalPassword, setModalPassword] = useState('')
    const [error, setError] = useState('')

    const handleSubmit = () => {
      if (modalPassword === 'poly15admin') {
        confirmBotAction(passwordModal.action)
        setModalPassword('')
        setError('')
      } else {
        setError('Invalid password')
      }
    }

    if (!passwordModal.isOpen) return null

    return (
      <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
        <div className="bg-slate-900 border border-slate-700 rounded-xl p-6 w-80">
          <h3 className="text-lg font-semibold mb-4">Confirm {passwordModal.action}</h3>
          <input
            type="password"
            value={modalPassword}
            onChange={(e) => setModalPassword(e.target.value)}
            placeholder="Enter password"
            className="w-full px-4 py-2 bg-slate-800 border border-slate-600 rounded-lg mb-3"
          />
          {error && <p className="text-red-400 text-sm mb-3">{error}</p>}
          <div className="flex gap-3">
            <button
              onClick={handleSubmit}
              className="flex-1 bg-blue-600 hover:bg-blue-500 py-2 rounded-lg"
            >
              Confirm
            </button>
            <button
              onClick={() => setPasswordModal({ isOpen: false, action: '' })}
              className="flex-1 bg-slate-700 hover:bg-slate-600 py-2 rounded-lg"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-slate-950 text-white">
      <Navbar 
        activeTab={activeTab} 
        setActiveTab={setActiveTab}
        autoRefresh={autoRefresh}
        setAutoRefresh={setAutoRefresh}
        onRefresh={fetchData}
      />
      
      <main className="container mx-auto px-4 py-6">
        {loading ? (
          <div className="flex items-center justify-center h-64">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500"></div>
          </div>
        ) : (
          <>
            {activeTab === 'dashboard' && <DashboardContent />}
            {activeTab === 'positions' && <PositionsContent />}
            {activeTab === 'trades' && <TradesContent />}
            {activeTab === 'config' && <ConfigContent />}
          </>
        )}
      </main>

      <PasswordModal />

      {/* Global Styles */}
      <style jsx global>{`
        .card {
          background: rgb(30 41 59);
          border: 1px solid rgb(51 65 85);
          border-radius: 0.75rem;
          padding: 1.5rem;
        }
      `}</style>
    </div>
  )
}