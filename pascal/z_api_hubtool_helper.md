# z_api_hubtool_helper.pas 使用指南

**版本：** 2.5.0  
**适用编译器：** Free Pascal 3.0+ / Delphi XE+  
**依赖：** `z_api_hubtool_import.pas` 和 C4 动态库（`z_api_hub64.dll` / `libz_api_hub.so` / `libz_api_hub.dylib`）

---

## 📖 概述

`z_api_hubtool_helper.pas` 是 API Hub Tool 的 **Pascal RAII 封装单元**，在底层的 `z_api_hubtool_import.pas`（C 绑定）之上提供了一套 **面向对象、自动资源管理** 的高级接口。

- **RAII 自动释放**：`TDataHandle` 和 `TAppHandle` 在构造时创建底层句柄，析构时自动释放，杜绝内存泄漏。
- **无异常设计**：所有方法静默失败（失败返回 0/空/False），无需 `try..except`，适合高频调用。
- **线程安全**：`TDataHandle` 内部加锁，所有方法可并发调用（同一句柄写操作串行化）。
- **链式调用**：所有 `WriteXXX` 方法返回 `Self`，支持连续写入。
- **类型安全读写**：内置小端序整数、IEEE 浮点、UTF‑8 字符串的读写，并遵循跨语言字符串协议（UTF‑8 + #0 终止）。
- **对象方法回调支持**：可直接注册 Pascal 对象方法（`of object`）作为远程 API，无需手写 `cdecl` 桥接。
- **同步回调（软同步）**：提供 `RegisterCallSync` / `RegisterNotifySync`，将回调排队到主线程，便于安全访问 UI（需定期调用 `API.Sync`）。
- **动态注销**：`TAppHandle.Unregister` 支持运行时移除 API，触发网络广播。
- **运行时配置**：`API.SetOption` 动态调整认证密码、部署模式、IPC 线程池等。

本单元适用于 **生产级 Pascal 项目**，无论是编写跨语言服务端、客户端，还是进行本地测试，都能显著简化代码并提升可靠性。

---

## 🧠 核心概念速览

| 概念 | 说明 | 对应 Pascal 类型 |
|------|------|------------------|
| **数据句柄** | 二进制缓冲区，包含 API 名称和载荷数据 | `API.TDataHandle` |
| **应用句柄** | 逻辑应用，可注册多个 API，网络唯一名称 | `API.TAppHandle` |
| **回调函数** | 处理远程请求的业务函数，`cdecl` 或对象方法 | `TAPI_Call` / `TAPI_Call_M` 等 |
| **Call（同步调用）** | 请求‑响应模式，等待结果 | `API.CallApp` / `TAppHandle.LocalCall` |
| **Notify（单向通知）** | 发送后立即返回，不等待响应 | `API.NotifyApp` / `TAppHandle.LocalNotify` |
| **动态注销** | 运行时移除已注册的 API，广播变更 | `TAppHandle.Unregister` |
| **软同步队列** | 将回调任务排队到主线程的机制 | `API.Sync` |

---

## 🔧 环境准备与安装

### 第一步：获取动态库

从发布包中下载对应平台的动态库，放置到可执行文件目录或系统 `PATH` 中：

| 平台 | 核心库 | IPC 依赖库 |
|------|--------|------------|
| Windows 64‑bit | `z_api_hub64.dll` | `z_ipc_64.dll` |
| Windows 32‑bit | `z_api_hub32.dll` | `z_ipc_32.dll` |
| Linux / BSD | `libz_api_hub.so` | `libz_ipc.so` |
| macOS | `libz_api_hub.dylib` | `libz_ipc.dylib` |

> `z_api_hubtool_import.pas` 使用 `external` 声明，库会在首次调用时自动加载，无需手动 `LoadLibrary`。

### 第二步：引用单元

```pascal
uses
  z_api_hubtool_import,   // 底层 C 绑定（必需）
  z_api_hubtool_helper;   // RAII 封装（推荐）
```

**编译器要求**：
- Free Pascal：需 `{$mode delphi}` 和 `{$modeswitch advancedrecords}`（单元内已处理）。
- Delphi：直接支持。

