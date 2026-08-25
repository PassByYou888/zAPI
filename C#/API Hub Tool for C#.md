# API Hub Tool for C# – 让 .NET 融入多语言分布式世界

## 一个 .cs 文件，让 C# 与 10+ 种语言无缝互通

**版本：** 2.1（与 ZAPI 核心 v2.1 同步）

---

**API Hub Tool** 是一个基于纯 C ABI 的分布式 RPC 框架，为 C# 提供了 **P/Invoke 绑定**，让您的 .NET 应用能够：

- 将任意 C# 方法暴露为远程可调用 API（请求‑响应 `Call` 或单向通知 `Notify`）
- 无痛调用其他语言（C/C++、Python、Java、Go、Rust、Pascal、PHP、Node.js 等）编写的服务
- 在同一台机器上通过 **IPC**（< 1ms）或跨云通过 **TCP** 实现高性能通信
- 享受 **自动服务发现、智能负载均衡、断线重连、NAT 穿透** 等企业级能力
- **v2.1 新增**：支持 `API_Reg_Call_Sync` / `API_Reg_Notify_Sync` —— **UI 主线程同步回调**，对标 Pascal `TSoft_Synchronize_Tool` 机制，业务代码可直接操作 UI 控件，无需手动 `BeginInvoke`

**您只需引用一个 .cs 文件，就能让 .NET 应用瞬间成为分布式服务网格的一等公民。**

---

## 🚀 C# 开发者体验：极简、现代、安全

### 1. 自动加载动态库，无需手工配置

`API_HubTool.cs` 内置了跨平台 DllImport 解析器，会根据当前操作系统和位数自动加载正确的动态库：

```csharp
// 完全自动：Windows 加载 z_api_hub64.dll，Linux 加载 libz_api_hub.so
AppHnd app = API.API_Create_APPHnd("MyApp", "Description");
```

无需手动 `LoadLibrary`，也无需为不同平台编写条件编译。

### 2. 定义你的第一个 API（3 分钟）

```csharp
using API_HubTool.Bindings;
using static API_HubTool.Bindings.API;

// 回调必须使用 Cdecl 调用约定
private static void AddCallback(IntPtr trigger, IntPtr input, IntPtr output)
{
    DataHnd hInput = new DataHnd { Handle = input };
    DataHnd hOutput = new DataHnd { Handle = output };
    
    // 使用类型安全读写（对标 Pascal 的原子读写）
    if (API_ReadInt32(hInput, out int a) && API_ReadInt32(hInput, out int b))
    {
        int sum = a + b;
        API_WriteInt32(hOutput, sum);
    }
}

// 在 Main 中
AppHnd app = API_Create_APPHnd("Calc", "Calculator");
APICallDelegate del = AddCallback;
GCHandle.Alloc(del);  // ⚠️ 防止 GC 回收
API_Reg_Call(app, "add", "Addition", IntPtr.Zero, del);
```

### 3. 本地调用（无需网络，用于测试）

```csharp
DataHnd param = API_Create_DataHnd("add");
API_WriteInt32(param, 5);
API_WriteInt32(param, 7);
DataHnd result = API_Local_APP_Call(app, param);
int sum = API_ReadInt32(result);
Console.WriteLine($"5 + 7 = {sum}");
API_Free_DataHnd(param);
API_Free_DataHnd(result);
```

### 4. 远程调用（跨进程/跨语言）

```csharp
API_Reset_Prepare();
API_Prepare_Client("ipc:calc_service", app);  // 连接服务
if (API_Prepare_Done() == 1)
{
    DataHnd param = API_Create_DataHnd("add");
    API_WriteInt32(param, 10);
    API_WriteInt32(param, 20);
    DataHnd result = API_Call("CalcService", param, 5000);
    int sum = API_ReadInt32(result);
    Console.WriteLine($"远程调用结果：{sum}");
    API_Free_DataHnd(param);
    API_Free_DataHnd(result);
}
```

