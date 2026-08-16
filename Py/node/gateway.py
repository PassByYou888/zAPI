#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
极简 Python 网关 – 暴露 HTTP 接口调用 zAPI 内置 add 和 log
所有 API 注册到同一个 App 中，避免多 App 冲突。
使用方法：
  1. 确保 Binary 目录下有 z_api_hub64.dll 和 z_ipc_64.dll
  2. 运行: python gateway.py --port 8080 --endpoint ipc:gateway
  3. Node.js 通过 POST /call 和 /notify 调用
"""

import sys
import os
import json
import ctypes
import argparse
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
import socketserver

# 将上级目录（Py）加入模块搜索路径，以便导入 api_hub
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))
from api_hub import _native
from api_hub.core import App

# ==================== 全局应用句柄 ====================
APP = None

# ==================== 简单日志函数 ====================
def log(msg):
    print(f"[Gateway] {msg}", flush=True)

def log_err(msg):
    print(f"[ERROR] {msg}", flush=True)

# ==================== 内置 add 回调 ====================
def add_callback(trigger, inp, out):
    """加法：接收 JSON 数组 [a, b]，返回 JSON 数字"""
    inp_h = inp.raw
    out_h = out.raw
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
        if isinstance(args, list) and len(args) >= 2:
            a, b = args[0], args[1]
            result = a + b
            log(f"add({a}, {b}) = {result}")
            resp = json.dumps(result).encode('utf-8') + b'\x00'
            _native.API_WriteBuffer(out_h, ctypes.c_char_p(resp), len(resp))
    except Exception as e:
        log_err(f"add_callback exception: {e}")

# ==================== 内置 log 通知回调 ====================
def log_notify(trigger, inp):
    """打印接收到的日志通知"""
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
    global APP
    APP = App("NodeGateway", "Simple Gateway")           # 应用名，Node 调用时需指定
    APP.register_call("add", add_callback, "a+b")        # 注册 call API
    APP.register_notify("log", log_notify, "Log notify") # 注册 notify API
    log("App created with 'add' and 'log'")

    _native.API_Reset_Prepare()                          # 清空之前准备
    if endpoint.startswith("ipc:"):
        _native.API_Prepare_Service(endpoint.encode('utf-8'), endpoint.encode('utf-8'))
        _native.API_Prepare_Client(endpoint.encode('utf-8'), APP.raw)
    else:
        # TCP 模式：监听所有接口，公布地址为 endpoint
        listen = "0.0.0.0:" + endpoint.split(":")[-1] if ":" in endpoint else "0.0.0.0:9898"
        _native.API_Prepare_Service(listen.encode('utf-8'), endpoint.encode('utf-8'))
        _native.API_Prepare_Client(endpoint.encode('utf-8'), APP.raw)

    ret = _native.API_Prepare_Done()                     # 启动框架，阻塞直到就绪

    # 状态信息由库自动输出到控制台，无需手动获取
    if ret != 1:
        raise RuntimeError("API_Prepare_Done failed")
    log(f"Gateway ready on {endpoint}")

# ==================== HTTP 处理器 ====================
class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # 屏蔽默认日志（避免噪音），可自行开启
        pass

    def do_POST(self):
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
        """处理同步调用"""
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
            payload = json.dumps(args).encode('utf-8')
            _native.API_WriteBuffer(hnd, ctypes.c_char_p(payload), len(payload))
            res = _native.API_Call(app.encode('utf-8'), hnd, timeout)
            if not res:
                self._send_json(500, {"error": "API_Call returned null"})
                return
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
                    self._send_json(200, {"result": raw.decode('utf-8', errors='replace')})
            _native.API_Free_DataHnd(res)
        finally:
            _native.API_Free_DataHnd(hnd)

    def _handle_notify(self, data):
        """处理通知（fire-and-forget）"""
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
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(obj).encode('utf-8'))

class ThreadedServer(socketserver.ThreadingMixIn, HTTPServer):
    allow_reuse_address = True

# ==================== 入口 ====================
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8080, help='HTTP 端口')
    parser.add_argument('--endpoint', default='ipc:gateway', help='zAPI 端点，如 ipc:gateway 或 127.0.0.1:9898')
    args = parser.parse_args()

    try:
        init_gateway(args.endpoint)
    except Exception as e:
        log_err(f"Init failed: {e}")
        sys.exit(1)

    log(f"HTTP server starting on 0.0.0.0:{args.port}")
    server = ThreadedServer(('0.0.0.0', args.port), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("Shutting down...")
        _native.API_Exit_MainThread()
        _native.API_shutdown()
        server.shutdown()

if __name__ == '__main__':
    main()