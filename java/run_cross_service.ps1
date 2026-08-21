# run_cross_service.ps1
# 功能：启动 CrossService（服务注册中心）
# 用法：在 PowerShell 中直接运行 .\run_cross_service.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$JNA_JAR = Join-Path $ScriptDir "lib\jna-5.14.0.jar"
$OUT_DIR = Join-Path $ScriptDir "out"
$DLL_DIR = Resolve-Path (Join-Path $ScriptDir "..\Binary")

# 将动态库目录加入 PATH，JNA 会自动搜索
$env:PATH = "$env:PATH;$DLL_DIR"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CrossService (Service Registry)" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Dynamic library path: $DLL_DIR"
Write-Host "Starting service registry on ipc:cross..."
Write-Host "Press Ctrl+C to stop this service." -ForegroundColor Yellow
Write-Host ""

java -cp "$JNA_JAR;$OUT_DIR" demo.CrossService

# 如果进程异常退出，暂停以便查看错误信息
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ERROR] CrossService exited with code $LASTEXITCODE" -ForegroundColor Red
    Read-Host "Press Enter to exit"
}# run_cross_service.ps1
# 功能：启动 CrossService（服务注册中心）
# 用法：在 PowerShell 中直接运行 .\run_cross_service.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$JNA_JAR = Join-Path $ScriptDir "lib\jna-5.14.0.jar"
$OUT_DIR = Join-Path $ScriptDir "out"
$DLL_DIR = Resolve-Path (Join-Path $ScriptDir "..\Binary")

# 将动态库目录加入 PATH，JNA 会自动搜索
$env:PATH = "$env:PATH;$DLL_DIR"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CrossService (Service Registry)" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Dynamic library path: $DLL_DIR"
Write-Host "Starting service registry on ipc:cross..."
Write-Host "Press Ctrl+C to stop this service." -ForegroundColor Yellow
Write-Host ""

java -cp "$JNA_JAR;$OUT_DIR" demo.CrossService

# 如果进程异常退出，暂停以便查看错误信息
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ERROR] CrossService exited with code $LASTEXITCODE" -ForegroundColor Red
    Read-Host "Press Enter to exit"
}