### 5. v2.1 新增：UI 主线程同步回调（对标 Pascal 软同步）

**Pascal 开发者** 使用 `API_Reg_Sync_Call_M` + `API.Sync` 将回调安全迁移到主线程。  
**C# 开发者** 使用 `API_Reg_Call_Sync` + `ProcessSyncQueue` —— **完全相同的设计理念**：

```csharp
// 注册同步回调（回调将在主线程执行）
int r1 = API_Reg_Call_Sync(app, "add", "add(int a, int b)", IntPtr.Zero, AddCallback);

// 回调中直接操作 UI — 无需任何 Invoke 代码！
private void AddCallback(IntPtr trigger, IntPtr input, IntPtr output)
{
    DataHnd hInput = new DataHnd { Handle = input };
    DataHnd hOutput = new DataHnd { Handle = output };
    
    if (API_ReadInt32(hInput, out int a) && API_ReadInt32(hInput, out int b))
    {
        int c = a + b;
        API_WriteInt32(hOutput, c);
        // 直接更新 UI — 运行在主线程！
        this.lstLog.Items.Add($"收到加法请求: {a}+{b}={c}");
    }
}

// 主线程定期驱动同步队列（对标 Pascal API.Sync）
private void Timer_Tick(object sender, EventArgs e)
{
    API.ProcessSyncQueue();
}
```

**技术原理**：桥接委托使用 `ManualResetEvent` 阻塞等待主线程执行完毕，确保 `input`/`output` 句柄在回调期间有效，完全对标 Pascal `TSoft_Synchronize_Tool.Synchronize` 的阻塞等待语义。

### 6. 动态注销 API

```csharp
// 运行时注销 API
if (API_UnReg(app, "add") == 1)
{
    Console.WriteLine("API 'add' unregistered, broadcast in progress.");
}
```

### 7. 运行时配置

```csharp
// 动态调整配置，无需重启
API_SetOption("Wait_Connection_ReadyOk", "False");
API_SetOption("IPC_Serv_ThreadCount", "8");
```

---

## 🌍 真正的跨语言互通

| 语言 | 接入方式 | 代码量 | 同步回调支持 |
|------|---------|--------|-------------|
| **C#** | `API_HubTool.cs` | 最少 | ✅ `API_Reg_Call_Sync` |
| **Pascal** | `z_api_hubtool_import.pas` | 极简 | ✅ `API_Reg_Sync_Call_M` |
| **C/C++** | `API_HubTool.h` / `.hpp` | 极少 | ❌ (需手动调度) |
| **Python** | `ctypes.CDLL` | 10 行 | ❌ (需手动调度) |
| **Java** | JNA | 15 行 | ❌ (需手动调度) |
| **Go** | cgo | 15 行 | ❌ (需手动调度) |
| **Rust** | extern "C" | 20 行 | ❌ (需手动调度) |
| **PHP / Node.js** | ZAPI Bridge HTTP 网关 | 极少 | ✅ 通过 Bridge 回调 |

**同一个服务，可被任意语言调用，无需修改一行服务端代码。**

---

## ⚡ 技术核心——C4 分布式服务网格

API Hub 底层是久经考验的 **C4 服务网格**，提供：

- **自动服务发现**：无需配置 IP 列表，服务上线即注册。
- **智能负载均衡**：请求自动路由到负载最低的实例。
- **透明容错**：断线自动重连，业务代码无感知。
- **NAT 穿透**：跨公网、跨云、跨机房开箱即用。
- **IPC 零拷贝通道**：同机延迟 < 1ms，吞吐 10,000+ 请求/秒。
- **动态 API 注销**：运行时移除 API，约 3 秒广播传播，支持热卸载。
- **运行时配置**：动态调整认证密码、等待连接、IPC 线程池等。

---

## 📊 性能数据（实测）

