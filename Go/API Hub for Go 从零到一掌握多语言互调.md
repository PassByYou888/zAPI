# 🐹 API Hub for Go 从零到一掌握多语言互调

**版本：** 2.1（与 ZAPI 核心 v2.1 同步）

---

## 📖 目录

1. [概述：API Hub 是什么](#1-概述api-hub-是什么)
2. [核心概念（必读）](#2-核心概念必读)
3. [环境准备与安装](#3-环境准备与安装)
4. [快速入门 —— 三分钟跑通第一个服务](#4-快速入门--三分钟跑通第一个服务)
5. [数据句柄（DataHnd）详解](#5-数据句柄datahnd详解)
6. [应用与服务端（Server）详解](#6-应用与服务端server详解)
7. [客户端（Client）详解](#7-客户端client详解)
8. [状态与检查 API（新增）](#8-状态与检查-api新增)
9. [动态注销 API](#9-动态注销-api)
10. [运行时配置](#10-运行时配置)
11. [线程安全与回调约束（⚠️ 关键）](#11-线程安全与回调约束-关键)
12. [序列化与自定义载荷](#12-序列化与自定义载荷)
13. [日志与调试](#13-日志与调试)
14. [高级主题](#14-高级主题)
15. [完整示例集](#15-完整示例集)
16. [常见问题与排错](#16-常见问题与排错)
17. [开源与社区](#17-开源与社区)

---

## 1. 概述：API Hub 是什么

API Hub 是一个**基于 C4 分布式服务网格的轻量级 RPC 框架**，它通过一组纯 C 函数（ABI）让不同语言、不同进程、不同机器之间能够**像调用本地函数一样**进行通信。

- **核心 C 动态库**：`z_api_hub64.dll` / `libz_api_hub.so` / `libz_api_hub.dylib`，导出 30 个 API（含 v2.1 新增）。
- **Pascal 绑定**：`z_api_hubtool_import.pas` —— 这是**所有语言绑定的参考实现**，Go 绑定完全遵循其语义。
- **Go 绑定**：基于 `cgo` 封装，提供 `DataHnd`、`Client`、`Server` 等类型，让 Go 开发者无痛接入跨语言 RPC 世界。

**核心价值**：

- ✅ 将任意 Go 函数暴露为远程 API，供 Python/C++/Java/Rust/C#/PHP/Node.js 等语言调用。
- ✅ 用 Go 透明地调用其他语言编写的服务，无需 HTTP、不写 IDL、无需生成桩代码。
- ✅ 自动处理服务发现、负载均衡、断线重连、NAT 穿透。
- ✅ **v2.1 新增**状态与检查 API（`CheckMainThread`, `CheckApp`, `GetStatusNum`, `GetStatus`, `PostStatus`），方便调试和监控。
- ✅ 支持动态注销 API（`Server.Unregister`）和运行时配置（`SetOption`）。

## 2. 核心概念（必读）

在深入代码前，请先理解以下概念，它们与 Pascal 完全对应。

| 概念                    | 说明                                                                                                                              |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| **数据句柄（DataHnd）** | 封装一个 **API 名称** 和一段 **二进制载荷**。所有输入参数和输出结果都通过它传递。API 名称在创建时固定，后续读写只影响载荷。       |
| **应用句柄（AppHnd）**  | 代表一个逻辑应用，可注册多个 API（Call 或 Notify），在网络中具有唯一名称。客户端通过 `应用名 + API 名` 路由请求。                 |
| **Call（请求-响应）**   | 同步调用，发送请求并等待响应。对应 `Call` 函数。                                                                                  |
| **Notify（单向通知）**  | 异步通知，不等待响应。对应 `Notify` 函数。                                                                                        |
| **回调（Callback）**    | 服务端注册的函数，当远程调用到达时执行。**所有回调都在后台线程池中运行**（非 Go 主线程），因此必须遵守线程安全规则（见第 11 节）。 |
| **状态与检查（v2.1）**  | `CheckMainThread`、`CheckApp` 查询框架运行状态；`GetStatusNum`、`GetStatus`、`PostStatus` 提供日志队列访问。                      |
| **线程安全**            | 除少数日志辅助函数外，所有 API 均可并发调用。但单个 DataHnd 的写操作需串行化。                                                    |

## 3. 环境准备与安装

### 3.1 动态库文件

从发布包中获取对应平台的动态库，并将其放置在 Go 可搜索的路径中。

| 平台           | 核心库            | IPC 依赖库（同目录）     |
| -------------- | ----------------- | ------------------------ |
| Windows 64-bit | `z_api_hub64.dll` | `z_ipc_64.dll`           |
| Windows 32-bit | `z_api_hub32.dll` | `z_ipc_32.dll`           |
| Linux / BSD    | `libz_api_hub.so` | `libz_ipc.so`            |
| macOS          | `libz_api_hub.dylib` | `libz_ipc.dylib`（如有） |

### 3.2 Go 包安装

```bash
go get github.com/PassByYou888/zAPI/api_hub
```

### 3.3 验证加载

```go
package main

import (
    "fmt"
    "github.com/PassByYou888/zAPI/api_hub"
)

func main() {
    client, err := api_hub.NewClient()
    if err != nil {
        fmt.Printf("库加载失败: %v\n", err)
        return
    }
    defer client.Close()
    fmt.Println("✅ API Hub 库加载成功")
}
```

## 4. 快速入门 —— 三分钟跑通第一个服务

### 4.1 编写一个简单的加法服务（server.go）

```go
package main

import (
    "fmt"
    "github.com/PassByYou888/zAPI/api_hub"
)

func main() {
    // 创建服务端
    server, err := api_hub.NewServer("CalcService", "A simple calculator")
    if err != nil {
        panic(err)
    }
    defer server.Stop()

    // 注册加法 API
    err = server.RegisterCall("add", "a + b", func(input, output api_hub.DataHnd) {
        // 读取两个整数
        a, _ := api_hub.ReadInt32(input)
        b, _ := api_hub.ReadInt32(input)
        // 写入结果
        _ = api_hub.WriteInt32(output, a+b)
    })
    if err != nil {
        panic(err)
    }

    // 启动服务（使用 IPC，同机通信）
    if err := server.Start("ipc:calc_service"); err != nil {
        panic(err)
    }

    fmt.Println("✅ 服务已启动，按 Ctrl+C 退出...")
    select {} // 阻塞等待
}
```

### 4.2 编写客户端调用（client.go）

```go
package main

import (
    "fmt"
    "github.com/PassByYou888/zAPI/api_hub"
)

func main() {
    client, err := api_hub.NewClient()
    if err != nil {
        panic(err)
    }
    defer client.Close()

    // 准备连接
    client.ResetPrepare()
    if err := client.PrepareClient("ipc:calc_service"); err != nil {
        panic(err)
    }
    ok, err := client.PrepareDone()
    if !ok || err != nil {
        panic(fmt.Errorf("连接失败: %v", err))
    }
    defer client.Shutdown()

    // 构造请求
    param, _ := client.CreateDataHnd("add")
    defer client.FreeDataHnd(param)

    _ = client.WriteInt32(param, 10)
    _ = client.WriteInt32(param, 20)

    // 远程调用
    result, err := client.Call("CalcService", param, 3000)
    if err != nil {
        panic(err)
    }
    defer client.FreeDataHnd(result)

    // 读取结果
    client.SetPos(result, 0)
    sum, _ := client.ReadInt32(result)
    fmt.Printf("📞 10 + 20 = %d\n", sum)
}
```

> **💡 解释**：
>
> - `NewServer("CalcService", ...)` 创建了一个逻辑应用，名称为 `"CalcService"`（区分大小写）。
> - `RegisterCall("add", ...)` 将回调函数注册为远程 API。
> - `server.Start("ipc:calc_service")` 启动服务，监听 IPC 通道。
> - 客户端 `PrepareClient("ipc:calc_service")` 连接到同一 IPC 通道。
> - `client.Call("CalcService", param, 3000)` 同步调用远程 API，超时 3000ms。

## 5. 数据句柄（DataHnd）详解

`DataHnd` 是底层 `TDataHnd` 的 Go 封装，负责管理 API 名称和二进制数据。

### 5.1 创建与释放

```go
// 创建句柄，API 名称为 "echo"
param, err := client.CreateDataHnd("echo")
if err != nil {
    return err
}
defer client.FreeDataHnd(param)  // 必须释放
```

**重要**：

- `CreateDataHnd` 永远返回非零句柄（除非出错）。
- `Call` 返回的句柄同样必须释放，即使其大小为 0。
- 建议使用 `defer` 确保释放。

### 5.2 写入数据

```go
// 写入整数（小端序）
_ = client.WriteInt32(param, 12345)

// 写入 UTF-8 字符串（以空终止符结尾）
_ = client.WriteStringZ(param, "hello")

// 写入字节数组（长度前缀）
_ = client.WriteBytes(param, []byte{0x01, 0x02, 0x03})

// 写入布尔值
_ = client.WriteBool(param, true)

// 写入原始字节
data := []byte("raw data")
_, _ = client.WriteBuffer(param, data)
```

### 5.3 读取数据

```go
// 读取整数
client.SetPos(result, 0)
val, _ := client.ReadInt32(result)

// 读取空终止字符串
str, _ := client.ReadStringZ(result)

// 读取长度前缀字节数组
bytes, _ := client.ReadBytes(result)

// 读取布尔值
ok, _ := client.ReadBool(result)

// 读取原始字节
buf := make([]byte, 1024)
n, _ := client.ReadBuffer(result, buf)
```

### 5.4 位置与大小

```go
size := client.GetSize(param)   // 当前缓冲区大小（字节）
client.SetPos(param, 0)          // 重置读写位置到开头
```

### 5.5 底层访问（零拷贝）

如果需要直接操作原始字节，可以使用 `WriteBuffer` 和 `ReadBuffer` 配合 `[]byte` 切片。这适合高性能场景，但需小心内存越界。

## 6. 应用与服务端（Server）详解

`Server` 封装了 `AppHnd`，用于注册 API 并启动服务。

### 6.1 创建与释放

```go
server, err := api_hub.NewServer("MyApp", "My application")
if err != nil {
    return err
}
defer server.Stop()  // 自动释放资源
```

### 6.2 注册 Call API（请求-响应）

```go
err := server.RegisterCall("add", "a + b", func(input, output api_hub.DataHnd) {
    // input: 只读，包含请求参数
    // output: 只写，用于写入响应
    a, _ := api_hub.ReadInt32(input)
    b, _ := api_hub.ReadInt32(input)
    _ = api_hub.WriteInt32(output, a+b)
})
```

**回调签名**：`func(input DataHnd, output DataHnd)`  
**重要**：回调运行在 C 线程池中，**不能阻塞**，**不能调用 `Call` 或 `Notify`**（见第 11 节）。

### 6.3 注册 Notify API（单向通知）

```go
err := server.RegisterNotify("log", "Logger", func(input api_hub.DataHnd) {
    msg, _ := api_hub.ReadStringZ(input)
    fmt.Printf("[LOG] %s\n", msg)
})
```

### 6.4 启动服务

```go
// IPC 同机通信
err := server.Start("ipc:my_service")

// 或 TCP 跨机通信
err := server.Start("0.0.0.0:9898")
```

`Start` 内部执行：

- `ResetPrepare()`
- `PrepareService(addr, addr)`
- `PrepareClient(addr, app)`
- `PrepareDone()`

### 6.5 停止服务

```go
server.Stop()  // 调用 ExitMainThread + Shutdown + FreeAppHnd
```

## 7. 客户端（Client）详解

`Client` 提供所有客户端功能，包括连接管理和远程调用。

### 7.1 创建客户端

```go
client, err := api_hub.NewClient()
if err != nil {
    return err
}
defer client.Close()
```

### 7.2 准备连接

```go
client.ResetPrepare()
if err := client.PrepareClient("ipc:my_service"); err != nil {
    return err
}
ok, err := client.PrepareDone()
if !ok || err != nil {
    return fmt.Errorf("连接失败: %v", err)
}
defer client.Shutdown()
```

### 7.3 远程调用（Call）

```go
param, _ := client.CreateDataHnd("add")
defer client.FreeDataHnd(param)

_ = client.WriteInt32(param, 10)
_ = client.WriteInt32(param, 20)

result, err := client.Call("TargetApp", param, 3000)
if err != nil {
    return err
}
defer client.FreeDataHnd(result)

// 读取结果
client.SetPos(result, 0)
sum, _ := client.ReadInt32(result)
```

### 7.4 发送通知（Notify）

```go
param, _ := client.CreateDataHnd("log")
defer client.FreeDataHnd(param)

_ = client.WriteStringZ(param, "INFO")
_ = client.WriteStringZ(param, "Service started")

client.Notify("TargetApp", param)
```

## 8. 状态与检查 API（新增）

v2.1 新增了五个函数，用于查询框架运行状态和获取日志信息，极大方便了调试和运维。

### 8.1 `CheckMainThread`

```go
func CheckMainThread() int
```

检查模拟主线程（C4 事件循环）是否正在运行。

- **返回值**：`1` 表示运行中，`0` 表示已停止或未启动。
- **用途**：在调用远程 API 前确认框架已就绪，或在退出前确认主循环状态。
- **示例**：
  ```go
  if api_hub.CheckMainThread() == 1 {
      fmt.Println("主线程正在运行")
  } else {
      fmt.Println("主线程已停止")
  }
  ```

### 8.2 `CheckApp`

```go
func CheckApp(appName string) int
```

检查网络中是否存在指定名称的应用（基于本地缓存，可能有短暂滞后）。

- **参数**：`appName` – 应用名称（UTF‑8，区分大小写）。
- **返回值**：`1` 表示存在至少一个实例，`0` 表示不存在。
- **用途**：在调用 `Call` 前探测目标应用是否在线，避免无效超时。
- **示例**：
  ```go
  if api_hub.CheckApp("MyService") == 1 {
      // 安全调用
      result, _ := client.Call("MyService", param, 5000)
  } else {
      fmt.Println("MyService 当前不可用")
  }
  ```

### 8.3 日志队列 API

库内部维护一个 FIFO 日志队列，最多存储 **1000 条**消息，溢出时丢弃最旧的消息。

#### `GetStatusNum`

```go
func GetStatusNum() int
```

返回当前队列中待读取的日志条数。

#### `GetStatus`

```go
func GetStatus() string
```

取出队列头部的一条日志消息（UTF‑8 编码，已复制到 Go 字符串）。

- **返回**：若队列为空，返回空字符串。
- **示例**：
  ```go
  for api_hub.GetStatusNum() > 0 {
      msg := api_hub.GetStatus()
      fmt.Printf("[库日志] %s\n", msg)
  }
  ```

#### `PostStatus`

```go
func PostStatus(status string)
```

向队列中注入一条自定义日志消息，与库自身日志混合输出。

- **参数**：`status` – UTF‑8 字符串。
- **用途**：将应用层日志统一纳入 API Hub 的日志流。
- **示例**：
  ```go
  api_hub.PostStatus("应用初始化完成")
  ```

## 9. 动态注销 API

`Server.Unregister()` 方法允许您在运行时移除已注册的 API。

### 9.1 方法签名

```go
func (s *Server) Unregister(apiName string) error
```

### 9.2 使用示例

```go
server, _ := api_hub.NewServer("MyService", "")
server.RegisterCall("add", "Addition", addCallback)
server.RegisterCall("echo", "Echo", echoCallback)

// ... 运行一段时间后 ...

// 动态注销 'add' API
if err := server.Unregister("add"); err != nil {
    fmt.Printf("注销失败: %v\n", err)
} else {
    fmt.Println("API 'add' unregistered, broadcast in progress.")
}
```

### 9.3 关键行为

- **本地立即生效**：API 从本地注册表中同步删除。
- **网络异步广播**：删除操作触发 C4 服务网格广播，传播时间约 3 秒。
- **传播延迟窗口**：在广播传播期间，远程调用可能仍然到达并收到"未找到"错误。

### 9.4 使用场景

- **热卸载插件**：动态库插件可先注销自身 API，再安全卸载。
- **临时维护模式**：临时下线某些功能 API，无需重启整个应用。
- **权限动态调整**：根据用户角色或运行时条件，移除敏感 API 暴露。

## 10. 运行时配置

`SetOption()` 函数允许您在运行时动态调整 API Hub 框架的全局配置选项。

### 10.1 函数签名

```go
func SetOption(option, value string)
```

### 10.2 支持的选项

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

### 10.3 使用示例

```go
// 设置认证密码
api_hub.SetOption("password", "my_secret_token")

// 服务端不等待客户端就绪（适合大规模部署）
api_hub.SetOption("Wait_Connection_ReadyOk", "False")

// 提高 IPC 并发能力
api_hub.SetOption("IPC_Serv_ThreadCount", "8")
```

## 11. 线程安全与回调约束（⚠️ 关键）

### 11.1 导出函数线程安全

- ✅ `Call`、`Notify`、`WriteBuffer`、`ReadBuffer`、`Prepare*`、`Shutdown`、`CheckMainThread`、`CheckApp`、`GetStatusNum`、`GetStatus`、`PostStatus` 等**全部**可被多线程并发调用。
- ✅ 所有新增状态与检查 API 均为线程安全。

### 11.2 回调执行上下文

你的回调函数（通过 `RegisterCall`/`RegisterNotify` 注册）**运行在底层 C4 线程池的工作线程中**，而不是 Go 的 goroutine。

**因此必须遵守**：

- **禁止阻塞**：不要在回调中执行 `time.Sleep`、等待锁、循环大量计算等耗时操作。
- **禁止调用 Call/Notify**：否则可能死锁（因为回调线程可能已持有内部锁）。
- **禁止直接操作 UI**：如需更新 GUI，请使用 channel 将任务派发到主 goroutine。
- **推荐做法**：如果必须执行耗时任务或发起远程调用，将任务放入 channel，由另一个 goroutine 异步处理，回调立即返回。

**示例（正确）**：

```go
type Task struct {
    Data []byte
    Resp chan []byte
}

taskQueue := make(chan Task, 100)

// 后台 worker
go func() {
    for task := range taskQueue {
        // 这里可以安全地调用 Call
        result, _ := client.Call("Worker", param, 5000)
        task.Resp <- result
    }
}()

// 回调中只入队
server.RegisterCall("process", func(input, output DataHnd) {
    data, _ := ReadBytes(input)
    resp := make(chan []byte, 1)
    taskQueue <- Task{Data: data, Resp: resp}
    result := <-resp
    _ = WriteBytes(output, result)
})
```

## 12. 序列化与自定义载荷

Go 绑定提供了便捷的序列化辅助函数，全部使用**小端序**编码：

| 函数                         | 说明                            |
| ---------------------------- | ------------------------------- |
| `WriteInt32` / `ReadInt32`   | 32 位整数                       |
| `WriteStringZ` / `ReadStringZ` | UTF-8 字符串（空终止符 `#0`） |
| `WriteBool` / `ReadBool`     | 单字节布尔值                    |
| `WriteBytes` / `ReadBytes`   | 长度前缀（int32）+ 字节数组     |
| `WriteBuffer` / `ReadBuffer` | 原始字节读写                    |

**自定义序列化**：你可以使用 `WriteBuffer` 和 `ReadBuffer` 直接读写原始字节，实现任意格式（JSON、Protobuf、MsgPack 等）。

## 13. 日志与调试

库会输出大量运行时日志（连接状态、注册结果、错误信息等）。您可以通过以下方式获取：

1. **控制台自动输出**（默认开启）：库会将日志打印到标准输出，无需额外处理。
2. **程序化拉取（v2.1 新增）**：使用 `GetStatusNum` / `GetStatus` 在您的循环中拉取日志，实现自定义日志处理（如写入文件、网络传输）。
3. **注入自定义日志**：使用 `PostStatus` 将您的日志混合到库的日志流中。

**典型用法（主循环中拉取日志）**：

```go
func PollLogs() {
    for api_hub.GetStatusNum() > 0 {
        msg := api_hub.GetStatus()
        // 将 msg 写入文件、网络或控制台
        fmt.Println("[库日志]", msg)
    }
}
```

**控制台日志配置**：通过 `SetOption("ConsoleOutput", "False")` 可关闭控制台输出，完全由您的代码接管日志处理。也可通过 `<可执行文件名>.api-tool.ini` 配置文件调整日志行为。

常见日志含义：

| 日志                             | 含义                | 解决                   |
| -------------------------------- | ------------------- | ---------------------- |
| `bind address already in use`    | 端口/IPC 名称被占用 | 更换地址或终止其他进程 |
| `no found app("XXX") api("YYY")` | 目标应用/API 不存在 | 检查名称大小写，使用 `CheckApp` 提前探测 |
| `timeout`                        | 调用超时            | 增加超时，检查网络     |

## 14. 高级主题

### 14.1 并发调用

由于所有 API 都是线程安全的，你可以轻松实现高并发：

```go
var wg sync.WaitGroup
for i := 0; i < 100; i++ {
    wg.Add(1)
    go func(i int) {
        defer wg.Done()
        param, _ := client.CreateDataHnd("add")
        defer client.FreeDataHnd(param)
        _ = client.WriteInt32(param, int32(i))
        _ = client.WriteInt32(param, int32(i*2))
        result, _ := client.Call("CalcService", param, 3000)
        defer client.FreeDataHnd(result)
        client.SetPos(result, 0)
        sum, _ := client.ReadInt32(result)
        fmt.Printf("goroutine %d: %d\n", i, sum)
    }(i)
}
wg.Wait()
```

### 14.2 超时与重试

`Call` 的超时参数（毫秒）可自定义。超时返回的句柄大小为 0，此时可重试：

```go
result, err := client.Call("TargetApp", param, 5000)
if err != nil {
    return err
}
if client.GetSize(result) == 0 {
    // 超时或失败，可重试
    client.FreeDataHnd(result)
    result, _ = client.Call("TargetApp", param, 5000)
}
```

### 14.3 多实例负载均衡

只需在**不同进程**中启动多个服务端，注册**相同的应用名**。客户端调用时，C4 会自动将请求分发到负载最低的实例。

- 每个服务端使用不同的监听地址（如不同的 IPC 名称或端口），但公布地址应相同。
- 对于 IPC，多个服务端不能共用同一个 IPC 名称，需使用不同名称（如 `ipc:calc_1`、`ipc:calc_2`），但客户端可连接到任意一个。

### 14.4 本地调用（无网络）

在开发测试阶段，可以使用 `LocalCall` 避免启动网络，快速验证逻辑：

```go
param, _ := client.CreateDataHnd("add")
defer client.FreeDataHnd(param)
_ = client.WriteInt32(param, 10)
_ = client.WriteInt32(param, 20)

result := server.LocalCall(param)
defer client.FreeDataHnd(result)

client.SetPos(result, 0)
sum, _ := client.ReadInt32(result)
fmt.Printf("本地调用: %d\n", sum)
```

## 15. 完整示例集

项目 `Go/demos/` 目录下提供了 14 个场景示例：

| 示例                              | 说明                        |
| --------------------------------- | --------------------------- |
| `calc_server` / `calc_client`     | 计算服务（add/sub/mul/div） |
| `echo_server` / `echo_client`     | 回显服务                    |
| `file_server` / `file_client`     | 文件传输（分块）            |
| `log_server` / `log_client`       | 日志收集                    |
| `pubsub_server` / `pubsub_client` | 发布订阅                    |
| `config_server` / `config_client` | 配置中心                    |
| `concurrent_client`               | 并发压测                    |
| `cross_client`                    | 跨语言调用示例              |

每个示例都是独立的可运行程序，建议按顺序学习。

## 16. 常见问题与排错

| 问题                     | 可能原因                    | 解决方案                                         |
| ------------------------ | --------------------------- | ------------------------------------------------ |
| `loadLibrary` 失败       | 动态库不在搜索路径          | 将 `z_api_hub64.dll` 等放在可执行目录或系统 PATH |
| `PrepareDone` 返回 false | 地址已被占用或格式错误      | 检查地址，查看控制台输出或使用 `GetStatus` 获取详细错误 |
| 回调未触发               | 应用名或 API 名大小写不一致 | 核对大小写，服务端与客户端完全一致               |
| 远程调用超时             | 网络延迟或服务端未响应      | 增加超时时间，检查服务是否正常运行，用 `CheckApp` 提前探测 |
| 内存泄漏                 | 未释放 DataHnd              | 确保每个句柄都调用了 `FreeDataHnd`               |
| 回调中调用 Call 导致死锁 | 违反了回调约束              | 将远程调用移至后台 goroutine                     |
| 动态注销后仍有调用       | 广播传播延迟（约 3 秒）     | 正常行为，等待广播完成即可                       |
| 如何查看库内部日志       | 使用新增的日志 API          | 调用 `GetStatusNum`/`GetStatus` 拉取日志        |

## 17. 开源与社区

本项目由**老张**主导，致力于打造多语言互调的通用基础设施。  
Go 绑定只是其中一环，我们还有 Python、C++、Rust、Java、C#、Pascal、PHP、Node.js 等完整绑定，全部共享同一核心。

- **开源首页**：[https://github.com/PassByYou888/zAPI](https://github.com/PassByYou888/zAPI)
- **仓库地址**：[https://github.com/PassByYou888/zAPI.git](https://github.com/PassByYou888/zAPI.git)

欢迎 Star、Fork、提 Issue 和 PR！

## 📢 结语

**API Hub for Go** 让您用最 Go 的方式，拥抱整个异构世界。  
无论是将现有 Go 函数暴露给其他语言，还是优雅地调用 Python/C++/Rust 的高性能服务，API Hub 都是最轻量、最直接的桥梁。

> **"Write once, expose anywhere. Call anyone, from anywhere."**  
> —— 这就是 API Hub 的承诺。

现在就试试吧！启动一个 Go 服务，然后用 Python 或 PHP 客户端调用它，感受跨语言调用的丝滑体验。  
**我们在 GitHub 等你！** 🎉

## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](../C++/API%20Hub%20Tool%20C++%20使用指南.md)
- [API Hub Tool C 语言使用指南](../C++/API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](../Py/从零到一，掌握多语言互调.md)
- [zAPI Rust 使用指南](../rust/zAPI%20Rust%20使用指南.md)
- [API Hub Java 使用指南](../java/API%20Hub%20Java%20使用指南.md)
- [API Hub Tool for C# — 完整使用指南](../C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [API Hub Tool for Pascal](../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../node/Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](../Py/web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](../Py/web/js_api.py%20使用指南.md)
