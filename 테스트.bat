@echo off
chcp 65001 >nul
title MineBeat Rush - tests
cd /d "%~dp0"
"S:\GameDev\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "%~dp0." --script res://tests/run_tests.gd
echo.
pause
