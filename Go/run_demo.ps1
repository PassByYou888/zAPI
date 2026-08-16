# run_demo.ps1
# 用途：自动配置 DLL 搜索路径（Binary 目录），然后运行指定的 Go demo。
# 用法：
#   .\run_demo.ps1                    # 交互式选择 demo
#   .\run_demo.ps1 calc_server        # 直接运行 demos/calc_server
#   .\run_demo.ps1 -DemoName calc_server  # 同上

param(
    [string]$DemoName = ""
)

$ErrorActionPreference = "Stop"

# 获取脚本所在目录（即 Go 根目录）
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# 定位 Binary 目录（位于 Go 的上级目录下的 Binary）
$binaryPath = Resolve-Path "$scriptDir\..\Binary" -ErrorAction SilentlyContinue
if (-not $binaryPath) {
    Write-Host "❌ Binary directory not found at $scriptDir\..\Binary" -ForegroundColor Red
    Write-Host "请确保目录结构为：Go 目录与 Binary 目录同级（均在 API_Hub_Tool\DLL-Build 下）" -ForegroundColor Yellow
    exit 1
}

# 将 Binary 目录添加到当前进程的 PATH 环境变量（DLL 搜索路径）
$env:PATH = "$binaryPath;$env:PATH"
Write-Host "✅ 已添加 DLL 搜索路径：$binaryPath" -ForegroundColor Cyan

# 检查 go 命令是否可用
if (-not (Get-Command "go" -ErrorAction SilentlyContinue)) {
    Write-Host "❌ 未找到 go 命令，请确保 Go 已安装并配置环境变量。" -ForegroundColor Red
    exit 1
}

# 如果没有指定 demo 名称，则交互式列出所有可用 demo
if (-not $DemoName) {
    $demosDir = Join-Path $scriptDir "demos"
    if (-not (Test-Path $demosDir)) {
        Write-Host "❌ demos 目录不存在：$demosDir" -ForegroundColor Red
        exit 1
    }

    # 获取所有包含 .go 文件的子目录
    $subDirs = Get-ChildItem -Path $demosDir -Directory | Where-Object {
        (Get-ChildItem -Path $_.FullName -Filter "*.go" -File).Count -gt 0
    }

    if ($subDirs.Count -eq 0) {
        Write-Host "❌ 没有找到任何包含 Go 文件的 demo 目录。" -ForegroundColor Red
        exit 1
    }

    Write-Host "`n可用的 demo：" -ForegroundColor Yellow
    $i = 1
    $nameMap = @{}
    foreach ($dir in $subDirs) {
        Write-Host "  $i. $($dir.Name)" -ForegroundColor Green
        $nameMap[$i] = $dir.Name
        $i++
    }

    $choice = Read-Host "`n请输入编号或 demo 名称"
    # 如果输入是数字，则映射到名称
    if ($choice -match '^\d+$') {
        $idx = [int]$choice
        if ($nameMap.ContainsKey($idx)) {
            $DemoName = $nameMap[$idx]
        } else {
            Write-Host "❌ 无效的编号" -ForegroundColor Red
            exit 1
        }
    } else {
        $DemoName = $choice.Trim()
    }
}

# 检查 demo 目录是否存在（修复 Join-Path 用法）
$demoPath = Join-Path (Join-Path $scriptDir "demos") $DemoName
if (-not (Test-Path $demoPath)) {
    Write-Host "❌ Demo '$DemoName' 不存在于 $demoPath" -ForegroundColor Red
    exit 1
}

# 检查是否有 .go 文件
$goFiles = Get-ChildItem -Path $demoPath -Filter "*.go" -File
if ($goFiles.Count -eq 0) {
    Write-Host "❌ Demo '$DemoName' 目录中没有找到 .go 文件" -ForegroundColor Red
    exit 1
}

Write-Host "`n🚀 正在运行 demo：$DemoName ..." -ForegroundColor Cyan
Push-Location $demoPath
try {
    # 执行 go run . ，自动编译并运行
    go run .
} catch {
    Write-Host "❌ 运行失败：$_" -ForegroundColor Red
} finally {
    Pop-Location
}

Write-Host "`n✅ Demo 执行完毕。" -ForegroundColor Green