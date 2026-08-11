# Turtle WoW V2 — Windows server launcher (Docker Compose)
$ErrorActionPreference = "Continue"
$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$STACK_DIR = if ($env:TW2_ROOT) { $env:TW2_ROOT } else { Join-Path $HomeDir "tortoise-wow-server-V2" }
$WORLD_PORT = 8095
$AUTH_PORT = 3724
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

Log "=== Turtle WoW V2 Windows server ==="
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Die "docker not found on PATH. Install Docker Desktop."
}
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Die "Docker is not responding. Start Docker Desktop." }
if (-not (Test-Path $STACK_DIR)) { Die "Cannot find $STACK_DIR — was the DML pack restored?" }

# V1 conflict on 3724
$v1 = docker ps --filter "name=tortoise-realmd" --format "{{.Names}}" 2>$null
if ($v1) {
  Die "Turtle WoW V1 appears to be running (owns port $AUTH_PORT)." "Stop V1 first."
}

Set-Location $STACK_DIR
Log "Starting docker compose in $STACK_DIR"
docker compose up -d 2>&1 | Tee-Object -FilePath $LogFile -Append
if ($LASTEXITCODE -ne 0) {
  Die "docker compose failed" "Check: docker compose -f `"$STACK_DIR\docker-compose.yml`" logs"
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
Write-Host "  Account : mmodad / pass1234   (typical pack default — check handoff doc)"
Write-Host "  Realm   : 127.0.0.1 : $WORLD_PORT"
Write-Host "  Now launch the Turtle WoW client."
Write-Host "  Log     : $LogFile"
Write-Host ""
Read-Host "Press Enter to close this window (server keeps running)"
