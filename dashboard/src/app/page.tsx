'use client'

import { useState, useEffect, useCallback } from 'react'
import Navbar from '@/components/Navbar'

// Ensure API_URL always has proper protocol and doesn't get mangled
const getApiUrl = (): string => {
  const envUrl = process.env.NEXT_PUBLIC_API_URL || ''
  
  // If we're in the browser and no env var, use current origin for local dev
  if (typeof window !== 'undefined' && !envUrl) {
    return 'http://localhost:8000'
  }
  
  // Ensure the URL has a protocol
  if (envUrl && !envUrl.startsWith('http://') && !envUrl.startsWith('https://')) {
    return `http://${envUrl}`
  }
  
  return envUrl || 'http://localhost:8000'
}

const API_URL = getApiUrl()

interface BotState {
  status: string
  is_trading: boolean
  last_trade?: string
  uptime_seconds?: number
  [key: string]: unknown
}

interface ServiceHealth {
  name: string
  status: string
  last_check: string
  details?: Record<string, unknown>
}

interface CircuitBreaker {
  name: string
  state: string
  failure_count: number
  last_failure?: string
}

interface PriceData {
  market: string
  price: number
  timestamp: string
  source: string
}

interface Position {
  market: string
  side: string
  size: number
  entry_price: number
  current_price?: number
  pnl?: number
}

interface Order {
  id: string
  market: string
  side: string
  size: number
  price: number
  status: string
  created_at: string
}

interface DailyPnL {
  date: string
  pnl: number
  trades: number
  win_rate?: number
}

interface ConfigItem {
  key: string
  value: string
  description?: string
}

type TabType = 'overview' | 'positions' | 'orders' | 'config'

