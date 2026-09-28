<#
    setup-fabric-client.ps1
    Vollautomatische Fabric-Installation fuer den OFFIZIELLEN Minecraft-Launcher.
    Keine GUI, kein Fabric-Installer-Fenster, alles headless.

    Ablauf:
      1. Minecraft-Launcher schliessen
      2. Mods-Ordner zeitgestempelt sichern
      3. Fabric Installer (CLI/headless) ausfuehren -> legt Profil im Launcher an
      4. Version-JSON patchen, damit 26.3 den eigenen Mods-Ordner nutzt
      5. Client-Mods aus Modrinth laden und verifizieren
      6. Optional: Minecraft mit dem Fabric-Profil starten

    Aufruf:
      .\setup-fabric-client.ps1
      .\setup-fabric-client.ps1 -Launch          # startet danach Minecraft
      .\setup-fabric-client.ps1 -Bootstrap <url>  # laedt sich selbst erst noch herunter
#>
param(
    [string]$MinecraftDir  = "$env:APPDATA\.minecraft",
    [string]$ModsFolder    = "mods26.3",
    [string]$MCVersion     = "26.3",
    [string]$Loader        = "0.19.5",
    [string]$BaseUrl       = "https://92mxs21.github.io/mc-fabric-26-3/",
    [switch]$LauncherOpen,
    [switch]$Launch,
    [string]$Bootstrap     = ""
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$SelfDir = $PSScriptRoot

# ---------------------------------------------------------------- Bootstrap
# Laedt das Skript erst herunter und startet es neu. Wird das Skript zuerst
# ohne Parameter aufgerufen (bootstrap.cmd), landet man hier.
if ($Bootstrap -ne "") {
    $name = [System.IO.Path]::GetFileName(([Uri]$Bootstrap).AbsolutePath)
    $cacheDir = Join-Path $env:TEMP 'mc-fabric-bootstrap'
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    $target = Join-Path $cacheDir $name

    Write-Host "Lade $name herunter ..." -ForegroundColor Cyan
    Write-Host "  von $Bootstrap" -ForegroundColor DarkGray
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest $Bootstrap -OutFile $target -TimeoutSec 300 -UseBasicParsing

    $len = (Get-Item $target).Length
    Write-Host "  $([math]::Round($len/1KB,1)) KB -> $target" -ForegroundColor Green

    $sha = 'n/a'
    try {
        # Ohne Get-FileHash, siehe Begruendung in mods-backup.ps1
        $algo = [System.Security.Cryptography.SHA256]::Create()
        try {
            $sha = (-join ($algo.ComputeHash([IO.File]::ReadAllBytes($target)) |
                       ForEach-Object { $_.ToString('x2') }))
        } finally { $algo.Dispose() }
    } catch { $sha = 'n/a' }
    Write-Host "  SHA256: $sha" -ForegroundColor DarkGray

    # Ausfuehren und alle Argumente durchreichen
    $rest = @()
    if ($LauncherOpen) { $rest += '-LauncherOpen' }
    if ($Launch)       { $rest += '-Launch' }
    $rest += @('-MinecraftDir', $MinecraftDir, '-ModsFolder', $ModsFolder,
               '-MCVersion', $MCVersion, '-Loader', $Loader, '-BaseUrl', $BaseUrl)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $target @rest
    exit $LASTEXITCODE
}

$CacheDir     = Join-Path $SelfDir 'cache'
$InstallerJar = Join-Path $CacheDir 'fabric-installer.jar'
$ModsPath     = Join-Path $MinecraftDir $ModsFolder
$BackupRoot   = Join-Path $MinecraftDir 'backups\mods'

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

# ---------------------------------------------------------------- Java finden
# Der Fabric Installer ist eine JAR und laeuft nur mit Java. Auf manchen PCs
# ist Java installiert, aber nicht im PATH - dann bricht "java -jar" mit
# CommandNotFound ab. Wir suchen deshalb an allen ueblichen Orten.
function Find-Java {
    $cands = New-Object System.Collections.Generic.List[string]

    $onPath = Get-Command 'java.exe' -ErrorAction SilentlyContinue
    if ($onPath) { $cands.Add($onPath.Source) }

    if ($env:JAVA_HOME) { $cands.Add((Join-Path $env:JAVA_HOME 'bin\java.exe')) }

    # Registry: HKLM\SOFTWARE\JavaSoft\JDK\<Version>
    foreach ($root in @('HKLM:\SOFTWARE\JavaSoft\JDK', 'HKLM:\SOFTWARE\JavaSoft\Java Development Kit')) {
        if (Test-Path $root) {
            Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
                $p = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).JavaHome
                if ($p) { $cands.Add((Join-Path $p 'bin\java.exe')) }
            }
        }
    }

    # Bekannte Installationsorte
    $globs = @(
        "$env:ProgramFiles\Eclipse Adoptium\jdk-*\bin\java.exe",
        "$env:ProgramFiles\Java\jdk-*\bin\java.exe",
        "$env:ProgramFiles\Microsoft\jdk-*\bin\java.exe",
        "$env:ProgramFiles\Zulu\zulu-*\bin\java.exe",
        "$env:ProgramFiles\Amazon Corretto\jdk*\bin\java.exe",
        "$env:LOCALAPPDATA\Programs\*jdk*\bin\java.exe",
        "$env:LOCALAPPDATA\Programs\Eclipse Adoptium\jdk-*\bin\java.exe",
        "$env:USERPROFILE\.jdks\jdk-*\bin\java.exe",
        "$env:USERPROFILE\scoop\apps\openjdk*\current\bin\java.exe"
    )
    foreach ($g in $globs) {
        Get-ChildItem $g -ErrorAction SilentlyContinue | ForEach-Object { $cands.Add($_.FullName) }
    }

    # Vom Minecraft-Launcher mitgebrachte Runtime
    foreach ($n in @('javaw.exe', 'java.exe')) {
        Get-ChildItem "$env:APPDATA\.minecraft\runtime" -Recurse -Filter $n -ErrorAction SilentlyContinue |
            ForEach-Object { $cands.Add($_.FullName) }
    }

    # Vorhandene pruefen, Version ermitteln, hoechste gewinnt
    $best = $null; $bestVer = $null
    foreach ($c in $cands) {
        if (-not $c) { continue }
        if (-not (Test-Path $c)) { continue }
        try {
            $info = & $c -version 2>&1 | Out-String
            if ($info -match 'version "([\d._]+)') {
                $raw = $Matches[1] -replace '_', '.'
                $ver = $null
                [version]::TryParse((($raw -split '-')[0]), [ref]$ver) | Out-Null
                if ($ver -and ($null -eq $bestVer -or $ver -gt $bestVer)) {
                    $bestVer = $ver; $best = $c
                }
            }
        } catch {
            # Kandidat ist keine ausfuehrbare Java-Version -> ueberspringen
        }
    }

    if ($best) { return [pscustomobject]@{ Path = $best; Version = $bestVer } }
    return $null
}

