@echo off
rem Double-click to install. Needs no admin rights.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
pause
