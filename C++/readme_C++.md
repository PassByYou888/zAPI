# API Hub Tool – 打通一切，连接万物

## 一个头文件，让所有语言无缝互通

**版本：** 2.0（与 ZAPI 核心 v2.0 同步）

---

**API Hub Tool** 是一个**头文件级**的多语言分布式 RPC 框架。  
它让 **C、C++、Pascal、Python、C#、Java、Go、Rust、PHP、Node.js** 等语言可以**互相调用**对方的函数，就像调用本地函数一样简单。

---

## 📦 一个 C ABI，承载无限可能

API Hub 基于**纯 C 动态库**设计，任何支持 FFI 的语言都能接入。你不需要学习新的 IDL，不需要代码生成，不需要复杂的配置——**只需一个头文件，就能让函数跨语言、跨进程、跨机器运行**。

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
    API_LoadLibrary();
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

## 🌍 支持的语言（远不止这些）

| 语言 | 接入方式 | 难度 | v2.0 新特性 |
|------|---------|------|-------------|
| **C** | `#include "API_HubTool.h"` | ⭐ | ✅ 动态注销 `API_UnReg` |
| **C++** | `#include "API_HubTool.hpp"` | ⭐ | ✅ 运行时配置 `API_SetOption` |
| **Pascal (Delphi/FPC)** | `uses z_api_hubtool_import` | ⭐ | ✅ 热卸载支持 |
| **Python** | `ctypes.CDLL` | ⭐⭐ | ✅ `@expose` 装饰器 |
| **C#** | `[DllImport]` | ⭐⭐ | ✅ 自动库加载 |
| **Java** | JNA / JNI | ⭐⭐ | ✅ AutoCloseable 资源管理 |
| **Go** | `cgo` | ⭐⭐ | ✅ 动态注册/注销 |
| **Rust** | `extern "C"` | ⭐⭐ | ✅ RAII 封装 |
| **PHP** | HTTP Bridge (v2.0 新增) | ⭐ | ✅ 通过 ZAPI Bridge 双向调用 |
| **Node.js** | HTTP Bridge (v2.0 新增) | ⭐ | ✅ 零原生依赖，v2.0 全新体验 |

**没有任何语言限制。任何能调用动态库的语言，都能立即接入。**

> **v2.0 重大升级：** PHP 和 Node.js 现在可以通过 **ZAPI Bridge** 直接调用所有 zAPI 服务，实现双向跨语言调用。详见 [📖 ZAPI Bridge 完整使用手册](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)。

---

## ⚡ 技术核心——C4 分布式服务网格

API Hub 底层是成熟的 **C4 分布式服务网格**，具备企业级通信能力：

### 🔍 自动服务发现
服务启动后自动广播自己的地址和 API 列表。客户端无需任何配置，就能找到需要的服务。

### ⚖️ 智能负载均衡
客户端实时获取所有服务实例的负载状态（线程数、活跃请求数），自动将请求路由到**负载最低**的实例。

### 🔄 自动断线重连
网络抖动、服务重启、机器宕机——客户端自动检测并重连，业务代码无需处理任何异常。

### 🌐 NAT 穿透
支持跨公网、跨云、跨机房部署，无需公网 IP，无需端口映射，开箱即用。

### 🚄 IPC 零拷贝通道
同机通信使用操作系统级 IPC（命名管道/共享内存），延迟 **< 1 毫秒**，吞吐量 **10,000+ 请求/秒**。

### 🔧 动态 API 注销（v2.0 新增）
`API_UnReg` 运行时移除 API，自动广播至所有对等节点（约 3 秒传播）。适合热卸载插件、临时维护、权限动态调整。

### ⚙️ 运行时配置（v2.0 新增）
`API_SetOption` 动态调整认证密码、等待连接、IPC 线程池等参数，无需重启应用。

---

## 🔥 C++ 开发者体验：RAII 封装，现代 C++ 风格