| 场景 | 延迟 | 吞吐量 |
|------|------|--------|
| 本地 IPC（同机） | **< 1 ms** | **10,000+ 次/秒** |
| 本地 TCP 回环 | ~2–5 ms | ~3,000 次/秒 |
| 跨机房 TCP | 网络延迟决定 | ~1,000 次/秒 |

### 为什么这么快？

- **零拷贝**：`API_GetBuffer()` 返回直接指针，无二次复制。
- **无锁数据结构**：底层使用原子操作和自旋锁。
- **异步线程池**：回调在后台执行，主循环永不阻塞。
- **自动压缩**：大数据传输自动压缩，节省带宽。

---

## 🔒 线程安全与回调上下文（关键）

> **所有 API 函数都是完全线程安全的。**  
> 您可以在成千上万个线程中同时调用 `API_Call`，无需加锁。

但**回调函数（`APICallDelegate` / `APINotifyDelegate`）的执行上下文取决于注册方式**：

### 异步注册（`API_Reg_Call`）
- 回调在 **C 线程池** 中执行。
- ❌ **禁止**调用 `API_Call` 或 `API_Notify`（可能死锁）。
- ❌ **禁止**长时间阻塞。
- ❌ **禁止**直接访问 UI 控件。

### 同步注册（`API_Reg_Call_Sync`）
- 回调在 **主线程** 中执行（对标 Pascal `API_Reg_Sync_Call_M`）。
- ✅ 可直接操作 UI 控件。
- ⚠️ 会增加主线程负担，不适合高吞吐场景。
- **必须定期调用 `ProcessSyncQueue` 驱动队列**。

```csharp
// ❌ 错误：在异步回调中调用远程 API
private static void BadCallback(IntPtr trigger, IntPtr input, IntPtr output)
{
    DataHnd result = API_Call("OtherApp", input, 5000);  // 死锁风险！
}

// ✅ 正确：将请求放入队列，由专用线程处理
private static void GoodCallback(IntPtr trigger, IntPtr input, IntPtr output)
{
    WorkQueue.Enqueue(input);  // 快速返回
}
```

---

## 🎯 应用场景——无限可能

### 🎮 游戏开发
- **Unity/C# 做客户端逻辑**，**C++ 做服务器战斗引擎**。两者通过 API Hub 直接通信，无需额外的网络层。

### 🏭 工业自动化
- 将 **Delphi 编写的二十年老系统** 通过 API Hub 暴露给现代 **C#/Python/Go/PHP/Node.js 微服务**，实现渐进式现代化。

### 🤖 AI / 数据科学
- **Python 训练模型**，**C# 调用模型进行推理**，两端通过 IPC 实现微秒级延迟。

### ☁️ 微服务架构
- 替代 gRPC / REST，**减少 80% 的样板代码**。内置服务发现和负载均衡，无需 Consul / Eureka。

### 🔧 桌面应用插件系统
- 主程序用 **C#/WPF**，插件可用 **Python、C++、JavaScript、PHP** 等任意语言编写，动态加载。

### 🔄 热更新（v2.0）
- 用 `API_UnReg` 注销旧 API，重新注册新 API，**实现不停机更新**。

---

## ⚖️ 为什么选择 API Hub？

| 特性 | API Hub v2.1 | gRPC | REST | ZeroMQ |
|------|---------|------|------|--------|
| **多语言 C ABI** | ✅ | ❌ (需 stub) | ❌ | ✅ |
| **无需 IDL/代码生成** | ✅ | ❌ | ❌ | ❌ |
| **自动服务发现** | ✅ | ❌ | ❌ | ❌ |
| **内置负载均衡** | ✅ | ❌ | ❌ | ❌ |
| **NAT 穿透** | ✅ | ❌ | ❌ | ❌ |
| **自动重连** | ✅ | ❌ | ❌ | ❌ |
| **IPC（<1ms）** | ✅ | ❌ | ❌ | ✅ |
| **零拷贝** | ✅ | ❌ | ❌ | ❌ |
| **动态注销 API** | ✅ | ❌ | ❌ | ❌ |
| **运行时配置** | ✅ | ❌ | ❌ | ❌ |
| **UI 主线程同步回调** | ✅ | ❌ | ❌ | ❌ |
| **学习曲线** | **极低** | 高 | 中 | 中 |

