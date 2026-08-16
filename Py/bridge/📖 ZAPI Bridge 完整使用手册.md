# 📖 ZAPI Bridge 完整使用手册

**版本**：2.0  
**适用对象**：开发者、运维人员、技术决策者  
**核心目标**：提供 Bridge 的安装、配置、使用、测试、开发、调优、故障排除全流程指南

---

## 📌 1. 概述

### 1.1 什么是 ZAPI Bridge？

`zapi_bridge.py` 是一个 **HTTP ↔ zAPI 双向网关**，它让 PHP、Node.js、浏览器、Python、Pascal 等语言能够：

- 通过 HTTP 调用 zAPI 多语言服务网格中的任意服务（C++/Python/Go/Rust/Java/C#/Pascal）
- 将外部 HTTP 服务（Webhook）注册为 zAPI 回调，使其他语言反过来调用它们
- 实现真正的"语言透明" —— 任意语言都能互相调用，无需 FFI、无需编译、无需 IDL

### 1.2 核心价值

| 特性         | 说明                                                                             |
| ------------ | -------------------------------------------------------------------------------- |
| **零依赖**   | PHP 只需 cURL，Node.js 只需原生 `http`，Python 只需标准库，Pascal 只需 zAPI 绑定 |
| **零编译**   | 无需 `node-gyp`，无需 PHP FFI 扩展，无需编译任何东西                             |
| **零侵入**   | 你的现有服务（C++/Python/Go）一行代码都不用改                                    |
| **高性能**   | 转发延迟 1-3ms（实测），近乎无感                                                |
| **双向调用** | PHP 能调 Python，Python 也能调 PHP，互相"捅"                                     |
| **生产就绪** | 使用 Waitress 多线程服务器，支持高并发                                           |
| **动态注册** | 支持运行时注册/注销 Webhook，无需重启                                             |

---

## 🧠 2. 工作原理

