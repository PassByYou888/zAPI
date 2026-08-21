#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Cross Bridge – 轻量级 HTTP 中转站
用于 PHP/Node.js/Web.js 调用 zAPI cross 服务（demo 应用）
仅支持主动调用，不提供 Webhook 注册。
"""
import sys
import os
import json
import ctypes
import logging
import struct
import argparse
import atexit
from flask import Flask, request, jsonify

# 添加上级目录以导入 api_hub
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from api_hub import _native
from api_hub.core import DataHandle

# ---------- 全局配置 ----------
HTTP_HOST = '0.0.0.0'
HTTP_PORT = 8081
APP_NAME = 'demo'
TIMEOUT_MS = 2000
ENDPOINT = 'ipc:cross'

flask_app = Flask(__name__)
flask_app.logger.disabled = True
werkzeug_log = logging.getLogger('werkzeug')
werkzeug_log.setLevel(logging.ERROR)

# ---------- CORS ----------
@flask_app.after_request
def after_request(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    response.headers['Access-Control-Allow-Methods'] = 'POST, GET, OPTIONS'
    return response

# ---------- 清理函数 ----------
def cleanup():
    """释放 zAPI 资源"""
    try:
        _native.API_Exit_MainThread()
        _native.API_shutdown()
        print("[CrossBridge] 资源已释放")
    except:
        pass

# 注册退出清理
atexit.register(cleanup)

# ---------- 底层调用函数 ----------
def zapi_call_add(args, timeout_ms=TIMEOUT_MS):
    """调用 add：写入两个 int32，读取 int32"""
    if len(args) < 2:
        return False, "add 需要两个参数"
    a, b = args[0], args[1]
    hnd = _native.API_Create_DataHnd(b"add")
    if not hnd:
        return False, "创建 DataHandle 失败"
    try:
        _native.API_WriteBuffer(hnd, ctypes.c_char_p(a.to_bytes(4, 'little', signed=True)), 4)
        _native.API_WriteBuffer(hnd, ctypes.c_char_p(b.to_bytes(4, 'little', signed=True)), 4)
        result_hnd = _native.API_Call(APP_NAME.encode('utf-8'), hnd, timeout_ms)
        if not result_hnd:
            return False, "API_Call 返回空句柄"
        size = _native.API_GetSize(result_hnd)
        if size != 4:
            _native.API_Free_DataHnd(result_hnd)
            return False, f"add 返回数据长度错误: {size}"
        buf = ctypes.create_string_buffer(4)
        _native.API_SetPos(result_hnd, 0)
        _native.API_ReadBuffer(result_hnd, buf, 4)
        result = int.from_bytes(buf.raw[:4], 'little', signed=True)
        _native.API_Free_DataHnd(result_hnd)
        return True, result
    except Exception as e:
        return False, str(e)
    finally:
        _native.API_Free_DataHnd(hnd)

def zapi_call_inv_seri(timeout_ms=TIMEOUT_MS):
    """调用 inv_seri：写入固定六个字段，读取并返回描述字符串"""
    hnd = _native.API_Create_DataHnd(b"inv_seri")
    if not hnd:
        return False, "创建 DataHandle 失败"
    try:
        b = 200
        w = 0x10
        c = 0x2F
        u64 = 0x3F
        s = "hello world"
        f = 3.14
        # 写入 uint8
        _native.API_WriteBuffer(hnd, ctypes.c_char_p(b.to_bytes(1, 'little')), 1)
        # uint16
        _native.API_WriteBuffer(hnd, ctypes.c_char_p(w.to_bytes(2, 'little')), 2)
        # uint32
        _native.API_WriteBuffer(hnd, ctypes.c_char_p(c.to_bytes(4, 'little')), 4)
        # uint64
        _native.API_WriteBuffer(hnd, ctypes.c_char_p(u64.to_bytes(8, 'little')), 8)
        # string + #0
        s_bytes = s.encode('utf-8') + b'\x00'
        _native.API_WriteBuffer(hnd, ctypes.c_char_p(s_bytes), len(s_bytes))
        # float
        _native.API_WriteBuffer(hnd, ctypes.c_char_p(struct.pack('<f', f)), 4)
        result_hnd = _native.API_Call(APP_NAME.encode('utf-8'), hnd, timeout_ms)
        if not result_hnd:
            return False, "API_Call 返回空句柄"
        size = _native.API_GetSize(result_hnd)
        if size == 0:
            _native.API_Free_DataHnd(result_hnd)
            return False, "服务无响应（demo.inv_seri）"
        buf = ctypes.create_string_buffer(size)
        _native.API_SetPos(result_hnd, 0)
        _native.API_ReadBuffer(result_hnd, buf, size)
        data = buf.raw[:size]
        pos = 0
        try:
            f_ret = struct.unpack('<f', data[pos:pos+4])[0]; pos += 4
            null_idx = data.find(b'\x00', pos)
            if null_idx == -1:
                return False, "回复中无字符串终止符"
            s_ret = data[pos:null_idx].decode('utf-8')
            pos = null_idx + 1
            u64_ret = struct.unpack('<Q', data[pos:pos+8])[0]; pos += 8
            c_ret = struct.unpack('<I', data[pos:pos+4])[0]; pos += 4
            w_ret = struct.unpack('<H', data[pos:pos+2])[0]; pos += 2
            b_ret = data[pos] if pos < len(data) else 0
        except Exception as e:
            _native.API_Free_DataHnd(result_hnd)
            return False, f"解析响应失败: {e}"
        _native.API_Free_DataHnd(result_hnd)
        result_str = (f"接收数据序 [{b_ret}, {w_ret}, {c_ret}, {u64_ret}, \"{s_ret}\", {f_ret:.2f}] = "
                      f"发送数据序 [{f_ret:.2f}, \"{s_ret}\", {u64_ret}, {c_ret}, {w_ret}, {b_ret}]")
        return True, result_str
    except Exception as e:
        return False, str(e)
    finally:
        _native.API_Free_DataHnd(hnd)

# ---------- Flask 路由 ----------
@flask_app.route('/cross', methods=['POST', 'OPTIONS'])
def handle_cross():
    if request.method == 'OPTIONS':
        return '', 200
    try:
        data = request.get_json()
        if not data:
            return jsonify({"code": -2, "error": "缺少 JSON 体"}), 400
    except Exception as e:
        return jsonify({"code": -2, "error": f"无效 JSON: {e}"}), 400

    api = data.get('api')
    args = data.get('args', [])
    timeout = data.get('timeout', TIMEOUT_MS)

    if not api:
        return jsonify({"code": -2, "error": "缺少 'api' 字段"}), 400

    if api == 'add':
        success, result = zapi_call_add(args, timeout)
    elif api == 'inv_seri':
        success, result = zapi_call_inv_seri(timeout)
    else:
        return jsonify({"code": -2, "error": f"不支持的 API: {api}"}), 400

    if success:
        return jsonify({"code": 0, "result": result})
    else:
        return jsonify({"code": -1, "error": result}), 200

@flask_app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok", "app": "CrossBridge"})

# ---------- 启动网络 ----------
def setup_network():
    _native.API_Reset_Prepare()
    _native.API_Prepare_Client(ENDPOINT.encode('utf-8'), None)
    if _native.API_Prepare_Done() != 1:
        raise RuntimeError("连接服务网格失败。请确保 cross_service 正在运行。")
    print("[CrossBridge] 已连接到", ENDPOINT)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=HTTP_PORT)
    parser.add_argument('--host', default=HTTP_HOST)
    args = parser.parse_args()

    try:
        setup_network()
    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(1)

    print(f"[CrossBridge] 启动 HTTP 服务 http://{args.host}:{args.port}")
    print("[CrossBridge] 端点: POST /cross")
    print("[CrossBridge] 按 Ctrl+C 可安全退出")

    try:
        # use_reloader=False 防止额外进程阻塞 Ctrl+C
        flask_app.run(host=args.host, port=args.port, threaded=True, use_reloader=False)
    except KeyboardInterrupt:
        print("\n[CrossBridge] 收到中断信号，正在关闭...")
    finally:
        cleanup()

if __name__ == '__main__':
    main()