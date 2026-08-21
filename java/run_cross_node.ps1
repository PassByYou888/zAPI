# run_cross_node.ps1
# 功能：启动一个 CrossNode（工作节点）
# 用法：在 PowerShell 中直接运行 .\run_cross_node.ps1
#       可同时打开多个终端窗口运行多个节点实例，实现负载均衡

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$JNA_JAR = Join-Path $ScriptDir "lib\jna-5.14.0.jar"
$OUT_DIR = Join-Path $ScriptDir "out"
$DLL_DIR = Resolve-Path (Join-Path $ScriptDir "..\Binary")

# 将动态库目录加入 PATH
$env:PATH = "$env:PATH;$DLL_DIR"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CrossNode (Worker Node)" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Dynamic library path: $DLL_DIR"
Write-Host "Starting worker node on ipc:cross..."
Write-Host "This node registers 'add' and 'inv_seri' APIs under app 'demo'."
Write-Host "Press Enter to stop this node." -ForegroundColor Yellow
Write-Host ""

java -cp "$JNA_JAR;$OUT_DIR" demo.CrossNode

# 如果进程异常退出，暂停以便查看错误信息
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ERROR] CrossNode exited with code $LASTEXITCODE" -ForegroundColor Red
    Read-Host "Press Enter to exit"
}