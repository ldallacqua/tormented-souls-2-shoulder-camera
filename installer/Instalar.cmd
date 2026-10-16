@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Gerenciar-Mod.ps1" -Acao Instalar -Pasta "%~1"
pause
