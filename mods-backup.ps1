<#
    mods-backup.ps1
    Sichert den Mods-Ordner in einen Zeitstempel-Ordner und macht ein Manifest mit Pruefsummen.

    Beispiele:
      .\mods-backup.ps1                                  # .minecraft\mods
      .\mods-backup.ps1 -ModsDir 'D:\Spiel\mods'         # anderer Ordner
      .\mods-backup.ps1 -ModsDir 'D:\Spiel\mods' -Prune 5  # nur die letzten 5 Backups behalten
#>
param(
    [string]$ModsDir = "$env:APPDATA\.minecraft\mods",
    [string]$BackupRoot = "$env:APPDATA\.minecraft\backups\mods",
    [int]$Prune = 0
)

$ErrorActionPreference = 'Stop'

# Pruefsumme ohne Get-FileHash.
# Grund: Ist PowerShell 7 installiert, steht dessen Modules-Ordner im
# PSModulePath vor dem von Windows PowerShell 5.1. Beim Autoloaden findet
# 5.1 dann das inkompatible Core-Modul und Get-FileHash fehlt komplett.
# [System.Security.Cryptography.SHA256] gehoert zum Framework und geht immer.
function Get-Sha256([string]$path, [int]$len = 64) {
    $algo = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $algo.ComputeHash([System.IO.File]::ReadAllBytes($path))
        $hex = -join ($bytes | ForEach-Object { $_.ToString('x2') })
        if ($hex.Length -gt $len) { return $hex.Substring(0, $len) }
        return $hex
    } finally {
        $algo.Dispose()
    }
}

if (-not (Test-Path $ModsDir)) {
    Write-Host "[FEHLER] Mods-Ordner nicht gefunden: $ModsDir" -ForegroundColor Red
    exit 1
}

# Zeitstempel fuer Dateinamen: keine Doppelpunkte, keine Leerzeichen
$stamp   = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$destDir = Join-Path $BackupRoot "mods-backup_$stamp"

Write-Host "Mods   : $ModsDir" -ForegroundColor DarkGray
Write-Host "Backup : $destDir" -ForegroundColor DarkGray
Write-Host ''

New-Item -ItemType Directory -Force -Path $destDir | Out-Null

# --- JARs kopieren ---
$jars = @(Get-ChildItem $ModsDir -Filter '*.jar' -File -ErrorAction SilentlyContinue)
$total = 0

foreach ($j in $jars) {
    Copy-Item $j.FullName (Join-Path $destDir $j.Name) -Force
    $total += $j.Length
}

# --- Manifest mit Pruefsummen, damit spaeter auffaellt falls sich was aendert ---
$manifest = Join-Path $destDir '_manifest.txt'
$lines = @(
    "# Mods-Backup vom $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "# Quelle: $ModsDir",
    "# Dateien: $($jars.Count)  Gesamt: $([math]::Round($total/1MB,2)) MB",
    ""
)
foreach ($j in ($jars | Sort-Object Name)) {
    $hash = Get-Sha256 $j.FullName 16
    $lines += ('{0}  {1}  {2} MB' -f $hash, $j.Name.PadRight(48), [math]::Round($j.Length/1MB,2))
}
$lines | Set-Content $manifest -Encoding UTF8

Write-Host ("[OK] {0} JARs gesichert ({1} MB)" -f $jars.Count, [math]::Round($total/1MB,2)) -ForegroundColor Green
Write-Host "[OK] Manifest: $manifest" -ForegroundColor Green

# --- Alte Backups aufraeumen ---
if ($Prune -gt 0) {
    $all = @(Get-ChildItem $BackupRoot -Directory -Filter 'mods-backup_*' -ErrorAction SilentlyContinue |
             Sort-Object Name -Descending)
    if ($all.Count -gt $Prune) {
        $old = $all[$Prune..($all.Count-1)]
        foreach ($o in $old) {
            Remove-Item $o.FullName -Recurse -Force
            Write-Host "[ALT] entfernt: $($o.Name)" -ForegroundColor DarkYellow
        }
    }
}

# --- Uebersicht ---
$all = @(Get-ChildItem $BackupRoot -Directory -Filter 'mods-backup_*' -ErrorAction SilentlyContinue |
         Sort-Object Name -Descending)
$size = [math]::Round((($all | ForEach-Object {
    (Get-ChildItem $_.FullName -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
} | Measure-Object -Sum).Sum)/1MB, 2)

Write-Host ''
Write-Host ("Backups gesamt: {0} ({1} MB)" -f $all.Count, $size) -ForegroundColor Cyan
$i = 0
foreach ($b in $all) {
    $i++
    $mark = if ($b.Name -eq "mods-backup_$stamp") { '  <-- neu' } else { '' }
    Write-Host ("  {0}. {1}{2}" -f $i, $b.Name, $mark) -ForegroundColor DarkGray
}
