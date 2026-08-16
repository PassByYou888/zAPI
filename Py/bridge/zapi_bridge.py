#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
ZAPI HTTP Bridge – 工业级多语言互调网关

═══════════════════════════════════════════════════════════════════════════════
功能概述
═══════════════════════════════════════════════════════════════════════════════
  接收 HTTP 请求，通过 zAPI（基于 C4 服务网格）转发给任意语言的服务，
  或将外部 Webhook 注册为 zAPI 回调，实现双向跨语言调用。

═══════════════════════════════════════════════════════════════════════════════
环境变量配置
═══════════════════════════════════════════════════════════════════════════════
  LOG_LEVEL              日志级别 (DEBUG/INFO/WARNING/ERROR)  默认 INFO
  HTTP_PORT              HTTP 服务端口                        默认 8080
  WEBHOOK_TIMEOUT        Webhook 转发超时（秒）               默认 10
  BRIDGE_LISTEN          zAPI 监听地址                        默认 0.0.0.0:9898
  BRIDGE_PUBLIC          zAPI 公布地址                        默认 127.0.0.1:9898
  PERF_LOG_ENABLED       是否开启性能日志 (1/0)               默认 0 (关闭)
  USE_INDEPENDENT_REQUEST 调试：强制独立 HTTP 请求 (1/0)      默认 0

═══════════════════════════════════════════════════════════════════════════════
启动命令
═══════════════════════════════════════════════════════════════════════════════
  python zapi_bridge.py
