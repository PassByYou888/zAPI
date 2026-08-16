# Z.IPC — Pascal IPC 绑定文档（z_ipc 库）

## 1. 概述

`Z.IPC` 是 **z_ipc**（进程间通信库）的 Pascal 绑定，为 Delphi 和 Free Pascal 提供**高性能同机进程通信**能力。它封装了底层的 C API，并提供面向对象的 `TIPCClient` 和 `TIPCServer` 类，让您可以用几行代码实现跨进程的 RPC 调用和通知。

### 1.1 z_ipc 是什么？

z_ipc 是 **zAPI 跨语言 RPC 框架**的进程通信组件，专门解决**同一台机器上多个进程之间的高效数据交换**问题。它基于 **共享内存 + 消息队列** 实现，具备以下特点：

- **极低延迟**：同机通信延迟 < 1ms，比 Unix Domain Socket 快 150 倍（实测）
- **高吞吐**：单机可支撑 10,000+ 请求/秒
- **零拷贝**：大数据通过共享内存传输，无需序列化/反序列化
- **跨语言**：基于 C ABI，支持 C++、Python、Go、Rust、Java、C#、Pascal 等
- **零配置**：合理默认值，开箱即用
- **自动生命周期管理**：RAII 风格，不用手动清理共享内存

### 1.2 本单元在 Z‑framework 中的位置

- `Z.IPC.API` – 直接映射 z_ipc C 库的导出函数、类型和常量（底层）
- `Z.IPC.Helper` – 面向对象的封装，提供 `TIPCClient` / `TIPCServer` 类，更符合 Pascal 习惯

> **建议**：大多数场景使用 `Z.IPC.Helper`，它自动管理句柄、缓冲区和错误检查。如需更细粒度的控制，可直接使用 `Z.IPC.API`。

---

## 2. 仓库与源码