export default function Home() {
  const [authenticated, setAuthenticated] = useState(false)
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [activeTab, setActiveTab] = useState<TabType>('overview')
  
  // Data states
  const [botState, setBotState] = useState<BotState | null>(null)
  const [services, setServices] = useState<ServiceHealth[]>([])
  const [circuitBreakers, setCircuitBreakers] = useState<CircuitBreaker[]>([])
  const [prices, setPrices] = useState<PriceData[]>([])
  const [positions, setPositions] = useState<Position[]>([])
  const [orders, setOrders] = useState<Order[]>([])
  const [dailyPnL, setDailyPnL] = useState<DailyPnL[]>([])
  const [configs, setConfigs] = useState<ConfigItem[]>([])
  const [walletBalance, setWalletBalance] = useState<number | null>(null)
  const [loading, setLoading] = useState(true)

  // Auto-refresh state
  const [autoRefresh, setAutoRefresh] = useState(true)
  const REFRESH_INTERVAL = 5000

  const handleLogin = (e: React.FormEvent) => {
    e.preventDefault()
    if (password === 'poly15admin') {
      setAuthenticated(true)
      setError('')
      localStorage.setItem('poly15_auth', 'true')
    } else {
      setError('Invalid password')
    }
  }

  useEffect(() => {
    const isAuth = localStorage.getItem('poly15_auth')
    if (isAuth === 'true') {
      setAuthenticated(true)
    }
  }, [])

  const fetchData = useCallback(async () => {
    if (!authenticated) return
    
    try {
      const endpoints = [
        { key: 'state', url: `${API_URL}/v1/admin/bot/state` },
        { key: 'services', url: `${API_URL}/v1/health/services` },
        { key: 'circuitBreakers', url: `${API_URL}/v1/admin/circuit-breakers` },
        { key: 'prices', url: `${API_URL}/v1/prices/latest` },
        { key: 'positions', url: `${API_URL}/v1/positions` },
        { key: 'orders', url: `${API_URL}/v1/orders?limit=20` },
        { key: 'daily', url: `${API_URL}/v1/pnl/daily` },
        { key: 'config', url: `${API_URL}/v1/config` },
        { key: 'balance', url: `${API_URL}/v1/admin/wallet/balance` },
      ]

      const results = await Promise.allSettled(
        endpoints.map(ep => 
          fetch(ep.url).then(r => r.ok ? r.json() : Promise.reject(r.status))
        )
      )

      results.forEach((result, i) => {
        if (result.status === 'fulfilled') {
          const data = result.value
          switch (endpoints[i].key) {
            case 'state':
              setBotState(data.state || data)
              break
            case 'services':
              setServices(data.services || [])
              break
            case 'circuitBreakers':
              setCircuitBreakers(data.circuit_breakers || [])
              break
            case 'prices':
              setPrices(data.prices || [])
              break
            case 'positions':
              setPositions(data.positions || [])
              break
            case 'orders':
              setOrders(data.orders || [])
              break
            case 'daily':
              setDailyPnL(data.daily || [])
              break
            case 'config':
              // Handle both array and object formats
              if (data.config && typeof data.config === 'object' && !Array.isArray(data.config)) {
                // Convert object to array format
                const configArray = Object.entries(data.config).map(([key, value]) => ({
                  key,
                  value: String(value),
                  description: ''
                }))
                setConfigs(configArray)
              } else {
                setConfigs(data.configs || data.config || [])
              }
              break
            case 'balance':
              setWalletBalance(data.balance ?? data.usdc_balance ?? null)
              break
          }
        }
      })
    } catch (err) {
      console.error('Fetch error:', err)
    } finally {
      setLoading(false)
    }
  }, [authenticated])

  useEffect(() => {
    if (authenticated) {
      fetchData()
    }
  }, [authenticated, fetchData])

  useEffect(() => {
    if (!authenticated || !autoRefresh || activeTab === 'config') return
    
    const interval = setInterval(fetchData, REFRESH_INTERVAL)
    return () => clearInterval(interval)
  }, [authenticated, autoRefresh, activeTab, fetchData])

  const formatUptime = (seconds?: number) => {
    if (!seconds) return 'N/A'
    const hours = Math.floor(seconds / 3600)
    const mins = Math.floor((seconds % 3600) / 60)
    return `${hours}h ${mins}m`
  }

  const getStatusColor = (status: string) => {
    switch (status?.toLowerCase()) {
      case 'healthy':
      case 'running':
      case 'closed':
        return 'text-green-400'
      case 'degraded':
      case 'half-open':
        return 'text-yellow-400'
      case 'unhealthy':
      case 'stopped':
      case 'open':
        return 'text-red-400'
      default:
        return 'text-gray-400'
    }
  }

  if (!authenticated) {
    return (
      <div className="min-h-screen bg-gray-900 flex items-center justify-center">
        <div className="bg-gray-800 p-8 rounded-lg shadow-xl w-96">
          <h1 className="text-2xl font-bold text-white mb-6 text-center">PolyTrader Dashboard</h1>
          <form onSubmit={handleLogin}>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Enter password"
              className="w-full p-3 bg-gray-700 text-white rounded mb-4 focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
            {error && <p className="text-red-400 text-sm mb-4">{error}</p>}
            <button
              type="submit"
              className="w-full bg-blue-600 text-white p-3 rounded hover:bg-blue-700 transition"
            >
              Login
            </button>
          </form>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-900 text-white">
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
            {activeTab === 'overview' && (
              <div className="space-y-6">
                {/* Bot Status Card */}
                <div className="bg-gray-800 rounded-lg p-6">
                  <h2 className="text-xl font-semibold mb-4">Bot Status</h2>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                    <div>
                      <p className="text-gray-400 text-sm">Status</p>
                      <p className={`text-lg font-semibold ${getStatusColor(botState?.status || '')}`}>
                        {botState?.status || 'Unknown'}
                      </p>
                    </div>
                    <div>
                      <p className="text-gray-400 text-sm">Trading</p>
                      <p className={`text-lg font-semibold ${botState?.is_trading ? 'text-green-400' : 'text-red-400'}`}>
                        {botState?.is_trading ? 'Active' : 'Inactive'}
                      </p>
                    </div>
                    <div>
                      <p className="text-gray-400 text-sm">Uptime</p>
                      <p className="text-lg font-semibold">{formatUptime(botState?.uptime_seconds)}</p>
                    </div>
                    <div>
                      <p className="text-gray-400 text-sm">Wallet Balance</p>
                      <p className="text-lg font-semibold text-green-400">
                        {walletBalance !== null ? `$${walletBalance.toFixed(2)}` : 'N/A'}
                      </p>
                    </div>
                  </div>
                </div>

                {/* Services Health */}
                <div className="bg-gray-800 rounded-lg p-6">
                  <h2 className="text-xl font-semibold mb-4">Services</h2>
                  <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
                    {services.map((service, i) => (
                      <div key={i} className="bg-gray-700 rounded p-3">
                        <p className="text-sm text-gray-300">{service.name}</p>
                        <p className={`font-semibold ${getStatusColor(service.status)}`}>
                          {service.status}
                        </p>
                      </div>
                    ))}
                  </div>
                </div>

                {/* Circuit Breakers */}
                <div className="bg-gray-800 rounded-lg p-6">
                  <h2 className="text-xl font-semibold mb-4">Circuit Breakers</h2>
                  <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
                    {circuitBreakers.map((cb, i) => (
                      <div key={i} className="bg-gray-700 rounded p-3">
                        <p className="text-sm text-gray-300">{cb.name}</p>
                        <p className={`font-semibold ${getStatusColor(cb.state)}`}>
                          {cb.state} ({cb.failure_count} failures)
                        </p>
                      </div>
                    ))}
                  </div>
                </div>

                {/* Latest Prices */}
                <div className="bg-gray-800 rounded-lg p-6">
                  <h2 className="text-xl font-semibold mb-4">Latest Prices</h2>
                  <div className="overflow-x-auto">
                    <table className="w-full">
                      <thead>
                        <tr className="text-left text-gray-400 border-b border-gray-700">
                          <th className="pb-2">Market</th>
                          <th className="pb-2">Price</th>
                          <th className="pb-2">Source</th>
                          <th className="pb-2">Updated</th>
                        </tr>
                      </thead>
                      <tbody>
                        {prices.map((p, i) => (
                          <tr key={i} className="border-b border-gray-700">
                            <td className="py-2">{p.market}</td>
                            <td className="py-2">${p.price?.toFixed(4) || 'N/A'}</td>
                            <td className="py-2 text-gray-400">{p.source}</td>
                            <td className="py-2 text-gray-400">{new Date(p.timestamp).toLocaleTimeString()}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>

                {/* Daily P&L */}
                <div className="bg-gray-800 rounded-lg p-6">
                  <h2 className="text-xl font-semibold mb-4">Daily P&L</h2>
                  <div className="overflow-x-auto">
                    <table className="w-full">
                      <thead>
                        <tr className="text-left text-gray-400 border-b border-gray-700">
                          <th className="pb-2">Date</th>
                          <th className="pb-2">P&L</th>
                          <th className="pb-2">Trades</th>
                          <th className="pb-2">Win Rate</th>
                        </tr>
                      </thead>
                      <tbody>
                        {dailyPnL.map((d, i) => (
                          <tr key={i} className="border-b border-gray-700">
                            <td className="py-2">{d.date}</td>
                            <td className={`py-2 ${d.pnl >= 0 ? 'text-green-400' : 'text-red-400'}`}>
                              ${d.pnl?.toFixed(2) || '0.00'}
                            </td>
                            <td className="py-2">{d.trades}</td>
                            <td className="py-2">{d.win_rate ? `${(d.win_rate * 100).toFixed(1)}%` : 'N/A'}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              </div>
            )}

            {activeTab === 'positions' && (
              <div className="bg-gray-800 rounded-lg p-6">
                <h2 className="text-xl font-semibold mb-4">Open Positions</h2>
                {positions.length === 0 ? (
                  <p className="text-gray-400">No open positions</p>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full">
                      <thead>
                        <tr className="text-left text-gray-400 border-b border-gray-700">
                          <th className="pb-2">Market</th>
                          <th className="pb-2">Side</th>
                          <th className="pb-2">Size</th>
                          <th className="pb-2">Entry</th>
                          <th className="pb-2">Current</th>
                          <th className="pb-2">P&L</th>
                        </tr>
                      </thead>
                      <tbody>
                        {positions.map((p, i) => (
                          <tr key={i} className="border-b border-gray-700">
                            <td className="py-2">{p.market}</td>
                            <td className={`py-2 ${p.side === 'buy' ? 'text-green-400' : 'text-red-400'}`}>
                              {p.side?.toUpperCase()}
                            </td>
                            <td className="py-2">{p.size}</td>
                            <td className="py-2">${p.entry_price?.toFixed(4)}</td>
                            <td className="py-2">${p.current_price?.toFixed(4) || 'N/A'}</td>
                            <td className={`py-2 ${(p.pnl || 0) >= 0 ? 'text-green-400' : 'text-red-400'}`}>
                              ${p.pnl?.toFixed(2) || '0.00'}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            )}

            {activeTab === 'orders' && (
              <div className="bg-gray-800 rounded-lg p-6">
                <h2 className="text-xl font-semibold mb-4">Recent Orders</h2>
                {orders.length === 0 ? (
                  <p className="text-gray-400">No recent orders</p>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full">
                      <thead>
                        <tr className="text-left text-gray-400 border-b border-gray-700">
                          <th className="pb-2">ID</th>
                          <th className="pb-2">Market</th>
                          <th className="pb-2">Side</th>
                          <th className="pb-2">Size</th>
                          <th className="pb-2">Price</th>
                          <th className="pb-2">Status</th>
                          <th className="pb-2">Created</th>
                        </tr>
                      </thead>
                      <tbody>
                        {orders.map((o, i) => (
                          <tr key={i} className="border-b border-gray-700">
                            <td className="py-2 font-mono text-sm">{o.id?.slice(0, 8)}...</td>
                            <td className="py-2">{o.market}</td>
                            <td className={`py-2 ${o.side === 'buy' ? 'text-green-400' : 'text-red-400'}`}>
                              {o.side?.toUpperCase()}
                            </td>
                            <td className="py-2">{o.size}</td>
                            <td className="py-2">${o.price?.toFixed(4)}</td>
                            <td className={`py-2 ${getStatusColor(o.status)}`}>{o.status}</td>
                            <td className="py-2 text-gray-400">{new Date(o.created_at).toLocaleString()}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            )}

            {activeTab === 'config' && (
              <div className="bg-gray-800 rounded-lg p-6">
                <h2 className="text-xl font-semibold mb-4">Configuration</h2>
                <div className="overflow-x-auto">
                  <table className="w-full">
                    <thead>
                      <tr className="text-left text-gray-400 border-b border-gray-700">
                        <th className="pb-2">Key</th>
                        <th className="pb-2">Value</th>
                        <th className="pb-2">Description</th>
                      </tr>
                    </thead>
                    <tbody>
                      {configs.map((c, i) => (
                        <tr key={i} className="border-b border-gray-700">
                          <td className="py-2 font-mono text-blue-400">{c.key}</td>
                          <td className="py-2">{c.value}</td>
                          <td className="py-2 text-gray-400">{c.description || '--'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <p className="text-gray-500 text-sm mt-4">
                  API URL: {API_URL}
                </p>
              </div>
            )}
          </>
        )}
      </main>
    </div>
  )
}