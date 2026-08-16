# z_api_hubtool_helper.pas 使用指南

**版本：** 2.0  
**适用编译器：** Free Pascal 3.0+ / Delphi XE+  
**依赖：** `z_api_hubtool_import.pas` 和 C4 动态库（`z_api_hub64.dll` / `libz_api_hub.so` / `z_api_hub.dylib`）  

---

## 📖 概述

`z_api_hubtool_helper.pas` 是 **API Hub Tool** 的 Pascal 语言 **RAII 包装单元**，它基于底层的 `z_api_hubtool_import.pas` 提供了一套 **现代、安全、易用** 的面向对象接口。  
你不再需要手动管理句柄的生命周期（`API_Create_DataHnd` / `API_Free_DataHnd`），也不需要担心内存泄漏——**析构函数会帮你自动释放所有资源**。

### 主要特性

- **RAII 自动资源管理**：`TDataHandle` 和 `TAppHandle` 在构造时创建句柄，析构时自动释放，杜绝内存泄漏。
- **方法链式调用**：所有 `WriteXXX` 方法返回 `Self`，支持连续写入（如 `Data.WriteInt32(5).WriteInt32(7)`）。
- **类型安全读写**：提供 `WriteInt32`、`ReadString`、`WriteDouble` 等类型化方法，自动处理小端序和 UTF‑8 编码。
- **完整的网络支持**：封装了服务端/客户端准备、同步调用（`CallApp`）和单向通知（`NotifyApp`）。
- **零拷贝访问**：通过 `GetBuffer` 直接获取内部指针，适合高性能场景。
- **完全线程安全**：所有方法均可从多线程并发调用，回调在后台线程池执行。
- **动态 API 注销**：`TAppHandle.Unregister` 方法支持运行时移除 API，自动广播至所有对等节点。
- **运行时配置**：全局 `SetOption` 函数支持动态调整认证密码、等待连接、IPC 线程池等参数。

---

## 🧠 核心概念速览

| 概念 | 说明 | Pascal 类型 |
|------|------|-------------|
| **数据句柄** | 一个二进制缓冲区，包含 **API 名称** 和 **载荷数据**。用于输入参数和输出结果。 | `TDataHandle` |
| **应用句柄** | 一个逻辑应用，可以注册多个 API，在网络中具有唯一名称。 | `TAppHandle` |
| **回调函数** | 实现业务逻辑的 C 风格函数（`cdecl`），在后台线程池中执行。 | `TAPI_Call` / `TAPI_Notify` |
| **同步调用（Call）** | 请求‑响应模式，调用方阻塞等待结果。 | `CallApp` / `TAppHandle.LocalCall` |
| **单向通知（Notify）** | 发送后立即返回，不等待响应。 | `NotifyApp` / `TAppHandle.LocalNotify` |
| **动态注销（Unregister）** | 运行时移除已注册的 API，触发网络广播。 | `TAppHandle.Unregister` |
| **运行时配置（SetOption）** | 动态调整全局参数（密码、超时、IPC 等）。 | `SetOption` |

---

## 🔧 环境准备与安装

### 第一步：获取动态库

从项目发布包中下载对应平台的动态库，放置在可执行文件目录或系统 `PATH` 中：

| 平台 | 核心库 | IPC 依赖库 |
|------|--------|-----------|
| Windows 64‑bit | `z_api_hub64.dll` | `z_ipc_64.dll` |
| Windows 32‑bit | `z_api_hub32.dll` | `z_ipc_32.dll` |
| Linux / BSD | `libz_api_hub.so` | `libz_ipc.so` |
| macOS | `z_api_hub.dylib` | `libz_ipc.dylib` |

> **提示**：`z_api_hubtool_import.pas` 会自动加载库，你无需调用任何 `LoadLibrary`。

### 第二步：将单元添加到项目

在你的 Pascal 源代码中引用两个单元：

```pascal
uses
  z_api_hubtool_import,   // 底层 C 绑定
  z_api_hubtool_helper;   // RAII 封装（推荐）
```