```cpp
#include "API_HubTool.hpp"

using namespace z_api_hub;

// 回调必须是 __cdecl，确保 ABI 稳定
static void __cdecl AddCallback(void* trigger, void* input, void* output) {
    DataHandle in(static_cast<TDataHnd>(input), false);   // 借用，不释放
    DataHandle out(static_cast<TDataHnd>(output), false);

    int a, b;
    if (in.read(a) != sizeof(a) || in.read(b) != sizeof(b)) return;
    int sum = a + b;
    out.write(sum);
}

int main() {
    try {
        // RAII：自动加载/卸载动态库
        LibraryLoader loader;

        // RAII：自动释放应用句柄
        App app("Calculator", "Demo");
        API_Reg_Call(app.get(), "add", "Add two ints", nullptr, AddCallback);

        // RAII：数据句柄自动管理内存
        DataHandle param("add");
        param.write(5);
        param.write(7);

        // 本地调用（不经过网络，用于测试/调试）
        auto result = app.localCall(param);
        int sum;
        result.read(sum);
        std::cout << "5 + 7 = " << sum << '\n';

        // v2.0 新增：动态注销 API
        app.unregister("add");

        // v2.0 新增：运行时配置
        setOption("Wait_Connection_ReadyOk", "False");

        // 所有资源在析构时自动释放
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << '\n';
        return 1;
    }
    return 0;
}
```

**没有裸指针，没有手动释放，没有泄漏风险。** 现代 C++ 开发者会感到宾至如归。

---

## 🐍 Python 调用 C++ 服务——只需 10 行

```python
from ctypes import *

lib = cdll.LoadLibrary("z_api_hub64.dll")

# 创建数据，指定 API 名
data = lib.API_Create_DataHnd(b"add")
lib.API_WriteBuffer(data, byref(c_int(5)), 4)
lib.API_WriteBuffer(data, byref(c_int(7)), 4)

# 远程调用（阻塞，带超时）
result = lib.API_Call(b"Calculator", data, 5000)
lib.API_Free_DataHnd(data)

# 读取结果
sum = c_int()
lib.API_ReadBuffer(result, byref(sum), 4)
print(f"5 + 7 = {sum.value}")

lib.API_Free_DataHnd(result)
```

**C++ 服务端一行代码都不用改，Python 就能调用了。**

---

## ☕ C# 调用——同样简单

```csharp
[DllImport("z_api_hub64.dll", CallingConvention = CallingConvention.Cdecl)]
static extern IntPtr API_Create_DataHnd(string name);

[DllImport("z_api_hub64.dll")]
static extern IntPtr API_Call(string app, IntPtr param, ulong timeout);

// 使用
var data = API_Create_DataHnd("add");
// 写入两个 int...
var result = API_Call("Calculator", data, 5000);
// 读取结果...
```

---

## 📊 性能数据——不是"够用"，而是"极致"

| 场景 | 延迟 | 吞吐量 |
|------|------|--------|
| 本地 IPC | **< 1 ms** | **10,000+ 次/秒** |
| 本地 TCP 回环 | ~2–5 ms | ~3,000 次/秒 |
| 跨机房 TCP | 网络延迟决定 | ~1,000 次/秒 |
| 1000 并发线程 | 线性扩展 | 无性能衰减 |

### 为什么这么快？

- **零拷贝**：`API_GetBuffer()` 返回直接指针，无需二次复制。
- **无锁数据结构**：底层使用原子操作和自旋锁，减少上下文切换。
- **自动压缩**：大数据传输自动压缩，节省带宽。
- **异步线程池**：回调在后台执行，主循环永不阻塞。

---

## 🎯 应用场景——无限可能

### 🎮 游戏开发
- **C++ 写核心战斗逻辑**，**C#/Lua 写业务层**。
- 客户端和服务器共享同一套 API 定义，本地测试 + 远程部署无缝切换。

### 🤖 物联网 / 边缘计算
- **嵌入式设备用 C 暴露传感器接口**，**云端用 Python/Go 消费**。
- 穿透 NAT，无需公网 IP，自动重连。

### 🏭 工业自动化
- **二十年历史的 Delphi 控制系统**，通过 API Hub 暴露给现代微服务。
- **无需重写历史代码**，实现现代化改造。

### 🧠 AI / 数据科学
- **Python 训练模型**，**C++ 做高性能推理服务**。
- 两者通过 API Hub 直接通信，无需中间层。

### 🔧 桌面应用插件系统
- 主程序用 **C++ 或 Pascal**，插件可以用**任何语言**写。
- 插件自动发现、动态加载、安全隔离。

### ☁️ 微服务架构
- 替代 gRPC / REST，**减少 80% 的样板代码**。
- 内置服务发现和负载均衡，**不需要 Consul / Eureka**。

