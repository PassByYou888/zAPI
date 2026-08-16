# API Hub Tool for C# — 完整使用指南

> **让您的 C# 应用轻松融入分布式 API 生态，以最轻量的方式实现跨语言、跨进程、跨机器的函数调用。**  
> 基于 C4 分布式服务网格与 Z 系列基础库，提供企业级服务发现、负载均衡与容错能力。

---

## 📖 目录

- [1. 概述](#1-概述)
- [2. 环境准备与库加载](#2-环境准备与库加载)
- [3. 核心概念速览](#3-核心概念速览)
- [4. 数据句柄（DataHnd）操作](#4-数据句柄datahnd操作)
- [5. 应用句柄（AppHnd）与 API 注册](#5-应用句柄apphnd与-api-注册)
  - [5.1 API_Create_APPHnd](#51-api_create_apphnd)
  - [5.2 API_Free_APPHnd](#52-api_free_apphnd)
  - [5.3 API_Reg_Call](#53-api_reg_call)
  - [5.4 API_Reg_Notify](#54-api_reg_notify)
  - [5.5 API_UnReg — 动态注销 API（新增）](#55-api_unreg--动态注销-api新增)
  - [5.6 API_Local_APP_Call](#56-api_local_app_call)
  - [5.7 API_Local_APP_Notify](#57-api_local_app_notify)
- [6. 本地调用（无网络）](#6-本地调用无网络)
- [7. 网络层准备与启动](#7-网络层准备与启动)
- [8. 远程调用与通知](#8-远程调用与通知)
  - [8.1 API_Call](#81-api_call)
  - [8.2 API_Notify](#82-api_notify)
  - [8.3 API_SetOption — 运行时动态调整全局配置（新增）](#83-api_setoption--运行时动态调整全局配置新增)
- [9. 线程安全与回调上下文（重要）](#9-线程安全与回调上下文重要)
- [10. 高级主题](#10-高级主题)
- [11. 调试与错误处理](#11-调试与错误处理)
- [12. 完整示例：服务端 + 客户端](#12-完整示例服务端--客户端)
- [13. 常见问题 FAQ](#13-常见问题-faq)
- [14. 总结与资源](#14-总结与资源)

---

## 1. 概述

`API_HubTool.cs` 是 API Hub 的 **C# P/Invoke 绑定文件**。它通过自定义 DllImport 解析器自动加载底层 C 动态库（`z_api_hub64.dll` / `z_api_hub.so` / `z_api_hub.dylib`），让任何 .NET 程序（.NET Framework 4.6+、.NET Core 2.0+、.NET 5+）能够：

- 将普通 C# 方法暴露为**远程可调用 API**（请求-响应或单向通知）
- 调用其他语言（C/C++、Python、Java、Go、Rust、Pascal、PHP、Node.js 等）注册的远程服务
- 在同一台机器上通过 **IPC**（进程间通信）或跨机器通过 **TCP** 进行通信

底层基于 **C4 分布式服务网格**，自动处理服务发现、负载均衡、断线重连、NAT 穿透等复杂问题。

---

## 2. 环境准备与库加载

### 2.1 动态库放置

| 操作系统 | 动态库名称 | 放置位置 |
|----------|-----------|----------|
| Windows 64-bit | `z_api_hub64.dll` | 可执行文件目录或 `PATH` |
| Windows 32-bit | `z_api_hub32.dll` | 可执行文件目录或 `PATH` |
| Linux | `libz_api_hub.so` | `LD_LIBRARY_PATH` 或 `/usr/lib` |
| macOS | `z_api_hub.dylib` | `DYLD_LIBRARY_PATH` 或 `/usr/local/lib` |

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

如果库缺失，会抛出 `DllNotFoundException`。建议在程序入口处进行异常处理。

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

**重要约束**（详见第 9 节）：
- 回调中**禁止**调用 `API_Call` 或 `API_Notify`（可能死锁）。
- 回调不应长时间阻塞；耗时操作应异步处理。
- 回调中的异常会被库捕获并记录，但不会返回给调用方；建议在回调内部自行处理异常。

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

在传输时，载荷会与 API 名称一起打包（序列化格式由内部实现处理），但作为用户，您只需使用提供的读写函数即可，无需关心内部细节。

---

### 4.1 `API_Create_DataHnd`

```csharp
DataHnd data = API.API_Create_DataHnd("add");
```

**功能**：创建一个新的数据句柄，并设置其关联的 API 名称。初始载荷为空（大小 0）。

**参数**：
- `apiName`：目标 API 的名称（以空字符结尾的 UTF-8 字符串）。该名称将用于路由。

**返回值**：新句柄。正常情况下永远返回非 `null`（但可通过 `IsValid` 判断）。

**线程安全**：✅

**注意**：句柄必须通过 `API_Free_DataHnd` 释放，否则内存泄漏。

---

### 4.2 `API_Free_DataHnd`

```csharp
API.API_Free_DataHnd(data);
```

**功能**：销毁数据句柄，释放所有关联内存。句柄变为无效。

**线程安全**：✅ 是，但句柄不能被并发使用。

---

### 4.3 `API_GetBuffer`

```csharp
IntPtr raw = API.API_GetBuffer(data);
```

**功能**：返回指向句柄内部缓冲区的直接指针（零拷贝访问）。指针在句柄被释放或缓冲区调整大小之前有效。**不要释放此指针**。

**线程安全**：✅ 读安全，但若同时有写入操作则不安全。

---

### 4.4 `API_WriteBuffer`

```csharp
byte[] payload = BitConverter.GetBytes(123);
long written = API.API_WriteBuffer(data, payload, payload.Length);
```

**功能**：从当前读写位置开始，向句柄缓冲区写入数据。缓冲区自动扩容。

**线程安全**：⚠️ 同一句柄上的写操作应串行化；不同句柄可并发写入。

---

### 4.5 `API_ReadBuffer`

```csharp
byte[] buffer = new byte[4];
long read = API.API_ReadBuffer(data, buffer, 4);
```

**功能**：从当前读写位置读取数据到调用者缓冲区，位置随读取字节数后移。

**线程安全**：⚠️ 同一句柄上不应同时读写；但多个线程同时读取是安全的。

---

### 4.6 位置与大小管理

```csharp
long pos = API.API_GetPos(data);   // 当前偏移
API.API_SetPos(data, 0);           // 重置到开头
long size = API.API_GetSize(data); // 总大小
API.API_SetSize(data, 1024);       // 调整大小
```

---

### 4.7 便捷辅助方法

`API` 类提供了几个辅助方法，简化常见操作：

```csharp
byte[] allData = API.ReadAllBytes(data);  // 读取所有数据到字节数组
API.WriteBytes(data, byteArray);          // 写入字节数组
string str = API.ReadString(data);        // 读取 null 结尾的 UTF-8 字符串
API.WriteString(data, "Hello");           // 写入 UTF-8 字符串（自动附加 null 终止符）
```

---

## 5. 应用句柄（AppHnd）与 API 注册

### 5.1 `API_Create_APPHnd`

```csharp
AppHnd app = API.API_Create_APPHnd("Calculator", "My Calc Service");
```

**功能**：创建一个应用上下文。应用是 API 的容器，在网络中具有唯一名称。

**参数**：
- `appName`：应用名称（区分大小写，网络唯一，UTF-8）。
- `desc`：描述（可为空字符串，UTF-8）。

**返回值**：新应用句柄，正常情况下非 `null`。

**线程安全**：✅

---

### 5.2 `API_Free_APPHnd`

```csharp
API.API_Free_APPHnd(app);
```

**功能**：销毁应用句柄，释放所有已注册的 API 及相关资源。

**线程安全**：✅ 但确保没有其他线程正在使用该句柄。

---

### 5.3 `API_Reg_Call`

```csharp
private static void AddCallback(IntPtr trigger, IntPtr input, IntPtr output)
{
    DataHnd hInput = new DataHnd { Handle = input };
    DataHnd hOutput = new DataHnd { Handle = output };
    int a = API.ReadInt(hInput);
    int b = API.ReadInt(hInput);
    int sum = a + b;
    API.WriteInt(hOutput, sum);
}

// 注册
APICallDelegate del = AddCallback;
// ⚠️ 重要：委托必须保持存活，防止 GC 回收
// 生产环境建议将委托存储在静态字段或类实例字段中
GCHandle.Alloc(del);  // 防止 GC 回收
API.API_Reg_Call(app, "add", "Addition", IntPtr.Zero, del);
```

> **⚠️ 委托生命周期管理**：`GCHandle.Alloc(del)` 会防止委托被垃圾回收，但如果不调用 `GCHandle.Free()`，会导致内存泄漏。生产环境中，建议将委托存储在静态字段中，或在适当的时候调用 `GCHandle.Free()`。为简化示例，本指南未展示释放逻辑。

**功能**：在应用中注册一个请求-响应（Call）API。当远程或本地调用此 API 时，`OnCall` 回调会被执行。

**参数**：
- `appHnd`：应用句柄。
- `apiName`：API 名称（应用内唯一，区分大小写，UTF-8）。
- `desc`：描述（可选，UTF-8）。
- `trigger`：用户数据指针，回调时会原样传回。
- `onCall`：回调委托（必须 `Cdecl`）。

**返回值**：`1` 成功，`0` 失败（名称已存在）。

**线程安全**：✅

---

### 5.4 `API_Reg_Notify`

注册一个单向通知（Notify）API。回调无输出。

```csharp
private static void LogCallback(IntPtr trigger, IntPtr input)
{
    string msg = API.ReadString(new DataHnd { Handle = input });
    Console.WriteLine($"[Log] {msg}");
}

APINotifyDelegate notifyDel = LogCallback;
GCHandle.Alloc(notifyDel);
API.API_Reg_Notify(app, "log", "Logger", IntPtr.Zero, notifyDel);
```

---

### 5.5 `API_UnReg` — 动态注销 API（新增）

```csharp
if (API.API_UnReg(app, "add") == 1)
{
    Console.WriteLine("API 'add' unregistered, broadcast in progress.");
}
```

**功能**：从应用中注销一个先前注册的 API。该 API 会**立即从本地注册表中移除**，并**触发网络广播**通知所有已连接的对等节点。

**参数**：
- `appHnd`：应用句柄。
- `apiName`：要注销的 API 名称（**UTF-8** 编码）。

**返回值**：`1` 成功（API 存在并被移除），`0` 失败（API 名称不存在）。

**关键行为**：
- **本地立即生效**：API 从本地注册表中同步删除。
- **网络异步广播**：删除操作触发广播，传播时间约 3 秒（取决于网络延迟）。
- **传播延迟窗口**：在广播传播期间，远程调用可能仍然到达并失败。

**使用场景**：
- **热卸载插件**：动态库插件可先注销自身 API，再安全卸载。
- **临时维护模式**：临时下线某些功能 API，无需重启整个应用。
- **权限动态调整**：根据用户角色或运行时条件，移除敏感 API 暴露。

---

### 5.6 `API_Local_APP_Call`

在**本地**同步执行一个 Call API，绕过网络。适用于单元测试或内部调用。

```csharp
DataHnd param = API.API_Create_DataHnd("add");
API.WriteInt(param, 5);
API.WriteInt(param, 7);
DataHnd result = API.API_Local_APP_Call(app, param);
int sum = API.ReadInt(result);
API.API_Free_DataHnd(param);
API.API_Free_DataHnd(result);
```

---

### 5.7 `API_Local_APP_Notify`

在本地发送一个通知（无返回）。

```csharp
DataHnd param = API.API_Create_DataHnd("log");
API.WriteString(param, "Hello from local");
API.API_Local_APP_Notify(app, param);
API.API_Free_DataHnd(param);
```

---

## 6. 本地调用（无网络）

在开始网络编程之前，强烈建议先用本地调用验证您的 API 注册和回调逻辑。以下示例完全无需网络，仅在一个进程中测试：

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

此测试不涉及任何网络，可用于快速验证回调逻辑。

---

## 7. 网络层准备与启动

### 7.1 地址匹配规则

- **服务端**：`listeningAddr` 是**本地绑定**地址（如 `0.0.0.0` 表示监听所有接口）。`physicsAddr` 是**对外公布**的地址，客户端将使用此地址连接。
- **客户端**：`physicsAddr` 必须与服务端的 `physicsAddr` **完全一致**（包括端口）。对于 IPC，双方必须使用相同的服务名（如 `ipc:my_service`）。

### 7.2 `API_Reset_Prepare`

清除所有之前准备的网络服务/客户端配置。在重新配置前调用。

```csharp
API.API_Reset_Prepare();
```

### 7.3 `API_Prepare_Service`

准备一个服务端监听器。可多次调用以启动多个服务。

```csharp
API.API_Prepare_Service("0.0.0.0", "127.0.0.1:9898");   // TCP 服务
API.API_Prepare_Service("ipc:my_service", "ipc:my_service"); // IPC 服务
```

### 7.4 `API_Prepare_Client`

准备一个客户端连接。若提供了 `appHnd`，该应用会在连接成功后自动注册到服务端。

```csharp
API.API_Prepare_Client("127.0.0.1:9898", app);  // 注册应用
API.API_Prepare_Client("ipc:my_service", AppHnd.Null); // 纯消费
```

**注意**：客户端会在断线后自动重连，并重新注册应用。

### 7.5 `API_Prepare_Done`

启动 C4 网络框架，阻塞直到所有准备的服务/客户端初始化完成。之后才能进行远程调用。

```csharp
if (API.API_Prepare_Done() == 1)
{
    // 框架已启动
}
else
{
    // 失败，查看控制台输出获取详细错误信息
    Console.WriteLine("Prepare failed. Check console output for details.");
}
```

> **调试说明**：库会将详细的运行日志（包括连接状态、注册信息、错误原因）自动输出到控制台。你可以在 `<可执行文件名>.api-tool.ini` 配置文件中调整日志行为。

**重要**：
- 只能调用一次，除非中间调用了 `API_Exit_MainThread` 或 `API_shutdown` 重置状态。
- 重复调用而未重置会导致未定义行为。
- 该函数会启动一个模拟主线程，持续运行网络事件循环。

### 7.6 `API_Exit_MainThread`

通知模拟主线程退出，停止网络事件循环。资源不会自动释放，需继续调用 `API_shutdown`。

```csharp
API.API_Exit_MainThread();
```

---

## 8. 远程调用与通知

### 8.1 `API_Call`

同步调用远程应用 `appName` 的 API。阻塞直到收到响应或超时。

```csharp
DataHnd param = API_Create_DataHnd("add");
WriteInt(param, 10);
WriteInt(param, 20);
DataHnd result = API_Call("Calculator", param, 5000);
if (result.IsValid && API_GetSize(result) >= 4)
{
    int sum = ReadInt(result);
    Console.WriteLine($"Result: {sum}");
}
API_Free_DataHnd(param);
API_Free_DataHnd(result);
```

**返回值**：**新句柄，永远非 `null`**。若调用成功，句柄大小 > 0；若超时或失败，句柄大小为 0。**调用者必须始终释放返回的句柄**（即使大小为 0）。

**注意**：
- 支持本地优化：若目标应用在同一进程内已注册，则直接本地执行，避免网络开销。
- 并发调用的执行顺序不保证（见第 9 节）。

### 8.2 `API_Notify`

发送单向通知，不等待响应。尽力送达。

```csharp
DataHnd param = API_Create_DataHnd("log");
WriteString(param, "User logged in");
API_Notify("LoggerService", param);
API_Free_DataHnd(param);
```

### 8.3 `API_SetOption` — 运行时动态调整全局配置（新增）

```csharp
// 设置认证密码
API.API_SetOption("password", "my_secret_token");

// 服务端不等待客户端就绪
API.API_SetOption("Wait_Connection_ReadyOk", "False");

// 提高 IPC 并发能力
API.API_SetOption("IPC_Serv_ThreadCount", "8");
```

**功能**：在运行时动态调整 API Hub 框架的全局配置选项。所有更改对后续操作**立即生效**（除非另有说明）。

**参数**：
- `Option`：配置键（**UTF-8** 编码，不区分大小写，支持别名）。
- `Value`：新值（**UTF-8** 编码）。对于布尔选项，接受 `"True"`/`"False"`、`"1"`/`"0"`、`"Yes"`/`"No"`。

**返回值**：无。未知选项被**静默忽略**。

#### 支持的选项

| 选项键（主名） | 别名 | 值类型 | 说明 |
|---------------|------|--------|------|
| `password` | `passwd` | 字符串 | 设置 C4 P2PVM 认证令牌。**服务端和客户端必须匹配**。 |
| `Quiet` | — | 布尔 | 启用/禁用静默模式（`True`/`False`）。 |
| `External_Conf_Auto_Save` | `Conf_Auto_Save` | 布尔 | 程序退出时自动保存配置到 `.ini` 文件（默认 `True`）。 |
| `Wait_Connection_ReadyOk` | `Wait_API_Prepare_Done`、`WaitConnect`、`Wait_Ready` | 布尔 | 控制 `PrepareDone` 是否阻塞等待所有客户端连接就绪。 |
| `Wait_Connection_Timeout` | `Wait_TimeOut` | 整数（毫秒） | 最大等待时间，默认 `30000`。 |
| `ShowThreadID` | `ShowThread`、`Show_Thread` | 布尔 | 在日志中显示线程 ID。 |
| `ConsoleOutput` | `Console_Output` | 布尔 | 启用/禁用控制台日志输出。 |
| `IPC_Serv_ThreadCount` | `IPC_ThreadCount`、`IPC_Server_ThreadCount` | 整数 | IPC 服务线程池大小，默认 `4`。 |
| `IPC_Serv_MaxQueueLength` | `IPC_MaxQueueLength` | 整数 | IPC 消息队列最大长度，默认 `4096`。 |
| `IPC_Serv_MaxMsgSize` | `IPC_MaxMsgSize` | 整数（字节） | 单条 IPC 消息最大大小，默认 `32768`。 |

---

## 9. 线程安全与回调上下文（重要）

### 9.1 导出函数线程安全

**所有导出函数都是完全线程安全的**。您可以在多个线程中同时调用 `API_Call`、`API_WriteBuffer` 等，无需外部锁。

但**同一 `DataHnd` 的写操作（`API_WriteBuffer`、`API_SetPos`、`API_SetSize`）应串行化**，避免数据竞争。不同句柄可自由并发。

### 9.2 回调执行上下文

**您的回调函数（`APICallDelegate`、`APINotifyDelegate`）是在后台线程池线程中执行的**，而不是在调用 `API_Call` 的线程。

这带来以下约束：
- ❌ **禁止**在回调中调用 `API_Call` 或 `API_Notify` —— 可能导致死锁，因为回调线程可能持有内部锁。
- ❌ **禁止**长时间阻塞（如 `Thread.Sleep`、等待事件、大量循环）。
- ❌ **禁止**直接访问 UI 组件或线程局部存储（除非通过 `Control.Invoke` 或同步机制）。
- ✅ **推荐**将耗时任务或需要远程调用的请求放入队列，由独立工作线程处理，回调快速返回。

```csharp
// ❌ 错误做法
private static void BadCallback(IntPtr trigger, IntPtr input, IntPtr output)
{
    // 死锁风险！
    DataHnd result = API_Call("OtherApp", input, 5000);
}

// ✅ 正确做法
private static void GoodCallback(IntPtr trigger, IntPtr input, IntPtr output)
{
    // 将数据放入线程安全队列，由工作线程处理
    WorkQueue.Enqueue(input);
    // 快速返回
}
```

### 9.3 执行顺序不保证

由于负载均衡，并发请求可能被路由到不同实例，**调用顺序不保证**。如果您发送 `1,2,3`，远程可能以 `2,1,3` 处理。需要顺序的业务请自行实现序列号或单线程调度。

---

## 10. 高级主题

### 10.1 并发调用

利用线程安全轻松实现高并发：

```csharp
var tasks = new List<Task>();
for (int i = 0; i < 100; i++)
{
    int a = i, b = i * 2;
    tasks.Add(Task.Run(() =>
    {
        DataHnd param = API_Create_DataHnd("add");
        WriteInt(param, a);
        WriteInt(param, b);
        DataHnd result = API_Call("ServiceApp", param, 5000);
        // 处理结果...
        API_Free_DataHnd(param);
        API_Free_DataHnd(result);
    }));
}
Task.WaitAll(tasks.ToArray());
```

### 10.2 IPC vs TCP

- **IPC**（`ipc:服务名`）：同机通信，延迟 < 1 ms，吞吐极高。适合单机微服务。
- **TCP**：跨机通信，支持 IPv4/IPv6，可配置端口。延迟取决于网络。

### 10.3 多实例部署

多个服务实例注册**相同应用名**，客户端自动负载均衡。每个实例可监听不同地址。

### 10.4 自定义序列化

由于 `DataHnd` 支持二进制数据，您可以使用任何序列化框架（如 `MessagePack`、`Protobuf`）或手动序列化结构体。

---

## 11. 调试与错误处理

### 11.1 控制台日志

库会在控制台自动输出详细的运行日志（包括连接状态、注册信息、错误原因）。你可以在 `<可执行文件名>.api-tool.ini` 配置文件中调整日志行为。

### 11.2 常见错误

| 错误信息 | 原因 | 解决方案 |
|---------|------|---------|
| `no found app("XXX") api("YYY")` | 目标应用未注册或 API 名不匹配 | 检查大小写，确认客户端已注册成功 |
| `bind address already in use` | 端口被占用 | 更换端口或结束占用进程 |
| `timeout` | 响应超时 | 增加超时值，检查网络 |
| `DllNotFoundException` | 动态库未找到 | 确保库文件在搜索路径 |

---

## 12. 完整示例：服务端 + 客户端

### 12.1 服务端（Service.cs）

```csharp
using System;
using System.Threading;
using System.Runtime.InteropServices;
using API_HubTool.Bindings;
using static API_HubTool.Bindings.API;

class Service
{
    private static volatile bool _exit = false;

    static void Main()
    {
        AppHnd app = API_Create_APPHnd("ServiceApp", "Demo Service");
        APICallDelegate addDel = AddCallback;
        GCHandle.Alloc(addDel);
        API_Reg_Call(app, "add", "Add", IntPtr.Zero, addDel);

        API_Reset_Prepare();
        API_Prepare_Service("0.0.0.0", "127.0.0.1:9898");
        API_Prepare_Service("ipc:demo", "ipc:demo");
        API_Prepare_Client("127.0.0.1:9898", app);
        API_Prepare_Client("ipc:demo", app);

        if (API_Prepare_Done() != 1)
        {
            Console.WriteLine("Start failed");
            return;
        }
        Console.WriteLine("Service running. Press Enter to exit.");
        Console.ReadLine();

        API_Exit_MainThread();
        API_Free_APPHnd(app);
        API_shutdown();
    }

    private static void AddCallback(IntPtr trigger, IntPtr input, IntPtr output)
    {
        DataHnd hIn = new DataHnd { Handle = input };
        DataHnd hOut = new DataHnd { Handle = output };
        int a = ReadInt(hIn);
        int b = ReadInt(hIn);
        WriteInt(hOut, a + b);
    }
}
```

### 12.2 客户端（Client.cs）

```csharp
using System;
using API_HubTool.Bindings;
using static API_HubTool.Bindings.API;

class Client
{
    static void Main()
    {
        API_Reset_Prepare();
        API_Prepare_Client("ipc:demo", AppHnd.Null);
        API_Prepare_Client("127.0.0.1:9898", AppHnd.Null);

        if (API_Prepare_Done() != 1)
        {
            Console.WriteLine("Connect failed");
            return;
        }

        DataHnd param = API_Create_DataHnd("add");
        WriteInt(param, 10);
        WriteInt(param, 20);
        DataHnd result = API_Call("ServiceApp", param, 5000);
        if (result.IsValid && API_GetSize(result) >= 4)
        {
            int sum = ReadInt(result);
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

## 13. 常见问题 FAQ

**Q1: 为什么我的回调没有被调用？**  
A: 检查应用名和 API 名是否完全匹配（大小写）。确认客户端已成功连接并注册（查看日志）。`API_Prepare_Done` 是否成功？

**Q2: 可以在回调中调用 `API_Call` 吗？**  
A: **不可以**。会导致死锁。请将请求放入队列，由独立线程处理。

**Q3: 多个线程同时调用 `API_Call` 安全吗？**  
A: 是的，所有导出函数都是线程安全的。但同一 `DataHnd` 的写操作需串行化。

**Q4: 如何处理超时？**  
A: `API_Call` 超时后返回的句柄大小为 0。可增加超时值或检查网络。超时值 0 表示无限等待，慎用。

**Q5: 我可以在同一进程运行多个应用吗？**  
A: 可以。创建多个 `AppHnd`，注册不同的 API 集，分别准备客户端即可。

**Q6: 如何处理大型数据？**  
A: 使用 `API_GetBuffer` 零拷贝访问，或直接操作指针。可考虑压缩（库内置支持）。

**Q7: 动态注销 API 后，正在进行的调用会怎样？**  
A: 正在执行中的回调不会被打断，它们会正常完成。新到达的请求会在广播传播后收到"未找到"错误。

---

## 14. 总结与资源

您已掌握 API Hub Tool 的 C# P/Invoke 全部核心用法。现在您可以：

- 用 C# 编写高性能服务，暴露给任何语言消费。
- 用 C# 编写客户端，调用其他语言的服务。
- 利用 IPC 实现微秒级同机通信，或通过 TCP 构建跨云分布式系统。

**进一步学习资源：**
- [API_HubTool.cs](API_HubTool.cs) —— 完整 C# 绑定（内含详尽注释）
- [C API 参考](../C++/API_HubTool.h)
- [Pascal 完整指南](../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- 示例代码：`HelloWorld.cs`、`Service.cs`、`Client1.cs`、`Client2.cs`、`ComprehensiveDemo.cs`、`FuncService.cs`、`FuncClient.cs`

---

## 📬 联系 & 社区

### 👨‍💻 作者

**（QQ：600585）**  
项目发起人 & 核心开发者。欢迎技术交流、问题反馈。

---

**从今天起，您的 C# 代码可以轻松拥抱多语言生态。**  
API Hub Tool 让语言边界消失，让分布式开发回归简单。

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
