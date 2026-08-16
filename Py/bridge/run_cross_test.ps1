﻿# run_cross_test.ps1
# 所有服务窗口独立弹窗，Pascal 测试在当前窗口输出
# 使用临时文件执行 Python/PHP/Node.js 脚本，避免转义问题
#
# 重要：请确保 zapi_bridge.py 已更新为增强日志版本（包含 USE_INDEPENDENT_REQUEST 等）
#       否则日志中不会有详细的 DEBUG 信息。

Write-Host "=== ZAPI 多语言交叉调用测试（完整版 + 增强日志） ===" -ForegroundColor Cyan
Write-Host "注意：Bridge、Python/PHP/Node.js Webhook 会弹窗独立运行，Pascal 测试在当前窗口输出。" -ForegroundColor Yellow
Write-Host ""

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BridgeDir = $ScriptDir
$PhpDir = Join-Path $ScriptDir "PHP"
$NodeDir = Join-Path $ScriptDir "node.js"
$PascalDir = Join-Path $ScriptDir "pascal"
$BinaryDir = Resolve-Path (Join-Path $ScriptDir "..\..\Binary")

if (-not (Test-Path $BinaryDir)) {
    Write-Host "错误：找不到 Binary 目录，预期路径：$BinaryDir" -ForegroundColor Red
    Read-Host "按 Enter 退出"
    exit 1
}
$env:PATH = "$BinaryDir;$env:PATH"

# 检查必要文件
$bridgeScript = Join-Path $BridgeDir "zapi_bridge.py"
$pythonWebhook = Join-Path $BridgeDir "python_webhook.py"
$phpWebhook = Join-Path $PhpDir "webhook_server.php"
$nodeWebhook = Join-Path $NodeDir "node_webhook.js"
$pascalLpi = Join-Path $PascalDir "pascal_cross_test.lpi"
$pascalExe = Join-Path $PascalDir "pascal_cross_test.exe"

$missingFiles = @()
if (-not (Test-Path $bridgeScript)) { $missingFiles += "zapi_bridge.py" }
if (-not (Test-Path $pythonWebhook)) { $missingFiles += "python_webhook.py" }
if (-not (Test-Path $phpWebhook)) { $missingFiles += "PHP\webhook_server.php" }
if (-not (Test-Path $nodeWebhook)) { $missingFiles += "node.js\node_webhook.js" }
if (-not (Test-Path $pascalLpi)) { $missingFiles += "pascal\pascal_cross_test.lpi" }

if ($missingFiles.Count -gt 0) {
    Write-Host "错误：以下文件缺失：" -ForegroundColor Red
    foreach ($f in $missingFiles) { Write-Host "  - $f" }
    Read-Host "按 Enter 退出"
    exit 1
}

$nodeExists = Get-Command "node" -ErrorAction SilentlyContinue
if (-not $nodeExists) {
    Write-Host "警告：未找到 Node.js 命令，Node.js 相关服务将跳过。" -ForegroundColor Yellow
}

$lazbuildExists = Get-Command "lazbuild.exe" -ErrorAction SilentlyContinue
if (-not $lazbuildExists) {
    Write-Host "警告：未找到 lazbuild.exe，Pascal 测试将跳过。" -ForegroundColor Yellow
}

# ============ 启动服务（独立弹窗） ============
Write-Host "1. 启动 ZAPI Bridge (新窗口) ..."

# ---- 关键修改：设置环境变量 WEBHOOK_TIMEOUT 和 LOG_LEVEL，并指定 USE_INDEPENDENT_REQUEST=0（默认） ----
$bridgeCommand = "`$env:WEBHOOK_TIMEOUT=10; `$env:LOG_LEVEL='DEBUG'; `$env:USE_INDEPENDENT_REQUEST=0; `$env:PATH='$BinaryDir;'+`$env:PATH; cd '$BridgeDir'; Write-Host '=== ZAPI Bridge (增强日志) ===' -ForegroundColor Cyan; python zapi_bridge.py"
$bridgeProcess = Start-Process -FilePath "powershell" -ArgumentList "-NoExit", "-Command", $bridgeCommand -PassThru

