# run_func_server.ps1
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$JNA_JAR = Join-Path $ScriptDir "lib\jna-5.14.0.jar"
$OUT_DIR = Join-Path $ScriptDir "out"
$DLL_DIR = Resolve-Path (Join-Path $ScriptDir "..\Binary")

# 将动态库目录加入 PATH，JNA 会自动搜索
$env:PATH = "$env:PATH;$DLL_DIR"

Write-Host "Dynamic library path: $DLL_DIR"
Write-Host "Starting FuncServer..."
java -cp "$JNA_JAR;$OUT_DIR" demo.FuncServer