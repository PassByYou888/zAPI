#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
js_api.py - 浏览器调用 zAPI 演示网关
=====================================
通过 Python 网关将 zAPI 能力暴露给浏览器 JavaScript。

【架构说明】
   浏览器 (JavaScript)  →  HTTP (fetch)  →  Python 网关 (js_api.py)  →  zAPI 动态库 (C4 服务网格)
   
   用户通过浏览器打开 http://127.0.0.1:8080/，页面中的 JS 通过 fetch 调用 /call 和 /notify，
   Python 网关将这些请求转换为 zAPI 的 C 函数调用，实现跨语言 RPC。

【zAPI 简介】
   zAPI 是基于 C4 分布式服务网格的轻量级 RPC 框架，通过纯 C ABI 提供跨语言调用能力。
   支持的语言：C/C++, Python, Go, Rust, Java, C#, Pascal, Node.js 等。
   通信模式：同步调用 (Call) 和单向通知 (Notify)。
   底层自动处理服务发现、负载均衡、断线重连、NAT 穿透。

【使用步骤】
   1. 确保 Binary 目录下有 z_api_hub64.dll 和 z_ipc_64.dll。
   2. 在 Py\node 目录下执行：
        $env:PATH = "..\..\Binary;" + $env:PATH
        python js_api.py --port 8080 --endpoint ipc:gateway
   3. 在浏览器中打开 http://127.0.0.1:8080/ 即可体验。

【如何扩展新 API】
   1. 在下方 "内置 API 回调" 区域定义新的回调函数（参照 add_callback）。
   2. 在 init_gateway() 中用 APP.register_call() 或 APP.register_notify() 注册。
   3. 在浏览器端的 JavaScript 中调用 callAPI() 或 notifyAPI()，传入新的 API 名即可。
