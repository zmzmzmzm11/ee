# EveBox Stop-All Script (PowerShell)
# Usage: .\stop-all.ps1
# Stops all components from both start-all.ps1 and start-all1.ps1

# Auto-elevate to admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  EveBox - Stop All Components" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

# 1. Stop EveBox
Write-Host "`n[1/4] Stopping EveBox..." -ForegroundColor Yellow
$p = Get-Process evebox -ErrorAction SilentlyContinue
if ($p) {
    $p | Stop-Process -Force
    Write-Host "  Stopped" -ForegroundColor Green
} else {
    Write-Host "  Not running" -ForegroundColor Gray
}

# 2. Stop Suricata
Write-Host "[2/4] Stopping Suricata..." -ForegroundColor Yellow
$p = Get-Process suricata -ErrorAction SilentlyContinue
if ($p) {
    $p | Stop-Process -Force
    Write-Host "  Stopped" -ForegroundColor Green
} else {
    Write-Host "  Not running" -ForegroundColor Gray
}

# 3. Stop Suricata Simulator (all Python)
Write-Host "[3/4] Stopping Simulator..." -ForegroundColor Yellow
Get-Process python -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host "  Done" -ForegroundColor Green

# 4. Stop Elasticsearch
Write-Host "[4/4] Stopping Elasticsearch..." -ForegroundColor Yellow
$p = Get-Process java -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*elasticsearch*" }
if ($p) {
    $p | Stop-Process -Force
    Write-Host "  Stopped" -ForegroundColor Green
} else {
    Write-Host "  Not running" -ForegroundColor Gray
}

# Cleanup
Remove-Item "$Root\data\*.bookmark" -ErrorAction SilentlyContinue

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  All Components Stopped" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

Start-Sleep -Seconds 2