---

## 🚀 快速入门（5 分钟）

### 服务端（暴露加法 API）

```pascal
program QuickServer;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  z_api_hubtool_helper,
  z_api_hubtool_import;

// 加法回调（cdecl，在 C 线程池执行）
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
  App := TAppHandle.Create('CalcService', 'Calculator Demo');
  if not App.RegisterCall('add', 'a + b', nil, @AddCallback) then
    Halt(1);

  ResetPrepare;
  PrepareService('ipc:calc_service', 'ipc:calc_service');
  PrepareClient('ipc:calc_service', App);
  if not PrepareDone then Halt(1);

  Writeln('Service running. Press Enter to exit.');
  Readln;

  ExitMainThread;
  Shutdown;
  App.Free; // 显式释放（析构也会自动释放，但显式更清晰）
end.
```

### 客户端（调用加法）

```pascal
program QuickClient;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  z_api_hubtool_helper;

var
  Data, Res: TDataHandle;
  Sum: Integer;
begin
  ResetPrepare;
  PrepareClient('ipc:calc_service', nil);
  if not PrepareDone then Halt(1);

  Data := TDataHandle.Create('add');
  Data.WriteInt32(10).WriteInt32(20);   // 链式写入

  Res := CallApp('CalcService', Data, 3000);
  Data.Free; // 或使用 try..finally

  if Res.GetSize = 0 then
    Writeln('Timeout or error')
  else if Res.ReadInt32(Sum) then
    Writeln(Format('10 + 20 = %d', [Sum]));

  Res.Free;
  ExitMainThread;
  Shutdown;
end.
```

---

## 📚 `API.TDataHandle` 完整参考

### 构造与析构

| 构造 / 析构 | 说明 |
|-------------|------|
| `constructor Create(const APIName: string);` | 创建新句柄，API 名称自动 UTF‑8 编码。 |
| `constructor Create(AHandle: TDataHnd; Owned: Boolean = True);` | 包装已有句柄。若 `Owned=True`，析构时释放；否则只借用。 |
| `destructor Destroy; override;` | 自动释放（若 `Owned`）。 |

**示例**：
```pascal
var
  H: TDataHandle;
begin
  H := TDataHandle.Create('my_api'); // 自动创建
  // ... 使用 H ...
  H.Free; // 显式释放
end;

// 借用回调中的 Input 句柄（不释放）
procedure MyCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
var
  InHnd: TDataHandle;
begin
  InHnd := TDataHandle.Create(TDataHnd(Input), False); // Owned=False
  // ... 只读操作 ...
end;
```

### 原始字节读写

| 方法 | 说明 |
|------|------|
| `function WriteBuffer(const Buffer; Size: Int64): Int64;` | 写入 `Size` 字节，返回实际写入数。缓冲区自动扩容，位置后移。 |
| `function ReadBuffer(var Buffer; Size: Int64): Int64;` | 读取 `Size` 字节，返回实际读取数，位置后移。 |

### 类型安全写入（链式，返回 `Self`）

| 方法 | 写入内容 |
|------|----------|
| `WriteInt8(Value: Int8): TDataHandle;` | 8 位有符号整数 |
| `WriteUInt8(Value: UInt8): TDataHandle;` | 8 位无符号整数 |
| `WriteInt16(Value: Int16): TDataHandle;` | 16 位有符号整数（小端） |
| `WriteUInt16(Value: UInt16): TDataHandle;` | 16 位无符号整数（小端） |
| `WriteInt32(Value: Int32): TDataHandle;` | 32 位有符号整数（小端） |
| `WriteUInt32(Value: UInt32): TDataHandle;` | 32 位无符号整数（小端） |
| `WriteInt64(Value: Int64): TDataHandle;` | 64 位有符号整数（小端） |
| `WriteUInt64(Value: UInt64): TDataHandle;` | 64 位无符号整数（小端） |
| `WriteSingle(Value: Single): TDataHandle;` | 32 位浮点数（IEEE 754） |
| `WriteDouble(Value: Double): TDataHandle;` | 64 位浮点数（IEEE 754） |
| `WriteStringNullTerminated(const Value: string): TDataHandle;` | **写入 UTF‑8 字符串并追加 `#0` 终止符**（跨语言标准）。 |
| `procedure WriteString(const Value: string); deprecated;` | 已弃用，请使用 `WriteStringNullTerminated`。 |

