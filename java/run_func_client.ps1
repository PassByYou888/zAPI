# run_func_client.ps1
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$JNA_JAR = Join-Path $ScriptDir "lib\jna-5.14.0.jar"
$OUT_DIR = Join-Path $ScriptDir "out"
$DLL_DIR = Resolve-Path (Join-Path $ScriptDir "..\Binary")

$env:PATH = "$env:PATH;$DLL_DIR"

Write-Host "Dynamic library path: $DLL_DIR"
Write-Host "Starting FuncClient..."
java -cp "$JNA_JAR;$OUT_DIR" demo.FuncClient