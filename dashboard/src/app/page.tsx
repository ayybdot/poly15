'use client'

import { useEffect, useState, useCallback } from 'react'

// ==================== TYPES ====================
interface Price {
  symbol: string
  price: number
  change_15m_pct: number | null
  timestamp: string
  is_stale: boolean
}

interface BotState {
  state: string
  can_trade: boolean
  reason: string
}

interface Position {
  id: number
  market_id: number
  asset: string
  side: string
  size: number
  entry_price: number
  current_price: number
  unrealized_pnl: number
  created_at: string
  market_title?: string
}

interface Trade {
  id: number
  asset: string
  side: string
  size: number
  price: number
  pnl: number
  status: string
  created_at: string
}

interface WalletBalance {
  balance: number
  available: number
  in_positions: number
}

interface DailyPnL {
  date: string
  realized_pnl: number
  unrealized_pnl: number
  total_pnl: number
}

interface ServiceHealth {
  name: string
  status: 'healthy' | 'degraded' | 'down'
  lastCheck: string
}

interface Config {
  key: string
  value: string
  description: string
}

interface CircuitBreaker {
  name: string
  is_tripped: boolean
  trip_count: number
  last_trip: string | null
}

// ==================== ICONS ====================
const Icons = {
  Home: () => (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" />
    </svg>
  ),
  Chart: () => (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
    </svg>
  ),
  Settings: () => (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
    </svg>
  ),
  Shield: () => (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
    </svg>
  ),
  Activity: () => (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
    </svg>
  ),
  Server: () => (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01" />
    </svg>
  ),
  Database: () => (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4m0 5c0 2.21-3.582 4-8 4s-8-1.79-8-4" />
    </svg>
  ),
  Wifi: () => (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.141 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0" />
    </svg>
  ),
  Wallet: () => (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
    </svg>
  ),
  TrendingUp: () => (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
    </svg>
  ),
  TrendingDown: () => (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 17h8m0 0V9m0 8l-8-8-4 4-6-6" />
    </svg>
  ),
  CheckCircle: () => (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
  ),
  XCircle: () => (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
  ),
  AlertTriangle: () => (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
    </svg>
  ),
  Lock: () => (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
    </svg>
  ),
  Play: () => (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" />
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
  ),
  Pause: () => (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
  ),
  Stop: () => (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 10a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1v-4z" />
    </svg>
  ),
  RefreshCw: () => (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
    </svg>
  ),
}

// ==================== PASSWORD MODAL ====================
function PasswordModal({ 
  isOpen, 
  onClose, 
  onConfirm, 
  action 
}: { 
  isOpen: boolean
  onClose: () => void
  onConfirm: (password: string) => void
  action: string 
}) {
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (password === 'polytrader') {
      onConfirm(password)
      setPassword('')
      setError('')
    } else {
      setError('Incorrect password')
    }
  }

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-slate-800 rounded-lg p-6 w-96 shadow-xl border border-slate-700">
        <div className="flex items-center gap-3 mb-4">
          <div className="p-2 bg-yellow-500/20 rounded-lg text-yellow-400">
            <Icons.Lock />
          </div>
          <h3 className="text-lg font-semibold">Confirm {action}</h3>
        </div>
        <p className="text-gray-400 text-sm mb-4">
          Enter password to {action.toLowerCase()} the trading bot.
        </p>
        <form onSubmit={handleSubmit}>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="Enter password"
            className="w-full px-4 py-2 bg-slate-900 border border-slate-600 rounded-lg focus:outline-none focus:border-blue-500 mb-2"
            autoFocus
          />
          {error && <p className="text-red-400 text-sm mb-2">{error}</p>}
          <div className="flex gap-3 mt-4">
            <button
              type="button"
              onClick={() => { onClose(); setPassword(''); setError(''); }}
              className="flex-1 px-4 py-2 bg-slate-700 hover:bg-slate-600 rounded-lg transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              className="flex-1 px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded-lg transition-colors"
            >
              Confirm
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