### 2.1 架构图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          外部调用方（PHP/Node.js/浏览器）                   │
│                              HTTP JSON 请求                                 │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ZAPI Bridge（zapi_bridge.py）                     │
│                                                                             │
│   ┌─────────────┐    ┌─────────────────┐    ┌──────────────────────────┐    │
│   │  Flask App  │───▶│  /v1/invoke     │──-▶│  zapi_call()             │    │
│   │  (HTTP 8080)│    │  /v1/notify     │    │  zapi_notify()           │    │
│   │             │    │  /v1/hooks/*    │    │                          │    │
│   └─────────────┘    └─────────────────┘    └───────────┬──────────────┘    │
│                                                         │                   │
│                                            调用 zAPI C 动态库               │
│                                            (ctypes / _native)               │
└─────────────────────────────────────────────────┬───────────────────────────┘
                                                  │
                                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        zAPI 核心（C4 服务网格）                             │
│                    z_api_hub64.dll / libz_api_hub.so                        │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
              ┌───────────────────┼───────────────────┐
              ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│   C++ 服务      │ │  Python 服务    │ │  Go/Rust/Java   │
│   (高性能计算)  │ │  (AI 推理)      │ │  (微服务)       │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

### 2.2 核心组件

| 组件               | 角色             | 说明                                                                 |
| ------------------ | ---------------- | -------------------------------------------------------------------- |
| **HTTP 服务器**    | 接收外部请求     | 基于 Flask + Waitress，监听 8080 端口                                |
| **API 路由**       | 路由分发         | `/v1/invoke`、`/v1/notify`、`/v1/hooks/*`、`/v1/health`              |
| **zAPI 客户端**    | 调用 zAPI 服务   | 使用 `ctypes` 加载 `z_api_hub64.dll`，调用 `API_Call` / `API_Notify` |
| **Webhook 注册表** | 存储外部服务映射 | 内存字典 `registry`，映射 `(app, api)` → `{url, mode}`               |
| **线程池**         | 并发转发 Webhook | `ThreadPoolExecutor`，默认 20 个 worker                              |
| **性能日志**       | 记录各环节耗时   | 写入 `bridge_perf.log`，便于分析                                     |

### 2.3 数据流

#### 2.3.1 同步调用（`/v1/invoke`）

1. 外部发送 `POST /v1/invoke`，JSON 体包含 `{app, api, args, timeout}`
2. Bridge 解析 JSON，调用 `zapi_call()`
3. `zapi_call()` 序列化参数为 JSON 并写入 `DataHandle`
4. 调用 `API_Call(app, handle, timeout)` 发送给 zAPI 核心
5. zAPI 核心根据 `app` 名称路由到目标服务（可能是本地注册的，也可能是远程的）
6. 目标服务处理并返回结果
7. Bridge 读取结果、反序列化 JSON，返回给外部调用方

#### 2.3.2 Webhook 转发（调用已注册的 Webhook）

1. 外部调用 `POST /v1/invoke`，`app` 为 `HttpBridge`，`api` 为已注册的 Webhook 名称
2. `zapi_call()` 调用 `API_Call('HttpBridge', handle, timeout)`
3. Bridge 自身注册了该 `api` 的回调函数（通过 `build_webhook_callback` 生成）
4. 回调函数查询 `registry` 获取对应的 `callback_url`
5. 回调函数将请求提交给 `WEBHOOK_EXECUTOR` 线程池，实际执行 `requests.post(callback_url, json=payload)`
6. 等待外部 Webhook 响应，将结果写回输出句柄
7. Bridge 将结果返回给调用方

#### 2.3.3 单向通知（`/v1/notify`）

1. 外部发送 `POST /v1/notify`，JSON 体包含 `{app, api, args}`
2. Bridge 调用 `zapi_notify()`，执行 `API_Notify(app, handle)`
3. zAPI 核心发送通知，不等待响应
4. Bridge 立即返回 `{"status":"ok"}`

---

## 🚀 3. 安装与启动

### 3.1 环境要求

| 组件                 | 版本/要求                                                 |
| -------------------- | --------------------------------------------------------- |
| Python               | 3.8+                                                      |
| zAPI 动态库          | `z_api_hub64.dll`（Windows）或 `libz_api_hub.so`（Linux） |
| IPC 依赖             | `z_ipc_64.dll`（Windows）或 `libz_ipc.so`（Linux）        |
| 可选依赖（性能增强） | `orjson`（加快 JSON）、`waitress`（生产级 HTTP）          |

### 3.2 依赖安装

在启动 Bridge 之前，请先安装 Python 依赖：

```bash
cd Py/bridge
pip install -r requirements.txt
```

> 详细依赖清单见 [ZAPI Bridge Python 依赖清单](./ZAPI%20Bridge%20Python%20依赖清单.md)

### 3.3 目录结构

```
DLL-Build/
├── Binary/
│   ├── z_api_hub64.dll      # zAPI 核心库
│   └── z_ipc_64.dll         # IPC 支持库
└── Py/
    ├── api_hub/             # zAPI Python 绑定（必须）
    │   ├── __init__.py
    │   ├── _native.py
    │   ├── core.py
    │   ├── server.py
    │   └── ...
    └── bridge/
        ├── zapi_bridge.py   # ⭐ 主程序
        ├── requirements.txt # 依赖清单
        ├── python_webhook.py
        ├── run_cross_test.ps1
        └── ...
```

### 3.4 启动 Bridge

**Windows（PowerShell）**：

```powershell
cd D:\CoreLibrary\API_Hub_Tool\DLL-Build\Py\bridge
$env:PATH = "..\..\Binary;" + $env:PATH
python zapi_bridge.py
```

**Linux / macOS**：

```bash
cd /path/to/Py/bridge
export PATH="../../Binary:$PATH"
python3 zapi_bridge.py
```

**启动参数**（无需命令行参数，全部通过环境变量配置，见第 4 节）。

**成功标志**：

```
[INFO] WEBHOOK_TIMEOUT = 10 seconds
[INFO] Session proxies: {}
[INFO] ZAPI network ready.
[INFO] HTTP Bridge listening on http://0.0.0.0:8080
[INFO] Endpoints: /v1/invoke, /v1/notify, /v1/hooks/register, ...
[INFO] Log level: INFO
[INFO] Performance logs will be written to bridge_perf.log
```

### 3.5 验证服务

```bash
curl http://127.0.0.1:8080/v1/health
```

响应：

```json
{"status":"ok","app":"HttpBridge"}
```

---

## ⚙️ 4. 配置（环境变量）

所有配置通过环境变量设置，无需修改代码。

| 变量名                    | 默认值           | 说明                                                                 |
| ------------------------- | ---------------- | -------------------------------------------------------------------- |
| `LOG_LEVEL`               | `INFO`           | 日志级别：`DEBUG` / `INFO` / `WARNING` / `ERROR`                     |
| `HTTP_PORT`               | `8080`           | HTTP 服务端口                                                        |
| `WEBHOOK_TIMEOUT`         | `10`             | Webhook 转发超时（秒）                                               |
| `BRIDGE_LISTEN`           | `0.0.0.0:9898`   | zAPI 服务监听地址（TCP）                                             |
| `BRIDGE_PUBLIC`           | `127.0.0.1:9898` | zAPI 对外公布的地址                                                  |
| `PERF_LOG_ENABLED`        | `0`              | 性能日志开关（设为 `1` 开启）                                        |
| `USE_INDEPENDENT_REQUEST` | `0`              | 调试用：设为 `1` 强制使用独立 `requests.post`（绕过 Session 连接池） |

**使用示例**：

```powershell
$env:LOG_LEVEL = "DEBUG"
$env:HTTP_PORT = 8081
$env:WEBHOOK_TIMEOUT = 20
python zapi_bridge.py
```

---

## 📡 5. API 端点详解

所有端点前缀：`/v1/`

### 5.1 `POST /v1/invoke` — 同步调用

**功能**：调用 zAPI 生态中的任意服务（同步请求-响应）。

**请求体**：

```json
{
  "app": "CalcService",     // 目标应用名（必须）
  "api": "add",             // API 名称（必须）
  "args": [10, 20],         // 参数列表
  "timeout": 5000           // 超时毫秒数（可选，默认 5000）
}
```

**成功响应**（HTTP 200）：

```json
{
  "code": 0,
  "result": 30
}
```

**失败响应**（HTTP 200，业务错误）：

```json
{
  "code": -1,
  "error": "No response from 'CalcService.add'"
}
```

**curl 示例**：

```bash
curl -X POST http://127.0.0.1:8080/v1/invoke \
  -H "Content-Type: application/json" \
  -d '{"app":"CalcService","api":"add","args":[10,20]}'
```

### 5.2 `POST /v1/notify` — 单向通知

**功能**：发送 zAPI 单向通知（fire-and-forget，不等待响应）。

**请求体**：

```json
{
  "app": "LogService",
  "api": "log",
  "args": ["INFO", "Hello"]
}
```

**响应**：

```json
{
  "code": 0,
  "status": "notified"
}
```

**curl 示例**：

```bash
curl -X POST http://127.0.0.1:8080/v1/notify \
  -H "Content-Type: application/json" \
  -d '{"app":"LogService","api":"log","args":["INFO","test"]}'
```

### 5.3 `POST /v1/hooks/register` — 注册 Webhook

**功能**：将外部 HTTP 服务注册为 zAPI 的回调端点。注册后，Bridge 会将发往该 `(app, api)` 的请求转发到 `callback_url`。

**请求体**：

```json
{
  "app": "HttpBridge",                  // 固定为 HttpBridge（用于路由）
  "api": "py_echo",                     // API 名称（唯一标识）
  "callback_url": "http://127.0.0.1:9001/webhook", // 外部 Webhook 地址
  "mode": "call"                        // "call"（同步）或 "notify"（异步）
}
```

**响应**：

```json
{
  "code": 0,
  "status": "registered"
}
```

> ⚠️ **重要**：`callback_url` 必须使用 `127.0.0.1` 而非 `localhost`，以避免 Windows 下 IPv6 解析导致的 2 秒延迟。

**curl 示例**：

```bash
curl -X POST http://127.0.0.1:8080/v1/hooks/register \
  -H "Content-Type: application/json" \
  -d '{"app":"HttpBridge","api":"py_echo","callback_url":"http://127.0.0.1:9001/webhook","mode":"call"}'
```

### 5.4 `POST /v1/hooks/unregister` — 注销 Webhook

**功能**：移除已注册的 Webhook。

**请求体**：

```json
{
  "app": "HttpBridge",
  "api": "py_echo"
}
```

**响应**：

```json
{
  "code": 0,
  "status": "unregistered"
}
```

**curl 示例**：

```bash
curl -X POST http://127.0.0.1:8080/v1/hooks/unregister \
  -H "Content-Type: application/json" \
  -d '{"app":"HttpBridge","api":"py_echo"}'
```

### 5.5 `GET /v1/hooks/list` — 查询所有 Webhook

**功能**：列出当前所有已注册的 Webhook。

**响应**：

```json
{
  "code": 0,
  "hooks": [
    {
      "app": "HttpBridge",
      "api": "py_echo",
      "url": "http://127.0.0.1:9001/webhook",
      "mode": "call"
    }
  ]
}
```

**curl 示例**：

```bash
curl http://127.0.0.1:8080/v1/hooks/list
```

### 5.6 `GET /v1/health` — 健康检查

**功能**：检查 Bridge 是否正常运行。

**响应**：

```json
{
  "status": "ok",
  "app": "HttpBridge"
}
```

**curl 示例**：

```bash
curl http://127.0.0.1:8080/v1/health
```

---

## 🔄 6. 客户端库与使用示例

Bridge 提供了多语言客户端库，方便快速集成。

### 6.1 PHP 客户端

**文件**：`PHP/ZAPIBridgeClient.php`

**使用示例**：

```php
<?php
require_once 'ZAPIBridgeClient.php';

$client = new ZAPIBridgeClient('http://127.0.0.1:8080/v1');

// 同步调用
$result = $client->invoke('CalcService', 'add', [10, 20]);

// 发送通知
$client->notify('LogService', 'log', ['INFO', 'Hello']);

// 注册 Webhook
$client->registerHook('HttpBridge', 'my_api', 'http://127.0.0.1:9000/', 'call');

// 注销 Webhook
$client->unregisterHook('HttpBridge', 'my_api');

// 查询所有 Webhook
$hooks = $client->listHooks();

// 健康检查
if ($client->health()) {
    echo "Bridge is healthy";
}
```

### 6.2 Node.js 客户端（v2.0）

**文件**：`node.js/ZAPIBridgeClient.js`

**使用示例**：

```javascript
const { ZAPIBridgeClient } = require('./ZAPIBridgeClient');

const client = new ZAPIBridgeClient('http://127.0.0.1:8080/v1');

// 同步调用
const sum = await client.invoke('CalcService', 'add', [10, 20]);

// 发送通知
await client.notify('LogService', 'log', ['INFO', 'Hello']);

// 注册 Webhook
await client.registerHook('HttpBridge', 'my_api', 'http://127.0.0.1:9002/webhook', 'call');

// 注销 Webhook
await client.unregisterHook('HttpBridge', 'my_api');

// 查询所有 Webhook
const hooks = await client.listHooks();

// 健康检查
const healthy = await client.health();
```

### 6.3 Python 客户端（使用标准库）

**脚本**：`cross_call_python.py` 或直接使用 `urllib`

**使用示例**：

```python
import urllib.request, json

def invoke(app, api, args, timeout=5000):
    url = 'http://127.0.0.1:8080/v1/invoke'
    data = json.dumps({'app': app, 'api': api, 'args': args, 'timeout': timeout}).encode()
    req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode())

result = invoke('CalcService', 'add', [10, 20])
print(result)  # {'code': 0, 'result': 30}
```

### 6.4 Pascal 客户端（通过 zAPI）

**文件**：`pascal/pascal_cross_test.lpr`

Pascal 可以直接通过 zAPI 与 Bridge 通信（无需 HTTP），性能更高。

```pascal
// 连接到 Bridge
PrepareClient('127.0.0.1:9898', App);
// 调用 PHP 的 Webhook（通过 Bridge）
CallBridgeAPI('php_echo', ['Hello from Pascal!']);
```

---

## 🧪 7. 测试指南

### 7.1 使用 curl 测试基本功能

#### 健康检查

```bash
curl http://127.0.0.1:8080/v1/health
```

#### 调用 zAPI 服务（需先有服务运行）

```bash
curl -X POST http://127.0.0.1:8080/v1/invoke \
  -H "Content-Type: application/json" \
  -d '{"app":"CalcService","api":"add","args":[10,20]}'
```

#### 注册 Webhook

```bash
curl -X POST http://127.0.0.1:8080/v1/hooks/register \
  -H "Content-Type: application/json" \
  -d '{"app":"HttpBridge","api":"test","callback_url":"http://127.0.0.1:9000/","mode":"call"}'
```

#### 调用 Webhook

```bash
curl -X POST http://127.0.0.1:8080/v1/invoke \
  -H "Content-Type: application/json" \
  -d '{"app":"HttpBridge","api":"test","args":["hello"]}'
```

#### 查询 Webhook 列表

```bash
curl http://127.0.0.1:8080/v1/hooks/list
```

#### 注销 Webhook

```bash
curl -X POST http://127.0.0.1:8080/v1/hooks/unregister \
  -H "Content-Type: application/json" \
  -d '{"app":"HttpBridge","api":"test"}'
```

### 7.2 运行完整交叉测试套件

**一键启动所有服务并测试**（Windows PowerShell）：

```powershell
.\run_cross_test.ps1
```

这会：

1. 启动 Bridge（新窗口）
2. 启动 Python Webhook（端口 9001）
3. 启动 PHP Webhook（端口 9000）
4. 启动 Node.js Webhook（端口 9002）
5. 注册各语言 Webhook
6. 执行 Python → PHP、PHP → Python、Node.js → Python/PHP 交叉调用
7. 输出测试结果

**Linux/macOS**：需将 `.ps1` 转换为 Shell 脚本，或手动按顺序执行各步骤。

### 7.3 性能测试与日志分析

Bridge 内置性能日志，写入 `bridge_perf.log`。运行测试后，使用分析工具：

```bash
python analyze_perf.py bridge_perf.log
```

输出示例：

```
Label                                               Count   Avg (ms)   P50 (ms)   P95 (ms)
----------------------------------------------------------------------------------------
webhook_http.http://127.0.0.1:9000/                    10       6.52       6.21       8.76
webhook_http.http://127.0.0.1:9001/webhook             10       7.10       6.40      10.23
route_invoke.total                                     20      14.23      12.50      25.67
```

### 7.4 手动压测（使用 `wrk` 或 `ab`）

**示例**（使用 `wrk`）：

```bash
wrk -t4 -c100 -d10s --script=post.lua http://127.0.0.1:8080/v1/invoke
```

其中 `post.lua` 内容：

```lua
wrk.method = "POST"
wrk.body = '{"app":"CalcService","api":"add","args":[10,20]}'
wrk.headers["Content-Type"] = "application/json"
```

---

## 🛠️ 8. 开发与修改指南

### 8.1 添加新的内置 API

如果你想在 Bridge 中直接注册新的 zAPI（不通过外部 Webhook），可以修改 `zapi_bridge.py`：

1. **定义回调函数**（参照 `add_callback` 或 `log_notify`）：

```python
def mul_callback(trigger, inp, out):
    """乘法：接收 JSON 数组 [a, b]，返回 a*b"""
    inp_h = inp.raw
    out_h = out.raw
    size = _native.API_GetSize(inp_h)
    if size == 0:
        return
    buf = ctypes.create_string_buffer(size)
    _native.API_SetPos(inp_h, 0)
    _native.API_ReadBuffer(inp_h, buf, size)
    raw = buf.raw[:size].rstrip(b'\x00')
    try:
        args = json.loads(raw.decode('utf-8'))
        if len(args) >= 2:
            result = args[0] * args[1]
            resp = json.dumps(result).encode('utf-8') + b'\x00'
            _native.API_WriteBuffer(out_h, ctypes.c_char_p(resp), len(resp))
    except Exception as e:
        logger.error(f"mul_callback error: {e}")
```

2. **在 `init_gateway()` 中注册**：

```python
APP.register_call("mul", mul_callback, "a*b")
```

3. **重启 Bridge**，新 API 立即生效（无需重新编译）。

### 8.2 修改配置（环境变量）

无需修改代码，通过环境变量调整：

```powershell
$env:HTTP_PORT = 8081
$env:WEBHOOK_TIMEOUT = 30
python zapi_bridge.py
```

### 8.3 增加线程池大小

修改 `zapi_bridge.py` 中的：

```python
WEBHOOK_EXECUTOR = ThreadPoolExecutor(max_workers=20)
```

将其调整为更大的值（如 `50` 或 `100`），以应对更高并发。

### 8.4 调整日志级别

在 `zapi_bridge.py` 中，`LOG_LEVEL` 环境变量控制。也可以在代码中直接修改默认值。

### 8.5 添加新的 Webhook 注册模式

当前支持 `call` 和 `notify` 两种模式。如果要支持更多模式（如流式），需扩展 `build_webhook_callback` 和 `_forward_webhook_sync`。

### 8.6 添加新的路由端点

在 Flask 应用中添加新的路由函数：

```python
@flask_app.route("/v1/custom", methods=["GET"])
def custom_route():
    return jsonify({"message": "custom"})
```

### 8.7 调试开发

开启 DEBUG 日志：

```powershell
$env:LOG_LEVEL = "DEBUG"
python zapi_bridge.py
```

查看 `bridge_perf.log` 和终端输出，可追踪每个请求的详细流程。

---

## 🔍 9. 命令行测试与开发工具

### 9.1 curl 快速测试

最常用的命令行测试工具，前文已有大量示例。

### 9.2 查看端口监听状态

**Windows**：

```powershell
netstat -ano | findstr :8080
netstat -ano | findstr :9898
```

**Linux**：

```bash
ss -tlnp | grep 8080
ss -tlnp | grep 9898
```

### 9.3 实时查看性能日志

```powershell
Get-Content bridge_perf.log -Wait
```

### 9.4 使用 `analyze_perf.py` 分析日志

```bash
python analyze_perf.py bridge_perf.log
```

### 9.5 发送测试请求（使用 `httpie`）

```bash
http POST :8080/v1/invoke app=CalcService api=add args:='[10,20]'
```

### 9.6 使用 Postman 或 Insomnia

导入以下集合可方便测试：

**Collection 示例**（导入到 Postman）：

```json
{
  "info": { "name": "ZAPI Bridge" },
  "item": [
    {
      "name": "Health",
      "request": { "method": "GET", "url": "http://127.0.0.1:8080/v1/health" }
    },
    {
      "name": "Invoke",
      "request": {
        "method": "POST",
        "url": "http://127.0.0.1:8080/v1/invoke",
        "body": { "mode": "raw", "raw": "{\"app\":\"CalcService\",\"api\":\"add\",\"args\":[10,20]}" }
      }
    }
  ]
}
```

---

## 🐛 10. 故障排除

### 10.1 常见问题

| 现象                                   | 可能原因                            | 解决方案                                                         |
| -------------------------------------- | ----------------------------------- | ---------------------------------------------------------------- |
| `ImportError: No module named api_hub` | Python 找不到 `api_hub` 包          | 确保在 `bridge/` 目录运行，或设置 `PYTHONPATH` 指向 `Py/`        |
| `OSError: Cannot load library`         | 动态库未找到                        | 设置 `PATH` 包含 `Binary/` 目录，或复制 DLL 到 `bridge/`         |
| Bridge 启动后立即退出                  | 端口被占用                          | 更换 `HTTP_PORT` 或检查是否已有 Bridge 运行                      |
| Webhook 调用耗时 **~2 秒**             | URL 使用 `localhost` 导致 IPv6 回退 | 将 Webhook URL 中的 `localhost` 改为 `127.0.0.1`                 |
| `webhook_http` 超时                    | 外部 Webhook 服务未启动             | 检查目标端口（9000/9001/9002）是否在 `LISTENING` 状态            |
| 调用返回 `No webhook for ...`          | API 未注册                          | 先调用 `/v1/hooks/register` 注册 Webhook                         |
| `ConnectTimeout` / `ConnectionError`   | 目标服务拒绝连接                    | 检查防火墙，确认目标服务运行中                                   |
| 性能日志未生成                         | `PERF_LOG_ENABLED` 未设为 `1`       | 设置 `$env:PERF_LOG_ENABLED=1` 后重启 Bridge                     |
| 中文乱码                               | 控制台编码问题                      | Windows 中执行 `chcp 65001` 后再运行 Python                      |

### 10.2 开启调试日志

```powershell
$env:LOG_LEVEL = "DEBUG"
python zapi_bridge.py
```

### 10.3 检查 zAPI 内部日志

zAPI 动态库会自动将连接状态和错误信息输出到控制台。若 `API_Prepare_Done` 返回 0，控制台会打印详细错误。

---

## 📈 11. 性能调优

### 11.1 安装性能增强依赖

```bash
pip install orjson waitress
```

- `orjson`：序列化/反序列化速度提升 3-5 倍
- `waitress`：生产级 WSGI 服务器，支持更多并发连接

### 11.2 调整线程池大小

根据 CPU 核心数和并发量调整 `max_workers`。

### 11.3 使用 `127.0.0.1` 替代 `localhost`

避免 Windows 下 IPv6 解析延迟，所有注册 URL 和连接地址统一使用 `127.0.0.1`。

### 11.4 增大 `requests.Session` 连接池

在 `zapi_bridge.py` 中：

```python
adapter = HTTPAdapter(pool_connections=100, pool_maxsize=200, max_retries=0)
```

### 11.5 开启性能日志（调试时）

```powershell
$env:PERF_LOG_ENABLED = 1
python zapi_bridge.py
```

### 11.6 启用 `USE_INDEPENDENT_REQUEST` 调试（排查 Session 问题）

```powershell
$env:USE_INDEPENDENT_REQUEST = 1
python zapi_bridge.py
```

如果启用后性能显著提升，说明 `Session` 连接池存在问题，可考虑增大连接池或改用独立请求。

---

## 📂 12. 文件清单与说明

| 文件                       | 说明                              |
| -------------------------- | --------------------------------- |
| `zapi_bridge.py`           | Bridge 主程序（本手册描述）       |
| `requirements.txt`         | Python 依赖清单                   |
| `python_webhook.py`        | Python Webhook 接收服务器（示例） |
| `cross_call_python.py`     | Python 交叉调用脚本               |
| `analyze_perf.py`          | 性能日志分析工具                  |
| `run_cross_test.ps1`       | 一键启动所有服务并执行交叉测试    |
| `bridge_perf.log`          | 性能日志（运行时生成）            |
| `ZAPI 桥接开发踩坑记录.md` | 完整踩坑与解决方案文档            |
| `PHP/`                     | PHP 客户端库和示例                |
| `node.js/`                 | Node.js 客户端库和示例（v2.0）    |
| `pascal/`                  | Pascal 示例（直接 zAPI 调用）     |
| `../api_hub/`              | zAPI Python 核心绑定（必需）      |
| `../../Binary/`            | zAPI 动态库（必需）               |

---

## 🤝 13. 联系与支持

- **作者 QQ**：`600585`

欢迎技术交流、问题反馈、功能建议和贡献代码。

---

## 📄 14. 许可证

**MIT License** —— 自由使用、修改、分发，包括商业用途。

---

> **"ZAPI Bridge —— 让任何语言都能轻松调用任何语言。"**  
> 现在，你已经拥有了完整的工具链，开始构建你的多语言分布式系统吧！🚀

---

## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](../../C++/API%20Hub%20Tool%20C++%20使用指南.md)
- [API Hub Tool C 语言使用指南](../../C++/API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](../从零到一，掌握多语言互调.md)
- [API Hub for Go 从零到一掌握多语言互调](../../Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)
- [zAPI Rust 使用指南](../../rust/zAPI%20Rust%20使用指南.md)
- [API Hub Java 使用指南](../../java/API%20Hub%20Java%20使用指南.md)
- [API Hub Tool for C# — 完整使用指南](../../C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [API Hub Tool for Pascal](../../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../../node/Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../../VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](../web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](../web/js_api.py%20使用指南.md)
- [ZAPI Bridge Python 依赖清单](./ZAPI%20Bridge%20Python%20依赖清单.md)
- [ZAPI 桥接开发踩坑记录](./ZAPI%20桥接开发踩坑记录.md)