**编译器要求**：
- **Free Pascal**：启用 `{$mode delphi}` 和 `{$modeswitch advancedrecords}`（单元内已处理）。
- **Delphi**：直接支持，无需额外设置。

---

## 🚀 快速入门（5 分钟）

### 服务端（暴露一个加法 API）

```pascal
program CalcServer;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  z_api_hubtool_helper,
  z_api_hubtool_import;

// 加法回调（cdecl，在后台线程执行）
procedure AddCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
var
  A, B, Sum: Integer;
begin
  if API_ReadBuffer(TDataHnd(Input), @A, SizeOf(A)) <> SizeOf(A) then Exit;
  if API_ReadBuffer(TDataHnd(Input), @B, SizeOf(B)) <> SizeOf(B) then Exit;
  Sum := A + B;
  API_WriteBuffer(TDataHnd(Output), @Sum, SizeOf(Sum));
end;

var
  App: TAppHandle;
begin
  // 1. 创建应用（RAII，自动释放）
  App := TAppHandle.Create('CalcService', 'Calculator Demo');

  // 2. 注册 API
  if not App.RegisterCall('add', 'a + b', nil, @AddCallback) then
  begin
    Writeln('注册失败');
    Halt(1);
  end;

  // 3. 准备网络（IPC 模式）
  ResetPrepare;
  PrepareService('ipc:calc_service', 'ipc:calc_service');
  PrepareClient('ipc:calc_service', App);

  if not PrepareDone then
  begin
    Writeln('网络启动失败');
    Halt(1);
  end;

  Writeln('服务已启动，按 Enter 退出...');
  Readln;

  // 4. 清理（RAII 会自动释放 App，但我们手动调用网络停止）
  ExitMainThread;
  Shutdown;
  App.Free;  // 非必须，但显式释放更清晰
end.
```

### 客户端（调用加法）

```pascal
program CalcClient;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  z_api_hubtool_helper;

var
  Data, Res: TDataHandle;
  Sum: Integer;
begin
  // 1. 连接到服务（纯消费端，不暴露 API）
  ResetPrepare;
  PrepareClient('ipc:calc_service', nil);

  if not PrepareDone then
  begin
    Writeln('连接失败');
    Halt(1);
  end;

  // 2. 构造请求（RAII 自动释放）
  Data := TDataHandle.Create('add');
  Data.WriteInt32(10).WriteInt32(20);   // 链式写入

  // 3. 远程调用（超时 3000ms）
  Res := CallApp('CalcService', Data, 3000);
  try
    if Res.GetSize = 0 then
      Writeln('调用超时或失败')
    else if Res.ReadInt32(Sum) then
      Writeln(Format('10 + 20 = %d', [Sum]))
    else
      Writeln('读取结果失败');
  finally
    Res.Free;
  end;

  // 4. 清理
  ExitMainThread;
  Shutdown;
end.
```

---

## 📚 TDataHandle 完整 API 参考

### 构造函数

| 方法 | 说明 |
|------|------|
| `constructor Create(const APIName: string);` | 创建新的数据句柄，API 名称会转换为 UTF‑8。 |
| `constructor Create(AHandle: TDataHnd; Owned: Boolean = True);` | 包装已有句柄（通常用于回调内部）。 |

### 链式写入方法（均返回 `Self`）

| 方法 | 写入内容 |
|------|----------|
| `WriteInt8(Value: Int8)` | 8 位有符号整数 |
| `WriteUInt8(Value: UInt8)` | 8 位无符号整数 |
| `WriteInt16(Value: Int16)` | 16 位有符号整数 |
| `WriteUInt16(Value: UInt16)` | 16 位无符号整数 |
| `WriteInt32(Value: Int32)` | 32 位有符号整数 |
| `WriteUInt32(Value: UInt32)` | 32 位无符号整数 |
| `WriteInt64(Value: Int64)` | 64 位有符号整数 |
| `WriteUInt64(Value: UInt64)` | 64 位无符号整数 |
| `WriteSingle(Value: Single)` | 32 位浮点数 |
| `WriteDouble(Value: Double)` | 64 位浮点数 |
| `WriteString(const Value: string)` | UTF‑8 字符串（**长度前缀 + 字节**，由接收方按相同协议读取） |

