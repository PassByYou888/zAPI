# API Hub Tool for Pascal — 完整使用手册

> **让您的 Pascal 应用以最轻量、最可靠的方式融入分布式 API 生态，实现跨语言、跨进程、跨机器的函数调用。**  
> 基于 C4 分布式服务网格与 Z 系列基础库，提供企业级服务发现、负载均衡与容错能力。

---

## 📖 目录

1. [概述](#1-概述)
2. [核心概念](#2-核心概念)
3. [环境准备与库加载](#3-环境准备与库加载)
4. [底层 `z_api_hubtool_import` 单元详解](#4-底层-z_api_hubtool_import-单元详解)
   - 4.1 数据句柄操作
   - 4.2 应用句柄操作
   - 4.3 网络层准备与通信
   - 4.4 运行时配置与关闭
   - 4.5 同步辅助
5. [高级 RAII 封装 `z_api_hubtool_helper` 单元](#5-高级-raii-封装-z_api_hubtool_helper-单元)
   - 5.1 `API.TDataHandle` 类
   - 5.2 `API.TAppHandle` 类
   - 5.3 `API` 静态方法
   - 5.4 `API__` 底层静态映射
6. [回调函数详解与线程安全](#6-回调函数详解与线程安全)
7. [完整示例：服务端与客户端](#7-完整示例服务端与客户端)
   - 7.1 使用底层 `import` 单元
   - 7.2 使用 RAII 封装（推荐）
8. [常见问题与排错](#8-常见问题与排错)
9. [附录：函数速查表](#9-附录函数速查表)

---

## 1. 概述

`z_api_hubtool_import` 是 API Hub 的 **Pascal 核心绑定单元**，通过 `external` 动态链接加载底层 C 动态库（`z_api_hub64.dll` / `libz_api_hub.so` / `libz_api_hub.dylib`），让任意 Pascal 程序（Delphi / Free Pascal）能够：

- 将普通 Pascal 函数暴露为**远程可调用 API**（请求‑响应 `Call` 或单向通知 `Notify`）。
- 调用其他语言（C++、Python、Go、Rust、Java、C#、Node.js、PHP 等）注册的服务。
- 通过 **IPC**（进程间通信，同机）或 **TCP**（跨机）进行高性能通信。

此外，`z_api_hubtool_helper` 单元提供了 **RAII 封装**（`TDataHandle`、`TAppHandle`），自动管理句柄生命周期，并支持对象方法回调，极大简化使用。

底层基于 **C4 分布式服务网格**，自动处理服务发现、负载均衡、断线重连、NAT 穿透。

---

## 2. 核心概念

### 2.1 句柄

- **`TDataHnd`**（数据句柄）：封装 **API 名称** 和 **二进制载荷**。用于输入参数和输出结果。需显式创建和释放。
- **`TAppHnd`**（应用句柄）：代表一个逻辑应用，可注册多个 API。应用名在网络中必须唯一（区分大小写）。

### 2.2 回调约定

- **`TAPI_Call`**：请求‑响应回调，必须为 `cdecl`，接收 `Trigger`、只读 `Input`、只写 `Output`。
- **`TAPI_Notify`**：单向通知回调，`cdecl`，只接收 `Trigger` 和只读 `Input`。

**重要**：所有回调均在 **后台 C 线程池** 中执行，因此：
- **禁止**长时间阻塞（`Sleep`、等待事件、密集循环）。
- **可以**在回调内调用 `API_Call` / `API_Notify`（不会死锁），但需防止无限递归。
- **禁止**直接访问 UI（必须同步到主线程）。
- 耗时任务应异步提交到工作队列。

### 2.3 字符串编码 —— 强制 UTF‑8 + #0

所有 `PAnsiChar` 参数（API 名称、描述、网络地址、载荷中的字符串）**必须使用 UTF‑8 编码**，并以 **空字节 (#0) 结尾**。本库在 Windows 上不使用系统 ANSI 代码页，始终按 UTF‑8 处理。

### 2.4 线程安全与执行顺序

- 所有导出函数（`external`）均为**完全线程安全**，可并发调用。
- 同一 `TDataHnd` 的写操作需串行化；不同句柄可自由并发。
- 由于负载均衡，**并发调用的顺序不保证**（若需顺序，需在应用层实现序列号或单线程调度）。

---

## 3. 环境准备与库加载

### 3.1 动态库放置

从发布包获取对应平台的动态库，放至可执行文件目录或系统 `PATH`：

| 操作系统 | 核心库 | IPC 依赖库 |
|----------|--------|------------|
| Windows 64-bit | `z_api_hub64.dll` | `z_ipc_64.dll` |
| Windows 32-bit | `z_api_hub32.dll` | `z_ipc_32.dll` |
| Linux / BSD | `libz_api_hub.so` | `libz_ipc.so` |
| macOS | `libz_api_hub.dylib` | `libz_ipc.dylib`（如有） |

`z_api_hubtool_import` 使用 `external` 声明，**首次调用外部函数时自动加载**，无需手动 `LoadLibrary`。

### 3.2 配置文件

首次运行生成 `<可执行文件名>.api-tool.ini`，可调优线程池、超时、日志等参数，无需重新编译。

---

## 4. 底层 `z_api_hubtool_import` 单元详解

本节介绍 `z_api_hubtool_import` 单元中所有 **`external` 导入** 的 C 函数以及 **Pascal 辅助** 函数（不带 `external`）。  
**AI 注意**：跨语言绑定时，只需导入带 `external` 的 C 函数；Pascal 辅助函数是语法糖，其他语言应自行实现等价逻辑。

### 4.1 数据句柄操作

#### 4.1.1 创建与销毁

| 函数 | 类型 | 说明 |
|------|------|------|
| `API_Create_DataHnd(APIName: PAnsiChar): TDataHnd; cdecl; external ...` | **导入** | 创建数据句柄，绑定 API 名称。返回非 `nil` 句柄，需配合 `API_Free_DataHnd` 释放。 |
| `API_Create_DataHnd2(APIName: string): TDataHnd;` | **Pascal 辅助** | 自动 UTF‑8 转换版本，等价于 `API_Create_DataHnd(PAnsiChar(UTF8Encode(APIName)))`。 |
| `API_Free_DataHnd(Hnd: TDataHnd); cdecl; external ...` | **导入** | 销毁句柄，释放内存。传 `nil` 无操作。 |

**示例**：
```pascal
var
  d: TDataHnd;
begin
  d := API_Create_DataHnd2('my_api');
  // ... 使用 d ...
  API_Free_DataHnd(d);
end;
```

#### 4.1.2 读写原始字节

| 函数 | 类型 | 说明 |
|------|------|------|
| `API_WriteBuffer(Hnd: TDataHnd; Buff: Pointer; Size: Int64): Int64; cdecl; external ...` | **导入** | 从当前位置写入 `Size` 字节，返回实际写入数（通常等于 `Size`），缓冲区自动扩容，位置后移。 |
| `API_ReadBuffer(Hnd: TDataHnd; Buff: Pointer; Size: Int64): Int64; cdecl; external ...` | **导入** | 从当前位置读取最多 `Size` 字节到 `Buff`，返回实际读取数，位置后移。 |

**示例**：
```pascal
var
  i: Integer;
  buf: array[0..3] of Byte;
begin
  i := 12345;
  API_WriteBuffer(d, @i, SizeOf(i));   // 写入 4 字节
  API_SetPos(d, 0);
  API_ReadBuffer(d, @buf[0], 4);       // 读回
end;
```

#### 4.1.3 原子读写辅助（Pascal 实现，非 external）

这些函数基于 `API_WriteBuffer`/`API_ReadBuffer`，提供类型安全、小端序的读写，均返回 `Boolean` 表示成功。

| 写函数 | 读函数（`out` 版本） | 读函数（直接返回） | 说明 |
|--------|----------------------|-------------------|------|
| `API_WriteInt8` | `API_ReadInt8(out Value: Int8): Boolean` | `API_ReadInt8: Int8` | 8 位有符号整数 |
| `API_WriteUInt8` | `API_ReadUInt8(out Value: UInt8): Boolean` | `API_ReadUInt8: UInt8` | 8 位无符号整数 |
| `API_WriteInt16` | `API_ReadInt16(out Value: Int16): Boolean` | `API_ReadInt16: Int16` | 16 位有符号整数（小端） |
| `API_WriteUInt16` | `API_ReadUInt16(out Value: UInt16): Boolean` | `API_ReadUInt16: UInt16` | 16 位无符号整数（小端） |
| `API_WriteInt32` | `API_ReadInt32(out Value: Int32): Boolean` | `API_ReadInt32: Int32` | 32 位有符号整数（小端） |
| `API_WriteUInt32` | `API_ReadUInt32(out Value: UInt32): Boolean` | `API_ReadUInt32: UInt32` | 32 位无符号整数（小端） |
| `API_WriteInt64` | `API_ReadInt64(out Value: Int64): Boolean` | `API_ReadInt64: Int64` | 64 位有符号整数（小端） |
| `API_WriteUInt64` | `API_ReadUInt64(out Value: UInt64): Boolean` | `API_ReadUInt64: UInt64` | 64 位无符号整数（小端） |
| `API_WriteSingle` | `API_ReadSingle(out Value: Single): Boolean` | `API_ReadSingle: Single` | 32 位浮点数（IEEE 754） |
| `API_WriteDouble` | `API_ReadDouble(out Value: Double): Boolean` | `API_ReadDouble: Double` | 64 位浮点数（IEEE 754） |
| `API_WriteString` | `API_ReadString(out Value: string): Boolean` | `API_ReadString: string` | **UTF‑8 字符串 + #0 终止符**（跨语言标准） |

**注意**：
- 直接返回版本失败时返回 `0`（浮点返回 `0.0`，字符串返回 `''`）。
- `API_WriteString` 写入 UTF‑8 字节后追加一个 `#0`；`API_ReadString` 从当前位置扫描直到 `#0`，读取并解码 UTF‑8，位置移到终止符之后。

**示例**：
```pascal
var
  s: string;
begin
  API_WriteString(d, '你好');
  API_SetPos(d, 0);
  if API_ReadString(d, s) then WriteLn(s);  // 输出 "你好"
end;
```

#### 4.1.4 位置与大小

| 函数 | 类型 | 说明 |
|------|------|------|
| `API_GetPos(Hnd: TDataHnd): Int64; cdecl; external ...` | **导入** | 获取当前读写位置（字节偏移，0‑based）。 |
| `API_SetPos(Hnd: TDataHnd; Pos_: Int64); cdecl; external ...` | **导入** | 设置读写位置，若超出大小则扩展缓冲区（填充 0）。 |
| `API_GetSize(Hnd: TDataHnd): Int64; cdecl; external ...` | **导入** | 获取缓冲区总大小（字节）。 |
| `API_SetSize(Hnd: TDataHnd; Size_: Int64); cdecl; external ...` | **导入** | 设置缓冲区大小，截断或扩展（扩展部分未初始化）。 |

#### 4.1.5 零拷贝访问

| 函数 | 类型 | 说明 |
|------|------|------|
| `API_GetBuffer(Hnd: TDataHnd): Pointer; cdecl; external ...` | **导入** | 返回内部缓冲区起始指针，可读写但不得越界，不要释放。 |
| `API_GetBuffer2(Hnd: TDataHnd; Offset: NativeInt): Pointer;` | **Pascal 辅助** | 返回 `API_GetBuffer(Hnd) + Offset`，方便索引访问。 |

**注意**：指针有效期至句柄释放或调整大小。

---

### 4.2 应用句柄操作

#### 4.2.1 创建与释放

| 函数 | 类型 | 说明 |
|------|------|------|
| `API_Create_APPHnd(appName, Desc: PAnsiChar): TAppHnd; cdecl; external ...` | **导入** | 创建应用句柄，应用名必须全网唯一（区分大小写）。 |
| `API_Create_APPHnd2(appName, Desc: string): TAppHnd;` | **Pascal 辅助** | UTF‑8 自动转换版本。 |
| `API_Free_APPHnd(appHnd: TAppHnd); cdecl; external ...` | **导入** | 销毁应用句柄，注销所有注册 API，释放资源。 |

#### 4.2.2 注册 API（`cdecl` 函数指针）

| 函数 | 类型 | 说明 |
|------|------|------|
| `API_Reg_Call(appHnd: TAppHnd; APIName, Desc: PAnsiChar; Trigger: Pointer; OnCall: TAPI_Call): Integer; cdecl; external ...` | **导入** | 注册请求‑响应 API，`OnCall` 必须为 `cdecl` 函数。返回 `1` 成功，`0` 名称重复。 |
| `API_Reg_Notify(appHnd: TAppHnd; APIName, Desc: PAnsiChar; Trigger: Pointer; OnNotify: TAPI_Notify): Integer; cdecl; external ...` | **导入** | 注册单向通知 API，回调无输出。 |

辅助便捷版本（UTF‑8 自动转换）：
- `API_Reg_Call2(appHnd; APIName, Desc: string; Trigger: Pointer; OnCall: TAPI_Call): Integer;`
- `API_Reg_Notify2(...)`

**回调注意事项**：详见第 6 节。

#### 4.2.3 注册 API（对象方法版本，Pascal 辅助）

为方便 Pascal 开发者，提供了对象方法（`of object`）的注册函数，它们将对象方法适配为 `cdecl` 回调。

| 函数 | 说明 |
|------|------|
| `API_Reg_Call_M(appHnd: TAppHnd; APIName, Desc: string; OnCall: TAPI_Call_M): Integer;` | 注册对象方法 `Call`，回调直接在 C 线程池执行。 |
| `API_Reg_Sync_Call_M(appHnd; APIName, Desc: string; OnCall: TAPI_Call_M): Integer;` | 注册对象方法 `Call`，并通过 `TSoft_Synchronize_Tool` 将回调**同步到主线程**执行（需主线程定期调用 `API_Sync`）。 |
| `API_Reg_Notify_M(...)` / `API_Reg_Sync_Notify_M(...)` | 同理用于 `Notify`。 |

其中 `TAPI_Call_M = procedure(Input: TDataHnd; Output: TDataHnd) of object;`，`TAPI_Notify_M = procedure(Input: TDataHnd) of object;`。

**注意**：
- 非同步版本（不带 `Sync`）回调在 C 线程池执行，**不可阻塞**，但可调用 `API_Call`（需防死循环）。
- 同步版本（带 `Sync`）将任务排队到主线程软同步队列，需定期调用 `API_Sync` 处理，适用于必须访问 UI 的场景，但会增大主线程负担。

#### 4.2.4 动态注销 API

| 函数 | 类型 | 说明 |
|------|------|------|
| `API_UnReg(appHnd: TAppHnd; APIName: PAnsiChar): Integer; cdecl; external ...` | **导入** | 注销已注册的 API，本地立即生效，网络广播约 3 秒传播。返回 `1` 成功，`0` 不存在。 |
| `API_UnReg2(appHnd; APIName: string): Integer;` | **Pascal 辅助** | UTF‑8 自动转换版本。 |

#### 4.2.5 本地调用（不经过网络）

| 函数 | 类型 | 说明 |
|------|------|------|
| `API_Local_APP_Call(appHnd: TAppHnd; Param: TDataHnd): TDataHnd; cdecl; external ...` | **导入** | 本地同步执行 `Call`，返回结果句柄（需释放）。失败时大小 = 0。 |
| `API_Local_APP_Notify(appHnd: TAppHnd; Param: TDataHnd); cdecl; external ...` | **导入** | 本地发送通知，无返回值。 |

---

### 4.3 网络层准备与通信

#### 4.3.1 重置与准备

| 函数 | 类型 | 说明 |
|------|------|------|
| `API_Reset_Prepare(); cdecl; external ...` | **导入** | 清除所有已准备的服务/客户端配置，重新配置前调用。 |
| `API_Prepare_Service(ListeningAddr_, PhysicsAddr_: PAnsiChar): Integer; cdecl; external ...` | **导入** | 准备一个服务监听器，可多次调用。`ListeningAddr_` 为绑定地址（如 `0.0.0.0:9898` 或 `ipc:my_service`），`PhysicsAddr_` 为对外公布地址（客户端连接时使用）。返回内部标签（可忽略）。 |
| `API_Prepare_Service2(ListeningAddr_, PhysicsAddr_: string): Integer;` | **Pascal 辅助** | UTF‑8 转换版本。 |
| `API_Prepare_Client(PhysicsAddr_: PAnsiChar; appHnd: TAppHnd): Integer; cdecl; external ...` | **导入** | 准备一个客户端连接。若 `appHnd` 非 `nil`，则暴露该应用；若为 `nil` 则纯消费。返回内部标签。 |
| `API_Prepare_Client2(PhysicsAddr_: string; appHnd: TAppHnd): Integer;` | **Pascal 辅助** | 带应用句柄版本。 |
| `API_Prepare_Client2(PhysicsAddr_: string): Integer;` | **Pascal 辅助** | 纯消费版本（`appHnd = nil`）。 |

#### 4.3.2 启动框架

| 函数 | 类型 | 说明 |
|------|------|------|
| `API_Prepare_Done: Integer; cdecl; external ...` | **导入** | 启动 C4 网络框架，**阻塞** 直到所有准备的服务/客户端初始化完成。返回 `1` 成功，`0` 失败（错误信息打印到控制台）。**只能调用一次**（除非重置）。 |

#### 4.3.3 停止事件循环

| 函数 | 类型 | 说明 |
|------|------|------|
| `API_Exit_MainThread(); cdecl; external ...` | **导入** | 通知内部事件循环退出，停止网络处理。通常后接 `API_shutdown`。 |

---

### 4.4 远程调用与通知

| 函数 | 类型 | 说明 |
|------|------|------|
| `API_Call(appName: PAnsiChar; Param: TDataHnd; Timeout_: UInt64): TDataHnd; cdecl; external ...` | **导入** | 同步远程调用目标应用，超时毫秒。返回**新句柄**，永远非 `nil`，调用者必须释放（即使大小为 0）。支持本地优化（若目标在本地注册）。 |
| `API_Call2(appName: string; Param: TDataHnd; Timeout_: UInt64): TDataHnd;` | **Pascal 辅助** | UTF‑8 转换版本。 |
| `API_Notify(appName: PAnsiChar; Param: TDataHnd); cdecl; external ...` | **导入** | 单向通知，不等待响应，尽力送达。 |
| `API_Notify2(appName: string; Param: TDataHnd);` | **Pascal 辅助** | UTF‑8 转换版本。 |

**注意**：
- `API_Call` 内部克隆参数句柄，调用者仍需释放原 `Param`。
- 超时值 `0` 表示无限等待（慎用）。
- 在回调中调用 `API_Call`/`API_Notify` 不会死锁，但注意防止无限递归，且不可阻塞。

---

### 4.5 运行时配置与关闭

#### 4.5.1 `API_SetOption`

```pascal
procedure API_SetOption(Option, Value: PAnsiChar); cdecl; external libapi_hub name 'API_SetOption';
```

**功能**：动态调整全局运行时配置，无需修改 `.ini` 文件或重启应用。

**支持的选项**（详见下表）：

| 选项键（主名） | 别名 | 值类型 | 说明 |
|---------------|------|--------|------|
| `password` | `passwd` | 字符串 | 设置 C4 P2PVM 认证令牌（新建连接生效，服务端/客户端必须匹配）。 |
| `Quiet` | — | 布尔 | 静默模式（`True` 抑制日志）。 |
| `External_Conf_Auto_Save` | `Conf_Auto_Save` | 布尔 | 退出时自动保存配置到 `.ini` 文件（默认 `True`）。 |
| `Wait_Connection_ReadyOk` | `Wait_API_Prepare_Done`, `WaitConnect`, `Wait_Ready`, `WaitReady` | 布尔 | `API_Prepare_Done` 是否等待客户端就绪。`False` 适合弹性部署。 |
| `Wait_Connection_Timeout` | `Wait_TimeOut`, `WaitTimeOut` | 整数（毫秒） | 最大等待时间，默认 30000。 |
| `ShowThreadID` | `ShowThread`, `Show_Thread` | 布尔 | 状态日志是否显示线程 ID。 |
| `ConsoleOutput` | `Console_Output` | 布尔 | 是否输出控制台日志。 |
| `IPC_Serv_ThreadCount` | `IPC_ThreadCount`, `IPC_Server_ThreadCount` | 整数 | IPC 服务线程池大小，默认 4。 |
| `IPC_Serv_MaxQueueLength` | `IPC_MaxQueueLength`, `IPC_Server_MaxQueueLength` | 整数 | IPC 消息队列最大长度，默认 4096。 |
| `IPC_Serv_MaxMsgSize` | `IPC_MaxMsgSize`, `IPC_Server_MaxMsgSize` | 整数（字节） | IPC 单条消息最大大小，默认 32768。 |

**注意事项**：
- 未知选项静默忽略。
- `Wait_Connection_*` 和 `password` 仅在 `API_Prepare_Done` 前设置有效。
- 布尔值接受 `True/False`、`1/0`、`Yes/No`。
- 无返回值，调用者需确保值合法。

**示例**：
```pascal
API_SetOption2('Wait_Ready', 'False');          // 部署模式
API_SetOption2('IPC_Serv_ThreadCount', '8');
API_SetOption2('ConsoleOutput', 'False');       // 关闭日志
```

#### 4.5.2 关闭框架

| 函数 | 类型 | 说明 |
|------|------|------|
| `API_shutdown(); cdecl; external ...` | **导入** | 完全关闭框架，停止所有服务、断开客户端、释放资源。建议先调用 `API_Exit_MainThread`，再 `API_shutdown`。 |

---

### 4.6 同步辅助

| 函数 | 类型 | 说明 |
|------|------|------|
| `API_Sync: Integer;` | **Pascal 实现** | 处理主线程软同步队列，返回处理的任务数。主线程需定期调用（例如在定时器或主循环中）以执行同步回调任务。 |

**使用场景**：当注册了 `API_Reg_Sync_Call_M` 或 `API_Reg_Sync_Notify_M` 时，必须定期调用 `API_Sync`，否则队列任务永远不会执行，导致回调阻塞。

---

## 5. 高级 RAII 封装 `z_api_hubtool_helper` 单元

本单元提供了面向对象的 RAII 封装，自动管理句柄生命周期，并支持链式调用和对象方法回调。**推荐日常开发使用**。

### 5.1 `API.TDataHandle` 类

封装 `TDataHnd`，构造时自动创建，析构时自动释放（若 `Owned`）。所有读写方法内部加锁，线程安全。

#### 5.1.1 构造与析构

| 方法 | 说明 |
|------|------|
| `constructor Create(const APIName: string);` | 新建句柄，绑定 API 名称（自动 UTF‑8）。 |
| `constructor Create(AHandle: TDataHnd; Owned: Boolean = True);` | 包装已有句柄，`Owned` 控制是否在析构时释放。 |
| `destructor Destroy; override;` | 自动释放（若 `Owned`）。 |

#### 5.1.2 原始读写

| 方法 | 说明 |
|------|------|
| `function WriteBuffer(const Buffer; Size: Int64): Int64;` | 写入原始字节，返回实际写入数。 |
| `function ReadBuffer(var Buffer; Size: Int64): Int64;` | 读取原始字节，返回实际读取数。 |

#### 5.1.3 类型安全写入（链式，返回 `Self`）

| 方法 | 说明 |
|------|------|
| `WriteInt8(Value: Int8): TDataHandle;` | 写入 8 位有符号整数，支持链式调用。 |
| `WriteUInt8, WriteInt16, WriteUInt16, WriteInt32, WriteUInt32, WriteInt64, WriteUInt64, WriteSingle, WriteDouble` | 同理。 |
| `WriteStringNullTerminated(const Value: string): TDataHandle;` | 写入 UTF‑8 字符串并追加 `#0`。 |
| `procedure WriteString(const Value: string); deprecated;` | 已弃用，请用 `WriteStringNullTerminated`。 |

**示例**：
```pascal
h.WriteInt32(5).WriteInt32(7).WriteStringNullTerminated('hello');
```

#### 5.1.4 类型安全读取

| 方法 | 说明 |
|------|------|
| `function ReadInt8(var Value: Int8): Boolean; overload;` | 读取并返回成功标志。 |
| `function ReadInt8: Int8; overload;` | 直接返回，失败返回 0。 |
| 其他类型同理（`UInt8`, `Int16`, `UInt16`, `Int32`, `UInt32`, `Int64`, `UInt64`, `Single`, `Double`, `String`）。 | 均有 `var` 和直接返回两个版本。 |

#### 5.1.5 位置与大小

| 方法 | 说明 |
|------|------|
| `function GetPos: Int64;` `procedure SetPos(Pos_: Int64);` | 读写位置。 |
| `function GetSize: Int64;` `procedure SetSize(Size_: Int64);` | 获取/设置大小。 |
| 属性 `Pos`, `Size` | 对应读写。 |

#### 5.1.6 零拷贝访问

| 方法 | 说明 |
|------|------|
| `function GetBufferEx(out Size: Int64): Pointer;` | 返回内部指针和当前大小，调用者不得释放指针。 |

#### 5.1.7 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `Handle` | `TDataHnd` | 只读，返回原始句柄。 |

---

### 5.2 `API.TAppHandle` 类

封装 `TAppHnd`，自动管理应用句柄生命周期。

#### 5.2.1 构造与析构

| 方法 | 说明 |
|------|------|
| `constructor Create(const AppName, Desc: string);` | 创建应用句柄（自动 UTF‑8）。 |
| `destructor Destroy; override;` | 自动释放句柄。 |

#### 5.2.2 注册 API（函数指针版本）

| 方法 | 说明 |
|------|------|
| `function RegisterCall(const APIName, Desc: string; Trigger: Pointer; OnCall: TAPI_Call): Boolean;` | 注册 `cdecl` 函数指针 `Call`。 |
| `function RegisterNotify(const APIName, Desc: string; Trigger: Pointer; OnNotify: TAPI_Notify): Boolean;` | 注册 `cdecl` 函数指针 `Notify`。 |

#### 5.2.3 注册 API（对象方法版本，`of object`）

| 方法 | 说明 |
|------|------|
| `function RegisterCall(const APIName, Desc: string; OnCall: TAPI_Call_M): Boolean;` | 注册对象方法 `Call`（非同步，C 线程池执行）。 |
| `function RegisterCallSync(const APIName, Desc: string; OnCall: TAPI_Call_M): Boolean;` | 注册对象方法 `Call`（同步到主线程，需 `API.Sync`）。 |
| `function RegisterNotify(const APIName, Desc: string; OnNotify: TAPI_Notify_M): Boolean;` | 注册对象方法 `Notify`（非同步）。 |
| `function RegisterNotifySync(const APIName, Desc: string; OnNotify: TAPI_Notify_M): Boolean;` | 注册对象方法 `Notify`（同步到主线程）。 |

#### 5.2.4 动态注销

| 方法 | 说明 |
|------|------|
| `function Unregister(const APIName: string): Boolean;` | 注销 API，返回成功标志。 |

#### 5.2.5 本地调用

| 方法 | 说明 |
|------|------|
| `function LocalCall(Param: TDataHandle): TDataHandle;` | 本地同步执行 `Call`，返回结果句柄（需释放）。 |
| `procedure LocalNotify(Param: TDataHandle);` | 本地发送通知。 |

#### 5.2.6 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `Handle` | `TAppHnd` | 原始句柄。 |
| `Name` | `string` | 应用名。 |

---

### 5.3 `API` 静态方法

提供全局网络操作，所有方法均为 `class`。

| 方法 | 说明 |
|------|------|
| `class procedure ResetPrepare;` | 清除网络配置。 |
| `class function PrepareService(const ListeningAddr, PhysicsAddr: string): Integer; overload;` | 准备服务监听器。 |
| `class function PrepareService(const ListeningAddr, PhysicsAddr: string; App: TAppHandle): Integer; overload;` | 准备服务并自动准备客户端。 |
| `class function PrepareClient(const PhysicsAddr: string; App: TAppHandle): Integer;` | 准备客户端连接。 |
| `class function PrepareDone: Boolean;` | 启动网络框架，成功返回 `True`。 |
| `class procedure ExitMainThread;` | 停止事件循环。 |
| `class function CallApp(const AppName: string; Param: TDataHandle; TimeoutMs: UInt64): TDataHandle;` | 远程同步调用，返回结果句柄（需释放）。 |
| `class procedure NotifyApp(const AppName: string; Param: TDataHandle);` | 远程通知。 |
| `class procedure SetOption(const Option, Value: string);` | 运行时配置。 |
| `class function Sync: Integer;` | 处理主线程同步队列，返回任务数。 |
| `class procedure Shutdown;` | 关闭框架。 |

---

### 5.4 `API__` 底层静态映射

`API__` 类直接映射 `z_api_hubtool_import` 中的所有 **`external` 函数**（函数名相同，无 Pascal 辅助）。**仅供高级用户绕过 RAII 封装**，常规开发应使用 `API` 容器类。

---

## 6. 回调函数详解与线程安全

### 6.1 回调执行上下文

所有回调（`TAPI_Call`、`TAPI_Notify`）均在 **C4 线程池** 中执行。这意味着：

- **非同步版本**（`API_Reg_Call`、`API_Reg_Notify`、`API_Reg_Call_M`、`API_Reg_Notify_M`）的回调直接在线程池中运行。
- **同步版本**（`API_Reg_Sync_Call_M`、`API_Reg_Sync_Notify_M`）通过 `TSoft_Synchronize_Tool` 将任务排队到主线程软同步队列，**需主线程定期调用 `API.Sync`** 执行。

### 6.2 回调内的约束

无论哪种版本，回调内都应遵守：

- **✅ 可以**调用 `API_Call` / `API_Notify`（不会死锁），但要避免无限递归。
- **❌ 禁止**长时间阻塞（`Sleep`、等待锁、大量循环）。
- **❌ 禁止**直接访问 UI（必须用 `TThread.Synchronize` 或同步版本）。
- **✅ 推荐**耗时任务异步提交到自己的工作队列。

### 6.3 同步版本的使用要点

- 注册 `Sync` 回调后，必须在主线程（通常为定时器或主循环）中**频繁调用 `API.Sync`**，否则队列积压，回调永不执行。
- 同步版本虽然保证 UI 安全，但会增大主线程负担，不适合高频调用。

### 6.4 线程安全总结

- 所有 `external` 函数线程安全。
- `TDataHandle` 实例内部加锁，可并发读写（写操作串行化）。
- `TAppHandle` 无额外锁（底层已线程安全）。
- 回调中可自由调用 `API_Call`，但注意性能。

---

## 7. 完整示例：服务端与客户端

### 7.1 使用底层 `import` 单元（手动管理句柄）

#### 服务端（`server_import.lpr`）
```pascal
program server_import;

uses
  SysUtils,
  z_api_hubtool_import;

procedure AddCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
var
  a, b, sum: Integer;
begin
  if API_ReadBuffer(TDataHnd(Input), @a, SizeOf(a)) <> SizeOf(a) then Exit;
  if API_ReadBuffer(TDataHnd(Input), @b, SizeOf(b)) <> SizeOf(b) then Exit;
  sum := a + b;
  API_WriteBuffer(TDataHnd(Output), @sum, SizeOf(sum));
end;

var
  app: TAppHnd;
begin
  app := API_Create_APPHnd2('CalcService', 'Calculator');
  API_Reg_Call2(app, 'add', 'Addition', nil, @AddCallback);

  API_Reset_Prepare;
  API_Prepare_Service2('ipc:calc_service', 'ipc:calc_service');
  API_Prepare_Client2('ipc:calc_service', app);

  if API_Prepare_Done = 1 then
  begin
    Writeln('Service running. Press Enter to stop.');
    Readln;
  end;

  API_Exit_MainThread;
  API_Free_APPHnd(app);
  API_shutdown;
end.
```

#### 客户端（`client_import.lpr`）
```pascal
program client_import;

uses
  SysUtils,
  z_api_hubtool_import;

var
  param, res: TDataHnd;
  a, b, sum: Integer;
begin
  API_Reset_Prepare;
  API_Prepare_Client2('ipc:calc_service', nil);

  if API_Prepare_Done <> 1 then
  begin
    Writeln('Connect failed');
    Halt(1);
  end;

  param := API_Create_DataHnd2('add');
  a := 10; b := 20;
  API_WriteInt32(param, a);
  API_WriteInt32(param, b);

  res := API_Call2('CalcService', param, 3000);
  API_Free_DataHnd(param);

  if API_GetSize(res) >= SizeOf(Integer) then
  begin
    API_SetPos(res, 0);
    sum := API_ReadInt32(res);
    Writeln('10 + 20 = ', sum);
  end;

  API_Free_DataHnd(res);
  API_Exit_MainThread;
  API_shutdown;
end.
```

### 7.2 使用 RAII 封装（推荐）

#### 服务端（`server_helper.lpr`）
```pascal
program server_helper;

uses
  SysUtils,
  z_api_hubtool_helper,
  z_api_hubtool_import;

procedure AddCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
var
  a, b, sum: Integer;
begin
  if API_ReadBuffer(TDataHnd(Input), @a, SizeOf(a)) <> SizeOf(a) then Exit;
  if API_ReadBuffer(TDataHnd(Input), @b, SizeOf(b)) <> SizeOf(b) then Exit;
  sum := a + b;
  API_WriteBuffer(TDataHnd(Output), @sum, SizeOf(sum));
end;

var
  app: TAppHandle;
begin
  app := TAppHandle.Create('CalcService', 'Calculator');
  app.RegisterCall('add', 'Addition', nil, @AddCallback);

  API.ResetPrepare;
  API.PrepareService('ipc:calc_service', 'ipc:calc_service');
  API.PrepareClient('ipc:calc_service', app);

  if API.PrepareDone then
  begin
    Writeln('Service running. Press Enter to stop.');
    Readln;
  end;

  API.ExitMainThread;
  API.Shutdown;
  app.Free;  // 或利用 try..finally 自动释放
end.
```

#### 客户端（`client_helper.lpr`）
```pascal
program client_helper;

uses
  SysUtils,
  z_api_hubtool_helper;

var
  param, res: TDataHandle;
  sum: Integer;
begin
  API.ResetPrepare;
  API.PrepareClient('ipc:calc_service', nil);

  if not API.PrepareDone then
  begin
    Writeln('Connect failed');
    Halt(1);
  end;

  param := TDataHandle.Create('add');
  param.WriteInt32(10).WriteInt32(20);

  res := API.CallApp('CalcService', param, 3000);
  param.Free;

  if res.GetSize >= SizeOf(Integer) then
  begin
    res.SetPos(0);
    sum := res.ReadInt32;
    Writeln('10 + 20 = ', sum);
  end;
  res.Free;

  API.ExitMainThread;
  API.Shutdown;
end.
```

---

## 8. 常见问题与排错

| 问题 | 可能原因 | 解决方案 |
|------|----------|----------|
| 动态库加载失败 | DLL/so 不在搜索路径 | 将动态库放至可执行文件目录或系统 `PATH`。 |
| `API_Prepare_Done` 返回 0 | 端口/IPC 名称被占用或地址格式错误 | 检查控制台错误信息，更换地址。 |
| 回调未触发 | 应用名或 API 名大小写不一致 | 确保客户端调用名称完全匹配（区分大小写）。 |
| 内存泄漏 | 未释放句柄 | 确保每个 `Create` 都有对应 `Free`，`API_Call` 返回的句柄必须释放。 |
| 回调中调用 `API_Call` 死循环 | 无限递归 | 在回调中添加递归深度限制或避免循环调用。 |
| 同步回调不执行 | 未调用 `API.Sync` | 在主循环或定时器中定期调用 `API.Sync`。 |
| 多线程写冲突 | 同一 `TDataHnd` 并发写入 | 使用锁或不同句柄。 |
| 乱码 | 字符串不是 UTF‑8 | 确保所有字符串参数使用 `UTF8Encode` 转换。 |

---

## 9. 附录：函数速查表

### 9.1 底层 `import` 函数（带 `external`）

| 函数 | 用途 |
|------|------|
| `API_Create_DataHnd` | 创建数据句柄 |
| `API_Free_DataHnd` | 释放数据句柄 |
| `API_GetBuffer` | 获取内部缓冲区指针 |
| `API_WriteBuffer` | 写入原始字节 |
| `API_ReadBuffer` | 读取原始字节 |
| `API_GetPos` / `API_SetPos` | 读写位置 |
| `API_GetSize` / `API_SetSize` | 读写大小 |
| `API_Create_APPHnd` | 创建应用句柄 |
| `API_Free_APPHnd` | 释放应用句柄 |
| `API_Reg_Call` | 注册 Call（cdecl 函数） |
| `API_Reg_Notify` | 注册 Notify（cdecl 函数） |
| `API_UnReg` | 动态注销 API |
| `API_Local_APP_Call` | 本地同步调用 |
| `API_Local_APP_Notify` | 本地通知 |
| `API_Reset_Prepare` | 重置网络准备 |
| `API_Prepare_Service` | 准备服务监听 |
| `API_Prepare_Client` | 准备客户端连接 |
| `API_Prepare_Done` | 启动网络框架 |
| `API_Exit_MainThread` | 停止事件循环 |
| `API_Call` | 远程同步调用 |
| `API_Notify` | 远程通知 |
| `API_SetOption` | 运行时配置 |
| `API_shutdown` | 关闭框架 |

### 9.2 Pascal 辅助函数（不带 `external`）

| 函数 | 用途 |
|------|------|
| `API_Create_DataHnd2` | UTF‑8 版本创建句柄 |
| `API_GetBuffer2` | 带偏移的缓冲区指针 |
| `API_WriteInt8` … `API_WriteDouble` | 原子写入 |
| `API_ReadInt8` … `API_ReadDouble` | 原子读取 |
| `API_WriteString` / `API_ReadString` | UTF‑8 字符串读写 |
| `API_Create_APPHnd2` | UTF‑8 创建应用 |
| `API_Reg_Call2` / `API_Reg_Notify2` | UTF‑8 注册（函数指针） |
| `API_Reg_Call_M` / `API_Reg_Notify_M` | 注册对象方法（非同步） |
| `API_Reg_Sync_Call_M` / `API_Reg_Sync_Notify_M` | 注册对象方法（同步） |
| `API_UnReg2` | UTF‑8 注销 |
| `API_Prepare_Service2` / `API_Prepare_Client2` | UTF‑8 网络准备 |
| `API_Call2` / `API_Notify2` | UTF‑8 远程调用 |
| `API_SetOption2` | UTF‑8 配置 |
| `API_Sync` | 处理主线程同步队列 |

### 9.3 RAII 封装 `API` 类方法

| 方法 | 说明 |
|------|------|
| `TDataHandle.Create` | 构造 |
| `TDataHandle.WriteXXX` / `ReadXXX` | 读写 |
| `TDataHandle.GetPos/SetPos/GetSize/SetSize` | 位置/大小 |
| `TDataHandle.GetBufferEx` | 零拷贝指针 |
| `TAppHandle.Create` | 构造应用 |
| `TAppHandle.RegisterCall/Notify` | 注册 API（函数指针/对象方法） |
| `TAppHandle.Unregister` | 注销 |
| `TAppHandle.LocalCall/LocalNotify` | 本地调用 |
| `API.ResetPrepare`, `PrepareService`, `PrepareClient`, `PrepareDone` | 网络准备 |
| `API.CallApp`, `NotifyApp` | 远程调用 |
| `API.SetOption`, `Sync`, `Shutdown` | 配置/同步/关闭 |

---

**本手册涵盖了 `z_api_hubtool_import` 和 `z_api_hubtool_helper` 的全部内容，每个函数均有详细说明和示例。在实际开发中，推荐优先使用 RAII 封装以简化资源管理。如有疑问，请参考项目源码或控制台日志进行诊断。**
