# API Hub Tool for Pascal — 完整使用指南

> **让您的 Pascal 应用轻松融入分布式 API 生态，以最轻量的方式实现跨语言、跨进程、跨机器的函数调用。**  
> 基于 C4 分布式服务网格与 Z 系列基础库，提供企业级服务发现、负载均衡与容错能力。

---

## 📖 目录

- [1. 概述](#1-概述)
- [2. 核心概念](#2-核心概念)
- [3. 环境准备与库加载](#3-环境准备与库加载)
- [4. 数据句柄操作（DataHnd）](#4-数据句柄操作datahnd)
- [5. 应用句柄操作（AppHnd）](#5-应用句柄操作apphnd)
  - [5.1 API_Create_APPHnd](#51-api_create_apphnd)
  - [5.2 API_Free_APPHnd](#52-api_free_apphnd)
  - [5.3 API_Reg_Call](#53-api_reg_call)
  - [5.4 API_Reg_Notify](#54-api_reg_notify)
  - [5.5 API_Local_APP_Call](#55-api_local_app_call)
  - [5.6 API_Local_APP_Notify](#56-api_local_app_notify)
  - [5.7 API_UnReg — 动态注销 API（新增）](#57-api_unreg--动态注销-api新增)
- [6. 本地快速测试（无网络）](#6-本地快速测试无网络)
- [7. 网络层准备与启动](#7-网络层准备与启动)
- [8. 远程调用与通知](#8-远程调用与通知)
  - [8.1 API_Call](#81-api_call)
  - [8.2 API_Notify](#82-api_notify)
  - [8.3 API_SetOption — 运行时动态调整全局配置（新增）](#83-api_setoption--运行时动态调整全局配置新增)
- [9. 关闭与清理](#9-关闭与清理)
- [10. 完整示例（服务端 + 客户端）](#10-完整示例服务端--客户端)
- [11. 常见问题与排错](#11-常见问题与排错)
- [附录 A：API 速查表](#附录-aapi-速查表)
- [更新日志](#更新日志)

---

## 1. 概述

`z_api_hubtool_import` 是 API Hub 的 **Pascal 语言绑定单元**。它通过 `external` 动态链接方式加载底层 C 动态库（`z_api_hub64.dll` / `libz_api_hub.so` / `libz_api_hub.dylib`），让任何 Pascal 程序（Delphi / Free Pascal）能够：

- 将普通 Pascal 函数暴露为**远程可调用 API**（请求-响应或单向通知）
- 调用其他语言（C++、C#、Python、Go、Rust、PHP、Node.js 等）注册的远程服务
- 在同一台机器上通过 **IPC**（进程间通信）或跨机器通过 **TCP** 进行通信

底层基于 **C4 分布式服务网格**，自动处理服务发现、负载均衡、断线重连、NAT 穿越等复杂问题。

### 🔤 **字符串编码——强制 UTF-8**

所有 `PAnsiChar` 类型的参数（包括 API 名称、描述和网络地址）**必须使用 UTF-8 编码**，并且必须以 **null 字节（#0）结尾**。这是跨语言、跨平台调用的一致约定。在 Windows 上，库**不会**使用系统 ANSI 代码页（如 GBK），而是始终按 UTF-8 处理字节流。

---

## 2. 核心概念

### 2.1 句柄

- **`TDataHnd`**：数据句柄，封装了一个 API 名称和二进制载荷。用于输入参数和输出结果。
- **`TAppHnd`**：应用句柄，代表一个逻辑应用，可注册多个 API，在网络中具有唯一名称。

### 2.2 回调约定

- **`TAPI_Call`**：请求-响应回调，必须声明为 `cdecl`，接收 `Trigger`（用户数据）、`Input`（只读）、`Output`（只写）。
- **`TAPI_Notify`**：单向通知回调，也必须是 `cdecl`，只接收 `Trigger` 和 `Input`。

#### ⚠️ **回调执行上下文（关键）**

所有回调函数（`TAPI_Call` 和 `TAPI_Notify`）都**在后台线程池线程中执行**，而不是在调用 `API_Call`/`API_Notify` 的线程中。

这带来以下**重要约束**：

- **❌ 禁止**在回调内执行长时间阻塞操作（如 `Sleep`、等待事件、大量循环）。
- **❌ 禁止**在回调内调用 `API_Call` 或 `API_Notify` —— 这可能导致**死锁**，因为回调线程可能持有内部锁，而 `API_Call` 需要获取同一锁。
- **❌ 禁止**在回调内直接访问 UI 组件或线程局部存储（TLS），除非通过线程同步机制（如 `TThread.Synchronize`、`TMonitor`、消息队列等）。
- **✅ 推荐**将耗时任务**异步提交**到自己的工作线程或任务队列，使回调快速返回。

**示例（正确做法）**：将需要远程调用的请求放入队列，由另一个线程处理。

```pascal
// 在回调中不要直接调用 API_Call，而是发送一个异步任务
TCompute.RunP_NP(procedure
begin
  // 在这里安全地调用 API_Call
  Res := API_Call('TargetApp', Data, 5000);
end);
```

> **为什么回调会在线程池中执行？**  
> 因为 API Hub 的底层 C4 服务网格使用多线程处理并发请求，以充分利用多核 CPU。回调在线程池中执行可以最大化吞吐量，但您必须遵守上述规则。

---

### 2.3 并发与执行顺序

#### 🔄 **调用顺序不保证**

当您从多个线程或连续多次调用 `API_Call` 时，**请求到达远程服务的顺序是不确定的**。这是因为：

- 底层 C4 服务网格会**负载均衡**请求到多个服务实例（如果同一个应用名称在多个进程中注册）。
- 每个实例内部的线程池也会以不确定的顺序处理请求。

**示例**：如果您的程序按顺序发送调用 `1`、`2`、`3`，远程可能以 `2`、`1`、`3` 的顺序处理。**只有每个单个调用的请求-响应语义是可靠的**（原子性、正确性），但**全局顺序不保证**。

**如果需要保证顺序**，您必须在应用层实现自己的顺序控制（例如在请求中包含序列号，或通过单线程串行化调用）。

---

### 2.4 线程安全

- **所有导出函数都是完全线程安全的**，可在任意线程并发调用。
- 单个 `TDataHnd` 的写操作（`API_WriteBuffer`、`API_SetPos`、`API_SetSize`）应在同一句柄上串行化；不同句柄可以并发操作。

### 2.5 网络地址格式

| 协议 | 格式 | 示例 | 跨机 |
|------|------|------|------|
| TCP（IPv4） | `主机:端口` | `127.0.0.1:9898` | ✅ |
| TCP（IPv6） | `[::1]:端口` 或 `::1\|端口` | `[::1]:8080` | ✅ |
| IPC | `ipc:服务名` | `ipc:calc_service` | ❌ |
| 通配符（服务端） | `0.0.0.0` | 监听所有接口 | - |

默认 TCP 端口为 `9898`，IPC 忽略端口。

---

## 3. 环境准备与库加载

### 3.1 动态库放置

| 操作系统 | 动态库名称 | 放置位置 |
|----------|-----------|----------|
| Windows 64-bit | `z_api_hub64.dll` | 可执行文件目录或 `PATH` |
| Windows 32-bit | `z_api_hub32.dll` | 可执行文件目录或 `PATH` |
| Linux | `libz_api_hub.so` | `LD_LIBRARY_PATH` 或 `/usr/lib` |
| BSD | `libz_api_hub.so` | `LD_LIBRARY_PATH` 或标准库路径 |
| macOS | `libz_api_hub.dylib` | `DYLD_LIBRARY_PATH` 或 `/usr/local/lib` |

**依赖库**（需与主库同目录）：
- Windows：`z_ipc_64.dll` / `z_ipc_32.dll`
- Linux/BSD：`libz_ipc.so`
- macOS：`libz_ipc.dylib`（如有）

### 3.2 库自动加载

本单元使用 `external` 指令，库会在第一次调用外部函数时由操作系统自动加载。**无需手动调用 LoadLibrary**。

加载搜索顺序（平台相关）：
- 先搜索**可执行文件所在目录**（或当前工作目录，依系统而定）
- 再搜索系统标准库路径（Windows 的 `PATH`，Linux/BSD 的 `LD_LIBRARY_PATH`，macOS 的 `DYLD_LIBRARY_PATH`）

这使得部署非常简单：只需将库文件（及其辅助 IPC 库）放在可执行文件旁边或系统库目录中即可。

若库缺失，程序会抛出异常（如 `External exception`），建议在程序入口处进行错误处理（例如使用 `try..except` 包围第一次调用）。

### 3.3 配置文件

首次运行时会生成 `<可执行文件名>.api-tool.ini`，可编辑调整超时、日志、线程池大小等参数，无需重新编译。

---

## 4. 数据句柄操作（DataHnd）

### 📦 **数据布局说明**

`TDataHnd` 内部同时存储了 **API 名称**和**二进制载荷**。API 名称在创建时通过 `API_Create_DataHnd(APIName)` 设置，之后**不可更改**。所有 `API_WriteBuffer`、`API_ReadBuffer` 等操作**只影响载荷部分**，不会影响 API 名称。

**重要**：`APIName` 必须为 **UTF-8 编码**的 null 结尾字符串。

在传输时，载荷会与 API 名称一起打包（序列化格式由 `TMemory_Param_Tool` 处理），但作为用户，您只需使用提供的读写函数即可，无需关心内部细节。

---

### 4.1 `API_Create_DataHnd`

```pascal
function API_Create_DataHnd(APIName: PAnsiChar): TDataHnd; cdecl;
```

**功能**：创建一个新的数据句柄，并设置其关联的 API 名称。初始载荷为空（大小 0）。

**参数**：
- `APIName`：目标 API 的名称（以空字符结尾的 **UTF-8 字符串**）。该名称将用于路由。

**返回值**：新句柄。正常情况下永远返回非 `nil`。

**线程安全**：✅

**注意**：
- API 名称会被内部复制，调用者可立即释放输入的字符串。
- 句柄必须通过 `API_Free_DataHnd` 释放，否则内存泄漏。

**示例**：
```pascal
var
  h: TDataHnd;
begin
  h := API_Create_DataHnd('add');   // 'add' 是 ASCII，也是合法的 UTF-8
  // ... 写入数据 ...
  API_Free_DataHnd(h);
end;
```

---

### 4.2 `API_Free_DataHnd`

```pascal
procedure API_Free_DataHnd(Hnd: TDataHnd); cdecl;
```

**功能**：销毁数据句柄，释放所有关联内存。句柄变为无效。

**参数**：
- `Hnd`：要释放的句柄。若为 `nil` 则无操作。

**线程安全**：✅ 是，但句柄不能被并发使用。

---

### 4.3 `API_GetBuffer`

```pascal
function API_GetBuffer(Hnd: TDataHnd): Pointer; cdecl;
```

**功能**：返回指向句柄内部缓冲区的直接指针（零拷贝访问）。

**参数**：
- `Hnd`：数据句柄。

**返回值**：内部缓冲区指针；若句柄无数据则返回 `nil`。

**线程安全**：✅ 读安全，但若同时有写入操作（如其他线程调用 `API_WriteBuffer`）则不安全。

**注意**：
- 返回的指针可以**读取和写入**，但写入时**不得超过 `API_GetSize` 返回的大小**，否则会破坏内部状态。
- 调用者**不应释放**此指针。
- 指针在句柄被释放或重新调整大小后可能失效。

**示例**：
```pascal
var
  p: PByte;
  sz: Int64;
begin
  sz := API_GetSize(h);
  p := API_GetBuffer(h);
  // 读写 p[0] .. p[sz-1]
end;
```

---

### 4.4 `API_WriteBuffer`

```pascal
function API_WriteBuffer(Hnd: TDataHnd; Buff: Pointer; Size: Int64): Int64; cdecl;
```

**功能**：从当前读写位置开始，向句柄缓冲区写入数据。缓冲区自动扩容。

**参数**：
- `Hnd`：数据句柄。
- `Buff`：源数据指针。
- `Size`：要写入的字节数。

**返回值**：实际写入的字节数（通常等于 `Size`）。

**线程安全**：⚠️ 同一句柄上的写操作应串行化；不同句柄可并发写入。

**示例**：
```pascal
var
  i: Integer;
begin
  i := 12345;
  API_WriteBuffer(h, @i, SizeOf(i));
  API_WriteBuffer(h, 'hello', 5);
end;
```

---

### 4.5 `API_ReadBuffer`

```pascal
function API_ReadBuffer(Hnd: TDataHnd; Buff: Pointer; Size: Int64): Int64; cdecl;
```

**功能**：从当前读写位置读取数据到调用者缓冲区，位置随读取字节数后移。

**参数**：
- `Hnd`：数据句柄。
- `Buff`：目标缓冲区指针。
- `Size`：最多读取的字节数。

**返回值**：实际读取的字节数（可能小于 `Size`，若到达缓冲区尾部）。

**线程安全**：⚠️ 同一句柄上不应同时读写；但多个线程同时读取是安全的。

**示例**：
```pascal
var
  i: Integer;
begin
  API_SetPos(h, 0);
  if API_ReadBuffer(h, @i, SizeOf(i)) = SizeOf(i) then
    // i 被成功读取
end;
```

---

### 4.6 `API_GetPos` / `API_SetPos`

```pascal
function API_GetPos(Hnd: TDataHnd): Int64; cdecl;
procedure API_SetPos(Hnd: TDataHnd; Pos_: Int64); cdecl;
```

**功能**：获取/设置当前读写位置（0-based 偏移）。

**注意**：
- `API_SetPos` 若位置超出当前大小，会自动扩展缓冲区（填充零）。
- 位置必须 ≥ 0。

**线程安全**：`GetPos` 只读安全；`SetPos` 需串行化。

---

### 4.7 `API_GetSize` / `API_SetSize`

```pascal
function API_GetSize(Hnd: TDataHnd): Int64; cdecl;
procedure API_SetSize(Hnd: TDataHnd; Size_: Int64); cdecl;
```

**功能**：获取/设置缓冲区总大小。`SetSize` 可截断或扩展（扩展部分未初始化）。

**线程安全**：`GetSize` 只读安全；`SetSize` 需串行化。

---

## 5. 应用句柄操作（AppHnd）

### 5.1 `API_Create_APPHnd`

```pascal
function API_Create_APPHnd(appName, Desc: PAnsiChar): TAppHnd; cdecl;
```

**功能**：创建一个应用上下文。应用是 API 的容器，在网络中具有唯一名称。

**参数**：
- `appName`：应用名称（区分大小写，网络唯一，**UTF-8 编码**）。
- `Desc`：描述（可为空字符串，**UTF-8 编码**）。

**返回值**：新应用句柄，正常情况下非 `nil`。

**线程安全**：✅

**示例**：
```pascal
var
  app: TAppHnd;
begin
  app := API_Create_APPHnd('Calculator', 'My Calc Service');
  // 注册 API ...
  API_Free_APPHnd(app);
end;
```

---

### 5.2 `API_Free_APPHnd`

```pascal
procedure API_Free_APPHnd(appHnd: TAppHnd); cdecl;
```

**功能**：销毁应用句柄，释放所有已注册的 API 及相关资源。

**线程安全**：✅ 但确保没有其他线程正在使用该句柄。

---

### 5.3 `API_Reg_Call`

```pascal
function API_Reg_Call(appHnd: TAppHnd; APIName, Desc: PAnsiChar; Trigger: Pointer; OnCall: TAPI_Call): Integer; cdecl;
```

**功能**：在应用中注册一个请求-响应（Call）API。当远程或本地调用此 API 时，`OnCall` 回调会被执行。

**参数**：
- `appHnd`：应用句柄。
- `APIName`：API 名称（应用内唯一，区分大小写，**UTF-8**）。
- `Desc`：描述（可选，**UTF-8**）。
- `Trigger`：用户数据指针，回调时会原样传回。
- `OnCall`：回调函数指针（必须 `cdecl`）。

**返回值**：`1` 成功，`0` 失败（名称已存在）。

**线程安全**：✅

**注意**：回调中禁止调用 `API_Call`/`API_Notify`，避免死锁（详见 2.2 节）。

**示例**：
```pascal
procedure MyAdd(Trigger: Pointer; Input, Output: Pointer); cdecl;
var
  a, b, sum: Integer;
begin
  API_ReadBuffer(Input, @a, SizeOf(a));
  API_ReadBuffer(Input, @b, SizeOf(b));
  sum := a + b;
  API_WriteBuffer(Output, @sum, SizeOf(sum));
end;

// 注册
if API_Reg_Call(app, 'add', 'Addition', nil, @MyAdd) = 1 then
  // success
```

---

### 5.4 `API_Reg_Notify`

```pascal
function API_Reg_Notify(appHnd: TAppHnd; APIName, Desc: PAnsiChar; Trigger: Pointer; OnNotify: TAPI_Notify): Integer; cdecl;
```

**功能**：注册一个单向通知（Notify）API。调用者不等待响应。

**参数**：类似 `API_Reg_Call`，但回调类型为 `TAPI_Notify`（无 `Output` 参数）。字符串均为 **UTF-8**。

**返回值**：`1` 成功，`0` 失败。

**线程安全**：✅

---

### 5.5 `API_Local_APP_Call`

```pascal
function API_Local_APP_Call(appHnd: TAppHnd; Param: TDataHnd): TDataHnd; cdecl;
```

**功能**：在**本地**同步执行一个 Call API，绕过网络。适用于单元测试或内部调用。

**参数**：
- `appHnd`：应用句柄。
- `Param`：输入数据句柄（必须包含 API 名称和参数，API 名称必须为 **UTF-8**）。

**返回值**：新的结果句柄（必须释放）；若 API 未找到或出错，返回句柄大小为 0。

**线程安全**：✅

**示例**：
```pascal
var
  d, res: TDataHnd;
begin
  d := API_Create_DataHnd('add');
  API_WriteBuffer(d, @a, SizeOf(a));
  API_WriteBuffer(d, @b, SizeOf(b));
  res := API_Local_APP_Call(app, d);
  // 处理 res
  API_Free_DataHnd(d);
  API_Free_DataHnd(res);
end;
```

---

### 5.6 `API_Local_APP_Notify`

```pascal
procedure API_Local_APP_Notify(appHnd: TAppHnd; Param: TDataHnd); cdecl;
```

**功能**：在本地发送一个通知（无返回）。

**线程安全**：✅

---

### 5.7 `API_UnReg` — 动态注销 API（新增）

```pascal
function API_UnReg(appHnd: TAppHnd; APIName: PAnsiChar): Integer; cdecl;
```

**功能**：从应用中注销一个先前注册的 API。该 API 会**立即从本地注册表中移除**，并**触发网络广播**通知所有已连接的对等节点。广播完成后（通常在约 3 秒内，取决于网络延迟和 C4 更新间隔），远程节点将不再能发现或调用此 API。

**参数**：
- `appHnd`：应用句柄。
- `APIName`：要注销的 API 名称（**UTF-8** 编码）。

**返回值**：`1` 成功（API 存在并被移除），`0` 失败（API 名称不存在）。

**线程安全**：✅

**关键行为**：

- **本地立即生效**：API 从 `TAPI_Info_Pool` 中同步删除，后续本地调用（如 `API_Local_APP_Call`）将立即失败（返回空结果）。
- **网络异步广播**：删除操作会触发 `APP.DoChange()`，通过 C4 服务网格将更新广播给所有已连接的客户端。
- **传播延迟窗口**：在广播传播期间（通常约 3 秒），远程调用可能仍然到达并失败（返回"未找到"错误）。这是正常的分布式系统最终一致性行为。

**使用场景**：

- **热卸载插件**：动态库插件可先注销自身 API，再安全卸载。
- **临时维护模式**：临时下线某些功能 API，无需重启整个应用。
- **权限动态调整**：根据用户角色或运行时条件，移除敏感 API 暴露。

**示例**：

```pascal
var
  app: TAppHnd;
begin
  app := API_Create_APPHnd('MyService', '');
  API_Reg_Call(app, 'add', 'Addition', nil, @AddCallback);

  // ... 运行一段时间后，决定下线 'add' API
  if API_UnReg(app, 'add') = 1 then
    Writeln('API "add" unregistered, broadcast in progress');
  else
    Writeln('API "add" not found');

  API_Free_APPHnd(app);
end;
```

**注意事项**：
- 注销后，**正在执行中的回调不会被打断**（它们会正常完成）。
- 新到达的远程请求会在广播传播前或传播后分别被路由到旧状态或新状态，这是分布式系统的正常行为。
- 如需立即阻止新请求，可在注销前设置一个应用级别的"维护中"标志，由回调检查并拒绝请求。

---

## 6. 本地快速测试（无网络）

在开始网络编程之前，强烈建议先用本地调用验证您的 API 注册和回调逻辑。以下示例完全无需网络，仅在一个进程中测试：

```pascal
program QuickLocalTest;

uses
  z_api_hubtool_import;

procedure EchoCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
var
  sz: Int64;
  buf: PByte;
begin
  sz := API_GetSize(Input);
  if sz > 0 then
  begin
    buf := GetMemory(sz);
    API_SetPos(Input, 0);
    API_ReadBuffer(Input, buf, sz);
    API_WriteBuffer(Output, buf, sz);
    FreeMemory(buf);
  end;
end;

var
  app: TAppHnd;
  data, result: TDataHnd;
  msg: string;
begin
  app := API_Create_APPHnd('TestApp', '');
  API_Reg_Call(app, 'echo', 'Echo', nil, @EchoCallback);

  data := API_Create_DataHnd('echo');
  msg := 'Hello World';
  // 注意：PAnsiChar 应使用 UTF-8，这里 msg 为 ASCII，可直接转换
  API_WriteBuffer(data, PAnsiChar(msg), Length(msg));

  result := API_Local_APP_Call(app, data);
  if API_GetSize(result) > 0 then
  begin
    SetLength(msg, API_GetSize(result));
    API_ReadBuffer(result, PAnsiChar(msg), API_GetSize(result));
    WriteLn('Echo: ', msg);
  end;

  API_Free_DataHnd(data);
  API_Free_DataHnd(result);
  API_Free_APPHnd(app);
end.
```

此测试不涉及任何网络，可用于快速验证回调逻辑。

---

## 7. 网络层准备与启动

### 7.1 地址匹配规则

- **服务端**：`ListeningAddr_` 是**本地绑定**地址（如 `0.0.0.0` 表示监听所有接口）。`PhysicsAddr_` 是**对外公布**的地址，客户端将使用此地址连接。
- **客户端**：`PhysicsAddr_` 必须与服务端的 `PhysicsAddr_` **完全一致**（包括端口）。对于 IPC，双方必须使用相同的服务名（如 `ipc:my_service`）。

**示例**：
- 服务端：`API_Prepare_Service('0.0.0.0', '127.0.0.1:9898')` → 绑定所有接口，公布地址为 `127.0.0.1:9898`（仅本地可连）。
- 客户端：`API_Prepare_Client('127.0.0.1:9898', app)` → 连接 `127.0.0.1:9898`。

所有地址字符串均为 **UTF-8**。

---

### 7.2 `API_Reset_Prepare`

```pascal
procedure API_Reset_Prepare(); cdecl;
```

**功能**：清除所有之前准备的网络服务/客户端配置。在重新配置前调用。

**线程安全**：✅

---

### 7.3 `API_Prepare_Service`

```pascal
function API_Prepare_Service(ListeningAddr_, PhysicsAddr_: PAnsiChar): Integer; cdecl;
```

**功能**：准备一个服务端监听器。可多次调用以启动多个服务。

**参数**：
- `ListeningAddr_`：本地绑定地址（如 `"0.0.0.0:9898"` 或 `"ipc:my_service"`，**UTF-8**）。
- `PhysicsAddr_`：对外公布的地址（客户端将使用此地址连接，**UTF-8**）。

**返回值**：一个内部标签（`Tag_Seed`），通常可忽略。

**线程安全**：✅

---

### 7.4 `API_Prepare_Client`

```pascal
function API_Prepare_Client(PhysicsAddr_: PAnsiChar; appHnd: TAppHnd): Integer; cdecl;
```

**功能**：准备一个客户端连接。若提供了 `appHnd`，该应用会在连接成功后自动注册到服务端。

**参数**：
- `PhysicsAddr_`：远程服务地址（与 `API_Prepare_Service` 的公布地址一致，**UTF-8**）。
- `appHnd`：要暴露的应用句柄；若为 `nil`，则客户端仅作为消费者。

**返回值**：内部标签（可忽略）。

**线程安全**：✅

**注意**：客户端会在断线后自动重连，并重新注册应用。

---

### 7.5 `API_Prepare_Done`

```pascal
function API_Prepare_Done: Integer; cdecl;
```

**功能**：启动 C4 网络框架，阻塞直到所有准备的服务/客户端初始化完成。之后才能进行远程调用。

**返回值**：`1` 成功，`0` 失败。错误信息会输出到控制台（默认启用 `ConsoleOutput`），也可通过配置 `.api-tool.ini` 文件调整日志行为。

**重要**：
- 只能调用一次，除非中间调用了 `API_Exit_MainThread` 或 `API_shutdown` 重置状态。
- 重复调用而未重置会导致未定义行为。
- 该函数会启动一个模拟主线程，持续运行网络事件循环。

**线程安全**：✅ 但建议仅从主线程调用。

---

### 7.6 `API_Exit_MainThread`

```pascal
procedure API_Exit_MainThread; cdecl;
```

**功能**：通知模拟主线程退出，停止网络事件循环。资源不会自动释放，需继续调用 `API_shutdown`。

**线程安全**：✅

**建议顺序**：先 `API_Exit_MainThread`，再 `API_shutdown`，确保优雅退出。

---

## 8. 远程调用与通知

### 8.1 `API_Call`

```pascal
function API_Call(appName: PAnsiChar; Param: TDataHnd; Timeout_: UInt64): TDataHnd; cdecl;
```

**功能**：同步调用远程应用 `appName` 的 API。阻塞直到收到响应或超时。

**参数**：
- `appName`：目标应用名称（区分大小写，**UTF-8**）。
- `Param`：输入数据句柄（API 名称和参数）。库会克隆数据，调用者仍需释放原句柄。
- `Timeout_`：超时（毫秒），`0` 表示无限等待（慎用）。

**返回值**：**新句柄，永远非 `nil`**。若调用成功，句柄大小 > 0；若超时或失败，句柄大小为 0。**调用者必须始终释放返回的句柄**（即使大小为 0）。

**线程安全**：✅（完全线程安全）

**注意**：
- 支持本地优化：若目标应用在同一进程内已注册，则直接本地执行，避免网络开销。
- 并发调用的执行顺序不保证（见 2.3 节）。

**示例**：
```pascal
var
  d, res: TDataHnd;
begin
  d := API_Create_DataHnd('add');
  API_WriteBuffer(d, @a, SizeOf(a));
  API_WriteBuffer(d, @b, SizeOf(b));
  res := API_Call('CalcService', d, 5000);
  API_Free_DataHnd(d);
  if API_GetSize(res) > 0 then
  begin
    // 处理结果
  end;
  API_Free_DataHnd(res); // 必须释放
end;
```

---

### 8.2 `API_Notify`

```pascal
procedure API_Notify(appName: PAnsiChar; Param: TDataHnd); cdecl;
```

**功能**：发送单向通知，不等待响应。尽力送达。

**参数**：
- `appName`：目标应用名称（**UTF-8**）。
- `Param`：输入数据句柄（库会克隆，调用者仍需释放）。

**线程安全**：✅

---

### 8.3 `API_SetOption` — 运行时动态调整全局配置（新增）

```pascal
procedure API_SetOption(Option, Value: PAnsiChar);
```

**功能**：在运行时动态调整 API Hub 框架的全局配置选项。所有更改对后续操作**立即生效**（除非另有说明）。该函数允许您在不修改 `.ini` 文件且不重启应用的情况下进行运行时调优。

**参数**：
- `Option`：配置键（**UTF-8** 编码，不区分大小写，支持别名）。
- `Value`：新值（**UTF-8** 编码）。对于布尔选项，接受 `"True"`/`"False"`、`"1"`/`"0"`、`"Yes"`/`"No"`。

**返回值**：无。未知选项被**静默忽略**（不报错，不输出日志）。

**线程安全**：✅（所有选项的修改都是原子性的）

---

#### 8.3.1 支持的选项详解

| 选项键（主名） | 别名 | 值类型 | 说明 |
|---------------|------|--------|------|
| `password` | `passwd` | 字符串 | **设置 C4 P2PVM 认证令牌**。该密码用于**所有新建的 P2PVM 连接**（现有连接不受影响）。**服务端和客户端必须匹配**，否则握手失败。日志中会以掩码（`*` 和 `**`）显示，避免密码泄露。 |
| `Quiet` | — | 布尔 | 启用/禁用静默模式。`True` 时抑制大多数调试日志输出，`False` 时输出详细日志。 |
| `External_Conf_Auto_Save` | `Conf_Auto_Save` | 布尔 | 启用/禁用程序退出时自动保存当前配置到 `.api-tool.ini` 文件。默认 `True`。设为 `False` 可防止配置被持久化（适用于测试环境）。 |
| `Wait_Connection_ReadyOk` | `Wait_API_Prepare_Done`、`API_Prepare_Done_Wait`、`WaitConnect`、`Wait_Ready`、`WaitReady` | 布尔 | **🔴 重要：部署场景关键选项**。控制 `API_Prepare_Done` 是否**阻塞等待所有客户端连接就绪**。<br>• `True`（默认）：`API_Prepare_Done` 会轮询所有客户端，直到它们全部在线并完成应用注册，或超时（由 `Wait_Connection_Timeout` 控制）。<br>• `False`：`API_Prepare_Done` 立即返回，**不等待客户端连接**。客户端会在服务端上线后**自动重连**（断线重连机制）。<br>**部署建议**：在大型分布式部署中，服务端和客户端可能不同时启动。设置 `False` 可让服务端先行启动，客户端稍后自动接入，无需人工干预。 |
| `Wait_Connection_Timeout` | `Wait_TimeOut`、`API_Prepare_Done_TimeOut`、`WaitTimeOut` | 整数（毫秒） | 当 `Wait_Connection_ReadyOk = True` 时的最大等待时间。超时后 `API_Prepare_Done` 返回（即使部分客户端未就绪）。默认 `30000`（30 秒）。 |
| `ShowThreadID` | `ShowThread`、`Show_Thread` | 布尔 | 控制状态日志（`DoStatus`）是否显示线程 ID。`True` 时每条日志前显示 `[线程ID]`。 |
| `ConsoleOutput` | `Console_Output` | 布尔 | 启用/禁用控制台（stdout/stderr）日志输出。在库模式下（DLL/共享库）默认强制为 `True`。 |
| `IPC_Serv_ThreadCount` | `IPC_ThreadCount`、`IPC_Server_ThreadCount` | 整数 | IPC 服务线程池大小。影响 `TZNet_Server_IPC` 处理并发请求的能力。**立即生效**，影响后续创建的 IPC 连接。默认 `4`。 |
| `IPC_Serv_MaxQueueLength` | `IPC_MaxQueueLength`、`IPC_Server_MaxQueueLength` | 整数 | IPC 消息队列最大长度。超过此阈值时，新消息可能被丢弃或阻塞。默认 `4096`。 |
| `IPC_Serv_MaxMsgSize` | `IPC_MaxMsgSize`、`IPC_Server_MaxMsgSize` | 整数（字节） | 单条 IPC 消息的最大大小。超过此大小的消息会被拒绝，防止内存耗尽。默认 `32768`（32 KB）。 |

---

#### 8.3.2 典型使用场景

**场景 1：安全加固 —— 动态更换认证密码**

```pascal
// 在建立关键 P2PVM 连接前，动态设置一次性令牌
API_SetOption('password', 'one_time_token_xyz');
// 后续新建的连接将使用此令牌
```

**场景 2：大型部署 —— 服务端先行启动，客户端后接入**

```pascal
// 服务端：不等待客户端就绪，直接启动
API_SetOption('Wait_Connection_ReadyOk', 'False');
API_Prepare_Service('0.0.0.0', '192.168.1.100:9898');
API_Prepare_Done;  // 立即返回，不阻塞

// 客户端：稍后启动，自动连接
API_SetOption('Wait_Connection_ReadyOk', 'True');
API_Prepare_Client('192.168.1.100:9898', app);
API_Prepare_Done;  // 等待连接就绪
```

**场景 3：运维调试 —— 临时开启详细日志**

```pascal
// 开启详细日志以排查连接问题
API_SetOption('ConsoleOutput', 'True');
API_SetOption('ShowThreadID', 'True');
// 排查完毕后恢复
API_SetOption('ConsoleOutput', 'False');
API_SetOption('ShowThreadID', 'False');
```

**场景 4：性能调优 —— 提高 IPC 并发能力**

```pascal
// 在高并发场景下增加 IPC 线程数
API_SetOption('IPC_Serv_ThreadCount', '8');
API_SetOption('IPC_Serv_MaxQueueLength', '8192');
```

---

#### 8.3.3 注意事项

- **无返回值**：调用者无法获知选项是否被识别或值是否合法。例如传入负数给 `IPC_Serv_ThreadCount`，会被 `EStrToInt` 解析，可能导致底层库异常。
- **密码掩码**：虽然隐藏了密码原文，但掩码长度可能暴露密码长度，存在细微信息泄露风险。
- **选项生效时机**：
  - `password`：仅影响**新建连接**，已建立的连接不受影响。
  - `Wait_Connection_ReadyOk` / `Wait_Connection_Timeout`：仅在 `API_Prepare_Done` 执行前设置有效；启动后修改无影响。
  - IPC 相关参数：影响**新创建的 IPC 服务/客户端**，已存在的连接不受影响。
- **静默忽略**：传入未知选项不会报错，建议在代码中记录日志以便追踪。

---

## 9. 关闭与清理

### 9.1 `API_shutdown`

```pascal
procedure API_shutdown; cdecl;
```

**功能**：彻底关闭整个框架：停止服务、断开所有客户端、释放内部资源。之后可重新调用准备函数重新初始化。

**内部行为**：它会调用 `API_Exit_MainThread` 并清理 IPC 和线程池。

**线程安全**：✅ 但通常由主线程调用。

**建议**：先显式调用 `API_Exit_MainThread`，再调用 `API_shutdown`，确保顺序清理。

---

## 10. 完整示例（服务端 + 客户端）

### 10.1 服务端（注册 add 和 echo）

```pascal
program CalcServer;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  z_api_hubtool_import;

procedure AddCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
var
  a, b, sum: Integer;
begin
  if API_ReadBuffer(Input, @a, SizeOf(a)) <> SizeOf(a) then Exit;
  if API_ReadBuffer(Input, @b, SizeOf(b)) <> SizeOf(b) then Exit;
  sum := a + b;
  API_WriteBuffer(Output, @sum, SizeOf(sum));
end;

procedure EchoCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
var
  sz: Int64;
  buf: PByte;
begin
  sz := API_GetSize(Input);
  if sz > 0 then
  begin
    buf := GetMemory(sz);
    try
      API_SetPos(Input, 0);
      API_ReadBuffer(Input, buf, sz);
      API_WriteBuffer(Output, buf, sz);
    finally
      FreeMemory(buf);
    end;
  end;
end;

var
  app: TAppHnd;
begin
  // 创建应用
  app := API_Create_APPHnd('CalcService', 'Calculator');
  if app = nil then
  begin
    Writeln('Create app failed');
    Halt(1);
  end;

  // 注册 API
  API_Reg_Call(app, 'add', 'a+b', nil, @AddCallback);
  API_Reg_Call(app, 'echo', 'Echo', nil, @EchoCallback);

  // 准备网络
  API_Reset_Prepare;
  API_Prepare_Service('0.0.0.0', '127.0.0.1:9898');
  API_Prepare_Service('ipc:calc_service', 'ipc:calc_service');
  API_Prepare_Client('127.0.0.1:9898', app);
  API_Prepare_Client('ipc:calc_service', app);

  // 启动
  if API_Prepare_Done <> 1 then
  begin
    Writeln('Start failed');
    API_Free_APPHnd(app);
    Halt(1);
  end;

  Writeln('Service running. Press Enter to stop.');
  Readln;

  // 清理
  API_Exit_MainThread;
  API_Free_APPHnd(app);
  API_shutdown;
end.
```

### 10.2 客户端（调用 add）

```pascal
program CalcClient;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  z_api_hubtool_import;

var
  app: TAppHnd;
  param, result: TDataHnd;
  a, b, sum: Integer;
begin
  // 纯消费端，不暴露 API
  API_Reset_Prepare;
  API_Prepare_Client('ipc:calc_service', nil);

  if API_Prepare_Done <> 1 then
  begin
    Writeln('Connect failed');
    Halt(1);
  end;

  // 构造请求
  param := API_Create_DataHnd('add');
  a := 10; b := 20;
  API_WriteBuffer(param, @a, SizeOf(a));
  API_WriteBuffer(param, @b, SizeOf(b));

  // 远程调用
  result := API_Call('CalcService', param, 3000);
  API_Free_DataHnd(param);

  if API_GetSize(result) >= SizeOf(Integer) then
  begin
    API_SetPos(result, 0);
    API_ReadBuffer(result, @sum, SizeOf(sum));
    Writeln('10 + 20 = ', sum);
  end
  else
    Writeln('Call failed or timed out');

  API_Free_DataHnd(result);
  API_Exit_MainThread;
  API_shutdown;
end.
```

---

## 11. 常见问题与排错

### 11.1 动态库加载失败

- 确保库文件（`z_api_hub64.dll` 等）位于可执行文件目录或系统 `PATH`。
- 检查位数（32/64）与程序匹配。
- 库会自动搜索可执行目录和系统路径，无需额外设置。

### 11.2 `API_Prepare_Done` 返回 0

- 检查控制台输出，库会打印详细的错误信息（如端口占用、地址格式错误等）。
- 可通过编辑 `<可执行文件名>.api-tool.ini` 中的 `ConsoleOutput` 选项控制日志输出。
- 检查防火墙是否阻止端口。

### 11.3 回调未触发

- 确认应用名和 API 名大小写完全一致（`CalcService` ≠ `calcservice`）。
- 检查客户端是否成功注册（查看控制台状态日志）。
- 确保 `API_Prepare_Done` 成功。

### 11.4 内存泄漏

- 确保每个 `API_Create_DataHnd` 和 `API_Create_APPHnd` 都有对应的释放。
- `API_Call` 返回的句柄即使大小为 0 也必须释放。

### 11.5 多线程注意事项

- 所有函数都可安全并发调用。
- 同一 `TDataHnd` 的写操作应串行化，避免数据竞争。
- 回调在线程池中执行，不可阻塞或调用 `API_Call`/`API_Notify`。

### 11.6 超时问题

- 超时值为 0 表示无限等待，除非必要，否则不要使用，以免永久阻塞。
- 若频繁超时，检查网络延迟或服务端负载，适当增加超时值。

### 11.7 性能调优建议

- **使用 IPC** 进行同机通信，延迟更低。
- **复用数据句柄**：通过 `API_SetPos(0)` 和 `API_SetSize(0)` 重置句柄，而不是反复创建/释放。
- 调整 `.api-tool.ini` 中的 `IPC_Serv_ThreadCount` 和 `IPC_Serv_MaxQueueLength` 提高并发能力。
- 使用 `API_GetBuffer` 进行零拷贝读取，减少数据复制。

### 11.8 多实例部署

- 如需负载均衡，在**不同进程**中启动多个服务端，注册**相同的应用名**。C4 服务网格会自动将客户端请求分发到负载最低的实例。
- 每个服务端实例应使用不同的监听地址（例如不同的 TCP 端口或不同的 IPC 名称），但对外公布的 `PhysicsAddr_` 可以相同。IPC 服务需要不同的服务名（如 `ipc:my_service_1`、`ipc:my_service_2`），客户端连接任意一个即可。

---

## 附录 A：API 速查表

| 函数 | 用途 | 新增 |
|------|------|------|
| `API_Create_DataHnd` | 创建数据句柄（API 名称必须 UTF-8） | |
| `API_Free_DataHnd` | 释放数据句柄 | |
| `API_GetBuffer` | 获取内部缓冲区指针 | |
| `API_WriteBuffer` | 写入数据 | |
| `API_ReadBuffer` | 读取数据 | |
| `API_GetPos` / `API_SetPos` | 获取/设置读写位置 | |
| `API_GetSize` / `API_SetSize` | 获取/设置缓冲区大小 | |
| `API_Create_APPHnd` | 创建应用句柄（名称和描述必须 UTF-8） | |
| `API_Free_APPHnd` | 释放应用句柄 | |
| `API_Reg_Call` | 注册请求-响应 API（字符串必须 UTF-8） | |
| `API_Reg_Notify` | 注册通知 API（字符串必须 UTF-8） | |
| `API_UnReg` | **动态注销 API（触发网络广播，约 3 秒传播）** | ✅ |
| `API_Local_APP_Call` | 本地同步调用 | |
| `API_Local_APP_Notify` | 本地通知 | |
| `API_Reset_Prepare` | 重置网络准备 | |
| `API_Prepare_Service` | 准备服务端（地址必须 UTF-8） | |
| `API_Prepare_Client` | 准备客户端（地址必须 UTF-8） | |
| `API_Prepare_Done` | 启动网络框架 | |
| `API_Exit_MainThread` | 停止事件循环 | |
| `API_Call` | 远程同步调用（应用名 UTF-8） | |
| `API_Notify` | 远程通知（应用名 UTF-8） | |
| `API_SetOption` | **运行时动态调整全局配置（密码、超时、IPC 等）** | ✅ |
| `API_shutdown` | 关闭框架 | |

---

## 更新日志

| 日期 | 版本 | 变更内容 |
|------|------|----------|
| **2026-08-14** | **v2.0** | **新增 `API_UnReg` 动态注销 API 接口，支持热卸载和权限动态调整；新增 `API_SetOption` 运行时配置接口，支持动态调整密码、等待连接控制、IPC 参数等；更新文档目录、附录和示例。** |
| 2026-07-xx | v1.0 | 初始版本，覆盖基础 API 绑定、数据句柄、应用句柄、网络层和远程调用。 |

---

*本文档基于 API Hub Tool 最新版本编写，适用于 Delphi 和 Free Pascal。所有 `PAnsiChar` 字符串参数必须使用 UTF-8 编码并以 null 结尾。如有疑问，请查阅项目文档或检查控制台输出以获取诊断信息。*

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

---

**更新摘要**：

| 项目 | 内容 |
|------|------|
| **更新日期** | 2026-08-14 |
| **新增接口** | `API_UnReg`（5.7 节）、`API_SetOption`（8.3 节） |
| **更新内容** | 1. 第 5 章新增 5.7 节，详细说明 `API_UnReg` 的功能、参数、返回值、网络广播机制和传播延迟<br>2. 第 8 章新增 8.3 节，详细说明 `API_SetOption` 的所有选项（包括 password、Wait_Connection_ReadyOk 等关键选项）<br>3. 附录 A 新增两个函数，并标记为新增<br>4. 目录新增 5.7 和 8.3 章节链接<br>5. 文档末尾新增更新日志表格 |
