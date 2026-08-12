# EVE Online (EvEJS) - stop docker stack (compose stop, keep volumes)
$ErrorActionPreference = "Continue"
$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$EVEJS_ROOT = if ($env:EVEJS_ROOT) { $env:EVEJS_ROOT } else { Join-Path $HomeDir "evejs-xeve" }
$FromLauncher = ($args -contains "--from-launcher")

function Die($msg) {
  Write-Host "ERROR: $msg" -ForegroundColor Red
  if (-not $FromLauncher) { Read-Host "Press Enter to close" }
  exit 1
}

if (Get-Process -Name "exefile" -ErrorAction SilentlyContinue) {
  Write-Host "EVE client is still running. Close the game first." -ForegroundColor Yellow
  if (-not $FromLauncher) { Read-Host "Press Enter to close" }
  exit 1
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Die "docker not found" }
if (-not (Test-Path $EVEJS_ROOT)) { Die "missing $EVEJS_ROOT" }

Set-Location $EVEJS_ROOT
$running = docker compose ps --status running -q 2>$null
if (-not $running) {
  Write-Host "EvE server is already stopped."
  if (-not $FromLauncher) { Read-Host "Press Enter to close" }
  exit 0
}

Write-Host "Stopping EvE server (preserving volumes)..."
docker compose stop -t 60
if ($LASTEXITCODE -ne 0) { Die "docker compose stop failed" }
Write-Host "EvE server stopped." -ForegroundColor Green
if (-not $FromLauncher) { Read-Host "Press Enter to close" }
