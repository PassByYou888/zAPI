# zAPI — 让所有编程语言平等对话

**zAPI** 是一个基于 **纯 C ABI** 的跨语言 RPC 框架，让 C++、Python、Go、Rust、Java、C#、Pascal、PHP、Node.js 等 10+ 种语言编写的服务能够互相调用，就像调用本地函数一样简单。

> **核心承诺：** 无需 IDL，无需代码生成，无需学习新协议——用你熟悉的语言，调用全世界。

---

## 🌟 关于本项目的开放性

**zAPI 是一个完全开放、非商业性的开源项目。**

- ✅ **永久免费**：MIT 许可证，任何个人、团队、企业均可自由使用，包括商业用途。
- ✅ **无商业捆绑**：没有任何收费功能、付费订阅或商业版本。
- ✅ **社区驱动**：所有发展决策来自社区贡献者，而非商业公司。
- ✅ **开放协作**：欢迎任何形式的贡献——代码、文档、测试、Issue 讨论。
- ✅ **透明开发**：所有源码公开，构建过程可复现，无闭源组件。

> 💡 **我们相信：** 跨语言通信应该是每个开发者的基本权利，而不应该被商业壁垒所限制。zAPI 将始终如一地保持开放、免费、社区驱动。

---

## 📦 一个 C ABI，承载无限可能

zAPI 基于**纯 C 动态库**设计，任何支持 FFI 的语言都能接入。你不需要学习新的 IDL，不需要代码生成，不需要复杂的配置——**只需一个头文件，就能让函数跨语言、跨进程、跨机器运行**。

```c
// C 语言注册一个 API
static void __cdecl AddCallback(void* trigger, void* input, void* output) {
    int a, b;
    API_ReadBuffer((TDataHnd)input, &a, sizeof(a));
    API_ReadBuffer((TDataHnd)input, &b, sizeof(b));
    int sum = a + b;
    API_WriteBuffer((TDataHnd)output, &sum, sizeof(sum));
}

int main() {
    // 库会在第一次调用 API 函数时自动加载，无需手动调用加载函数
    TAppHnd app = API_Create_APPHnd("Calc", "Calculator");
    API_Reg_Call(app, "add", "Add two ints", NULL, AddCallback);
    // 准备网络...
    API_Prepare_Service("0.0.0.0", "127.0.0.1:9898");
    API_Prepare_Client("127.0.0.1:9898", app);
    API_Prepare_Done();
    // 这个 API 现在可以被任何语言调用
}
```

---

## 🚀 核心特性

| 特性 | 说明 |
|------|------|
| **🌍 10+ 语言绑定** | C++、Python、Go、Rust、Java、C#、Pascal、VB.NET、PHP、Node.js、Web.js — 开箱即用 |
| **⚡ 高性能** | IPC 模式延迟 < 1ms，吞吐量 10,000+ 请求/秒 |
| **🔌 双通信模式** | TCP（跨机器）+ IPC（同机微秒级延迟） |
| **🔄 自动服务发现** | 基于 C4 服务网格，自动注册、发现、负载均衡 |
| **🛡️ 容错与重连** | 断线自动重连，服务自动重新注册 |
| **🧵 全线程安全** | 所有 API 均支持并发调用 |
| **📦 零拷贝传输** | 直接访问内部缓冲区，极致性能 |
| **🎯 两种调用模式** | 请求-响应（Call）+ 单向通知（Notify） |
| **🔧 动态注销 API** | `API_UnReg` —— 运行时移除 API，自动广播至所有对等节点（约 3 秒传播） |
| **⚙️ 运行时配置** | `API_SetOption` —— 动态调整认证密码、等待连接、IPC 线程池等参数，无需重启 |
| **🔧 零配置启动** | 首次运行自动生成配置文件，无需重新编译即可调优 |

---

## 🎯 支持的语言

zAPI 支持两种集成方式：

- **原生 FFI 绑定** —— 语言可以直接通过 FFI 加载 C 动态库（C、C++、Python、Go、Rust、Java、C#、Pascal、VB.NET）。
- **HTTP 网关（ZAPI Bridge）** —— 无法直接加载 C 库的语言，通过轻量级 HTTP → zAPI 网关接入（PHP、Node.js、Web.js 以及任何支持 HTTP 的语言）。

