# check_all.ps1
# 一键检查所有 Rust 示例是否能成功编译
# 用法：在 rust/ 目录下运行 .\check_all.ps1

$ErrorActionPreference = "Continue"

# 检查是否在正确的目录（Cargo.toml 必须存在）
if (-not (Test-Path "Cargo.toml")) {
    Write-Host "❌ 请在 Rust 项目根目录（包含 Cargo.toml）运行此脚本！" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "🔍 检查所有 Rust 示例编译状态" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# 显示 rustc 版本
$rustcVer = rustc --version
Write-Host "Rust 版本: $rustcVer" -ForegroundColor Gray
Write-Host ""

# 先执行整体 cargo check，确保依赖没问题
Write-Host "📦 执行 cargo check (整体) ..." -ForegroundColor Cyan
$globalCheck = cargo check 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ 整体检查通过" -ForegroundColor Green
} else {
    Write-Host "   ⚠️ 整体检查有警告或错误，但继续检查示例" -ForegroundColor Yellow
}

# 解析 Cargo.toml 获取所有 example 名称
$examples = @()
$inExample = $false
$currentName = ""

Get-Content "Cargo.toml" | ForEach-Object {
    $line = $_.Trim()
    if ($line -match '^\[\[example\]\]') {
        $inExample = $true
        $currentName = ""
    }
    if ($inExample -and $line -match '^name\s*=\s*"(.+)"') {
        $currentName = $matches[1]
        $examples += $currentName
        $inExample = $false
    }
}

if ($examples.Count -eq 0) {
    Write-Host "⚠️ 未在 Cargo.toml 中找到任何 [[example]] 定义" -ForegroundColor Yellow
    Write-Host "   （如果您已生成示例，请检查 Cargo.toml 是否包含示例定义）" -ForegroundColor Yellow
    exit 0
}

Write-Host "`n📋 找到 $($examples.Count) 个示例: $($examples -join ', ')" -ForegroundColor Cyan
Write-Host ""

$pass = 0
$fail = 0
$log = ""

foreach ($name in $examples) {
    Write-Host "🔨 检查示例: $name ..." -ForegroundColor Cyan
    $build = cargo check --example $name 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ PASS" -ForegroundColor Green
        $pass++
    } else {
        Write-Host "   ❌ FAIL" -ForegroundColor Red
        $fail++
        $log += "`n--- FAIL: $name ---`n$build`n"
    }
}

# 输出统计
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "📊 总计: $($pass+$fail) 个示例" -ForegroundColor White
Write-Host "✅ 通过: $pass" -ForegroundColor Green
Write-Host "❌ 失败: $fail" -ForegroundColor Red

if ($fail -eq 0) {
    Write-Host "🎉 所有示例全部编译通过！" -ForegroundColor Green
} else {
    Write-Host "`n📋 详细失败日志（请复制以下内容用于诊断）：" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Yellow
    Write-Host $log
    Write-Host "----------------------------------------" -ForegroundColor Yellow
    Write-Host "💡 常见原因：" -ForegroundColor Yellow
    Write-Host "   - 缺少依赖（如 ctrlc），请在 Cargo.toml 的 [dependencies] 中添加 ctrlc = \"3.4\"" -ForegroundColor Yellow
    Write-Host "   - 示例代码中使用了未导出的 API（检查 lib.rs 是否为 pub）" -ForegroundColor Yellow
    Write-Host "   - 动态库路径问题（不影响编译，仅影响运行时）" -ForegroundColor Yellow
    exit 1
}