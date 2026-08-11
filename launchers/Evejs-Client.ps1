# EVE Online (EvEJS) — Windows native client launcher (localhost OR LAN host)
# Reads server host from (first match):
#   1) $env:EVEJS_SERVER_HOST / $env:EVEJS_PROXY_URL
#   2) %USERPROFILE%\_local\lan-play\evejs-client.env or %USERPROFILE%\DML-Launchers\evejs-client.env
#   3) tq\start.ini "server =" line
#   4) 127.0.0.1 (local play)
$ErrorActionPreference = "Continue"
$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }

function Log($msg) {
  $line = "{0:HH:mm:ss}  {1}" -f (Get-Date), $msg
  Write-Host $line
  if ($script:LogFile) { Add-Content -Path $script:LogFile -Value $line }
}
function Die($msg, $hint = "") {
  Write-Host "ERROR: $msg" -ForegroundColor Red
  if ($hint) { Write-Host "       $hint" -ForegroundColor Yellow }
  if ($script:LogFile) {
    Add-Content -Path $script:LogFile -Value "ERROR: $msg"
    if ($hint) { Add-Content -Path $script:LogFile -Value "HINT: $hint" }
  }
  Read-Host "Press Enter to close"
  exit 1
}

function Import-EnvFile([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return }
  Get-Content -LiteralPath $path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) { return }
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
      $k = $Matches[1]
      $v = $Matches[2].Trim().Trim('"')
      if (-not [string]::IsNullOrWhiteSpace($v)) {
        Set-Item -Path "Env:$k" -Value $v
      }
    }
  }
  Log "loaded env: $path"
}

# Optional env from lan-play client configure
@(
  (Join-Path $HomeDir "_local\lan-play\evejs-client.env"),
  (Join-Path $HomeDir "DML-Launchers\evejs-client.env"),
  (Join-Path $PSScriptRoot "evejs-client.env")
) | ForEach-Object { Import-EnvFile $_ }

$EVEJS_ROOT = if ($env:EVEJS_ROOT) { $env:EVEJS_ROOT } else { Join-Path $HomeDir "evejs-xeve" }
$CLIENT_ROOT = if ($env:EVEJS_CLIENT_ROOT) { $env:EVEJS_CLIENT_ROOT } else { Join-Path $HomeDir "Games\EVE Online - 3396210" }

$LogDir = Join-Path $HomeDir "evejs-logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$script:LogFile = Join-Path $LogDir ("client-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

Log "=== EvEJS Windows client ==="
Log "client=$CLIENT_ROOT"

$ClientExe = Join-Path $CLIENT_ROOT "tq\bin64\exefile.exe"
$BlueDll   = Join-Path $CLIENT_ROOT "tq\bin64\blue.dll"
$StartIni  = Join-Path $CLIENT_ROOT "tq\start.ini"
$ResFiles  = Join-Path $CLIENT_ROOT "ResFiles"
$IndexTq   = Join-Path $CLIENT_ROOT "index_tranquility.txt"

if (-not (Test-Path $ClientExe)) { Die "exefile.exe not found: $ClientExe" "Set EVEJS_CLIENT_ROOT to your client folder." }
if (-not (Test-Path $BlueDll))   { Die "blue.dll not found: $BlueDll" }
if (-not (Test-Path $StartIni))  { Die "start.ini not found: $StartIni" }
if (-not (Test-Path $ResFiles))  { Die "ResFiles not found: $ResFiles" }
if (-not (Test-Path $IndexTq))   { Die "index_tranquility.txt not found: $IndexTq" }

# Parse start.ini
$iniServer = $null
$iniCrypto = $null
$iniPort = "26000"
Get-Content -LiteralPath $StartIni | ForEach-Object {
  $line = $_ -replace '\r', ''
  if ($line -match '(?i)^\s*(server|serverip)\s*=\s*(.+)$') {
    $iniServer = $Matches[2].Trim()
  } elseif ($line -match '(?i)^\s*cryptopack\s*=\s*(.+)$') {
    $iniCrypto = $Matches[2].Trim()
  } elseif ($line -match '(?i)^\s*port\s*=\s*(.+)$') {
    $iniPort = $Matches[2].Trim()
  }
}

# Resolve host: env wins, else start.ini, else localhost
$ServerHost = $null
if ($env:EVEJS_SERVER_HOST) { $ServerHost = $env:EVEJS_SERVER_HOST.Trim() }
elseif ($iniServer) { $ServerHost = $iniServer }
else { $ServerHost = "127.0.0.1" }

if ($env:EVEJS_PROXY_URL) {
  $PROXY_URL = $env:EVEJS_PROXY_URL.Trim().TrimEnd('/')
} else {
  $PROXY_URL = "http://${ServerHost}:26002"
}

