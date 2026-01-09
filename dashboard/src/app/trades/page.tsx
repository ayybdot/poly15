'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'

interface Order {
  order_id: string
  market_id: number
  side: string
  token_id: string
  price: number
  size: number
  filled_size: number
  status: string
  created_at: string
  filled_at: string | null
}

export default function TradesPage() {
  const [orders, setOrders] = useState<Order[]>([])
  const [loading, setLoading] = useState(true)

  const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000'

  useEffect(() => {
    const fetchOrders = async () => {
      try {
        const res = await fetch(`${API_URL}/v1/trading/orders?limit=100`)
        if (res.ok) {
          const data = await res.json()
          setOrders(data.orders || [])
        }
      } catch (error) {
        console.error('Failed to fetch orders:', error)
      } finally {
        setLoading(false)
      }
    }

    fetchOrders()
    const interval = setInterval(fetchOrders, 10000)
    return () => clearInterval(interval)
  }, [API_URL])

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'filled': return 'bg-green-500'
      case 'open': return 'bg-blue-500'
      case 'cancelled': return 'bg-gray-500'
      case 'rejected': return 'bg-red-500'
      default: return 'bg-yellow-500'
    }
  }

  if (loading) {
    return <div className="min-h-screen p-8 flex items-center justify-center">Loading...</div>
  }

  return (
    <main className="min-h-screen p-8">
      <div className="max-w-7xl mx-auto">
        <div className="flex justify-between items-center mb-8">
          <h1 className="text-3xl font-bold">Trades & Orders</h1>
          <Link href="/" className="text-primary-400 hover:text-primary-300">← Back to Dashboard</Link>
        </div>

        <div className="card overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="border-b border-slate-700">
                <th className="text-left p-3">Order ID</th>
                <th className="text-left p-3">Side</th>
                <th className="text-left p-3">Price</th>
                <th className="text-left p-3">Size</th>
                <th className="text-left p-3">Filled</th>
                <th className="text-left p-3">Status</th>
                <th className="text-left p-3">Time</th>
              </tr>
            </thead>
            <tbody>
              {orders.length === 0 ? (
                <tr>
                  <td colSpan={7} className="p-8 text-center text-gray-400">
                    No orders yet
                  </td>
                </tr>
              ) : (
                orders.map(order => (
                  <tr key={order.order_id} className="border-b border-slate-700/50 hover:bg-slate-700/30">
                    <td className="p-3 font-mono text-sm">{order.order_id.slice(0, 8)}...</td>
                    <td className="p-3">
                      <span className={`px-2 py-1 rounded text-xs ${order.side === 'BUY' ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'}`}>
                        {order.side}
                      </span>
                    </td>
                    <td className="p-3">${order.price.toFixed(4)}</td>
                    <td className="p-3">{order.size.toFixed(2)}</td>
                    <td className="p-3">{order.filled_size.toFixed(2)}</td>
                    <td className="p-3">
                      <span className={`${getStatusColor(order.status)} px-2 py-1 rounded text-xs`}>
                        {order.status}
                      </span>
                    </td>
                    <td className="p-3 text-sm text-gray-400">
                      {new Date(order.created_at).toLocaleString()}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </main>
  )
}
