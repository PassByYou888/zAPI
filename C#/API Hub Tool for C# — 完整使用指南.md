# API Hub Tool for C# — 完整使用指南

> **让您的 C# 应用以最轻量、最可靠的方式融入分布式 API 生态，实现跨语言、跨进程、跨机器的函数调用。**  
> 基于 C4 分布式服务网格与 Z 系列基础库，提供企业级服务发现、负载均衡与容错能力。

---

## 📖 目录

1. [概述](#1-概述)
2. [环境准备与库加载](#2-环境准备与库加载)
3. [核心概念速览](#3-核心概念速览)
4. [数据句柄（DataHnd）操作](#4-数据句柄datahnd操作)
5. [应用句柄（AppHnd）与 API 注册](#5-应用句柄apphnd与-api-注册)
   - 5.1 API_Create_APPHnd
   - 5.2 API_Free_APPHnd
   - 5.3 API_Reg_Call
   - 5.4 API_Reg_Notify
   - 5.5 API_UnReg — 动态注销 API
   - 5.6 API_Local_APP_Call
   - 5.7 API_Local_APP_Notify
6. [本地调用（无网络）](#6-本地调用无网络)
7. [网络层准备与启动](#7-网络层准备与启动)
8. [远程调用与通知](#8-远程调用与通知)
   - 8.1 API_Call
   - 8.2 API_Notify
   - 8.3 API_SetOption — 运行时动态调整全局配置
9. [UI 主线程同步回调机制（对标 Pascal 软同步）](#9-ui-主线程同步回调机制对标-pascal-软同步)
   - 9.1 问题背景与根本原因
   - 9.2 解决方案：ManualResetEvent 阻塞等待
   - 9.3 注册同步回调 API
   - 9.4 驱动同步队列
10. [线程安全与回调上下文（重要）](#10-线程安全与回调上下文重要)
11. [高级主题](#11-高级主题)
    - 11.1 跨语言负载均衡（Cross Demo）
    - 11.2 分布式计算网格（Compute Grid）
    - 11.3 序列化通信（SequenceData）
    - 11.4 并发调用与性能测试
12. [调试与错误处理](#12-调试与错误处理)
13. [完整示例：服务端 + 客户端](#13-完整示例服务端--客户端)
14. [常见问题 FAQ](#14-常见问题-faq)
15. [总结与资源](#15-总结与资源)

---

## 1. 概述

`API_HubTool.cs` 是 API Hub 的 **C# P/Invoke 绑定文件**。它通过自定义 DllImport 解析器自动加载底层 C 动态库（`z_api_hub64.dll` / `libz_api_hub.so` / `libz_api_hub.dylib`），让任何 .NET 程序（.NET Framework 4.6+、.NET Core 2.0+、.NET 5+）能够：

- 将普通 C# 方法暴露为**远程可调用 API**（请求-响应 `Call` 或单向通知 `Notify`）。
- 调用其他语言（C++、Python、Java、Go、Rust、Pascal、PHP、Node.js 等）注册的远程服务。
- 在同一台机器上通过 **IPC**（进程间通信，<1ms 延迟）或跨机器通过 **TCP** 进行通信。

**与 Pascal 绑定的对标关系**：

| 功能 | Pascal 单元 | C# 文件 |
|------|-------------|---------|
| 底层 C ABI 导入 | `z_api_hubtool_import.pas` | `API_HubTool.cs`（核心 P/Invoke） |
| RAII 高级封装 | `z_api_hubtool_helper.pas` | `API_HubTool.cs` 中的静态辅助方法 + 用户自行封装 |
| 同步回调机制 | `API_Reg_Sync_Call_M` + `API.Sync` | `API_Reg_Call_Sync` + `ProcessSyncQueue` |

底层基于 **C4 分布式服务网格**，自动处理服务发现、负载均衡、断线重连、NAT 穿透。

---

## 2. 环境准备与库加载

### 2.1 动态库放置

| 操作系统 | 核心库 | 放置位置 |
|----------|--------|----------|
| Windows 64-bit | `z_api_hub64.dll` | 可执行文件目录或 `PATH` |
| Windows 32-bit | `z_api_hub32.dll` | 可执行文件目录或 `PATH` |
| Linux | `libz_api_hub.so` | `LD_LIBRARY_PATH` 或 `/usr/lib` |
| macOS | `libz_api_hub.dylib` | `DYLD_LIBRARY_PATH` 或 `/usr/local/lib` |

**依赖库**（需与主库同目录）：
- Windows：`z_ipc_64.dll` / `z_ipc_32.dll`
- Linux：`libz_ipc.so`
- macOS：`libz_ipc.dylib`（如有）

### 2.2 库自动加载

`API_HubTool.cs` 使用 `NativeLibrary.SetDllImportResolver` 在静态构造函数中设置自定义解析器，会根据当前平台和位数自动选择正确的库文件名。**您无需手动加载库，也无需为不同平台编写条件编译。**

```csharp
// 库会在第一次调用任何 API 函数时自动加载
AppHnd app = API.API_Create_APPHnd("MyApp", "Description");
```

### 2.3 配置文件

首次运行时会生成 `<可执行文件名>.api-tool.ini`，可编辑调整超时、日志、线程池大小等参数，无需重新编译。

---

## 3. 核心概念速览

### 3.1 句柄

- **`DataHnd`**：数据句柄，封装了一个 API 名称和二进制载荷。用于输入参数和输出结果。
- **`AppHnd`**：应用句柄，代表一个逻辑应用，可注册多个 API，在网络中具有唯一名称。

### 3.2 回调约定

- **`APICallDelegate`**：请求-响应回调，必须使用 `CallingConvention.Cdecl`，接收 `trigger`（用户数据）、`input`（只读）、`output`（只写）。
- **`APINotifyDelegate`**：单向通知回调，也必须是 `Cdecl`，只接收 `trigger` 和 `input`。

**重要约束**（详见第 10 节）：
- 回调中**禁止**调用 `API_Call` 或 `API_Notify`（可能死锁）。
- 回调不应长时间阻塞；耗时操作应异步处理。
- **如需操作 UI，必须使用同步回调机制（见第 9 节）**。

### 3.3 网络地址格式

| 协议 | 格式 | 示例 | 跨机 |
|------|------|------|------|
| TCP（IPv4） | `主机:端口` | `127.0.0.1:9898` | ✅ |
| TCP（IPv6） | `[::1]:端口` 或 `::1\|端口` | `[::1]:8080` | ✅ |
| IPC | `ipc:服务名` | `ipc:calc_service` | ❌ |
| 通配符（服务端） | `0.0.0.0` | 监听所有接口 | - |

默认 TCP 端口为 `9898`，IPC 忽略端口。

---

## 4. 数据句柄（DataHnd）操作

### 📦 数据布局说明

`DataHnd` 内部同时存储了 **API 名称**和**二进制载荷**。API 名称在创建时通过 `API_Create_DataHnd(apiName)` 设置，之后**不可更改**。所有 `API_WriteBuffer`、`API_ReadBuffer` 等操作**只影响载荷部分**，不会影响 API 名称。

### 4.1 `API_Create_DataHnd`

```csharp
DataHnd data = API.API_Create_DataHnd("add");
```

**功能**：创建一个新的数据句柄，并设置其关联的 API 名称。初始载荷为空（大小 0）。

**参数**：
- `apiName`：目标 API 的名称（以空字符结尾的 UTF-8 字符串）。

**返回值**：新句柄。必须通过 `API_Free_DataHnd` 释放。

### 4.2 `API_Free_DataHnd`

```csharp
API.API_Free_DataHnd(data);
```

**功能**：销毁数据句柄，释放所有关联内存。

### 4.3 `API_WriteBuffer` / `API_ReadBuffer`

```csharp
byte[] payload = BitConverter.GetBytes(123);
long written = API.API_WriteBuffer(data, payload, payload.Length);

byte[] buffer = new byte[4];
long read = API.API_ReadBuffer(data, buffer, 4);
```

### 4.4 位置与大小管理

```csharp
long pos = API.API_GetPos(data);   // 当前偏移
API.API_SetPos(data, 0);           // 重置到开头
long size = API.API_GetSize(data); // 总大小
API.API_SetSize(data, 1024);       // 调整大小
```

### 4.5 便捷辅助方法（对标 Pascal 的原子读写）

`API` 类提供了类型安全的读写辅助，对标 Pascal 的 `API_WriteInt32` / `API_ReadInt32` 系列：

```csharp
// 写入
API.API_WriteInt32(data, 123);
API.API_WriteString(data, "Hello");

// 读取
if (API.API_ReadInt32(data, out int value)) { ... }
string str = API.API_ReadString(data);  // 自动读取到 #0 终止符
```

**⚠️ 关键**：`API_ReadString` 和 `API_WriteString` 使用 **空终止符（#0）协议**，与 Pascal 绑定完全一致，确保跨语言字符串交换正确。

---

## 5. 应用句柄（AppHnd）与 API 注册

### 5.1 `API_Create_APPHnd`

```csharp
AppHnd app = API.API_Create_APPHnd("Calculator", "My Calc Service");
```

**功能**：创建一个应用上下文。应用名称在网络中必须唯一（区分大小写）。

### 5.2 `API_Free_APPHnd`

```csharp
API.API_Free_APPHnd(app);
```

### 5.3 `API_Reg_Call`

注册请求-响应 API：

```csharp
private static void AddCallback(IntPtr trigger, IntPtr input, IntPtr output)
{
    DataHnd hInput = new DataHnd { Handle = input };
    DataHnd hOutput = new DataHnd { Handle = output };
    
    if (API.API_ReadInt32(hInput, out int a) && API.API_ReadInt32(hInput, out int b))
    {
        int sum = a + b;
        API.API_WriteInt32(hOutput, sum);
    }
}

// 注册
APICallDelegate del = AddCallback;
GCHandle.Alloc(del);  // ⚠️ 防止 GC 回收
API.API_Reg_Call(app, "add", "Addition", IntPtr.Zero, del);
```

### 5.4 `API_Reg_Notify`

注册单向通知：

```csharp
private static void LogCallback(IntPtr trigger, IntPtr input)
{
    DataHnd hInput = new DataHnd { Handle = input };
    string msg = API.API_ReadString(hInput);
    Console.WriteLine($"[Log] {msg}");
}

APINotifyDelegate notifyDel = LogCallback;
GCHandle.Alloc(notifyDel);
API.API_Reg_Notify(app, "log", "Logger", IntPtr.Zero, notifyDel);
```

### 5.5 `API_UnReg` — 动态注销 API

```csharp
if (API.API_UnReg(app, "add") == 1)
{
    Console.WriteLine("API 'add' unregistered, broadcast in progress.");
}
```

**关键行为**（与 Pascal 完全一致）：
- **本地立即生效**：API 从本地注册表中同步删除。
- **网络异步广播**：约 3 秒传播至所有对等节点。
- **正在执行中的回调不受影响**。

### 5.6 `API_Local_APP_Call` / `API_Local_APP_Notify`

```csharp
DataHnd param = API.API_Create_DataHnd("add");
API.API_WriteInt32(param, 5);
API.API_WriteInt32(param, 7);
DataHnd result = API.API_Local_APP_Call(app, param);
int sum = API.API_ReadInt32(result);
API.API_Free_DataHnd(param);
API.API_Free_DataHnd(result);
```

---

## 6. 本地调用（无网络）

本地调用完全对标 Pascal 示例中的 `API_Local_APP_Call` 用法，适用于单元测试：

```csharp
using API_HubTool.Bindings;
using static API_HubTool.Bindings.API;

private static void EchoCallback(IntPtr trigger, IntPtr input, IntPtr output)
{
    DataHnd hInput = new DataHnd { Handle = input };
    DataHnd hOutput = new DataHnd { Handle = output };
    byte[] data = ReadAllBytes(hInput);
    WriteBytes(hOutput, data);
}

static void Main()
{
    AppHnd app = API_Create_APPHnd("TestApp", "");
    APICallDelegate del = EchoCallback;
    GCHandle.Alloc(del);
    API_Reg_Call(app, "echo", "Echo", IntPtr.Zero, del);

    DataHnd param = API_Create_DataHnd("echo");
    WriteString(param, "Hello World");
    DataHnd result = API_Local_APP_Call(app, param);
    string echoed = ReadString(result);
    Console.WriteLine($"Echo: {echoed}");

    API_Free_DataHnd(param);
    API_Free_DataHnd(result);
    API_Free_APPHnd(app);
}
```

---

## 7. 网络层准备与启动

### 7.1 地址匹配规则（对标 Pascal）

- **服务端**：`listeningAddr` 是本地绑定地址，`physicsAddr` 是对外公布地址。
- **客户端**：`physicsAddr` 必须与服务端的 `physicsAddr` **完全一致**。

### 7.2 准备服务与客户端

```csharp
API.API_Reset_Prepare();
API.API_Prepare_Service("ipc:calc_service", "ipc:calc_service");  // IPC
API.API_Prepare_Service("0.0.0.0", "127.0.0.1:9898");            // TCP
API.API_Prepare_Client("ipc:calc_service", app);                 // 暴露应用
API.API_Prepare_Client("127.0.0.1:9898", AppHnd.Null);           // 纯消费
```

### 7.3 启动框架

```csharp
if (API.API_Prepare_Done() == 1)
{
    // 框架已启动，可进行远程调用
}
```

---

## 8. 远程调用与通知

### 8.1 `API_Call`

```csharp
DataHnd param = API_Create_DataHnd("add");
API_WriteInt32(param, 10);
API_WriteInt32(param, 20);
DataHnd result = API_Call("Calculator", param, 5000);
if (result.IsValid && API_GetSize(result) >= 4)
{
    int sum = API_ReadInt32(result);
    Console.WriteLine($"Result: {sum}");
}
API_Free_DataHnd(param);
API_Free_DataHnd(result);
```

### 8.2 `API_Notify`

```csharp
DataHnd param = API_Create_DataHnd("log");
API_WriteString(param, "User logged in");
API_Notify("LoggerService", param);
API_Free_DataHnd(param);
```

### 8.3 `API_SetOption` — 运行时动态调整全局配置

```csharp
API.API_SetOption("Wait_Connection_ReadyOk", "False");  // 不等待客户端就绪
API.API_SetOption("IPC_Serv_ThreadCount", "8");
```

---

## 9. UI 主线程同步回调机制（对标 Pascal 软同步）

### 9.1 问题背景与根本原因

**Pascal 绑定**提供了 `API_Reg_Sync_Call_M` + `API.Sync` 机制，使用 `TSoft_Synchronize_Tool` 将回调从 C 线程池安全地迁移到主线程执行，业务代码可直接操作 UI 控件。

**C# 绑定的原始问题**：
> 如果仅将回调入队到 `ConcurrentQueue` 即返回，底层 C 库在桥接返回后会立即释放或重用 `input`/`output` 句柄。当主线程随后执行用户回调时，访问的句柄已无效，导致 **Access Violation 崩溃**。

### 9.2 解决方案：ManualResetEvent 阻塞等待

对标 Pascal `TSoft_Synchronize_Tool.Synchronize` 的**阻塞等待语义**，C# 实现使用 `ManualResetEvent`：

```csharp
private static APICallDelegate CreateSyncCallBridge(APICallDelegate userDelegate)
{
    return (trigger, input, output) =>
    {
        using (var mre = new ManualResetEvent(false))
        {
            EnqueueSyncAction(() =>
            {
                try { userDelegate(trigger, input, output); }
                finally { mre.Set(); }
            });
            mre.WaitOne();  // 阻塞等待主线程执行完毕
        }
    };
}
```

**核心原理**：
- 桥接委托在 C 线程池触发时，将用户回调入队，然后**阻塞等待** `ManualResetEvent`。
- 主线程调用 `ProcessSyncQueue` 执行用户回调，执行完毕后 `Set` 事件。
- 桥接线程被唤醒，此时 `input`/`output` 句柄仍有效，安全返回。

### 9.3 注册同步回调 API

```csharp
// 使用同步注册 API（内部已实现阻塞等待）
int r1 = API.API_Reg_Call_Sync(app, "add", "add(int a, int b)", IntPtr.Zero, AddCallback);
int r2 = API.API_Reg_Notify_Sync(app, "log", "Logger", IntPtr.Zero, LogCallback);
```

**回调中直接操作 UI**（无需任何 `BeginInvoke`）：

```csharp
private void AddCallback(IntPtr trigger, IntPtr input, IntPtr output)
{
    DataHnd hInput = new DataHnd { Handle = input };
    DataHnd hOutput = new DataHnd { Handle = output };
    
    if (API_ReadInt32(hInput, out int a) && API_ReadInt32(hInput, out int b))
    {
        int c = a + b;
        API_WriteInt32(hOutput, c);
        // 直接操作 UI 控件 — 在主线程执行！
        this.lstLog.Items.Add($"收到加法请求: {a}+{b}={c}");
    }
}
```

### 9.4 驱动同步队列

主线程需定期调用 `ProcessSyncQueue`（对标 Pascal 的 `API.Sync`）：

```csharp
// 在定时器或 Application.Idle 中
private void TimerRefresh_Tick(object sender, EventArgs e)
{
    API.ProcessSyncQueue();  // 驱动所有同步回调
}
```

**⚠️ 性能提示**：同步回调增加了主线程负担，建议仅在操作 UI 的必要场景使用。高吞吐场景应使用异步注册（`API_Reg_Call`）。

---

## 10. 线程安全与回调上下文（重要）

### 10.1 导出函数线程安全

**所有导出函数都是完全线程安全的**。您可以在多个线程中同时调用 `API_Call`、`API_WriteBuffer` 等。

### 10.2 回调执行上下文（对标 Pascal）

- **异步注册**（`API_Reg_Call`）：回调在 **C 线程池** 中执行，**禁止**操作 UI，**禁止**调用 `API_Call`。
- **同步注册**（`API_Reg_Call_Sync`）：回调在 **主线程** 中执行，可直接操作 UI，但会阻塞后台线程。

### 10.3 执行顺序不保证

由于负载均衡，并发调用的顺序不保证（对标 Pascal）。需要顺序的业务请自行实现序列号或单线程调度。

---

## 11. 高级主题

### 11.1 跨语言负载均衡（Cross Demo） — 对标 Pascal `cross_demo`

**场景**：启动多个工作节点（`CrossNode`）注册到同一服务网格，客户端请求被 C4 网格自动均匀分发到各节点。

**C# 工作节点实现**（对标 Pascal `cross_node.lpr`）：

```csharp
class CrossNode
{
    private static void AddCallback(IntPtr trigger, IntPtr input, IntPtr output)
    {
        DataHnd hInput = new DataHnd { Handle = input };
        DataHnd hOutput = new DataHnd { Handle = output };
        if (API_ReadInt32(hInput, out int a) && API_ReadInt32(hInput, out int b))
        {
            int c = a + b;
            API_WriteInt32(hOutput, c);
            Console.WriteLine($"[Node] add({a},{b}) = {c}");
        }
    }

    static void Main()
    {
        AppHnd app = API_Create_APPHnd("demo", "C# worker node");
        API_Reg_Call(app, "add", "add(int,int)", IntPtr.Zero, AddCallback);
        
        API_SetOption("Wait_Ready", "False");
        API_Reset_Prepare();
        API_Prepare_Client("ipc:cross", app);
        API_Prepare_Done();
        
        Console.WriteLine("节点已注册，按 Enter 退出...");
        Console.ReadLine();
        API_Exit_MainThread();
        API_Free_APPHnd(app);
        API_shutdown();
    }
}
```

### 11.2 分布式计算网格（Compute Grid） — 对标 Pascal `Compute_Grid_Demo`

**场景**：计算节点注册 `exp` API 接收表达式字符串（如 `"3+4*5"`），服务端通过 Z.Expression 引擎求值。C# 可调用其他语言（Pascal）的计算节点。

**C# 客户端调用远程表达式计算**：

```csharp
static double ComputeExpression(string expr)
{
    DataHnd param = API_Create_DataHnd("exp");
    API_WriteString(param, expr);
    DataHnd result = API_Call("ComputeGrid", param, 5000);
    if (result.IsValid && API_GetSize(result) >= 8)
    {
        double value = API_ReadDouble(result);
        API_Free_DataHnd(result);
        return value;
    }
    API_Free_DataHnd(result);
    return 0.0;
}
```

### 11.3 序列化通信（SequenceData） — 对标 Pascal `SequenceData`

**场景**：通过 `Notify` 分块传输大数据（如 10MB），使用 SessionID + Index 在服务端重排乱序数据，最终聚合 MD5 验证完整性。

**C# 客户端分块发送**：

```csharp
static void SendSequenceData(byte[] data, int chunkSize = 1536)
{
    int sessionId = new Random().Next(10000);
    int totalChunks = (data.Length + chunkSize - 1) / chunkSize;
    
    for (int i = 0; i < totalChunks; i++)
    {
        int offset = i * chunkSize;
        int len = Math.Min(chunkSize, data.Length - offset);
        DataHnd param = API_Create_DataHnd("seq_data");
        API_WriteInt32(param, sessionId);
        API_WriteInt32(param, i);          // Index
        API_WriteInt32(param, totalChunks);
        API_WriteBuffer(param, data, offset, len);
        API_Notify("SequenceService", param);
        API_Free_DataHnd(param);
    }
}
```

### 11.4 并发调用与性能测试（对标 Pascal `zAPIBenchClient`）

```csharp
var tasks = new List<Task>();
for (int i = 0; i < 100; i++)
{
    tasks.Add(Task.Run(() =>
    {
        DataHnd param = API_Create_DataHnd("add");
        API_WriteInt32(param, 10);
        API_WriteInt32(param, 20);
        DataHnd result = API_Call("ServiceApp", param, 5000);
        if (result.IsValid) { int sum = API_ReadInt32(result); }
        API_Free_DataHnd(param);
        API_Free_DataHnd(result);
    }));
}
Task.WaitAll(tasks.ToArray());
```

---

## 12. 调试与错误处理

### 12.1 控制台日志

库会在控制台自动输出详细日志。可通过 `API_SetOption("ConsoleOutput", "False")` 关闭。

### 12.2 程序化日志拉取（对标 Pascal `API_Get_Status`）

```csharp
int count = API.API_Get_Status_Num();
for (int i = 0; i < count; i++)
{
    string msg = API.API_Get_Status();
    Console.WriteLine($"[库日志] {msg}");
}
```

### 12.3 常见错误

| 错误信息 | 原因 | 解决方案 |
|---------|------|---------|
| `no found app("XXX") api("YYY")` | 目标应用未注册或 API 名不匹配 | 检查大小写，使用 `API_Check_App` 前置探测 |
| `bind address already in use` | 端口被占用 | 更换端口 |
| `timeout` | 响应超时 | 增加超时值 |
| `Access Violation` | 同步回调桥接未阻塞等待 | 使用 `API_Reg_Call_Sync` 而非手动入队 |

---

## 13. 完整示例：服务端 + 客户端

### 13.1 服务端（对标 Pascal `Service` 示例）

```csharp
class Service
{
    private static void AddCallback(IntPtr trigger, IntPtr input, IntPtr output)
    {
        DataHnd hIn = new DataHnd { Handle = input };
        DataHnd hOut = new DataHnd { Handle = output };
        if (API_ReadInt32(hIn, out int a) && API_ReadInt32(hIn, out int b))
        {
            API_WriteInt32(hOut, a + b);
        }
    }

    static void Main()
    {
        AppHnd app = API_Create_APPHnd("ServiceApp", "Demo Service");
        APICallDelegate del = AddCallback;
        GCHandle.Alloc(del);
        API_Reg_Call(app, "add", "Add", IntPtr.Zero, del);

        API_Reset_Prepare();
        API_Prepare_Service("ipc:demo", "ipc:demo");
        API_Prepare_Client("ipc:demo", app);

        if (API_Prepare_Done() == 1)
        {
            Console.WriteLine("Service running. Press Enter to exit.");
            Console.ReadLine();
        }

        API_Exit_MainThread();
        API_Free_APPHnd(app);
        API_shutdown();
    }
}
```

### 13.2 客户端

```csharp
class Client
{
    static void Main()
    {
        API_Reset_Prepare();
        API_Prepare_Client("ipc:demo", AppHnd.Null);
        API_Prepare_Done();

        DataHnd param = API_Create_DataHnd("add");
        API_WriteInt32(param, 10);
        API_WriteInt32(param, 20);
        DataHnd result = API_Call("ServiceApp", param, 5000);
        if (result.IsValid && API_GetSize(result) >= 4)
        {
            int sum = API_ReadInt32(result);
            Console.WriteLine($"10 + 20 = {sum}");
        }
        API_Free_DataHnd(param);
        API_Free_DataHnd(result);

        API_Exit_MainThread();
        API_shutdown();
    }
}
```

---

## 14. 常见问题 FAQ

**Q1: 同步回调机制与 Pascal 的 `TSoft_Synchronize_Tool` 有什么区别？**  
A: 实现原理完全对标。Pascal 使用 `TSoft_Synchronize_Tool.Synchronize` 忙等待同步，C# 使用 `ManualResetEvent` 阻塞等待，两者都确保了句柄在回调期间有效。

**Q2: 为什么我的同步回调崩溃？**  
A: 请确保使用 `API_Reg_Call_Sync` 注册，并定期调用 `ProcessSyncQueue`。不要手动创建桥接委托。

**Q3: 可以在回调中调用 `API_Call` 吗？**  
A: **不可以**（与 Pascal 一致）。会导致死锁。请将远程调用放入独立任务。

**Q4: 如何调试跨语言调用问题？**  
A: 使用 `API_Get_Status` 拉取库日志，使用 `API_Check_App` 前置探测目标服务在线状态。

**Q5: 动态注销 API 后，正在进行的调用会怎样？**  
A: 正在执行中的回调不会被打断。新请求在广播传播后（约 3 秒）收到 "未找到" 错误。

---

## 15. 总结与资源

您已掌握 API Hub Tool 的 C# P/Invoke 全部核心用法。现在您可以：

- 用 C# 编写高性能服务，暴露给任何语言消费。
- 用 C# 编写客户端，调用其他语言（Pascal、C++、Python 等）的服务。
- 利用 IPC 实现微秒级同机通信，或通过 TCP 构建跨云分布式系统。
- 使用同步回调机制安全操作 UI，对标 Pascal 的 `TSoft_Synchronize_Tool`。

**进一步学习资源：**
- [API_HubTool.cs](API_HubTool.cs) —— 完整 C# 绑定（内含详尽注释）
- [Pascal 完整指南](../pascal/API%20Hub%20Tool%20for%20Pascal.md) —— 理解原始设计的参考
- [Cross Demo 全语言实战手册](../🚀%20Cross%20Demo%20全语言实战手册.md) —— 多语言负载均衡实战
- 示例代码：`HelloWorld.cs`、`Service.cs`、`Client1.cs`、`Client2.cs`、`ComprehensiveDemo.cs`、`FuncService.cs`、`FuncClient.cs`

---

**从今天起，您的 C# 代码可以轻松拥抱多语言生态，与 Pascal、C++、Python 等 10+ 种语言平等对话。**  
API Hub Tool 让语言边界消失，让分布式开发回归简单。