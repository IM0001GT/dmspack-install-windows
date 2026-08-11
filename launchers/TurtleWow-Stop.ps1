# Turtle WoW V2 — stop compose stack (keep volumes)
$ErrorActionPreference = "Continue"
$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$STACK_DIR = if ($env:TW2_ROOT) { $env:TW2_ROOT } else { Join-Path $HomeDir "tortoise-wow-server-V2" }
$FromLauncher = ($args -contains "--from-launcher")

if (Get-Process -Name "WoW" -ErrorAction SilentlyContinue) {
  Write-Host "WoW is still running. Close the game first." -ForegroundColor Yellow
  if (-not $FromLauncher) { Read-Host "Press Enter to close" }
  exit 1
}
if (-not (Test-Path $STACK_DIR)) {
  Write-Host "missing $STACK_DIR"
  exit 1
}
Set-Location $STACK_DIR
Write-Host "Stopping Turtle WoW V2 (up to 120s for DB flush)..."
docker compose stop -t 120
Write-Host "Done."
if (-not $FromLauncher) { Read-Host "Press Enter to close" }
