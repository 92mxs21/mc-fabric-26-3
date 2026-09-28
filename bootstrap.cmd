@echo off
REM ===================================================================
REM  Minecraft 26.3 Fabric - Ein-Klick-Setup
REM
REM  Laedt das Setup-Script von GitHub Pages herunter und startet es.
REM  Danach laeuft alles automatisch: Fabric, Mods, getrennter Mods-Ordner.
REM
REM  Rechtsklick -> "Als Administrator ausfuehren" ist NICHT noetig.
REM ===================================================================
setlocal EnableDelayedExpansion
title Minecraft 26.3 Fabric Setup
color 0B

REM Basis-URL der Website (GitHub Pages).
set "BASE=https://92mxs21.github.io/mc-fabric-26-3/"
set "SCRIPT=setup-fabric-client.ps1"
set "AUX=mods-backup.ps1"
set "DIR=%TEMP%\mc-fabric-bootstrap"
set "PS1=%DIR%\%SCRIPT%"

echo.
echo   ============================================
echo      Minecraft 26.3 Fabric  -  Ein-Klick-Setup
echo   ============================================
echo.
echo   Quelle: %BASE%
echo.

if not exist "%DIR%" mkdir "%DIR%" >nul 2>&1

REM --- Download mit curl.exe (ab Windows 10 1803 immer dabei) ---
echo   Lade %SCRIPT% herunter ...
curl.exe -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 -o "%PS1%" "%BASE%%SCRIPT%"
if errorlevel 1 (
    echo.
    echo   [FEHLER] Download fehlgeschlagen.
    echo   Pruefe deine Internetverbindung.
    goto :fail
)

if not exist "%PS1%" (
    echo.
    echo   [FEHLER] Script wurde nicht gespeichert.
    goto :fail
)

REM --- Backup-Script mitnehmen (optional, das Hauptscript laedt es notfalls nach) ---
curl.exe -fsSL --retry 2 --connect-timeout 15 -o "%DIR%\%AUX%" "%BASE%%AUX%" >nul 2>&1
if exist "%DIR%\%AUX%" (echo   Lade %AUX% mit ...) else (echo   %AUX% nicht verfuegbar - wird nachgeladen)

REM --- Groesse + Pruefsumme, ohne Abhaengigkeit von Get-FileHash ---
REM     [System.Security.Cryptography.SHA256] ist immer da, das Cmdlet nicht
REM     zuverlaessig - und ein Fehler hier darf den Ablauf nicht abbrechen.
for /f "usebackq delims=" %%H in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { $h=[System.Security.Cryptography.SHA256]::Create(); $s=$h.ComputeHash([IO.File]::ReadAllBytes('%PS1%')); ($s | ForEach-Object { $_.ToString('x2') }) -join '' } catch { 'n/a' }"`) do set "SHA=%%H"

echo   OK: %PS1%
for %%F in ("%PS1%") do echo   Groesse: %%~zF Bytes
echo   SHA256: !SHA!
echo.

REM --- Setup starten ---
echo   Starte Setup ...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo   ============================================
    echo      Fertig!
    echo      Im Minecraft-Launcher das Profil
    echo      "fabric-loader-26.3" waehlen und starten.
    echo   ============================================
    echo.
    pause
    endlocal
    exit /b 0
)

echo   [FEHLER] Setup endete mit Code %RC%.
echo   Schick die Meldung oben im Log weiter, falls es haengt.
echo.
pause
endlocal
exit /b %RC%

:fail
echo.
pause
endlocal
exit /b 1
