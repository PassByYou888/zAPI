# run_client.ps1
$ErrorActionPreference = "Stop"

$JNA_JAR = ".\lib\jna-5.14.0.jar"
$OUT_DIR = ".\out"
$DLL_DIR = "..\Binary"

$env:PATH = "$env:PATH;$DLL_DIR"

Write-Host "Starting client..."
java -cp "$JNA_JAR;$OUT_DIR" demo.DemoClient