Write-Host "等待 Bridge 启动（最多 15 秒）..."
$bridgeReady = $false
for ($i=0; $i -lt 15; $i++) {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:8080/v1/health" -TimeoutSec 1 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $bridgeReady = $true
            Write-Host "Bridge 已就绪（耗时 $i 秒）" -ForegroundColor Green
            break
        }
    } catch {}
    Start-Sleep -Seconds 1
}
if (-not $bridgeReady) {
    Write-Host "警告：Bridge 未能在 15 秒内就绪，将继续执行测试。" -ForegroundColor Yellow
}

Write-Host "2. 启动 Python Webhook 服务器 (端口 9001，新窗口) ..."
$pyWebhookProcess = Start-Process -FilePath "powershell" -ArgumentList "-NoExit", "-Command", "cd '$BridgeDir'; Write-Host '=== Python Webhook (9001) ===' -ForegroundColor Cyan; python python_webhook.py" -PassThru
Start-Sleep -Seconds 2

Write-Host "3. 启动 PHP Webhook 服务器 (端口 9000，新窗口) ..."
$phpWebhookProcess = Start-Process -FilePath "powershell" -ArgumentList "-NoExit", "-Command", "cd '$PhpDir'; Write-Host '=== PHP Webhook (9000) ===' -ForegroundColor Cyan; php -S 127.0.0.1:9000 webhook_server.php" -PassThru
Start-Sleep -Seconds 2

if ($nodeExists) {
    Write-Host "4. 启动 Node.js Webhook 服务器 (端口 9002，新窗口) ..."
    $nodeWebhookProcess = Start-Process -FilePath "powershell" -ArgumentList "-NoExit", "-Command", "cd '$NodeDir'; Write-Host '=== Node.js Webhook (9002) ===' -ForegroundColor Cyan; node node_webhook.js" -PassThru
    Start-Sleep -Seconds 2
} else {
    Write-Host "4. 跳过 Node.js Webhook 服务器" -ForegroundColor Yellow
}

# ============ 编译 Pascal ============
if ($lazbuildExists) {
    Write-Host "5. 编译 Pascal 交叉测试程序 ..." -ForegroundColor Yellow
    Push-Location $PascalDir
    & lazbuild.exe -B "pascal_cross_test.lpi"
    $compileResult = $LASTEXITCODE
    Pop-Location
    if ($compileResult -ne 0) {
        Write-Host "Pascal 编译失败，错误代码 $compileResult" -ForegroundColor Red
        $pascalCompiled = $false
    } else {
        Write-Host "Pascal 编译成功。" -ForegroundColor Green
        $pascalCompiled = $true
    }
} else {
    $pascalCompiled = $false
}

# ============ 阶段一：注册所有 Webhook（使用临时文件） ============
Write-Host "`n========== 阶段一：注册所有 Webhook ==========" -ForegroundColor Cyan

# --- 注册 Python ---
Write-Host "`n[注册] Python (py_echo) ..." -ForegroundColor Yellow
$pyRegScript = @"
import urllib.request, json
url = 'http://127.0.0.1:8080/v1/hooks/register'
data = json.dumps({'app':'HttpBridge','api':'py_echo','callback_url':'http://127.0.0.1:9001/webhook','mode':'call'}).encode()
req = urllib.request.Request(url, data=data, headers={'Content-Type':'application/json'})
try:
    resp = json.loads(urllib.request.urlopen(req, timeout=5).read().decode())
    print('  Python py_echo:', resp.get('status', resp))
except Exception as e:
    print('  Python py_echo error:', e)
"@
$pyRegScript | Out-File -FilePath "$env:TEMP\reg_py.py" -Encoding utf8
python "$env:TEMP\reg_py.py"
Remove-Item "$env:TEMP\reg_py.py" -ErrorAction SilentlyContinue

