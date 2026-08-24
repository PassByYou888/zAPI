# 🐍 gateway.py 使用指南

**“别再写一坨 node-gyp 配置了，Node.js 调 C++ 的正确姿势在这里。”**


## 📖 目录

- [这个文件是干嘛的](#-这个文件是干嘛的)
- [它怎么工作的](#-它怎么工作的)
- [环境准备](#-环境准备)
- [启动网关](#-启动网关)
- [API 使用说明](#-api-使用说明)
- [如何添加新 API](#-如何添加新-api)
- [完整示例](#-完整示例)
- [常见问题](#-常见问题)
- [写在最后](#-写在最后)


## 🤔 这个文件是干嘛的

`gateway.py` 是一个 **Python HTTP 网关**，它的工作简单粗暴：

**接收 Node.js（或任何能发 HTTP 请求的语言）发来的请求，转手调用 zAPI 的 C 动态库，然后把结果打包成 JSON 还回去。**

说白了，它就是 Node.js 和 zAPI 之间的 **“翻译官”**：

```
Node.js → HTTP请求 → gateway.py → zAPI(C动态库) → 目标服务
                 ↓
            返回 JSON
```

**没有这个文件，你的 Node.js 就得去写 C++ 插件编译脚本，然后被各种链接错误整到怀疑人生。**


## 🔧 它怎么工作的

`gateway.py` 启动后做了三件事：

1. **创建了一个名为 `NodeGateway` 的 zAPI 应用**——相当于在 zAPI 网络里注册了一个“门派”，你这个应用就代表 Node.js 这一方。
2. **注册了内置 API**——目前自带两个：`add`（加法）和 `log`（日志通知），开箱即用，童叟无欺。
3. **启动了 HTTP 服务**——监听 `8080` 端口（端口可配），等着接收你的 HTTP 请求。

**核心逻辑链：**

```
HTTP /call → 解析 JSON → 创建 DataHnd → 写入参数 → API_Call → 读取结果 → 返回 JSON
HTTP /notify → 解析 JSON → 创建 DataHnd → 写入参数 → API_Notify → 返回 {"status":"ok"}
```

## 🚀 环境准备

### 第一步：动态库（别慌，不是让你编译）

确保以下文件在 `Binary/` 目录下：

| 文件 | 说明 | 去哪找 |
|------|------|--------|
| `z_api_hub64.dll` | zAPI 核心库（Windows） | Release 包里有 |
| `z_ipc_64.dll` | IPC 通信支持库 | Release 包里有 |
| `libz_api_hub.so` | zAPI 核心库（Linux） | Release 包里有 |
| `libz_ipc.so` | IPC 通信支持库（Linux） | Release 包里有 |

**简单说：去 Releases 页面下载，解压，放到 `Binary/` 目录下，完事。**

### 第二步：Python 依赖

确保安装了 Python 3.8+，并且同级目录下有 `api_hub` 包（就是 zAPI 的 Python 绑定，项目自带，不用额外 pip install）。

### 第三步：目录结构

确认你的目录长这样：

```
DLL-Build/
├── Binary/
│   ├── z_api_hub64.dll     ← 核心库
│   └── z_ipc_64.dll        ← IPC 库
└── Py/
    ├── api_hub/            ← zAPI Python 绑定
    └── node/
        └── gateway.py      ← 就是这个文件
```


## ▶️ 启动网关

### Windows（PowerShell）

```powershell
cd D:\CoreLibrary\API_Hub_Tool\DLL-Build\Py\node
$env:PATH = "..\..\Binary;" + $env:PATH
python gateway.py --port 8080 --endpoint ipc:gateway
```

### Linux/macOS

```bash
cd /path/to/Py/node
export PATH="../../Binary:$PATH"
python3 gateway.py --port 8080 --endpoint ipc:gateway
```

### 启动参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--port` | 8080 | HTTP 服务端口 |
| `--endpoint` | `ipc:gateway` | zAPI 端点地址 |

**关于 `--endpoint` 参数：**
- `ipc:xxx`：使用 IPC（进程间通信），适合同机调用，**速度飞快，延迟 < 1ms**
- `127.0.0.1:9898`：使用 TCP，适合跨机调用
- 推荐先玩 IPC，**快到你感觉不到延迟**。

### 启动成功标志

看到这个输出就代表成功了：

```
[Gateway] App created with 'add' and 'log'
[C4] API-Hub Service Listening: "ipc:gateway:0" OK
[C4] APP NodeGateway "Simple Gateway" Ready OK
[Gateway] Gateway ready on ipc:gateway
[Gateway] HTTP server starting on 0.0.0.0:8080
```

**此时网关正在运行，保持终端不要关闭！** 关了就没服务了。

### 可以 Ctrl+C 优雅停止

按 `Ctrl+C` 会触发 shutdown，安全释放资源。


## 📡 API 使用说明

网关提供了两个 HTTP 端点：

### 1. POST /call —— 同步调用

**用途**：请求-响应模式，发送参数，等待结果。

**请求体格式**：

```json
{
  "app": "NodeGateway",    // 应用名（固定，除非你改代码）
  "api": "add",            // API 名称
  "args": [10, 20],        // 参数列表（JSON 数组）
  "timeout": 5000          // 超时时间（毫秒，可选，默认 5000）
}
```

**响应格式（成功）**：

```json
{ "result": 30 }
```

**响应格式（超时或失败）**：

```json
{ "result": null, "error": "timeout or empty" }
```

### 2. POST /notify —— 单向通知

**用途**：fire-and-forget 模式，发送消息，不等待响应，主打一个“发了就跑”。

**请求体格式**：

```json
{
  "app": "NodeGateway",
  "api": "log",
  "args": ["INFO", "Hello from Node.js!"]
}
```

**响应格式**：

```json
{ "status": "ok" }
```

**注意**：通知是单向的，不会返回处理结果，也不保证送达——就像你给对象发“早安”，对方看不看是对方的事。

### 内置 API 列表

| API | 模式 | 说明 | 参数示例 |
|-----|------|------|----------|
| `add` | Call | 加法运算 | `[10, 20]` → `30` |
| `log` | Notify | 日志打印 | `["INFO", "hello"]` → 网关终端打印日志 |


## 🔧 如何添加新 API

### 第一步：写回调函数

```python
def mul_callback(trigger, inp, out):
    """
    乘法回调：接收 JSON 数组 [a, b]，返回 JSON 数字 a*b
    """
    # 获取底层句柄
    inp_h = inp.raw
    out_h = out.raw

    # 读输入
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
            result = a * b
            log(f"mul({a}, {b}) = {result}")
            resp = json.dumps(result).encode('utf-8') + b'\x00'
            _native.API_WriteBuffer(out_h, ctypes.c_char_p(resp), len(resp))
    except Exception as e:
        log_err(f"mul_callback exception: {e}")
```

### 第二步：注册到应用

在 `init_gateway()` 函数中添加一行：

```python
def init_gateway(endpoint):
    global APP
    APP = App("NodeGateway", "Simple Gateway")
    APP.register_call("add", add_callback, "a+b")
    APP.register_notify("log", log_notify, "Log notify")
    APP.register_call("mul", mul_callback, "a*b")    # ← 加这一行就行
    # ... 后面的不用动
```

### 第三步：Node.js 调用

```javascript
const result = await call('NodeGateway', 'mul', [6, 7]);
console.log('6 × 7 =', result);  // 42
```

**加一个 API 的代码量比你中午点外卖还少。**


## 💻 完整示例

### Node.js 调用示例（client.js）

```javascript
const http = require('http');

const GATEWAY = 'http://localhost:8080';

async function call(app, api, args, timeout = 5000) {
    const data = JSON.stringify({ app, api, args, timeout });
    return new Promise((resolve, reject) => {
        const req = http.request(`${GATEWAY}/call`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(data)
            }
        }, (res) => {
            let raw = '';
            res.on('data', chunk => raw += chunk);
            res.on('end', () => {
                try { resolve(JSON.parse(raw)); }
                catch (e) { resolve(raw); }
            });
        });
        req.on('error', reject);
        req.write(data);
        req.end();
    });
}

async function notify(app, api, args) {
    const data = JSON.stringify({ app, api, args });
    return new Promise((resolve, reject) => {
        const req = http.request(`${GATEWAY}/notify`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(data)
            }
        }, (res) => {
            let raw = '';
            res.on('data', chunk => raw += chunk);
            res.on('end', () => {
                try { resolve(JSON.parse(raw)); }
                catch (e) { resolve(raw); }
            });
        });
        req.on('error', reject);
        req.write(data);
        req.end();
    });
}

async function main() {
    // 调用加法
    const sum = await call('NodeGateway', 'add', [10, 20]);
    console.log('10 + 20 =', sum.result);

    // 发送日志通知
    await notify('NodeGateway', 'log', ['INFO', 'Hello from Node.js']);
    console.log('日志已发送');
}

main();
```

### 运行

```bash
node client.js
```

输出：

```
10 + 20 = 30
日志已发送
```

同时网关终端会输出：

```
[Gateway] CALL NodeGateway.add args=[10, 20]
[Gateway] add(10, 20) = 30
[Gateway] NOTIFY NodeGateway.log args=['INFO', 'Hello from Node.js']
[Gateway] [LOG] ['INFO', 'Hello from Node.js']
```


## ❓ 常见问题

**Q1: 启动时报 `ImportError: No module named api_hub`**

A: 说明 Python 找不到 `api_hub` 包。确保你在 `Py/node/` 目录下运行，或者检查 `sys.path.append` 是否正确指向了 `Py/` 目录。

**Q2: 报 `OSError: Cannot load library: z_api_hub64.dll`**

A: 动态库路径没设置好。检查 `$env:PATH = "..\..\Binary;" + $env:PATH` 是否执行了，或者直接把 `Binary/` 目录加到系统 `PATH` 里。

**Q3: 报 `API_Prepare_Done failed`**

A: 一般是 `--endpoint` 地址被占用了。换个名字试试，比如 `--endpoint ipc:gateway2`，或者检查是否有其他程序占用了同样的 IPC 名称。

**Q4: Node.js 调用返回 `timeout or empty`**

A: 检查目标应用是否存在。比如你调 `'NodeGateway'`，但网关没起来。或者调了个不存在的 API 名，检查拼写有没有写错，大小写有没有对。

**Q5: 网关启动后 Node 连不上**

A: 检查防火墙是否拦截了 `8080` 端口，或者看网关是否真的在运行（终端没关吧？）。

**Q6: 能不能同时跑多个网关？**

A: 可以，用不同的 `--port` 和 `--endpoint` 就行，比如：
```bash
# 网关1
python gateway.py --port 8080 --endpoint ipc:gateway1
# 网关2
python gateway.py --port 8081 --endpoint ipc:gateway2
```

**Q7: 为什么用 IPC 不用 TCP？**

A: IPC 是进程间通信，走的是操作系统内核的命名管道或共享内存，延迟比 TCP 低一个数量级。**同机通信不用 IPC 等于浪费性能**，就像点了外卖自己去店里取一样。

**Q8: 能不能跑在 Docker 里？**

A: 能。IPC 在容器里需要用 `--ipc=host` 或者宿主机共享 IPC 命名空间。或者直接换成 TCP 模式更方便。


## 📝 写在最后

`gateway.py` 是个 **70 行核心逻辑、20 行回调、总共不到 200 行代码** 的文件，但它干的事是：

**让 Node.js（以及任何能发 HTTP 请求的语言）拥有了调用整个 zAPI 生态的能力。**

你的 Node.js 应用现在可以：

- 调用 C++ 的高性能计算模块
- 调用 Python 的 AI 推理服务
- 调用 Go 的微服务
- 调用 Rust 的系统级库
- 调用 Java 的大数据组件
- 调用 20 年前的 Pascal 遗留系统

**真正的“一次接入，万物互联”。**

**这不是画饼，这是你今晚就能跑通的代码。**

---

**开源首页**：[https://github.com/PassByYou888/zAPI](https://github.com/PassByYou888/zAPI)
**仓库地址**：[https://github.com/PassByYou888/zAPI.git](https://github.com/PassByYou888/zAPI.git)
**作者 QQ**：`600585`

Star、Fork、Issue、PR——欢迎一切形式的参与！🎉

## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](../../C%2B%2B/API%20Hub%20Tool%20C%2B%2B%20%E4%BD%BF%E7%94%A8%E6%8C%87%E5%8D%97.md)
- [API Hub Tool C 语言使用指南](../../C%2B%2B/API%20Hub%20Tool%20C%20%E8%AF%AD%E8%A8%80%E4%BD%BF%E7%94%A8%E6%8C%87%E5%8D%97.md)
- [从零到一，掌握多语言互调](../%E4%BB%8E%E9%9B%B6%E5%88%B0%E4%B8%80%EF%BC%8C%E6%8E%8C%E6%8F%A1%E5%A4%9A%E8%AF%AD%E8%A8%80%E4%BA%92%E8%B0%83.md)
- [API Hub for Go 从零到一掌握多语言互调](../../Go/API%20Hub%20for%20Go%20%E4%BB%8E%E9%9B%B6%E5%88%B0%E4%B8%80%E6%8E%8C%E6%8F%A1%E5%A4%9A%E8%AF%AD%E8%A8%80%E4%BA%92%E8%B0%83.md)
- [zAPI Rust 使用指南](../../rust/zAPI%20Rust%20%E4%BD%BF%E7%94%A8%E6%8C%87%E5%8D%97.md)
- [API Hub Java 使用指南](../../java/API%20Hub%20Java%20%E4%BD%BF%E7%94%A8%E6%8C%87%E5%8D%97.md)
- [API Hub Tool for C# — 完整使用指南](../../C%23/API%20Hub%20Tool%20for%20C%23%20%E2%80%94%20%E5%AE%8C%E6%95%B4%E4%BD%BF%E7%94%A8%E6%8C%87%E5%8D%97.md)
- [API Hub Tool for Pascal](../../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../../node/Node.js%20%E8%B7%A8%E8%AF%AD%E8%A8%80%E8%B0%83%E7%94%A8%E6%96%B9%E6%A1%88%E9%80%89%E5%9E%8B%EF%BC%9A%E4%B8%BA%E4%BB%80%E4%B9%88%E6%88%91%E4%BB%AC%E9%80%89%E6%8B%A9%20Python%20%E7%BD%91%E5%85%B3%E8%80%8C%E9%9D%9E%20npm%20%E5%8E%9F%E7%94%9F%E5%8C%85.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../../VB.NET/%E8%80%81%E5%93%A5%E5%88%AB%E5%8D%B7%E4%BA%86%2C%E4%BD%A0%E7%9A%84%20VB.NET%20%E4%BB%A3%E7%A0%81%E4%BB%8A%E5%A4%A9%E5%BC%80%E5%A7%8B%E5%85%A8%E6%A0%88%E9%80%9A%E6%9D%80.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](../web/%E6%B5%8F%E8%A7%88%E5%99%A8%E8%B0%83%E7%94%A8%20C%2B%2B%20%E7%9A%84%E4%B8%89%E7%A7%8D%E6%96%B9%E6%A1%88%E5%AF%B9%E6%AF%94%EF%BC%9A%E4%B8%BA%E4%BB%80%E4%B9%88%E6%88%91%E4%BB%AC%E9%80%89%E6%8B%A9%E4%BA%86%20zAPI%20%E7%BD%91%E5%85%B3.md)
- [js_api.py 使用指南](../web/js_api.py%20%E4%BD%BF%E7%94%A8%E6%8C%87%E5%8D%97.md)
