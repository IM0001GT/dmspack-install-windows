# EVE Online (EvEJS) - Windows server launcher with interactive control
# Requires: Docker Desktop running (Linux containers)
#
# After READY:
#   A = Auto   - watch for exefile; stop server when the game closes
#   S = Stay   - keep server up until you choose Shutdown (no client timeout)
#   Q = Quit   - stop server now
#   R = Status - is the client process running?
$ErrorActionPreference = "Continue"
$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$EVEJS_ROOT = if ($env:EVEJS_ROOT) { $env:EVEJS_ROOT } else { Join-Path $HomeDir "evejs-xeve" }
$PROXY_URL = if ($env:EVEJS_PROXY_URL) { $env:EVEJS_PROXY_URL } else { "http://127.0.0.1:26002" }
$ClientProcessNames = @("exefile")
$LogDir = Join-Path $HomeDir "evejs-logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("server-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

function Log($msg) {
  $line = "{0:HH:mm:ss}  {1}" -f (Get-Date), $msg
  Write-Host $line
  Add-Content -Path $LogFile -Value $line
}
function Die($msg) {
  Write-Host "ERROR: $msg" -ForegroundColor Red
  Add-Content -Path $LogFile -Value "ERROR: $msg"
  Read-Host "Press Enter to close"
  exit 1
}
function ClientRunning {
  foreach ($n in $ClientProcessNames) {
    if (Get-Process -Name $n -ErrorAction SilentlyContinue) { return $true }
  }
  return $false
}
function Stop-Server {
  Log "Stopping EveJS stack (compose stop, keep volumes)..."
  Push-Location $EVEJS_ROOT
  try {
    docker compose stop -t 60 2>&1 | Tee-Object -FilePath $LogFile -Append
  } finally {
    Pop-Location
  }
  if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: docker compose stop returned $LASTEXITCODE - see $LogFile" -ForegroundColor Yellow
  } else {
    Write-Host "Server stopped. Safe to close this window." -ForegroundColor Green
  }
}

Log "=== EvEJS Windows server launcher ==="
Log "root=$EVEJS_ROOT log=$LogFile"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Die "docker not found on PATH. Install Docker Desktop and enable Linux containers."
}
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  Die "Docker is not responding. Start Docker Desktop and wait until it is ready."
}
if (-not (Test-Path $EVEJS_ROOT)) {
  Die "Cannot find $EVEJS_ROOT - was the DML pack restored?"
}

