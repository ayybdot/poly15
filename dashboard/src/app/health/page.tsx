'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'

interface HealthData {
  status: string
  components: {
    [key: string]: {
      status: string
      [key: string]: any
    }
  }
  timestamp: string
}

export default function HealthPage() {
  const [health, setHealth] = useState<HealthData | null>(null)
  const [loading, setLoading] = useState(true)

  const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000'

  useEffect(() => {
    const fetchHealth = async () => {
      try {
        const res = await fetch(`${API_URL}/health/detailed`)
        if (res.ok) {
          setHealth(await res.json())
        }
      } catch (error) {
        console.error('Failed to fetch health:', error)
      } finally {
        setLoading(false)
      }
    }

    fetchHealth()
    const interval = setInterval(fetchHealth, 5000)
    return () => clearInterval(interval)
  }, [API_URL])

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'ok': return 'bg-green-500'
      case 'healthy': return 'bg-green-500'
      case 'degraded': return 'bg-yellow-500'
      case 'stale': return 'bg-yellow-500'
      case 'restricted': return 'bg-yellow-500'
      default: return 'bg-red-500'
    }
  }

  if (loading) {
    return <div className="min-h-screen p-8 flex items-center justify-center">Loading...</div>
  }

  return (
    <main className="min-h-screen p-8">
      <div className="max-w-4xl mx-auto">
        <div className="flex justify-between items-center mb-8">
          <h1 className="text-3xl font-bold">System Health</h1>
          <Link href="/" className="text-primary-400 hover:text-primary-300">← Back to Dashboard</Link>
        </div>

        {health && (
          <>
            {/* Overall Status */}
            <div className={`card mb-8 border-2 ${health.status === 'healthy' ? 'border-green-500' : health.status === 'degraded' ? 'border-yellow-500' : 'border-red-500'}`}>
              <div className="flex items-center justify-between">
                <div>
                  <h2 className="text-xl font-semibold">Overall Status</h2>
                  <p className="text-gray-400">Last checked: {new Date(health.timestamp).toLocaleString()}</p>
                </div>
                <span className={`${getStatusColor(health.status)} px-4 py-2 rounded-lg text-lg font-semibold uppercase`}>
                  {health.status}
                </span>
              </div>
            </div>

            {/* Component Details */}
            <div className="space-y-4">
              {Object.entries(health.components).map(([name, component]) => (
                <div key={name} className="card">
                  <div className="flex items-center justify-between mb-4">
                    <h3 className="text-lg font-semibold capitalize">{name.replace(/_/g, ' ')}</h3>
                    <span className={`${getStatusColor(component.status)} px-3 py-1 rounded text-sm`}>
                      {component.status}
                    </span>
                  </div>
                  <div className="grid grid-cols-2 gap-4 text-sm">
                    {Object.entries(component)
                      .filter(([key]) => key !== 'status')
                      .map(([key, value]) => (
                        <div key={key}>
                          <span className="text-gray-400">{key.replace(/_/g, ' ')}: </span>
                          <span className="font-mono">
                            {typeof value === 'boolean' ? (value ? 'Yes' : 'No') :
                             typeof value === 'object' ? JSON.stringify(value) :
                             String(value)}
                          </span>
                        </div>
                      ))}
                  </div>
                </div>
              ))}
            </div>
          </>
        )}

        {/* Quick Actions */}
        <div className="card mt-8">
          <h2 className="text-xl font-semibold mb-4">Quick Actions</h2>
          <div className="flex gap-4">
            <button
              onClick={() => window.location.reload()}
              className="bg-slate-600 hover:bg-slate-500 px-4 py-2 rounded"
            >
              Refresh
            </button>
            <a
              href={`${API_URL}/docs`}
              target="_blank"
              rel="noopener noreferrer"
              className="bg-slate-600 hover:bg-slate-500 px-4 py-2 rounded"
            >
              API Docs
            </a>
          </div>
        </div>
      </div>
    </main>
  )
}