---

## 📦 快速开始（5 分钟）

1. **克隆仓库**，将 `API_HubTool.cs` 添加到您的 C# 项目。
2. **编译**（.NET Framework 4.6+ / .NET Core 2.0+ / .NET 5+）。
3. **复制动态库**到输出目录：
   - Windows: `z_api_hub64.dll` 或 `z_api_hub32.dll`
   - Linux: `libz_api_hub.so`
   - macOS: `libz_api_hub.dylib`
4. **运行示例**：
   - `HelloWorld.cs` – 本地调用入门
   - `Service.cs` + `Client1.cs` / `Client2.cs` – 多客户端交互
   - `CrossNodeUI/MainForm.cs` – UI 同步回调演示
   - `FuncService.cs` + `FuncClient.cs` – 13 个 API 并发性能测试
   - `ComprehensiveDemo.cs` – 综合业务模拟

**您不需要写任何网络代码！** 所有底层通信由框架自动处理。

---

## 🧩 完整的 C# 示例库

我们提供了丰富的示例，覆盖从入门到高级的所有场景：

| 示例 | 说明 | 对标 Pascal |
|------|------|-------------|
| `HelloWorld.cs` | 本地调用，无网络，验证基本流程 | `HelloWorld` |
| `Service.cs` | 注册 11 个 API，通过 IPC 暴露 | `Service` |
| `Client1.cs` / `Client2.cs` | 注册自己的 API，调用 Service 和对方 | `Client1` / `Client2` |
| `CrossNodeUI` | UI 同步回调演示（WinForms） | `cross_node_ui` |
| `CrossService/Node/Call` | 跨语言负载均衡演示 | `cross_demo` |
| `FuncService.cs` | 13 个 API（含 SHA3-256），支持 IPC 和 TCP | `zAPIBenchServer` |
| `FuncClient.cs` | 真正并发压测，展示线程安全 | `zAPIBenchClient` |
| `ComprehensiveDemo.cs` | 模拟用户/订单/文件/统计业务 | — |

所有示例均包含**详细中文注释**，让您轻松上手。

---

## 📚 文档与资源

- [C# 绑定文件](API_HubTool.cs)（含完整注释）
- [C# 完整使用指南](API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [Pascal 完整指南](../pascal/API%20Hub%20Tool%20for%20Pascal.md) —— 理解原始设计
- [Cross Demo 全语言实战手册](../🚀%20Cross%20Demo%20全语言实战手册.md)
- [📖 ZAPI Bridge 完整使用手册](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)

---

## 📬 联系 & 社区

### 👨‍💻 作者

**（QQ：600585）**  
项目发起人 & 核心开发者。欢迎技术交流、问题反馈。

---

## 📄 许可证

**MIT License** —— 商业、开源、个人项目均可自由使用。

---

## ⭐ 给个 Star 吧

如果 API Hub 解决了你的问题，请给我们一个 Star。  
这能帮助更多开发者发现这个工具，让跨语言分布式开发变得简单。

---

**一个 .cs 文件，让 C# 拥抱多语言生态。**  
**一行代码，连接全世界。**

## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](../C++/API%20Hub%20Tool%20C++%20使用指南.md)
- [API Hub Tool C 语言使用指南](../C++/API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](../Py/从零到一，掌握多语言互调.md)
- [API Hub for Go 从零到一掌握多语言互调](../Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)
- [zAPI Rust 使用指南](../rust/zAPI%20Rust%20使用指南.md)
- [API Hub Java 使用指南](../java/API%20Hub%20Java%20使用指南.md)
- [API Hub Tool for Pascal](../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../node/Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](../Py/web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](../Py/web/js_api.py%20使用指南.md)
- [📖 ZAPI Bridge 完整使用手册](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)
