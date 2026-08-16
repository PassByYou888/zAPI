# Z.IPC.Helper — 面向对象的 IPC 客户端/服务器封装

## 1. 概述

`Z.IPC.Helper` 是 `Z.IPC.API` 的高层封装，提供了 **`TIPCClient`** 和 **`TIPCServer`** 两个类，让你能够用更符合 Pascal 习惯的面向对象方式使用 z_ipc 进程间通信库。

- **自动资源管理**：创建、连接、断开、销毁全自动，无需手动调用 `ipc_client_destroy` 等底层函数。
- **多种数据类型重载**：支持 `TMem64`、`TBytes` 和原始指针，轻松传递二进制数据。
- **简化回调注册**：直接注册 Pascal 回调过程（`cdecl`），框架自动处理 C 与 Pascal 的调用约定。
- **异常友好**：构造函数加载库失败时抛出异常（`RaiseInfo`），便于集中错误处理。

---

## 2. 设计目标

- **降低使用门槛**：不需要理解 C 句柄、内存分配、队列名称等底层细节。
- **提高代码可读性**：用 `Client.CallBinary()` 替代复杂的 `ipc_client_call_binary`。
- **保持高性能**：所有方法最终都直接调用 C API，无额外开销。
- **兼容性**：同时支持 Delphi 和 Free Pascal。

---

## 3. 类参考

### 3.1 TIPCClient

客户端类，负责连接到服务端，发起 RPC 调用和通知，并接收服务端下发的通知。

#### 构造函数与析构

| 方法 | 说明 |
|------|------|
| `constructor Create;` | 创建客户端实例。自动调用 `LoadIPCLibrary`，若库加载失败则抛出异常。 |
| `destructor Destroy; override;` | 销毁客户端，自动断开连接并释放底层 C 句柄。 |

#### 连接管理

| 方法 | 说明 |
|------|------|
| `function Connect(const QueueName: string): Boolean;` | 连接到服务端的主队列。若已连接则先断开。成功返回 `True`。 |
| `procedure Disconnect;` | 主动断开与服务器的连接。 |
| `function IsConnected: Boolean;` | 返回当前是否已连接。 |
| `function GetRespQueueName: string;` | 获取此客户端的专用响应队列名称（服务端可用它向此客户端发送通知）。 |

#### RPC 调用（同步）

| 方法 | 说明 |
|------|------|
| `function CallBinary(const FuncName: string; InData, OutData: TMem64): Integer;` | 使用 `TMem64` 作为输入和输出流。 |
| `function CallBinary(const FuncName: string; const Data: Pointer; Size: Integer; out OutData: TByteArray): Integer;` | 输入为原始指针+大小，输出为 `TBytes`。 |
| `function CallBinary(const FuncName: string; const Data: TByteArray; out OutData: TByteArray): Integer;` | 输入输出均为 `TBytes`。 |

所有 `CallBinary` 均返回错误码（`IPC_OK` 表示成功），输出参数在成功时填充数据。

#### 通知（单向）

| 方法 | 说明 |
|------|------|
| `function NotifyBinary(const FuncName: string; InData: TMem64): Integer;` | 使用 `TMem64` 作为通知负载。 |
| `function NotifyBinary(const FuncName: string; const Data: Pointer; Size: Integer): Integer;` | 原始指针形式。 |
| `function NotifyBinary(const FuncName: string; const Data: TByteArray): Integer;` | `TBytes` 形式。 |

通知不等待回应，返回立即成功或失败。

#### 通知处理器注册

| 方法 | 说明 |
|------|------|
| `function RegisterBinaryNotify(const Name: string; Handler: TIPCBinaryNotifyHandler; Trigger: Pointer): Boolean;` | 注册一个服务端→客户端的通知处理器。同名只能注册一个。 |
| `function UnregisterBinaryNotify(const Name: string): Boolean;` | 取消注册。 |

#### 其他

| 方法 | 说明 |
|------|------|
| `procedure SetTimeout(Milliseconds: Integer);` | 设置 RPC 调用超时（毫秒）。 |
| `property Connected: Boolean read FConnected;` | 同 `IsConnected`。 |
| `property Handle: TIPCClientHandle read FHandle;` | 原始 C 句柄（高级用途）。 |

---

### 3.2 TIPCServer

服务端类，创建消息队列，注册 RPC 处理器和通知处理器，并向客户端发送通知。

