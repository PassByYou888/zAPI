const http = require('http');

class CrossBridgeClient {
    constructor(baseUrl = 'http://127.0.0.1:8081') {
        this.baseUrl = baseUrl.replace(/\/+$/, '');
    }

    /**
     * 调用远程 API
     * @param {string} api   API 名称
     * @param {Array}  args  参数列表
     * @param {number} timeout 超时（毫秒）
     * @returns {Promise<any>}
     */
    call(api, args = [], timeout = 2000) {
        return new Promise((resolve, reject) => {
            const payload = JSON.stringify({ api, args, timeout });
            const url = new URL(this.baseUrl + '/cross');
            const options = {
                hostname: url.hostname,
                port: url.port || 80,
                path: url.pathname,
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Content-Length': Buffer.byteLength(payload)
                },
                timeout: timeout + 1000
            };
            const req = http.request(options, (res) => {
                let data = '';
                res.on('data', chunk => data += chunk);
                res.on('end', () => {
                    try {
                        const parsed = JSON.parse(data);
                        if (parsed.code !== undefined && parsed.code !== 0) {
                            reject(new Error(`Bridge error: ${parsed.error || 'Unknown'}`));
                        } else {
                            resolve(parsed.result);
                        }
                    } catch (e) {
                        reject(new Error(`Invalid JSON: ${data}`));
                    }
                });
            });
            req.on('error', reject);
            req.on('timeout', () => {
                req.destroy();
                reject(new Error('Request timeout'));
            });
            req.write(payload);
            req.end();
        });
    }
}

// 使用示例
async function main() {
    const client = new CrossBridgeClient('http://127.0.0.1:8081');
    try {
        const sum = await client.call('add', [10, 20]);
        console.log(`10 + 20 = ${sum}`);

        const result = await client.call('inv_seri');
        console.log(`inv_seri 结果: ${result}`);
    } catch (e) {
        console.error('错误:', e.message);
    }
}
main();