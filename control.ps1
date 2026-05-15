# EveBox 统一控制脚本 (PowerShell)
# 用法:
#   powershell -ExecutionPolicy Bypass -File control.ps1 start
#   powershell -ExecutionPolicy Bypass -File control.ps1 stop
#   powershell -ExecutionPolicy Bypass -File control.ps1 status
#   powershell -ExecutionPolicy Bypass -File control.ps1         (交互式菜单)

param([string]$Action = "")

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$ES_HOME = "$Root\elasticsearch\elasticsearch-7.17.28"
$ES_JAVA_HOME = "C:\Program Files\Java\jdk-17.0.18"
$EVEBOX_EXE = "$Root\target\debug\evebox.exe"
$EVEBOX_DATA = "$Root\data"
$EVE_OUTPUT = "$EVEBOX_DATA\suricata-eve.json"
$ES_URL = "http://localhost:9200"
$EVEBOX_PORT = 5636
$EVEBOX_URL = "http://localhost:$EVEBOX_PORT"

function Write-Banner($text) {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Test-Port($port) {
    try {
        $conn = [System.Net.Sockets.TcpClient]::new("127.0.0.1", $port)
        $conn.Close(); $conn.Dispose()
        return $true
    } catch {
        return $false
    }
}

function Start-Elasticsearch {
    if (Test-Port 9200) {
        Write-Host "[ES] Elasticsearch 已在运行 (localhost:9200)" -ForegroundColor Green
        return $true
    }
    Write-Host "[ES] 启动 Elasticsearch..." -ForegroundColor Yellow
    if (-not (Test-Path "$ES_HOME\bin\elasticsearch.bat")) {
        Write-Host "[ES] ERROR: 未找到 Elasticsearch: $ES_HOME" -ForegroundColor Red
        return $false
    }
    $env:ES_JAVA_HOME = $ES_JAVA_HOME
    $env:JAVA_HOME = $ES_JAVA_HOME
    $proc = Start-Process -FilePath "$ES_HOME\bin\elasticsearch.bat" -WindowStyle Minimized -PassThru

    Write-Host "[ES] 等待 Elasticsearch 就绪..." -ForegroundColor Gray
    for ($i = 0; $i -lt 40; $i++) {
        if (Test-Port 9200) {
            $info = Invoke-RestMethod -Uri $ES_URL -TimeoutSec 5 -ErrorAction SilentlyContinue
            Write-Host "[ES] 就绪: $($info.version.number), cluster=$($info.cluster_name)" -ForegroundColor Green
            return $true
        }
        Start-Sleep -Seconds 3
    }
    Write-Host "[ES] ERROR: ES 启动超时" -ForegroundColor Red
    return $false
}

function Start-SuricataSimulator {
    $sim = Get-Process -Name "python" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*Suricata*" }
    if ($sim) {
        Write-Host "[Suricata] 模拟器已在运行" -ForegroundColor Green
        return $true
    }
    Write-Host "[Suricata] 启动 EVE 事件模拟器..." -ForegroundColor Yellow
    $env:EVE_OUTPUT = $EVE_OUTPUT
    $env:EVE_INTERVAL = "1.5"
    Start-Process -FilePath "python" -ArgumentList "tools\suricata_simulator.py" -WindowStyle Minimized
    Start-Sleep -Seconds 2
    if (Test-Path $EVE_OUTPUT) {
        $count = (Get-Content $EVE_OUTPUT | Measure-Object -Line).Lines
        Write-Host "[Suricata] 模拟器已启动，当前事件数: $count" -ForegroundColor Green
    }
    return $true
}

function Start-EveBox {
    # 找空闲端口
    $port = $EVEBOX_PORT
    if (Test-Port $port) {
        Write-Host "[EveBox] 端口 $port 被占用，尝试其他端口..." -ForegroundColor Yellow
        for ($p = 5637; $p -lt 5650; $p++) {
            if (-not (Test-Port $p)) {
                $port = $p
                $script:EVEBOX_PORT = $p
                $script:EVEBOX_URL = "http://localhost:$p"
                break
            }
        }
    }
    Write-Host "[EveBox] 启动 (端口 $port, ES 后端)..." -ForegroundColor Yellow
    $args = @(
        "server",
        "--datastore", "elasticsearch",
        "--no-auth", "--no-tls",
        "-D", $EVEBOX_DATA,
        "-e", $ES_URL,
        "-i", "evebox",
        "--input", $EVE_OUTPUT,
        "-p", $port
    )
    $proc = Start-Process -FilePath $EVEBOX_EXE -ArgumentList $args -WindowStyle Minimized -PassThru
    Write-Host "[EveBox] 等待就绪..." -ForegroundColor Gray
    for ($i = 0; $i -lt 20; $i++) {
        if (Test-Port $port) {
            Start-Sleep -Seconds 2
            Write-Host "[EveBox] 就绪: http://localhost:$port" -ForegroundColor Green
            return $true
        }
        Start-Sleep -Seconds 1
    }
    Write-Host "[EveBox] ERROR: 启动超时" -ForegroundColor Red
    return $false
}

function Stop-Elasticsearch {
    Write-Host "[ES] 停止 Elasticsearch..." -ForegroundColor Yellow
    $procs = Get-Process -Name "java" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*elasticsearch*" }
    if ($procs) {
        $procs | Stop-Process -Force
        Write-Host "[ES] 已停止" -ForegroundColor Green
    } else {
        Write-Host "[ES] 无运行中的进程" -ForegroundColor Gray
    }
    Start-Sleep -Seconds 2
}

function Stop-SuricataSimulator {
    Write-Host "[Suricata] 停止模拟器..." -ForegroundColor Yellow
    $procs = Get-Process -Name "python" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*suricata_simulator*" }
    if ($procs) {
        $procs | Stop-Process -Force
        Write-Host "[Suricata] 已停止" -ForegroundColor Green
    } else {
        Write-Host "[Suricata] 无运行中的进程" -ForegroundColor Gray
    }
}

function Stop-EveBox {
    Write-Host "[EveBox] 停止..." -ForegroundColor Yellow
    $procs = Get-Process -Name "evebox" -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force
        Write-Host "[EveBox] 已停止" -ForegroundColor Green
    } else {
        Write-Host "[EveBox] 无运行中的进程" -ForegroundColor Gray
    }
    Remove-Item "$EVEBOX_DATA\*.bookmark" -ErrorAction SilentlyContinue
}

