/**
 * client.js - Node.js 客户端，通过 Python 网关调用 zAPI
 * ============================================================
 * 
 * 【架构说明】
 *   Node.js 应用 → HTTP 请求 → Python 网关 (gateway.py) → zAPI 动态库 (C4 服务网格)
 * 
 * 【为什么需要 Python 网关？】
 *   zAPI 是 C 动态库，通过 ctypes 在 Python 中调用最方便。
 *   Node.js 通过 HTTP 与 Python 网关通信，无需直接加载动态库，
 *   避免了 Node 原生插件编译的麻烦，同时获得跨语言调用的能力。
 * 
 * 【使用步骤】
 *   1. 准备环境：
 *      - 确保 Python 3.8+ 已安装
 *      - 确保 Node.js 已安装
 *      - 确保 z_api_hub64.dll (Windows) 或 libz_api_hub.so (Linux) 
 *        以及 z_ipc_64.dll 放在 `../Binary/` 目录下（相对于 Py 目录）
 * 
 *   2. 启动 Python 网关（在 Py 目录下执行）：
 *        cd D:\CoreLibrary\API_Hub_Tool\DLL-Build\Py
 *        $env:PATH = "..\Binary;" + $env:PATH   # 添加动态库路径
 *        python .\node\gateway.py --port 8080 --endpoint ipc:gateway
 * 
 *      网关启动后，会注册两个内置 API：
 *        - add    : 加法 (call)
 *        - log    : 日志通知 (notify)
 *      应用名固定为 "NodeGateway"，后续 Node 调用时需指定此应用名。
 * 
 *   3. 运行本客户端（在 node 目录下）：
 *        node client.js
 * 
 *   4. 期望输出：
 *        📞 调用 add(10, 20)...
 *        ✅ 结果: 30
 *        📨 发送日志通知...
 *        ✅ 通知已发送
 * 
 * 【如何扩展更多 API？】
 *   在 gateway.py 中仿照 add_callback 或 log_notify 添加新回调，
 *   然后用 APP.register_call() 或 APP.register_notify() 注册，
 *   即可在本客户端中通过 call() 或 notify() 调用。
 * 
 * 【注意事项】
 *   - app 参数固定为 "NodeGateway"（与 Python 网关注册的应用名一致）
 *   - 如果使用 TCP 地址，启动网关时改为 --endpoint 127.0.0.1:9898
 *   - 确保网关保持运行，否则请求会失败
 */

const http = require('http');

// 网关地址（与 Python 网关启动时的 --port 参数一致）
const GATEWAY = 'http://localhost:8080';

/**
 * 通用 HTTP 请求函数
 * @param {string} method - HTTP 方法 (POST)
 * @param {string} path - 路径 (/call 或 /notify)
 * @param {object} body - 请求体对象
 * @returns {Promise<object>} 响应 JSON
 */
function request(method, path, body) {
    return new Promise((resolve, reject) => {
        const url = new URL(path, GATEWAY);
        const data = JSON.stringify(body);
        const options = {
            hostname: url.hostname,
            port: url.port,
            path: url.pathname,
            method: method,
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(data)
            }
        };
        const req = http.request(options, (res) => {
            let raw = '';
            res.on('data', chunk => raw += chunk);
            res.on('end', () => {
                if (res.statusCode === 200) {
                    try {
                        resolve(JSON.parse(raw));
                    } catch (e) {
                        resolve(raw); // 非 JSON 响应时直接返回字符串
                    }
                } else {
                    reject(new Error(`HTTP ${res.statusCode}: ${raw}`));
                }
            });
        });
        req.on('error', reject);
        req.write(data);
        req.end();
    });
}

/**
 * 同步远程调用 (对应 zAPI 的 API_Call)
 * @param {string} app   - 目标应用名 (固定为 "NodeGateway")
 * @param {string} api   - API 名称 (如 "add")
 * @param {Array}  args  - 参数列表 (会被序列化为 JSON)
 * @param {number} timeout - 超时毫秒数 (默认 5000)
 * @returns {Promise<any>} 返回结果
 */
async function call(app, api, args, timeout = 5000) {
    const resp = await request('POST', '/call', { app, api, args, timeout });
    if (resp.error) throw new Error(resp.error);
    return resp.result;
}

/**
 * 单向通知 (对应 zAPI 的 API_Notify)
 * @param {string} app - 目标应用名 (固定为 "NodeGateway")
 * @param {string} api - API 名称 (如 "log")
 * @param {Array}  args - 参数列表
 * @returns {Promise<void>}
 */
async function notify(app, api, args) {
    await request('POST', '/notify', { app, api, args });
}

// ---------- 演示：调用内置 add 和 log ----------
async function main() {
    try {
        // 调用加法
        console.log('📞 调用 add(10, 20)...');
        const sum = await call('NodeGateway', 'add', [10, 20]);
        console.log('✅ 结果:', sum);

        // 发送日志通知
        console.log('📨 发送日志通知...');
        await notify('NodeGateway', 'log', ['INFO', 'Hello from Node.js']);
        console.log('✅ 通知已发送');
    } catch (err) {
        console.error('❌ 错误:', err.message);
    }
}

// 如果直接运行此脚本，执行 main()
if (require.main === module) {
    main();
}

// 导出函数以便其他模块使用
module.exports = { call, notify };