"""

import sys
import os
import json
import ctypes
import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
import socketserver

# 将上级目录（Py）加入模块搜索路径，以便导入 api_hub 包
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))
from api_hub import _native
from api_hub.core import App

# ==================== 全局应用句柄 ====================
# APP 是 zAPI 的应用上下文，所有 API 都注册在此应用下
APP = None


# ==================== 简单日志函数 ====================
def log(msg):
    """打印信息日志（带前缀）"""
    print(f"[JS-API] {msg}", flush=True)


def log_err(msg):
    """打印错误日志"""
    print(f"[ERROR] {msg}", flush=True)


# ==================== 内置 API 回调 ====================
# 所有回调函数都在 zAPI 的线程池中执行，必须快速返回，不能阻塞。
# 回调参数：
#   trigger: 用户数据指针（注册时传入，此处未使用）
#   inp: DataHandle 对象（只读），包含请求参数（JSON 格式）
#   out: DataHandle 对象（只写），用于写入响应数据（JSON 格式）

def add_callback(trigger, inp, out):
    """
    加法回调 (Call 模式)
    接收 JSON 数组 [a, b]，返回 JSON 数字 (a+b)
    """
    # 获取底层原生句柄（ctypes 指针）
    inp_h = inp.raw
    out_h = out.raw

    # 读取输入数据的大小
    size = _native.API_GetSize(inp_h)
    if size == 0:
        return

    # 读取原始字节
    buf = ctypes.create_string_buffer(size)
    _native.API_SetPos(inp_h, 0)
    _native.API_ReadBuffer(inp_h, buf, size)
    raw = buf.raw[:size]

    # 去除末尾的 '\x00'（JSON 序列化时添加的终止符）
    if raw and raw[-1] == 0:
        raw = raw.rstrip(b'\x00')

    try:
        # 尝试解析 JSON 数组
        args = json.loads(raw.decode('utf-8'))
        if isinstance(args, list) and len(args) >= 2:
            a, b = args[0], args[1]
            result = a + b
            log(f"add({a}, {b}) = {result}")

            # 将结果序列化为 JSON 并写入输出句柄（加 '\x00' 作为终止符）
            resp = json.dumps(result).encode('utf-8') + b'\x00'
            _native.API_WriteBuffer(out_h, ctypes.c_char_p(resp), len(resp))
    except Exception as e:
        log_err(f"add_callback exception: {e}")


def log_notify(trigger, inp):
    """
    日志通知回调 (Notify 模式)
    接收 JSON 数组 [level, message]，打印到控制台
    """
    inp_h = inp.raw
    size = _native.API_GetSize(inp_h)
    if size == 0:
        return

    buf = ctypes.create_string_buffer(size)
    _native.API_SetPos(inp_h, 0)
    _native.API_ReadBuffer(inp_h, buf, size)
    raw = buf.raw[:size]
    if raw and raw[-1] == 0:
        raw = raw.rstrip(b'\x00')

    try:
        args = json.loads(raw.decode('utf-8'))
        log(f"[LOG] {args}")
    except Exception as e:
        log_err(f"log_notify parse error: {e}")


# ==================== 初始化网关 ====================
def init_gateway(endpoint):
    """
    初始化 zAPI 网关：
      1. 创建应用 (App) 并注册 API
      2. 准备网络（IPC 或 TCP）
      3. 启动 C4 框架
    """
    global APP
    APP = App("NodeGateway", "Browser API Gateway")      # 应用名，浏览器调用时需指定
    APP.register_call("add", add_callback, "a+b")        # 注册同步 API
    APP.register_notify("log", log_notify, "Log notify") # 注册通知 API
    log("App created with 'add' (call) and 'log' (notify)")

    # 清空之前的网络准备状态
    _native.API_Reset_Prepare()

    # 根据端点类型选择 IPC 或 TCP
    if endpoint.startswith("ipc:"):
        # IPC 模式（本机进程间通信）
        _native.API_Prepare_Service(endpoint.encode('utf-8'), endpoint.encode('utf-8'))
        _native.API_Prepare_Client(endpoint.encode('utf-8'), APP.raw)
    else:
        # TCP 模式（跨机器）
        # 监听所有网络接口，公布地址为 endpoint（例如 127.0.0.1:9898）
        listen = "0.0.0.0:" + endpoint.split(":")[-1] if ":" in endpoint else "0.0.0.0:9898"
        _native.API_Prepare_Service(listen.encode('utf-8'), endpoint.encode('utf-8'))
        _native.API_Prepare_Client(endpoint.encode('utf-8'), APP.raw)

    # 启动 C4 框架（阻塞直到网络就绪）
    ret = _native.API_Prepare_Done()

    # 状态信息由库自动输出到控制台，无需手动获取
    if ret != 1:
        raise RuntimeError("API_Prepare_Done failed")
    log(f"Gateway ready on {endpoint}")


# ==================== 嵌入式 HTML 页面 ====================
HTML_PAGE = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>zAPI 浏览器调用演示</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #e8f0fe 0%, #d4e4f7 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .container {
            max-width: 820px;
            width: 100%;
            background: rgba(255,255,255,0.95);
            border-radius: 20px;
            padding: 40px 35px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.15);
            backdrop-filter: blur(10px);
        }
        h1 {
            font-size: 28px;
            color: #1a2a4a;
            margin-bottom: 6px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .subtitle {
            color: #5a6a8a;
            font-size: 14px;
            margin-bottom: 20px;
            border-left: 3px solid #4a7cf7;
            padding-left: 14px;
        }
        /* 状态栏 */
        .status-bar {
            background: #f0f4ff;
            border-radius: 10px;
            padding: 10px 16px;
            margin-bottom: 20px;
            font-size: 14px;
            color: #2a4a7a;
            display: flex;
            align-items: center;
            gap: 10px;
            flex-wrap: wrap;
        }
        .status-dot {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: #27ae60;
            animation: pulse 1.5s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; transform: scale(1); }
            50% { opacity: 0.5; transform: scale(0.8); }
        }
        .status-bar .right { margin-left:auto; font-size:12px; color:#6a8aaa; }

        /* ===== zAPI 说明卡片 ===== */
        .info-card {
            background: #f8faff;
            border-radius: 14px;
            padding: 18px 22px;
            margin-bottom: 25px;
            border: 1px solid #e0eaf5;
        }
        .info-card h2 {
            font-size: 17px;
            color: #1a2a4a;
            margin-bottom: 8px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .info-card p {
            font-size: 14px;
            line-height: 1.7;
            color: #3a4a6a;
            margin: 4px 0;
        }
        .info-card .tags {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
            margin-top: 8px;
        }
        .info-card .tag {
            background: #e0ecff;
            color: #1a4a8a;
            padding: 2px 12px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: 500;
        }
        .info-card .tag.green { background: #d4edda; color: #155724; }
        .info-card .tag.orange { background: #fff3cd; color: #856404; }

        /* 功能卡片 */
        .card {
            background: #f8faff;
            border-radius: 14px;
            padding: 22px 24px;
            margin-bottom: 20px;
            border: 1px solid #e6edf8;
            transition: border-color 0.2s;
        }
        .card:hover { border-color: #c0d4f0; }
        .card-title {
            font-weight: 600;
            font-size: 16px;
            color: #1a2a4a;
            margin-bottom: 14px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .badge {
            font-size: 11px;
            background: #4a7cf7;
            color: white;
            padding: 2px 10px;
            border-radius: 12px;
            font-weight: 500;
        }
        .badge.notify-badge { background: #f39c12; }
        .row {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            align-items: center;
        }
        input[type="number"], input[type="text"] {
            padding: 10px 14px;
            border: 2px solid #dce4f0;
            border-radius: 8px;
            font-size: 15px;
            background: white;
            transition: border 0.2s;
            flex: 1;
            min-width: 80px;
        }
        input:focus {
            outline: none;
            border-color: #4a7cf7;
            box-shadow: 0 0 0 3px rgba(74,124,247,0.15);
        }
        input[type="text"] { flex: 2; min-width: 150px; }
        .btn {
            padding: 10px 24px;
            border: none;
            border-radius: 8px;
            font-size: 15px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.2s;
            display: inline-flex;
            align-items: center;
            gap: 6px;
            white-space: nowrap;
        }
        .btn-primary {
            background: #4a7cf7;
            color: white;
        }
        .btn-primary:hover { background: #3a6ae0; transform: translateY(-1px); }
        .btn-primary:disabled { background: #a0b8e0; cursor: not-allowed; transform: none; }
        .btn-warning {
            background: #f39c12;
            color: white;
        }
        .btn-warning:hover { background: #d68910; transform: translateY(-1px); }
        .btn-warning:disabled { background: #d4b87a; cursor: not-allowed; transform: none; }
        .result-box {
            margin-top: 14px;
            padding: 14px 18px;
            background: white;
            border-radius: 8px;
            border: 1px solid #e6edf8;
            font-size: 15px;
            min-height: 50px;
            display: flex;
            align-items: center;
            color: #1a2a4a;
        }
        .result-box .loading { color: #6a8aba; }
        .result-box .success { color: #27ae60; font-weight: 500; }
        .result-box .error { color: #e74c3c; font-weight: 500; }
        .log-area {
            margin-top: 14px;
            padding: 14px 18px;
            background: #1a2a3a;
            border-radius: 8px;
            min-height: 80px;
            max-height: 200px;
            overflow-y: auto;
            font-family: 'Courier New', monospace;
            font-size: 13px;
            color: #aaccee;
            line-height: 1.6;
        }
        .log-area .log-entry {
            border-bottom: 1px solid #2a3a4a;
            padding: 3px 0;
        }
        .log-area .log-entry:last-child { border-bottom: none; }
        .log-area .time { color: #6a8aaa; }
        .footer {
            margin-top: 25px;
            text-align: center;
            font-size: 12px;
            color: #8a9aaa;
            border-top: 1px solid #e6edf8;
            padding-top: 18px;
        }
        @media (max-width: 600px) {
            .container { padding: 20px 16px; }
            .row { flex-direction: column; }
            .btn { width: 100%; justify-content: center; }
            input { width: 100%; }
            .status-bar .right { margin-left:0; width:100%; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>⚡ zAPI · 浏览器调用</h1>
        <div class="subtitle">通过 Python 网关，在浏览器中直接调用 zAPI 服务</div>

        <!-- 状态栏 -->
        <div class="status-bar">
            <span class="status-dot"></span>
            <span>网关运行中 · 应用: <strong>NodeGateway</strong></span>
            <span class="right">端点: ipc:gateway</span>
        </div>

        <!-- ===== zAPI 说明卡片 ===== -->
        <div class="info-card">
            <h2>📖 关于 zAPI</h2>
            <p>
                <strong>zAPI</strong> 是基于 <strong>C4 分布式服务网格</strong> 的跨语言 RPC 框架，
                通过纯 C ABI 提供高性能、轻量级的远程调用能力。
                支持 <strong>Call（请求-响应）</strong> 和 <strong>Notify（单向通知）</strong> 两种通信模式。
            </p>
            <p>
                它让不同语言（C/C++, Python, Go, Rust, Java, C#, Pascal, Node.js 等）编写的服务能够无缝互调，
                自动处理服务发现、负载均衡、断线重连和 NAT 穿透。
            </p>
            <p style="margin-top:6px; font-size:13px; color:#5a7a9a;">
                🌐 当前网关已注册 API：<code>add</code> (Call) 和 <code>log</code> (Notify)
            </p>
            <div class="tags">
                <span class="tag">✅ 跨语言</span>
                <span class="tag green">⚡ 高性能</span>
                <span class="tag orange">🔌 零配置服务发现</span>
                <span class="tag">📦 支持 IPC / TCP</span>
            </div>
        </div>

        <!-- ====== CALL 卡片 ====== -->
        <div class="card">
            <div class="card-title">
                📞 同步调用 (Call)
                <span class="badge">请求-响应</span>
            </div>
            <div class="row">
                <input type="number" id="numA" value="10" step="any">
                <span style="font-size:20px;color:#6a8aaa;">+</span>
                <input type="number" id="numB" value="20" step="any">
                <button class="btn btn-primary" id="btnAdd">计算</button>
            </div>
            <div class="result-box" id="callResult">
                <span style="color:#8a9aaa;">输入两个数字，点击计算</span>
            </div>
        </div>

        <!-- ====== NOTIFY 卡片 ====== -->
        <div class="card">
            <div class="card-title">
                📨 单向通知 (Notify)
                <span class="badge notify-badge">fire-and-forget</span>
            </div>
            <div class="row">
                <input type="text" id="logMsg" placeholder="输入日志消息..." value="Hello from Browser!">
                <button class="btn btn-warning" id="btnLog">发送日志</button>
            </div>
            <div class="log-area" id="logDisplay">
                <div style="color:#6a8aaa;">等待发送日志...</div>
            </div>
        </div>

        <div class="footer">
            🚀 浏览器 JavaScript → Python 网关 → zAPI (C4 服务网格)
        </div>
    </div>

    <script>
        // ============================================================
        // 浏览器端 JavaScript — 通过 fetch 调用 Python 网关
        // ============================================================

        const GATEWAY = '';  // 同源，留空即可

        /**
         * 调用同步 API (POST /call)
         * @param {string} app    - 应用名 (固定为 "NodeGateway")
         * @param {string} api    - API 名称 (如 "add")
         * @param {Array}  args   - 参数列表
         * @param {number} timeout - 超时毫秒数
         * @returns {Promise<any>} 返回结果
         */
        async function callAPI(app, api, args, timeout = 5000) {
            const resp = await fetch('/call', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ app, api, args, timeout })
            });
            if (!resp.ok) {
                const text = await resp.text();
                throw new Error(`HTTP ${resp.status}: ${text}`);
            }
            const data = await resp.json();
            if (data.error) throw new Error(data.error);
            return data.result;
        }

        /**
         * 发送通知 (POST /notify)
         * @param {string} app  - 应用名
         * @param {string} api  - API 名称
         * @param {Array}  args - 参数列表
         */
        async function notifyAPI(app, api, args) {
            const resp = await fetch('/notify', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ app, api, args })
            });
            if (!resp.ok) {
                const text = await resp.text();
                throw new Error(`HTTP ${resp.status}: ${text}`);
            }
            const data = await resp.json();
            if (data.error) throw new Error(data.error);
        }

        // ---- DOM 引用 ----
        const numA = document.getElementById('numA');
        const numB = document.getElementById('numB');
        const btnAdd = document.getElementById('btnAdd');
        const callResult = document.getElementById('callResult');

        const logMsg = document.getElementById('logMsg');
        const btnLog = document.getElementById('btnLog');
        const logDisplay = document.getElementById('logDisplay');

        // ---- 加法 ----
        btnAdd.addEventListener('click', async function() {
            const a = parseFloat(numA.value) || 0;
            const b = parseFloat(numB.value) || 0;
            this.disabled = true;
            callResult.innerHTML = '<span class="loading">⏳ 调用中...</span>';

            try {
                const result = await callAPI('NodeGateway', 'add', [a, b]);
                callResult.innerHTML = `<span class="success">✅ ${a} + ${b} = ${result}</span>`;
            } catch (err) {
                callResult.innerHTML = `<span class="error">❌ 错误: ${err.message}</span>`;
            } finally {
                this.disabled = false;
            }
        });

        // 回车触发计算
        [numA, numB].forEach(el => {
            el.addEventListener('keydown', (e) => { if (e.key === 'Enter') btnAdd.click(); });
        });

        // ---- 日志通知 ----
        function appendLog(msg, type = 'info') {
            const entry = document.createElement('div');
            entry.className = 'log-entry';
            const time = new Date().toLocaleTimeString();
            const emoji = type === 'info' ? '📘' : '❌';
            entry.innerHTML = `<span class="time">[${time}]</span> ${emoji} ${msg}`;
            logDisplay.appendChild(entry);
            logDisplay.scrollTop = logDisplay.scrollHeight;
            // 保留最近 50 条
            while (logDisplay.children.length > 50) {
                logDisplay.removeChild(logDisplay.firstChild);
            }
        }

        btnLog.addEventListener('click', async function() {
            const msg = logMsg.value.trim() || 'empty';
            this.disabled = true;
            appendLog('⏳ 发送中...', 'info');

            try {
                await notifyAPI('NodeGateway', 'log', ['INFO', msg]);
                appendLog(`✅ 通知已发送: "${msg}"`, 'info');
            } catch (err) {
                appendLog(`❌ 发送失败: ${err.message}`, 'error');
            } finally {
                this.disabled = false;
            }
        });

        // 回车发送日志
        logMsg.addEventListener('keydown', (e) => { if (e.key === 'Enter') btnLog.click(); });

        // ---- 页面加载完成提示 ----
        console.log('🚀 zAPI 浏览器演示已加载');
        console.log('📞 调用 /call 和 /notify 与 Python 网关通信');
    </script>
</body>
</html>
"""