function Show-Status {
    Write-Banner "EveBox 系统状态"

    $es = Test-Port 9200
    Write-Host "  Elasticsearch : " -NoNewline
    if ($es) {
        $info = Invoke-RestMethod -Uri $ES_URL -TimeoutSec 3 -ErrorAction SilentlyContinue
        Write-Host "运行中 ($($info.version.number), docs: $((Invoke-RestMethod "$ES_URL/_cat/count/evebox*?format=json" -TimeoutSec 3).count))" -ForegroundColor Green
    } else {
        Write-Host "未运行" -ForegroundColor Red
    }

    $ebPort = $null
    foreach ($p in @($EVEBOX_PORT, 15636, 15637, 15638, 5637, 5638, 5639)) {
        if (Test-Port $p) {
            try {
                $config = Invoke-RestMethod "http://localhost:$p/api/config" -TimeoutSec 3
                if ($config.datastore -eq "elasticsearch") {
                    $ebPort = $p
                    break
                }
            } catch {}
        }
    }
    Write-Host "  EveBox        : " -NoNewline
    if ($ebPort) {
        Write-Host "运行中 (端口 $ebPort, $((Invoke-RestMethod "http://localhost:$ebPort/api/config" -TimeoutSec 3).datastore))" -ForegroundColor Green
    } else {
        Write-Host "未运行" -ForegroundColor Red
    }

    $sim = Test-Path $EVE_OUTPUT
    Write-Host "  Suricata 模拟器: " -NoNewline
    if ($sim) {
        $count = (Get-Content $EVE_OUTPUT -ErrorAction SilentlyContinue | Measure-Object -Line).Lines
        Write-Host "数据文件存在 ($count 条事件)" -ForegroundColor Green
    } else {
        Write-Host "数据文件不存在" -ForegroundColor Red
    }
    Write-Host ""
}

# ====== 主逻辑 ======
switch ($Action) {
    "start" {
        Write-Banner "EveBox 一键启动"
        $ok = $true
        if (-not (Start-Elasticsearch)) { $ok = $false }
        if (-not (Start-SuricataSimulator)) { $ok = $false }
        if (-not (Start-EveBox)) { $ok = $false }
        if ($ok) {
            Write-Banner "全部组件已启动!"
            Write-Host "  Elasticsearch : $ES_URL" -ForegroundColor Cyan
            Write-Host "  EveBox        : $EVEBOX_URL" -ForegroundColor Cyan
            Write-Host "  Suricata 数据  : $EVE_OUTPUT" -ForegroundColor Cyan
            Start-Process $EVEBOX_URL
        } else {
            Write-Host "部分组件启动失败，请检查日志" -ForegroundColor Red
        }
    }
    "stop" {
        Write-Banner "EveBox 一键停止"
        Stop-EveBox
        Stop-SuricataSimulator
        Stop-Elasticsearch
        Start-Sleep -Seconds 2
        Write-Banner "所有组件已停止"
    }
    "restart" {
        & $MyInvocation.MyCommand.Path -Action "stop"
        Start-Sleep -Seconds 3
        & $MyInvocation.MyCommand.Path -Action "start"
    }
    "status" {
        Show-Status
    }
    default {
        Write-Banner "EveBox 控制面板"
        Write-Host ""
        Write-Host "  1. 启动所有组件 (start)"
        Write-Host "  2. 停止所有组件 (stop)"
        Write-Host "  3. 重启所有组件 (restart)"
        Write-Host "  4. 查看状态     (status)"
        Write-Host "  q. 退出"
        Write-Host ""
        $choice = Read-Host "请选择"
        switch ($choice) {
            "1" { & $MyInvocation.MyCommand.Path -Action "start" }
            "2" { & $MyInvocation.MyCommand.Path -Action "stop" }
            "3" { & $MyInvocation.MyCommand.Path -Action "restart" }
            "4" { & $MyInvocation.MyCommand.Path -Action "status" }
        }
    }
}