# --- 注册 PHP ---
Write-Host "`n[注册] PHP (php_echo) ..." -ForegroundColor Yellow
$phpRegScript = @'
<?php
$url = 'http://127.0.0.1:8080/v1/hooks/register';
$data = json_encode(['app'=>'HttpBridge','api'=>'php_echo','callback_url'=>'http://127.0.0.1:9000/','mode'=>'call']);
$ch = curl_init($url);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, $data);
curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
$resp = json_decode(curl_exec($ch), true);
if ($resp && isset($resp['status'])) {
    echo '  PHP php_echo: ' . $resp['status'] . "\n";
} else {
    echo '  PHP php_echo: error - ' . curl_error($ch) . "\n";
}
'@
$phpRegScript | Out-File -FilePath "$env:TEMP\reg_php.php" -Encoding utf8
php "$env:TEMP\reg_php.php"
Remove-Item "$env:TEMP\reg_php.php" -ErrorAction SilentlyContinue

# --- 注册 Node.js ---
if ($nodeExists) {
    Write-Host "`n[注册] Node.js (node_echo) ..." -ForegroundColor Yellow
    $nodeRegScript = @"
const http = require('http');
const data = JSON.stringify({app:'HttpBridge',api:'node_echo',callback_url:'http://127.0.0.1:9002/webhook',mode:'call'});
const req = http.request('http://127.0.0.1:8080/v1/hooks/register', {method:'POST',headers:{'Content-Type':'application/json'}}, res => {
    let body=''; res.on('data',c=>body+=c); res.on('end',()=>{ const r=JSON.parse(body); console.log('  Node node_echo:', r.status || r); });
});
req.on('error', e => console.log('  Node node_echo error:', e.message));
req.write(data); req.end();
"@
    $nodeRegScript | Out-File -FilePath "$env:TEMP\reg_node.js" -Encoding utf8
    node "$env:TEMP\reg_node.js"
    Remove-Item "$env:TEMP\reg_node.js" -ErrorAction SilentlyContinue
}

# 等待注册生效
Write-Host "`n等待 3 秒让注册生效..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

# 验证注册结果
Write-Host "`n[验证] 已注册的 hooks:" -ForegroundColor Yellow
$hooks = Invoke-WebRequest -Uri "http://127.0.0.1:8080/v1/hooks/list" -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json
if ($hooks.hooks) {
    $hooks.hooks | ForEach-Object { Write-Host "  $($_.app).$($_.api) -> $($_.url)" }
} else {
    Write-Host "  无 hooks 注册" -ForegroundColor Yellow
}

# ============ 阶段二：交叉调用测试 ============
Write-Host "`n========== 阶段二：交叉调用测试 ==========" -ForegroundColor Cyan

# --- Python 调用 PHP ---
Write-Host "`n[测试] Python 调用 PHP (php_echo) ..." -ForegroundColor Yellow
$pyCallScript = @"
import urllib.request, json, time
url = 'http://127.0.0.1:8080/v1/invoke'
data = json.dumps({'app':'HttpBridge','api':'php_echo','args':['Hello from Python!'],'timeout':5000}).encode()
for i in range(3):
    req = urllib.request.Request(url, data=data, headers={'Content-Type':'application/json'})
    try:
        resp = json.loads(urllib.request.urlopen(req, timeout=5).read().decode())
        if resp.get('code') == 0:
            print('  Python -> PHP:', resp.get('result'))
            break
        else:
            print(f'  Attempt {i+1}: {resp.get("error")}')
    except Exception as e:
        print(f'  Attempt {i+1}: error - {e}')
    time.sleep(1)
else:
    print('  Python -> PHP: all attempts failed')
"@
$pyCallScript | Out-File -FilePath "$env:TEMP\call_py.py" -Encoding utf8
python "$env:TEMP\call_py.py"
Remove-Item "$env:TEMP\call_py.py" -ErrorAction SilentlyContinue