### 读取方法（返回 `Boolean` 表示成功）

| 方法 | 读取内容 |
|------|----------|
| `ReadInt8(out Value: Int8): Boolean` | 8 位有符号整数 |
| `ReadUInt8(out Value: UInt8): Boolean` | 8 位无符号整数 |
| `ReadInt16(out Value: Int16): Boolean` | 16 位有符号整数 |
| `ReadUInt16(out Value: UInt16): Boolean` | 16 位无符号整数 |
| `ReadInt32(out Value: Int32): Boolean` | 32 位有符号整数 |
| `ReadUInt32(out Value: UInt32): Boolean` | 32 位无符号整数 |
| `ReadInt64(out Value: Int64): Boolean` | 64 位有符号整数 |
| `ReadUInt64(out Value: UInt64): Boolean` | 64 位无符号整数 |
| `ReadSingle(out Value: Single): Boolean` | 32 位浮点数 |
| `ReadDouble(out Value: Double): Boolean` | 64 位浮点数 |
| `ReadString(out Value: string): Boolean` | UTF‑8 字符串（长度前缀） |

### 位置与大小管理

| 方法 | 说明 |
|------|------|
| `function GetPos: Int64;` | 返回当前读写位置（字节偏移） |
| `procedure SetPos(Pos_: Int64);` | 设置读写位置（若超出大小，自动扩展缓冲区） |
| `function GetSize: Int64;` | 返回缓冲区总大小 |
| `procedure SetSize(Size_: Int64);` | 调整缓冲区大小（截断或扩展） |

### 零拷贝访问

| 方法 | 说明 |
|------|------|
| `function GetBuffer: Pointer;` | 返回内部缓冲区的直接指针（只读/可写，但不要越界或释放） |

### 原始字节读写

| 方法 | 说明 |
|------|------|
| `function WriteBuffer(const Buffer; Size: Int64): Int64;` | 写入任意二进制数据 |
| `function ReadBuffer(var Buffer; Size: Int64): Int64;` | 读取任意二进制数据 |

### 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `Handle` | `TDataHnd` | 原始 C 句柄（只读） |

---

## 📚 TAppHandle 完整 API 参考

### 构造函数

| 方法 | 说明 |
|------|------|
| `constructor Create(const AppName, Desc: string);` | 创建应用句柄，名称和描述自动转为 UTF‑8。 |

### 注册 API

| 方法 | 说明 |
|------|------|
| `function RegisterCall(const APIName, Desc: string; Trigger: Pointer; OnCall: TAPI_Call): Boolean;` | 注册请求‑响应 API。返回 `True` 成功，`False` 表示名称重复。 |
| `function RegisterNotify(const APIName, Desc: string; Trigger: Pointer; OnNotify: TAPI_Notify): Boolean;` | 注册单向通知 API。 |

### 动态注销 API（新增）

| 方法 | 说明 |
|------|------|
| `function Unregister(const APIName: string): Boolean;` | 从应用中注销一个已注册的 API。**立即从本地移除**，并**触发网络广播**（约 3 秒传播）。 |

**使用场景**：
- **热卸载插件**：动态库插件可先注销自身 API，再安全卸载。
- **临时维护模式**：临时下线某些功能 API，无需重启整个应用。
- **权限动态调整**：根据用户角色或运行时条件，移除敏感 API 暴露。

**示例**：
```pascal
var
  App: TAppHandle;
begin
  App := TAppHandle.Create('MyService', '');
  App.RegisterCall('add', 'Addition', nil, @AddCallback);

  // ... 运行一段时间后，决定下线 'add' API
  if App.Unregister('add') then
    Writeln('API "add" unregistered, broadcast in progress')
  else
    Writeln('API "add" not found');

  App.Free;
end;
```

