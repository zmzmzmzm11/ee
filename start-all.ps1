# EveBox Start-All Script (PowerShell)
# Usage: .\start-all.ps1
# Requires: Administrator (auto-elevates)

$ErrorActionPreference = "Continue"

# Auto-elevate to admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting administrator privileges..." -ForegroundColor Yellow
    Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  EveBox - Start All Components" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan

# ====== Check Prerequisites ======
Write-Host "`n[Check] Prerequisites..." -ForegroundColor Gray

$EveBoxExe = "$Root\target\debug\evebox.exe"
if (-not (Test-Path $EveBoxExe)) {
    Write-Host "[ERROR] evebox.exe not found: $EveBoxExe" -ForegroundColor Red
    Write-Host "        Run: cargo build" -ForegroundColor Yellow
    pause; exit 1
}
Write-Host "  evebox.exe ... OK" -ForegroundColor Green

$SimulatorPy = "$Root\tools\suricata_simulator.py"
if (-not (Test-Path $SimulatorPy)) {
    Write-Host "[ERROR] suricata_simulator.py not found" -ForegroundColor Red
    pause; exit 1
}
Write-Host "  suricata_simulator.py ... OK" -ForegroundColor Green

# Java
$java = Get-Command java -ErrorAction SilentlyContinue
if (-not $java) {
    $jdkPath = "C:\Program Files\Java\jdk-17.0.18\bin\java.exe"
    if (Test-Path $jdkPath) {
        $env:JAVA_HOME = "C:\Program Files\Java\jdk-17.0.18"
        $env:PATH = $env:JAVA_HOME + "\bin;" + $env:PATH
        Write-Host "  Java: $jdkPath" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Java not found, ES will be skipped" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Java: $($java.Source)" -ForegroundColor Green
}

# ====== 1. Start Elasticsearch ======
Write-Host "`n[1/3] Elasticsearch..." -ForegroundColor Yellow
$EsHome = "$Root\elasticsearch\elasticsearch-7.17.28"

if (-not (Test-Path "$EsHome\bin\elasticsearch.bat")) {
    Write-Host "  [SKIP] Elasticsearch not found at $EsHome" -ForegroundColor Yellow
} else {
    try {
        $esCheck = Invoke-WebRequest -Uri "http://localhost:9200" -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
        Write-Host "  [SKIP] Already running (localhost:9200)" -ForegroundColor Green
    } catch {
        Write-Host "  Starting Elasticsearch..." -ForegroundColor Gray
        $env:ES_JAVA_HOME = $env:JAVA_HOME
        $esProc = Start-Process -FilePath "$EsHome\bin\elasticsearch.bat" -WindowStyle Minimized -PassThru

        Write-Host "  Waiting for ES to be ready..." -ForegroundColor Gray
        $waited = 0
        do {
            Start-Sleep -Seconds 5
            $waited += 5
            try {
                Invoke-WebRequest -Uri "http://localhost:9200" -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop | Out-Null
                Write-Host "  Elasticsearch ready ($waited s)" -ForegroundColor Green
                break
            } catch {
                if ($waited -ge 120) {
                    Write-Host "  [WARN] ES startup timeout" -ForegroundColor Yellow
                    break
                }
            }
        } while ($true)
    }
}

# ====== 2. Start Suricata ======
Write-Host "`n[2/3] Suricata..." -ForegroundColor Yellow

$SuricataExe = "C:\Program Files\Suricata\suricata.exe"
$SuricataYaml = "C:\Program Files\Suricata\suricata.yaml"
$EveOutput = "C:\Program Files\Suricata\eve.json"

# Get network adapter
$adapter = (Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -First 1).Name
if (-not $adapter) {
    Write-Host "  [ERROR] No active network adapter found" -ForegroundColor Red
    pause; exit 1
}
Write-Host "  Using adapter: $adapter" -ForegroundColor Gray

# Kill old Suricata
Get-Process suricata -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if (-not (Test-Path $SuricataExe)) {
    Write-Host "  [SKIP] Suricata not found at $SuricataExe" -ForegroundColor Yellow
    Write-Host "  Falling back to simulator..." -ForegroundColor Gray
    $EveOutput = "$Root\data\suricata-eve.json"
    if (-not (Test-Path "$Root\data")) { New-Item -Path "$Root\data" -ItemType Directory -Force | Out-Null }
    Start-Process -FilePath "python" -ArgumentList $SimulatorPy -WindowStyle Minimized
} else {
    if (-not (Test-Path "$Root\data")) { New-Item -Path "$Root\data" -ItemType Directory -Force | Out-Null }

    Write-Host "  Starting Suricata on $adapter..." -ForegroundColor Gray
    Start-Process -FilePath $SuricataExe -ArgumentList "-c", $SuricataYaml, "-i", $adapter -WindowStyle Minimized

    Write-Host "  Waiting for Suricata to initialize..." -ForegroundColor Gray
    $waited = 0
    do {
        Start-Sleep -Seconds 3
        $waited += 3
        if (Test-Path $EveOutput) { break }
        if ($waited -ge 30) { break }
    } while ($true)

    if (Test-Path $EveOutput) {
        $count = (Get-Content $EveOutput | Measure-Object -Line).Lines
        Write-Host "  Suricata ready ($waited s), events: $count" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] eve.json not created after ${waited}s" -ForegroundColor Yellow
        Write-Host "  Check: C:\Program Files\Suricata\suricata.log" -ForegroundColor Gray
    }
}

