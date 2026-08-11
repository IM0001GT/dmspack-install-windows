#Requires -Version 5.1
<#
.SYNOPSIS
  DMS Pack installer for Windows (Docker Desktop + native clients).

.DESCRIPTION
  Menu-driven installer equivalent of install-dmlpack-portable.sh for Steam Deck /
  Linux. Restores .dmlpack archives (Turtle WoW, EvEJS, etc.) using a Windows-
  capable dmlpack.py, Docker Compose for servers, and PowerShell launchers for
  native Windows clients (no Proton required).

  Put this folder next to your .dmlpack files (e.g. on a USB stick) or clone the
  GitHub kit into tools/dmspack-install-windows (or next to your .dmlpack files).

.NOTES
  Requires: Python 3.10+, Docker Desktop (Linux containers), enough free disk.
  Optional: Steam (for Steam library shortcuts), zstd on PATH (else Docker extracts).
#>

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Version = "1.1.2-windows"
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
        $v = & py -3 -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) { return @{ Cmd = @("py", "-3"); Version = "$v".Trim() } }
      } else {
        $v = & $c -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) { return @{ Cmd = @($c); Version = "$v".Trim() } }
      }
    } catch {}
  }
  return $null
}

function Get-PythonMajorMinor([string]$ver) {
  if ($ver -match '^(\d+)\.(\d+)') {
    return @{ Major = [int]$Matches[1]; Minor = [int]$Matches[2] }
  }
  return $null
}

