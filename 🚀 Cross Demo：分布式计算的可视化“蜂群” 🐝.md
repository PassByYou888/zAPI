# 🚀 Cross Demo：分布式计算的可视化“蜂群” 🐝

> *“老板，你看这 10 个控制台窗口一起冒数字，像不像你当年在网吧包夜打 CS 的时候？”*  
> *—— 某位 Pascal 老哥跑通 Cross Demo 后的朋友圈*

---

## 1. 这玩意儿到底是个啥？

**Cross Demo** 是 zAPI 生态里最“骚气”的一个示例 —— 它用不到 200 行代码，搭起了一个 **能让你肉眼看到负载均衡** 的分布式计算集群。

它长这样：

```
┌─────────────────────────────────────────────────────────┐
│                    服务注册中心                         │
│                 (cross_service)                         │
│                 IPC 信标：ipc:cross                     │
└─────────────────────┬───────────────────────────────────┘
                      │ 注册 / 发现
          ┌───────────┼───────────┐
          ▼           ▼           ▼
    ┌──────────┐ ┌──────────┐ ┌──────────┐
    │ Worker 1 │ │ Worker 2 │ │ Worker 3 │   ... 可开 N 个
    │  (Node)  │ │  (Node)  │ │  (Node)  │   每个都注册 app='demo'
    │ api:add  │ │ api:add  │ │ api:add  │   提供 'add' 和 'inv_seri'
    │ inv_seri │ │ inv_seri │ │ inv_seri │
    └──────────┘ └──────────┘ └──────────┘
                      ▲
                      │ 自动负载均衡
                      │ (C4 网格帮你搞定)
          ┌───────────┼───────────┐
          ▼           ▼           ▼
    ┌──────────┐ ┌──────────┐ ┌──────────┐
    │ Caller 1 │ │ Caller 2 │ │ Caller 3 │   ... 可开 M 个
    │ (Client) │ │ (Client) │ │ (Client) │   疯狂发送计算请求
    └──────────┘ └──────────┘ └──────────┘
```

**核心组件只有三个：**

- **`cross_service`（信标）**：一个“广播塔”，告诉所有节点“我在这儿”。它不干任何业务活，就是个指路牌。
- **`cross_node`（工人）**：真正干活的苦力。注册应用名 `demo`，暴露 `add`（加法）和 `inv_seri`（序列化逆序大乱斗）两个 API。
- **`cross_call`（甲方）**：疯狂发需求。随机调用 `add` 或 `inv_seri`，持续 10 秒后潇洒退场。

**关键骚操作：**  
你可以在不同终端里启动 **任意数量** 的 `cross_node` 和 `cross_call`。C4 服务网格会自动把所有 `demo` 应用当成一个 **服务池（Service Pool）**，并把客户端请求 **均匀打散** 到各个节点上 —— 你甚至能肉眼看到请求在多个窗口之间“弹射”！

---

## 2. 全语言“全家桶” —— 原生 vs 跳板

zAPI 的 Cross Demo 已经覆盖了 **10 多种编程语言**，让你真正体验“一次编写，到处调用”的快乐。

| 语言 | 接入方式 | 角色 | 状态 |
|------|----------|------|------|
| **Pascal (Delphi/FPC)** | 原生 C 绑定 | Worker / Caller / Service | ✅ 直接开干 |
| **C / C++** | 原生头文件 | Worker / Caller / Service | ✅ 直接开干 |
| **Rust** | 原生 FFI | Worker / Caller / Service | ✅ 直接开干 |
| **Go** | 原生 CGO | Worker / Caller / Service | ✅ 直接开干 |
| **Java** | 原生 JNA | Worker / Caller / Service | ✅ 直接开干 |
| **C#** | 原生 P/Invoke | Worker / Caller / Service | ✅ 直接开干 |
| **VB.NET** | 原生 P/Invoke | Worker / Caller / Service | ✅ 直接开干 |
| **Python** | 原生 ctypes | Worker / Caller / Service | ✅ 直接开干 |
| **PHP** | **通过 Python Bridge** | 仅 Caller | 🚀 跳板接入 |
| **Node.js** | **通过 Python Bridge** | 仅 Caller | 🚀 跳板接入 |
| **Web.js (浏览器)** | **通过 Python Bridge** | 仅 Caller | 🌐 跳板接入 |

> **为什么 Python 是“跳板”？**  
> 因为 PHP、Node.js 和浏览器无法直接加载 C 动态库（FFI 太麻烦或压根不支持），所以我们写了一个 **轻量级 HTTP 中转站 —— `cross_bridge.py`**。它本质上是一个“翻译官”：接收 HTTP JSON 请求，翻译成 zAPI 的二进制协议，丢给服务网格，再把结果翻译成 JSON 还回去。

**一句话总结：**  
- **原生语言**：直接调 C 库，性能拉满，延迟 <1ms。  
- **跳板语言**：通过 HTTP 调 Python 桥，多了一点点网络延迟，但省去了 FFI 的麻烦，照样能玩转分布式计算。

