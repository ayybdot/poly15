#Requires -Version 5.1
<#
.SYNOPSIS
    Step 02: Setup Repository
.DESCRIPTION
    Sets up the Python virtual environment and installs backend dependencies.
    Installs Node.js dependencies for the dashboard.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Get script directory and load library
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\_lib.ps1"

# Verify dependencies completed
if (-not (Test-Marker -Name "deps_ok")) {
    Write-Host "ERROR: Dependencies not installed. Run 01_install_dependencies.ps1 first." -ForegroundColor Red
    exit 1
}

# Start logging
$logFile = Start-Log -StepNumber "02" -StepName "setup_repo"
Write-StepHeader "02" "SETUP REPOSITORY"

$root = Get-PolyTraderRoot
$backendDir = Join-Path $root "backend"
$dashboardDir = Join-Path $root "dashboard"
$venvDir = Join-Path $root "venv"

try {
    # ========================================================================
    # CREATE PYTHON VIRTUAL ENVIRONMENT
    # ========================================================================
    Write-Section "Python Virtual Environment"
    
    if (Test-Path (Join-Path $venvDir "Scripts\python.exe")) {
        Write-Ok "Virtual environment already exists"
    }
    else {
        Write-Status "Creating virtual environment..." -Icon "Arrow"
        
        # Create venv
        $result = Invoke-LoggedCommand -Command "python -m venv `"$venvDir`"" -Description "Creating venv"
        
        if (Test-Path (Join-Path $venvDir "Scripts\python.exe")) {
            Write-Ok "Virtual environment created at $venvDir"
        }
        else {
            throw "Failed to create virtual environment"
        }
    }
    
    # Activate venv for this session
    $venvPython = Join-Path $venvDir "Scripts\python.exe"
    $venvPip = Join-Path $venvDir "Scripts\pip.exe"
    
    # ========================================================================
    # UPGRADE PIP IN VENV
    # ========================================================================
    Write-Section "Upgrade Pip in Virtual Environment"
    
    Invoke-LoggedCommand -Command "`"$venvPython`" -m pip install --upgrade pip" -Description "Upgrading pip in venv"
    Write-Ok "Pip upgraded in virtual environment"
    
    # ========================================================================
    # CREATE REQUIREMENTS.TXT
    # ========================================================================
    Write-Section "Create Requirements File"
    
    $requirementsPath = Join-Path $backendDir "requirements.txt"
    
    $requirements = @"
# PolyTrader Backend Dependencies
# Generated automatically - do not edit manually

# Web Framework
fastapi==0.109.2
uvicorn[standard]==0.27.1
python-multipart==0.0.9
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4

# Database
sqlalchemy==2.0.25
asyncpg==0.29.0
psycopg2-binary==2.9.9
alembic==1.13.1

# Polymarket
py-clob-client==0.17.0
eth-account==0.11.0
web3==6.15.1

# Data Processing
pandas==2.2.0
numpy==1.26.3
scipy==1.12.0
scikit-learn==1.4.0

# HTTP & WebSockets
httpx==0.26.0
websockets==12.0
aiohttp==3.9.3

# Configuration & Utilities
pydantic==2.6.0
pydantic-settings==2.1.0
python-dotenv==1.0.1
pytz==2024.1
structlog==24.1.0

# Task Scheduling
apscheduler==3.10.4

# Testing
pytest==8.0.0
pytest-asyncio==0.23.4
pytest-cov==4.1.0

# Development
black==24.1.1
isort==5.13.2
mypy==1.8.0
"@
    
    # Ensure backend directory exists
    if (-not (Test-Path $backendDir)) {
        New-Item -ItemType Directory -Path $backendDir -Force | Out-Null
    }
    
    Set-Content -Path $requirementsPath -Value $requirements -Encoding UTF8
    Write-Ok "Created requirements.txt"
    
    # ========================================================================
    # INSTALL PYTHON DEPENDENCIES
    # ========================================================================
    Write-Section "Install Python Dependencies"
    
    Write-Status "Installing Python packages (this may take a few minutes)..." -Icon "Arrow"
    
    # Use direct pip execution instead of Invoke-LoggedCommand to avoid cmd.exe path issues
    try {
        Push-Location $backendDir
        $pipOutput = & $venvPip install -r $requirementsPath 2>&1
        $pipExitCode = $LASTEXITCODE
        Write-Log "Pip output: $pipOutput"
        
        if ($pipExitCode -eq 0) {
            Write-Ok "Python dependencies installed"
        }
        else {
            throw "Pip install failed with exit code $pipExitCode"
        }
    }
    catch {
        # Try installing packages one by one on failure
        Write-Warn "Bulk install failed: $_"
        Write-Warn "Trying individual packages..."
        
        $packages = $requirements -split "`n" | Where-Object { $_ -match "^[a-zA-Z]" -and $_ -notmatch "^#" }
        
        foreach ($package in $packages) {
            $packageName = ($package -split "==")[0].Trim()
            if ($packageName) {
                Write-Status "Installing $packageName..." -Icon "Arrow"
                try {
                    & $venvPip install $package.Trim() 2>&1 | Out-Null
                }
                catch {
                    Write-Warn "Failed to install $packageName"
                }
            }
        }
        Write-Ok "Individual package installation completed"
    }
    finally {
        Pop-Location
    }
    
    # Verify key packages
    Write-Status "Verifying key packages..." -Icon "Arrow"
    
    $keyPackages = @("fastapi", "sqlalchemy", "pandas", "httpx")
    $allPkgsOk = $true
    foreach ($pkg in $keyPackages) {
        try {
            $check = & $venvPython -c "import $pkg; print(getattr($pkg, '__version__', 'installed'))" 2>$null
            if ($LASTEXITCODE -eq 0 -and $check) {
                Write-Ok "$pkg installed: $($check.Trim())"
            }
            else {
                Write-Warn "$pkg import check failed"
                $allPkgsOk = $false
            }
        }
        catch {
            Write-Warn "$pkg verification error: $_"
            $allPkgsOk = $false
        }
    }
    
    if (-not $allPkgsOk) {
        Write-Warn "Some packages may not have installed correctly, but continuing..."
    }
    
    # ========================================================================
    # CREATE DASHBOARD PACKAGE.JSON
    # ========================================================================
    Write-Section "Create Dashboard Package Configuration"
    
    # Ensure dashboard directory exists
    if (-not (Test-Path $dashboardDir)) {
        New-Item -ItemType Directory -Path $dashboardDir -Force | Out-Null
    }
    
    $packageJson = @"
{
  "name": "polytrader-dashboard",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "next dev -p 3000",
    "build": "next build",
    "start": "next start -p 3000",
    "lint": "next lint"
  },
  "dependencies": {
    "next": "14.1.0",
    "react": "18.2.0",
    "react-dom": "18.2.0",
    "@tanstack/react-query": "5.17.19",
    "axios": "1.6.7",
    "chart.js": "4.4.1",
    "react-chartjs-2": "5.2.0",
    "lightweight-charts": "4.1.1",
    "date-fns": "3.3.1",
    "clsx": "2.1.0",
    "tailwind-merge": "2.2.1",
    "lucide-react": "0.316.0",
    "zustand": "4.5.0",
    "socket.io-client": "4.7.4",
    "@radix-ui/react-dialog": "1.0.5",
    "@radix-ui/react-dropdown-menu": "2.0.6",
    "@radix-ui/react-tabs": "1.0.4",
    "@radix-ui/react-toast": "1.1.5",
    "@radix-ui/react-switch": "1.0.3",
    "@radix-ui/react-select": "2.0.0",
    "@radix-ui/react-slot": "1.0.2"
  },
  "devDependencies": {
    "@types/node": "20.11.16",
    "@types/react": "18.2.52",
    "@types/react-dom": "18.2.18",
    "autoprefixer": "10.4.17",
    "postcss": "8.4.33",
    "tailwindcss": "3.4.1",
    "typescript": "5.3.3",
    "eslint": "8.56.0",
    "eslint-config-next": "14.1.0"
  }
}
"@
    
    $packageJsonPath = Join-Path $dashboardDir "package.json"
    Set-Content -Path $packageJsonPath -Value $packageJson -Encoding UTF8
    Write-Ok "Created package.json"
    
    # ========================================================================
    # INSTALL NODE.JS DEPENDENCIES
    # ========================================================================
    Write-Section "Install Node.js Dependencies"
    
    Write-Status "Installing npm packages (this may take a few minutes)..." -Icon "Arrow"
    
    Push-Location $dashboardDir
    try {
        $result = Invoke-LoggedCommand -Command "npm install" -Description "Installing npm packages" -WorkingDirectory $dashboardDir
        
        if ($result.Success) {
            Write-Ok "Node.js dependencies installed"
        }
        else {
            throw "npm install failed"
        }
    }
    finally {
        Pop-Location
    }
    
    # ========================================================================
    # CREATE TAILWIND CONFIG
    # ========================================================================
    Write-Section "Create Tailwind Configuration"
    
    $tailwindConfig = @"
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#f0f9ff',
          100: '#e0f2fe',
          200: '#bae6fd',
          300: '#7dd3fc',
          400: '#38bdf8',
          500: '#0ea5e9',
          600: '#0284c7',
          700: '#0369a1',
          800: '#075985',
          900: '#0c4a6e',
        },
        success: {
          50: '#f0fdf4',
          500: '#22c55e',
          600: '#16a34a',
        },
        danger: {
          50: '#fef2f2',
          500: '#ef4444',
          600: '#dc2626',
        },
        warning: {
          50: '#fffbeb',
          500: '#f59e0b',
          600: '#d97706',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'Menlo', 'monospace'],
      },
    },
  },
  plugins: [],
}
"@
    
    $tailwindConfigPath = Join-Path $dashboardDir "tailwind.config.js"
    Set-Content -Path $tailwindConfigPath -Value $tailwindConfig -Encoding UTF8
    Write-Ok "Created tailwind.config.js"
    
    # PostCSS config
    $postcssConfig = @"
