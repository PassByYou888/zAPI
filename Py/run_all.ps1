# run_all.ps1 - 运行 Py/examples 下所有 Python 演示程序，完整输出状态
# 用法：在 Py 目录下执行 .\run_all.ps1

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) {
    $scriptDir = (Get-Location).Path
}

# ---------- 设置 PYTHONPATH（确保 api_hub 包可导入） ----------
$env:PYTHONPATH = $scriptDir
Write-Host "设置 PYTHONPATH = $env:PYTHONPATH" -ForegroundColor Cyan

# ---------- 不修改 PATH（_native.py 自动处理） ----------

# ---------- 检查 Python 是否可用 ----------
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    Write-Host "❌ 错误：找不到 python 命令，请确保 Python 已安装并在 PATH 中。" -ForegroundColor Red
    exit 1
}

# ---------- 辅助函数：在后台运行 demo_server，等待就绪，返回作业对象 ----------
function Start-DemoServer {
    $serverScript = Join-Path $scriptDir "examples\client_server\demo_server.py"
    if (-not (Test-Path $serverScript)) {
        Write-Host "⚠️ 找不到 demo_server.py，跳过自动启动" -ForegroundColor Yellow
        return $null
    }
    Write-Host "🔄 正在启动 demo_server.py 作为后台服务..." -ForegroundColor Magenta
    $job = Start-Job -ScriptBlock {
        param($scriptPath)
        python $scriptPath
    } -ArgumentList $serverScript
    # 等待服务就绪（简单等待 2 秒，实际可检查日志）
    Start-Sleep -Seconds 2
    return $job
}

function Stop-DemoServer {
    param($job)
    if ($job -and ($job.State -eq 'Running')) {
        Write-Host "🛑 正在停止 demo_server 后台作业..." -ForegroundColor Magenta
        Stop-Job $job
        Receive-Job $job  # 输出日志
        Remove-Job $job
    }
}

# ---------- 获取所有演示文件（排除 __pycache__） ----------
$examples = Get-ChildItem -Path "$scriptDir\examples" -Filter "*.py" -Recurse |
    Where-Object { $_.Directory.Name -ne "__pycache__" -and $_.FullName -notmatch "\\__pycache__\\" }

$total = $examples.Count
$passed = 0
$failed = 0
$demoServerJob = $null

Write-Host "`n🚀 运行所有 Python 演示程序 (共 $total 个)" -ForegroundColor Cyan
Write-Host "=========================================`n"

foreach ($ex in $examples) {
    $relPath = $ex.FullName.Substring($scriptDir.Length + 1)
    Write-Host "▶️  $relPath" -ForegroundColor Yellow

    # ---------- 特殊处理 demo_client.py ----------
    if ($ex.Name -eq "demo_client.py") {
        # 如果 demo_server 尚未启动，则启动它
        if (-not $demoServerJob) {
            $demoServerJob = Start-DemoServer
        }
    }

    # 运行当前脚本
    & python $ex.FullName
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host "   ✅ 成功 (退出码: 0)" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "   ❌ 失败 (退出码: $exitCode)" -ForegroundColor Red
        $failed++
    }
    Write-Host ""  # 空行分隔

    # ---------- 特殊处理：如果是 demo_server.py，不立即停止，继续运行 ----------
    # 但我们在最后统一停止，避免重复启动
}

# ---------- 在所有示例运行完后，停止 demo_server（如果还在运行） ----------
if ($demoServerJob) {
    Stop-DemoServer -job $demoServerJob
}

# ---------- 统计 ----------
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "📊 总计: $total, ✅ 通过: $passed, ❌ 失败: $failed" -ForegroundColor White
if ($failed -eq 0) {
    Write-Host "🎉 全部通过！" -ForegroundColor Green
} else {
    Write-Host "⚠️ 有 $failed 个失败，请检查上述输出。" -ForegroundColor Yellow
}