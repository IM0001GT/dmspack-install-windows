#Requires -Version 5.1
<#
.SYNOPSIS
  DML Pack installer for Windows (Docker Desktop + native clients).

.DESCRIPTION
  Menu-driven installer equivalent of install-dmlpack-portable.sh for Steam Deck /
  Linux. Restores .dmlpack archives (Turtle WoW, EvEJS, etc.) using a Windows-
  capable dmlpack.py, Docker Compose for servers, and PowerShell launchers for
  native Windows clients (no Proton required).

  Put this folder next to your .dmlpack files (e.g. on a USB stick) or clone the
  GitHub kit into tools/dmlpack-windows inside an evejs tree.

.NOTES
  Requires: Python 3.10+, Docker Desktop (Linux containers), enough free disk.
  Optional: Steam (for Steam library shortcuts), zstd on PATH (else Docker extracts).
#>

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Version = "1.1.0-windows"
$Pack = $null
$Python = $null

function Write-Header([string]$msg) {
  Write-Host ""
  Write-Host ("=" * 60) -ForegroundColor Cyan
  Write-Host "  $msg" -ForegroundColor Cyan
  Write-Host ("=" * 60) -ForegroundColor Cyan
}
function Write-Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Blue }
function Write-Ok([string]$msg)   { Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "  !!  $msg" -ForegroundColor Yellow }
function Write-Err([string]$msg)  { Write-Host " FAIL $msg" -ForegroundColor Red }
function Write-Info([string]$msg) { Write-Host "  ..  $msg" -ForegroundColor DarkCyan }
function Pause-Enter { Write-Host ""; Read-Host "Press Enter to continue" | Out-Null }

function Ask-YesNo([string]$prompt, [bool]$default = $false) {
  $hint = if ($default) { "[Y/n]" } else { "[y/N]" }
  $ans = Read-Host "$prompt $hint"
  if ([string]::IsNullOrWhiteSpace($ans)) { return $default }
  return $ans.Trim().ToLower().StartsWith("y")
}

function Find-Python {
  foreach ($c in @("py -3", "python3", "python")) {
    try {
      if ($c -eq "py -3") {
        $v = & py -3 -c "import sys; print(sys.version)" 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) { return @("py", "-3") }
      } else {
        $v = & $c -c "import sys; print(sys.version)" 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) { return @($c) }
      }
    } catch {}
  }
  return $null
}

function Invoke-Dmlpack {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$DmlArgs)
  if (-not $script:Python) { throw "Python not configured" }
  $py = $script:Python
  $dml = Join-Path $ScriptDir "dmlpack.py"
  if (-not (Test-Path $dml)) { throw "dmlpack.py missing next to installer: $dml" }
  $pyArgs = @()
  if ($py.Count -gt 1) { $pyArgs = $py[1..($py.Count - 1)] }
  & $py[0] @pyArgs $dml @DmlArgs
  return $LASTEXITCODE
}

function Test-Docker {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Err "Docker is not installed / not on PATH."
    Write-Info "Install Docker Desktop for Windows and enable Linux containers."
    Write-Info "https://docs.docker.com/desktop/setup/install/windows-install/"
    return $false
  }
  docker info 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Warn "Docker is installed but not running."
    if (Ask-YesNo "Open Docker Desktop now?" $true) {
      $dd = @(
        "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
      ) | Where-Object { Test-Path $_ } | Select-Object -First 1
      if ($dd) { Start-Process $dd } else { Write-Warn "Could not find Docker Desktop.exe" }
      Write-Info "Waiting up to 90s for Docker..."
      for ($i = 0; $i -lt 18; $i++) {
        Start-Sleep -Seconds 5
        docker info 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { break }
        Write-Host -NoNewline "."
      }
      Write-Host ""
    }
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
      Write-Err "Docker still not responding."
      return $false
    }
  }
  Write-Ok "Docker is running"
  return $true
}

function Test-SteamRunning {
  return $null -ne (Get-Process -Name "steam","steamwebhelper" -ErrorAction SilentlyContinue)
}