#### 构造函数与析构

| 方法 | 说明 |
|------|------|
| `constructor Create;` | 创建服务端实例，自动加载库。 |
| `destructor Destroy; override;` | 停止服务并释放资源。 |

#### 启动与停止

| 方法 | 说明 |
|------|------|
| `function Start(const QueueName: string): Boolean;` | 用默认配置启动（线程数=0自动，队列长度=1000，消息大小=1024）。 |
| `function Start(const QueueName: string; const Config: TIPCServerConfig): Boolean;` | 使用自定义配置记录启动。 |
| `function StartEx(const QueueName: string; ThreadCount: Integer; MaxQueueLength, MaxMsgSize: TSize_t): Boolean;` | 显式指定所有参数。 |
| `procedure Stop;` | 停止服务，移除队列。 |

#### RPC 处理器注册

| 方法 | 说明 |
|------|------|
| `function RegisterBinaryHandler(const Name: string; Handler: TIPCBinaryReplyHandler; Trigger: Pointer): Boolean;` | 注册一个 RPC 函数，客户端可通过 `CallBinary` 调用。 |
| `function UnregisterBinaryHandler(const Name: string): Boolean;` | 取消注册。 |

#### 通知处理器注册（客户端→服务端）

| 方法 | 说明 |
|------|------|
| `function RegisterBinaryNotify(const Name: string; Handler: TIPCBinaryNotifyHandler; Trigger: Pointer): Boolean;` | 注册一个通知处理器，接收来自客户端的通知。 |
| `function UnregisterBinaryNotify(const Name: string): Boolean;` | 取消注册。 |

#### 发送通知给客户端

| 方法 | 说明 |
|------|------|
| `function SendNotifyBinary(const ClientRespQueue, FuncName: string; InData: TMem64): Integer;` | 通过 `TMem64` 发送。 |
| `function SendNotifyBinary(const ClientRespQueue, FuncName: string; const Data: Pointer; Size: Integer): Integer;` | 原始指针。 |
| `function SendNotifyBinary(const ClientRespQueue, FuncName: string; const Data: TByteArray): Integer;` | `TBytes` 形式。 |

`ClientRespQueue` 是客户端的响应队列名（通过 `TIPCClient.GetRespQueueName` 获得）。

#### 属性

| 属性 | 说明 |
|------|------|
| `property Started: Boolean read FStarted;` | 服务器是否正在运行。 |
| `property Handle: TIPCServerHandle read FHandle;` | 原始 C 句柄。 |

---

## 4. 回调函数编写规则

所有回调（`TIPCBinaryReplyHandler` 和 `TIPCBinaryNotifyHandler`）都运行在 C++ 工作线程中，必须遵守以下规则：

- **声明为 `cdecl`**：
  ```pascal
  procedure MyHandler(trigger: Pointer; data: Pointer; size: TSize_t); cdecl;
  ```
- **不要阻塞**：禁止在回调中执行长时间操作（如 Sleep、等待事件、大量计算），否则会阻塞整个服务。
- **内存分配**：在 `TIPCBinaryReplyHandler` 中，必须用 `ipc_alloc` 分配 `outData` 内存，框架会在发送后自动调用 `ipc_free`。
  ```pascal
  outData := ipc_alloc(size);
  Move(data^, outData^, size);
  outSize := size;
  ```
- **异常安全**：回调中若发生异常，应自行捕获并处理，不要将异常传播到 C 代码。

---

## 5. 完整示例

### 5.1 服务端（带 RPC + 通知）

```pascal
program ServerDemo;

{$APPTYPE CONSOLE}

uses
  SysUtils, Z.Core, Z.IPC.Helper, Z.MemoryStream;

var
  Server: TIPCServer;

// RPC 处理器：回显
procedure EchoHandler(trigger: Pointer; data: Pointer; size: TSize_t;
  out outData: Pointer; out outSize: TSize_t); cdecl;
begin
  if size = 0 then
  begin
    outData := nil;
    outSize := 0;
    Exit;
  end;
  outData := ipc_alloc(size);
  if outData <> nil then
  begin
    Move(data^, outData^, size);
    outSize := size;
  end
  else
    outSize := 0;
end;

// 通知处理器（客户端发给服务端）
procedure NotifyHandler(trigger: Pointer; data: Pointer; size: TSize_t); cdecl;
begin
  WriteLn('Server received notification of ', size, ' bytes');
end;

begin
  Server := TIPCServer.Create;
  try
    if not Server.Start('test_queue') then
    begin
      WriteLn('Failed to start server');
      Exit;
    end;
    WriteLn('Server started on "test_queue"');

    Server.RegisterBinaryHandler('echo', EchoHandler, nil);
    Server.RegisterBinaryNotify('client_notify', NotifyHandler, nil);

    WriteLn('Press Enter to stop server...');
    ReadLn;
  finally
    Server.Free;
  end;
end.
```

