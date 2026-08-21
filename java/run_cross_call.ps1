# run_cross_call.ps1
# 功能：启动一个 CrossCall（并发客户端）
# 用法：在 PowerShell 中直接运行 .\run_cross_call.ps1
#       客户端运行 10 秒后自动退出。可同时打开多个终端窗口运行多个客户端。

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$JNA_JAR = Join-Path $ScriptDir "lib\jna-5.14.0.jar"
$OUT_DIR = Join-Path $ScriptDir "out"
$DLL_DIR = Resolve-Path (Join-Path $ScriptDir "..\Binary")

# 将动态库目录加入 PATH
$env:PATH = "$env:PATH;$DLL_DIR"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CrossCall (Concurrent Client)" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Dynamic library path: $DLL_DIR"
Write-Host "Starting client on ipc:cross..."
Write-Host "This client will send requests for 10 seconds and then exit." -ForegroundColor Yellow
Write-Host ""

java -cp "$JNA_JAR;$OUT_DIR" demo.CrossCall

# 如果进程异常退出，暂停以便查看错误信息
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ERROR] CrossCall exited with code $LASTEXITCODE" -ForegroundColor Red
    Read-Host "Press Enter to exit"
}