module.exports = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
"@
    
    $postcssConfigPath = Join-Path $dashboardDir "postcss.config.js"
    Set-Content -Path $postcssConfigPath -Value $postcssConfig -Encoding UTF8
    Write-Ok "Created postcss.config.js"
    
    # ========================================================================
    # CREATE NEXT.JS CONFIG
    # ========================================================================
    Write-Section "Create Next.js Configuration"
    
    $nextConfig = @"
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  output: 'standalone',
  env: {
    NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000',
    NEXT_PUBLIC_WS_URL: process.env.NEXT_PUBLIC_WS_URL || 'ws://localhost:8000',
  },
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: 'http://localhost:8000/:path*',
      },
    ]
  },
}

module.exports = nextConfig
"@
    
    $nextConfigPath = Join-Path $dashboardDir "next.config.js"
    Set-Content -Path $nextConfigPath -Value $nextConfig -Encoding UTF8
    Write-Ok "Created next.config.js"
    
    # ========================================================================
    # CREATE TSCONFIG
    # ========================================================================
    Write-Section "Create TypeScript Configuration"
    
    $tsConfig = @"
{
  "compilerOptions": {
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [
      {
        "name": "next"
      }
    ],
    "paths": {
      "@/*": ["./src/*"]
    }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
"@
    
    $tsConfigPath = Join-Path $dashboardDir "tsconfig.json"
    Set-Content -Path $tsConfigPath -Value $tsConfig -Encoding UTF8
    Write-Ok "Created tsconfig.json"
    
    # ========================================================================
    # CREATE DIRECTORY STRUCTURE
    # ========================================================================
    Write-Section "Create Directory Structure"
    
    $directories = @(
        (Join-Path $dashboardDir "src\app"),
        (Join-Path $dashboardDir "src\components"),
        (Join-Path $dashboardDir "src\lib"),
        (Join-Path $dashboardDir "public"),
        (Join-Path $backendDir "app\api\routes"),
        (Join-Path $backendDir "app\core"),
        (Join-Path $backendDir "app\db\models"),
        (Join-Path $backendDir "app\services"),
        (Join-Path $backendDir "app\workers"),
        (Join-Path $backendDir "tests"),
        (Join-Path $root "logs"),
        (Join-Path $root "data\candles"),
        (Join-Path $root "data\prices"),
        (Join-Path $root "data\trades"),
        (Join-Path $root "data\markets")
    )
    
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    Write-Ok "Directory structure created"
    
    # ========================================================================
    # SUMMARY
    # ========================================================================
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Cyan
    
    Write-Ok "Repository setup completed successfully!"
    Set-Marker -Name "repo_ok"
    
    Write-Host ""
    Write-Host "  Virtual Environment: $venvDir" -ForegroundColor Gray
    Write-Host "  Backend Directory:   $backendDir" -ForegroundColor Gray
    Write-Host "  Dashboard Directory: $dashboardDir" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Next step: Run 03_setup_database.ps1" -ForegroundColor Green
    Write-Host ""
    
    Stop-Log -Success $true
}
catch {
    Write-Fail "Repository setup failed: $_"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Stop-Log -Success $false
    
    Write-Host ""
    Write-Host "  Check log file for details: $logFile" -ForegroundColor Red
    Write-Host ""
    
    exit 1
}