Log "server host = $ServerHost"
Log "proxy URL   = $PROXY_URL"
Log "start.ini   = server=$iniServer cryptoPack=$iniCrypto port=$iniPort"

if (-not $iniCrypto -or $iniCrypto -ine "Placebo") {
  Die "start.ini cryptoPack must be Placebo (found '$iniCrypto')" "Set cryptoPack = Placebo in tq\start.ini"
}

# Health check against the *configured* host (LAN or local)
try {
  $null = Invoke-WebRequest -Uri "$PROXY_URL/health" -UseBasicParsing -TimeoutSec 8
  Log "server proxy OK at $PROXY_URL"
} catch {
  Die "The EVE server is not reachable at $PROXY_URL" `
    "On the HOST PC: start the server (LAN mode if remote). On THIS PC: set start.ini server= to the host LAN IP (or run lan-play.sh client evejs set)."
}

# CA: server tree, or client-local copy for pure client machines
$CaCandidates = @(
  (Join-Path $EVEJS_ROOT "server\certs\xmpp-ca-cert.pem"),
  (Join-Path $CLIENT_ROOT "evejs-ca.pem"),
  (Join-Path $CLIENT_ROOT "tq\evejs-ca.pem"),
  (Join-Path $HomeDir "DML-Launchers\xmpp-ca-cert.pem"),
  (Join-Path $HomeDir "_local\lan-play\xmpp-ca-cert.pem"),
  (Join-Path $PSScriptRoot "xmpp-ca-cert.pem")
)
$CaPem = $CaCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $CaPem) {
  Log "WARNING: CA pem not found — TLS login may fail on LAN"
  Log "Copy host server/certs/xmpp-ca-cert.pem next to this launcher or into the client folder as evejs-ca.pem"
} else {
  Log "CA = $CaPem"
  $caInstaller = @(
    (Join-Path $HomeDir "evejs-install-ca.py"),
    (Join-Path $PSScriptRoot "evejs-install-ca.py"),
    (Join-Path $EVEJS_ROOT "tools\ClientSETUP\scripts\Install-EvEJSCerts.ps1")
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1

  if ($caInstaller -and $caInstaller.EndsWith(".py")) {
    Log "installing CA into client cert bundles"
    & python $caInstaller --client-root $CLIENT_ROOT --ca $CaPem 2>&1 | Tee-Object -FilePath $script:LogFile -Append
    if ($LASTEXITCODE -ne 0) { Log "WARNING: CA install exit $LASTEXITCODE" }
  } elseif ($caInstaller -and $caInstaller.EndsWith(".ps1")) {
    Log "CA helper is Install-EvEJSCerts.ps1 — run ClientSETUP if TLS fails"
  } else {
    # Minimal inline: append CA to cacert.pem files if not already present
    $caText = Get-Content -LiteralPath $CaPem -Raw
    if ($caText -and $caText -match "BEGIN CERTIFICATE") {
      Get-ChildItem -Path $CLIENT_ROOT -Filter cacert.pem -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $bundle = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
        if ($bundle -and $bundle -notmatch "EvEJS Local") {
          $backup = $_.FullName + ".evejs-backup"
          if (-not (Test-Path $backup)) { Copy-Item $_.FullName $backup }
          Add-Content -LiteralPath $_.FullName -Value ("`n" + $caText.Trim() + "`n")
          Log "appended CA to $($_.FullName)"
        }
      }
    }
  }
}

# Ensure start.ini matches resolved host (helps if env was set but ini was stale)
if ($iniServer -ne $ServerHost) {
  Log "updating start.ini server $iniServer -> $ServerHost"
  $raw = Get-Content -LiteralPath $StartIni -Raw
  if ($raw -match '(?im)^\s*(server|serverip)\s*=') {
    $raw = [regex]::Replace($raw, '(?im)^\s*(server|serverip)\s*=.*$', "server = $ServerHost")
  } else {
    $raw = $raw.TrimEnd() + "`r`nserver = $ServerHost`r`n"
  }
  Set-Content -LiteralPath $StartIni -Value $raw -NoNewline
}

Log "starting $ClientExe"
$work = Join-Path $CLIENT_ROOT "tq\bin64"
# Optional proxy env for Python-based HTTPS inside the client
$env:http_proxy = $PROXY_URL
$env:https_proxy = $PROXY_URL
$env:HTTP_PROXY = $PROXY_URL
$env:HTTPS_PROXY = $PROXY_URL
$env:no_proxy = "127.0.0.1,localhost,$ServerHost"
$env:NO_PROXY = $env:no_proxy
if ($CaPem) {
  $env:SSL_CERT_FILE = $CaPem
  $env:REQUESTS_CA_BUNDLE = $CaPem
  $env:CURL_CA_BUNDLE = $CaPem
}

Start-Process -FilePath $ClientExe -WorkingDirectory $work
Log "client process started"
Start-Sleep -Seconds 2
