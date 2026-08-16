# run_all.ps1 - 运行 Py/examples 下所有 Python 演示程序，完整输出状态
# 用法：在 Py 目录下执行 .\run_all.ps1

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------- 设置环境变量 ----------
$env:PYTHONPATH = $scriptDir
$env:PATH = "$scriptDir\..\Binary;$env:PATH"

# ---------- 获取所有演示文件（排除 __pycache__） ----------
$examples = Get-ChildItem -Path "$scriptDir\examples" -Filter "*.py" -Recurse |
    Where-Object { $_.Directory.Name -ne "__pycache__" -and $_.FullName -notmatch "\\__pycache__\\" }

$total = $examples.Count
$passed = 0
$failed = 0

Write-Host "`n🚀 运行所有 Python 演示程序 (共 $total 个)" -ForegroundColor Cyan
Write-Host "=========================================`n"

foreach ($ex in $examples) {
    $relPath = $ex.FullName.Substring($scriptDir.Length + 1)
    Write-Host "▶️  $relPath" -ForegroundColor Yellow

    # 运行并捕获退出码，同时输出所有内容到控制台（不屏蔽）
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
}

# ---------- 统计 ----------
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "📊 总计: $total, ✅ 通过: $passed, ❌ 失败: $failed" -ForegroundColor White
if ($failed -eq 0) {
    Write-Host "🎉 全部通过！" -ForegroundColor Green
} else {
    Write-Host "⚠️ 有 $failed 个失败，请检查上述输出。" -ForegroundColor Yellow
}