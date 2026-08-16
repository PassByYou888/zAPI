# run_server.ps1
$ErrorActionPreference = "Stop"

$JNA_JAR = ".\lib\jna-5.14.0.jar"
$OUT_DIR = ".\out"
$DLL_DIR = "..\Binary"   # 根据实际动态库位置调整

# 将动态库目录加入 PATH（Windows）
$env:PATH = "$env:PATH;$DLL_DIR"

Write-Host "Starting server..."
java -cp "$JNA_JAR;$OUT_DIR" demo.DemoServer