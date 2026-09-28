# Server

Der Minecraft-26.3-Fabric-Server. Alles laeuft aus `start.bat` in diesem Ordner.

## Starten

```
start.bat            normal, mit sichtbarem Fenster, "stop" zum Beenden
```

oder im Hintergrund mit Log:

```powershell
.\start-bg.ps1
Get-Content .\logs\console.log -Wait     # Live-Log
```

Kommandos an den laufenden Server schicken:

```powershell
Add-Content .\logs\cmd.txt "gamemode creative @a"
Add-Content .\logs\cmd.txt "stop"
```

## Ports

| | |
|---|---|
| Spiel | TCP 25565 |
| Voice Chat | UDP 24454 (playit `della-otis.tun.ply.gg:4243`) |

Simple Voice Chat nutzt nur **einen** UDP-Port, passt also 1:1 auf die
playit-Weiterleitung. Der Tunnel fuer 4243 muss **UDP** sein.

## Mods

`mods/` enthaelt Tectonic, Lithostitched, Terralith, Incendium, Nullscape,
Lithium, Chunky, Dream Displays und Simple Voice Chat - alles Fabric 26.3.

Neu laden: `.\download-mods.ps1`

## Welt vorladen

Noch nicht gemacht, weil es sehr lange dauert. In der Serverkonsole:

```
chunky center 0 0
chunky radius 1000
chunky start
chunky progress
```

| Radius | Chunks | Dauer (geschaetzt) |
|---|---|---|
| 500 | ~785.000 | ~1 h |
| 1000 | ~3,1 Mio. | ~2-5 h |
| 2000 | ~12,5 Mio. | 10-20+ h |

`spawn-protection=0` ist gesetzt, damit die Vorabgenerierung nicht blockiert.

## Hinweise zu 26.3

- Der Fabric Installer liefert **keinen** `server.jar` mehr mit. Er muss separat
  von Mojang kommen (liegt hier, SHA-1 geprueft).
- Die Welt nutzt das neue Layout `world\dimensions\minecraft\<dim>\region\`.
- `region-file-compression` nimmt nur noch `lz4`, `none` oder `deflate` - keine Zahlen.

## Icon und MOTD

`server-icon.png` (64x64) und die MOTD in `server.properties`.
Beides wird live ausgeliefert und laesst sich pruefen mit
`python ..\check-serverlist.py`.