---

## ⚖️ 方案对比——为什么选 API Hub

| 特性 | API Hub v2.0 | gRPC | REST | ZeroMQ | 手工 Socket |
|------|---------|------|------|--------|-------------|
| **多语言 C ABI** | ✅ | ❌ | ❌ | ✅ | ❌ |
| **无需 IDL/代码生成** | ✅ | ❌ | ❌ | ❌ | ❌ |
| **自动服务发现** | ✅ | ❌ | ❌ | ❌ | ❌ |
| **内置负载均衡** | ✅ | ❌ | ❌ | ❌ | ❌ |
| **NAT 穿透** | ✅ | ❌ | ❌ | ❌ | ❌ |
| **自动重连** | ✅ | ❌ | ❌ | ❌ | ❌ |
| **IPC（<1ms）** | ✅ | ❌ | ❌ | ✅ | ❌ |
| **零拷贝** | ✅ | ❌ | ❌ | ❌ | ❌ |
| **动态注销 API** | ✅ (v2.0) | ❌ | ❌ | ❌ | ❌ |
| **运行时配置** | ✅ (v2.0) | ❌ | ❌ | ❌ | ❌ |
| **PHP/Node.js 支持** | ✅ (v2.0) | ✅ | ✅ | ❌ | ❌ |
| **学习曲线** | **极低** | 高 | 中 | 中 | 高 |
| **代码量** | **极少** | 多 | 中 | 中 | 极多 |

---

## 🔒 线程安全与回调执行上下文

> **API Hub 的 API 函数（除 `API_Get_Status` 外）都是完全线程安全的。**  
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

## 📂 文件结构

```
API_HubTool.h       - C 接口声明
API_HubTool.hpp     - C++ RAII 包装（推荐）
API_HubTool.c       - 动态库加载器实现
z_api_hubtool_import.pas - Pascal 导入单元
```

---

## 🚀 快速开始（5 分钟）

### 1. 获取动态库

- **Windows 64-bit**: `z_api_hub64.dll`
- **Windows 32-bit**: `z_api_hub32.dll`
- **Linux**: `libz_api_hub.so`
- **macOS**: `z_api_hub.dylib`

### 2. 包含头文件

- **C**: `#include "API_HubTool.h"`
- **C++**: `#include "API_HubTool.hpp"`

### 3. 编译运行

```bash
# Linux
gcc -o server server.c -ldl
./server

# Windows (MSVC)
cl /Fe:server.exe server.c
server.exe
```

### 4. 用任意语言调用

参考上面的 Python、C#、Go、PHP、Node.js 示例，立即可用。

---

## 📚 完整文档

- [C API 完整参考](API_HubTool.h)（内含详细注释）
- [C++ RAII 包装文档](API_HubTool.hpp)（内含示例）
- [C 语言使用指南](API%20Hub%20Tool%20C%20语言使用指南.md)
- [C++ 使用指南](API%20Hub%20Tool%20C++%20使用指南.md)
- [Pascal 完整使用指南](../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- [📖 ZAPI Bridge 完整使用手册](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)

---

## 📬 联系 & 社区

### 👨‍💻 作者

**老张（QQ：600585）**  
项目发起人 & 核心开发者。欢迎技术交流、问题反馈。

---

## 📄 许可证

**MIT License** —— 商业、开源、个人项目均可自由使用。

---

## ⭐ 给个 Star 吧

如果 API Hub 解决了你的问题，请给我们一个 Star。  
这能帮助更多开发者发现这个工具，让跨语言分布式开发变得简单。

---

**一个头文件，打通所有语言。**  
**一行代码，连接全世界。**

## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](API%20Hub%20Tool%20C++%20使用指南.md)
- [API Hub Tool C 语言使用指南](API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](../Py/从零到一，掌握多语言互调.md)
- [API Hub for Go 从零到一掌握多语言互调](../Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)
- [zAPI Rust 使用指南](../rust/zAPI%20Rust%20使用指南.md)
- [API Hub Java 使用指南](../java/API%20Hub%20Java%20使用指南.md)
- [API Hub Tool for C# — 完整使用指南](../C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [API Hub Tool for Pascal](../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../node/Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](../Py/web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](../Py/web/js_api.py%20使用指南.md)
- [📖 ZAPI Bridge 完整使用手册](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)