function Ensure-SteamClosed {
  if (-not (Test-SteamRunning)) { Write-Ok "Steam is closed"; return $true }
  Write-Warn "Steam is running."
  Write-Info "Steam rewrites shortcuts.vdf on exit and can discard installer changes."
  if (Ask-YesNo "Try to close Steam now?" $true) {
    try { Start-Process "steam://exit" -ErrorAction SilentlyContinue } catch {}
    Get-Process -Name "steam" -ErrorAction SilentlyContinue | ForEach-Object {
      try { $_.CloseMainWindow() | Out-Null } catch {}
    }
    for ($i = 0; $i -lt 30; $i++) {
      if (-not (Test-SteamRunning)) { Write-Ok "Steam closed"; return $true }
      Start-Sleep -Seconds 2
    }
    Write-Err "Steam is still running — close it from the tray, then retry."
    return $false
  }
  Write-Warn "Continuing with Steam open — Steam shortcuts may be skipped."
  return $true
}

function Find-Packs {
  $roots = New-Object System.Collections.Generic.List[string]
  $roots.Add($ScriptDir)
  $roots.Add((Split-Path $ScriptDir -Parent))
  $roots.Add($env:USERPROFILE)
  # Removable / fixed drives
  Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Root) { $roots.Add($_.Root) }
  }
  $found = @{}
  foreach ($r in $roots) {
    if (-not $r -or -not (Test-Path $r)) { continue }
    try {
      Get-ChildItem -Path $r -Filter "*.dmlpack" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $found[$_.FullName] = $true
      }
      # One level deeper on drive roots / media
      Get-ChildItem -Path $r -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Get-ChildItem -Path $_.FullName -Filter "*.dmlpack" -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
          ForEach-Object { $found[$_.FullName] = $true }
      }
    } catch {}
  }
  return @($found.Keys | Sort-Object)
}

function Get-PackSummary([string]$path) {
  try {
    $json = & tar -xOf $path manifest.json 2>$null
    if (-not $json) { return "unreadable|?|0" }
    $m = $json | ConvertFrom-Json
    $date = if ($m.packed_at) { $m.packed_at.Substring(0, [Math]::Min(10, $m.packed_at.Length)) } else { "?" }
    $n = if ($m.members) { @($m.members).Count } else { 0 }
    $name = if ($m.display_name) { $m.display_name } else { "?" }
    return "$name|$date|$n"
  } catch {
    return "unreadable|?|0"
  }
}

function Choose-Pack {
  $packs = Find-Packs
  if ($packs.Count -eq 0) {
    Write-Warn "No .dmlpack files found on this PC or next to the installer."
    Write-Info "Copy packs next to Install-DmlPack.portable.ps1 or plug in the USB."
    if (Ask-YesNo "Type a full path manually?" $false) {
      $p = Read-Host "Full path to .dmlpack"
      if (Test-Path -LiteralPath $p -PathType Leaf) {
        $script:Pack = (Resolve-Path -LiteralPath $p).Path
        return $true
      }
      Write-Err "not a file: $p"
    }
    return $false
  }
  Write-Header "Choose a pack"
  for ($i = 0; $i -lt $packs.Count; $i++) {
    $p = $packs[$i]
    $sum = Get-PackSummary $p
    $parts = $sum -split '\|', 3
    $size = "{0:N1} GB" -f ((Get-Item -LiteralPath $p).Length / 1GB)
    Write-Host ("   {0}) {1,-28} {2,8}   packed {3}   {4} members" -f ($i+1), $parts[0], $size, $parts[1], $parts[2])
    Write-Host ("      {0}" -f $p) -ForegroundColor DarkGray
  }
  Write-Host "   0) back"
  $choice = Read-Host "Pick a number"
  if ($choice -eq "0") { return $false }
  $n = 0
  if (-not [int]::TryParse($choice, [ref]$n)) { Write-Err "not a valid choice"; return $false }
  if ($n -lt 1 -or $n -gt $packs.Count) { Write-Err "not a valid choice"; return $false }
  $script:Pack = $packs[$n - 1]
  Write-Ok ("selected: {0}" -f (Split-Path $script:Pack -Leaf))
  return $true
}