# ==================== HTTP 处理器 ====================
class Handler(BaseHTTPRequestHandler):
    """
    HTTP 请求处理器：
      - GET / 或 /index.html  → 返回 HTML 页面
      - POST /call            → 处理同步调用
      - POST /notify          → 处理通知
    """
    def do_GET(self):
        if self.path == '/' or self.path == '/index.html':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(HTML_PAGE.encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'Not Found')

    def log_message(self, format, *args):
        # 屏蔽默认的 HTTP 日志（避免干扰）
        pass

    def do_POST(self):
        """处理 POST 请求，解析 JSON 并路由到 /call 或 /notify"""
        try:
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length)
            data = json.loads(body.decode('utf-8')) if body else {}

            if self.path == '/call':
                self._handle_call(data)
            elif self.path == '/notify':
                self._handle_notify(data)
            else:
                self._send_json(404, {"error": "Not found"})
        except json.JSONDecodeError:
            self._send_json(400, {"error": "Invalid JSON"})
        except Exception as e:
            self._send_json(500, {"error": str(e)})

    def _handle_call(self, data):
        """
        处理 /call 请求：
          - 从 JSON 中提取 app, api, args, timeout
          - 创建 DataHnd，写入序列化后的参数
          - 调用 API_Call，读取响应并返回
        """
        app = data.get('app')
        api = data.get('api')
        args = data.get('args', [])
        timeout = data.get('timeout', 5000)
        if not app or not api:
            self._send_json(400, {"error": "Missing 'app' or 'api'"})
            return

        log(f"CALL {app}.{api} args={args}")
        hnd = _native.API_Create_DataHnd(api.encode('utf-8'))
        if not hnd:
            self._send_json(500, {"error": "Create DataHnd failed"})
            return

        try:
            # 将参数序列化为 JSON 并写入 DataHnd
            payload = json.dumps(args).encode('utf-8')
            _native.API_WriteBuffer(hnd, ctypes.c_char_p(payload), len(payload))

            # 执行同步调用
            res = _native.API_Call(app.encode('utf-8'), hnd, timeout)
            if not res:
                self._send_json(500, {"error": "API_Call returned null"})
                return

            # 读取响应
            size = _native.API_GetSize(res)
            if size == 0:
                self._send_json(200, {"result": None, "error": "timeout or empty"})
            else:
                buf = ctypes.create_string_buffer(size)
                _native.API_SetPos(res, 0)
                _native.API_ReadBuffer(res, buf, size)
                raw = buf.raw[:size]
                if raw and raw[-1] == 0:
                    raw = raw.rstrip(b'\x00')
                try:
                    result = json.loads(raw.decode('utf-8'))
                    self._send_json(200, {"result": result})
                except:
                    # 如果不是 JSON，直接返回原始字符串
                    self._send_json(200, {"result": raw.decode('utf-8', errors='replace')})
            _native.API_Free_DataHnd(res)
        finally:
            _native.API_Free_DataHnd(hnd)

    def _handle_notify(self, data):
        """
        处理 /notify 请求：
          - 从 JSON 中提取 app, api, args
          - 创建 DataHnd，写入序列化后的参数
          - 调用 API_Notify（fire-and-forget）
        """
        app = data.get('app')
        api = data.get('api')
        args = data.get('args', [])
        if not app or not api:
            self._send_json(400, {"error": "Missing 'app' or 'api'"})
            return

        log(f"NOTIFY {app}.{api} args={args}")
        hnd = _native.API_Create_DataHnd(api.encode('utf-8'))
        if not hnd:
            self._send_json(500, {"error": "Create DataHnd failed"})
            return

        try:
            payload = json.dumps(args).encode('utf-8')
            _native.API_WriteBuffer(hnd, ctypes.c_char_p(payload), len(payload))
            _native.API_Notify(app.encode('utf-8'), hnd)
            self._send_json(200, {"status": "ok"})
        finally:
            _native.API_Free_DataHnd(hnd)

    def _send_json(self, code, obj):
        """发送 JSON 响应"""
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(obj).encode('utf-8'))


# ==================== 启动服务器 ====================
class ThreadedServer(socketserver.ThreadingMixIn, HTTPServer):
    """支持多线程的 HTTP 服务器，允许并发处理请求"""
    allow_reuse_address = True


def main():
    parser = argparse.ArgumentParser(description="zAPI 浏览器演示网关")
    parser.add_argument('--port', type=int, default=8080, help='HTTP 端口 (默认: 8080)')
    parser.add_argument('--endpoint', default='ipc:gateway',
                        help='zAPI 端点，如 ipc:gateway 或 127.0.0.1:9898')
    args = parser.parse_args()

    try:
        init_gateway(args.endpoint)
    except Exception as e:
        log_err(f"初始化失败: {e}")
        sys.exit(1)

    log(f"HTTP 服务启动: http://127.0.0.1:{args.port}")
    log("在浏览器中打开上述地址即可体验")

    server = ThreadedServer(('0.0.0.0', args.port), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("\n正在关闭...")
        _native.API_Exit_MainThread()
        _native.API_shutdown()
        server.shutdown()


if __name__ == '__main__':
    main()