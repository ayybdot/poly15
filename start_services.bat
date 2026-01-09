@echo off
echo Starting PolyTrader services...
net start PolyTrader-API
timeout /t 5
net start PolyTrader-UI
echo.
echo API and UI services started.
echo Worker service requires manual start after configuring credentials:
echo   net start PolyTrader-Worker
pause