# --- PHP 调用 Python ---
Write-Host "`n[测试] PHP 调用 Python (py_echo) ..." -ForegroundColor Yellow
$phpCallScript = @'
<?php
$url = 'http://127.0.0.1:8080/v1/invoke';
$data = json_encode(['app'=>'HttpBridge','api'=>'py_echo','args'=>['Hello from PHP!'],'timeout'=>5000]);
$ch = curl_init($url);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, $data);
curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
$resp = json_decode(curl_exec($ch), true);
if ($resp && isset($resp['code']) && $resp['code'] === 0) {
    echo '  PHP -> Python: ' . json_encode($resp['result']) . "\n";
} else {
    echo '  PHP -> Python error: ' . ($resp['error'] ?? 'unknown') . "\n";
}
'@
$phpCallScript | Out-File -FilePath "$env:TEMP\call_php.php" -Encoding utf8
php "$env:TEMP\call_php.php"
Remove-Item "$env:TEMP\call_php.php" -ErrorAction SilentlyContinue

# --- Node.js 调用 ---
if ($nodeExists) {
    Write-Host "`n[测试] Node.js 调用 Python (py_echo) ..." -ForegroundColor Yellow
    $nodeCallPy = @"
const http = require('http');
const data = JSON.stringify({app:'HttpBridge',api:'py_echo',args:['Hello from Node.js!'],timeout:5000});
const req = http.request('http://127.0.0.1:8080/v1/invoke', {method:'POST',headers:{'Content-Type':'application/json'}}, res => {
    let body=''; res.on('data',c=>body+=c); res.on('end',()=>{ const r=JSON.parse(body); console.log('  Node -> Python:', r.result || r.error); });
});
req.on('error', e => console.log('  Node -> Python error:', e.message));
req.write(data); req.end();
"@
    $nodeCallPy | Out-File -FilePath "$env:TEMP\call_node_py.js" -Encoding utf8
    node "$env:TEMP\call_node_py.js"
    Remove-Item "$env:TEMP\call_node_py.js" -ErrorAction SilentlyContinue

    Write-Host "`n[测试] Node.js 调用 PHP (php_echo) ..." -ForegroundColor Yellow
    $nodeCallPhp = @"
const http = require('http');
const data = JSON.stringify({app:'HttpBridge',api:'php_echo',args:['Hello from Node.js!'],timeout:5000});
const req = http.request('http://127.0.0.1:8080/v1/invoke', {method:'POST',headers:{'Content-Type':'application/json'}}, res => {
    let body=''; res.on('data',c=>body+=c); res.on('end',()=>{ const r=JSON.parse(body); console.log('  Node -> PHP:', r.result || r.error); });
});
req.on('error', e => console.log('  Node -> PHP error:', e.message));
req.write(data); req.end();
"@
    $nodeCallPhp | Out-File -FilePath "$env:TEMP\call_node_php.js" -Encoding utf8
    node "$env:TEMP\call_node_php.js"
    Remove-Item "$env:TEMP\call_node_php.js" -ErrorAction SilentlyContinue
}

# ============ Pascal 测试 ============
if ($pascalCompiled) {
    Write-Host "`n[测试] Pascal 交叉调用 (当前窗口) ..." -ForegroundColor Yellow
    Write-Host "  运行 pascal_cross_test.exe，输出如下：" -ForegroundColor Yellow
    Push-Location $PascalDir
    & .\pascal_cross_test.exe
    $pascalExitCode = $LASTEXITCODE
    Pop-Location
    Write-Host "  Pascal 测试程序退出代码: $pascalExitCode" -ForegroundColor Green
} else {
    Write-Host "`n[测试] 跳过 Pascal 测试（编译失败或未安装 Lazarus）" -ForegroundColor Yellow
}

Write-Host "`n测试脚本执行完毕。" -ForegroundColor Green
Write-Host "所有服务进程仍在后台窗口运行。" -ForegroundColor Yellow
Write-Host "请检查各窗口日志确认结果，完成后手动关闭。"
Write-Host ""
Write-Host "🔍 重要：请查看 Bridge 窗口的控制台输出，以及 bridge_perf.log 文件。"
Write-Host "   查找 '[DEBUG] _forward_webhook_sync timeout = ...' 和异常类型信息。"
Read-Host "按 Enter 退出（不会关闭服务窗口）"