# Prefer LAN compose if present + env
$composeArgs = @("-f", "compose.yaml")
$lanCompose = Join-Path $EVEJS_ROOT "compose.lan.yaml"
$lanEnv = @(
  (Join-Path $HomeDir "_local\lan-play\evejs-lan.env"),
  (Join-Path $EVEJS_ROOT "_local\lan-play\evejs-lan.env"),
  (Join-Path $EVEJS_ROOT "tools\lan-play\evejs-lan.env")
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ((Test-Path $lanCompose) -and $lanEnv) {
  $composeArgs += @("-f", "compose.lan.yaml", "--env-file", $lanEnv)
  Log "LAN mode: using compose.lan.yaml + $lanEnv"
}

Set-Location $EVEJS_ROOT
$composeName = $null
if (Test-Path "compose.yaml") {
  $line = Select-String -Path "compose.yaml" -Pattern '^name:\s*(\S+)' | Select-Object -First 1
  if ($line) { $composeName = $line.Matches[0].Groups[1].Value }
}
if (-not $composeName) { $composeName = Split-Path $EVEJS_ROOT -Leaf }
$serverContainer = "$composeName-server-1"
Log "project=$composeName container=$serverContainer"

function ServerHealthy {
  $status = docker inspect -f '{{.State.Health.Status}}' $serverContainer 2>$null
  return ($status -eq "healthy")
}

if (ServerHealthy) {
  Log "Backend already healthy"
} else {
  Log "Starting docker compose..."
  & docker compose @composeArgs up --detach 2>&1 | Tee-Object -FilePath $LogFile -Append
  if ($LASTEXITCODE -ne 0) {
    Die "docker compose up failed. See $LogFile"
  }
  Log "Containers started"
}

Log "Waiting for backend health (can take several minutes on first boot)..."
$deadline = (Get-Date).AddMinutes(12)
while ((Get-Date) -lt $deadline) {
  if (ServerHealthy) { break }
  Start-Sleep -Seconds 5
  Write-Host -NoNewline "."
}
Write-Host ""
if (-not (ServerHealthy)) {
  Die "Backend never became healthy. Check: docker compose logs --tail 100 server"
}
Log "Backend healthy"

try {
  $r = Invoke-WebRequest -Uri "$PROXY_URL/health" -UseBasicParsing -TimeoutSec 10
  if ($r.StatusCode -ge 400) { throw "status $($r.StatusCode)" }
  Log "Client proxy responding at $PROXY_URL"
} catch {
  Die "Client proxy not answering at $PROXY_URL/health - port/bind problem?"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  EVE ONLINE SERVER IS READY" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Now launch the EVE Online client shortcut."
Write-Host "  Log: $LogFile"
Write-Host ""
Write-Host "  Server control" -ForegroundColor White
Write-Host "    A  Auto     - shut down when the game client closes"
Write-Host "    S  Stay     - keep running until you press Q (no client timeout)"
Write-Host "    Q  Shutdown - stop the server now"
Write-Host "    R  Status   - is the client process running?"
Write-Host ""

$mode = $null
while (-not $mode) {
  $choice = Read-Host "  Choice [A/S/Q/R] (default A)"
  if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "A" }
  switch ($choice.Trim().ToUpperInvariant()) {
    { $_ -in @("A", "AUTO") } { $mode = "auto" }
    { $_ -in @("S", "STAY") } { $mode = "stay" }
    { $_ -in @("Q", "QUIT", "STOP", "EXIT", "SHUTDOWN") } { $mode = "quit" }
    { $_ -in @("R", "STATUS") } {
      if (ClientRunning) {
        Write-Host "  Client process detected ($($ClientProcessNames -join ', '))" -ForegroundColor Green
      } else {
        Write-Host "  No client process right now" -ForegroundColor Yellow
      }
    }
    default { Write-Host "  Unknown choice - pick A, S, Q, or R" -ForegroundColor Yellow }
  }
}

if ($mode -eq "quit") {
  Stop-Server
  Read-Host "Press Enter to close"
  exit 0
}

if ($mode -eq "auto") {
  Log "control mode: auto"
  Write-Host "  Auto mode - waiting for client (exefile)..." -ForegroundColor Cyan
  Write-Host "  (If none appears, server stays up 3 hours then stops, or press Ctrl+C and use Q next time.)"
  $waitUntil = (Get-Date).AddMinutes(5)
  $found = $false
  while ((Get-Date) -lt $waitUntil) {
    if (ClientRunning) { $found = $true; break }
    Start-Sleep -Seconds 5
    Write-Host -NoNewline "."
  }
  Write-Host ""
  if ($found) {
    Write-Host "  Client detected - have fun! Server stops when the game closes." -ForegroundColor Green
    while ($true) {
      while (ClientRunning) { Start-Sleep -Seconds 3 }
      # grace: client must stay gone ~20s
      $gone = $true
      for ($i = 0; $i -lt 4; $i++) {
        Start-Sleep -Seconds 5
        if (ClientRunning) { $gone = $false; break }
      }
      if ($gone) { break }
      Log "client reappeared; resuming watch"
    }
    Write-Host "  Client closed - shutting the server down..." -ForegroundColor Yellow
    Stop-Server
  } else {
    Write-Host "  No client detected - keeping server up for 3 hours (Stay would avoid this timeout)." -ForegroundColor Yellow
    $idleUntil = (Get-Date).AddHours(3)
    while ((Get-Date) -lt $idleUntil) {
      if (ClientRunning) {
        Write-Host "  Client appeared late - switching to watch until exit." -ForegroundColor Green
        while ($true) {
          while (ClientRunning) { Start-Sleep -Seconds 3 }
          $gone = $true
          for ($i = 0; $i -lt 4; $i++) {
            Start-Sleep -Seconds 5
            if (ClientRunning) { $gone = $false; break }
          }
          if ($gone) { break }
        }
        Stop-Server
        Read-Host "Press Enter to close"
        exit 0
      }
      Start-Sleep -Seconds 30
    }
    Write-Host "  Idle timeout - shutting the server down..." -ForegroundColor Yellow
    Stop-Server
  }
  Read-Host "Press Enter to close"
  exit 0
}

# Stay mode
Log "control mode: stay"
Write-Host "  Stay mode - server keeps running." -ForegroundColor Green
Write-Host "  Press Q then Enter to shut down.  R = client status.  A = switch to auto."
while ($true) {
  $stamp = Get-Date -Format "HH:mm:ss"
  if (ClientRunning) {
    Write-Host "  [$stamp] client: running  -  Q=shutdown  R=refresh  A=auto"
  } else {
    Write-Host "  [$stamp] client: not detected  -  server still up  -  Q=shutdown  R=refresh"
  }
  $cmd = Read-Host "  >"
  if ([string]::IsNullOrWhiteSpace($cmd)) { continue }
  switch ($cmd.Trim().ToUpperInvariant()) {
    { $_ -in @("Q", "QUIT", "STOP", "EXIT", "SHUTDOWN") } {
      Write-Host "  Shutdown requested..." -ForegroundColor Yellow
      Stop-Server
      Read-Host "Press Enter to close"
      exit 0
    }
    { $_ -in @("R", "STATUS") } { continue }
    { $_ -in @("A", "AUTO") } {
      Write-Host "  Switching to Auto is only available at startup - use Q then relaunch, or keep Stay." -ForegroundColor DarkYellow
    }
    default { Write-Host "  Q = shutdown, R = refresh" -ForegroundColor Yellow }
  }
}
