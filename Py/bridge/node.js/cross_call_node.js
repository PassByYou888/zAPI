// cross_call_node.js
// Node.js 交叉调用测试：注册 webhook 并调用 Python/PHP

const { ZAPIBridgeClient } = require('./ZAPIBridgeClient');

async function main() {
    const client = new ZAPIBridgeClient('http://127.0.0.1:8080/v1');

    console.log('=== Node.js Cross Call Test ===');

    // 1. 健康检查
    console.log('\n[1] Health check...');
    const healthy = await client.health();
    if (!healthy) {
        console.error('❌ Bridge not reachable. Please start bridge first.');
        process.exit(1);
    }
    console.log('✅ Bridge is healthy');

    // 2. 启动一个简单的 Node.js Webhook 服务器（内联）
    // 注意：需要单独启动 webhook 接收服务器，这里只做调用演示

    // 3. 注册 Node.js 自己的 webhook（供其他语言调用）
    console.log('\n[2] Registering Node.js webhook (HttpBridge.node_echo)...');
    try {
        await client.unregisterHook('HttpBridge', 'node_echo').catch(() => {});
        const resp = await client.registerHook(
            'HttpBridge',
            'node_echo',
            'http://127.0.0.1:9002/webhook',
            'call'
        );
        console.log('   ✅ Registered:', resp);
    } catch (e) {
        console.error('   ❌ Registration failed:', e.message);
    }

    // 4. 等待其他语言注册完成
    console.log('\n[3] Waiting for Python/PHP to register...');
    await sleep(2000);

    // 5. 调用 Python 的 py_echo
    console.log('\n[4] Calling Python webhook (py_echo)...');
    try {
        const result = await client.invoke('HttpBridge', 'py_echo', ['Hello from Node.js!']);
        console.log('   ✅ Python echo response:', result);
    } catch (e) {
        console.error('   ❌ Python echo failed:', e.message);
    }

    // 6. 调用 PHP 的 php_echo
    console.log('\n[5] Calling PHP webhook (php_echo)...');
    try {
        const result = await client.invoke('HttpBridge', 'php_echo', ['Hello from Node.js!']);
        console.log('   ✅ PHP echo response:', result);
    } catch (e) {
        console.error('   ❌ PHP echo failed:', e.message);
    }

    // 7. 列出所有已注册的 hook
    console.log('\n[6] Listing all hooks...');
    try {
        const hooks = await client.listHooks();
        console.log('   ✅ Hooks:', hooks);
    } catch (e) {
        console.error('   ❌ List hooks failed:', e.message);
    }

    console.log('\n=== Node.js Cross Call Test Completed ===');
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

main().catch(console.error);