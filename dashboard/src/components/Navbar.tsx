'use client'

import { API_URL } from '@/lib/config'

interface NavbarProps {
  activeTab: string
  setActiveTab: (tab: string) => void
  autoRefresh: boolean
  setAutoRefresh: (value: boolean) => void
  onRefresh: () => void
}

export default function Navbar({ 
  activeTab, 
  setActiveTab, 
  autoRefresh, 
  setAutoRefresh,
  onRefresh 
}: NavbarProps) {
  const tabs = [
    { id: 'dashboard', label: 'Dashboard', icon: '📊' },
    { id: 'positions', label: 'Positions', icon: '💼' },
    { id: 'trades', label: 'Trades', icon: '📈' },
    { id: 'config', label: 'Config', icon: '⚙️' },
  ]

  const handleLogout = () => {
    localStorage.removeItem('poly15_auth')
    window.location.reload()
  }

  return (
    <nav className="bg-slate-900 border-b border-slate-700">
      <div className="container mx-auto px-4">
        <div className="flex items-center justify-between h-14">
          {/* Logo / Brand */}
          <div className="flex items-center gap-3">
            <span className="text-xl font-bold text-white">🤖 PolyTrader</span>
            <span className="text-xs text-slate-400 hidden sm:inline">15-min Markets</span>
          </div>

          {/* Tabs */}
          <div className="flex items-center gap-1">
            {tabs.map(tab => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
                  activeTab === tab.id
                    ? 'bg-blue-600 text-white'
                    : 'text-slate-400 hover:text-white hover:bg-slate-800'
                }`}
              >
                <span className="mr-1.5">{tab.icon}</span>
                <span className="hidden sm:inline">{tab.label}</span>
              </button>
            ))}
          </div>

          {/* Controls */}
          <div className="flex items-center gap-3">
            {/* Auto-refresh toggle */}
            <div className="flex items-center gap-2">
              <span className="text-xs text-slate-400 hidden sm:inline">Auto</span>
              <label className="relative inline-flex items-center cursor-pointer">
                <input
                  type="checkbox"
                  checked={autoRefresh}
                  onChange={(e) => setAutoRefresh(e.target.checked)}
                  className="sr-only peer"
                />
                <div className="w-8 h-4 bg-gray-600 rounded-full peer peer-checked:after:translate-x-full after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-3 after:w-3 after:transition-all peer-checked:bg-green-600"></div>
              </label>
            </div>

            {/* Manual refresh */}
            <button
              onClick={onRefresh}
              className="p-2 text-slate-400 hover:text-white hover:bg-slate-800 rounded-lg transition-colors"
              title="Refresh"
            >
              🔄
            </button>

            {/* Logout */}
            <button
              onClick={handleLogout}
              className="p-2 text-slate-400 hover:text-red-400 hover:bg-slate-800 rounded-lg transition-colors"
              title="Logout"
            >
              🚪
            </button>
          </div>
        </div>
      </div>
    </nav>
  )
}