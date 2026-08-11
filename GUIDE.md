# Windows DML pack install — full guide

## Background

On Steam Deck / Linux, `install-dmlpack-portable.sh` unpacks a `.dmlpack` with `dmlpack.py`, starts servers in Docker, and registers **Steam + Proton** shortcuts for Windows game binaries.

On Windows the same archives work, but:

- Servers still run in **Docker** (compose)
- Clients run as **native `.exe`** (no Proton / Wine)
- Shortcuts are **Desktop + `%USERPROFILE%\DML-Launchers`** PowerShell scripts
- Steam shortcuts are optional and remapped to those scripts

## Step-by-step

### 1. Install prerequisites

1. Docker Desktop → install → start → confirm **Linux containers** (not Windows containers).  
2. Python 3.10+ → install → tick **Add to PATH**.  
3. Reboot if Docker/Python were just installed.

The installer **checks dependencies automatically** when it starts (Python, Docker Linux engine + compose, tar, disk space, kit files; optional Steam/zstd).  
Each FAIL line includes an install URL or fix. Menu **8) Re-check dependencies** re-runs the report anytime.  
**Install is blocked** until required items pass.

### 2. Place the kit

Either:

- USB: copy the whole `dmspack-install-windows` folder next to `evejs-1.0.dmlpack` and `TurtleV2.dmlpack`, or  
- Git:

```powershell
git clone https://github.com/IM0001GT/dmspack-install-windows.git
# copy your .dmlpack files into that folder or leave them on the USB
```

### 3. Run the installer

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Install-DmsPack.portable.ps1
```

Menu:

| # | Action |
|---|--------|
| 1 | Install (full restore) |
| 2 | Dry-run preflight |
| 3 | Verify sha256 of every member |
| 4 | Rebuild shortcuts only |
| 5 | Repair docker/images without re-extract |
| 6 | List packs |
| 7 | Requirements help |

### 4. First launch

**Always start the server first.**

| Game | Server shortcut | Client |
|------|-----------------|--------|
| EvEJS | EVE Online Server | EVE Online |
| Turtle V2 | Turtle WoW V2 Server | Turtle WoW |

Wait until the server window says **READY**, then start the client.

### 5. Disk & temp space

Extraction uses a scratch folder next to the pack (`.dmlpack-tmp`). Prefer installing from a drive with **lots of free space** (USB 3 / internal data drive), not a nearly full `C:`.

## Ports

| Pack | Ports |
|------|-------|
| EvEJS | 443, 5222, 26000–26002, 40110 |
| Turtle V2 | 80, 3309, 3724, 8095 |

Close anything already bound to those ports (IIS on 80, other game servers, etc.).

## After install — where things live

| Path | Contents |
|------|----------|
| `%USERPROFILE%\evejs-xeve` | EvEJS server tree |
| `%USERPROFILE%\Games\EVE Online - 3396210` | EVE client |
| `%USERPROFILE%\tortoise-wow-server-V2` | Turtle server + compose |
| `%USERPROFILE%\Games\TurtleWoW\TurtleWoW` | Turtle client |
| `%USERPROFILE%\DML-Launchers` | PowerShell launchers |
| Docker volume `evejs-xeve-data` | EvEJS universe DB |
| Docker volume (Turtle dbdata) | Turtle DB |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Unexpected token` / `Missing closing ')'` as soon as the script starts | You have an **old kit** (v1.1.0) that Windows PowerShell 5.1 mis-read (UTF-8 without BOM + fancy dashes). Download **v1.1.1+** from GitHub releases and replace `Install-DmsPack.portable.ps1`. Do not open/edit the `.ps1` in Notepad and re-save as ANSI. |
| Deps all OK (only optional zstd missing) but **Pre-flight failed** with no FAIL lines | Fixed in **v1.1.2**: Windows no longer fails pre-flight on Deck/Proton runtime deps; path rewriting for `/home/deck` is fixed; dry-run prints the real Python exit code. Update the kit and retry. |
| **Verify archive** fails instantly with almost no dmlpack output, even though the pack SHA-256 matches a known-good file | Fixed in **v1.1.3**: PowerShell was capturing Python’s stdout into `$rc = Invoke-Dmlpack …`, hiding the real verify log and treating success as failure (`$rc -ne 0` on an array of log lines). Update the kit and retry — the pack itself is fine. |
| Steam path shows as a single letter `C` | Cosmetic only (fixed in v1.1.2); Steam is still optional. |
| Docker not responding | Start Docker Desktop; wait until engine is green |
| Preflight: port in use | `netstat -ano \| findstr :3724` (etc.) and stop the process |
| Client can’t connect | Server READY? Firewall blocking local ports? |
| EvEJS login TLS errors | Start server once (generates CA), re-run client (runs `evejs-install-ca.py`) |
| Turtle instant disconnect | `realmlist.wtf` must be exactly `set realmlist 127.0.0.1` with **no leading space** |
| Steam shortcuts missing | Close Steam fully, installer option 4 |
| Extraction fails without zstd | Normal - Docker alpine is used; ensure Docker works |

## Repair without re-copying 30 GB

If files are on disk but images/volumes are wrong:

```text
Menu → 5) Repair
```

Or:

```powershell
python dmlpack.py repair path\to\pack.dmlpack
```

## Moving machines later

For a **live** EveJS world you have already played on, prefer:

[evejs-server-snapshot](https://github.com/IM0001GT/evejs-server-snapshot)

A `.dmlpack` is a **factory image** of a known-good stack; a server-snapshot is your **current** characters and market.
