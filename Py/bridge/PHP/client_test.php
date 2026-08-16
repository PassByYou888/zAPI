<?php
require_once 'ZAPIBridgeClient.php';

$bridgeUrl = 'http://127.0.0.1:8080/v1';
echo "=== ZAPI Bridge PHP Client Test Suite ===\n";
echo "Bridge URL: $bridgeUrl\n\n";

try {
    $client = new ZAPIBridgeClient($bridgeUrl);
    
    // 1. Health check
    echo "[1] Health check... ";
    if ($client->health()) {
        echo "✅ Bridge is healthy.\n";
    } else {
        echo "❌ Bridge not reachable. Please start bridge.\n";
        exit(1);
    }

    // 2. Call ZAPI (may fail if service not running)
    echo "\n[2] Calling CalcService.add(10, 20)... ";
    try {
        $result = $client->invoke('CalcService', 'add', [10, 20]);
        echo "✅ Result: $result\n";
    } catch (Exception $e) {
        echo "⚠️ Invoke failed: " . $e->getMessage() . " (CalcService may not be running)\n";
    }

    // 3. Send notification
    echo "\n[3] Sending notification to LogService.log... ";
    try {
        $client->notify('LogService', 'log', ['INFO', 'PHP test message']);
        echo "✅ Notification sent.\n";
    } catch (Exception $e) {
        echo "⚠️ " . $e->getMessage() . "\n";
    }

    // 4. Register webhook (with pre-unregister to ensure clean state)
    echo "\n[4] Registering webhook for MyApp.echo -> http://127.0.0.1:9000/ (mode=call)\n";
    // First, try to unregister in case it already exists (idempotent)
    try {
        $client->unregisterHook('MyApp', 'echo');
        echo "   (pre-unregistered any existing hook)\n";
    } catch (Exception $e) {
        // ignore if not exists
    }
    try {
        $resp = $client->registerHook('MyApp', 'echo', 'http://127.0.0.1:9000/', 'call');
        echo "   ✅ Registered (mode: {$resp['mode']})\n";
    } catch (Exception $e) {
        echo "   ❌ Register failed: " . $e->getMessage() . "\n";
    }

    // 5. Call the webhook (via /invoke) – will work only if webhook server is running
    echo "\n[5] Calling webhook (via /invoke) MyApp.echo with args [\"Hello from ZAPI!\"]... ";
    try {
        $result = $client->invoke('HttpBridge', 'echo', ['Hello from ZAPI!']);
        echo "✅ Webhook call successful: " . json_encode($result) . "\n";
    } catch (Exception $e) {
        echo "⚠️ Webhook call failed: " . $e->getMessage() . " (webhook server may not be running)\n";
    }

    // 6. List hooks
    echo "\n[6] Listing all registered hooks... ";
    try {
        $hooks = $client->listHooks();
        echo "✅ Current hooks:\n";
        print_r($hooks);
    } catch (Exception $e) {
        echo "⚠️ " . $e->getMessage() . "\n";
    }

    // 7. Unregister
    echo "\n[7] Unregistering webhook for MyApp.echo... ";
    try {
        $resp = $client->unregisterHook('MyApp', 'echo');
        echo "✅ Unregistered: " . json_encode($resp) . "\n";
    } catch (Exception $e) {
        echo "⚠️ " . $e->getMessage() . "\n";
    }

    echo "\n=== Test suite completed ===\n";
} catch (Exception $e) {
    echo "❌ Fatal error: " . $e->getMessage() . "\n";
}