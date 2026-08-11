# Turtle WoW — Windows native client launcher
$ErrorActionPreference = "Continue"
$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$ClientRoot = if ($env:TW_CLIENT) { $env:TW_CLIENT } else { Join-Path $HomeDir "Games\TurtleWoW\TurtleWoW" }
$WowExe = Join-Path $ClientRoot "WoW.exe"
$Realmlist = Join-Path $ClientRoot "realmlist.wtf"

function Die($msg, $hint = "") {
  Write-Host "ERROR: $msg" -ForegroundColor Red
  if ($hint) { Write-Host "       $hint" -ForegroundColor Yellow }
  Read-Host "Press Enter to close"
  exit 1
}

if (-not (Test-Path $WowExe)) {
  Die "WoW.exe not found: $WowExe" "Was the Turtle client restored from the pack?"
}

# Ensure local realmlist
if (Test-Path $Realmlist) {
  $text = Get-Content $Realmlist -Raw
  if ($text -notmatch 'set realmlist 127\.0\.0\.1') {
    Write-Host "Updating realmlist.wtf -> 127.0.0.1"
    # Remove leading spaces (Turtle disconnects if realmlist line is indented)
    $new = ($text -split "`n" | ForEach-Object {
      if ($_ -match 'realmlist') { "set realmlist 127.0.0.1" } else { $_.TrimEnd() }
    }) -join "`r`n"
    if ($new -notmatch 'set realmlist 127\.0\.0\.1') {
      $new = "set realmlist 127.0.0.1`r`n"
    }
    Set-Content -Path $Realmlist -Value $new -Encoding ascii
  }
} else {
  Set-Content -Path $Realmlist -Value "set realmlist 127.0.0.1`r`n" -Encoding ascii
}

Write-Host "Starting Turtle WoW from $ClientRoot"
Start-Process -FilePath $WowExe -WorkingDirectory $ClientRoot