function Test-FileLocked([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    try {
        $s = [System.IO.File]::Open($path, 'Open', 'ReadWrite', 'None')
        $s.Close()
        return $false
    } catch { return $true }
}

# Wartet darauf, dass eine Datei wirklich frei ist. Windows gibt Dateisperren
# erst eine Weile nach dem Prozessende frei, ein fester Sleep reicht nicht.
function Wait-FileUnlocked([string]$path, [int]$maxSec = 30) {
    for ($i = 0; $i -lt $maxSec; $i++) {
        if (-not (Test-FileLocked $path)) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

# ---------------------------------------------------------------- 0. Java pruefen
Say "`n=== 0/5  Java suchen ===" 'Cyan'
$java = Find-Java
if (-not $java) {
    Say "  [FEHLER] Kein Java gefunden." 'Red'
    Say "  Der Fabric Installer ist eine JAR und braucht zwingend Java." 'DarkGray'
    Say "  Minecraft 26.3 verlangt Java 25." 'DarkGray'
    Say ""
    Say "  Installieren (kostenlos, ~180 MB):" 'White'
    Say "    https://adoptium.net/temurin/releases/?version=25" 'Cyan'
    Say ""
    Say "  Danach dieses Script erneut starten." 'DarkGray'
    exit 1
}
Say "  Gefunden: Java $($java.Version)" 'Green'
Say "  Pfad    : $($java.Path)" 'DarkGray'
# Fuer den Installer reicht Java 8+, das Spiel braucht 25 - nur kurz hinweisen
if ($java.Version -lt [version]'25.0') {
    Say "  Hinweis: Das Setup laeuft, aber Minecraft 26.3 braucht Java 25." 'Yellow'
    Say "  Der Launcher sucht sich seine Version meist selbst." 'DarkGray'
}

Say "`n=== 1/5  Minecraft-Launcher ===" 'Cyan'
$mc = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessName -eq 'Minecraft' -or $_.ProcessName -like 'MinecraftUWP*'
})
if ($mc.Count -gt 0 -and -not $LauncherOpen) {
    Say "  $($mc.Count) Launcher-Prozesse gefunden, schliesse sie..." 'Yellow'
    $mc | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
}
# Auf echtes Prozessende warten, nicht nur einen festen Sleep
for ($i = 0; $i -lt 30; $i++) {
    $left = @(Get-Process -Name 'Minecraft' -ErrorAction SilentlyContinue)
    if ($left.Count -eq 0) { break }
    Start-Sleep -Milliseconds 500
}
$still = @(Get-Process -Name 'Minecraft' -ErrorAction SilentlyContinue)
if ($still.Count -gt 0) {
    Say "  [FEHLER] Launcher laeuft noch. Bitte schliessen und neu ausfuehren (oder -LauncherOpen weglassen)." 'Red'
    exit 1
}
Say "  Launcher ist geschlossen." 'Green'

# Dateisperren abwarten - der Launcher haelt die Version-JARs sonst noch fest
$verJar = Join-Path $MinecraftDir "versions\fabric-loader-$Loader-$MCVersion\fabric-loader-$Loader-$MCVersion.jar"
if (Test-Path $verJar) {
    if (-not (Wait-FileUnlocked $verJar 30)) {
        Say "  [WARNUNG] $verJar ist noch gesperrt - Installation kann fehlschlagen." 'Yellow'
    }
}

if (-not (Test-Path $MinecraftDir)) { Say "  [FEHLER] $MinecraftDir nicht gefunden" 'Red'; exit 1 }
Say "  Minecraft-Ordner: $MinecraftDir" 'DarkGray'

# ---------------------------------------------------------------- 2. Backup
Say "`n=== 2/5  Backup ===" 'Cyan'
$backupScript = Join-Path $PSScriptRoot 'mods-backup.ps1'

# Beim Ein-Klick-Start liegt nur dieses eine Script im Temp-Ordner.
# mods-backup.ps1 dann nachladen, sonst waere das Backup still uebersprungen.
if (-not (Test-Path $backupScript) -and (Test-Path $ModsPath)) {
    try {
        Say "  Lade mods-backup.ps1 nach ..." 'DarkGray'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest ($BaseUrl + 'mods-backup.ps1') -OutFile $backupScript -UseBasicParsing -TimeoutSec 120
        Say "  nachgeladen." 'DarkGray'
    } catch {
        Say "  [WARNUNG] mods-backup.ps1 nicht ladbar - diesmal wird NICHT gesichert." 'Yellow'
        Say "  Backup spaeter nachholen mit:" 'DarkYellow'
        Say "    .\mods-backup.ps1 -ModsDir '$ModsPath'" 'DarkYellow'
    }
}

if (Test-Path $ModsPath) {
    if (Test-Path $backupScript) {
        # -Prune 5: jedes Backup sind ~38 MB, ohne Begrenzung wachsen die
        # Backups bei jedem Start um eine halbe Giga.
        & $backupScript -ModsDir $ModsPath -BackupRoot $BackupRoot -Prune 5 | Out-Null
        $kept = @(Get-ChildItem $BackupRoot -Directory -Filter 'mods-backup_*' -ErrorAction SilentlyContinue)
        $latest = $kept | Sort-Object Name -Descending | Select-Object -First 1
        if ($latest) { Say "  Gesichert nach: $($latest.Name)  (behalte die letzten $($kept.Count))" 'Green' }
    }
} else {
    Say "  '$ModsFolder' existiert noch nicht - nichts zu sichern." 'DarkGray'
}

# ---------------------------------------------------------------- 3. Installer + headless install
Say "`n=== 3/5  Fabric installieren (headless) ===" 'Cyan'
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

$installerUrl = "https://maven.fabricmc.net/net/fabricmc/fabric-installer/1.1.2/fabric-installer-1.1.2.jar"
if (-not (Test-Path $InstallerJar)) {
    Say "  Lade Fabric Installer herunter..." 'DarkGray'
    Invoke-WebRequest $installerUrl -OutFile $InstallerJar -TimeoutSec 300
}
Say "  Installer: $([math]::Round((Get-Item $InstallerJar).Length/1KB,1)) KB" 'DarkGray'

# Der Installer bietet zwei Modi, die sich NUR im Namen der Profildatei unterscheiden:
#   win32           -> launcher_profiles.json
#   microsoft_store -> launcher_profiles_microsoft_store.json
# Der Native-Launcher 2.6.2 legt aber nur launcher_profiles.json an, deshalb
# erkennen wir hier, welche Datei wirklich existiert.
$profilesFile = Join-Path $MinecraftDir 'launcher_profiles.json'
$storeFile    = Join-Path $MinecraftDir 'launcher_profiles_microsoft_store.json'

if (Test-Path $storeFile) { $LauncherType = 'microsoft_store' }
elseif (Test-Path $profilesFile) { $LauncherType = 'win32' }
else {
    Say "  [FEHLER] Keine launcher_profiles.json gefunden - Minecraft-Ordner falsch?" 'Red'
    exit 1
}
Say "  Launcher-Modus: $LauncherType" 'DarkGray'
Say "  Profildatei   : $((Split-Path $profilesFile -Leaf))" 'DarkGray'

# Profildatei vorher pruefen. Der Installer stirbt an Muell mit einem
# Java-Stacktrace ab, das hier niemandem hilft.
try {
    $null = Get-Content $profilesFile -Raw | ConvertFrom-Json
} catch {
    Say "  [FEHLER] launcher_profiles.json ist kein gueltiges JSON." 'Red'
    Say "  $($_.Exception.Message)" 'DarkGray'
    Say "  Meist hilft: Minecraft-Launcher einmal starten und schliessen," 'DarkGray'
    Say "  dann diese Datei loeschen - der Launcher legt sie neu an." 'DarkGray'
    exit 1
}

# Sicherheitsnetz: der Installer schreibt in die Profildatei
$profilesBackup = "$profilesFile.mcsetup-backup"
try {
    Copy-Item $profilesFile $profilesBackup -Force
    Say "  Profildatei gesichert: $((Split-Path $profilesBackup -Leaf))" 'DarkGray'
} catch {
    Say "  [WARNUNG] Profildatei nicht sicherbar: $($_.Exception.Message)" 'Yellow'
}

# Wichtig: nicht $args - das ist eine automatische PowerShell-Variable.
$javaArgs = @('-jar', $InstallerJar, 'client', '-dir', $MinecraftDir,
             '-launcher', $LauncherType, '-mcversion', $MCVersion, '-loader', $Loader)
Say "  > $($java.Path) $($javaArgs -join ' ')" 'DarkGray'

$installerOk = $false
for ($attempt = 1; $attempt -le 3 -and -not $installerOk; $attempt++) {
    if ($attempt -gt 1) {
        Say "  Wiederholung $attempt/3 ..." 'Yellow'
        # Aufloesen und neu auf FileHandles warten
        if (Test-Path $verJar) { [void](Wait-FileUnlocked $verJar 30) }
        Start-Sleep -Seconds 2
    }
    $out = & $java.Path @javaArgs 2>&1 | Out-String
    $out.TrimEnd() -split "`r?`n" | ForEach-Object { Say "    $_" 'DarkGray' }

    if ($LASTEXITCODE -eq 0) {
        $installerOk = $true
    } elseif ($out -match 'verwendet wird|being used by another process') {
        Say "  Datei ist noch gesperrt - warte auf Freigabe ..." 'Yellow'
        if (Test-Path $verJar) { [void](Wait-FileUnlocked $verJar 30) }
    } else {
        break   # anderer Fehler, nochmaliges Probieren bringt nichts
    }
}

if (-not $installerOk) {
    Say "  [FEHLER] Installer fehlgeschlagen (Exit $LASTEXITCODE)" 'Red'
    exit 1
}

# Pruefen, ob das Profil wirklich in der Profildatei gelandet ist.
# Ohne diesen Check waere ein stilles Scheitern moeglich und der Client
# zeigt das Profil im Dropdown nicht.
$profileName = "fabric-loader-$MCVersion"
$versionId  = "fabric-loader-$Loader-$MCVersion"
try {
    $pjson = Get-Content $profilesFile -Raw | ConvertFrom-Json
    $prof  = $pjson.profiles.$profileName
    # lastVersionId nur lesen wenn das Profil wirklich existiert, sonst
    # waere der Warnungs-Zweig selbst der Fehler.
    $actual = if ($prof) { $prof.lastVersionId } else { '<fehlt>' }
    if ($prof -and $actual -eq $versionId) {
        Say "  Profil '$profileName' -> $actual" 'Green'
    } else {
        Say "  [WARNUNG] Profil '$profileName' zeigt auf '$actual' statt '$versionId'." 'Yellow'
        Say "  Im Launcher trotzdem nach 'fabric-loader-$MCVersion' schauen." 'Yellow'
    }
} catch {
    Say "  [WARNUNG] $profilesFile nicht lesbar: $($_.Exception.Message)" 'Yellow'
}

# ---------------------------------------------------------------- 4. Version-JSON patchen
Say "`n=== 4/5  Mods-Ordner umbiegen auf '$ModsFolder' ===" 'Cyan'

$verDir = Get-ChildItem (Join-Path $MinecraftDir 'versions') -Directory -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -like "fabric-loader-$Loader-$MCVersion*" } |
          Sort-Object Name -Descending | Select-Object -First 1

