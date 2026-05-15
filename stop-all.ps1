# EveBox Stop-All Script (PowerShell)
# Usage: .\stop-all.ps1

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  EveBox - Stop All Components" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

# 1. Stop EveBox
Write-Host "`n[1/3] Stopping EveBox..." -ForegroundColor Yellow
$p = Get-Process evebox -ErrorAction SilentlyContinue
if ($p) {
    $p | Stop-Process -Force
    Write-Host "  Stopped ($($p.Count) processes)" -ForegroundColor Green
} else {
    Write-Host "  No running EveBox process" -ForegroundColor Gray
}

# 2. Stop Suricata Simulator
Write-Host "[2/3] Stopping Suricata Simulator..." -ForegroundColor Yellow
$p = Get-Process python -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*suricata_simulator*" }
if ($p) {
    $p | Stop-Process -Force
    Write-Host "  Stopped" -ForegroundColor Green
} else {
    Write-Host "  No running simulator process" -ForegroundColor Gray
}

# 3. Stop Elasticsearch
Write-Host "[3/3] Stopping Elasticsearch..." -ForegroundColor Yellow
$p = Get-Process java -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*elasticsearch*" }
if ($p) {
    $p | Stop-Process -Force
    Write-Host "  Stopped (PID: $($p.Id -join ', '))" -ForegroundColor Green
} else {
    Write-Host "  No running Elasticsearch process" -ForegroundColor Gray
}

# Cleanup
Remove-Item "$Root\data\*.bookmark" -ErrorAction SilentlyContinue

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  All Components Stopped" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

Start-Sleep -Seconds 2