function Need-Pack {
  if ($script:Pack -and (Test-Path -LiteralPath $script:Pack)) { return $true }
  return Choose-Pack
}

function Do-Install {
  if (-not (Need-Pack)) { return }
  $sum = Get-PackSummary $script:Pack
  $name = ($sum -split '\|')[0]
  Write-Header "Install $name"
  Write-Info ("pack : {0} ({1:N1} GB)" -f (Split-Path $script:Pack -Leaf), ((Get-Item $script:Pack).Length / 1GB))
  Write-Host ""
  Write-Info "This will:"
  Write-Info "  1. check free space, ports, and Docker Desktop"
  Write-Info "  2. unpack the server (Docker) and Windows game client"
  Write-Info "  3. load Docker images / volumes and rebuild compose images if needed"
  Write-Info "  4. install Desktop + DML-Launchers PowerShell shortcuts"
  Write-Info "  5. optionally register Steam shortcuts (if Steam is installed)"
  Write-Host ""
  if (-not (Ask-YesNo "Continue?" $true)) { return }

  if (-not (Test-Docker)) { Pause-Enter; return }
  Ensure-SteamClosed | Out-Null

  if (Ask-YesNo "Verify archive checksums first (slow, recommended once)?" $false) {
    $rc = Invoke-Dmlpack verify $script:Pack
    if ($rc -ne 0) { Write-Err "Archive failed checks — not installing."; Pause-Enter; return }
  }

  Write-Step "pre-flight dry-run"
  $rc = Invoke-Dmlpack restore $script:Pack --dry-run
  if ($rc -ne 0) {
    Write-Err "Pre-flight failed. Fix the issues above, then retry."
    Pause-Enter
    return
  }
  Write-Ok "ready to install"
  if (-not (Ask-YesNo "Unpack now? This can take a long time for multi-GB packs." $true)) { return }

  Write-Header "Installing — do not close this window"
  # Prefer scratch on the same drive as the pack (USB / data drive) to avoid filling C:
  $tmp = Join-Path (Split-Path $script:Pack -Parent) ".dmlpack-tmp"
  $rc = Invoke-Dmlpack restore $script:Pack --tmp $tmp
  if ($rc -eq 0) {
    Write-Header "Done"
    Write-Ok "$name is installed."
    Write-Info "Desktop shortcuts and $env:USERPROFILE\DML-Launchers were created when possible."
    Write-Info "1) Start Docker Desktop"
    Write-Info "2) Run the SERVER shortcut and wait until it says READY"
    Write-Info "3) Run the GAME shortcut"
  } else {
    Write-Warn "Restore finished with warnings (often Steam shortcuts)."
    Write-Info "Server/client files are usually fine — use DML-Launchers or option 4."
  }
  Pause-Enter
}

function Do-Verify {
  if (-not (Need-Pack)) { return }
  Write-Header "Verify archive"
  Invoke-Dmlpack verify $script:Pack | Out-Host
  Pause-Enter
}

function Do-Preview {
  if (-not (Need-Pack)) { return }
  Write-Header "Preview (nothing written)"
  if (-not (Test-Docker)) { Pause-Enter; return }
  Invoke-Dmlpack restore $script:Pack --dry-run | Out-Host
  Pause-Enter
}

function Do-Shortcuts {
  if (-not (Need-Pack)) { return }
  Write-Header "Add shortcuts"
  Ensure-SteamClosed | Out-Null
  Invoke-Dmlpack shortcuts $script:Pack | Out-Host
  # Also re-run launcher install via a tiny restore post-step
  Write-Info "Refreshing Windows launchers..."
  $code = @'
import json, tarfile, sys
from pathlib import Path
sys.path.insert(0, r"'" + $ScriptDir.Replace("'", "''") + r"'")
import dmlpack
pack = Path(r"'" + $script:Pack.Replace("'", "''") + r"'")
with tarfile.open(pack, "r|") as tf:
    m = json.loads(tf.extractfile(next(tf)).read())
dmlpack.install_windows_launchers(m)
print("launchers refreshed")
'@
  try {
    $py = $script:Python
    & $py[0] @($py[1..($py.Length-1)]) -c $code
  } catch {
    Write-Warn "launcher refresh skipped: $_"
  }
  Pause-Enter
}

