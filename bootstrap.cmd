@echo off
REM ===================================================================
REM  Minecraft 26.3 Fabric - Ein-Klick-Setup
REM
REM  Laedt das Setup-Script von GitHub Pages herunter und startet es.
REM  Danach ist alles automatisch: Fabric, Mods, getrennter Mods-Ordner.
REM
REM  Rechtsklick -> "Als Administrator ausfuehren" ist NICHT noetig.
REM ===================================================================
setlocal
title Minecraft 26.3 Fabric Setup
color 0B

echo.
echo   ============================================
echo      Minecraft 26.3 Fabric  -  Ein-Klick-Setup
echo   ============================================
echo.

REM Basis-URL der Website (GitHub Pages). Ganz unten anpassbar.
set "BASE=https://92mxs21.github.io/mc-fabric-26-3/"

echo   Lade Setup-Script herunter ...
echo   Quelle: %BASE%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$d=Join-Path $env:TEMP 'mc-fabric-bootstrap';" ^
  "New-Item -ItemType Directory -Force -Path $d | Out-Null;" ^
  "$o=Join-Path $d 'setup-fabric-client.ps1';" ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
  "try { Invoke-WebRequest '%BASE%setup-fabric-client.ps1' -OutFile $o -UseBasicParsing -TimeoutSec 120 } catch { Write-Host ('  FEHLER: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 };" ^
  "if (Test-Path $o) { Write-Host ('  OK: ' + [math]::Round((Get-Item $o).Length/1KB,1) + ' KB') -ForegroundColor Green; Write-Host ('  SHA256: ' + (Get-FileHash $o -Algorithm SHA256).Hash.ToLower()) -ForegroundColor DarkGray } else { Write-Host '  FEHLER: Datei nicht gefunden' -ForegroundColor Red; exit 1 };"

if errorlevel 1 (
    echo.
    echo   [FEHLER] Download fehlgeschlagen.
    echo   Pruefe deine Internetverbindung.
    pause
    exit /b 1
)

echo.
echo   Starte Setup ...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\mc-fabric-bootstrap\setup-fabric-client.ps1"
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo   ============================================
    echo      Fertig! Im Minecraft-Launcher das
    echo      Profil "fabric-loader-26.3" waehlen.
    echo   ============================================
) else (
    echo   [FEHLER] Setup endete mit Code %RC%.
)
echo.
pause
endlocal