**注意**：所有写入失败时静默忽略（仍返回 `Self`），调用者无法获知是否成功。若需确认，可使用底层的 `WriteBuffer` 并检查返回值。

### 类型安全读取（`out` 版本，返回 `Boolean`）

| 方法 | 读取内容 | 成功返回 `True`，失败返回 `False`（Value 不变） |
|------|----------|----------------------------------------------|
| `ReadInt8(var Value: Int8): Boolean;` | 8 位有符号整数 | |
| `ReadUInt8(var Value: UInt8): Boolean;` | 8 位无符号整数 | |
| `ReadInt16(var Value: Int16): Boolean;` | 16 位有符号整数 | |
| `ReadUInt16(var Value: UInt16): Boolean;` | 16 位无符号整数 | |
| `ReadInt32(var Value: Int32): Boolean;` | 32 位有符号整数 | |
| `ReadUInt32(var Value: UInt32): Boolean;` | 32 位无符号整数 | |
| `ReadInt64(var Value: Int64): Boolean;` | 64 位有符号整数 | |
| `ReadUInt64(var Value: UInt64): Boolean;` | 64 位无符号整数 | |
| `ReadSingle(var Value: Single): Boolean;` | 32 位浮点数 | |
| `ReadDouble(var Value: Double): Boolean;` | 64 位浮点数 | |

### 类型安全读取（直接返回版本）

| 方法 | 返回值 | 失败返回 |
|------|--------|----------|
| `ReadInt8: Int8;` | 8 位有符号整数 | 0 |
| `ReadUInt8: UInt8;` | 8 位无符号整数 | 0 |
| `ReadInt16: Int16;` | 16 位有符号整数 | 0 |
| `ReadUInt16: UInt16;` | 16 位无符号整数 | 0 |
| `ReadInt32: Int32;` | 32 位有符号整数 | 0 |
| `ReadUInt32: UInt32;` | 32 位无符号整数 | 0 |
| `ReadInt64: Int64;` | 64 位有符号整数 | 0 |
| `ReadUInt64: UInt64;` | 64 位无符号整数 | 0 |
| `ReadSingle: Single;` | 32 位浮点数 | 0.0 |
| `ReadDouble: Double;` | 64 位浮点数 | 0.0 |
| `ReadStringNullTerminated: string;` | UTF‑8 字符串（扫描直到 `#0`） | `''` |

**注意**：直接返回版本无法区分“读取成功但值为 0”和“读取失败”，建议在关键逻辑中使用 `out` 版本。

### 位置与大小

| 方法 | 说明 |
|------|------|
| `function GetPos: Int64;` | 返回当前读写位置（字节偏移）。 |
| `procedure SetPos(Pos_: Int64);` | 设置位置，若超出大小则扩展缓冲区并填充 0。 |
| `function GetSize: Int64;` | 返回缓冲区总大小。 |
| `procedure SetSize(Size_: Int64);` | 调整大小（截断或扩展）。 |
| `property Pos: Int64 read GetPos write SetPos;` | 位置属性。 |
| `property Size: Int64 read GetSize write SetSize;` | 大小属性。 |

### 零拷贝访问

| 方法 | 说明 |
|------|------|
| `function GetBufferEx(out Size: Int64): Pointer;` | 返回内部缓冲区指针和当前大小。**不要释放指针**，且确保句柄有效期间不重新分配大小。 |

### 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `Handle` | `TDataHnd` | 原始 C 句柄（只读）。 |

---

## 📚 `API.TAppHandle` 完整参考

### 构造与析构

| 方法 | 说明 |
|------|------|
| `constructor Create(const AppName, Desc: string);` | 创建应用句柄，名称自动 UTF‑8。 |
| `destructor Destroy; override;` | 自动释放句柄。 |

### 注册 API（`cdecl` 函数指针）