**注意事项**：
- 注销后，**正在执行中的回调不会被打断**（它们会正常完成）。
- 新到达的远程请求会在广播传播前或传播后分别被路由到旧状态或新状态。
- 如需立即阻止新请求，可在注销前设置一个应用级别的"维护中"标志。

### 本地调用（不经过网络）

| 方法 | 说明 |
|------|------|
| `function LocalCall(Param: TDataHandle): TDataHandle;` | 同步执行本地 Call API，返回结果句柄（调用者负责释放）。 |
| `procedure LocalNotify(Param: TDataHandle);` | 发送本地通知，无返回。 |

### 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `Handle` | `TAppHnd` | 原始 C 句柄 |
| `Name` | `string` | 应用名称 |

---

## 🌐 全局网络函数

这些函数对应底层的 C4 准备和通信操作。

| 函数 | 说明 |
|------|------|
| `procedure ResetPrepare;` | 清空所有已准备的服务/客户端配置。 |
| `function PrepareService(const ListeningAddr, PhysicsAddr: string): Integer;` | 添加一个服务监听（如 `ipc:test` 或 `0.0.0.0:9898`）。返回内部标签。 |
| `function PrepareClient(const PhysicsAddr: string; App: TAppHandle): Integer;` | 添加一个客户端连接。若传入 `App`，则暴露该应用。 |
| `function PrepareDone: Boolean;` | 启动网络框架，阻塞直到就绪。成功返回 `True`。 |
| `procedure ExitMainThread;` | 停止内部事件循环。 |
| `function CallApp(const AppName: string; Param: TDataHandle; TimeoutMs: UInt64): TDataHandle;` | 远程同步调用，返回结果句柄（调用者释放）。超时返回 `Size=0` 的句柄。 |
| `procedure NotifyApp(const AppName: string; Param: TDataHandle);` | 发送单向通知，立即返回。 |
| `procedure SetOption(const Option, Value: string);` | **运行时动态调整全局配置**（密码、超时、IPC 等）。详见下文。 |
| `procedure Shutdown;` | 完全关闭框架，释放所有资源。 |

---

## ⚙️ 运行时配置（SetOption）

`SetOption` 函数允许您在运行时动态调整 API Hub 框架的全局配置选项，无需修改 `.ini` 文件或重启应用。

### 函数签名

```pascal
procedure SetOption(const Option, Value: string);
```

### 支持的选项

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

### 示例

```pascal
// 设置认证密码
SetOption('password', 'my_secret_token');

// 服务端不等待客户端就绪（适合大规模部署）
SetOption('Wait_Connection_ReadyOk', 'False');

// 提高 IPC 并发能力
SetOption('IPC_Serv_ThreadCount', '8');
```

---

## ⚠️ 关键安全规则（必读）

### 1. 回调执行上下文

**所有回调函数（`TAPI_Call` / `TAPI_Notify`）都在底层 C4 线程池中执行**，而非主线程。这意味着：

- ❌ **禁止**在回调中调用 `CallApp` 或 `NotifyApp` —— 会导致死锁。
- ❌ **禁止**长时间阻塞（如 `Sleep`、等待事件、密集循环）。
- ❌ **禁止**直接访问 UI 控件（需用 `TThread.Synchronize` 或消息队列）。
- ✅ 若必须执行耗时操作或远程调用，请将任务**入队**到工作线程，回调立即返回。

**正确示例**：

```pascal
procedure MyCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
begin
  // 只读取必要数据，然后快速返回
  TThread.CreateAnonymousThread(
    procedure
    begin
      // 在这里可以安全地调用 CallApp
      Res := CallApp('OtherApp', Data, 5000);
    end
  ).Start;
end;
```

### 2. 句柄生命周期

