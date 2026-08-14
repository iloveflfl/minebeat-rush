@echo off
chcp 65001 >nul
title MineBeat Rush - Godot Editor
cd /d "%~dp0"
start "" "S:\GameDev\Godot\Godot_v4.7-stable_win64.exe" --editor --path "%~dp0."
exit
