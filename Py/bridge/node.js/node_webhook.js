// node_webhook.js
// Node.js Webhook 接收服务器 - 供桥接回调

const http = require('http');
const url = require('url');

const PORT = 9002;

const server = http.createServer((req, res) => {
    // 只处理 POST /webhook
    if (req.method !== 'POST' || !req.url.endsWith('/webhook')) {
        res.writeHead(404);
        res.end('Not Found');
        return;
    }

    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
        try {
            const data = JSON.parse(body);
            console.log(`[Node Webhook] Received:`, data);

            // 提取信息
            const { app, api, args, timestamp } = data;

            // 构造响应（echo 风格）
            const response = {
                status: 'ok',
                message: `Node.js processed: ${api}`,
                received: { app, api, args, timestamp }
            };

            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(response));
        } catch (e) {
            console.error('[Node Webhook] Error:', e.message);
            res.writeHead(400);
            res.end(JSON.stringify({ error: 'Invalid JSON' }));
        }
    });
});

server.listen(PORT, () => {
    console.log(`[Node Webhook] Listening on port ${PORT}`);
});

// 优雅关闭
process.on('SIGINT', () => {
    console.log('\n[Node Webhook] Shutting down...');
    server.close();
    process.exit(0);
});