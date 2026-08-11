# EVE Online (EvEJS) — Windows server launcher
# Requires: Docker Desktop running (Linux containers)
$ErrorActionPreference = "Continue"
$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$EVEJS_ROOT = if ($env:EVEJS_ROOT) { $env:EVEJS_ROOT } else { Join-Path $HomeDir "evejs-xeve" }
$PROXY_URL = if ($env:EVEJS_PROXY_URL) { $env:EVEJS_PROXY_URL } else { "http://127.0.0.1:26002" }
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
  Die "Cannot find $EVEJS_ROOT — was the DML pack restored?"
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
  docker compose up --detach 2>&1 | Tee-Object -FilePath $LogFile -Append
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
  Die "Backend never became healthy. Check: docker compose -f `"$EVEJS_ROOT\compose.yaml`" logs --tail 100 server"
}
Log "Backend healthy"

try {
  $r = Invoke-WebRequest -Uri "$PROXY_URL/health" -UseBasicParsing -TimeoutSec 10
  if ($r.StatusCode -ge 400) { throw "status $($r.StatusCode)" }
  Log "Client proxy responding at $PROXY_URL"
} catch {
  Die "Client proxy not answering at $PROXY_URL/health — port/bind problem?"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  EVE ONLINE SERVER IS READY" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Login : mmodad  (any password on local)"
Write-Host "  Market: http://127.0.0.1:40110/health"
Write-Host "  Now launch the EVE Online client shortcut."
Write-Host "  Leave this window open if you want to watch logs."
Write-Host "  Log   : $LogFile"
Write-Host ""
Read-Host "Press Enter to close this window (server keeps running)"
