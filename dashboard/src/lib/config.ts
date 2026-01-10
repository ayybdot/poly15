// Dashboard configuration
// This file centralizes the API URL configuration

const getApiUrl = (): string => {
  const envUrl = process.env.NEXT_PUBLIC_API_URL || ''
  
  // If empty or undefined, use localhost for local dev
  if (!envUrl) {
    return 'http://localhost:8000'
  }
  
  // Ensure the URL has a protocol prefix
  if (!envUrl.startsWith('http://') && !envUrl.startsWith('https://')) {
    return `http://${envUrl}`
  }
  
  return envUrl
}

export const API_URL = getApiUrl()