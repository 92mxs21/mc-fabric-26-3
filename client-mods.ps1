<#
    client-mods.ps1
    Laedt die 3 Client-Mods fuer Freunde direkt in .minecraft\mods
    Aufruf:  .\client-mods.ps1
#>

$ErrorActionPreference = 'Stop'

$MCVersion = '26.3'
$Loader    = 'fabric'

$Mods = [ordered]@{
    'fabric-api'         = 'Fabric API'
    'dreamdisplays'      = 'Dream Displays'
    'simple-voice-chat'  = 'Simple Voice Chat'
}

$ModsDir = Join-Path $env:APPDATA '.minecraft\mods'
New-Item -ItemType Directory -Force -Path $ModsDir | Out-Null

$hdr = @{ 'User-Agent' = 'mc-server-setup/1.0 (local)' }

Write-Host "Zielordner: $ModsDir" -ForegroundColor Cyan
Write-Host ''

foreach ($slug in $Mods.Keys) {
    $name = $Mods[$slug]
    try {
        $q = "https://api.modrinth.com/v2/project/$slug/version" +
             "?game_versions=%5B%22$MCVersion%22%5D&loaders=%5B%22$Loader%22%5D"
        $versions = Invoke-RestMethod $q -Headers $hdr -TimeoutSec 60

        if (-not $versions -or $versions.Count -eq 0) {
            Write-Host ("[SKIP] {0,-18} keine {1}/{2} Version" -f $name, $MCVersion, $Loader) -ForegroundColor Yellow
            continue
        }

        $file = $versions[0].files | Where-Object { $_.primary } | Select-Object -First 1
        if (-not $file) { $file = $versions[0].files[0] }

        $dest = Join-Path $ModsDir $file.filename
        if (Test-Path $dest) {
            Write-Host ("[OK  ] {0,-18} {1} (bereits da)" -f $name, $file.filename) -ForegroundColor DarkGray
            continue
        }

        Invoke-WebRequest $file.url -OutFile $dest -Headers $hdr -TimeoutSec 300
        Write-Host ("[DL  ] {0,-18} {1} ({2} KB)" -f $name, $file.filename, [math]::Round((Get-Item $dest).Length/1KB,1)) -ForegroundColor Green
    }
    catch {
        Write-Host ("[FAIL] {0,-18} {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host "Fertig. In Minecraft: Fabric-Profil mit diesen Mods starten." -ForegroundColor Cyan
Write-Host "Bei Voice-Chat-Problemen: Mikrofon-Adresse = della-otis.tun.ply.gg:4243" -ForegroundColor DarkGray