function Test-CommandExists([string]$name) {
  return $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

function Get-FreeDiskGB([string]$path) {
  try {
    $resolved = if (Test-Path -LiteralPath $path) {
      (Resolve-Path -LiteralPath $path).Path
    } else {
      $path
    }
    $root = [System.IO.Path]::GetPathRoot($resolved)
    if (-not $root) { $root = $env:SystemDrive + "\" }
    $drive = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
      Where-Object { $_.Root -eq $root -or ($_.Name + ":\") -eq $root } |
      Select-Object -First 1
    if ($drive -and $drive.Free) {
      return [math]::Round($drive.Free / 1GB, 1)
    }
    # Fallback: WMI / .NET
    $letter = $root.Substring(0, 1)
    $vol = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
    if ($vol) { return [math]::Round($vol.SizeRemaining / 1GB, 1) }
  } catch {}
  return $null
}

function Test-DockerLinuxEngine {
  # Returns: ok | missing | not_running | wrong_engine | unknown
  if (-not (Test-CommandExists "docker")) { return "missing" }
  $info = & docker info 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { return "not_running" }
  if ($info -match 'OSType:\s*windows' -or $info -match 'windowsfilter') {
    return "wrong_engine"
  }
  # compose v2 plugin
  & docker compose version 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { return "no_compose" }
  return "ok"
}

<#
.SYNOPSIS
  Check required and optional dependencies. Prints a report.
.OUTPUTS
  Hashtable: RequiredOk (bool), OptionalNotes (string[]), Details
#>
function Test-Dependencies {
  param(
    [switch]$Quiet,
    [switch]$RequireDockerRunning
  )

  $details = New-Object System.Collections.Generic.List[object]
  $requiredOk = $true
  $optionalNotes = New-Object System.Collections.Generic.List[string]

  # Use a scriptblock so we mutate the outer lists reliably in Windows PowerShell 5.1
  $addDep = {
    param([string]$name, [string]$status, [string]$level, [string]$detail, [string]$fix)
    $details.Add([pscustomobject]@{
      Name = $name; Status = $status; Level = $level; Detail = $detail; Fix = $fix
    }) | Out-Null
    # Only FAIL on required items blocks install; warn/skip do not.
    if ($level -eq "required" -and $status -eq "fail") {
      $script:depRequiredOk = $false
    }
  }
  $script:depRequiredOk = $true

  # --- PowerShell ---
  $psVer = $PSVersionTable.PSVersion
  if ($psVer.Major -ge 5) {
    & $addDep "PowerShell" "ok" "required" "v$psVer" ""
  } else {
    & $addDep "PowerShell" "fail" "required" "v$psVer (need 5.1+)" `
      "Use Windows PowerShell 5.1 or install PowerShell 7: https://aka.ms/powershell"
  }

  # --- 64-bit Windows ---
  if ([Environment]::Is64BitOperatingSystem) {
    & $addDep "Windows 64-bit" "ok" "required" ([System.Environment]::OSVersion.Version.ToString()) ""
  } else {
    & $addDep "Windows 64-bit" "fail" "required" "32-bit OS not supported" "Use a 64-bit Windows 10/11 PC"
  }

  # --- Kit files ---
  $dml = Join-Path $ScriptDir "dmlpack.py"
  if (Test-Path -LiteralPath $dml) {
    & $addDep "dmlpack.py" "ok" "required" $dml ""
  } else {
    & $addDep "dmlpack.py" "fail" "required" "missing next to installer" `
      "Re-copy the dmspack-install-windows folder (include dmlpack.py)"
  }
  $launchers = Join-Path $ScriptDir "launchers"
  if (Test-Path -LiteralPath $launchers) {
    & $addDep "launchers/" "ok" "required" $launchers ""
  } else {
    & $addDep "launchers/" "fail" "required" "folder missing" `
      "Re-copy the full dmspack-install-windows kit including launchers\"
  }

  # --- Python ---
  $pyInfo = Find-Python
  if (-not $pyInfo) {
    & $addDep "Python 3" "fail" "required" "not found on PATH" `
      "Install Python 3.10+ from https://www.python.org/downloads/  (tick 'Add python.exe to PATH'), then re-open PowerShell"
    $script:Python = $null
  } else {
    $script:Python = $pyInfo.Cmd
    $mm = Get-PythonMajorMinor $pyInfo.Version
    if ($mm -and ($mm.Major -gt 3 -or ($mm.Major -eq 3 -and $mm.Minor -ge 10))) {
      & $addDep "Python 3" "ok" "required" ("{0} ({1})" -f $pyInfo.Version, ($pyInfo.Cmd -join " ")) ""
    } elseif ($mm) {
      & $addDep "Python 3" "fail" "required" ("found {0}, need 3.10+" -f $pyInfo.Version) `
        "Upgrade Python: https://www.python.org/downloads/"
    } else {
      & $addDep "Python 3" "warn" "required" ("found ({0}), version unclear" -f ($pyInfo.Cmd -join " ")) `
        "Ensure Python 3.10+ is installed"
    }
  }

  # --- tar (Windows 10+ ships tar.exe) ---
  if (Test-CommandExists "tar") {
    & $addDep "tar" "ok" "required" ((Get-Command tar).Source) ""
  } else {
    & $addDep "tar" "fail" "required" "tar.exe not on PATH" `
      "Windows 10/11 includes tar.exe; repair system PATH or install Git for Windows"
  }

  # --- Docker ---
  $dockerState = Test-DockerLinuxEngine
  switch ($dockerState) {
    "ok" {
      $dv = (& docker version --format '{{.Server.Version}}' 2>$null)
      if (-not $dv) { $dv = "running" }
      & $addDep "Docker Desktop" "ok" "required" "Linux engine $dv + compose" ""
    }
    "missing" {
      & $addDep "Docker Desktop" "fail" "required" "docker not on PATH" `
        "Install Docker Desktop: https://docs.docker.com/desktop/setup/install/windows-install/  then enable Linux containers"
    }
    "not_running" {
      # Required for install; startup report shows FAIL so user knows to start it
      & $addDep "Docker Desktop" "fail" "required" "installed but engine not running" `
        "Start Docker Desktop and wait until it says 'Engine running'. Installer can try to open it for you at install time."
    }
    "wrong_engine" {
      & $addDep "Docker Desktop" "fail" "required" "Windows containers mode active" `
        "Switch Docker Desktop to Linux containers (tray icon -> Switch to Linux containers)"
    }
    "no_compose" {
      & $addDep "Docker Compose" "fail" "required" "docker compose plugin missing" `
        "Update Docker Desktop; Compose V2 should ship as 'docker compose'"
    }
    default {
      & $addDep "Docker Desktop" "fail" "required" "unknown state" "Reinstall Docker Desktop"
    }
  }

  # --- Optional: zstd ---
  if (Test-CommandExists "zstd" -or Test-CommandExists "zstd.exe") {
    & $addDep "zstd" "ok" "optional" "on PATH (faster extract)" ""
  } else {
    & $addDep "zstd" "skip" "optional" "not on PATH - Docker alpine will decompress packs" `
      "Optional: install zstd for Windows if you want host-side extract"
    $optionalNotes.Add("zstd optional; Docker can extract .tar.zst without it") | Out-Null
  }

  # --- Optional: Steam ---
  $steamPaths = @(
    @(
      "${env:ProgramFiles(x86)}\Steam\steam.exe",
      "${env:ProgramFiles}\Steam\steam.exe",
      "$env:LOCALAPPDATA\Steam\steam.exe"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
  )
  if ($steamPaths.Count -gt 0) {
    & $addDep "Steam" "ok" "optional" $steamPaths[0] ""
  } else {
    & $addDep "Steam" "skip" "optional" "not found - Desktop shortcuts still work" `
      "Optional: https://store.steampowered.com/about/ for Steam library shortcuts"
    $optionalNotes.Add("Steam optional; use Desktop / DML-Launchers without it") | Out-Null
  }

  # --- Disk (user profile) ---
  $freeHome = Get-FreeDiskGB $env:USERPROFILE
  if ($null -ne $freeHome) {
    if ($freeHome -ge 40) {
      & $addDep "Free disk (user profile)" "ok" "required" ("{0} GB free on {1}" -f $freeHome, ([IO.Path]::GetPathRoot($env:USERPROFILE))) ""
    } elseif ($freeHome -ge 15) {
      & $addDep "Free disk (user profile)" "warn" "required" ("only {0} GB free - large packs need ~40+ GB" -f $freeHome) `
        "Free space on the system drive or restore with packs/temp on a larger drive"
    } else {
      & $addDep "Free disk (user profile)" "fail" "required" ("only {0} GB free" -f $freeHome) `
        "Free at least ~40 GB (EveJS pack is multi-dozen GB unpacked + Docker layers)"
    }
  } else {
    & $addDep "Free disk (user profile)" "warn" "optional" "could not measure free space" "Check disk space manually"
  }

  $requiredOk = $script:depRequiredOk

  if (-not $Quiet) {
    Write-Header "Dependency check"
    foreach ($d in $details) {
      $tag = switch ($d.Status) {
        "ok"   { " OK "; break }
        "fail" { "FAIL"; break }
        "warn" { " !! "; break }
        "skip" { " -- "; break }
        default { $d.Status }
      }
      $color = switch ($d.Status) {
        "ok"   { "Green"; break }
        "fail" { "Red"; break }
        "warn" { "Yellow"; break }
        default { "DarkCyan" }
      }
      $level = if ($d.Level -eq "optional") { "optional" } else { "required" }
      Write-Host ("  [{0}] {1,-22} ({2})  {3}" -f $tag, $d.Name, $level, $d.Detail) -ForegroundColor $color
      if ($d.Status -eq "fail" -and $d.Fix) {
        Write-Host ("         -> {0}" -f $d.Fix) -ForegroundColor Yellow
      } elseif ($d.Status -eq "warn" -and $d.Fix) {
        Write-Host ("         -> {0}" -f $d.Fix) -ForegroundColor DarkYellow
      }
    }
    Write-Host ""
    if ($requiredOk) {
      Write-Ok "All required dependencies look good."
    } else {
      Write-Err "One or more REQUIRED dependencies are missing."
      Write-Info "Install the items marked FAIL, re-open PowerShell, then run this installer again."
      Write-Info "Menu option 8 re-runs this check anytime."
    }
  }

  return @{
    RequiredOk = $requiredOk
    Details    = $details
    Optional   = $optionalNotes
  }
}

function Invoke-Dmlpack {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$DmlArgs)
  if (-not $script:Python) { throw "Python not configured - run dependency check (menu 8)" }
  $py = @($script:Python)
  $dml = Join-Path $ScriptDir "dmlpack.py"
  if (-not (Test-Path $dml)) { throw "dmlpack.py missing next to installer: $dml" }
  $pyArgs = @()
  if ($py.Count -gt 1) { $pyArgs = $py[1..($py.Count - 1)] }
  # Unbuffered Python so pre-flight lines appear immediately on Windows consoles
  $env:PYTHONUNBUFFERED = "1"
  $env:PYTHONIOENCODING = "utf-8"
  Write-Host ("  ..  python: {0} {1}" -f ($py -join " "), ($DmlArgs -join " ")) -ForegroundColor DarkGray
  & $py[0] @pyArgs $dml @DmlArgs
  $code = $LASTEXITCODE
  # Some hosts leave LASTEXITCODE null after py.exe; treat null as failure only
  # when $? is false, else 0.
  if ($null -eq $code) {
    if (-not $?) { $code = 1 } else { $code = 0 }
  }
  return [int]$code
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
    Write-Err "Steam is still running - close it from the tray, then retry."
    return $false
  }
  Write-Warn "Continuing with Steam open - Steam shortcuts may be skipped."
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
    Write-Info "Copy packs next to Install-DmsPack.portable.ps1 or plug in the USB."
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

  Write-Step "checking dependencies"
  $dep = Test-Dependencies -RequireDockerRunning
  if (-not $dep.RequiredOk) {
    Write-Err "Cannot install until required dependencies pass (see list above)."
    Pause-Enter
    return
  }
  if (-not (Test-Docker)) { Pause-Enter; return }
  Ensure-SteamClosed | Out-Null

  if (Ask-YesNo "Verify archive checksums first (slow, recommended once)?" $false) {
    $rc = Invoke-Dmlpack verify $script:Pack
    if ($rc -ne 0) { Write-Err "Archive failed checks - not installing."; Pause-Enter; return }
  }

  Write-Step "pre-flight dry-run"
  Write-Info "Running: dmlpack.py restore --dry-run (details below)..."
  $rc = Invoke-Dmlpack restore $script:Pack --dry-run
  if ($rc -ne 0) {
    Write-Err ("Pre-flight failed (exit code {0}). Read the FAIL lines above." -f $rc)
    Write-Info "Common fixes: free ports listed above; free disk on the destination drive;"
    Write-Info "close apps using game folders; ensure the .dmlpack path is readable."
    Write-Info "Tip: menu 3) Preview shows the same dry-run without starting install."
    Pause-Enter
    return
  }
  Write-Ok "ready to install"
  if (-not (Ask-YesNo "Unpack now? This can take a long time for multi-GB packs." $true)) { return }

  Write-Header "Installing - do not close this window"
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
    Write-Info "Server/client files are usually fine - use DML-Launchers or option 4."
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
  $dep = Test-Dependencies -Quiet
  if (-not $dep.RequiredOk -or -not $script:Python) {
    Write-Err "Fix required dependencies first (menu 8)."
    $null = Test-Dependencies
    Pause-Enter
    return
  }
  if (-not (Test-Docker)) { Pause-Enter; return }
  Invoke-Dmlpack restore $script:Pack --dry-run | Out-Host
  Pause-Enter
}

function ConvertTo-PythonString([string]$Value) {
  # Produce a Python single-quoted string literal safe for -c embedding
  if ($null -eq $Value) { return "''" }
  $escaped = $Value.Replace('\', '\\').Replace("'", "\'")
  return "'$escaped'"
}

function Do-Shortcuts {
  if (-not (Need-Pack)) { return }
  Write-Header "Add shortcuts"
  Ensure-SteamClosed | Out-Null
  Invoke-Dmlpack shortcuts $script:Pack | Out-Host
  # Also re-run launcher install via a tiny restore post-step
  Write-Info "Refreshing Windows launchers..."
  $pyScriptDir = ConvertTo-PythonString $ScriptDir
  $pyPack = ConvertTo-PythonString $script:Pack
  # Double-quoted here-string so PowerShell expands $pyScriptDir / $pyPack
  $code = @"
import json, tarfile, sys
from pathlib import Path
sys.path.insert(0, $pyScriptDir)
import dmlpack
pack = Path($pyPack)
# .dmlpack is an uncompressed tar (first member = manifest.json)
with tarfile.open(pack, "r|") as tf:
    first = next(iter(tf))
    m = json.loads(tf.extractfile(first).read())
dmlpack.install_windows_launchers(m)
print("launchers refreshed")
"@
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
  Write-Header "Windows requirements (reference)"
  Write-Host @"
  REQUIRED
  - Windows 10/11 64-bit
  - PowerShell 5.1+
  - Python 3.10+ on PATH (python or py -3)
      https://www.python.org/downloads/   (tick "Add python.exe to PATH")
  - Docker Desktop with Linux containers + "docker compose"
      https://docs.docker.com/desktop/setup/install/windows-install/
  - tar.exe (included with modern Windows)
  - Free disk: typically 40+ GB per full pack (client + server + Docker layers)
  - This kit's dmlpack.py + launchers\ folder

  OPTIONAL
  - Steam (library shortcuts; Desktop shortcuts work without it)
  - zstd.exe on PATH (otherwise Docker alpine decompresses packs)

  Ports used (must be free at install / runtime):
    EvEJS     : 443, 5222, 26000-26002, 40110
    Turtle V2 : 80, 3309, 3724, 8095

  Flow after install:
    1. Start Docker Desktop
    2. Desktop -> SERVER shortcut -> wait for READY
    3. Desktop -> GAME shortcut

  Use menu 8 anytime for a live check of what is installed on THIS PC.

"@
  Pause-Enter
}

function Do-DependencyCheck {
  $null = Test-Dependencies
  Pause-Enter
}

# ---------------------------------------------------------------- main
Write-Header "DMS Pack Installer for Windows  v$Version"
Write-Info "Script dir: $ScriptDir"
Write-Host ""

# Always run a dependency report at startup so missing Python/Docker is obvious
$startupDeps = Test-Dependencies
if (-not $startupDeps.RequiredOk) {
  Write-Host ""
  Write-Warn "Some required tools are missing. You can still browse the menu,"
  Write-Warn "but Install / Preview / Repair will be blocked until they pass."
  Write-Info "Fix the FAIL lines above, then use menu 8 to re-check."
  Write-Host ""
  if (-not (Ask-YesNo "Continue to the menu anyway?" $true)) {
    exit 1
  }
}

while ($true) {
  Write-Header "Main menu"
  Write-Host "   1) Install a pack (recommended)"
  Write-Host "   2) Preview / dry-run"
  Write-Host "   3) Verify pack checksums"
  Write-Host "   4) Re-add Steam + Desktop shortcuts"
  Write-Host "   5) Repair (docker/images after a partial install)"
  Write-Host "   6) List packs found"
  Write-Host "   7) Windows requirements (text guide)"
  Write-Host "   8) Re-check dependencies on this PC"
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
    "8" { Do-DependencyCheck }
    "0" { break }
    default { Write-Warn "not a valid choice" }
  }
}

Write-Host "Bye."