### 5.2 客户端（调用 RPC + 发送通知 + 注册接收通知）

```pascal
program ClientDemo;

{$APPTYPE CONSOLE}

uses
  SysUtils, Z.Core, Z.IPC.Helper, Z.MemoryStream;

var
  Client: TIPCClient;
  Req, Resp: TMem64;
  Code: Integer;

// 服务端→客户端的通知处理器
procedure ServerNotify(trigger: Pointer; data: Pointer; size: TSize_t); cdecl;
begin
  WriteLn('Client received notification of ', size, ' bytes');
end;

begin
  Client := TIPCClient.Create;
  try
    if not Client.Connect('test_queue') then
    begin
      WriteLn('Connect failed');
      Exit;
    end;
    WriteLn('Connected, response queue: ', Client.GetRespQueueName);

    // 注册接收服务端通知
    Client.RegisterBinaryNotify('server_notify', ServerNotify, nil);

    // 发送 RPC
    Req := TMem64.Create;
    Resp := TMem64.Create;
    try
      Req.WriteString('Hello Server');
      Req.Position := 0;
      Code := Client.CallBinary('echo', Req, Resp);
      if Code = IPC_OK then
      begin
        Resp.Position := 0;
        WriteLn('RPC reply: ', Resp.ReadString);
      end
      else
        WriteLn('RPC failed, code: ', Code);

      // 发送通知给服务端
      Req.Clear;
      Req.WriteString('Ping from client');
      Code := Client.NotifyBinary('client_notify', Req);
      if Code = IPC_OK then
        WriteLn('Notify sent successfully');
    finally
      Req.Free;
      Resp.Free;
    end;

    WriteLn('Press Enter to exit...');
    ReadLn;
  finally
    Client.Free;
  end;
end.
```

---

## 6. 错误处理

- 所有 `CallBinary` 和 `NotifyBinary` 方法返回 `Integer` 错误码（参见 `Z.IPC.API` 常量）。应检查返回值。
- `Connect` 和 `Register*` 方法返回布尔值，表示操作成功/失败，具体错误原因可通过返回值或日志查看。
- 构造函数在库加载失败时会抛出异常（`RaiseInfo`），建议在 `try..except` 块中创建。

---

## 7. 线程安全

- **`TIPCClient` 和 `TIPCServer` 不是线程安全的**。每个实例应只在一个线程中使用，或在外部加锁（如 `TCritical`）。
- 回调函数在 C++ 工作线程中执行，它们本身是线程安全的上下文，但如果你在回调中访问共享数据，需要自己加锁。

---

## 8. 性能提示

- **重用对象**：尽量重用 `TMem64` 或 `TBytes` 来减少内存分配。
- **避免小包**：频繁发送极小的数据包（< 100 字节）会增加消息队列开销，建议适当合并。
- **调整超时**：`SetTimeout` 默认值可能为 3 秒，可根据业务调整。
- **线程数**：服务端 `StartEx` 中设置 `ThreadCount=0` 将自动使用 CPU 核心数，通常是最优选择。

---

## 9. 与底层 API 的关系

`Z.IPC.Helper` 是 `Z.IPC.API` 的薄封装，所有方法最终调用 C 函数。如果需要更细粒度的控制（如直接管理内存、自定义队列配置），可以直接使用 `Z.IPC.API`，该单元提供了完整的类型和函数声明。

---

## 10. 更多资源

- **底层 API 文档**：参见 `Z.IPC.API.md`
- **zIPC 仓库**：[https://github.com/PassByYou888/zIPC](https://github.com/PassByYou888/zIPC)
- **zAPI 跨语言框架**：[https://github.com/PassByYou888/zAPI](https://github.com/PassByYou888/zAPI)

---

*文档版本 1.0 – 基于 Z.IPC.Helper.pas 源码及 zIPC 文档整理。*