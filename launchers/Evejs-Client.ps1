# EVE Online (EvEJS) — Windows native client launcher
$ErrorActionPreference = "Continue"
$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$EVEJS_ROOT = if ($env:EVEJS_ROOT) { $env:EVEJS_ROOT } else { Join-Path $HomeDir "evejs-xeve" }
$CLIENT_ROOT = if ($env:EVEJS_CLIENT_ROOT) { $env:EVEJS_CLIENT_ROOT } else { Join-Path $HomeDir "Games\EVE Online - 3396210" }
$PROXY_URL = if ($env:EVEJS_PROXY_URL) { $env:EVEJS_PROXY_URL } else { "http://127.0.0.1:26002" }
$LogDir = Join-Path $HomeDir "evejs-logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("client-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

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

Log "=== EvEJS Windows client ==="
Log "client=$CLIENT_ROOT"

try {
  $null = Invoke-WebRequest -Uri "$PROXY_URL/health" -UseBasicParsing -TimeoutSec 5
} catch {
  Die "The EVE server is not running." "Launch `"EVE Online Server`" first, wait for READY, then start the game."
}
Log "server proxy OK"

$ClientExe = Join-Path $CLIENT_ROOT "tq\bin64\exefile.exe"
$BlueDll   = Join-Path $CLIENT_ROOT "tq\bin64\blue.dll"
$StartIni  = Join-Path $CLIENT_ROOT "tq\start.ini"
$ResFiles  = Join-Path $CLIENT_ROOT "ResFiles"
$IndexTq   = Join-Path $CLIENT_ROOT "index_tranquility.txt"
$CaPem     = Join-Path $EVEJS_ROOT "server\certs\xmpp-ca-cert.pem"

if (-not (Test-Path $ClientExe)) { Die "exefile.exe not found: $ClientExe" "Was the client member restored?" }
if (-not (Test-Path $BlueDll))   { Die "blue.dll not found: $BlueDll" }
if (-not (Test-Path $StartIni))  { Die "start.ini not found: $StartIni" }
if (-not (Test-Path $ResFiles))  { Die "ResFiles not found: $ResFiles" }
if (-not (Test-Path $IndexTq))   { Die "index_tranquility.txt not found: $IndexTq" }

$ini = Get-Content $StartIni -Raw
if ($ini -notmatch '(?im)^\s*server\s*=\s*127\.0\.0\.1') {
  Die "start.ini server is not 127.0.0.1" "Edit tq\start.ini"
}
if ($ini -notmatch '(?im)^\s*cryptoPack\s*=\s*Placebo') {
  Die "start.ini cryptoPack is not Placebo" "Edit tq\start.ini"
}
Log "start.ini OK"

if (-not (Test-Path $CaPem)) {
  Die "CA missing: $CaPem" "Start the server once so it generates certificates."
}

# Install local CA into client certifi bundles (Python, no openssl required for subject filter best-effort)
$caInstaller = Join-Path $HomeDir "evejs-install-ca.py"
if (Test-Path $caInstaller) {
  Log "installing local CA into client cert bundles"
  python $caInstaller --client-root $CLIENT_ROOT --ca $CaPem 2>&1 | Tee-Object -FilePath $LogFile -Append
  if ($LASTEXITCODE -ne 0) {
    Log "WARNING: CA install returned $LASTEXITCODE — login may fail TLS"
  }
} else {
  Log "WARNING: evejs-install-ca.py not found at $caInstaller"
}

Log "starting $ClientExe"
$work = Join-Path $CLIENT_ROOT "tq\bin64"
Start-Process -FilePath $ClientExe -WorkingDirectory $work
Log "client process started"
Start-Sleep -Seconds 2
