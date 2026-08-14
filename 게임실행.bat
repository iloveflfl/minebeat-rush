@echo off
chcp 65001 >nul
title MineBeat Rush - Desert Bridge
cd /d "%~dp0"
start "" "S:\GameDev\Godot\Godot_v4.7-stable_win64.exe" --path "%~dp0."
exit
