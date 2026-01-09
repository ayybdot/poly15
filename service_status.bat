@echo off
echo PolyTrader Service Status:
echo ==========================
sc query PolyTrader-API | find "STATE"
sc query PolyTrader-Worker | find "STATE"
sc query PolyTrader-UI | find "STATE"
echo.
pause
