# Java 编程入门指南 —— 手把手教你用 API Hub 构建跨语言服务

> **面向读者**：Java 初学者或刚接触 API Hub 的开发者。假设你已经了解 Java 基本语法（变量、循环、类、异常），但对 JNA、跨语言 RPC 或分布式系统尚不熟悉。  
> **读完本文，你将能够**：
> - 从零搭建 API Hub Java 开发环境；
> - 编写第一个跨语言服务端和客户端；
> - 理解核心概念（句柄、回调、网络准备）；
> - 学会调试和解决常见问题；
> - 掌握 v2.1 新特性（动态注销、运行时配置、状态与检查 API）；
> - 迈出迈向多语言生态的第一步。
>
> **版本：** 2.1（与 ZAPI 核心 v2.1 同步）

---

## 📖 目录

- [1. 准备工作](#1-准备工作)
- [2. 项目结构详解](#2-项目结构详解)
- [3. 编写第一个服务端（Hello Server）](#3-编写第一个服务端hello-server)
- [4. 编写第一个客户端（Hello Client）](#4-编写第一个客户端hello-client)
- [5. 运行并验证](#5-运行并验证)
- [6. 深入理解：每一步做了什么？](#6-深入理解每一步做了什么)
- [7. 扩展：注册多个 API](#7-扩展注册多个-api)
- [8. 扩展：发送通知（Notify）](#8-扩展发送通知notify)
- [9. v2.1 新特性：动态注销 API](#9-v21-新特性动态注销-api)
- [10. v2.1 新特性：运行时配置](#10-v21-新特性运行时配置)
- [11. v2.1 新特性：状态与检查 API](#11-v21-新特性状态与检查-api)
- [12. 跨语言调用初体验](#12-跨语言调用初体验)
- [13. 常见错误与解决方法](#13-常见错误与解决方法)
- [14. 下一步学什么](#14-下一步学什么)

---

## 1. 准备工作

### 1.1 确认 Java 环境

打开终端（或 PowerShell），输入：
```bash
java -version
javac -version
```
确保输出 Java 8 或更高版本。如果没有，请先安装 [JDK](https://adoptium.net/)。

### 1.2 获取 API Hub Java 绑定代码

本项目已包含所有源码，你只需将整个 `java/` 目录复制到你的工作空间。目录结构如下：

```
java/
├── lib/
│   └── jna-5.14.0.jar          # JNA 库（用于 Java 调用 C 库）
├── src/
│   └── com/apihub/             # 核心绑定代码（不要修改，除非你很熟悉）
│       ├── ApiHubNative.java   # JNA 接口声明
│       ├── DataHandle.java     # 数据句柄封装
│       ├── AppHandle.java      # 应用句柄封装
│       ├── CallCallback.java   # 请求-响应回调接口
│       ├── NotifyCallback.java # 通知回调接口
│       └── ApiHub.java         # 静态工具类（含 v2.1 新方法）
├── demo/
│   ├── DemoServer.java         # 最简单的服务端（加法）
│   ├── DemoClient.java         # 最简单的客户端（调用加法）
│   ├── FuncServer.java         # 功能丰富的服务端（13个API）
│   └── FuncClient.java         # 并发压测客户端（进阶，暂不关注）
├── build.ps1                   # Windows 编译脚本
├── run_server.ps1              # 启动服务端
├── run_client.ps1              # 启动客户端
├── run_func_server.ps1         # 启动功能服务端
└── run_func_client.ps1         # 启动压测客户端
```

> **如果你使用 Linux/macOS**，请将 `.ps1` 替换为对应的 Shell 脚本（项目暂未提供，但可参考命令自行编写）。

### 1.3 放置动态库

API Hub 的核心是 C 动态库，你需要将 `Binary/` 目录下的文件放到合适位置：

- Windows：`z_api_hub64.dll`（及依赖 `z_ipc_64.dll`、`mimalloc64.dll`）  
- Linux：`libz_api_hub.so`  
- macOS：`libz_api_hub.dylib`

**最简单的方法**：将这些文件复制到 `java/` 目录（与 `build.ps1` 同级），或确保系统 `PATH` 包含 `Binary/` 路径。我们提供的脚本会自动将 `../Binary` 加入 `PATH`，所以如果你保持项目结构不变，无需额外操作。

> ⚠️ **常见误区**：很多人遗漏动态库，导致运行时 `UnsatisfiedLinkError`。务必先确认动态库存在且可访问。

---

## 2. 项目结构详解

- **`src/com/apihub/`**：这是核心绑定，你一般不需要修改。它通过 JNA 加载动态库，并提供了 `DataHandle`（数据缓冲）、`AppHandle`（应用上下文）等便利类。
- **`demo/`**：你的代码放在这里。我们会从 `DemoServer` 和 `DemoClient` 开始。
- **`lib/`**：JNA 的 JAR 包，编译和运行时需要。

我们编写的所有程序都会用到 `com.apihub` 包，因此需要在代码头部导入：
```java
import com.apihub.*;
```

---

## 3. 编写第一个服务端（Hello Server）

打开 `demo/DemoServer.java`，它就是我们的第一个服务端程序。我们逐行分析：

```java
package demo;

import com.apihub.*;

public class DemoServer {
    public static void main(String[] args) {
        System.out.println("=== Java API Hub Server Demo ===");

        // 注册 Shutdown Hook 让程序在 Ctrl+C 时优雅退出
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            System.out.println("Shutdown hook triggered.");
            ApiHub.exitMainThread();
            ApiHub.shutdown();
        }));

        // 1. 创建应用（AppHandle）
        try (AppHandle app = new AppHandle("CalcService", "Calculator")) {
            // 2. 注册 API
            CallCallback addCallback = (trigger, input, output) -> {
                // 包装输入输出句柄（不接管所有权）
                DataHandle in = DataHandle.wrapInput(input);
                DataHandle out = DataHandle.wrapOutput(output);
                try {
                    int a = in.readInt();   // 读取第一个整数
                    int b = in.readInt();   // 读取第二个整数
                    int sum = a + b;
                    out.writeInt(sum);      // 写入结果
                    System.out.printf("[Server] add(%d, %d) = %d%n", a, b, sum);
                } catch (Exception e) {
                    System.err.println("Add callback error: " + e.getMessage());
                }
            };
            // 注册名为 "add" 的 Call API
            if (!app.registerCall("add", "a+b", addCallback)) {
                System.err.println("Register 'add' failed");
                return;
            }
            System.out.println("Registered 'add' API");

            // 3. 网络准备
            ApiHub.resetPrepare();                      // 清空之前的状态
            
            // v2.1 新增：运行时配置（可选）
            ApiHub.setOption("Wait_Connection_ReadyOk", "False");
            
            ApiHub.prepareService("ipc:calc_service", "ipc:calc_service"); // 启动 IPC 服务
            ApiHub.prepareClient("ipc:calc_service", app); // 客户端自连（暴露自己的 API）

            if (!ApiHub.prepareDone()) {
                System.err.println("Prepare failed. Check console output for details.");
                return;
            }
            System.out.println("Service started on ipc:calc_service");
            System.out.println("Press Ctrl+C to stop...");

            // 4. 保持主线程运行（可中断循环）
            while (!Thread.currentThread().isInterrupted()) {
                try {
                    Thread.sleep(1000);
                } catch (InterruptedException e) {
                    System.out.println("Interrupted, shutting down...");
                    Thread.currentThread().interrupt();
                    break;
                }
                // 可选：打印状态日志（库会自动输出到控制台）
            }
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
            // 确保清理（尽管 ShutdownHook 也会做）
            ApiHub.exitMainThread();
            ApiHub.shutdown();
        }
    }
}
```

### 关键点解释

- **`AppHandle`**：代表一个逻辑应用，名称 `CalcService` 是网络唯一标识，客户端将用这个名字来调用。
- **`registerCall`**：注册一个请求-响应 API。第一个参数是 API 名称（`"add"`），第二个是描述（随意），第三个是回调函数（Lambda 表达式）。
- **回调函数**：接收三个参数 `trigger`（用户数据，这里没用）、`input`（输入句柄）、`output`（输出句柄）。我们从 `input` 读两个整数，计算和，写入 `output`。
- **网络准备**：
  - `resetPrepare()`：清空之前配置（避免冲突）。
  - `prepareService("ipc:calc_service", "ipc:calc_service")`：启动一个 IPC 服务，地址为 `ipc:calc_service`。IPC 是本机进程间通信，速度极快。
  - `prepareClient("ipc:calc_service", app)`：作为客户端连接到同一个服务，并将 `app` 暴露出去，这样外部就能调用 `CalcService` 的 API。
  - `prepareDone()`：启动框架，阻塞直到网络就绪。返回 `true` 表示成功。
- **v2.1 新特性**：`ApiHub.setOption()` 可在启动前动态调整配置。
- **主循环**：使用可中断循环保持程序运行，直到收到 Ctrl+C。`Thread.sleep(1000)` 让出 CPU。
- **ShutdownHook**：当程序被中断时，调用 `ApiHub.exitMainThread()` 和 `shutdown()` 释放资源。

---

## 4. 编写第一个客户端（Hello Client）

打开 `demo/DemoClient.java`：

```java
package demo;

import com.apihub.*;

public class DemoClient {
    public static void main(String[] args) {
        System.out.println("=== Java API Hub Client Demo ===");

        // 1. 连接服务（纯消费，不暴露 API）
        ApiHub.resetPrepare();
        ApiHub.prepareClient("ipc:calc_service", null); // 第二个参数 null 表示不暴露 API
        if (!ApiHub.prepareDone()) {
            System.err.println("Connect failed. Check console output for details.");
            return;
        }
        System.out.println("Connected to ipc:calc_service");

        // 2. 构造请求
        try (DataHandle param = new DataHandle("add")) {
            param.writeInt(10);
            param.writeInt(20);

            // 3. 远程调用
            try (DataHandle result = ApiHub.call("CalcService", param, 3000)) {
                if (result.getSize() == 0) {
                    System.err.println("Call timed out or failed");
                } else {
                    int sum = result.readInt();
                    System.out.println("10 + 20 = " + sum);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
            ApiHub.exitMainThread();
            ApiHub.shutdown();
        }
    }
}
```

### 关键点解释

- 客户端**不暴露任何 API**，所以 `prepareClient` 第二个参数传 `null`。
- 使用 `new DataHandle("add")` 创建数据句柄，指定要调用的 API 名称。
- 写入两个整数（顺序要与服务端读取顺序一致）。
- `ApiHub.call("CalcService", param, 3000)`：调用远程应用 `CalcService`，超时 3000 毫秒。返回结果句柄。
- 检查 `result.getSize()` 是否为 0，非 0 表示成功，读取整数并打印。
- 最后调用 `exitMainThread` 和 `shutdown` 释放资源。

---

## 5. 运行并验证

### 5.1 编译

在 `java/` 目录下打开 PowerShell，执行：
```powershell
.\build.ps1
```
若成功，会显示 `Compilation succeeded. Classes in .\out`。

### 5.2 启动服务端

```powershell
.\run_server.ps1
```
你会看到：
```
=== Java API Hub Server Demo ===
Registered 'add' API
Service started on ipc:calc_service
Press Ctrl+C to stop...
```

### 5.3 启动客户端（另开终端）

```powershell
.\run_client.ps1
```
输出：
```
=== Java API Hub Client Demo ===
Connected to ipc:calc_service
10 + 20 = 30
```

恭喜！你已经成功完成第一个跨语言 RPC 调用。虽然目前只有 Java，但底层协议与 C++/C#/Python/Go 完全一致。

---

## 6. 深入理解：每一步做了什么？

### 6.1 JNA 的作用

JNA 让 Java 能直接调用 C 动态库中的函数。在 `ApiHubNative.java` 中，我们定义了接口，JNA 会在运行时加载动态库并映射函数。你不需要编写任何 C 代码。

### 6.2 句柄是什么？

- **`DataHandle`**：相当于一个"包裹"，里面装着 API 名称和二进制数据。你往里面写参数，远程服务从里面读参数；服务端往输出句柄写结果，客户端从结果句柄读结果。
- **`AppHandle`**：相当于你的"服务名片"，代表你注册的一组 API。只有通过它注册的 API，才能被远程调用。

### 6.3 回调为何是 Lambda？

`registerCall` 接受一个 `CallCallback` 接口，我们用 Lambda 表达式实现它。这个 Lambda 会被转换为 C 函数指针，由底层库在接收到远程请求时调用。**注意**：Lambda 不能捕获外部可变状态（除非线程安全），否则可能出问题。

### 6.4 地址 `ipc:calc_service` 的含义

- `ipc:` 前缀表示使用操作系统的命名管道/共享内存进行进程间通信，仅限于本机。  
- 你也可以使用 `127.0.0.1:9898` 这样的 TCP 地址，实现跨机器调用（需服务端监听 `0.0.0.0`）。

---

## 7. 扩展：注册多个 API

服务端可以注册任意数量的 API。例如，增加减法、乘法等。只需编写新的回调并用 `registerCall` 注册即可。参考 `FuncServer.java`，它注册了 13 个 API。

```java
app.registerCall("subtract", "a-b", (trigger, input, output) -> {
    DataHandle in = DataHandle.wrapInput(input);
    DataHandle out = DataHandle.wrapOutput(output);
    int a = in.readInt();
    int b = in.readInt();
    out.writeInt(a - b);
});
```

客户端调用时只需改变 API 名称：
```java
try (DataHandle p = new DataHandle("subtract")) {
    p.writeInt(50);
    p.writeInt(30);
    try (DataHandle r = ApiHub.call("CalcService", p, 3000)) {
        System.out.println(r.readInt()); // 20
    }
}
```

---

## 8. 扩展：发送通知（Notify）

通知（Notify）是单向消息，不需要等待响应，适用于日志、事件等。

**服务端注册 Notify**：
```java
app.registerNotify("log", "Logging", (trigger, input) -> {
    DataHandle in = DataHandle.wrapInput(input);
    // 推荐使用空终止字符串，确保跨语言兼容
    String level = in.readStringNullTerminated();
    String msg = in.readStringNullTerminated();
    System.out.println("[" + level + "] " + msg);
});
```

**客户端发送 Notify**：
```java
try (DataHandle p = new DataHandle("log")) {
    p.writeStringNullTerminated("INFO");
    p.writeStringNullTerminated("User logged in");
    ApiHub.notify("LogService", p);
}
```

> **跨语言字符串协议提醒**：为确保与其他语言（C++、Python、Go、Pascal 等）兼容，请使用 `writeStringNullTerminated` / `readStringNullTerminated`，它们写入 UTF-8 字节后追加一个 `\0`，与 Pascal 的 `API_WriteString` 行为一致。旧版 `writeString` / `readString`（长度前缀）仅限 Java 内部使用，不跨语言。

---

## 9. v2.1 新特性：动态注销 API

`AppHandle.unregister()` 方法允许您在运行时移除已注册的 API。

### 9.1 使用示例

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

### 9.2 关键行为

- **本地立即生效**：API 从本地注册表中同步删除。
- **网络异步广播**：删除操作触发 C4 服务网格广播，传播时间约 3 秒（取决于网络延迟）。
- **传播延迟窗口**：在广播传播期间，远程调用可能仍然到达并收到"未找到"错误。

### 9.3 使用场景

- **热卸载插件**：动态库插件可先注销自身 API，再安全卸载。
- **临时维护模式**：临时下线某些功能 API，无需重启整个应用。
- **权限动态调整**：根据用户角色或运行时条件，移除敏感 API 暴露。

---

## 10. v2.1 新特性：运行时配置

`ApiHub.setOption()` 方法允许您在运行时动态调整 API Hub 框架的全局配置选项。

### 10.1 方法签名

```java
public static void setOption(String option, String value)
```

### 10.2 常用选项

| 选项键（主名） | 别名 | 值类型 | 说明 |
|---------------|------|--------|------|
| `password` | `passwd` | 字符串 | 设置 C4 P2PVM 认证令牌。**服务端和客户端必须匹配**。 |
| `Quiet` | — | 布尔 | 启用/禁用静默模式（`True`/`False`）。 |
| `Wait_Connection_ReadyOk` | `Wait_API_Prepare_Done`、`WaitConnect` | 布尔 | 控制 `PrepareDone` 是否阻塞等待所有客户端连接就绪。 |
| `Wait_Connection_Timeout` | `Wait_TimeOut` | 整数（毫秒） | 最大等待时间，默认 `30000`。 |
| `ShowThreadID` | `ShowThread` | 布尔 | 在日志中显示线程 ID。 |
| `ConsoleOutput` | `Console_Output` | 布尔 | 启用/禁用控制台日志输出。 |
| `IPC_Serv_ThreadCount` | `IPC_ThreadCount` | 整数 | IPC 服务线程池大小，默认 `4`。 |
| `IPC_Serv_MaxQueueLength` | `IPC_MaxQueueLength` | 整数 | IPC 消息队列最大长度，默认 `4096`。 |
| `IPC_Serv_MaxMsgSize` | `IPC_MaxMsgSize` | 整数（字节） | 单条 IPC 消息最大大小，默认 `32768`。 |

### 10.3 使用示例

```java
// 设置认证密码（必须在 PrepareDone 之前调用）
ApiHub.setOption("password", "my_secret_token");

// 服务端不等待客户端就绪（适合大规模部署）
ApiHub.setOption("Wait_Connection_ReadyOk", "False");

// 提高 IPC 并发能力
ApiHub.setOption("IPC_Serv_ThreadCount", "8");
```

---

## 11. v2.1 新特性：状态与检查 API

v2.1 新增了五个 API，让你能监控框架运行状态、探测服务可用性、程序化拉取日志。它们全部线程安全，非常适合生产环境的监控和故障排查。

### 11.1 API 概览

| 方法 | 说明 |
|------|------|
| `ApiHub.checkMainThread()` | 返回 `1` 如果模拟主线程（C4 事件循环）正在运行，`0` 否则。 |
| `ApiHub.checkApp(appName)` | 返回 `1` 如果指定应用在线（基于本地缓存，可能短暂滞后），`0` 否则。 |
| `ApiHub.getStatusNum()` | 返回内部日志队列中待读取的消息数量。 |
| `ApiHub.getStatus()` | 从队列中取出一条日志消息（UTF‑8），队列为空返回空字符串。 |
| `ApiHub.postStatus(status)` | 向队列中注入一条自定义日志消息。 |

### 11.2 使用示例

**检查主线程是否运行**（确保框架已就绪）：
```java
if (ApiHub.checkMainThread() == 1) {
    System.out.println("主线程运行正常，可以发起调用");
} else {
    System.err.println("框架未启动，请先调用 prepareDone()");
}
```

**调用前探测目标服务**：
```java
if (ApiHub.checkApp("PaymentService") == 1) {
    try (DataHandle res = ApiHub.call("PaymentService", param, 3000)) {
        // 处理结果
    }
} else {
    // 降级策略：返回缓存或错误码
    System.err.println("PaymentService 不可用，使用降级方案");
}
```

**拉取库日志到你的日志系统**（例如 SLF4J 或 Log4j）：
```java
while (ApiHub.getStatusNum() > 0) {
    String msg = ApiHub.getStatus();
    logger.info("[zAPI] {}", msg);  // 写入统一日志
}
```

**注入自定义日志**：
```java
ApiHub.postStatus("用户会话过期，重定向中...");
```

这些 API 让 Java 开发者不再依赖控制台输出，可以像处理普通日志一样处理库内部消息，极大提升运维效率。

---

## 12. 跨语言调用初体验

现在，你可以尝试用其他语言编写的客户端调用你的 Java 服务。例如，启动 Java 服务端后：

**Python 客户端**：
```python
from api_hub import C4
client = C4("CalcService", "ipc:calc_service")
result = client.add(100, 200)
print(f"100 + 200 = {result}")  # 输出 300
```

**PHP 客户端（通过 Bridge v2.0）**：
```php
require_once 'ZAPIBridgeClient.php';
$client = new ZAPIBridgeClient('http://127.0.0.1:8080/v1');
$result = $client->invoke('CalcService', 'add', [100, 200]);
echo "100 + 200 = " . $result . "\n";  // 输出 300
```

**Go 客户端**：
```go
client, _ := api_hub.NewClient()
client.PrepareClient("ipc:calc_service")
client.PrepareDone()
h, _ := client.CreateDataHnd("add")
client.WriteInt32(h, 100)
client.WriteInt32(h, 200)
res, _ := client.Call("CalcService", h, 3000)
sum, _ := client.ReadInt32(res)
fmt.Printf("100 + 200 = %d\n", sum)  // 输出 300
```

这种无缝互操作正是 API Hub 的魅力所在。所有语言使用相同的二进制协议和地址格式，因此无论服务端用什么语言实现，客户端都不需要调整代码。

---

## 13. 常见错误与解决方法

### 13.1 `UnsatisfiedLinkError: Unable to load library 'z_api_hub64'`
- **原因**：动态库找不到。  
- **解决**：将 `Binary/` 目录加入系统 `PATH`，或复制 `z_api_hub64.dll` 到 `java/` 目录。

### 13.2 `ClassNotFoundException: demo.DemoServer`
- **原因**：未编译或类路径不对。  
- **解决**：执行 `.\build.ps1`，确保 `out` 目录存在 `.class` 文件。

### 13.3 客户端调用超时（返回句柄大小为 0）
- **原因**：服务端未启动，或地址不一致。  
- **解决**：检查服务端是否运行；客户端 `prepareClient` 地址必须与服务端 `prepareService` 公布的地址一致；检查应用名称大小写是否匹配（`CalcService` vs `calcservice`）。

### 13.4 回调未触发
- **原因**：注册时 API 名称拼写错误，或客户端未正确连接。  
- **解决**：检查 `registerCall` 和 `new DataHandle` 中的名称是否完全一致（包括大小写）；查看控制台输出，或使用 `checkApp` 探测目标服务是否在线。

### 13.5 编译时出现 `编码 GBK 的不可映射字符`
- **原因**：源文件是 UTF-8，而 `javac` 默认使用系统编码（如 GBK）。  
- **解决**：编译时添加 `-encoding UTF-8` 参数（我们的 `build.ps1` 已包含）。

### 13.6 v2.1 动态注销后仍有请求到达
- **原因**：广播传播需要时间（约 3 秒），这是分布式系统的正常行为。
- **解决**：等待广播完成，或在客户端实现重试逻辑。

### 13.7 如何获取库内部的详细日志？
- 使用 `getStatusNum()` / `getStatus()` 拉取日志，或直接查看控制台输出。也可使用 `postStatus()` 注入自定义日志便于关联分析。

---

## 14. 下一步学什么

- **阅读《Java 使用指南》**：深入了解所有 API 和高级用法。  
- **尝试 `FuncServer` 和 `FuncClient`**：体验 13 个 API 和并发压测，理解性能特性。  
- **探索其他语言绑定**：查看 `C++/`、`C#/`、`Py/` 等目录，编写多语言协作的示例。  
- **将你的业务逻辑封装为 API**：比如加密、图像处理、数据库操作，让其他语言调用。  
- **学习分布式概念**：服务发现、负载均衡、自动重连等，API Hub 已为你实现。
- **掌握 v2.1 新特性**：尝试使用状态与检查 API，将库日志集成到你的监控系统，实现生产级可观测性。

---

## 📚 附录：常用 API 速查

| 操作 | 方法 |
|------|------|
| 创建应用 | `new AppHandle("MyApp", "desc")` |
| 注册 Call | `app.registerCall("api", "desc", callback)` |
| 注册 Notify | `app.registerNotify("api", "desc", callback)` |
| **动态注销（v2.1）** | `app.unregister("api")` |
| **运行时配置（v2.1）** | `ApiHub.setOption("key", "value")` |
| **检查主线程（v2.1）** | `ApiHub.checkMainThread()` |
| **检查应用在线（v2.1）** | `ApiHub.checkApp("appName")` |
| **获取日志数量（v2.1）** | `ApiHub.getStatusNum()` |
| **获取日志消息（v2.1）** | `ApiHub.getStatus()` |
| **注入自定义日志（v2.1）** | `ApiHub.postStatus("message")` |
| 创建数据句柄 | `new DataHandle("apiName")` |
| 写入整数 | `data.writeInt(int)` |
| 读取整数 | `int v = data.readInt()` |
| 写入字符串（跨语言） | `data.writeStringNullTerminated(String)` |
| 读取字符串（跨语言） | `String s = data.readStringNullTerminated()` |
| 写入字节 | `data.write(byte[])` |
| 读取字节 | `byte[] b = data.read(len)` |
| 获取大小 | `data.getSize()` |
| 重置位置 | `data.setPos(0)` |
| 准备网络 | `ApiHub.resetPrepare(); prepareService(...); prepareClient(...); prepareDone()` |
| 远程调用 | `ApiHub.call("AppName", param, timeout)` |
| 发送通知 | `ApiHub.notify("AppName", param)` |
| 关闭 | `ApiHub.exitMainThread(); ApiHub.shutdown();` |

---

**你已经完成了入门学习！** 现在，尝试修改代码，添加自己的 API，或与同事用不同语言编写服务，感受跨语言协作的便捷。如果遇到困难，记得检查控制台输出或使用 `getStatus()` ——它几乎能告诉你所有底层信息。

祝你编码愉快，开启分布式之旅！🚀

---

*[项目地址](https://github.com/PassByYou888/zAPI) | [问题反馈](https://github.com/PassByYou888/zAPI/issues)*


## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](../C++/API%20Hub%20Tool%20C++%20使用指南.md)
- [API Hub Tool C 语言使用指南](../C++/API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](../Py/从零到一，掌握多语言互调.md)
- [API Hub for Go 从零到一掌握多语言互调](../Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)
- [zAPI Rust 使用指南](../rust/zAPI%20Rust%20使用指南.md)
- [API Hub Java 使用指南](API%20Hub%20Java%20使用指南.md)
- [API Hub Tool for C# — 完整使用指南](../C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [API Hub Tool for Pascal](../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../node/Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](../Py/web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](../Py/web/js_api.py%20使用指南.md)
- [📖 ZAPI Bridge 完整使用手册](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)
