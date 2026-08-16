<?php
require_once 'ZAPIBridgeClient.php';

$client = new ZAPIBridgeClient('http://127.0.0.1:8080/v1');

// 1. 先注册 PHP 自己的 webhook（供 Python 调用）
echo "Registering PHP webhook (HttpBridge.php_echo)...\n";
try {
    $client->unregisterHook('HttpBridge', 'php_echo');
} catch (Exception $e) {}
$resp = $client->registerHook('HttpBridge', 'php_echo', 'http://127.0.0.1:9000/', 'call');
echo "   Registered: " . json_encode($resp) . "\n";

// 2. 等待 Python 也完成注册（通过 sleep 简单等待）
echo "Waiting for Python to register its webhook...\n";
sleep(2);

// 3. 调用 Python 的 webhook
echo "Calling Python webhook (HttpBridge.py_echo) from PHP...\n";
try {
    $result = $client->invoke('HttpBridge', 'py_echo', ['Hello from PHP via Bridge!']);
    echo "✅ Result: " . json_encode($result) . "\n";
} catch (Exception $e) {
    echo "❌ Error: " . $e->getMessage() . "\n";
}