if (-not $verDir) {
    Say "  [FEHLER] Fabric-Versionsordner nicht gefunden." 'Red'
    exit 1
}
Say "  Versionsordner: $($verDir.Name)" 'DarkGray'

$json = Get-ChildItem $verDir.FullName -Filter '*.json' |
        Where-Object { $_.Name -ne 'fabric_installer.json' } | Select-Object -First 1
if (-not $json) { Say "  [FEHLER] Versions-JSON nicht gefunden." 'Red'; exit 1 }
Say "  JSON: $($json.Name)" 'DarkGray'

$prop    = "-Dfabric.modsFolder=$ModsPath"
# WICHTIG: In JSON muessen Backslashes verdoppelt werden, sonst ist
# "C:\Users\..." ein ungueltiges Escape-Sequenz (\U) und die Datei ist kaputt.
$jsonProp = $prop -replace '\\', '\\\\'
$text = Get-Content $json.FullName -Raw

if ($text.Contains($jsonProp)) {
    Say "  Property ist schon gesetzt." 'DarkGray'
} else {
    # Rein mit String-Operationen, kein Regex (das liefert bei MatchEvaluator
    # zuverlaessig den falschen Text zurueck).
    $jvmIdx = $text.IndexOf('"jvm"')
    if ($jvmIdx -lt 0) {
        Say "  [WARNUNG] jvm-Array nicht gefunden - bitte manuell pruefen." 'Yellow'
    } else {
        $open = $text.IndexOf('[', $jvmIdx)
        if ($open -lt 0) {
            Say "  [WARNUNG] Kein '[' nach 'jvm' - bitte manuell pruefen." 'Yellow'
        } else {
            # Ist das Array leer? Dann kein Komma noetig.
            $rest = $text.Substring($open + 1).TrimStart()
            $isEmpty = $rest.StartsWith(']')
            $entry = "`n        `"$jsonProp`""
            if (-not $isEmpty) { $entry += ',' }

            $new = $text.Substring(0, $open + 1) + $entry + $text.Substring($open + 1)
            [System.IO.File]::WriteAllText($json.FullName, $new, (New-Object System.Text.UTF8Encoding($false)))
            Say "  Gesetzt: $prop" 'Green'
        }
    }
}

# JSON nochmal pruefen - ein kaputtes Argument-Array wuerde den Start verhindern
try {
    $check = Get-Content $json.FullName -Raw | ConvertFrom-Json
    $jvmCount = @($check.arguments.jvm).Count
    Say "  JSON validiert, arguments.jvm hat $jvmCount Eintraege." 'Green'
} catch {
    Say "  [FEHLER] JSON ist ungueltig: $($_.Exception.Message)" 'Red'
    exit 1
}
Say "  -> 26.3 nutzt jetzt: $ModsPath" 'Green'
Say "  -> Vanilla-26.3 nutzt weiter: $(Join-Path $MinecraftDir 'mods')" 'DarkGray'

# ---------------------------------------------------------------- 5. Mods laden
Say "`n=== 5/5  Client-Mods laden ===" 'Cyan'
New-Item -ItemType Directory -Force -Path $ModsPath | Out-Null

$Mods = [ordered]@{
    'fabric-api'        = 'Fabric API'
    'dreamdisplays'     = 'Dream Displays'
    'simple-voice-chat' = 'Simple Voice Chat'
    'sodium'            = 'Sodium'
    'iris'              = 'Iris Shaders'
    'sodium-extra'      = 'Sodium Extra'
}
$hdr = @{ 'User-Agent' = 'mc-fabric-setup/1.0 (local)' }
$dlOk = 0; $dlBad = 0

foreach ($slug in $Mods.Keys) {
    $name = $Mods[$slug]
    try {
        $q = "https://api.modrinth.com/v2/project/$slug/version" +
             "?game_versions=%5B%22$MCVersion%22%5D&loaders=%5B%22fabric%22%5D"
        $versions = Invoke-RestMethod $q -Headers $hdr -TimeoutSec 60
        if (-not $versions -or $versions.Count -eq 0) {
            Say ("  [SKIP] {0,-18} keine {1}/fabric-Version" -f $name, $MCVersion) 'Yellow'
            $dlBad++
            continue
        }
        $file = $versions[0].files | Where-Object { $_.primary } | Select-Object -First 1
        if (-not $file) { $file = $versions[0].files[0] }

        $dest = Join-Path $ModsPath $file.filename
        if (Test-Path $dest) {
            Say ("  [OK  ] {0,-18} {1} (bereits da)" -f $name, $file.filename) 'DarkGray'
        } else {
            Invoke-WebRequest $file.url -OutFile $dest -Headers $hdr -TimeoutSec 300
            Say ("  [DL  ] {0,-18} {1} ({2} MB)" -f $name, $file.filename, [math]::Round((Get-Item $dest).Length/1MB,2)) 'Green'
        }
        $dlOk++
    } catch {
        Say ("  [FAIL] {0,-18} {1}" -f $name, $_.Exception.Message) 'Red'
        $dlBad++
    }
}

# --- Jedes JAR selbst fragen, welche MC-Version es wirklich unterstuetzt ---
Say "  Pruefe Mod-Metadaten ..." 'DarkGray'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$verOk = 0; $verBad = @(); $verUnrestricted = 0
foreach ($j in @(Get-ChildItem $ModsPath -Filter '*.jar' -ErrorAction SilentlyContinue)) {
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($j.FullName)
        $e = $zip.Entries | Where-Object { $_.FullName -eq 'fabric.mod.json' } | Select-Object -First 1
        if (-not $e) { $zip.Dispose(); continue }
        $sr = [System.IO.StreamReader]::new($e.Open())
        $meta = $sr.ReadToEnd() | ConvertFrom-Json
        $sr.Close(); $zip.Dispose()

        $mvn = @($meta.depends.minecraft)[0]
        # Kein "minecraft"-Eintrag heisst: das Mod schraenkt die Version nicht ein.
        # Das ist normal (z.B. Iris) und kein Fehler.
        if (-not $mvn) {
            $verUnrestricted++
        } elseif ($mvn -match '26\.3') {
            $verOk++
        } else {
            $verBad += "$($meta.id) ($mvn)"
        }
    } catch {
        $verBad += "$($j.Name) (unlesbar)"
    }
}
if ($verBad.Count -eq 0) {
    $extra = ''
    if ($verUnrestricted -gt 0) { $extra = ", $verUnrestricted ohne Versions-Einschraenkung" }
    Say "  [OK  ] $verOk Mods unterstuetzen $MCVersion$extra" 'Green'
} else {
    Say ("  [ACHTUNG] {0} Mod(s) nennen kein 26.3: {1}" -f $verBad.Count, ($verBad -join ', ')) 'Yellow'
}

# ---------------------------------------------------------------- 6. Start
if ($Launch) {
    Say "`n=== 6/6  Minecraft starten ===" 'Cyan'
    # Wichtig: Der Ordnername in WindowsApps enthaelt die Versionsnummer
    # (Microsoft.MinecraftUWP_1.26.5203.0_x64__8wekyb3d8bbwe), die sich aendert.
    # Deshalb nicht auf den Ordnernamen globben, sondern das Paket abfragen.
    $exe = $null
    try {
        $pkg = Get-AppxPackage -Name 'Microsoft.MinecraftUWP' -ErrorAction Stop |
               Sort-Object Version -Descending | Select-Object -First 1
        if ($pkg) {
            $candidate = Join-Path $pkg.InstallLocation 'Minecraft.exe'
            if (Test-Path $candidate) { $exe = $candidate }
        }
    } catch {
        Say "  Get-AppxPackage fehlgeschlagen: $($_.Exception.Message)" 'DarkGray'
    }
    # Fallback: Start-AppsFolder-URI
    if (-not $exe) {
        try {
            Start-Process 'shell:AppsFolder\Microsoft.MinecraftUWP_8wekyb3d8bbwe!App'
            Say "  Launcher ueber AppsFolder gestartet." 'Green'
            Say "  Waehle das Profil 'fabric-loader-$MCVersion'." 'Yellow'
            $exe = 'shell:AppsFolder'
        } catch {
            Say "  [WARNUNG] Minecraft konnte nicht gestartet werden." 'Yellow'
        }
    }
    if ($exe -and $exe -ne 'shell:AppsFolder') {
        Say "  Starte: $exe" 'DarkGray'
        Say "  Waehle im Launcher das Profil 'fabric-loader-$MCVersion'." 'Yellow'
        Start-Process -FilePath $exe
    }
}

# ---------------------------------------------------------------- Fertig
Say "`n=== Fertig ===" 'Cyan'
$jars = @(Get-ChildItem $ModsPath -Filter '*.jar' -ErrorAction SilentlyContinue)
Say "  Mods-Ordner : $ModsPath  ($($jars.Count) JARs)" 'White'
Say "  Version     : Fabric Loader $Loader fuer Minecraft $MCVersion" 'White'
if ($dlBad -gt 0) { Say "  Hinweis     : $dlBad Mod(s) konnten nicht geladen werden" 'Yellow' }
Say ""
Say "  Naechster Schritt: Minecraft-Launcher oeffnen, im Profil-Dropdown" 'White'
Say "  'fabric-loader-$Loader-$MCVersion' waehlen und starten." 'White'
Say ""
Say "  Backup-Ordner: $BackupRoot" 'DarkGray'
