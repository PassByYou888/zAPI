# check_all_rs.ps1 - Check compilation of all Rust examples
# Usage: run in the rust/ directory where Cargo.toml exists

$ErrorActionPreference = "Continue"

# Check if we are in the correct directory (Cargo.toml must exist)
if (-not (Test-Path "Cargo.toml")) {
    Write-Host "❌ Please run this script in the Rust project root (where Cargo.toml is located)." -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "🔍 Checking all Rust examples compilation status" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Show rustc version
$rustcVer = rustc --version
Write-Host "Rust version: $rustcVer" -ForegroundColor Gray
Write-Host ""

# First run cargo check globally to ensure dependencies are fine
Write-Host "📦 Running cargo check (global) ..." -ForegroundColor Cyan
$globalCheck = cargo check 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ Global check passed" -ForegroundColor Green
} else {
    Write-Host "   ⚠️ Global check has warnings or errors, but continuing to check examples" -ForegroundColor Yellow
}

# Parse Cargo.toml to get all example names
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
    Write-Host "⚠️ No [[example]] definitions found in Cargo.toml" -ForegroundColor Yellow
    Write-Host "   (If you have generated examples, please check that Cargo.toml contains example definitions.)" -ForegroundColor Yellow
    exit 0
}

Write-Host "`n📋 Found $($examples.Count) example(s): $($examples -join ', ')" -ForegroundColor Cyan
Write-Host ""

$pass = 0
$fail = 0
$log = ""

foreach ($name in $examples) {
    Write-Host "🔨 Checking example: $name ..." -ForegroundColor Cyan
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

# Output statistics
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "📊 Total: $($pass+$fail) example(s)" -ForegroundColor White
Write-Host "✅ Passed: $pass" -ForegroundColor Green
Write-Host "❌ Failed: $fail" -ForegroundColor Red

if ($fail -eq 0) {
    Write-Host "🎉 All examples compiled successfully!" -ForegroundColor Green
} else {
    Write-Host "`n📋 Detailed failure log (copy below for diagnosis):" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Yellow
    Write-Host $log
    Write-Host "----------------------------------------" -ForegroundColor Yellow
    Write-Host "💡 Common causes:" -ForegroundColor Yellow
    Write-Host "   - Missing dependencies (e.g., ctrlc) - add ctrlc = \"3.4\" to Cargo.toml's [dependencies]" -ForegroundColor Yellow
    Write-Host "   - Example code uses non-exported API (check lib.rs for pub visibility)" -ForegroundColor Yellow
    Write-Host "   - Dynamic library path issues (does not affect compilation, only runtime)" -ForegroundColor Yellow
    exit 1
}