// ==================== MAIN COMPONENT ====================
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
  const [passwordModal, setPasswordModal] = useState<{ isOpen: boolean; action: string }>({ isOpen: false, action: '' })

  const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000'

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
          // Convert config object to array format
          if (data.config) {
            const configArray = Object.entries(data.config).map(([key, val]: [string, any]) => ({
              key,
              value: typeof val === 'object' ? val.value : val,
              description: typeof val === 'object' ? val.description : ''
            }))
            setConfigs(configArray)
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
  }, [API_URL])

  useEffect(() => {
    fetchData()
    // Only auto-refresh on dashboard, exposure, and health tabs - not config
    if (activeTab !== 'config') {
      const interval = setInterval(fetchData, 2000)
      return () => clearInterval(interval)
    }
  }, [fetchData, activeTab])

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

  const getStateColor = (state: string) => {
    switch (state) {
      case 'RUNNING': return 'bg-green-500'
      case 'PAUSED': return 'bg-yellow-500'
      case 'STOPPED': return 'bg-gray-500'
      default: return 'bg-red-500'
    }
  }

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'healthy': return <span className="text-green-400"><Icons.CheckCircle /></span>
      case 'degraded': return <span className="text-yellow-400"><Icons.AlertTriangle /></span>
      default: return <span className="text-red-400"><Icons.XCircle /></span>
    }
  }

  const formatCurrency = (value: number | null | undefined) => {
    if (value == null) return '--'
    return `$${value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
  }

  const formatPnL = (value: number | null | undefined) => {
    if (value == null) return <span>--</span>
    const prefix = value >= 0 ? '+' : ''
    const color = value >= 0 ? 'text-green-400' : 'text-red-400'
    return <span className={color}>{prefix}{formatCurrency(value)}</span>
  }

  const totalUnrealizedPnL = positions.reduce((sum, p) => sum + (p.unrealized_pnl || 0), 0)

  const navItems = [
    { id: 'dashboard', label: 'Dashboard', icon: Icons.Home },
    { id: 'exposure', label: 'Exposure & Risk', icon: Icons.Shield },
    { id: 'health', label: 'System Health', icon: Icons.Activity },
    { id: 'config', label: 'Configuration', icon: Icons.Settings },
  ]

  const OperationalStatus = () => (
    <div className="bg-slate-800/50 border-b border-slate-700 px-4 py-2">
      <div className="max-w-7xl mx-auto flex items-center justify-between gap-4 text-sm">
        <div className="flex items-center gap-6">
          <div className="flex items-center gap-2">
            <Icons.Server />
            <span className="text-gray-400">API:</span>
            <span className="text-green-400">●</span>
          </div>
          <div className="flex items-center gap-2">
            <Icons.Database />
            <span className="text-gray-400">DB:</span>
            <span className="text-green-400">●</span>
          </div>
          <div className="flex items-center gap-2">
            <Icons.Wifi />
            <span className="text-gray-400">Polymarket:</span>
            <span className="text-green-400">●</span>
          </div>
          <div className="flex items-center gap-2">
            <Icons.Activity />
            <span className="text-gray-400">Worker:</span>
            <span className="text-green-400">●</span>
          </div>
        </div>
        <div className="flex items-center gap-4">
          {lastUpdate && (
            <span className="text-gray-500 text-xs flex items-center gap-1">
              <Icons.RefreshCw />
              {lastUpdate.toLocaleTimeString()}
            </span>
          )}
          {botState && (
            <span className={`${getStateColor(botState.state)} px-2 py-0.5 rounded text-xs font-medium`}>
              {botState.state}
            </span>
          )}
        </div>
      </div>
    </div>
  )

  const DashboardContent = () => (
    <div className="space-y-6">
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div className="card bg-gradient-to-br from-slate-800 to-slate-900">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-blue-500/20 rounded-lg text-blue-400">
              <Icons.Wallet />
            </div>
            <div>
              <p className="text-gray-400 text-sm">Wallet Balance</p>
              <p className="text-xl font-bold tabular-nums">{formatCurrency(wallet.balance)}</p>
            </div>
          </div>
        </div>
        <div className="card bg-gradient-to-br from-slate-800 to-slate-900">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-green-500/20 rounded-lg text-green-400">
              <Icons.TrendingUp />
            </div>
            <div>
              <p className="text-gray-400 text-sm">Available</p>
              <p className="text-xl font-bold tabular-nums">{formatCurrency(wallet.available)}</p>
            </div>
          </div>
        </div>
        <div className="card bg-gradient-to-br from-slate-800 to-slate-900">
          <div className="flex items-center gap-3">
            <div className={`p-2 rounded-lg ${(dailyPnL?.total_pnl ?? 0) >= 0 ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'}`}>
              {(dailyPnL?.total_pnl ?? 0) >= 0 ? <Icons.TrendingUp /> : <Icons.TrendingDown />}
            </div>
            <div>
              <p className="text-gray-400 text-sm">Today&apos;s P&L</p>
              <p className="text-xl font-bold tabular-nums">{formatPnL(dailyPnL?.total_pnl)}</p>
            </div>
          </div>
        </div>
        <div className="card bg-gradient-to-br from-slate-800 to-slate-900">
          <div className="flex items-center gap-3">
            <div className={`p-2 rounded-lg ${totalUnrealizedPnL >= 0 ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'}`}>
              <Icons.Chart />
            </div>
            <div>
              <p className="text-gray-400 text-sm">Unrealized P&L</p>
              <p className="text-xl font-bold tabular-nums">{formatPnL(totalUnrealizedPnL)}</p>
            </div>
          </div>
        </div>
      </div>

      <div>
        <h2 className="text-lg font-semibold mb-3">Live Prices</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {prices.length === 0 ? (
            <div className="col-span-3 text-center text-gray-400 py-8">Loading prices...</div>
          ) : (
            prices.map(price => (
              <div key={price.symbol} className="card transition-all duration-300 hover:bg-slate-700/50">
                <div className="flex justify-between items-start">
                  <div>
                    <h3 className="text-lg font-semibold">{price.symbol}</h3>
                    <p className="text-2xl font-bold tabular-nums">{formatCurrency(price.price)}</p>
                  </div>
                  <div className={`text-sm font-medium px-2 py-1 rounded ${(price.change_15m_pct ?? 0) >= 0 ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'}`}>
                    {price.change_15m_pct != null ? `${price.change_15m_pct >= 0 ? '+' : ''}${price.change_15m_pct.toFixed(2)}%` : '--'}
                  </div>
                </div>
                {price.is_stale && <span className="text-xs text-yellow-400 mt-2 block">⚠ Stale data</span>}
              </div>
            ))
          )}
        </div>
      </div>

      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Bot Controls</h2>
        <div className="flex items-center gap-4">
          <button onClick={() => handleBotAction('start')} className="flex items-center gap-2 bg-green-600 hover:bg-green-500 text-white px-4 py-2 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed transition-colors" disabled={botState?.state === 'RUNNING'}>
            <Icons.Play /> Start
          </button>
          <button onClick={() => handleBotAction('pause')} className="flex items-center gap-2 bg-yellow-600 hover:bg-yellow-500 text-white px-4 py-2 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed transition-colors" disabled={botState?.state === 'PAUSED'}>
            <Icons.Pause /> Pause
          </button>
          <button onClick={() => handleBotAction('stop')} className="flex items-center gap-2 bg-red-600 hover:bg-red-500 text-white px-4 py-2 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed transition-colors" disabled={botState?.state === 'STOPPED'}>
            <Icons.Stop /> Stop
          </button>
          <div className="ml-auto flex items-center gap-2 text-sm text-gray-400">
            <Icons.Lock />
            Password protected
          </div>
        </div>
        {botState && !botState.can_trade && (
          <p className="mt-3 text-yellow-400 text-sm bg-yellow-500/10 px-3 py-2 rounded">{botState.reason}</p>
        )}
      </div>

      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Open Positions ({positions.length})</h2>
        {positions.length === 0 ? (
          <p className="text-gray-400 text-center py-8">No open positions</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="text-left text-gray-400 text-sm border-b border-slate-700">
                  <th className="pb-2">Asset</th>
                  <th className="pb-2">Side</th>
                  <th className="pb-2">Size</th>
                  <th className="pb-2">Entry</th>
                  <th className="pb-2">Current</th>
                  <th className="pb-2">P&L</th>
                </tr>
              </thead>
              <tbody>
                {positions.map(pos => (
                  <tr key={pos.id} className="border-b border-slate-700/50">
                    <td className="py-3 font-medium">{pos.asset}</td>
                    <td className={`py-3 ${pos.side === 'UP' || pos.side === 'YES' ? 'text-green-400' : 'text-red-400'}`}>{pos.side}</td>
                    <td className="py-3 tabular-nums">{formatCurrency(pos.size)}</td>
                    <td className="py-3 tabular-nums">{formatCurrency(pos.entry_price)}</td>
                    <td className="py-3 tabular-nums">{formatCurrency(pos.current_price)}</td>
                    <td className="py-3 tabular-nums">{formatPnL(pos.unrealized_pnl)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Recent Trades</h2>
        {trades.length === 0 ? (
          <p className="text-gray-400 text-center py-8">No recent trades</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="text-left text-gray-400 text-sm border-b border-slate-700">
                  <th className="pb-2">Time</th>
                  <th className="pb-2">Asset</th>
                  <th className="pb-2">Side</th>
                  <th className="pb-2">Size</th>
                  <th className="pb-2">Price</th>
                  <th className="pb-2">Status</th>
                </tr>
              </thead>
              <tbody>
                {trades.slice(0, 10).map(trade => (
                  <tr key={trade.id} className="border-b border-slate-700/50">
                    <td className="py-3 text-sm text-gray-400">{new Date(trade.created_at).toLocaleTimeString()}</td>
                    <td className="py-3 font-medium">{trade.asset}</td>
                    <td className={`py-3 ${trade.side === 'BUY' ? 'text-green-400' : 'text-red-400'}`}>{trade.side}</td>
                    <td className="py-3 tabular-nums">{formatCurrency(trade.size)}</td>
                    <td className="py-3 tabular-nums">{formatCurrency(trade.price)}</td>
                    <td className="py-3">
                      <span className={`px-2 py-0.5 rounded text-xs ${trade.status === 'FILLED' ? 'bg-green-500/20 text-green-400' : trade.status === 'PENDING' ? 'bg-yellow-500/20 text-yellow-400' : 'bg-gray-500/20 text-gray-400'}`}>{trade.status}</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )

  const ExposureContent = () => (
    <div className="space-y-6">
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Position Exposure</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <div className="bg-slate-900 rounded-lg p-4">
            <p className="text-gray-400 text-sm">Total Exposure</p>
            <p className="text-2xl font-bold">{formatCurrency(wallet.in_positions)}</p>
          </div>
          <div className="bg-slate-900 rounded-lg p-4">
            <p className="text-gray-400 text-sm">Available Capital</p>
            <p className="text-2xl font-bold">{formatCurrency(wallet.available)}</p>
          </div>
          <div className="bg-slate-900 rounded-lg p-4">
            <p className="text-gray-400 text-sm">Exposure %</p>
            <p className="text-2xl font-bold">{wallet.balance > 0 ? ((wallet.in_positions / wallet.balance) * 100).toFixed(1) : 0}%</p>
          </div>
        </div>
        
        <h3 className="font-semibold mb-3">Exposure by Asset</h3>
        <div className="space-y-2">
          {['BTC', 'ETH', 'SOL'].map(asset => {
            const assetPositions = positions.filter(p => p.asset === asset)
            const assetExposure = assetPositions.reduce((sum, p) => sum + p.size, 0)
            const maxExposure = wallet.balance * 0.2
            const percentage = maxExposure > 0 ? (assetExposure / maxExposure) * 100 : 0
            
            return (
              <div key={asset} className="bg-slate-900 rounded-lg p-3">
                <div className="flex justify-between mb-2">
                  <span className="font-medium">{asset}</span>
                  <span className="text-gray-400">{formatCurrency(assetExposure)}</span>
                </div>
                <div className="h-2 bg-slate-700 rounded-full overflow-hidden">
                  <div className={`h-full rounded-full transition-all ${percentage > 80 ? 'bg-red-500' : percentage > 50 ? 'bg-yellow-500' : 'bg-green-500'}`} style={{ width: `${Math.min(percentage, 100)}%` }} />
                </div>
              </div>
            )
          })}
        </div>
      </div>

      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Circuit Breakers</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {circuitBreakers.length === 0 ? (
            <p className="text-gray-400 col-span-2">No circuit breakers configured</p>
          ) : (
            circuitBreakers.map(cb => (
              <div key={cb.name} className={`p-4 rounded-lg border ${cb.is_tripped ? 'bg-red-500/10 border-red-500' : 'bg-slate-900 border-slate-700'}`}>
                <div className="flex justify-between items-center">
                  <span className="font-medium">{cb.name}</span>
                  <span className={`px-2 py-0.5 rounded text-xs ${cb.is_tripped ? 'bg-red-500 text-white' : 'bg-green-500/20 text-green-400'}`}>{cb.is_tripped ? 'TRIPPED' : 'OK'}</span>
                </div>
                <p className="text-sm text-gray-400 mt-1">Trip count: {cb.trip_count}</p>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  )

  const HealthContent = () => (
    <div className="space-y-6">
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Service Health</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {[
            { name: 'API Server', key: 'api' },
            { name: 'Database', key: 'database' },
            { name: 'Trading Worker', key: 'worker' },
            { name: 'Polymarket API', key: 'polymarket' },
            { name: 'Price Service', key: 'prices' },
          ].map(service => {
            const health = services.find(s => s.name === service.key)
            return (
              <div key={service.key} className="flex items-center justify-between bg-slate-900 rounded-lg p-4">
                <div className="flex items-center gap-3">
                  <Icons.Server />
                  <span>{service.name}</span>
                </div>
                <div className="flex items-center gap-2">
                  {getStatusIcon(health?.status || 'down')}
                  <span className={health?.status === 'healthy' ? 'text-green-400' : health?.status === 'degraded' ? 'text-yellow-400' : 'text-red-400'}>{health?.status || 'unknown'}</span>
                </div>
              </div>
            )
          })}
        </div>
      </div>

      <div className="card">
        <h2 className="text-lg font-semibold mb-4">System Information</h2>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="bg-slate-900 rounded-lg p-4">
            <p className="text-gray-400 text-sm">Total Candles</p>
            <p className="text-xl font-bold">363+</p>
          </div>
          <div className="bg-slate-900 rounded-lg p-4">
            <p className="text-gray-400 text-sm">Active Markets</p>
            <p className="text-xl font-bold">9</p>
          </div>
          <div className="bg-slate-900 rounded-lg p-4">
            <p className="text-gray-400 text-sm">Decisions Today</p>
            <p className="text-xl font-bold">0</p>
          </div>
          <div className="bg-slate-900 rounded-lg p-4">
            <p className="text-gray-400 text-sm">Orders Today</p>
            <p className="text-xl font-bold">{trades.length}</p>
          </div>
        </div>
      </div>
    </div>
  )

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
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-slate-900 text-white">
      <nav className="bg-slate-800 border-b border-slate-700 sticky top-0 z-40">
        <div className="max-w-7xl mx-auto px-4">
          <div className="flex items-center justify-between h-14">
            <div className="flex items-center gap-2">
              <span className="text-xl font-bold bg-gradient-to-r from-blue-400 to-purple-500 bg-clip-text text-transparent">PolyTrader</span>
            </div>
            <div className="flex items-center gap-1">
              {navItems.map(item => (
                <button key={item.id} onClick={() => setActiveTab(item.id)} className={`flex items-center gap-2 px-4 py-2 rounded-lg transition-colors ${activeTab === item.id ? 'bg-blue-600 text-white' : 'text-gray-400 hover:text-white hover:bg-slate-700'}`}>
                  <item.icon />
                  <span className="hidden md:inline">{item.label}</span>
                </button>
              ))}
            </div>
          </div>
        </div>
      </nav>

      <OperationalStatus />

      <main className="max-w-7xl mx-auto px-4 py-6">
        {loading ? (
          <div className="flex items-center justify-center h-64">
            <div className="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-blue-500"></div>
          </div>
        ) : (
          <>
            {activeTab === 'dashboard' && <DashboardContent />}
            {activeTab === 'exposure' && <ExposureContent />}
            {activeTab === 'health' && <HealthContent />}
            {activeTab === 'config' && <ConfigContent />}
          </>
        )}
      </main>

      <PasswordModal isOpen={passwordModal.isOpen} onClose={() => setPasswordModal({ isOpen: false, action: '' })} onConfirm={() => confirmBotAction(passwordModal.action)} action={passwordModal.action} />
    </div>
  )
}