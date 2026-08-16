# check_all.ps1
# 一键检查所有客户端和服务端 Demo 编译状态
# 输出每个 demo 的 PASS/FAIL，并汇总日志
# 自动启用 CGO（跨平台需要）

$ErrorActionPreference = "Continue"

# 强制启用 CGO（必须）
$env:CGO_ENABLED = "1"

$root = "."

# 检查是否在正确的目录
if (-not (Test-Path "api_hub") -or -not (Test-Path "demos")) {
    Write-Host "❌ 请在 GoDemos 根目录（包含 api_hub 和 demos 文件夹）运行此脚本！" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "🔍 全面检查所有 Demo（客户端 + 服务端）" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# 显示环境信息
$goVer = go version
Write-Host "Go 版本: $goVer" -ForegroundColor Gray
$cgo = go env CGO_ENABLED
Write-Host "CGO_ENABLED: $cgo" -ForegroundColor Gray
Write-Host ""

# 整理依赖
Write-Host "📦 执行 go mod tidy..." -ForegroundColor Cyan
go mod tidy

$pass = 0
$fail = 0
$log = ""

# 定义编译测试函数
function Test-Build {
    param($Name, $Path)
    Write-Host "🔨 编译 $Name ..." -ForegroundColor Cyan
    $out = go build -o "$env:TEMP\test_build.exe" $Path 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ PASS" -ForegroundColor Green
        $script:pass++
        Remove-Item "$env:TEMP\test_build.exe" -ErrorAction SilentlyContinue
    } else {
        Write-Host "   ❌ FAIL" -ForegroundColor Red
        $script:fail++
        $script:log += "`n--- FAIL: $Name ---`n$out`n"
    }
}

# 1. 测试核心包 (api_hub)
Test-Build "api_hub (包)" "./api_hub"

# 2. 测试所有 demo 子目录
Write-Host "`n📂 检查 demos 下的所有子目录..." -ForegroundColor Cyan
$subDirs = Get-ChildItem -Path ".\demos" -Directory
if ($subDirs.Count -eq 0) {
    Write-Host "⚠️ 没有找到子目录，请确认 demos 结构正确。" -ForegroundColor Yellow
} else {
    foreach ($dir in $subDirs) {
        $goFiles = Get-ChildItem -Path $dir.FullName -Filter "*.go" -File
        if ($goFiles.Count -gt 0) {
            Test-Build $dir.Name $dir.FullName
        }
    }
}

# 输出统计
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "📊 总计: $($pass+$fail) 个检查项" -ForegroundColor White
Write-Host "✅ 通过: $pass" -ForegroundColor Green
Write-Host "❌ 失败: $fail" -ForegroundColor Red

if ($fail -eq 0) {
    Write-Host "🎉 所有 Demo 全部编译通过！" -ForegroundColor Green
} else {
    Write-Host "`n📋 详细失败日志（请复制以下内容给 AI 诊断）：" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Yellow
    Write-Host $log
    Write-Host "----------------------------------------" -ForegroundColor Yellow
    Write-Host "💡 提示：请确保 CGO 已启用（$env:CGO_ENABLED=1）。" -ForegroundColor Yellow
}