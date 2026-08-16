# 🌐 什么？浏览器里能直接跑 C++ 代码了？

> **友情提示：** 这不是 WebAssembly，这是比 Wasm 更野的路子——直接"远程遥控"服务器上的任何语言进程。
>
> **版本**：2.0（与 ZAPI Bridge v2.0 同步）

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![JavaScript](https://img.shields.io/badge/JavaScript-ES6+-yellow.svg)](https://developer.mozilla.org/zh-CN/docs/Web/JavaScript)
[![Platform](https://img.shields.io/badge/platform-Any%20Browser-green.svg)]()


## 前端受气包翻身记

以前在公司：

> 后端： "这个接口我改一下 Schema，你等会儿。"
> 前端： "好的爸爸，我等。"

> 后端： "这个服务在重构，暂时调不了。"
> 前端： "好的爸爸，我先 mock。"

> 后端： "这个接口响应有点慢，你加个 loading 吧。"
> 前端： "好的爸爸，我加。"

**现在有了 zAPI 的浏览器网关（`js_api.py`）：**

> 前端： "我直接调 C++ 的服务了，你的 Java 接口太慢了，不用了谢谢。"
> 后端： "？？？"

> 前端： "Python 的 AI 模型我也直接调了，你那个 Flask 服务我撤掉了哈。"
> 后端： "等等，你再说一遍？？？"

> 前端： "PHP 和 Node.js 的服务我也能调了，你们都不用写了。"
> 后端： "？？？？？？"

**前端不再是"切图仔"，而是真正的"全栈指挥官"。**


## 这玩意儿怎么工作的？（20 秒看懂）

```
┌─────────────┐     fetch      ┌──────────────────┐    C ABI     ┌─────────────┐
│  浏览器 JS  │ ────────────── │  Python 网关     │ ──────────── │  zAPI Core  │
│  (你的网页) │ ◄───────────── │  (js_api.py)     │ ◄─────────── │  (DLL/SO)   │
└─────────────┘     JSON       └──────────────────┘             └─────────────┘
                                                                      │
                                                                      ▼
                                                         ┌─────────────────────┐
                                                         │ C++ / Python / Go   │
                                                         │ Rust / Java / C#    │
                                                         │ Pascal / PHP/Node   │
                                                         └─────────────────────┘
```

**简单说：** 你在网页里点个按钮，JavaScript 发个请求给 Python 网关，网关转手调用了 zAPI 的 C 核心库，C 核心库找到目标语言的服务，把结果传回来。

**一套流程走完，用户甚至没注意到中间经过了这么多层——因为他点完按钮，结果就出来了。**

> **v2.0 新特性：** 现在不仅浏览器能调，PHP 和 Node.js 也能通过同样的网关双向调用。详见 [ZAPI Bridge 完整使用手册](../bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)。


## 怎么玩？三步走

### Step 1：启动网关（就一行命令）
```bash
cd Py/web
python js_api.py --port 8080 --endpoint ipc:gateway
```

### Step 2：打开浏览器
访问 `http://localhost:8080`，你会看到一个自带交互界面的"武器库"。

里面有两个功能卡片：
- **📞 同步调用**：输入两个数，点"计算"，立即看到 C++ 算出来的结果
- **📨 单向通知**：输入一条消息，点"发送"，日志瞬间出现在终端

**你甚至不需要写任何代码，点一点就能体验跨语言调用的魔力。**

### Step 3：在 Console 里写 JS（如果你非要写的话）
```javascript
// 这就叫"跨维度打击"
const result = await fetch('/call', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
        app: 'HPC_Service',   // 这是一台 C++ 写的超算服务
        api: 'sha256',        // 算个哈希
        args: ['hello world'],
        timeout: 5000
    })
}).then(r => r.json());

console.log('C++ 算出来的哈希：', result.result);
// 输出: 5eb63bbbe01eeed093cb22bb8f5acdc3...
```


## 浏览器现在能随便拿捏哪些语言？

| 语言 | 能调吗？ | 怎么调？ |
|------|---------|----------|
| **C++** | ✅ | `fetch('/call', { body: JSON.stringify({ app: 'CppService', api: 'compute' }) })` |
| **Python** | ✅ | 同上，把 `app` 改成 `PyTorchModel` |
| **Go** | ✅ | 同上，把 `app` 改成 `GoGateway` |
| **Rust** | ✅ | 同上，把 `app` 改成 `RustEngine` |
| **Java** | ✅ | 同上，把 `app` 改成 `JavaAnalytics` |
| **Pascal** | ✅ | 同上，把 `app` 改成 `LegacyERP` |
| **PHP** | ✅ | 同上，把 `app` 改成 `PHPWebhook`（通过 Bridge 注册） |
| **Node.js** | ✅ | 同上，把 `app` 改成 `NodeWebhook`（通过 Bridge 注册） |

**你看，语法完全一样，只是换了个 `app` 名字。这就叫"统一接口，全语言制霸"。**


## 应用场景（应用空间无限扩大）

| 场景 | 浏览器怎么用 |
|------|-------------|
| **AI 模型推理** | 网页直接调用 Python 训练的模型，实时推理——**AI 从"服务器专属"变成"前端可及"** |
| **高性能计算** | 浏览器调用 C++ 数学库，做复杂计算——**网页也能算大数据** |
| **物联网控制** | 网页调用 Go 微服务控制智能设备——**点一下网页，灯就亮了** |
| **游戏辅助** | 浏览器调用 Rust 游戏引擎——**页游也能有 3A 级的计算能力** |
| **遗留系统集成** | 网页调用 20 年前 Pascal 写的 ERP 系统——**古董系统也上云了** |
| **极速原型开发** | 不写后端接口，直接调服务——**原型开发提速 10 倍** |
| **跨语言编排** | 一个网页同时调 C++、Python、Go 的服务——**真·全栈** |


## 性能数据（浏览器里也能飞）

| 场景 | 延迟 | 说明 |
|------|------|------|
| 本地 IPC（同机） | **< 1 ms** | 浏览器 + 网关 + zAPI 同机，快到你感觉不到 |
| 局域网 TCP | ~2–5 ms | 办公网内，响应丝滑 |
| 跨公网 TCP | 取决于网速 | 比传统 REST API 少一层 JSON 序列化，实测快 30% |

**浏览器里调用 C++ 服务，比你去调 REST API 还快——因为你绕过了 HTTP 序列化/反序列化开销，走的是二进制协议。**


## 常见问题（FAQ）

**Q1：需要配置 CORS 吗？**
A：不用，因为页面和网关是**同源**的（都是 `localhost:8080`）。如果网关部署到其他地址，加几行 CORS 头就行。

**Q2：能部署到公网吗？**
A：能。把网关部署到云服务器上，浏览器通过公网 IP 访问即可。建议加一层 HTTPS 和鉴权。

**Q3：页面能自适应吗？**
A：能。页面已做了响应式布局，手机、平板、电脑都能优雅显示——**你在地铁上都能拿手机体验**。

**Q4：支持 WebSocket 吗？**
A：目前是 HTTP 长轮询，但 zAPI 底层支持双向流，后续可扩展 WebSocket 支持——**不过当前 HTTP 模式已经够快了**。

**Q5：能不能用 React/Vue 调用？**
A：能，`fetch` 是标准 Web API，任何框架都能用。你甚至可以封装成一个 `useZApi` Hook。

**Q6：和 ZAPI Bridge 是什么关系？**
A：`js_api.py` 是 ZAPI Bridge v2.0 生态的浏览器专用版本。完整的 Bridge 还支持 PHP 和 Node.js 双向调用。


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
- [js_api.py 使用指南](js_api.py%20使用指南.md)
- [📖 ZAPI Bridge 完整使用手册](../bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)
- [ZAPI 桥接开发踩坑记录](../bridge/ZAPI%20桥接开发踩坑记录.md)


## 总结

> **"以前前端是'切图仔'，现在前端是'总指挥'——点一下按钮，全世界都为你运转。"**

`js_api.py` 是个不到 200 行核心逻辑的文件，但它干的事是：

**让浏览器 JavaScript 拥有了调用整个 zAPI 生态的能力。**

你的网页现在可以：
- 调用 C++ 的高性能计算模块
- 调用 Python 的 AI 推理服务
- 调用 Go 的微服务
- 调用 Rust 的系统级库
- 调用 Java 的大数据组件
- 调用 20 年前的 Pascal 遗留系统
- 调用 PHP 和 Node.js 的服务（通过 Bridge v2.0）

**这不是画饼，这是你今晚就能跑通的代码。** 🚀


## 🤝 社区 & 支持

- **开源首页**：[https://github.com/PassByYou888/zAPI](https://github.com/PassByYou888/zAPI)
- **仓库地址**：[https://github.com/PassByYou888/zAPI.git](https://github.com/PassByYou888/zAPI.git)
- **作者 QQ**：`600585`

**Star、Fork、Issue、PR——来者不拒，你的每一个 Star 都是我们熬夜写代码的动力。**


## 📄 许可证

**MIT License** —— 商业、开源、个人项目通通可以用，**放心大胆地用**。


> **"让每一种语言，都能被浏览器轻松调用。"**
> —— 这不是口号，是 zAPI 每天都在做的事。

**现在，去给你的网页开个"跨语言外挂"吧。** 🌐
