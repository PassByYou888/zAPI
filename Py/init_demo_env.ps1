<#
.SYNOPSIS
    初始化 zAPI Python 演示环境，设置 PYTHONPATH 和 PATH。
.DESCRIPTION
    此脚本设置当前 PowerShell 会话的环境变量，使得 api_hub 包可被导入，
    并可选地将 Binary 目录（包含 z_api_hub64.dll）添加到系统 PATH 中。
    建议在运行任何 Python 示例前执行此脚本。
.PARAMETER NoBinary
    如果指定，则不将 Binary 目录添加到 PATH（默认添加）。
.EXAMPLE
    .\init_demo_env.ps1
    初始化环境，添加 Binary 到 PATH。
.EXAMPLE
    .\init_demo_env.ps1 -NoBinary
    仅设置 PYTHONPATH，不修改 PATH。
#>

param(
    [switch]$NoBinary
)

# 获取脚本所在目录（即 Py 根目录）
$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = (Get-Location).Path
}

Write-Host "🔧 初始化 zAPI Python 演示环境" -ForegroundColor Cyan
Write-Host "脚本根目录: $scriptDir" -ForegroundColor Gray

# ---------- 设置 PYTHONPATH ----------
$currentPYTHONPATH = [Environment]::GetEnvironmentVariable("PYTHONPATH", "Process")
if ($currentPYTHONPATH) {
    # 检查 $scriptDir 是否已在 PYTHONPATH 中
    $paths = $currentPYTHONPATH -split [IO.Path]::PathSeparator
    if ($paths -contains $scriptDir) {
        Write-Host "✅ PYTHONPATH 已包含 $scriptDir，无需重复添加" -ForegroundColor Green
    } else {
        $env:PYTHONPATH = "$scriptDir;$currentPYTHONPATH"
        Write-Host "✅ 已追加 $scriptDir 到 PYTHONPATH" -ForegroundColor Green
    }
} else {
    $env:PYTHONPATH = $scriptDir
    Write-Host "✅ 已设置 PYTHONPATH = $scriptDir" -ForegroundColor Green
}

# ---------- 设置 PATH（添加 Binary 目录） ----------
if (-not $NoBinary) {
    $binaryDir = Join-Path $scriptDir "..\Binary"
    # 规范化路径（解析 ..）
    $binaryDir = Resolve-Path $binaryDir -ErrorAction SilentlyContinue
    if (-not $binaryDir) {
        Write-Host "⚠️ 警告：Binary 目录不存在: $binaryDir，跳过 PATH 设置" -ForegroundColor Yellow
    } else {
        $currentPATH = [Environment]::GetEnvironmentVariable("PATH", "Process")
        $paths = $currentPATH -split [IO.Path]::PathSeparator
        if ($paths -contains $binaryDir) {
            Write-Host "✅ PATH 已包含 $binaryDir，无需重复添加" -ForegroundColor Green
        } else {
            $env:PATH = "$binaryDir;$currentPATH"
            Write-Host "✅ 已追加 $binaryDir 到 PATH" -ForegroundColor Green
        }
    }
} else {
    Write-Host "ℹ️ 根据 -NoBinary 参数，未修改 PATH" -ForegroundColor Gray
}

# ---------- 验证 api_hub 包是否可导入 ----------
Write-Host "`n🔍 验证 api_hub 包..." -ForegroundColor Cyan
$testCmd = "import api_hub; print('api_hub 导入成功')"
try {
    $output = python -c $testCmd 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ api_hub 包导入正常" -ForegroundColor Green
    } else {
        Write-Host "❌ api_hub 包导入失败，请检查 PYTHONPATH 设置" -ForegroundColor Red
        Write-Host "错误信息: $output" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ 无法运行 python 命令，请确保 Python 已安装并在 PATH 中" -ForegroundColor Red
}

# ---------- 显示最终环境变量 ----------
Write-Host "`n📋 当前环境变量摘要：" -ForegroundColor Cyan
Write-Host "PYTHONPATH = $env:PYTHONPATH" -ForegroundColor Gray
Write-Host "PATH (前3项) = $($env:PATH -split [IO.Path]::PathSeparator | Select-Object -First 3) ..." -ForegroundColor Gray
Write-Host "`n✅ 环境初始化完成。现在可以运行任何示例，例如： .\run_all.ps1" -ForegroundColor Cyan