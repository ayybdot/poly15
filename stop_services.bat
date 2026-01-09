@echo off
echo Stopping PolyTrader services...
net stop PolyTrader-Worker 2>nul
net stop PolyTrader-UI
net stop PolyTrader-API
echo Services stopped.
pause
