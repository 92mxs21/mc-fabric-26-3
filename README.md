# uwu uwu uwu - Minecraft 26.3 Fabric

Ein-Klick-Setup fuer den **offiziellen** Minecraft-Launcher (Microsoft Store und Win32).
Kein dritter Launcher, kein Fabric-Installer-Fenster - alles headless.

Website: <https://92mxs21.github.io/mc-fabric-26-3/>

## Was es macht

| Schritt | |
|---|---|
| 1 | Minecraft-Launcher schliessen |
| 2 | Mods-Ordner zeitgestempelt sichern (SHA-256-Manifest) |
| 3 | Fabric 26.3 headless installieren, Profil im Launcher anlegen |
| 4 | Versions-JSON patchen: eigener Mods-Ordner fuer 26.3 |
| 5 | Mods von Modrinth laden und gegen ihre `fabric.mod.json` pruefen |
| 6 | Optional: Minecraft starten |

## Benutzung

**Fertig herunterladen (empfohlen):** `bootstrap.cmd` ausfuehren.
Laedt `setup-fabric-client.ps1` von GitHub Pages und startet es.

**Aus dem Repo:**
```powershell
.\setup-fabric-client.ps1
.\setup-fabric-client.ps1 -Launch   # startet danach Minecraft
```

Administratorrechte sind nicht noetig.

## Getrennte Mods-Ordner

| Profil | Ordner |
|---|---|
| Vanilla 26.3 | `.minecraft\mods` |
| Fabric 26.3 | `.minecraft\mods26.3` |

Umsetzung ueber `-Dfabric.modsFolder` in der Versions-JSON, damit Welten,
Einstellungen und Ressourcenpakete geteilt bleiben.

## Zwei Fallstricke, die das Script umgeht

**`-launcher microsoft_store` ist falsch.** Der Fabric Installer sucht dann
`launcher_profiles_microsoft_store.json`. Der Native-Launcher 2.6.2 legt aber nur
`launcher_profiles.json` an - der Installer liegt bei dieser Version falsch und
bricht mit `FileNotFoundException` ab. Das Script prueft, welche Datei existiert.

**Backslashes in JSON muessen verdoppelt sein.** `-Dfabric.modsFolder=C:\Users\...`
ist ein ungueltiges Escape-Sequenz (`\U`), die Versions-JSON wird dann ungueltig und
der Client startet gar nicht. Das Script escaped das und validiert die JSON danach.

## Mods

**Client** (geht in `mods26.3`): Fabric API, Dream Displays, Simple Voice Chat,
Sodium, Iris, Sodium Extra.

**Server** (gehoert in den Serverordner, nicht auf den Client):
Tectonic, Lithostitched, Terralith, Incendium, Nullscape, Lithium, Chunky,
Dream Displays, Simple Voice Chat.

Sodium, Iris und Sodium Extra sind `env=client` und gehoeren **nicht** auf den Server.
Sodium ist fuer 26.3 noch Alpha (`0.9.3-alpha.1`).

## Backups

```powershell
.\mods-backup.ps1 -ModsDir '...\mods26.3' -Prune 5
```

Legt `.minecraft\backups\mods\mods-backup_JJJJ-MM-TT_HH-mm-ss\` an
(JJJJ-MM-TT_HH-mm-ss, weil Windows keine Doppelpunkte in Dateinamen erlaubt),
inklusive `_manifest.txt` mit SHA-256-Pruefsummen.

## Server

Siehe `server/README.md`. Ports: Spiel TCP 25565, Voice Chat UDP 24454.

## Lizenz

MIT - siehe [LICENSE](LICENSE).

Minecraft ist ein eingetragenes Warenzeichen von Mojang Studios.
Dieses Projekt ist nicht von Mojang oder Microsoft offiziell unterstuetzt.