---

## 3. 数据序列化 —— 跨语言的“通用语言”

> *“你说你的，我说我的，但我们都用二进制，谁也别说谁。”*

Cross Demo 最硬核的地方在于 —— **所有语言使用完全一样的二进制数据布局**。不管你是 Pascal 的 `Integer`，还是 Go 的 `int32`，或者是 JavaScript 的 `number`，在网络上传递时都长一个样：

| 字段 | 类型 | 字节数 | 端序 |
|------|------|--------|------|
| `b` | unsigned 8-bit | 1 | little-endian |
| `w` | unsigned 16-bit | 2 | little-endian |
| `c` | unsigned 32-bit | 4 | little-endian |
| `u64` | unsigned 64-bit | 8 | little-endian |
| `s` | UTF-8 字符串 + NUL | 可变 | – |
| `f` | IEEE 754 single | 4 | little-endian |

**`inv_seri` 这个 API 就是在炫技**：  
客户端按 `b, w, c, u64, s, f` 的顺序写入，服务端读到后，**反向** 回复 `f, s, u64, c, w, b`。这就好比你先用英语问，对方用倒序的英语答 —— 目的是证明双方都能正确解析每一个字节，没有任何歧义。

**这波不亏：**  
- 所有语言都遵循这个“字节契约”，所以 Go 写的节点可以被 Pascal 的客户端调用，Python 写的节点可以被 Rust 调用……  
- 你甚至可以把一个节点用 C++ 写，另一个节点用 Java 写，它们之间互相调用，完全无感。

---

## 4. 负载均衡 —— 真·可视化集群

> *“以前你只能看监控图表脑补负载均衡，现在你可以直接开 10 个窗口，看着数字往不同窗口里飞 —— 这才是真·可视化。”*

当你启动多个 `cross_node` 时，C4 服务网格会自动感知它们，并把所有注册了 `demo` 的应用当成一个 **逻辑集群**。客户端发起 `API_Call('demo', ...)` 时，网格会**根据当前各节点的活跃请求数和线程负载**，自动把请求发到最空闲的那个节点。

**实测效果：**  
- 开 10 个 `cross_node`，每个都打印日志。  
- 开 20 个 `cross_call`，每个都疯狂发请求。  
- 你会看到 **10 个窗口同时刷屏**，但每个窗口收到的请求数量大致相等 —— 就像蜂群里的工蜂各自领活，谁也不闲着，谁也不累死。

这就是 **C4 服务网格的智能负载均衡**，完全不需要你写任何调度代码。

---

## 5. 如何快速体验（5 分钟上手）

### 5.1 先跑原生集群（Python 版）

```bash
# 终端 1：启动信标
python cross_service.py

# 终端 2：启动第一个工人
python cross_node.py

# 终端 3：再开一个工人（你也可以开 10 个）
python cross_node.py

# 终端 4：启动客户端（10 秒后自动退出）
python cross_call.py
```

看！多个窗口已经开始“对喷”了！

---

### 5.2 让 PHP/Node.js/浏览器也加入狂欢

启动 `cross_bridge.py`（HTTP 中转站）：

```bash
python cross_bridge.py
```

然后：

- **PHP**：`php php_cross_client.php`
- **Node.js**：`node node_cross_client.js`
- **浏览器**：打开 `web_cross_client.html`，点按钮

你会看到它们也成功调用了 `demo.add` 和 `demo.inv_seri`，而背后其实是 Python 桥在替你打工。

---

## 6. 不同语言的原生实现 —— 你值得拥有

除了 Python，其他语言也都有原生实现，就在项目对应目录下：

- **C++**：`C++/CrossDemo/`  
- **Go**：`Go/demos/cross_*`  
- **Rust**：`rust/examples/cross_*`  
- **Java**：`java/demo/Cross*.java`  
- **C#**：`C#/Cross*`  
- **VB.NET**：`VB.NET/Cross*`  
- **Pascal**：`pascal/cross_demo/`

它们全部 **二进制兼容**，你可以混合启动 —— 比如用 Go 写的节点，配合 C# 写的客户端，再让 Pascal 的节点加入集群。**这就是 zAPI 的终极魅力：语言透明。**

---

## 7. 结语：分布式计算，从“看日志”到“看大片”

过去，我们看分布式系统只能盯着监控面板和日志文件；现在，Cross Demo 让你用 **10 个窗口** 亲眼目睹请求如何在节点间“弹跳”。这不仅是技术演示，更是一种 **视觉化的分布式计算教育工具**。

> *“以前我看不懂负载均衡，现在我看着 10 个窗口同时刷屏，我懂了。”*

**如果你的项目也需要跨语言、跨进程、跨机器的通信，zAPI 可能就是你的梦中情库。**

**🌟 给个 Star，让更多人看到这个“蜂群”吧！**  
[GitHub – zAPI](https://github.com/PassByYou888/zAPI)