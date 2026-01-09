@echo off
cd /d "C:\Users\Administrator\Desktop\PolyTrader\backend"
set PYTHONPATH=C:\Users\Administrator\Desktop\PolyTrader\backend
"C:\Users\Administrator\Desktop\PolyTrader\venv\Scripts\python.exe" -m uvicorn app.main:app --host 0.0.0.0 --port 8000
