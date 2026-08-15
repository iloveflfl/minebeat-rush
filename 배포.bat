@echo off
chcp 65001 >nul
title MineBeat Rush - deploy to web
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\deploy_web.ps1" %1
echo.
pause
