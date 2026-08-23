# API Hub Java 使用指南 —— 从入门到跨语言实战

> **面向读者**：Java 开发者（Java 8+），无论你是微服务架构师、算法工程师还是桌面应用开发者，这份指南将带你用最少的代码，将 Java 函数变成跨语言 RPC 服务，并自如调用其他语言（C++、C#、Python、Go、Pascal、PHP、Node.js）编写的服务。  
> **读完本文，你将能够**：
> - 理解 API Hub Java 绑定的核心设计；
> - 在 Java 中注册 API 并处理请求；
> - 在 Java 中调用远程服务；
> - 实现与 C++/C#/Python/Go/Pascal/PHP/Node.js 的互通；
> - 动态注销 API 和运行时调整配置；
> - 利用状态与检查 API 进行运行时监控和日志管理；
> - 应对生产环境中的常见问题。

---

## 📖 目录

- [1. 概述](#1-概述)
- [2. 环境搭建与快速开始](#2-环境搭建与快速开始)
- [3. 核心 API 详解](#3-核心-api-详解)
  - [3.1 DataHandle —— 数据句柄](#31-datahandle--数据句柄)
  - [3.2 AppHandle —— 应用句柄](#32-apphandle--应用句柄)
  - [3.3 回调接口](#33-回调接口)
  - [3.4 ApiHub —— 网络与工具类](#34-apihub--网络与工具类)
  - [3.5 v2.1 新增：状态与检查 API](#35-v21-新增状态与检查-api)
- [4. 服务端开发](#4-服务端开发)
- [5. 客户端开发](#5-客户端开发)
- [6. 序列化与数据类型](#6-序列化与数据类型)
- [7. 动态注销 API](#7-动态注销-api)
- [8. 运行时配置](#8-运行时配置)
- [9. 多场景实战](#9-多场景实战)
- [10. 多语言互操作](#10-多语言互操作)
- [11. 性能调优与最佳实践](#11-性能调优与最佳实践)
- [12. 常见问题（FAQ）](#12-常见问题faq)
- [13. 总结与扩展](#13-总结与扩展)

---

## 1. 概述

API Hub Java 绑定是一套基于 [JNA](https://github.com/java-native-access/jna) 的轻量级封装，它让 Java 程序能够**直接调用** C 动态库（`z_api_hub64.dll` / `libz_api_hub.so`）导出的函数，从而接入由 **C4 分布式服务网格** 驱动的跨语言 RPC 网络。

### 1.1 核心设计理念

- **语言透明**：所有绑定（Java、C++、C#、Python、Go、Pascal、PHP、Node.js）共享相同的 **C ABI** 和 **二进制序列化协议**，相互调用无需转换。  
- **零序列化开销**：数据以原始字节流传递，无 JSON/Protobuf 编解码，性能媲美原生 Socket。  
- **双协议无缝切换**：IPC（本机进程间）和 TCP（跨机器）使用完全相同的 API，仅地址字符串不同。  
- **自动服务发现**：应用按名称注册，客户端按名称调用，框架自动路由、负载均衡、断线重连。  
- **RAII 资源管理**：`DataHandle` 和 `AppHandle` 实现 `AutoCloseable`，自动释放内存，杜绝泄漏。
- **动态 API 注销**（v2.0）：`AppHandle.unregister()` 支持运行时移除 API，自动广播至所有对等节点。
- **运行时配置**（v2.0）：`ApiHub.setOption()` 支持动态调整认证密码、等待连接、IPC 线程池等参数。
- **状态与检查 API**（v2.1）：新增 `checkMainThread`、`checkApp`、`getStatusNum`、`getStatus`、`postStatus`，方便调试和运维。

### 1.2 适用场景

- 将 Java 算法（加密、图像处理、ML 推理）快速暴露为跨语言服务。  
- 在微服务架构中，用 Java 实现业务中枢，与 C++ 高性能计算、Python 数据科学、C# 桌面端等混合部署。  
- 同一台机器上进程间通信（IPC）替代繁琐的 Socket 编程。  
- 遗留系统现代化：将现有 Java 代码包装为远程 API，供其他语言调用。

---

## 2. 环境搭建与快速开始

### 2.1 前置条件

- **Java 8+**（推荐 11 或 17）  
- **JNA 5.14.0**（项目 lib 目录已包含）  
- **API Hub 动态库**：从 `Binary/` 目录获取，根据操作系统放置：
  - Windows 64-bit：`z_api_hub64.dll`（附带 `z_ipc_64.dll`、`mimalloc64.dll`）
  - Linux：`libz_api_hub.so`
  - macOS：`libz_api_hub.dylib`

> 动态库**必须**位于可执行文件的搜索路径中（`PATH` / `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH`），或放在与 JAR 相同的目录。项目提供的 PowerShell 脚本会自动处理。

### 2.2 项目结构

```
java/
├── lib/                # JNA JAR
├── src/com/apihub/     # 核心绑定源码
├── demo/               # 示例程序
├── build.ps1           # 编译脚本
├── run_server.ps1      # 启动基础服务
├── run_client.ps1      # 启动基础客户端
├── run_func_server.ps1 # 启动功能服务（13 API）
└── run_func_client.ps1 # 并发压测客户端
```

### 2.3 30 秒体验

1. **编译**（在 `java/` 目录下）：
   ```powershell
   .\build.ps1
   ```
2. **启动服务端**（保留窗口）：
   ```powershell
   .\run_server.ps1
   ```
   输出：
   ```
   === Java API Hub Server Demo ===
   Registered 'add' API
   Service started on ipc:calc_service
   Press Ctrl+C to stop...
   ```
3. **运行客户端**（另开终端）：
   ```powershell
   .\run_client.ps1
   ```
   输出：
   ```
   10 + 20 = 30
   ```

恭喜！你已经完成了一次 Java 远程调用。现在让我们深入细节。

---

## 3. 核心 API 详解

### 3.1 DataHandle —— 数据句柄

`DataHandle` 封装了底层二进制缓冲区，包含 **API 名称** 和 **载荷**。所有输入/输出数据都通过它传递。

**构造**：
- `new DataHandle("apiName")`：创建一个新句柄，API 名称用于路由。
- `DataHandle.wrapInput(Pointer)` / `wrapOutput(Pointer)`：在回调中包装传入的原始指针（**不接管所有权**）。

**写入数据**：
- `write(byte[])`：写入原始字节。
- `writeInt(int)`、`writeDouble(double)`：小端序写入。
- **推荐**：`writeStringNullTerminated(String)` —— 写入 UTF-8 字符串并追加一个 **空终止符 (#0)**，与 Pascal 的 `API_WriteString` 完全兼容，适用于跨语言通信。  
- **已弃用**：`writeString(String)` —— 使用 4 字节长度前缀，仅限 Java 内部协议，不跨语言。

**读取数据**：
- `read(int)`：读取指定字节数。
- `readInt()`、`readDouble()`。
- **推荐**：`readStringNullTerminated()` —— 读取直到空终止符，位置移至终止符后，与 Pascal `API_ReadString` 一致。  
- **已弃用**：`readString()` —— 长度前缀方式。

**位置控制**：
- `getPos()` / `setPos(long)`：读写位置。
- `getSize()` / `setSize(long)`：缓冲区总大小。

**零拷贝访问**：
- `getBuffer()`：直接获取内部指针（只读，高性能）。

**资源释放**：实现 `AutoCloseable`，建议使用 `try-with-resources` 自动释放。

### 3.2 AppHandle —— 应用句柄

`AppHandle` 代表一个逻辑应用，可注册多个 API，网络唯一标识。

**构造**：
- `new AppHandle("MyApp", "Description")`。

**注册 API**：
- `registerCall(apiName, desc, callback)`：请求-响应。
- `registerNotify(apiName, desc, callback)`：单向通知。

**动态注销（v2.0）**：
- `unregister(apiName)`：运行时移除已注册的 API，触发网络广播（约 3 秒传播）。

**本地调用**（用于测试）：
- `localCall(param)`：同步执行本地注册的 API，不经过网络。

### 3.3 回调接口 —— `CallCallback` 和 `NotifyCallback`

- `CallCallback`：`void invoke(Pointer trigger, Pointer input, Pointer output)`  
  从 `input` 读取参数，将结果写入 `output`。**必须快速返回**，禁止阻塞或调用 `ApiHub.call` / `notify`。
- `NotifyCallback`：`void invoke(Pointer trigger, Pointer input)`  
  只读，无输出。

**重要**：回调由底层 C 库在内部线程池中执行，必须线程安全。

### 3.4 ApiHub —— 网络与工具类

| 方法 | 说明 |
|------|------|
| `resetPrepare()` | 清空之前的准备状态（每次配置前调用）。 |
| `prepareService(listening, physics)` | 添加一个服务监听地址（可多次调用）。 |
| `prepareClient(physics, app)` | 添加一个客户端连接，若提供 `app` 则暴露该应用。 |
| `prepareDone()` | 启动网络框架，阻塞直到就绪，返回 `true` 成功。 |
| `exitMainThread()` | 通知框架停止内部循环。 |
| `shutdown()` | 关闭所有连接，释放资源。 |
| `call(appName, param, timeoutMs)` | 同步远程调用，返回结果句柄。 |
| `notify(appName, param)` | 单向通知，无返回。 |
| `setOption(option, value)` | **运行时动态调整全局配置（v2.0）**。 |

### 3.5 v2.1 新增：状态与检查 API

| 方法 | 说明 |
|------|------|
| `checkMainThread()` | 返回 1 如果模拟主线程（C4 事件循环）正在运行，0 否则。 |
| `checkApp(appName)` | 返回 1 如果指定应用在线（基于本地缓存，可能短暂滞后），0 否则。 |
| `getStatusNum()` | 返回内部日志队列中待读取的消息数量。 |
| `getStatus()` | 从队列中取出下一条日志消息（UTF-8），队列为空返回空字符串。 |
| `postStatus(status)` | 向队列中注入一条自定义日志消息，与库自身日志混合。 |

这些 API 全部线程安全，可用于实时监控框架运行状态、探测目标服务可用性、程序化拉取和注入日志。

**使用示例**：
```java
// 检查主线程状态
if (ApiHub.checkMainThread() == 1) {
    System.out.println("主线程运行中");
}

// 探测目标服务是否在线
if (ApiHub.checkApp("MyService") == 1) {
    // 安全调用
    try (DataHandle res = ApiHub.call("MyService", param, 5000)) { ... }
} else {
    System.err.println("服务不可用");
}

// 拉取所有日志
while (ApiHub.getStatusNum() > 0) {
    String msg = ApiHub.getStatus();
    System.out.println("[库日志] " + msg);
}

// 注入自定义日志
ApiHub.postStatus("应用初始化完成");
```

> **调试说明**：库会将详细的运行日志（包括连接状态、注册信息、错误原因）自动输出到控制台。你也可以通过上述状态 API 程序化获取日志，实现集中监控。

---

## 4. 服务端开发

### 4.1 注册单个 API

```java
try (AppHandle app = new AppHandle("CalcService", "Calculator")) {
    app.registerCall("add", "Add two integers", (trigger, input, output) -> {
        DataHandle in = DataHandle.wrapInput(input);
        DataHandle out = DataHandle.wrapOutput(output);
        int a = in.readInt();
        int b = in.readInt();
        out.writeInt(a + b);
    });

    ApiHub.resetPrepare();
    ApiHub.prepareService("ipc:calc_service", "ipc:calc_service");
    ApiHub.prepareClient("ipc:calc_service", app);
    if (ApiHub.prepareDone()) {
        System.out.println("Service ready.");
        Thread.currentThread().join();  // 阻塞主线程
    }
}
```

### 4.2 注册多个 API

参考 `FuncServer.java`，它注册了 13 个 API，包括数学运算、字符串处理、数组操作等。每个回调独立处理自己的序列化逻辑。

### 4.3 注册通知（Notify）

```java
app.registerNotify("log", "Logging", (trigger, input) -> {
    DataHandle in = DataHandle.wrapInput(input);
    String level = in.readStringNullTerminated();
    String msg = in.readStringNullTerminated();
    System.out.println("[" + level + "] " + msg);
});
```

### 4.4 优雅退出

服务端通常需要响应 Ctrl+C，可注册 `ShutdownHook`：

```java
Runtime.getRuntime().addShutdownHook(new Thread(() -> {
    ApiHub.exitMainThread();
    ApiHub.shutdown();
}));
```

主线程使用可中断循环代替 `join()`：

```java
while (!Thread.currentThread().isInterrupted()) {
    Thread.sleep(1000);
}
```

---

## 5. 客户端开发

### 5.1 纯消费端（不暴露 API）

```java
ApiHub.resetPrepare();
ApiHub.prepareClient("ipc:calc_service", null);
if (!ApiHub.prepareDone()) {
    // 处理错误
}

try (DataHandle param = new DataHandle("add")) {
    param.writeInt(10);
    param.writeInt(20);
    try (DataHandle result = ApiHub.call("CalcService", param, 3000)) {
        if (result.getSize() == 0) {
            System.err.println("Timeout or error");
        } else {
            int sum = result.readInt();
            System.out.println(sum);
        }
    }
}
```

### 5.2 带重试的健壮调用

```java
public static DataHandle callWithRetry(String app, DataHandle param, long timeout, int maxRetries) {
    for (int i = 0; i < maxRetries; i++) {
        try (DataHandle res = ApiHub.call(app, param, timeout)) {
            if (res.getSize() > 0) {
                return res;  // 调用者负责释放
            }
        } catch (Exception e) {
            // 忽略，继续重试
        }
        try { Thread.sleep(100 * (i + 1)); } catch (InterruptedException ignored) {}
    }
    return null;
}
```

### 5.3 发送通知

```java
try (DataHandle param = new DataHandle("log")) {
    param.writeStringNullTerminated("INFO");
    param.writeStringNullTerminated("Client started");
    ApiHub.notify("LogService", param);
}
```

---

## 6. 序列化与数据类型

### 6.1 基本类型读写顺序

服务端和客户端必须**严格一致**的读写顺序。例如：

**客户端写入**：
```java
param.writeInt(100);
param.writeDouble(3.14);
param.writeStringNullTerminated("hello");
```

**服务端读取**：
```java
int a = in.readInt();
double b = in.readDouble();
String s = in.readStringNullTerminated();
```

### 6.2 数组与结构体

写入数组时，先写长度，再写每个元素：

```java
// 写入 int 数组
param.writeInt(arr.length);
for (int v : arr) param.writeInt(v);

// 读取 int 数组
int len = in.readInt();
int[] arr = new int[len];
for (int i = 0; i < len; i++) arr[i] = in.readInt();
```

对于固定长度的结构体，可以一次性写入字节数组，确保跨语言内存对齐（使用小端序）：

```java
class Point {
    int x, y;
    byte[] label = new byte[32];
}

void writePoint(DataHandle h, Point p) {
    ByteBuffer buf = ByteBuffer.allocate(40).order(ByteOrder.LITTLE_ENDIAN);
    buf.putInt(p.x).putInt(p.y).put(p.label);
    h.write(buf.array());
}

Point readPoint(DataHandle h) {
    byte[] data = h.read(40);
    ByteBuffer buf = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN);
    Point p = new Point();
    p.x = buf.getInt();
    p.y = buf.getInt();
    buf.get(p.label);
    return p;
}
```

这种方式与 C/C++ 的 `struct` 完全兼容，实现零拷贝跨语言数据交换。

### 6.3 字符串协议（跨语言关键）

**所有语言绑定统一采用「空终止符（#0）」格式**：  
- 写入：UTF-8 字节 + 一个 `\0` 字节。  
- 读取：从当前位置扫描直到遇到 `\0`，位置移至终止符后。  

Java 绑定提供：
- `writeStringNullTerminated(String)` —— **推荐**，与 Pascal、C#、Go 等完全兼容。
- `readStringNullTerminated()` —— **推荐**，配套使用。

**已弃用的长度前缀方法**（`writeString` / `readString`）仅用于 Java 内部协议，**不跨语言**。

---

## 7. 动态注销 API

`AppHandle.unregister()` 方法允许您在运行时移除已注册的 API。

### 7.1 方法签名

```java
public boolean unregister(String apiName)
```

### 7.2 使用示例

```java
try (AppHandle app = new AppHandle("MyService", "")) {
    // 注册 API
    app.registerCall("add", "Addition", addCallback);
    app.registerCall("echo", "Echo", echoCallback);

    // ... 运行一段时间后 ...

    // 动态注销 'add' API
    if (app.unregister("add")) {
        System.out.println("API 'add' unregistered, broadcast in progress.");
    } else {
        System.out.println("API 'add' not found.");
    }

    // 'add' 不再可用，但 'echo' 仍然可用
}
```

### 7.3 关键行为

- **本地立即生效**：API 从本地注册表中同步删除。
- **网络异步广播**：删除操作触发 C4 服务网格广播，传播时间约 3 秒（取决于网络延迟）。
- **传播延迟窗口**：在广播传播期间，远程调用可能仍然到达并收到"未找到"错误。

### 7.4 使用场景

- **热卸载插件**：动态库插件可先注销自身 API，再安全卸载。
- **临时维护模式**：临时下线某些功能 API，无需重启整个应用。
- **权限动态调整**：根据用户角色或运行时条件，移除敏感 API 暴露。

---

## 8. 运行时配置

`ApiHub.setOption()` 方法允许您在运行时动态调整 API Hub 框架的全局配置选项。

### 8.1 方法签名

```java
public static void setOption(String option, String value)
```

### 8.2 支持的选项

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

### 8.3 使用示例

```java
// 设置认证密码（必须在 PrepareDone 之前调用）
ApiHub.setOption("password", "my_secret_token");

// 服务端不等待客户端就绪（适合大规模部署）
ApiHub.setOption("Wait_Connection_ReadyOk", "False");

// 提高 IPC 并发能力
ApiHub.setOption("IPC_Serv_ThreadCount", "8");

// 开启详细日志（调试时使用）
ApiHub.setOption("ConsoleOutput", "True");
ApiHub.setOption("ShowThreadID", "True");
```

---

## 9. 多场景实战

### 9.1 计算服务（基础）

即 `DemoServer` / `DemoClient`，是最简单的入门示例，涵盖注册、调用、超时处理。

### 9.2 配置中心（推拉结合）

**需求**：分布式配置管理，支持动态更新。

**服务端（Java）**：
```java
Map<String, String> config = new ConcurrentHashMap<>();

app.registerNotify("set", "", (trigger, input) -> {
    DataHandle in = DataHandle.wrapInput(input);
    String key = in.readStringNullTerminated();
    String val = in.readStringNullTerminated();
    config.put(key, val);
    System.out.println("Config updated: " + key + "=" + val);
});

app.registerCall("get", "", (trigger, input, output) -> {
    DataHandle in = DataHandle.wrapInput(input);
    DataHandle out = DataHandle.wrapOutput(output);
    String key = in.readStringNullTerminated();
    String val = config.getOrDefault(key, "");
    out.writeStringNullTerminated(val);
});
```

**客户端（任意语言）**：
- 设置：`notify("set", "db_host", "localhost")`
- 获取：`call("get", "db_host")` 返回 `localhost`

### 9.3 文件传输（二进制分块）

**服务端**：提供 `upload`（接收文件名 + 字节数据）和 `download`（返回文件内容）。

```java
app.registerCall("upload", "", (trigger, input, output) -> {
    DataHandle in = DataHandle.wrapInput(input);
    String name = in.readStringNullTerminated();
    int len = in.readInt();
    byte[] data = in.read(len);
    try (FileOutputStream fos = new FileOutputStream(name)) {
        fos.write(data);
        out.writeInt(1);  // 成功
    } catch (IOException e) {
        out.writeInt(0);
    }
});
```

**客户端（Java）**：
```java
try (DataHandle param = new DataHandle("upload")) {
    byte[] content = Files.readAllBytes(Paths.get("local.txt"));
    param.writeStringNullTerminated("remote.txt");
    param.writeInt(content.length);
    param.write(content);
    try (DataHandle res = ApiHub.call("FileService", param, 10000)) {
        if (res.readInt() == 1) System.out.println("Upload success");
    }
}
```

### 9.4 发布订阅（事件驱动）

**服务端**：
```java
Map<String, Set<String>> subscribers = new ConcurrentHashMap<>();

app.registerNotify("subscribe", "", (trigger, input) -> {
    DataHandle in = DataHandle.wrapInput(input);
    String topic = in.readStringNullTerminated();
    String client = in.readStringNullTerminated();
    subscribers.computeIfAbsent(topic, k -> ConcurrentHashMap.newKeySet()).add(client);
});

app.registerNotify("publish", "", (trigger, input) -> {
    DataHandle in = DataHandle.wrapInput(input);
    String topic = in.readStringNullTerminated();
    String msg = in.readStringNullTerminated();
    Set<String> clients = subscribers.get(topic);
    if (clients != null) {
        for (String c : clients) {
            System.out.println("Notifying " + c + ": " + msg);
            // 实际可通过 API_Call 或 Notify 转发给订阅者
        }
    }
});
```

### 9.5 并发压测（高吞吐）

`FuncClient.java` 展示了如何用 **每个调用一个线程** 的方式并发调用所有 API，统计延迟分布和 QPS。它利用了底层库的线程安全特性，无需加锁。

---

## 10. 多语言互操作

API Hub 的**杀手锏**在于跨语言透明。以下所有示例均**已验证**，服务端和客户端可以任意互换。

### 10.1 Java 服务端 + C++ 客户端

**Java 服务端**（如 `FuncServer`）注册 `add` 等 API，使用 IPC 地址 `ipc:func_service`。

**C++ 客户端**（使用 `API_HubTool.h`）：
```cpp
#include "API_HubTool.h"

int main() {
    API_LoadLibrary();
    API_Reset_Prepare();
    API_Prepare_Client("ipc:func_service", nullptr);
    if (API_Prepare_Done() != 1) return 1;

    TDataHnd data = API_Create_DataHnd("add");
    int32_t a = 10, b = 20;
    API_WriteBuffer(data, &a, 4);
    API_WriteBuffer(data, &b, 4);
    TDataHnd result = API_Call("FuncService", data, 3000);
    API_Free_DataHnd(data);
    if (result) {
        int32_t sum;
        API_SetPos(result, 0);
        API_ReadBuffer(result, &sum, 4);
        printf("10 + 20 = %d\n", sum);
        API_Free_DataHnd(result);
    }
    API_shutdown();
    API_FreeLibrary();
    return 0;
}
```

### 10.2 Java 服务端 + C# 客户端

**C# 客户端**（使用 `API_HubTool.Bindings`）：
```csharp
using static API_HubTool.Bindings.API;

var data = API_Create_DataHnd("add");
API_WriteBuffer(data, BitConverter.GetBytes(10), 4);
API_WriteBuffer(data, BitConverter.GetBytes(20), 4);
var result = API_Call("FuncService", data, 3000);
if (result.IsValid) {
    int sum = BitConverter.ToInt32(ReadAllBytes(result), 0);
    Console.WriteLine($"10 + 20 = {sum}");
}
```

### 10.3 Java 服务端 + Python 客户端

**Python 客户端**（使用 `api_hub` 包）：
```python
from api_hub import C4
c4 = C4("FuncService", "ipc:func_service")
print(c4.add(10, 20))   # 输出 30
```

### 10.4 Java 服务端 + Go 客户端

**Go 客户端**（使用 `api_hub-go`）：
```go
client, _ := api_hub.NewClient()
client.PrepareClient("ipc:func_service")
client.PrepareDone()
h, _ := client.CreateDataHnd("add")
client.WriteInt32(h, 10)
client.WriteInt32(h, 20)
res, _ := client.Call("FuncService", h, 3000)
sum, _ := client.ReadInt32(res)
fmt.Println(sum)
```

### 10.5 Java 服务端 + PHP 客户端（通过 Bridge）

**PHP 客户端**（使用 `ZAPIBridgeClient`）：
```php
require_once 'ZAPIBridgeClient.php';
$client = new ZAPIBridgeClient('http://127.0.0.1:8080/v1');
$result = $client->invoke('FuncService', 'add', [10, 20]);
echo "10 + 20 = " . $result . "\n";
```

### 10.6 Java 客户端 + 其他语言服务

只需将 `ApiHub.prepareClient` 的地址指向其他语言服务，`ApiHub.call` 的 `appName` 改为对方注册的名称，即可无缝调用。例如：

- 调用 **C++ FuncService**（注册名为 `FuncService`）：
  ```java
  ApiHub.prepareClient("ipc:func_service", null);
  try (DataHandle param = new DataHandle("sha3")) {
      param.writeStringNullTerminated("hello");
      try (DataHandle res = ApiHub.call("FuncService", param, 5000)) {
          System.out.println(res.readStringNullTerminated());  // SHA3 哈希
      }
  }
  ```

- 调用 **Python AI 推理服务**（注册名为 `InferenceService`，地址 `127.0.0.1:9898`）：
  ```java
  ApiHub.prepareClient("127.0.0.1:9898", null);
  try (DataHandle param = new DataHandle("predict")) {
      param.writeStringNullTerminated(imageDataBase64);
      try (DataHandle res = ApiHub.call("InferenceService", param, 10000)) {
          String result = res.readStringNullTerminated();  // 模型输出
      }
  }
  ```

**关键在于**：所有语言使用相同的二进制协议，所以无论服务端用什么语言实现，客户端只需按顺序读写基本类型即可。

---

## 11. 性能调优与最佳实践

1. **优先使用 IPC**：同机通信时 `ipc:service_name` 延迟 <0.1ms，远优于 TCP（~1-2ms）。  
2. **复用 DataHandle**：频繁创建/释放句柄有开销，可重置位置和大小后重复使用：
   ```java
   DataHandle h = new DataHandle("add");
   for (int i = 0; i < 1000; i++) {
       h.setSize(0);
       h.setPos(0);
       h.writeInt(i);
       h.writeInt(i*2);
       try (DataHandle res = ApiHub.call("Calc", h, 1000)) { ... }
   }
   ```
3. **批量写入**：将多个参数打包成结构体一次写入，减少 JNI 调用次数。  
4. **超时设置**：根据网络环境设置合理超时（毫秒），避免无谓等待。  
5. **回调避免阻塞**：若回调中有耗时操作（如数据库访问），应将其放入独立线程池，并在回调中仅将任务入队。  
6. **线程安全**：底层库完全线程安全，但同一 `DataHandle` 不应并发读写；不同句柄可安全并发。
7. **错误诊断**：
   - 控制台会自动输出日志。  
   - 可通过 **状态与检查 API** 程序化拉取日志（`getStatusNum`/`getStatus`），实现集中监控。  
   - 使用 `checkApp` 提前探测目标服务可用性，避免无效超时。  
   - 使用 `checkMainThread` 确认框架已就绪。
8. **动态配置**：利用 `setOption` 和 `unregister` 实现热更新和不停机维护。

---

## 12. 常见问题（FAQ）

**Q1：运行时报 `UnsatisfiedLinkError: Unable to load library 'z_api_hub64'`**  
A：动态库不在 `PATH` 中。将 `Binary/` 目录加入环境变量，或复制 `.dll` 到项目目录。使用提供的脚本可自动处理。

**Q2：`prepareDone()` 返回 `false`，如何排查？**  
A：检查控制台输出，库会打印详细的错误信息（如端口占用、IPC 地址冲突、动态库版本不匹配等）。也可使用 `getStatusNum()` / `getStatus()` 程序化获取日志，便于集成到日志系统。

**Q3：回调没有触发**  
A：检查应用名称和 API 名称是否**大小写完全一致**（如 `FuncService` 和 `funcservice` 不同）；查看控制台输出是否有注册成功日志；使用 `checkApp` 验证目标应用是否在线。

**Q4：客户端调用超时**  
A：确认服务端已启动且地址一致；适当增加超时时间（如 5000ms）；检查防火墙是否阻止 IPC（通常不会）。用 `checkApp` 提前探测。

**Q5：如何传递二进制数据（如文件）？**  
A：使用 `write(byte[])` 直接写入原始字节；读取时用 `read(int)` 获取。注意大文件应分块传输。

**Q6：Java 绑定是否支持多线程？**  
A：底层库完全线程安全，可安全并发调用 `ApiHub.call`。但同一 `DataHandle` 不应被多个线程同时修改。

**Q7：能否在同一个 Java 进程中有多个应用（AppHandle）？**  
A：可以，每个 `AppHandle` 独立命名，分别注册 API 并连接到不同服务。

**Q8：动态注销 API 后，正在进行的调用会怎样？**  
A：正在执行中的回调不会被打断，它们会正常完成。新到达的请求会在广播传播后收到"未找到"错误。

**Q9：如何获取库内部的运行日志？**  
A：使用 `getStatusNum()` / `getStatus()` 拉取日志，或使用 `postStatus()` 注入自定义日志。也可查看控制台输出。

---

## 13. 总结与扩展

API Hub Java 绑定让你以最优雅的方式接入跨语言分布式网络。通过 JNA 和 RAII，Java 开发者无需接触任何 C 代码即可享受高性能 RPC。无论你是想快速搭建微服务原型，还是希望将 Java 算法融入异构系统，它都能大幅降低开发成本。

**v2.1 新能力**：
- 状态与检查 API 提供了主动监控和日志管理能力，让生产环境下的故障诊断更加高效。
- 结合 `checkApp`、`checkMainThread` 和日志拉取，可构建更健壮的服务治理体系。

**扩展方向**：
- 基于 `DataHandle` 封装更高级的序列化工具（如支持 protobuf、JSON 的适配器）。
- 集成 Spring Boot，将 `@RestController` 自动映射为远程 API。
- 提供异步调用模式（基于 `CompletableFuture`）。

现在你已经掌握了全部核心知识，动手写一个属于自己的跨语言服务吧！如果遇到问题，记得检查控制台输出或使用 `getStatus()` ——它们是最好的"诊断工具"。

---

*[返回顶部](#api-hub-java-使用指南--从入门到跨语言实战)*  
*项目源码及示例：`java/` 目录*  
*反馈与贡献：欢迎 Issue 和 PR*

## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](../C++/API%20Hub%20Tool%20C++%20使用指南.md)
- [API Hub Tool C 语言使用指南](../C++/API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](../Py/从零到一，掌握多语言互调.md)
- [API Hub for Go 从零到一掌握多语言互调](../Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)
- [zAPI Rust 使用指南](../rust/zAPI%20Rust%20使用指南.md)
- [API Hub Tool for C# — 完整使用指南](../C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [API Hub Tool for Pascal](../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../node/Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](../Py/web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](../Py/web/js_api.py%20使用指南.md)