"""

import sys
import os
import ctypes
import threading
import time
import logging
import functools
import atexit
from contextlib import contextmanager
from concurrent.futures import ThreadPoolExecutor

# ==================== 依赖检查 ====================
try:
    from flask import Flask, request, jsonify
except ImportError:
    raise ImportError("Flask is required. Install: pip install flask")

try:
    import requests
    from requests.adapters import HTTPAdapter
except ImportError:
    raise ImportError("requests is required. Install: pip install requests")

# ==================== 可选依赖（性能增强） ====================
try:
    import orjson

    def json_dumps(obj):
        return orjson.dumps(obj)

    def json_loads(data):
        return orjson.loads(data)

    _HAS_ORJSON = True
except ImportError:
    import json

    def json_dumps(obj):
        return json.dumps(obj, ensure_ascii=False).encode('utf-8')

    def json_loads(data):
        return json.loads(data.decode('utf-8'))

    _HAS_ORJSON = False

try:
    from waitress import serve
    _HAS_WAITRESS = True
except ImportError:
    serve = None
    _HAS_WAITRESS = False

# ==================== 环境变量配置 ====================
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
HTTP_PORT = int(os.environ.get("HTTP_PORT", 8080))
WEBHOOK_TIMEOUT = int(os.environ.get("WEBHOOK_TIMEOUT", 10))   # 秒
BRIDGE_APP_NAME = "HttpBridge"
BRIDGE_TCP_LISTEN = os.environ.get("BRIDGE_LISTEN", "0.0.0.0:9898")
BRIDGE_TCP_PUBLIC = os.environ.get("BRIDGE_PUBLIC", "127.0.0.1:9898")
HTTP_HOST = "0.0.0.0"
USE_INDEPENDENT_REQUEST = os.environ.get("USE_INDEPENDENT_REQUEST", "0") == "1"

# 性能日志开关（默认关闭，避免生产环境 I/O 开销）
PERF_LOG_ENABLED = os.environ.get("PERF_LOG_ENABLED", "0") == "1"

# ==================== 日志系统 ====================
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="[%(asctime)s] %(levelname)s %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger("ZAPIBridge")

# 如果开启性能日志，创建独立的文件 handler
perf_logger = None
if PERF_LOG_ENABLED:
    perf_logger = logging.getLogger("ZAPIBridge.Perf")
    perf_logger.setLevel(logging.DEBUG)
    fh = logging.FileHandler("bridge_perf.log", encoding='utf-8')
    fh.setLevel(logging.DEBUG)
    formatter = logging.Formatter(
        '%(asctime)s.%(msecs)03d %(levelname)s %(name)s: %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    fh.setFormatter(formatter)
    perf_logger.addHandler(fh)
    perf_logger.propagate = False

# ==================== 性能计时上下文（仅在开启时生效） ====================
@contextmanager
def timing_context(name: str, threshold_ms: float = 0):
    """
    性能计时上下文管理器。

    当 PERF_LOG_ENABLED=1 时，记录代码块耗时并写入性能日志；
    否则，该上下文管理器为零开销（仅 yield）。
    """
    if not PERF_LOG_ENABLED:
        yield
        return

    start = time.perf_counter()
    yield
    elapsed = (time.perf_counter() - start) * 1000
    if elapsed >= threshold_ms:
        perf_logger.warning(f"{name} took {elapsed:.2f} ms")
    else:
        perf_logger.debug(f"{name} took {elapsed:.2f} ms")

# ==================== 全局 HTTP 会话（复用连接） ====================
_session = requests.Session()
adapter = HTTPAdapter(pool_connections=50, pool_maxsize=100, max_retries=0)
_session.mount('http://', adapter)
_session.mount('https://', adapter)
logger.info(f"Session proxies: {_session.proxies}")

# ==================== 导入 zAPI 绑定 ====================
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
from api_hub import Server
from api_hub._native import (
    API_Call, API_Notify,
    API_Create_DataHnd, API_Free_DataHnd,
    API_WriteBuffer, API_ReadBuffer,
    API_SetPos, API_GetSize,
    API_Reset_Prepare, API_Prepare_Service, API_Prepare_Client, API_Prepare_Done,
    API_Exit_MainThread, API_shutdown
)
from api_hub.errors import RegistrationError
from api_hub.core import DataHandle

# ==================== 全局状态 ====================
# registry: 存储已注册的 Webhook 映射
#   key: (app_name, api_name)
#   value: {'url': callback_url, 'mode': 'call' | 'notify'}
registry = {}
registry_lock = threading.RLock()

# registered_apis: 记录已注册到 zAPI 的 API 名称（避免重复注册）
registered_apis = set()

# 线程池：用于转发 Webhook 请求，避免阻塞 zAPI 回调线程
WEBHOOK_EXECUTOR = ThreadPoolExecutor(max_workers=20)

# zAPI 服务器实例（通过装饰器注册 API）
zapi_server = Server(BRIDGE_APP_NAME, "HTTP Bridge")

# ==================== Flask 应用 ====================
flask_app = Flask(__name__)
flask_app.logger.disabled = True
werkzeug_log = logging.getLogger('werkzeug')
werkzeug_log.setLevel(logging.ERROR)

# ==================== 辅助函数 ====================
def get_server_app():
    """获取 zAPI 服务器内部的 App 句柄（用于底层网络准备）。"""
    return zapi_server._app

def _forward_webhook_sync(url, payload, out_handle, timeout):
    """
    在工作线程中同步转发 Webhook 请求，并将响应写入 out_handle。

    Args:
        url: 目标 Webhook URL
        payload: 要发送的 JSON 数据
        out_handle: zAPI 输出句柄（用于写入响应）
        timeout: 超时（秒）
    """
    logger.info(f"[DEBUG] _forward_webhook_sync timeout = {timeout} sec, url={url}")

    with timing_context(f"webhook_http.{url}", threshold_ms=5.0):
        try:
            if USE_INDEPENDENT_REQUEST:
                logger.warning("Using independent requests.post (not Session) for debugging")
                resp = requests.post(url, json=payload, timeout=(timeout, timeout))
            else:
                resp = _session.post(url, json=payload, timeout=(timeout, timeout))
            resp.raise_for_status()
            out = DataHandle._from_raw(out_handle, owned=False)
            out.write(resp.json())
        except requests.exceptions.ConnectTimeout as e:
            logger.error(f"ConnectTimeout to {url}: {e}")
            out = DataHandle._from_raw(out_handle, owned=False)
            out.write({"error": f"ConnectTimeout: {e}"})
        except requests.exceptions.ReadTimeout as e:
            logger.error(f"ReadTimeout to {url}: {e}")
            out = DataHandle._from_raw(out_handle, owned=False)
            out.write({"error": f"ReadTimeout: {e}"})
        except requests.exceptions.ConnectionError as e:
            logger.error(f"ConnectionError to {url}: {e}")
            out = DataHandle._from_raw(out_handle, owned=False)
            out.write({"error": f"ConnectionError: {e}"})
        except requests.exceptions.Timeout as e:
            logger.error(f"Timeout to {url}: {e}")
            out = DataHandle._from_raw(out_handle, owned=False)
            out.write({"error": f"Timeout: {e}"})
        except Exception as e:
            logger.error(f"Request error to {url}: {e}")
            out = DataHandle._from_raw(out_handle, owned=False)
            out.write({"error": str(e)})

def _forward_webhook_async(url, payload):
    """
    异步转发 Webhook 通知（fire-and-forget）。

    Args:
        url: 目标 Webhook URL
        payload: 要发送的 JSON 数据
    """
    try:
        _session.post(url, json=payload, timeout=WEBHOOK_TIMEOUT)
    except Exception:
        pass

def build_webhook_callback(app_name, api_name, mode):
    """
    为指定的 (app, api) 构造 zAPI 回调函数。

    回调函数会在 zAPI 线程池中执行，将请求转发到注册的 Webhook URL。
    对于 'call' 模式，同步等待响应；对于 'notify' 模式，异步发送。

    Args:
        app_name: 应用名
        api_name: API 名
        mode: 'call' 或 'notify'
    Returns:
        zAPI 回调函数
    """
    def callback(trigger, inp, out):
        with timing_context(f"webhook_callback.{app_name}.{api_name}", threshold_ms=10.0):
            # 读取输入参数
            try:
                data = inp.read()
            except Exception as e:
                logger.error(f"Read input failed: {e}")
                if mode == "call":
                    out.write({"error": f"Read input failed: {e}"})
                return

            # 查询注册信息
            with registry_lock:
                entry = registry.get((app_name, api_name))
            if not entry:
                if mode == "call":
                    out.write({"error": f"No webhook for {app_name}.{api_name}"})
                return

            callback_url = entry["url"]
            payload = {
                "app": app_name,
                "api": api_name,
                "args": data,
                "timestamp": time.time()
            }

            if mode == "call":
                logger.debug(f"Submitting webhook with timeout={WEBHOOK_TIMEOUT}")
                future = WEBHOOK_EXECUTOR.submit(
                    _forward_webhook_sync,
                    callback_url, payload, out.raw, WEBHOOK_TIMEOUT
                )
                with timing_context(f"webhook_future_wait.{app_name}.{api_name}"):
                    try:
                        future.result(timeout=WEBHOOK_TIMEOUT + 1)
                    except Exception as e:
                        out.write({"error": f"Webhook internal error: {e}"})
            else:
                # Notify 模式：异步发送，不等待响应
                WEBHOOK_EXECUTOR.submit(_forward_webhook_async, callback_url, payload)

    return callback

def ensure_api_registered(app_name, api_name, mode):
    """
    确保指定的 (app, api) 在 zAPI 中已注册。

    如果尚未注册，则创建回调并注册。注册后存入 registered_apis 避免重复。

    Args:
        app_name: 应用名
        api_name: API 名
        mode: 'call' 或 'notify'
    Raises:
        RuntimeError: 注册失败
    """
    key = (app_name, api_name)
    with registry_lock:
        if key in registered_apis:
            return

    server_app = get_server_app()
    try:
        if mode == "call":
            server_app.register_call(
                api_name,
                build_webhook_callback(app_name, api_name, mode),
                f"Bridge proxy for {app_name}.{api_name}"
            )
        else:
            server_app.register_notify(
                api_name,
                build_webhook_callback(app_name, api_name, mode),
                f"Bridge proxy for {app_name}.{api_name}"
            )
        with registry_lock:
            registered_apis.add(key)
        logger.info(f"Registered {app_name}.{api_name} ({mode})")
    except RegistrationError:
        logger.info(f"API {app_name}.{api_name} already exists, reusing")
        with registry_lock:
            registered_apis.add(key)
    except Exception as e:
        raise RuntimeError(f"Registration failed: {e}")

def zapi_call(app_name, api_name, args, timeout_ms):
    """
    执行 zAPI 同步调用。

    序列化参数，调用 API_Call，反序列化响应。

    Args:
        app_name: 目标应用名
        api_name: API 名
        args: 参数列表
        timeout_ms: 超时毫秒数

    Returns:
        (success: bool, result_or_error: any)
    """
    # 序列化参数
    with timing_context("zapi_call.serialize"):
        payload = json_dumps(args)

    hnd = API_Create_DataHnd(api_name.encode('utf-8'))
    if not hnd:
        return False, "Create handle failed"

    try:
        API_WriteBuffer(hnd, payload, len(payload))

        # C 库调用
        with timing_context("zapi_call.c_lib_call"):
            result_hnd = API_Call(app_name.encode('utf-8'), hnd, timeout_ms)
        if not result_hnd:
            return False, "Call returned null handle"

        size = API_GetSize(result_hnd)
        if size == 0:
            API_Free_DataHnd(result_hnd)
            return False, f"No response from '{app_name}.{api_name}'"

        # 读取并反序列化结果
        with timing_context("zapi_call.deserialize"):
            buf = ctypes.create_string_buffer(size)
            API_SetPos(result_hnd, 0)
            API_ReadBuffer(result_hnd, buf, size)
            raw = buf.raw[:size].rstrip(b'\x00')
            try:
                result = json_loads(raw)
            except Exception:
                result = raw.decode('utf-8', errors='replace')
        API_Free_DataHnd(result_hnd)
        return True, result
    except Exception as e:
        return False, str(e)
    finally:
        API_Free_DataHnd(hnd)

def zapi_notify(app_name, api_name, args):
    """
    发送 zAPI 单向通知。

    Args:
        app_name: 目标应用名
        api_name: API 名
        args: 参数列表
    """
    hnd = API_Create_DataHnd(api_name.encode('utf-8'))
    if not hnd:
        return
    try:
        payload = json_dumps(args)
        API_WriteBuffer(hnd, payload, len(payload))
        API_Notify(app_name.encode('utf-8'), hnd)
    except Exception as e:
        logger.error(f"zapi_notify exception: {e}")
    finally:
        API_Free_DataHnd(hnd)

# ==================== Flask 路由 ====================
@flask_app.route("/v1/invoke", methods=["POST"])
def route_invoke():
    """
    同步调用端点：接收 JSON，调用 zAPI，返回结果。
    """
    with timing_context("route_invoke.total", threshold_ms=20.0):
        try:
            body = request.get_json() or {}
        except Exception as e:
            return jsonify({"code": -2, "error": f"Invalid JSON: {e}"}), 400

        app_name = body.get("app")
        api_name = body.get("api")
        args = body.get("args", [])
        timeout = body.get("timeout", 5000)
        if not app_name or not api_name:
            return jsonify({"code": -2, "error": "Missing app/api"}), 400

        logger.info(f"INVOKE {app_name}.{api_name} args={args}")
        start = time.time()
        success, result = zapi_call(app_name, api_name, args, timeout)
        elapsed_ms = (time.time() - start) * 1000
        logger.debug(f"INVOKE completed in {elapsed_ms:.2f}ms")

        if success:
            return jsonify({"code": 0, "result": result})
        else:
            return jsonify({"code": -1, "error": result}), 200

@flask_app.route("/v1/notify", methods=["POST"])
def route_notify():
    """
    单向通知端点：接收 JSON，发送 zAPI 通知，立即返回。
    """
    try:
        body = request.get_json() or {}
    except Exception as e:
        return jsonify({"code": -2, "error": f"Invalid JSON: {e}"}), 400

    app_name = body.get("app")
    api_name = body.get("api")
    args = body.get("args", [])
    if not app_name or not api_name:
        return jsonify({"code": -2, "error": "Missing app/api"}), 400

    logger.info(f"NOTIFY {app_name}.{api_name} args={args}")
    zapi_notify(app_name, api_name, args)
    return jsonify({"code": 0, "status": "notified"})

@flask_app.route("/v1/hooks/register", methods=["POST"])
def route_register():
    """
    注册 Webhook：将外部 HTTP 服务注册为 zAPI 回调。
    """
    try:
        body = request.get_json() or {}
    except Exception as e:
        return jsonify({"code": -2, "error": f"Invalid JSON: {e}"}), 400

    app_name = body.get("app")
    api_name = body.get("api")
    callback_url = body.get("callback_url")
    mode = body.get("mode", "call")
    if not all([app_name, api_name, callback_url]):
        return jsonify({"code": -2, "error": "Missing fields"}), 400
    if mode not in ("call", "notify"):
        return jsonify({"code": -2, "error": "mode must be 'call' or 'notify'"}), 400

    with registry_lock:
        registry[(app_name, api_name)] = {"url": callback_url, "mode": mode}
    try:
        ensure_api_registered(app_name, api_name, mode)
    except Exception as e:
        return jsonify({"code": -1, "error": str(e)}), 500

    return jsonify({"code": 0, "status": "registered"})

@flask_app.route("/v1/hooks/unregister", methods=["POST"])
def route_unregister():
    """
    注销 Webhook：移除已注册的回调。
    """
    try:
        body = request.get_json() or {}
    except Exception as e:
        return jsonify({"code": -2, "error": f"Invalid JSON: {e}"}), 400

    app_name = body.get("app")
    api_name = body.get("api")
    if not app_name or not api_name:
        return jsonify({"code": -2, "error": "Missing fields"}), 400
    with registry_lock:
        key = (app_name, api_name)
        registry.pop(key, None)
        registered_apis.discard(key)
    return jsonify({"code": 0, "status": "unregistered"})

@flask_app.route("/v1/hooks/list", methods=["GET"])
def route_list_hooks():
    """
    列出所有已注册的 Webhook。
    """
    with registry_lock:
        hooks = [{"app": k[0], "api": k[1], "url": v["url"], "mode": v["mode"]}
                 for k, v in registry.items()]
    return jsonify({"code": 0, "hooks": hooks})

@flask_app.route("/v1/health", methods=["GET"])
def route_health():
    """
    健康检查端点。
    """
    return jsonify({"status": "ok", "app": BRIDGE_APP_NAME})

# ==================== 网络准备 ====================
def setup_network():
    """
    准备 zAPI 网络：重置配置，启动服务端和客户端（暴露本应用）。
    """
    logger.info("Setting up ZAPI network...")
    API_Reset_Prepare()
    API_Prepare_Service(BRIDGE_TCP_LISTEN.encode('utf-8'), BRIDGE_TCP_PUBLIC.encode('utf-8'))
    API_Prepare_Client(BRIDGE_TCP_PUBLIC.encode('utf-8'), zapi_server._app.raw)

    if API_Prepare_Done() != 1:
        raise RuntimeError("Network prepare failed. Check console output.")
    logger.info("ZAPI network ready.")

# ==================== 资源清理 ====================
def cleanup():
    """优雅关闭 Bridge，释放所有资源。"""
    logger.info("Shutting down Bridge...")
    API_Exit_MainThread()
    API_shutdown()
    WEBHOOK_EXECUTOR.shutdown(wait=True)
    logger.info("Bridge stopped.")

# 注册退出清理函数
atexit.register(cleanup)

# ==================== 主程序 ====================
def main():
    """
    主入口：初始化网络，启动 HTTP 服务。
    """
    # 打印配置信息
    logger.info(f"WEBHOOK_TIMEOUT = {WEBHOOK_TIMEOUT} seconds")
    logger.info(f"USE_INDEPENDENT_REQUEST = {USE_INDEPENDENT_REQUEST}")
    logger.info(f"PERF_LOG_ENABLED = {PERF_LOG_ENABLED}")

    try:
        setup_network()
    except Exception as e:
        logger.error(f"Network setup failed: {e}")
        sys.exit(1)

    logger.info(f"HTTP Bridge listening on http://{HTTP_HOST}:{HTTP_PORT}")
    logger.info("Endpoints: /v1/invoke, /v1/notify, /v1/hooks/register, ...")
    logger.info(f"Log level: {LOG_LEVEL}")
    if PERF_LOG_ENABLED:
        logger.info("Performance logs will be written to bridge_perf.log")
    else:
        logger.info("Performance logging is disabled (set PERF_LOG_ENABLED=1 to enable)")

    try:
        if _HAS_WAITRESS and serve is not None:
            serve(flask_app, host=HTTP_HOST, port=HTTP_PORT, threads=16)
        else:
            if not _HAS_WAITRESS:
                logger.warning("Waitress not installed, using Flask built-in server (not for production)")
            flask_app.run(host=HTTP_HOST, port=HTTP_PORT, threaded=True)
    except KeyboardInterrupt:
        logger.info("Shutting down by user...")
    finally:
        cleanup()

if __name__ == "__main__":
    main()