| 方法 | 说明 |
|------|------|
| `function RegisterCall(const APIName, Desc: string; Trigger: Pointer; OnCall: TAPI_Call): Boolean;` | 注册请求‑响应 API。返回 `True` 成功，`False` 名称重复。 |
| `function RegisterNotify(const APIName, Desc: string; Trigger: Pointer; OnNotify: TAPI_Notify): Boolean;` | 注册单向通知 API。 |

**示例**：
```pascal
function MyAdd(Trigger: Pointer; Input, Output: TDataHnd); cdecl;
begin ... end;

App.RegisterCall('add', 'Addition', nil, @MyAdd);
```

### 注册 API（对象方法，`of object`）

| 方法 | 说明 |
|------|------|
| `function RegisterCall(const APIName, Desc: string; OnCall: TAPI_Call_M): Boolean;` | 注册对象方法 `Call`（非同步，在 C 线程池执行）。 |
| `function RegisterCallSync(const APIName, Desc: string; OnCall: TAPI_Call_M): Boolean;` | 注册对象方法 `Call`（同步到主线程，需 `API.Sync`）。 |
| `function RegisterNotify(const APIName, Desc: string; OnNotify: TAPI_Notify_M): Boolean;` | 注册对象方法 `Notify`（非同步）。 |
| `function RegisterNotifySync(const APIName, Desc: string; OnNotify: TAPI_Notify_M): Boolean;` | 注册对象方法 `Notify`（同步到主线程）。 |

其中 `TAPI_Call_M = procedure(Input: TDataHnd; Output: TDataHnd) of object;`，`TAPI_Notify_M = procedure(Input: TDataHnd) of object;`。

**示例**：
```pascal
type
  TMyClass = class
    procedure MyAdd(Input: TDataHnd; Output: TDataHnd);
  end;

var
  Obj: TMyClass;
  App: TAppHandle;
begin
  Obj := TMyClass.Create;
  App := TAppHandle.Create('MyApp', '');
  // 非同步版本（C 线程池直接调用）
  App.RegisterCall('add', 'Addition', Obj.MyAdd);
  // 同步版本（排队到主线程，需调用 API.Sync）
  App.RegisterCallSync('add_sync', 'Addition Synced', Obj.MyAdd);
  // ...
end;
```

**注意事项**：
- **非同步版本**（不带 `Sync`）：回调在 C 线程池执行，**不能**阻塞，但可以调用 `API.CallApp`（注意防止无限递归）。
- **同步版本**（带 `Sync`）：通过软同步队列排队到主线程，必须**定期调用 `API.Sync`**（如定时器或主循环）以执行队列任务。适用于需要访问 UI 的场景，但会增大主线程负担，不宜高频调用。

### 动态注销

| 方法 | 说明 |
|------|------|
| `function Unregister(const APIName: string): Boolean;` | 注销已注册的 API。本地立即生效，网络广播约 3 秒传播。返回 `True` 成功。 |

**示例**：
```pascal
if App.Unregister('add') then
  Writeln('API removed, broadcast in progress');
```

### 本地调用（不经过网络）

| 方法 | 说明 |
|------|------|
| `function LocalCall(Param: TDataHandle): TDataHandle;` | 本地同步执行 `Call`，返回结果句柄（调用者需释放）。 |
| `procedure LocalNotify(Param: TDataHandle);` | 本地发送通知，无返回。 |

### 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `Handle` | `TAppHnd` | 原始 C 句柄。 |
| `Name` | `string` | 应用名称。 |

---

## 🌐 全局 `API` 静态方法

`API` 类提供静态方法管理网络和全局操作，所有方法均为 `class`。

