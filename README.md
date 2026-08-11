# DML Pack installer for Windows

Windows equivalent of `install-dmlpack-portable.sh` (Steam Deck / Linux).

Restores **Dad’s MMO Lab** `.dmlpack` archives on a Windows PC using:

| Piece | Windows approach |
|-------|------------------|
| Game servers | **Docker Desktop** (Linux containers) + `docker compose` |
| Game clients | **Native Windows `.exe`** (no Proton) |
| Launchers | PowerShell scripts + Desktop shortcuts |
| Optional | Steam library shortcuts (same `shortcuts.vdf` format) |

## Supported packs (tested recipes)

- **EVE Online (EvEJS X-Eve)** — `evejs-1.0.dmlpack`
- **Turtle WoW V2** — `TurtleV2.dmlpack`

Other dmlpack games may restore data via the same tool; Windows launchers are only bundled for the two above.

## Requirements

- Windows 10/11 64-bit  
- [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/) with **Linux containers**  
- [Python 3.10+](https://www.python.org/downloads/) on PATH  
- Enough free disk (often **40+ GB** per full pack)  
- Optional: [Steam](https://store.steampowered.com/) for library shortcuts  
- Optional: `zstd` on PATH (otherwise Docker alpine decompresses archives)

## Quick start

1. Copy this folder **next to** your `.dmlpack` files (e.g. on the USB stick).
2. Right-click `Install-DmlPack.portable.ps1` → **Run with PowerShell**  
   (or open PowerShell and run):

```powershell
cd "D:\DML Packs"   # wherever the kit + packs live
Set-ExecutionPolicy -Scope Process Bypass
.\Install-DmlPack.portable.ps1
```

3. Choose **1) Install a pack**, pick EvEJS or Turtle, wait for unpack.  
4. Start **Docker Desktop**, then:

   - Desktop → **EVE Online Server** / **Turtle WoW V2 Server** → wait for READY  
   - Desktop → **EVE Online** / **Turtle WoW**

Launchers also live under:

```text
%USERPROFILE%\DML-Launchers\
```

## GitHub

```text
https://github.com/IM0001GT/evejs-dmlpack-windows
```

## What this is not

- Not a crack or public multiplayer service  
- Does **not** include the multi-GB `.dmlpack` files (those stay on your USB)  
- Linux/Steam Deck users should keep using `install-dmlpack-portable.sh`

## Layout

```text
Install-DmlPack.portable.ps1   menu installer
dmlpack.py                     Windows-capable restore engine
launchers\                     Evejs-*.ps1, TurtleWow-*.ps1
GUIDE.md
NOTICE.md
```

## Related tools

| Tool | Purpose |
|------|---------|
| [evejs-solo-rpg-preset](https://github.com/IM0001GT/evejs-solo-rpg-preset) | Solo RPG config for EveJS |
| [evejs-server-snapshot](https://github.com/IM0001GT/evejs-server-snapshot) | Backup/migrate a live EveJS universe |
| [evejs-tq-import](https://github.com/IM0001GT/evejs-tq-import) | Import TQ characters via ESI |