| 语言 | 集成方式 | 文档 | 示例 |
|------|----------|------|------|
| **C++** | 原生 FFI（RAII） | [📖 使用指南](./C++/API%20Hub%20Tool%20C++%20使用指南.md) | [7 个示例](./C++) |
| **C** | 原生 FFI（显式加载） | [📖 使用指南](./C++/API%20Hub%20Tool%20C%20语言使用指南.md) | [7 个示例](./C++) |
| **Python** | 原生 FFI（`ctypes` + `@expose`） | [📖 完整指南](./Py/从零到一，掌握多语言互调.md) | [20+ 示例](./Py/examples/) |
| **Go** | 原生 FFI（CGO） | [📖 完整指南](./Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md) | [14 个示例](./Go/demos/) |
| **Rust** | 原生 FFI（`libloading` + RAII） | [📖 使用指南](./rust/zAPI%20Rust%20使用指南.md) | [14 个示例](./rust/examples/) |
| **Java** | 原生 FFI（JNA + AutoCloseable） | [📖 使用指南](./java/API%20Hub%20Java%20使用指南.md) | [4 个示例](./java/demo/) |
| **C#** | 原生 FFI（P/Invoke + .NET 8+） | [📖 完整指南](./C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md) | [7 个示例](./C%23/) |
| **VB.NET** | 原生 FFI（P/Invoke） | [📖 使用指南](./VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md) | [5 个示例](./VB.NET/) |
| **Pascal (Delphi/FPC)** | 原生 FFI（`external` 自动加载） | [📖 完整指南](./pascal/API%20Hub%20Tool%20for%20Pascal.md) | [3 个示例](./pascal/) |
| **PHP** | HTTP 网关（ZAPI Bridge） | [📖 Bridge 完整手册](./Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md) | [PHP 客户端](./Py/bridge/PHP/) |
| **Node.js v2.0** | HTTP 网关（ZAPI Bridge） | [📖 Bridge 完整手册](./Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md) | [Node.js 客户端](./Py/bridge/node.js/) |
| **Web.js (浏览器)** | HTTP 网关（ZAPI Bridge） | [📖 js_api 使用指南](./Py/web/js_api.py%20使用指南.md) | [js_api 示例](./Py/web/js_api.py) |

> **Node.js v2.0** 现已改用 **ZAPI Bridge** —— 一个轻量级 Python HTTP 网关，提供完整的双向跨语言调用能力，无需原生依赖。详细说明见 [Bridge 完整手册](./Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)。

> 任何支持 C ABI 的语言都可以接入——您甚至可以为自己的语言编写绑定。

---

## 🚀 5 分钟快速体验

### 第一步：获取动态库