| 方法 | 说明 |
|------|------|
| `class procedure ResetPrepare;` | 清空所有已准备的服务/客户端配置。 |
| `class function PrepareService(const ListeningAddr, PhysicsAddr: string): Integer; overload;` | 添加服务监听器（IPC 或 TCP）。返回内部标签（可忽略）。 |
| `class function PrepareService(const ListeningAddr, PhysicsAddr: string; App: TAppHandle): Integer; overload;` | 同上，并自动准备客户端连接（传入应用句柄）。 |
| `class function PrepareClient(const PhysicsAddr: string; App: TAppHandle): Integer;` | 添加客户端连接。若 `App` 非 `nil`，则暴露该应用；若 `nil` 则纯消费。 |
| `class function PrepareDone: Boolean;` | 启动网络框架，阻塞直到就绪。成功返回 `True`。 |
| `class procedure ExitMainThread;` | 停止内部事件循环（网络处理）。 |
| `class function CallApp(const AppName: string; Param: TDataHandle; TimeoutMs: UInt64): TDataHandle;` | 远程同步调用，返回结果句柄（调用者必须释放）。超时返回 `Size=0` 的句柄。 |
| `class procedure NotifyApp(const AppName: string; Param: TDataHandle);` | 发送单向通知，立即返回。 |
| `class procedure SetOption(const Option, Value: string);` | 动态调整全局配置（见下文）。 |
| `class function Sync: Integer;` | 处理主线程软同步队列，返回处理的任务数（需定期调用）。 |
| `class procedure Shutdown;` | 完全关闭框架，释放资源。 |

**示例**：
```pascal
API.ResetPrepare;
API.PrepareService('ipc:my_service', 'ipc:my_service');
API.PrepareClient('ipc:my_service', App);
if API.PrepareDone then ...
```

---

## ⚙️ 运行时配置（`API.SetOption`）

`SetOption` 用于动态调整框架行为，无需修改 `.ini` 文件或重启应用。

| 选项键（主名） | 别名 | 值类型 | 说明 |
|---------------|------|--------|------|
| `password` | `passwd` | 字符串 | C4 P2PVM 认证令牌（新建连接生效，服务端/客户端必须匹配）。 |
| `Quiet` | — | 布尔 | 静默模式（`True` 抑制日志）。 |
| `External_Conf_Auto_Save` | `Conf_Auto_Save` | 布尔 | 退出时自动保存配置到 `.ini`（默认 `True`）。 |
| `Wait_Connection_ReadyOk` | `Wait_API_Prepare_Done`, `WaitConnect`, `Wait_Ready`, `WaitReady` | 布尔 | `PrepareDone` 是否等待客户端就绪。`False` 适合弹性部署。 |
| `Wait_Connection_Timeout` | `Wait_TimeOut`, `WaitTimeOut` | 整数（毫秒） | 最大等待时间，默认 30000。 |
| `ShowThreadID` | `ShowThread`, `Show_Thread` | 布尔 | 状态日志是否显示线程 ID。 |
| `ConsoleOutput` | `Console_Output` | 布尔 | 是否输出控制台日志。 |
| `IPC_Serv_ThreadCount` | `IPC_ThreadCount`, `IPC_Server_ThreadCount` | 整数 | IPC 服务线程池大小，默认 4。 |
| `IPC_Serv_MaxQueueLength` | `IPC_MaxQueueLength`, `IPC_Server_MaxQueueLength` | 整数 | IPC 消息队列最大长度，默认 4096。 |
| `IPC_Serv_MaxMsgSize` | `IPC_MaxMsgSize`, `IPC_Server_MaxMsgSize` | 整数（字节） | IPC 单条消息最大大小，默认 32768。 |

**注意事项**：
- 未知选项静默忽略。
- 布尔值接受 `True/False`、`1/0`、`Yes/No`。
- `Wait_Connection_*` 和 `password` 需在 `PrepareDone` 前设置。
- 无返回值，调用者需确保值合法。

---

## 🧩 `API__` 底层静态映射

`API__` 类直接映射 `z_api_hubtool_import` 中的所有 **`external` 函数**（函数名相同），**不带任何 RAII 或类型安全**。此类的存在是为了满足高级用户绕过封装、直接调用底层 C API 的需求。常规开发应使用 `API` 容器类（`TDataHandle`、`TAppHandle` 等）。

**示例**：
```pascal
var
  App: TAppHnd;
begin
  App := API__.API_Create_APPHnd2('MyApp', '');
  API__.API_Reg_Call2(App, 'add', 'Addition', nil, @MyAdd);
  API__.API_Free_APPHnd(App);
end;
```

