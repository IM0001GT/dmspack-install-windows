# Turtle WoW V2 — Windows server launcher with interactive control
$ErrorActionPreference = "Continue"
$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$STACK_DIR = if ($env:TW2_ROOT) { $env:TW2_ROOT } else { Join-Path $HomeDir "tortoise-wow-server-V2" }
$WORLD_PORT = 8095
$AUTH_PORT = 3724
$ClientProcessNames = @("WoW")
$LogFile = Join-Path $HomeDir "tortoise-wow-v2-launcher.log"

function Log($msg) {
  $line = "{0:HH:mm:ss}  {1}" -f (Get-Date), $msg
  Write-Host $line
  Add-Content -Path $LogFile -Value $line
}
function Die($msg, $hint = "") {
  Write-Host "ERROR: $msg" -ForegroundColor Red
  if ($hint) { Write-Host "       $hint" -ForegroundColor Yellow }
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
  Log "Stopping Turtle WoW V2 (compose stop -t 120)..."
  Push-Location $STACK_DIR
  try {
    docker compose stop -t 120 2>&1 | Tee-Object -FilePath $LogFile -Append
  } finally {
    Pop-Location
  }
  if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: stop returned $LASTEXITCODE — see $LogFile" -ForegroundColor Yellow
  } else {
    Write-Host "Server stopped. Safe to close this window." -ForegroundColor Green
  }
}

Log "=== Turtle WoW V2 Windows server ==="
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Die "docker not found on PATH. Install Docker Desktop."
}
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Die "Docker is not responding. Start Docker Desktop." }
if (-not (Test-Path $STACK_DIR)) { Die "Cannot find $STACK_DIR — was the pack restored?" }

$v1 = docker ps --filter "name=tortoise-realmd" --format "{{.Names}}" 2>$null
if ($v1) {
  Die "Turtle WoW V1 appears to be running (owns port $AUTH_PORT)." "Stop V1 first."
}

Set-Location $STACK_DIR
Log "Starting docker compose in $STACK_DIR"
docker compose up -d 2>&1 | Tee-Object -FilePath $LogFile -Append
if ($LASTEXITCODE -ne 0) {
  Die "docker compose failed" "Check: docker compose logs"
}
Log "Containers started"

function WorldReady {
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    $iar = $c.BeginConnect("127.0.0.1", $WORLD_PORT, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne(2000, $false)
    if ($ok -and $c.Connected) { $c.Close(); return $true }
    $c.Close()
  } catch {}
  return $false
}

Log "Waiting for world port $WORLD_PORT (playerbot init can take a long time)..."
$deadline = (Get-Date).AddMinutes(45)
while ((Get-Date) -lt $deadline) {
  if (WorldReady) { break }
  Start-Sleep -Seconds 10
  Write-Host -NoNewline "."
}
Write-Host ""
if (-not (WorldReady)) {
  Die "World server never opened port $WORLD_PORT" "Check: docker logs tw2-mangosd"
}
Log "World server accepting connections on $WORLD_PORT"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TURTLE WOW V2 IS READY" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Now launch the Turtle WoW client."
Write-Host "  Log: $LogFile"
Write-Host ""
Write-Host "  Server control" -ForegroundColor White
Write-Host "    A  Auto     — shut down when WoW.exe closes"
Write-Host "    S  Stay     — keep running until you press Q (no client timeout)"
Write-Host "    Q  Shutdown — stop the server now"
Write-Host "    R  Status   — is the client process running?"
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
        Write-Host "  Client process detected (WoW)" -ForegroundColor Green
      } else {
        Write-Host "  No client process right now" -ForegroundColor Yellow
      }
    }
    default { Write-Host "  Unknown choice — pick A, S, Q, or R" -ForegroundColor Yellow }
  }
}

if ($mode -eq "quit") {
  Stop-Server
  Read-Host "Press Enter to close"
  exit 0
}

if ($mode -eq "auto") {
  Log "control mode: auto"
  Write-Host "  Auto mode — waiting for WoW.exe..." -ForegroundColor Cyan
  $waitUntil = (Get-Date).AddMinutes(5)
  $found = $false
  while ((Get-Date) -lt $waitUntil) {
    if (ClientRunning) { $found = $true; break }
    Start-Sleep -Seconds 5
    Write-Host -NoNewline "."
  }
  Write-Host ""
  if ($found) {
    Write-Host "  Client detected — have fun! Server stops when the game closes." -ForegroundColor Green
    while ($true) {
      while (ClientRunning) { Start-Sleep -Seconds 3 }
      $gone = $true
      for ($i = 0; $i -lt 4; $i++) {
        Start-Sleep -Seconds 5
        if (ClientRunning) { $gone = $false; break }
      }
      if ($gone) { break }
      Log "client reappeared; resuming watch"
    }
    Write-Host "  Client closed — shutting the server down..." -ForegroundColor Yellow
    Stop-Server
  } else {
    Write-Host "  No client detected — keeping server up for 3 hours (use Stay to avoid timeout)." -ForegroundColor Yellow
    $idleUntil = (Get-Date).AddHours(3)
    while ((Get-Date) -lt $idleUntil) {
      if (ClientRunning) {
        Write-Host "  Client appeared — watching until exit." -ForegroundColor Green
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
    Write-Host "  Idle timeout — shutting the server down..." -ForegroundColor Yellow
    Stop-Server
  }
  Read-Host "Press Enter to close"
  exit 0
}

Log "control mode: stay"
Write-Host "  Stay mode — server keeps running." -ForegroundColor Green
Write-Host "  Press Q then Enter to shut down.  R = client status."
while ($true) {
  $stamp = Get-Date -Format "HH:mm:ss"
  if (ClientRunning) {
    Write-Host "  [$stamp] client: running  —  Q=shutdown  R=refresh"
  } else {
    Write-Host "  [$stamp] client: not detected  —  server still up  —  Q=shutdown"
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
    default { Write-Host "  Q = shutdown, R = refresh" -ForegroundColor Yellow }
  }
}