**项目地址**：[https://github.com/PassByYou888/zIPC](https://github.com/PassByYou888/zIPC)

仓库包含：
- C++ 源码（`z_ipc_api.cpp`、`z_ipc_server_impl.cpp` 等）
- 构建脚本（`build_on_linux.sh`、`CMakeLists.txt`）
- Pascal 绑定单元（`Z.IPC.API.pas` 和 `Z.IPC.Helper.pas`）
- 预编译动态库（Windows 版 `z_ipc_32.dll` / `z_ipc_64.dll`）
- 文档（`readme.md`、`BUILD_LINUX.md`）

> 注意：该仓库是独立的 IPC 仓库，不包含 zAPI 其他部分。如需完整的跨语言 RPC 框架，请访问 [zAPI](https://github.com/PassByYou888/zAPI)。

---

## 3. 编译与部署

### 3.1 获取动态库

#### Windows
仓库已提供预编译 DLL：
- 32 位：`z_ipc_32.dll`
- 64 位：`z_ipc_64.dll`

将对应 DLL 放在可执行文件所在目录或系统 PATH 中即可。

#### Linux
使用一键构建脚本 `build_on_linux.sh`：
```bash
chmod +x build_on_linux.sh
./build_on_linux.sh
```
脚本会自动：
- 下载并编译 Boost 1.83.0（仅 `date_time` 库）
- 生成 CMake 工程并编译 z_ipc
- 输出 `build/libz_ipc.so`

依赖：g++、make、cmake（≥3.15）、tar、python（用于 Boost 构建）。详细说明见仓库的 `BUILD_LINUX.md`。

#### macOS / BSD
暂未提供预编译包，可使用 CMake 自行编译（需安装 Boost）。

### 3.2 在 Pascal 项目中引用

1. 将 `Z.IPC.API.pas` 和 `Z.IPC.Helper.pas` 复制到项目源码目录，或添加到搜索路径。
2. 在需要使用 IPC 的单元中 `uses Z.IPC.Helper;`（或 `Z.IPC.API;`）。
3. 确保动态库位于可执行文件的加载路径中。

单元会在初始化时自动加载动态库，若加载失败会抛出异常（`RaiseInfo`）。您也可以手动调用 `LoadIPCLibrary` 检查是否成功。

---

## 4. 核心 API 说明

### 4.1 错误码（Z.IPC.API）

所有 C 函数返回整数错误码，定义如下：

| 常量 | 值 | 说明 |
|------|----|------|
| `IPC_OK` | 0 | 操作成功 |
| `IPC_ERR_OPEN` | -1 | 无法打开队列（不存在或权限不足） |
| `IPC_ERR_SIZE` | -2 | 无效大小（过大或零数据） |
| `IPC_ERR_SEND` | -3 | 发送消息失败 |
| `IPC_ERR_RECEIVE` | -4 | 接收消息失败 |
| `IPC_ERR_MEMORY` | -5 | 内存分配失败 |
| `IPC_ERR_PERMISSION` | -6 | 权限不足 |
| `IPC_ERR_TIMEOUT` | -7 | 操作超时（RPC 调用） |
| `IPC_ERR_TYPE` | -8 | 类型不匹配（保留） |
| `IPC_ERR_NOT_FOUND` | -9 | 处理器或队列未找到 |
| `IPC_ERR_BUSY` | -10 | 资源忙碌（例如处理器已注册） |
| `IPC_ERR_INVAL` | -11 | 无效参数（空指针、空名称等） |
| `IPC_ERR_UNKNOWN` | -99 | 未知错误 |

### 4.2 类型

| 类型 | 说明 |
|------|------|
| `TIPCServerHandle` | 服务端句柄（整数，非零有效） |
| `TIPCClientHandle` | 客户端句柄（整数，非零有效） |
| `TIPCServerConfig` | 服务端配置记录（packed） |
| `TIPCBinaryReplyHandler` | RPC 响应回调（cdecl） |
| `TIPCBinaryNotifyHandler` | 通知回调（cdecl） |

### 4.3 核心 C 函数（低级）

**服务端**：
- `ipc_server_create(queue_name, thread_count)`
- `ipc_server_create_ex(queue_name, cfg)`
- `ipc_server_destroy(handle)`
- `ipc_server_register_binary_reply(handle, name, handler, trigger)`
- `ipc_server_register_binary_notify(handle, name, handler, trigger)`
- `ipc_server_send_notify_binary(handle, client_resp_queue, func_name, data, size)`

**客户端**：
- `ipc_client_create()`
- `ipc_client_destroy(handle)`
- `ipc_client_connect(handle, queue_name)`
- `ipc_client_disconnect(handle)`
- `ipc_client_get_resp_queue_name(handle)`
- `ipc_client_register_binary_notify(handle, name, handler, trigger)`
- `ipc_client_call_binary(handle, func_name, send_data, send_size, out outData, out outSize)`
- `ipc_client_notify_binary(handle, func_name, send_data, send_size)`
- `ipc_client_set_timeout(handle, milliseconds)`
- `ipc_client_is_connected(handle)`

**内存管理**：
- `ipc_alloc(size)` – 分配跨语言共享内存
- `ipc_free(ptr)` – 释放

**工具**：
- `ipc_Set_Status_handler(handler)` – 安装日志回调
- `ipc_cleanup(queue_name)` – 强制清理指定队列
- `ipc_shutdown()` – 关闭所有 IPC 资源

### 4.4 面向对象封装（Z.IPC.Helper）

#### TIPCClient

| 方法 | 说明 |
|------|------|
| `constructor Create` | 创建客户端，自动加载库 |
| `destructor Destroy` | 断开并释放句柄 |
| `function Connect(const QueueName: string): Boolean` | 连接到服务端队列 |
| `procedure Disconnect` | 断开连接 |
| `function GetRespQueueName: string` | 获取本客户端的响应队列名 |
| `function RegisterBinaryNotify(...) : Boolean` | 注册通知处理器 |
| `function UnregisterBinaryNotify(...) : Boolean` | 取消注册 |
| `function CallBinary(...) : Integer` | 同步 RPC 调用（多种重载） |
| `function NotifyBinary(...) : Integer` | 发送通知（多种重载） |
| `procedure SetTimeout(Milliseconds: Integer)` | 设置 RPC 超时 |
| `function IsConnected: Boolean` | 是否已连接 |
| `property Handle` | 原始 C 句柄 |

#### TIPCServer

| 方法 | 说明 |
|------|------|
| `constructor Create` | 创建服务端 |
| `destructor Destroy` | 停止并释放 |
| `function Start(const QueueName: string): Boolean` | 用默认配置启动 |
| `function Start(const QueueName: string; const Config: TIPCServerConfig): Boolean` | 自定义配置启动 |
| `function StartEx(...) : Boolean` | 显式参数启动 |
| `procedure Stop` | 停止服务 |
| `function RegisterBinaryHandler(...) : Boolean` | 注册 RPC 处理器 |
| `function UnregisterBinaryHandler(...) : Boolean` | 取消注册 |
| `function RegisterBinaryNotify(...) : Boolean` | 注册通知处理器 |
| `function UnregisterBinaryNotify(...) : Boolean` | 取消注册 |
| `function SendNotifyBinary(...) : Integer` | 向客户端发送通知（多种重载） |
| `property Started` | 是否正在运行 |
| `property Handle` | 原始 C 句柄 |

---

## 5. 使用示例

### 5.1 服务端（Pascal）

```pascal
program ServerDemo;

{$APPTYPE CONSOLE}

uses
  SysUtils, Z.Core, Z.IPC.Helper;

var
  Server: TIPCServer;
  Data: TMem64;

  // RPC 处理器：回显请求数据
  procedure EchoHandler(trigger: Pointer; data: Pointer; size: TSize_t;
    out outData: Pointer; out outSize: TSize_t); cdecl;
  begin
    if size = 0 then
    begin
      outData := nil;
      outSize := 0;
      Exit;
    end;
    // 分配回复缓冲区（必须用 ipc_alloc）
    outData := ipc_alloc(size);
    if outData <> nil then
    begin
      Move(data^, outData^, size);
      outSize := size;
    end
    else
      outSize := 0;
  end;

begin
  Server := TIPCServer.Create;
  try
    // 启动服务，队列名为 'echo_queue'
    if not Server.Start('echo_queue') then
    begin
      WriteLn('Failed to start server');
      Exit;
    end;
    WriteLn('Server started on queue: echo_queue');

    // 注册 RPC 处理器
    if Server.RegisterBinaryHandler('echo', EchoHandler, nil) then
      WriteLn('Handler "echo" registered');

    WriteLn('Press Enter to stop...');
    ReadLn;
  finally
    Server.Free;  // 自动停止
  end;
end.
```

### 5.2 客户端（Pascal）

```pascal
program ClientDemo;

{$APPTYPE CONSOLE}

uses
  SysUtils, Z.Core, Z.MemoryStream, Z.IPC.Helper;

var
  Client: TIPCClient;
  Req, Resp: TMem64;
  ResultCode: Integer;
begin
  Client := TIPCClient.Create;
  try
    // 连接到服务端队列
    if not Client.Connect('echo_queue') then
    begin
      WriteLn('Failed to connect to server');
      Exit;
    end;
    WriteLn('Connected. Response queue: ', Client.GetRespQueueName);

    // 准备请求数据
    Req := TMem64.Create;
    Resp := TMem64.Create;
    try
      Req.WriteString('Hello from Pascal!');
      Req.Position := 0;

      // 同步 RPC 调用
      ResultCode := Client.CallBinary('echo', Req, Resp);
      if ResultCode = IPC_OK then
      begin
        Resp.Position := 0;
        WriteLn('Reply: ', Resp.ReadString);
      end
      else
        WriteLn('RPC failed with code: ', ResultCode);
    finally
      Req.Free;
      Resp.Free;
    end;
  finally
    Client.Free;
  end;
  ReadLn;
end.
```

### 5.3 使用 TBytes 重载

```pascal
var
  InData, OutData: TBytes;
  Code: Integer;
begin
  SetLength(InData, 10);
  // 填充 InData ...
  Code := Client.CallBinary('process', InData, OutData);
  if Code = IPC_OK then
    // 使用 OutData
end;
```

### 5.4 通知（服务端 → 客户端）

**客户端注册通知**：
```pascal
procedure MyNotify(trigger: Pointer; data: Pointer; size: TSize_t); cdecl;
begin
  WriteLn('Received notification of ', size, ' bytes');
end;

...
Client.RegisterBinaryNotify('status_update', MyNotify, nil);
```

**服务端发送通知**：
```pascal
var
  NotifyData: TMem64;
begin
  NotifyData := TMem64.Create;
  NotifyData.WriteString('Server is busy');
  Server.SendNotifyBinary(ClientRespQueue, 'status_update', NotifyData);
  NotifyData.Free;
end;
```

---

## 6. 性能与调优

- **延迟**：同机 < 1ms（实测在 2.5GHz Xeon 上，RPC 往返约 0.3ms）
- **吞吐**：10,000+ 请求/秒（使用 4 个工作线程）
- **配置建议**：
  - `max_queue_length`：根据峰值并发设置，默认 1000 通常足够
  - `max_msg_size`：控制消息的最大尺寸（不含大数据），默认 1024 字节
  - `thread_count`：设为 0 自动检测 CPU 核心数，通常最优
- **大数据**：超过 `max_msg_size` 的数据自动通过共享内存传输，无需特殊处理

---

## 7. 注意事项

- **线程安全**：`TIPCClient` 和 `TIPCServer` 实例不是线程安全的，每个实例应从单一线程使用，或外部加锁。
- **回调上下文**：回调在 C++ 工作线程中执行，**禁止阻塞**（如 Sleep、等待同步对象），否则会阻塞整个 IPC 服务。
- **内存分配**：在 RPC 处理器中，`outData` 必须通过 `ipc_alloc` 分配，并在调用方用 `ipc_free` 释放。Pascal 的 `TIPCClient.CallBinary` 会自动释放。
- **队列名**：区分大小写，建议使用字母数字和下划线。
- **清理**：程序退出前确保所有 `TIPCServer` 和 `TIPCClient` 对象被释放，或调用 `ipc_shutdown`。

---

## 8. 与其他通信方式对比

| 方案 | 延迟 | 跨语言 | 配置 | 适用场景 |
|------|------|--------|------|----------|
| **Z.IPC** | **< 1 ms** | ✅ 原生 | 零配置 | **同机高性能通信** |
| Unix Domain Socket | 1-2 ms | 需封装 | 中 | 同机进程通信 |
| TCP 回环 | 2-3 ms | ✅ 通用 | 低 | 开发测试 |
| gRPC | 5-10 ms | ✅ 通用 | 高 | 微服务标准方案 |
| 原始共享内存 | 0.1-0.5 ms | ❌ 手写 | 极高 | 极致定制 |

**结论**：同机通信场景，Z.IPC 是性能与易用性的最佳平衡。

---

## 9. 更多资源

- **zIPC 仓库**：[https://github.com/PassByYou888/zIPC](https://github.com/PassByYou888/zIPC)
- **zAPI 跨语言 RPC 框架**：[https://github.com/PassByYou888/zAPI](https://github.com/PassByYou888/zAPI)
- **Boost.Interprocess 文档**：[https://www.boost.org/doc/libs/1_83_0/doc/html/interprocess.html](https://www.boost.org/doc/libs/1_83_0/doc/html/interprocess.html)

---

*文档版本 1.0 – 基于 Z.IPC.API、Z.IPC.Helper 及 zIPC 仓库 readme 整理。*