---

## ⚠️ 关键安全规则与线程模型

### 1. 回调执行上下文

所有回调（无论 `cdecl` 函数指针还是对象方法）**默认在 C4 线程池中执行**（非主线程）。这意味着：

- **非同步注册**（`RegisterCall` / `RegisterNotify` 不带 `Sync`）：回调在 C 线程池运行，可以调用 `API.CallApp` / `API.NotifyApp`（不会死锁），但**不可阻塞**（`Sleep`、等待锁、大量循环）。
- **同步注册**（`RegisterCallSync` / `RegisterNotifySync`）：回调通过软同步队列排队到主线程，**必须定期调用 `API.Sync`**（如定时器）以执行队列任务，否则回调永不触发。

**无论哪种方式，都禁止直接访问 UI**（同步版本可以，因为已在主线程执行，但需注意主线程负担）。

### 2. 句柄生命周期

- 每个 `TDataHandle` 和 `TAppHandle` 必须在作用域结束前调用 `Free`（或依赖析构，但显式更安全）。
- `API.CallApp` 返回的句柄**必须释放**，即使 `GetSize = 0`。
- 回调中的 `Input` / `Output` 句柄由框架管理，**不要释放**。

### 3. 线程安全

- `TDataHandle` 内部加锁，可安全并发读写（写操作需串行化）。
- `TAppHandle` 无额外锁（底层已线程安全）。
- 全局函数（`API.PrepareDone` 等）均线程安全。

---

## 🧪 完整测试套件

项目提供的 `fpc_tester_for_zAPI.lpr` 覆盖了本单元的所有功能，包括：
- 基础读写（所有类型、链式调用）
- 本地调用和通知
- 远程 IPC 通信
- 并发（10 线程 × 100 调用）
- 性能（1000 次顺序调用）
- 资源泄漏（10000 个句柄）
- 重复注册检测
- UTF‑8 国际化（中文/Emoji）

建议在首次使用时运行该测试，验证环境是否正常。

---

## ❓ 常见问题（FAQ）

**Q1: 如何传递复杂结构体？**  
A: 使用 `WriteBuffer` 直接写入记录的二进制内存，或序列化为 JSON 后用 `WriteStringNullTerminated` 传递。接收方按相同格式读取。

**Q2: 为什么回调没有被调用？**  
A: 检查：
- 应用名和 API 名大小写是否一致。
- `PrepareDone` 是否成功。
- 客户端是否成功连接（查看控制台日志）。
- 回调函数是否正确声明为 `cdecl`（对函数指针）或正确注册（对对象方法）。

**Q3: 在回调中调用 `CallApp` 导致程序挂起？**  
A: 旧版文档曾误称会死锁，实际上**不会死锁**，但若无限递归调用则导致死循环。请确保回调中的 `CallApp` 不会再次触发同一回调。

**Q4: 同步回调不执行？**  
A: 主线程需定期调用 `API.Sync`（例如在 `TTimer.OnTimer` 或主循环中）。

**Q5: 如何处理超时？**  
A: `CallApp` 超时参数单位为毫秒，超时返回 `Size=0` 的句柄。可重试或记录错误，避免使用 `0`（无限等待）。

**Q6: 同一进程可运行多个应用吗？**  
A: 可以。创建多个 `TAppHandle` 实例，注册不同 API，分别准备客户端即可。

**Q7: 动态注销后，正在进行的调用会怎样？**  
A: 正在执行的回调正常完成，新请求会在广播传播后收到“未找到”错误。

---

## 📄 许可证

MIT License —— 自由使用、修改、分发，含商业用途。

---

## 🧭 进一步学习

- [底层 `import` 完整指南（`z_api_hubtool_import`）](./API%20Hub%20Tool%20for%20Pascal.md)
- [C++ RAII 包装概念](../C++/API_HubTool.hpp)
- [压测服务器与客户端示例](./zAPIBenchServer.lpr)

---

**开始使用 zAPI 吧！让您的 Pascal 代码融入多语言分布式世界。** 🚀