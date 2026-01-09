@echo off
cd /d "C:\Users\Administrator\Desktop\PolyTrader\backend"
set PYTHONPATH=C:\Users\Administrator\Desktop\PolyTrader\backend
"C:\Users\Administrator\Desktop\PolyTrader\venv\Scripts\python.exe" -m app.workers.trading_worker
