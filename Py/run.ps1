# run.ps1 - PowerShell 版本的 run.bat
# 用法：.\run.ps1 [可选 Python 脚本路径]

# 获取当前脚本所在目录（Py 目录）
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) {
    # 如果直接执行代码块，可能为空，用 Get-Location 替代
    $ScriptDir = (Get-Location).Path
}

Write-Host "获取当前脚本所在目录（即 Py 目录）：$ScriptDir"

# 设置 PYTHONPATH 为 Py 目录本身
$env:PYTHONPATH = $ScriptDir
Write-Host "设置 PYTHONPATH = $env:PYTHONPATH"

# 设置 PATH，添加 Binary 目录（相对于 Py 目录为 ..\Binary）
$BinaryDir = Join-Path $ScriptDir "..\Binary"
if (Test-Path $BinaryDir) {
    $env:PATH = "$BinaryDir;$env:PATH"
    Write-Host "添加 Binary 目录到 PATH: $BinaryDir"
} else {
    Write-Host "警告：Binary 目录不存在: $BinaryDir" -ForegroundColor Yellow
}

# 如果传递了参数，则运行指定的脚本，否则默认运行 basic/hello_world.py
if ($args.Count -eq 0) {
    $ScriptToRun = "examples\basic\hello_world.py"
} else {
    $ScriptToRun = $args[0]
}

Write-Host "运行 Python 脚本: $ScriptToRun"
python $ScriptToRun

# 可选：等待用户按键（调试时）
# Read-Host "按 Enter 退出"