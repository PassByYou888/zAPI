# build.ps1
$ErrorActionPreference = "Stop"

$JNA_JAR = ".\lib\jna-5.14.0.jar"
$SRC_DIR = ".\src"
$DEMO_DIR = ".\demo"
$OUT_DIR = ".\out"

if (-not (Test-Path $OUT_DIR)) { New-Item -ItemType Directory -Path $OUT_DIR -Force | Out-Null }

Write-Host "Compiling Java sources..."
javac -encoding UTF-8 -d $OUT_DIR -cp "$JNA_JAR;$OUT_DIR" `
    ($SRC_DIR + "\com\apihub\*.java") `
    ($DEMO_DIR + "\*.java")

if ($LASTEXITCODE -ne 0) {
    Write-Host "Compilation failed."
    exit $LASTEXITCODE
}
Write-Host "Compilation succeeded. Classes in $OUT_DIR"