# ====== 3. Start EveBox ======
Write-Host "`n[3/3] EveBox..." -ForegroundColor Yellow

# Kill old EveBox
Get-Process evebox -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Find free port
$port = 5636
for ($p = 5636; $p -lt 5650; $p++) {
    try {
        $c = [System.Net.Sockets.TcpClient]::new("127.0.0.1", $p)
        $c.Close(); $c.Dispose()
    } catch {
        $port = $p
        break
    }
}
Write-Host "  Using port $port" -ForegroundColor Gray

$eveboxArgs = @(
    "server",
    "--datastore", "elasticsearch",
    "--no-tls",
    "-D", "$Root\data",
    "-e", "http://localhost:9200",
    "-i", "evebox",
    "--input", $EveOutput,
    "-p", $port
)
$EveLog = "$Root\data\evebox.log"
$eveboxCmd = "`"$EveBoxExe`" $($eveboxArgs -join ' ') 2>&1"
Start-Process -FilePath "cmd" -ArgumentList "/c", $eveboxCmd -RedirectStandardOutput $EveLog -WindowStyle Minimized

Write-Host "  Waiting for EveBox..." -ForegroundColor Gray
$waited = 0
do {
    Start-Sleep -Seconds 2
    $waited += 2
    # Check for admin password in log
    if (Test-Path $EveLog) {
        $pwLine = Select-String -Path $EveLog -Pattern "username=admin, password=" -SimpleMatch | Select-Object -Last 1
        if ($pwLine) {
            Write-Host "  $pwLine" -ForegroundColor Magenta
        }
    }
    try {
        $ver = Invoke-WebRequest -Uri "http://localhost:$port/api/version" -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
        Write-Host "  EveBox ready ($waited s)" -ForegroundColor Green
        break
    } catch {
        if ($waited -ge 60) {
            Write-Host "  [WARN] EveBox startup timeout" -ForegroundColor Yellow
            break
        }
    }
} while ($true)

# ====== Done ======
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  All Components Started!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Elasticsearch : http://localhost:9200" -ForegroundColor White
Write-Host "  EveBox        : http://localhost:$port" -ForegroundColor White
Write-Host "  EVE Output    : $EveOutput" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan

# Open browser
Start-Process "http://localhost:$port"

pause
