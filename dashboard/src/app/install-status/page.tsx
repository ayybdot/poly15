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
      const res = await fetch(`${API_URL}/v1/install/status`)
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
      const res = await fetch(`${API_URL}/v1/install/logs/tail?step=${step}&lines=200`)
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
          <Link href="/" className="text-blue-400 hover:text-blue-300">← Back to Dashboard</Link>
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
                    <code className="text-blue-400">{status.next_script}</code>
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
                            className="text-blue-400 hover:text-blue-300 text-sm"
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