- **每个 `TDataHandle` 和 `TAppHandle` 必须显式释放**（调用 `Free` 或使用 `try..finally`）。
- 从 `CallApp` 返回的句柄**必须释放**，即使 `GetSize = 0`。
- 在回调中传入的 `Input` 和 `Output` 句柄**不要释放**（由框架管理）。

### 3. 线程安全

- 所有 `TDataHandle` 和 `TAppHandle` 方法都是线程安全的。
- 但**同一 `TDataHandle` 的写操作（`WriteXXX`、`SetPos`、`SetSize`）必须串行化**，不同句柄可并发操作。

---

## 🧪 完整测试套件

项目提供的 `fpc_tester_for_zAPI.lpr` 覆盖了所有功能，包括：

- 基础读写（所有类型、链式调用）
- 本地调用和通知
- 远程 IPC 通信
- 并发（10 线程 × 100 调用）
- 性能（1000 次顺序调用）
- 资源泄漏（10000 个句柄分配/释放）
- 重复注册检测
- UTF‑8 国际化（中文/Emoji）

建议你在自己的环境中运行该测试，验证库是否正常工作。

---

## ❓ 常见问题（FAQ）

**Q1: 如何传递复杂结构体（记录/类）？**  
A: 你可以使用 `WriteBuffer` 直接写入记录的二进制内存，或使用 `WriteString` 序列化为 JSON。接收方按相同格式读取。

**Q2: 为什么我的回调没有被调用？**  
A: 检查以下几点：
- 应用名和 API 名的大小写是否完全一致（`CalcService` ≠ `calcservice`）。
- 客户端是否成功连接（查看控制台输出，库会打印详细日志）。
- `PrepareDone` 是否返回 `True`。
- 回调函数是否声明为 `cdecl`。

**Q3: 在回调中调用 `CallApp` 导致程序挂起？**  
A: 这是典型死锁问题。回调中禁止调用 `CallApp`/`NotifyApp`，请将远程调用移到独立线程。

**Q4: 如何处理超时？**  
A: `CallApp` 的超时参数单位为毫秒。超时后返回句柄的 `GetSize` 为 0，你可以选择重试或记录错误。不建议使用 0（无限等待）。

**Q5: 如何调试网络问题？**  
A: 库会在控制台输出详细的启动和运行时日志（包括连接状态、注册信息、错误原因）。你可以在 `<可执行文件名>.api-tool.ini` 配置文件中调整日志行为（例如关闭控制台输出或调整详细程度）。

**Q6: 我可以在同一进程运行多个应用吗？**  
A: 可以。创建多个 `TAppHandle` 实例，注册不同的 API 集，分别准备客户端即可。

**Q7: 动态注销 API 后，正在进行的调用会怎样？**  
A: 正在执行中的回调不会被打断，它们会正常完成。新到达的请求会在广播传播后收到"未找到"错误。

---

## 📄 许可证

MIT License —— 自由使用、修改、分发，甚至用于商业项目。

---

## 🧭 进一步学习

- [Pascal 完整指南（底层 import）](./API%20Hub%20Tool%20for%20Pascal.md) — 底层 C API 参考
- [C++ RAII 包装](../C++/API_HubTool.hpp) — 概念相通
- [压测服务器与客户端](./zAPIBenchServer.lpr) — 20 个 API 的实战示例

---

**开始使用 zAPI 吧！让您的 Pascal 代码融入多语言分布式世界。** 🚀

## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](../C++/API%20Hub%20Tool%20C++%20使用指南.md)
- [API Hub Tool C 语言使用指南](../C++/API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](../Py/从零到一，掌握多语言互调.md)
- [API Hub for Go 从零到一掌握多语言互调](../Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)
- [zAPI Rust 使用指南](../rust/zAPI%20Rust%20使用指南.md)
- [API Hub Java 使用指南](../java/API%20Hub%20Java%20使用指南.md)
- [API Hub Tool for C# — 完整使用指南](../C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../node/Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](../Py/web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](../Py/web/js_api.py%20使用指南.md)