function Do-Repair {
  if (-not (Need-Pack)) { return }
  Write-Header "Repair"
  Write-Info "Re-runs post-extract docker/image/client steps without re-extracting multi-GB data."
  if (-not (Ask-YesNo "Run repair now?" $true)) { return }
  if (-not (Test-Docker)) { Pause-Enter; return }
  Invoke-Dmlpack repair $script:Pack | Out-Host
  Pause-Enter
}

function Do-List {
  Write-Header "Packs found"
  $packs = Find-Packs
  if ($packs.Count -eq 0) { Write-Info "none found" }
  else {
    foreach ($p in $packs) {
      $sum = Get-PackSummary $p
      $parts = $sum -split '\|', 3
      $size = "{0:N1} GB" -f ((Get-Item -LiteralPath $p).Length / 1GB)
      Write-Host ("   {0,-28} {1,8}  packed {2}" -f $parts[0], $size, $parts[1])
      Write-Host ("      {0}" -f $p) -ForegroundColor DarkGray
    }
  }
  Pause-Enter
}

function Show-Requirements {
  Write-Header "Windows requirements"
  Write-Host @"
  - Windows 10/11 64-bit
  - Docker Desktop with Linux containers
  - Python 3.10+ on PATH (python or py -3)
  - Free disk: typically 40+ GB per full pack (client + server + Docker layers)
  - Optional: Steam (for Steam library shortcuts)
  - Optional: zstd.exe on PATH (otherwise extraction uses Docker alpine)

  Ports used (must be free):
    EvEJS     : 443, 5222, 26000-26002, 40110
    Turtle V2 : 80, 3309, 3724, 8095

  Flow after install:
    1. Start Docker Desktop
    2. Desktop -> SERVER shortcut -> wait for READY
    3. Desktop -> GAME shortcut

"@
  Pause-Enter
}

# ---------------------------------------------------------------- main
Write-Header "DML Pack Installer for Windows  v$Version"
Write-Info "Script dir: $ScriptDir"

$script:Python = Find-Python
if (-not $script:Python) {
  Write-Err "Python 3 not found. Install from https://www.python.org/downloads/"
  Write-Info "Enable 'Add python.exe to PATH', then re-open PowerShell."
  Pause-Enter
  exit 1
}
Write-Ok ("Python: {0}" -f ($script:Python -join " "))

if (-not (Test-Path (Join-Path $ScriptDir "dmlpack.py"))) {
  Write-Err "dmlpack.py must sit next to this script."
  Pause-Enter
  exit 1
}
if (-not (Test-Path (Join-Path $ScriptDir "launchers"))) {
  Write-Warn "launchers/ folder missing — Desktop scripts may not install."
}

while ($true) {
  Write-Header "Main menu"
  Write-Host "   1) Install a pack (recommended)"
  Write-Host "   2) Preview / dry-run"
  Write-Host "   3) Verify pack checksums"
  Write-Host "   4) Re-add Steam + Desktop shortcuts"
  Write-Host "   5) Repair (docker/images after a partial install)"
  Write-Host "   6) List packs found"
  Write-Host "   7) Windows requirements"
  Write-Host "   0) Exit"
  $c = Read-Host "Pick a number"
  switch ($c) {
    "1" { Do-Install }
    "2" { Do-Preview }
    "3" { Do-Verify }
    "4" { Do-Shortcuts }
    "5" { Do-Repair }
    "6" { Do-List }
    "7" { Show-Requirements }
    "0" { break }
    default { Write-Warn "not a valid choice" }
  }
}

Write-Host "Bye."