从 [Releases](https://github.com/PassByYou888/zAPI/releases) 下载对应平台的动态库：

| 平台 | 核心库 | IPC 依赖 |
|------|--------|----------|
| Windows 64-bit | `z_api_hub64.dll` | `z_ipc_64.dll` |
| Linux | `libz_api_hub.so` | `libz_ipc.so` |
| macOS | `libz_api_hub.dylib` | `libz_ipc.dylib` |

### 第二步：用 Python 写一个服务

```python
# service.py
from api_hub import Server

app = Server("Calculator")

@app.expose("add")
def add(a: int, b: int) -> int:
    return a + b

if __name__ == "__main__":
    app.start("ipc:calc_service")
    input("按 Enter 停止...")
    app.stop()
```

### 第三步：用 Go 写一个客户端（原生 FFI）

```go
package main

import (
    "fmt"
    "github.com/PassByYou888/zAPI/api_hub"
)

func main() {
    client, _ := api_hub.NewClient()
    client.PrepareClient("ipc:calc_service")
    client.PrepareDone()

    param, _ := client.CreateDataHnd("add")
    client.WriteInt32(param, 10)
    client.WriteInt32(param, 20)

    result, _ := client.Call("Calculator", param, 3000)
    sum, _ := client.ReadInt32(result)

    fmt.Printf("10 + 20 = %d\n", sum)  // 输出: 10 + 20 = 30
}
```

### 第四步：或者用 PHP 写一个客户端（HTTP 网关）

```php
<?php
require_once 'Py/bridge/PHP/ZAPIBridgeClient.php';

$client = new ZAPIBridgeClient('http://127.0.0.1:8080/v1');
$result = $client->invoke('Calculator', 'add', [10, 20]);
echo "10 + 20 = " . $result . "\n";  // 输出: 10 + 20 = 30
?>
```

**运行：**
```bash
# 终端 1：启动 Python 服务
python service.py

# 终端 2：启动 ZAPI Bridge（HTTP 网关）
cd Py/bridge
python zapi_bridge.py

# 终端 3：运行 Go 客户端（原生）
go run client.go

# 或者运行 PHP 客户端（通过 HTTP 网关）
php client.php
```

**Python 写的服务，Go（原生）或 PHP（通过 HTTP 网关）直接调用——不需要任何额外配置。**

---

## 🛠️ 从源码构建 zAPI 动态库

如果你需要从源码自行构建 zAPI 动态库（例如特殊平台、定制需求），请参阅完整的构建指南：

> 📖 **[《CONTRIBUTING.md》—— zAPI 动态库构建指南](./src/CONTRIBUTING.md)**

该指南涵盖：

| 平台 | 构建方式 |
|------|----------|
| **Windows** | 安装 Lazarus → `lazbuild z_api_hub.lpi` |
| **Linux（有 Lazarus 包）** | 包管理器安装 Lazarus → `lazbuild z_api_hub.lpi` |
| **Linux（无 Lazarus / FPC 版本过低）** | 手动编译 `lazbuild`（使用 FPC 3.3.1）→ 构建 zAPI |

**构建核心命令（前提：已安装 Lazarus 且 FPC ≥ 3.2.2）**：

```bash
git clone --recursive https://github.com/PassByYou888/zAPI.git
cd zAPI/src
lazbuild z_api_hub.lpi
```

> ⚠️ **注意**：克隆时必须使用 `--recursive` 选项拉取所有子模块（zIPC、mimalloc4p）。FPC 版本必须 ≥ 3.2.2，否则请参阅构建指南中的“手动构建 lazbuild”路线。

---

## 📊 性能数据

**测试环境：** Intel Xeon Gold 6248 / 32GB RAM / Ubuntu 22.04

| 通信模式 | 平均延迟 (p50) | 最大吞吐量 | 适用场景 |
|----------|----------------|------------|----------|
| 同机 IPC（命名管道） | **< 0.8 ms** | ~12,000 req/s | 单机微服务、边缘计算 |
| 本地 TCP 回环 | ~2.5 ms | ~6,500 req/s | 开发测试环境 |
| 跨机器局域网 TCP | ~5-15 ms | 受带宽限制 | 生产环境分布式部署 |

**对比参照：**

| 方案 | 典型延迟 | 相对开销 |
|------|----------|----------|
| zAPI (IPC) | < 1 ms | 基准 |
| zAPI (TCP) | ~2-3 ms | +2-3 ms |
| gRPC (TCP) | ~5-8 ms | +4-6 ms |
| HTTP REST (JSON) | ~10-20 ms | +9-18 ms |

**性能优势来源：**
1. **零拷贝数据传递：** `API_GetBuffer()` 直接返回内部指针，无二次复制。
2. **二进制协议：** 无 JSON/Protobuf 编解码开销。
3. **C 层并发调度：** 回调在 C 线程池执行，不受 Python/Node 等语言的 GIL 限制。

---

## 🐝 Cross Demo：多语言分布式计算演示

想让您亲眼看到负载均衡在 10 多种语言之间如何工作？**Cross Demo** 是一个不到 200 行代码的示例集群，它让您可以用 Python、Go、Rust、Java、C#、Pascal 等语言启动任意数量的工作节点，所有节点自动注册到同一个服务网格，客户端请求会被 C4 网格自动均匀分发到各个节点。

- [🚀 Cross Demo 全语言实战手册](./🚀%20Cross%20Demo%20全语言实战手册.md) —— 一键启动所有语言节点的操作指南，含详细的命令行步骤。
- [🚀 Cross Demo：分布式计算的可视化“蜂群” 🐝](./🚀%20Cross%20Demo：分布式计算的可视化“蜂群”%20🐝.md) —— 深入理解负载均衡原理、二进制序列化协议以及跨语言互调的底层机制。

> 无论您用哪种语言，Cross Demo 都能让您直观感受 zAPI 的“语言透明”和“自动治理”能力。推荐您在跑通“5 分钟快速体验”后，立即尝试 Cross Demo，感受多语言集群的魅力。

---

## 🌐 完整的语言互操作矩阵

**任意语言的客户端可以调用任意语言的服务端：**

| 服务端 ↓ / 客户端 → | C++ | Python | Go | Rust | Java | C# | Pascal | PHP | Node | Web |
|---------------------|-----|--------|-----|------|------|-----|--------|-----|------|-----|
| **C++** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Python** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Go** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Rust** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Java** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **C#** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Pascal** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

> PHP 和 Node.js 客户端通过 ZAPI Bridge（HTTP 网关）与所有服务通信。

---

## 📂 项目结构

```
zAPI/
├── Binary/                # 动态库和可执行文件
│   ├── z_api_hub64.dll    # 核心动态库
│   └── z_ipc_64.dll       # IPC 支持库
├── src/                   # ⭐ 核心源码和构建脚本
│   ├── z_api_hub.lpi      # 主项目文件（构建动态库）
│   ├── CONTRIBUTING.md    # 完整构建指南
│   └── ...
├── C++/                   # C/C++ 绑定 + 示例
├── Py/                    # Python 绑定 + 20+ 示例
│   ├── api_hub/           # Python 核心绑定
│   ├── bridge/            # 🌉 ZAPI Bridge（PHP/Node.js/Pascal HTTP 网关）
│   │   ├── PHP/           # PHP 客户端库
│   │   ├── node.js/       # Node.js 客户端库（v2.0）
│   │   └── pascal/        # Pascal Bridge 示例
│   ├── cross/             # ⭐ 跨语言 Cross Demo（多语言负载均衡演示）
│   │   ├── nodejs/        # Node.js 客户端示例
│   │   └── php/           # PHP 客户端示例
│   ├── node/              # Node.js 网关（旧版，已被 Bridge 取代）
│   └── web/               # Web.js 浏览器网关
├── Go/                    # Go 绑定 + 14 个示例
├── java/                  # Java 绑定 + JNA
├── rust/                  # Rust 绑定 + 14 个示例
├── C#/                    # C# 绑定 + 7 个示例
├── VB.NET/                # VB.NET 绑定 + 5 个示例
├── pascal/                # Pascal 完整文档
└── node/                  # Node.js 客户端示例（旧版）
```

---

## 🧩 ZAPI HTTP Bridge（PHP/Node.js 支持）

**ZAPI Bridge** 是一个 HTTP ↔ zAPI 双向网关，让 PHP、Node.js 以及任何能发起 HTTP 请求的语言都能接入 zAPI 生态。

**核心功能：**
- 🌉 **双向调用**：从 PHP/Node.js 调用 zAPI 服务，同时将 PHP/Node.js 函数暴露为 zAPI 服务。
- 🐘 **PHP 完整支持**：提供 `invoke()`、`notify()`、`registerHook()`、`unregisterHook()` 等完整客户端 API。
- 🟢 **Node.js v2.0**：现代化 Promise 风格客户端，取代旧版 npm 方案。
- 📦 **零原生依赖**：无需 FFI、无需编译——只需 HTTP。
- 🚀 **高性能**：本地调用典型延迟 1-3ms。
- 🔧 **热注册**：运行时动态注册/注销 Webhook。

### Bridge 文档
- [📖 ZAPI Bridge 完整使用手册](./Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)
- [🐍 Python 依赖清单](./Py/bridge/ZAPI%20Bridge%20Python%20依赖清单.md)
- [🛠️ 开发踩坑记录](./Py/bridge/ZAPI%20桥接开发踩坑记录.md)
- [🧪 多语言交叉测试脚本](./Py/bridge/run_cross_test.ps1)

### PHP 客户端示例
```php
require_once 'ZAPIBridgeClient.php';
$client = new ZAPIBridgeClient('http://127.0.0.1:8080/v1');
$result = $client->invoke('Calculator', 'add', [10, 20]);
```

### Node.js 客户端示例（v2.0）
```javascript
const { ZAPIBridgeClient } = require('./ZAPIBridgeClient');
const client = new ZAPIBridgeClient('http://127.0.0.1:8080/v1');
const result = await client.invoke('Calculator', 'add', [10, 20]);
```

---

## 🔒 线程安全与回调执行上下文

> **zAPI 的所有 API 函数都是完全线程安全的。**  
> 你可以在成千上万个线程中同时调用 `API_Call`，库会自动处理所有并发。

**但需要注意回调执行上下文：**

回调函数（`TAPI_Call` / `TAPI_Notify`）在**后台线程池**中执行。这意味着：

- ❌ **禁止**在回调中调用 `API_Call` 或 `API_Notify`——可能导致死锁。
- ❌ **禁止**在回调中做长时间阻塞操作。
- ❌ **禁止**在回调中直接访问 UI 组件。
- ✅ **推荐**将耗时任务异步提交到自己的工作线程。

```cpp
// ❌ 错误做法：在回调中调用 API_Call
static void __cdecl BadCallback(void* trigger, void* input, void* output) {
    // 死锁风险！
    TDataHnd result = API_Call("OtherApp", input, 5000);
}

// ✅ 正确做法：异步提交任务
static void __cdecl GoodCallback(void* trigger, void* input, void* output) {
    // 将请求放入队列，由工作线程处理
    WorkQueue.push(input);
    // 快速返回
}
```

---

## 🏗️ 架构原理

```
┌─────────────────────────────────────────────────────────────────┐
│                    应用层（10+ 种语言）                         │
├──────────┬──────────┬──────────┬──────────┬─────────────────────┤
│  C++     │  Python  │  Go      │  Rust    │  Java / C#          │
│  Pascal  │  VB.NET  │  C       │          │                     │
├──────────┴──────────┴──────────┴──────────┴─────────────────────┤
│                   统一的 C ABI 动态库层                         │
├─────────────────────────────────────────────────────────────────┤
│              C4 分布式服务网格（自动发现/负载均衡）             │
├─────────────────────────────────────────────────────────────────┤
│         TCP        │        IPC        │   自动服务发现         │
│      (跨机器)      │     (同机通信)    │   负载均衡             │
├─────────────────────────────────────────────────────────────────┤
│                   ZAPI Bridge（HTTP 网关）                      │
│          PHP / Node.js / Web.js / 任意 HTTP 客户端              │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📖 文档导航

### 快速入门
- [zAPI 帝国藏宝图：一分钟速通全语言版图](./pascal/zAPI%20帝国藏宝图：一分钟速通全语言版图.md) — 项目结构总览
- [zAPI：让所有编程语言平等对话的分布式服务网格](./pascal/zAPI：让所有编程语言平等对话的分布式服务网格.md) — 项目概述

### 各语言完整指南

> 快速上手可参考 [Pascal Demo 使用说明](./pascal/Pascal%20Demo%20使用说明Delphi+%20Free%20Pascal.md)。

| 语言 | 文档 |
|------|------|
| **C++** | [API Hub Tool C++ 使用指南](./C++/API%20Hub%20Tool%20C++%20使用指南.md) |
| **C** | [API Hub Tool C 语言使用指南](./C++/API%20Hub%20Tool%20C%20语言使用指南.md) |
| **Python** | [从零到一，掌握多语言互调](./Py/从零到一，掌握多语言互调.md) |
| **Go** | [API Hub for Go 从零到一掌握多语言互调](./Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md) |
| **Rust** | [zAPI Rust 使用指南](./rust/zAPI%20Rust%20使用指南.md) |
| **Java** | [API Hub Java 使用指南](./java/API%20Hub%20Java%20使用指南.md) |
| **C#** | [API Hub Tool for C# — 完整使用指南](./C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md) |
| **VB.NET** | [老哥别卷了，你的 VB.NET 代码今天开始全栈通杀](./VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md) |
| **Pascal** | [API Hub Tool for Pascal — 完整使用指南](./pascal/API%20Hub%20Tool%20for%20Pascal.md) |
| **PHP** | [ZAPI Bridge 完整使用手册](./Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md) |
| **Node.js** | [ZAPI Bridge 完整使用手册](./Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md) |
| **Web.js** | [js_api.py 使用指南](./Py/web/js_api.py%20使用指南.md) |

### 架构决策与实战
- [Go 微服务架构实战：用 zAPI 替换 gRPC 后，我们的延迟大幅降低](./Go/Go%20微服务架构实战：用%20zAPI%20替换%20gRPC%20后，我们的延迟大幅降低.md)
- [Python 微服务选型：为什么我们用 zAPI 替代 Flask 作为推理服务网关](./Py/web/Python%20微服务选型：为什么我们用%20zAPI%20替代%20Flask%20作为推理服务网关.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](./Py/web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)

### 运维与进阶
- [ZAPI 数据句柄自动化内存回收机制 —— 为长期稳定运行而设计](./ZAPI%20数据句柄自动化内存回收机制%20——%20为长期稳定运行而设计.md) —— 深入理解 zAPI 的内存管理策略，保障 7×24 小时高可用。

---

## 🤝 参与贡献

我们欢迎任何形式的贡献：

- 🐛 报告 Bug
- 💡 提出新特性
- 📝 改进文档
- 🔧 提交 Pull Request
- 🌍 为更多语言编写绑定

> **构建指南**：如果您需要从源码构建 zAPI 动态库，请参阅 [CONTRIBUTING.md](./src/CONTRIBUTING.md)。

---

## 📄 许可证

**MIT License** —— 自由使用、修改、分发，甚至用于商业项目。

---

## ⭐ Star 支持

如果这个项目对您有帮助，请给我们一个 Star！您的支持是我们持续改进的动力。

---

**让所有语言，相互对话。**

[GitHub](https://github.com/PassByYou888/zAPI) · [Issues](https://github.com/PassByYou888/zAPI/issues) · [Releases](https://github.com/PassByYou888/zAPI/releases)
