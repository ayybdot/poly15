#Requires -Version 5.1
<#
.SYNOPSIS
    Step 06: Setup Dashboard
.DESCRIPTION
    Configures and builds the Next.js dashboard.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\_lib.ps1"

if (-not (Test-Marker -Name "worker_dry_ok")) {
    Write-Host "ERROR: Worker not set up. Run 05_setup_worker.ps1 first." -ForegroundColor Red
    exit 1
}

$logFile = Start-Log -StepNumber "06" -StepName "setup_dashboard"
Write-StepHeader "06" "SETUP DASHBOARD"

$root = Get-PolyTraderRoot
$dashboardDir = Join-Path $root "dashboard"

try {
    Write-Section "Verify Dashboard Structure"
    
    $requiredFiles = @(
        "package.json",
        "next.config.js",
        "tailwind.config.js",
        "tsconfig.json"
    )
    
    foreach ($file in $requiredFiles) {
        $path = Join-Path $dashboardDir $file
        if (Test-Path $path) {
            Write-Ok "Found: $file"
        }
        else {
            Write-Fail "Missing: $file"
            throw "Required file missing: $file"
        }
    }
    
    Write-Section "Install Node Dependencies"
    
    Push-Location $dashboardDir
    try {
        if (-not (Test-Path "node_modules")) {
            Write-Status "Running npm install..." -Icon "Arrow"
            $result = Invoke-LoggedCommand -Command "npm install" -ContinueOnError
            if ($result.Success) {
                Write-Ok "npm install completed"
            }
            else {
                Write-Warn "npm install had issues, continuing..."
            }
        }
        else {
            Write-Ok "node_modules already exists"
        }
    }
    finally {
        Pop-Location
    }
    
    Write-Section "Create Dashboard Source Files"
    
    # Create src directories
    $srcDirs = @(
        "src\app",
        "src\app\trades",
        "src\app\exposure",
        "src\app\health",
        "src\app\config",
        "src\app\install-status",
        "src\components",
        "src\lib"
    )
    
    foreach ($dir in $srcDirs) {
        $path = Join-Path $dashboardDir $dir
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
    Write-Ok "Source directories created"
    
    # Check if dashboard files already exist (from ZIP extraction)
    $layoutFile = Join-Path $dashboardDir "src\app\layout.tsx"
    $pageFile = Join-Path $dashboardDir "src\app\page.tsx"
    
    if ((Test-Path $layoutFile) -and (Test-Path $pageFile)) {
        Write-Ok "Dashboard source files already exist (from ZIP), skipping creation"
    }
    else {
        Write-Status "Creating dashboard source files..." -Icon "Arrow"
        
    # Create globals.css
    $globalsCss = @"
@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  --foreground-rgb: 0, 0, 0;
  --background-start-rgb: 250, 250, 250;
  --background-end-rgb: 255, 255, 255;
}

@media (prefers-color-scheme: dark) {
  :root {
    --foreground-rgb: 255, 255, 255;
    --background-start-rgb: 15, 23, 42;
    --background-end-rgb: 30, 41, 59;
  }
}

body {
  color: rgb(var(--foreground-rgb));
  background: linear-gradient(
      to bottom,
      transparent,
      rgb(var(--background-end-rgb))
    )
    rgb(var(--background-start-rgb));
}

.card {
  @apply bg-white dark:bg-slate-800 rounded-lg shadow-md p-4;
}

.btn-primary {
  @apply bg-primary-600 hover:bg-primary-700 text-white px-4 py-2 rounded-md transition-colors;
}

.btn-danger {
  @apply bg-danger-500 hover:bg-danger-600 text-white px-4 py-2 rounded-md transition-colors;
}

.status-badge {
  @apply inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium;
}
"@
    Set-Content -Path (Join-Path $dashboardDir "src\app\globals.css") -Value $globalsCss -Encoding UTF8
    Write-Ok "Created globals.css"
    
    # Create layout.tsx
    $layoutTsx = @'
import type { Metadata } from 'next'
import { Inter, JetBrains_Mono } from 'next/font/google'
import './globals.css'

const inter = Inter({ subsets: ['latin'], variable: '--font-inter' })
const jetbrainsMono = JetBrains_Mono({ subsets: ['latin'], variable: '--font-mono' })

export const metadata: Metadata = {
  title: 'PolyTrader Dashboard',
  description: 'Polymarket Autotrader for BTC/ETH/SOL 15-minute markets',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" className="dark">
      <body className={`${inter.variable} ${jetbrainsMono.variable} font-sans bg-slate-900 text-white min-h-screen`}>
        {children}
      </body>
    </html>
  )
}
'@
    Set-Content -Path (Join-Path $dashboardDir "src\app\layout.tsx") -Value $layoutTsx -Encoding UTF8
    Write-Ok "Created layout.tsx"
    
    # Create main page
    $pageTsx = @"
'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'

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

export default function Home() {
  const [prices, setPrices] = useState<Price[]>([])
  const [botState, setBotState] = useState<BotState | null>(null)
  const [loading, setLoading] = useState(true)

  const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000'

  useEffect(() => {
    const fetchData = async () => {
      try {
        const [priceRes, stateRes] = await Promise.all([
          fetch(``${API_URL}/v1/prices/latest``),
          fetch(``${API_URL}/v1/admin/bot/state``)
        ])
        
        if (priceRes.ok) {
          const data = await priceRes.json()
          setPrices(data.prices || [])
        }
        
        if (stateRes.ok) {
          const data = await stateRes.json()
          setBotState(data)
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

  const handleBotAction = async (action: 'start' | 'pause' | 'stop') => {
    try {
      const res = await fetch(``${API_URL}/v1/admin/bot/`${action}``, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ reason: ``Manual `${action} from dashboard``, user: 'dashboard' })
      })
      if (res.ok) {
        const data = await res.json()
        setBotState(prev => prev ? { ...prev, state: data.state } : null)
      }
    } catch (error) {
      console.error(``Failed to `${action} bot:``, error)
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

  return (
    <main className="min-h-screen p-8">
      <div className="max-w-7xl mx-auto">
        {/* Header */}
        <div className="flex justify-between items-center mb-8">
          <h1 className="text-3xl font-bold">PolyTrader Dashboard</h1>
          <div className="flex items-center gap-4">
            {botState && (
              <span className={``${getStateColor(botState.state)} px-3 py-1 rounded-full text-sm font-medium``}>
                {botState.state}
              </span>
            )}
          </div>
        </div>

        {/* Price Cards */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
          {prices.map(price => (
            <div key={price.symbol} className="card">
              <div className="flex justify-between items-start">
                <div>
                  <h3 className="text-lg font-semibold">{price.symbol}</h3>
                  <p className="text-2xl font-bold">
                    `${price.price?.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                  </p>
                </div>
                <div className={``text-sm `${(price.change_15m_pct || 0) >= 0 ? 'text-green-400' : 'text-red-400'}``}>
                  {price.change_15m_pct !== null ? 
                    ``${price.change_15m_pct >= 0 ? '+' : ''}`${price.change_15m_pct.toFixed(2)}%`` : 
                    '--'}
                </div>
              </div>
              {price.is_stale && (
                <span className="text-xs text-yellow-400 mt-2 block">⚠ Stale data</span>
              )}
            </div>
          ))}
        </div>

        {/* Bot Controls */}
        <div className="card mb-8">
          <h2 className="text-xl font-semibold mb-4">Bot Controls</h2>
          <div className="flex gap-4">
            <button 
              onClick={() => handleBotAction('start')}
              className="btn-primary"
              disabled={botState?.state === 'RUNNING'}
            >
              Start
            </button>
            <button 
              onClick={() => handleBotAction('pause')}
              className="bg-yellow-500 hover:bg-yellow-600 text-white px-4 py-2 rounded-md"
              disabled={botState?.state === 'PAUSED'}
            >
              Pause
            </button>
            <button 
              onClick={() => handleBotAction('stop')}
              className="btn-danger"
              disabled={botState?.state === 'STOPPED'}
            >
              Stop
            </button>
          </div>
          {botState && !botState.can_trade && (
            <p className="mt-2 text-yellow-400 text-sm">{botState.reason}</p>
          )}
        </div>

        {/* Navigation */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <Link href="/trades" className="card hover:bg-slate-700 transition-colors">
            <h3 className="font-semibold">Trades</h3>
            <p className="text-sm text-gray-400">View trade history</p>
          </Link>
          <Link href="/exposure" className="card hover:bg-slate-700 transition-colors">
            <h3 className="font-semibold">Exposure & Risk</h3>
            <p className="text-sm text-gray-400">Position exposure</p>
          </Link>
          <Link href="/health" className="card hover:bg-slate-700 transition-colors">
            <h3 className="font-semibold">Health & Ops</h3>
            <p className="text-sm text-gray-400">System health</p>
          </Link>
          <Link href="/config" className="card hover:bg-slate-700 transition-colors">
            <h3 className="font-semibold">Configuration</h3>
            <p className="text-sm text-gray-400">Risk settings</p>
          </Link>
          <Link href="/install-status" className="card hover:bg-slate-700 transition-colors">
            <h3 className="font-semibold">Install Status</h3>
            <p className="text-sm text-gray-400">Installation progress</p>
          </Link>
        </div>
      </div>
    </main>
  )
}
"@
    Set-Content -Path (Join-Path $dashboardDir "src\app\page.tsx") -Value $pageTsx -Encoding UTF8
    Write-Ok "Created main page"
    
    # Create install-status page
    $installStatusPage = @"
'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'

interface Step {
  step: string
  name: string
  description: string
  status: string
  marker: string
  marker_exists: boolean
  marker_timestamp: string | null
  log_file: string | null
}

interface InstallStatus {
  overall_status: string
  progress: string
  steps: Step[]
  next_step: string | null
  next_script: string | null
}

export default function InstallStatusPage() {
  const [status, setStatus] = useState<InstallStatus | null>(null)
  const [logContent, setLogContent] = useState<string[]>([])
  const [selectedStep, setSelectedStep] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000'

  useEffect(() => {
    fetchStatus()
  }, [])

  const fetchStatus = async () => {
    try {
      const res = await fetch(``${API_URL}/v1/install/status``)
      if (res.ok) {
        const data = await res.json()
        setStatus(data)
      }
    } catch (error) {
      console.error('Failed to fetch install status:', error)
    } finally {
      setLoading(false)
    }
  }

  const fetchLog = async (step: string) => {
    try {
      setSelectedStep(step)
      const res = await fetch(``${API_URL}/v1/install/logs/tail?step=`${step}&lines=200``)
      if (res.ok) {
        const data = await res.json()
        setLogContent(data.lines || [])
      }
    } catch (error) {
      console.error('Failed to fetch log:', error)
      setLogContent(['Failed to load log file'])
    }
  }

  const getStatusBadge = (stepStatus: string) => {
    switch (stepStatus) {
      case 'DONE':
        return <span className="bg-green-500 text-white px-2 py-1 rounded text-xs">DONE</span>
      case 'NOT_DONE':
        return <span className="bg-gray-500 text-white px-2 py-1 rounded text-xs">NOT DONE</span>
      case 'LIKELY_FAILED':
        return <span className="bg-red-500 text-white px-2 py-1 rounded text-xs">LIKELY FAILED</span>
      default:
        return <span className="bg-yellow-500 text-white px-2 py-1 rounded text-xs">{stepStatus}</span>
    }
  }

  if (loading) {
    return <div className="min-h-screen p-8 flex items-center justify-center">Loading...</div>
  }

  return (
    <main className="min-h-screen p-8">
      <div className="max-w-6xl mx-auto">
        <div className="flex justify-between items-center mb-8">
          <h1 className="text-3xl font-bold">Installation Status</h1>
          <Link href="/" className="text-primary-400 hover:text-primary-300">← Back to Dashboard</Link>
        </div>

        {status && (
          <>
            {/* Overall Status */}
            <div className="card mb-8">
              <div className="flex justify-between items-center">
                <div>
                  <h2 className="text-xl font-semibold">Overall: {status.overall_status}</h2>
                  <p className="text-gray-400">Progress: {status.progress}</p>
                </div>
                {status.next_script && (
                  <div className="text-right">
                    <p className="text-sm text-gray-400">Next step:</p>
                    <code className="text-primary-400">{status.next_script}</code>
                  </div>
                )}
              </div>
            </div>

            {/* Steps Table */}
            <div className="card mb-8 overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="border-b border-slate-700">
                    <th className="text-left p-3">Step</th>
                    <th className="text-left p-3">Description</th>
                    <th className="text-left p-3">Status</th>
                    <th className="text-left p-3">Marker</th>
                    <th className="text-left p-3">Last Updated</th>
                    <th className="text-left p-3">Log</th>
                  </tr>
                </thead>
                <tbody>
                  {status.steps.map(step => (
                    <tr key={step.step} className="border-b border-slate-700/50 hover:bg-slate-700/30">
                      <td className="p-3 font-mono">{step.step}</td>
                      <td className="p-3">{step.description}</td>
                      <td className="p-3">{getStatusBadge(step.status)}</td>
                      <td className="p-3 text-sm">
                        {step.marker_exists ? (
                          <span className="text-green-400">✓ {step.marker}</span>
                        ) : (
                          <span className="text-gray-500">{step.marker}</span>
                        )}
                      </td>
                      <td className="p-3 text-sm text-gray-400">
                        {step.marker_timestamp ? new Date(step.marker_timestamp).toLocaleString() : '-'}
                      </td>
                      <td className="p-3">
                        {step.log_file && (
                          <button
                            onClick={() => fetchLog(step.step)}
                            className="text-primary-400 hover:text-primary-300 text-sm"
                          >
                            View Log
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Log Viewer */}
            {selectedStep && (
              <div className="card">
                <div className="flex justify-between items-center mb-4">
                  <h3 className="font-semibold">Log: Step {selectedStep}</h3>
                  <button
                    onClick={() => setSelectedStep(null)}
                    className="text-gray-400 hover:text-white"
                  >
                    Close
                  </button>
                </div>
                <pre className="bg-slate-900 p-4 rounded overflow-x-auto text-sm font-mono max-h-96 overflow-y-auto">
                  {logContent.join('\n')}
                </pre>
              </div>
            )}
          </>
        )}
      </div>
    </main>
  )
}
"@
    Set-Content -Path (Join-Path $dashboardDir "src\app\install-status\page.tsx") -Value $installStatusPage -Encoding UTF8
    Write-Ok "Created install-status page"
    
    } # End of else block for file creation
    
    Write-Section "Build Dashboard"
    
    Push-Location $dashboardDir
    try {
        Write-Status "Building Next.js application..." -Icon "Arrow"
        $result = Invoke-LoggedCommand -Command "npm run build" -ContinueOnError
        
        if ($result.Success) {
            Write-Ok "Dashboard build completed"
        }
        else {
            Write-Warn "Build had warnings - checking if .next exists"
            if (Test-Path (Join-Path $dashboardDir ".next")) {
                Write-Ok "Build output exists despite warnings"
            }
            else {
                throw "Dashboard build failed"
            }
        }
    }
    finally {
        Pop-Location
    }
    
    Write-Section "Create Dashboard Startup Script"
    
    $startScript = @"
@echo off
cd /d "$dashboardDir"
npm run start
"@
    
    $startScriptPath = Join-Path $root "start_dashboard.bat"
    Set-Content -Path $startScriptPath -Value $startScript -Encoding ASCII
    Write-Ok "Created start_dashboard.bat"
    
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Cyan
    Write-Ok "Dashboard setup completed successfully!"
    Set-Marker -Name "ui_ok"
    
    Write-Host ""
    Write-Host "  Dashboard can be started with: $startScriptPath" -ForegroundColor Gray
    Write-Host "  Access at: http://localhost:3000" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Next step: Run 07_register_services.ps1" -ForegroundColor Green
    Write-Host ""
    
    Stop-Log -Success $true
}
catch {
    Write-Fail "Dashboard setup failed: $_"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Stop-Log -Success $false
    Write-Host "  Check log file: $logFile" -ForegroundColor Red
    exit 1
}