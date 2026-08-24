# 🌐 js_api.py 使用指南

**“让浏览器也能跨语言执法，前端从此不再卑微。”**

**版本**：2.0（与 ZAPI Bridge v2.0 同步）

---

## 📖 目录

- [这个文件是干嘛的](#-这个文件是干嘛的)
- [它怎么工作的](#-它怎么工作的)
- [环境准备](#-环境准备)
- [启动网关](#-启动网关)
- [网页功能介绍](#-网页功能介绍)
- [如何添加新 API](#-如何添加新-api)
- [纯前端调用示例](#-纯前端调用示例)
- [常见问题](#-常见问题)
- [写在最后](#-写在最后)


## 🤔 这个文件是干嘛的

`js_api.py` 是一个 **自带可视化页面的 Python HTTP 网关**，它的使命只有一条：

**让浏览器 JavaScript 能够调用任何语言写的服务（C++、Python、Go、Rust、Java、C#、Pascal、PHP、Node.js……），就像调用本地 API 一样简单。**

它干的事就是：

```
浏览器 JS → fetch → js_api.py (HTTP 服务) → zAPI 核心 → 目标语言服务
                   ↓
            返回 JSON → 页面直接展示
```

**说白了，它是个“前端外交官”：浏览器不会说 C++ 的话，但它会；浏览器不会跟 Python 模型聊天，但它会。所有语言它都懂——它就是 zAPI 生态里的“联合国翻译官”。**

> **注意**：`js_api.py` 与 `zapi_bridge.py` 共享相同的底层架构，是 ZAPI Bridge v2.0 生态的一部分。如果你需要 PHP 或 Node.js 支持，请参考 [📖 ZAPI Bridge 完整使用手册](../bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)。


## 🔧 它怎么工作的

`js_api.py` 启动后做了三件事：

1. **启动了一个 HTTP 服务器**，监听 `8080` 端口（可配）。
2. **注册了内置 API**：`add`（同步加法）和 `log`（日志通知），开箱即用。
3. **内置了一个漂亮的 HTML 页面**，访问根路径 `/` 就能看到，页面里的 JS 已经封装好了 `/call` 和 `/notify` 的调用逻辑。

**你只需要启动它，打开浏览器，剩下的就是点点点。**


## 🚀 环境准备

### 第一步：动态库（别怕，不用你编译）

确保 `Binary/` 目录下有这些文件：

| 文件 | 说明 | 去哪找 |
|------|------|--------|
| `z_api_hub64.dll` | zAPI 核心库（Windows） | Release 包 |
| `z_ipc_64.dll` | IPC 支持库（Windows） | Release 包 |
| `libz_api_hub.so` | zAPI 核心库（Linux） | Release 包 |
| `libz_ipc.so` | IPC 支持库（Linux） | Release 包 |

**下载解压，放到 `Binary/`，完事。**

### 第二步：目录结构

确保你的目录长这样：

```
DLL-Build/
├── Binary/
│   ├── z_api_hub64.dll
│   └── z_ipc_64.dll
└── Py/
    ├── api_hub/           ← zAPI Python 绑定
    └── web/
        └── js_api.py      ← 就是这个文件
```


## ▶️ 启动网关

### Windows（PowerShell）

```powershell
cd D:\CoreLibrary\API_Hub_Tool\DLL-Build\Py\web
$env:PATH = "..\..\Binary;" + $env:PATH
python js_api.py --port 8080 --endpoint ipc:gateway
```

### Linux/macOS

```bash
cd /path/to/Py/web
export PATH="../../Binary:$PATH"
python3 js_api.py --port 8080 --endpoint ipc:gateway
```

### 启动参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--port` | 8080 | HTTP 服务端口，浏览器访问时用这个 |
| `--endpoint` | `ipc:gateway` | zAPI 端点地址，同机用 IPC，跨机用 TCP |

**推荐用 IPC（`ipc:xxx`），速度飞起，延迟 < 1ms，你点一下按钮，结果还没反应过来就出来了。**

### 启动成功标志

```
[JS-API] App created with 'add' (call) and 'log' (notify)
[JS-API] Gateway ready on ipc:gateway
[JS-API] HTTP 服务启动: http://localhost:8080
[JS-API] 在浏览器中打开上述地址即可体验
```

**看到这个，网关就在运行了。别关终端，关了服务就没了。**


## 🖥️ 网页功能介绍

打开 `http://localhost:8080/`，你会看到一个精美的交互页面，包含：

### 📖 zAPI 介绍卡片
- 简洁说明了 zAPI 是什么、支持哪些语言、有哪些特性。
- 让你知道你这波操作有多强。

### 📞 同步调用 (Call)
- 输入两个数字，点“计算”，立即显示 `a + b = 结果`。
- 这是典型的请求-响应模式，**你点一下，它算一下，你再点，它再算，比计算器还听话**。

### 📨 单向通知 (Notify)
- 输入一条消息，点“发送日志”，页面日志区记录发送记录，同时网关终端会打印 `[LOG] ['INFO', '你的消息']`。
- 这是 fire-and-forget 模式，**消息发出去了，看不看随缘，主打一个“发了就跑”**。

**这页面不光好看，还实用。你完全可以用它来演示、测试、甚至当作 zAPI 的“体验中心”。**


## 🔧 如何添加新 API（比改 PPT 还简单）

在 `js_api.py` 里加一个乘法：

### 第一步：写回调函数

```python
def mul_callback(trigger, inp, out):
    """
    乘法回调：接收 JSON 数组 [a, b]，返回 JSON 数字 a*b
    """
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
            result = a * b
            log(f"mul({a}, {b}) = {result}")
            resp = json.dumps(result).encode('utf-8') + b'\x00'
            _native.API_WriteBuffer(out_h, ctypes.c_char_p(resp), len(resp))
    except Exception as e:
        log_err(f"mul_callback exception: {e}")
```

### 第二步：注册到网关

在 `init_gateway()` 里加一行：

```python
def init_gateway(endpoint):
    global APP
    APP = App("NodeGateway", "Browser API Gateway")
    APP.register_call("add", add_callback, "a+b")
    APP.register_notify("log", log_notify, "Log notify")
    APP.register_call("mul", mul_callback, "a*b")   # ← 就这一行
    # ... 其他不用动
```

### 第三步：浏览器调用

在浏览器控制台执行：

```javascript
fetch('/call', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
        app: 'NodeGateway',
        api: 'mul',
        args: [6, 7]
    })
}).then(r => r.json()).then(console.log);
// 输出: { result: 42 }
```

**加一个 API 比你在工位上划水还简单，而且改完刷新页面立即生效，不用重启服务器。**


## 💻 纯前端调用示例（不依赖页面）

如果你不想用内置页面，只想在任意 HTML 里调用：

```html
<!DOCTYPE html>
<html>
<body>
    <button onclick="doCall()">计算 10+20</button>
    <div id="result"></div>

    <script>
    async function doCall() {
        const resp = await fetch('http://localhost:8080/call', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                app: 'NodeGateway',
                api: 'add',
                args: [10, 20],
                timeout: 5000
            })
        });
        const data = await resp.json();
        document.getElementById('result').textContent = '结果: ' + data.result;
    }
    </script>
</body>
</html>
```

**这就是全部代码。你没看错，没有 WebSocket，没有 CORS 配置，没有代理——浏览器直接调用 C++ 服务，就这几行。**


## ❓ 常见问题

**Q1: 为什么页面和网关在同一端口？这样不会有问题吗？**

A: 不会。`js_api.py` 同时提供静态页面和 API 接口，路径分开：`/` 返回 HTML，`/call` 和 `/notify` 处理请求。**一个端口搞定一切，省心省力。**

**Q2: 页面能部署到其他服务器吗？**

A: 可以。你可以把 HTML 提取出来放到任何静态服务器，只要把 `fetch` 的 URL 改成网关的实际地址就行（比如 `http://your-server:8080/call`）。

**Q3: 网关能跨域访问吗？**

A: 如果需要从不同域访问，在 `Handler` 里加 `Access-Control-Allow-Origin` 头即可。默认同源（页面和网关同端口），所以不存在跨域问题。

**Q4: 我能在手机上打开这个页面吗？**

A: 能。页面是响应式的，手机、平板、电脑都能自适应。网关监听 `0.0.0.0`，同一局域网内用手机浏览器输入 `http://你的电脑IP:8080` 就能访问。

**Q5: 支持 HTTPS 吗？**

A: 目前是 HTTP，生产环境建议用 Nginx 反代加 SSL。不过本地测试用 HTTP 足够了。

**Q6: 页面里的 zAPI 介绍是编的吗？**

A: 全是真实技术介绍，没吹牛。zAPI 确实支持 10+ 语言，确实有 C4 服务网格，确实自动服务发现。**这波不亏。**

**Q7: 和 ZAPI Bridge 是什么关系？**

A: `js_api.py` 是 ZAPI Bridge v2.0 生态的一部分，专门为浏览器 JavaScript 优化，自带可视化页面。如果你需要 PHP 或 Node.js 支持，使用完整的 Bridge。


## 📝 写在最后

`js_api.py` 是个 **不到 200 行核心逻辑** 的文件，但它干的事是：

**让浏览器 JavaScript 拥有了调用整个 zAPI 生态的能力。**

你的网页现在可以：

- 调用 C++ 的高性能计算模块
- 调用 Python 的 AI 推理服务
- 调用 Go 的微服务
- 调用 Rust 的系统级库
- 调用 20 年前的 Pascal 遗留系统

**以前网页是“前端”，现在网页是“总指挥”——点一下按钮，全世界都为你运转。**

**这不是画饼，这是你今晚就能跑通的代码。** 🚀


## 🤝 社区与支持

- **开源首页**：[https://github.com/PassByYou888/zAPI](https://github.com/PassByYou888/zAPI)
- **仓库地址**：[https://github.com/PassByYou888/zAPI.git](https://github.com/PassByYou888/zAPI.git)
- **作者 QQ**：`600585`

**Star、Fork、Issue、PR——欢迎一切形式的参与！**


## 📄 许可证

**MIT License** —— 放心用，商业、开源、个人项目通吃。


> **“让每一种语言，都能被浏览器轻松调用。”**  
> —— 这不是口号，是 zAPI 每天都在做的事。

**现在，去给你的网页开个“跨语言外挂”吧。** 🌐

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
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [📖 ZAPI Bridge 完整使用手册](../bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)
- [ZAPI Bridge Python 依赖清单](../bridge/ZAPI%20Bridge%20Python%20依赖清单.md)
- [ZAPI 桥接开发踩坑记录](../bridge/ZAPI%20桥接开发踩坑记录.md)
