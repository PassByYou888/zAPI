# API Hub Tool C++ 使用指南

**用现代 C++ 拥抱分布式 API 生态，一行代码打通所有语言**

**版本：** 2.1（与 ZAPI 核心 v2.1 同步）

---

## 目录

1. [概述](#1-概述)
2. [环境准备与库加载](#2-环境准备与库加载)
3. [核心概念速览](#3-核心概念速览)
4. [RAII 包装入门](#4-raii-包装入门)
5. [数据句柄（DataHandle）操作](#5-数据句柄datahandle操作)
6. [应用句柄（App）与 API 注册](#6-应用句柄app与-api-注册)
7. [本地调用（无网络）](#7-本地调用无网络)
8. [动态注销 API](#8-动态注销-api)
9. [运行时配置](#9-运行时配置)
10. [网络层准备与启动](#10-网络层准备与启动)
11. [远程调用与通知](#11-远程调用与通知)
12. [状态与检查 API（新增）](#12-状态与检查-api新增)
13. [线程安全与回调上下文（重要）](#13-线程安全与回调上下文重要)
14. [高级主题](#14-高级主题)
15. [调试与错误处理](#15-调试与错误处理)
16. [完整示例：服务端 + 客户端](#16-完整示例服务端--客户端)
17. [FAQ](#17-faq)
18. [总结与资源](#18-总结与资源)

---

## 1. 概述

API Hub Tool 是一个**基于纯 C ABI 的分布式 RPC 框架**，并提供**现代 C++ RAII 包装**（`API_HubTool.hpp`）。它让您的 C++ 应用程序能够：

- 将任何 C++ 函数暴露为远程可调用 API（请求-响应或单向通知）
- 无缝调用其他语言（C、Python、Go、Rust、Java、C#、Pascal、PHP、Node.js 等）注册的服务
- 在同一台机器上通过 IPC（< 1ms）或跨机器通过 TCP 进行通信
- **v2.1 新增**：提供 `API_Check_MainThread`、`API_Check_App`、`API_Get_Status_Num`、`API_Get_Status`、`API_Post_Status` 五个状态与检查 API，方便调试和监控。

**C++ 包装的核心优势：**
- **RAII 自动管理**：`DataHandle`、`App`、`LibraryLoader` 自动构造/析构，告别手动 `new`/`delete` 和资源泄漏。
- **类型安全**：`write()` / `read()` 模板函数支持任意可平凡复制类型。
- **异常安全**：所有错误抛出 `z_api_hub::ApiError` 异常。
- **零额外开销**：头文件实现，内联函数，性能与裸 C 调用无异。
- **v2.1 新增**：支持通过 C 函数直接使用状态与检查 API（未来 RAII 包装将提供更友好的封装）。

本指南将手把手带您从零开始掌握 API Hub 的 C++ 接口，并深入理解其设计哲学。

---

## 2. 环境准备与库加载

### 2.1 动态库文件

根据您的操作系统和位数，下载对应的动态库：

| 平台 | 文件名 |
|------|--------|
| Windows 64-bit | `z_api_hub64.dll` |
| Windows 32-bit | `z_api_hub32.dll` |
| Linux (包括 BSD) | `libz_api_hub.so` |
| macOS | `libz_api_hub.dylib` |

将动态库放在可执行文件目录或系统搜索路径（Windows 的 `PATH`，Linux 的 `LD_LIBRARY_PATH`，macOS 的 `DYLD_LIBRARY_PATH`）。

**依赖库**（需与主库同目录）：
- Windows：`z_ipc_64.dll` / `z_ipc_32.dll`
- Linux/BSD：`libz_ipc.so`
- macOS：`libz_ipc.dylib`（如有）

### 2.2 包含头文件

从项目获取 `API_HubTool.hpp`（它内部会包含 `API_HubTool.h`）。在您的 C++ 源文件中包含：

```cpp
#include "API_HubTool.hpp"
```

### 2.3 编译与链接

编译时需包含 `API_HubTool.c`，并链接必要的系统库：

- **Windows**：无需额外库（默认链接 kernel32）。
- **Linux / macOS**：需要链接 `libdl`（动态加载库）。

示例（Linux）：
```bash
g++ -std=c++17 -o myapp myapp.cpp API_HubTool.c -ldl
```

或者使用 CMake，将 `API_HubTool.c` 添加为源文件。

### 2.4 加载动态库（自动）

`z_api_hub::LibraryLoader` 对象在构造时自动调用 `API_LoadLibrary()`，析构时自动调用 `API_FreeLibrary()`。您只需创建它：

```cpp
try {
    z_api_hub::LibraryLoader loader;  // 自动加载
    // ... 使用 API ...
} catch (const z_api_hub::ApiError& e) {
    std::cerr << e.what() << std::endl;
}
// 退出时 loader 析构，自动卸载库
```

---

## 3. 核心概念速览

在开始编码前，理解以下核心概念：

- **TDataHnd（C 句柄）** → **`z_api_hub::DataHandle`（C++ 类）**：二进制缓冲区，存储"API 名称"和"载荷数据"。RAII 管理，自动释放。
- **TAppHnd（C 句柄）** → **`z_api_hub::App`（C++ 类）**：逻辑应用，可注册多个 API。RAII 管理。
- **回调函数（`TAPI_Call` / `TAPI_Notify`）**：实现业务逻辑的 C 风格函数（`__cdecl`），在 RAII 包装中仍使用原始 C 回调（因为需要 ABI 稳定）。
- **动态注销**：`App::unregister()` 运行时移除 API，触发网络广播。
- **运行时配置**：`setOption()` 动态调整认证密码、等待连接、IPC 线程池等参数。
- **状态与检查（v2.1 新增）**：`API_Check_MainThread`、`API_Check_App` 用于查询框架状态，`API_Get_Status_Num`/`API_Get_Status`/`API_Post_Status` 提供日志队列访问。

**RAII 生命周期示意：**
```cpp
{
    z_api_hub::LibraryLoader loader;            // 加载库
    z_api_hub::App app("MyApp", "Demo");        // 创建应用
    // 注册回调...
    z_api_hub::DataHandle param("add");         // 创建数据
    param.write(10);                            // 写入
    auto result = app.localCall(param);         // 本地调用
    // 所有资源在离开作用域时自动释放
}
```

---

## 4. RAII 包装入门

### 4.1 命名空间

所有 C++ 符号位于 `z_api_hub` 命名空间：

```cpp
using namespace z_api_hub;  // 可选
```

### 4.2 LibraryLoader

```cpp
LibraryLoader loader;  // 加载动态库，失败抛出 ApiError
```

`LibraryLoader` 不可拷贝，但可移动。

### 4.3 异常处理

所有包装函数在失败时抛出 `z_api_hub::ApiError`（派生自 `std::runtime_error`）。建议用 `try-catch` 包围主逻辑。

---

## 5. 数据句柄（DataHandle）操作

### 5.1 创建与释放（自动）

```cpp
DataHandle param("add");   // 创建，关联 API 名称 "add"
// 析构时自动调用 API_Free_DataHnd
```

如果想借用已有句柄（如在回调中），使用带 `bool` 参数的构造函数：

```cpp
DataHandle borrowed(static_cast<TDataHnd>(input), false);  // false = 不拥有
DataHandle owned(static_cast<TDataHnd>(result), true);     // true = 拥有，析构时释放
```

### 5.2 写入数据

```cpp
param.write(5);   // 写入 int（重载）
param.write(7);
// 等价于：
int a = 5;
param.write(&a, sizeof(a));
```

`write()` 始终从当前读写位置开始追加，位置自动后移。初始位置为 0。

### 5.3 读取数据

```cpp
int sum;
param.read(sum);   // 读取 int（重载）
// 等价于：
param.read(&sum, sizeof(sum));
```

注意读取会从当前位置读取，并自动移动位置。通常调用前需 `seek(0)` 重置。

### 5.4 位置与大小管理

```cpp
int64_t pos = param.pos();          // 当前偏移
param.seek(0);                       // 重置到开头
int64_t size = param.size();         // 总大小
const void* buf = param.buffer();    // 直接指针（零拷贝，只读）
```

### 5.5 释放所有权

如果不想让 DataHandle 析构时释放底层句柄，可以 `release()`：

```cpp
TDataHnd raw = param.release();  // 转移所有权，param 不再管理
// 之后需要手动 API_Free_DataHnd(raw)
```

---

## 6. 应用句柄（App）与 API 注册

### 6.1 创建应用

```cpp
App app("MyService", "My service description");
```

应用名在网络中必须唯一，区分大小写。

### 6.2 注册 Call API

回调函数必须是 `__cdecl` 的 C 函数（或静态函数），因为底层是 C ABI。

```cpp
static void __cdecl MyAdd(void* trigger, void* input, void* output) {
    DataHandle in(static_cast<TDataHnd>(input), false);   // 借用
    DataHandle out(static_cast<TDataHnd>(output), false);

    int a, b;
    if (in.read(a) != sizeof(a) || in.read(b) != sizeof(b))
        return;
    int sum = a + b;
    out.write(sum);
}

// 注册
if (!API_Reg_Call(app.get(), "add", "Add two integers", nullptr, MyAdd)) {
    // 名称已存在或错误
}
```

- `trigger`：用户数据指针，回调时传回，可用于传递上下文。
- `input`：只读，不要释放。
- `output`：写入结果，不要释放。

### 6.3 注册 Notify API

```cpp
static void __cdecl MyLogger(void* trigger, void* input) {
    DataHandle in(static_cast<TDataHnd>(input), false);
    const char* msg = static_cast<const char*>(in.buffer());
    std::cout << "Log: " << msg << std::endl;
}

API_Reg_Notify(app.get(), "log", "Log a message", nullptr, MyLogger);
```

### 6.4 App 自动释放

`App` 析构时自动调用 `API_Free_APPHnd`。

---

## 7. 本地调用（无网络）

本地调用用于同一进程内测试，不经过网络。

```cpp
DataHandle param("add");
param.write(10);
param.write(20);

auto result = app.localCall(param);   // result 是 DataHandle，拥有句柄

int sum;
result.read(sum);
std::cout << "10 + 20 = " << sum << std::endl;
// param 和 result 在作用域结束时自动释放
```

---

## 8. 动态注销 API

`App::unregister()` 方法允许您在运行时移除已注册的 API。

### 8.1 方法签名

```cpp
bool unregister(const std::string& apiName);
```

### 8.2 使用示例

```cpp
App app("MyService", "Demo service");
app.register_call("add", "Addition", nullptr, MyAdd);
app.register_call("echo", "Echo", nullptr, MyEcho);

// ... 运行一段时间后 ...

// 动态注销 'add' API
if (app.unregister("add")) {
    std::cout << "API 'add' unregistered, broadcast in progress." << std::endl;
} else {
    std::cout << "API 'add' not found." << std::endl;
}

// 'add' 不再可用，但 'echo' 仍然可用
```

### 8.3 关键行为

- **本地立即生效**：API 从本地注册表中同步删除。
- **网络异步广播**：删除操作触发 C4 服务网格广播，传播时间约 3 秒（取决于网络延迟）。
- **传播延迟窗口**：在广播传播期间，远程调用可能仍然到达并收到"未找到"错误。

### 8.4 使用场景

- **热卸载插件**：动态库插件可先注销自身 API，再安全卸载。
- **临时维护模式**：临时下线某些功能 API，无需重启整个应用。
- **权限动态调整**：根据用户角色或运行时条件，移除敏感 API 暴露。

---

## 9. 运行时配置

`setOption()` 函数允许您在运行时动态调整 API Hub 框架的全局配置选项。

### 9.1 函数签名

```cpp
void setOption(const std::string& option, const std::string& value);
```

### 9.2 支持的选项

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

### 9.3 使用示例

```cpp
// 设置认证密码（必须在 PrepareDone 之前调用）
z_api_hub::setOption("password", "my_secret_token");

// 服务端不等待客户端就绪（适合大规模部署）
z_api_hub::setOption("Wait_Connection_ReadyOk", "False");

// 提高 IPC 并发能力
z_api_hub::setOption("IPC_Serv_ThreadCount", "8");

// 开启详细日志（调试时使用）
z_api_hub::setOption("ConsoleOutput", "True");
z_api_hub::setOption("ShowThreadID", "True");
```

---

## 10. 网络层准备与启动

### 10.1 重置准备状态

```cpp
z_api_hub::resetPrepare();   // 调用 API_Reset_Prepare
```

### 10.2 准备服务端

```cpp
API_Prepare_Service("0.0.0.0", "127.0.0.1:9898");   // TCP
API_Prepare_Service("ipc:my_service", "ipc:my_service"); // IPC
```

### 10.3 准备客户端

```cpp
API_Prepare_Client("127.0.0.1:9898", app.get());   // 暴露 app
API_Prepare_Client("ipc:my_service", nullptr);      // 纯消费端
```

### 10.4 启动框架

```cpp
if (API_Prepare_Done() != 1) {
    // 失败，检查控制台输出
    std::cerr << "Prepare failed. Check console output for details." << std::endl;
    // 清理并退出
}
```

> **调试说明**：库会将详细的运行日志（包括连接状态、注册信息、错误原因）自动输出到控制台。你可以在 `<可执行文件名>.api-tool.ini` 配置文件中调整日志行为。

---

## 11. 远程调用与通知

### 11.1 远程调用（API_Call）

```cpp
DataHandle param("add");
param.write(10);
param.write(20);

// 调用应用 "MyService"，超时 5000ms
TDataHnd rawResult = API_Call("MyService", param.get(), 5000);
// 注意：param 仍然存在，但我们已传递内部句柄，API_Call 会克隆数据，所以 param 仍需释放（由析构完成）

if (rawResult && API_GetSize(rawResult) > 0) {
    DataHandle result(rawResult, true);  // 接管所有权
    int sum;
    result.read(sum);
    std::cout << "Sum = " << sum << std::endl;
} else {
    if (rawResult) API_Free_DataHnd(rawResult);  // 防止泄漏
}
```

更简洁的做法：用 `DataHandle` 包装返回值：

```cpp
DataHandle result(API_Call("MyService", param.get(), 5000), true);
if (result && result.size() > 0) { ... }
```

### 11.2 通知（API_Notify）

```cpp
DataHandle param("log");
const char* msg = "Hello from C++";
param.write(msg, strlen(msg) + 1);
API_Notify("MyService", param.get());
// param 析构时自动释放
```

---

## 12. 状态与检查 API（新增）

本版本新增了五个 C 函数，您可以直接调用它们（即使使用 C++ RAII 包装，这些函数也是可用的，因为它们来自底层 C API）。未来版本可能提供更友好的 C++ 封装，但目前您可以直接使用 `API_` 前缀的函数。

### 12.1 `API_Check_MainThread`

```c
int API_Check_MainThread(void);
```

检查模拟主线程（C4 事件循环）是否正在运行。

- **返回值**：`1` 表示正在运行，`0` 表示已停止或尚未启动。
- **用途**：在调用远程 API 前确认框架已就绪，或在退出前确认主循环状态。
- **示例**：
  ```cpp
  if (API_Check_MainThread()) {
      std::cout << "主线程正在运行\n";
  } else {
      std::cout << "主线程已停止\n";
  }
  ```

### 12.2 `API_Check_App`

```c
int API_Check_App(const char* appName);
```

检查网络中是否存在指定名称的应用（基于本地缓存，可能有短暂滞后）。

- **参数**：`appName` – 应用名称（UTF‑8，区分大小写）。
- **返回值**：`1` 表示存在至少一个实例，`0` 表示不存在。
- **用途**：在调用 `API_Call` 前探测目标应用是否在线，避免无效超时。
- **示例**：
  ```cpp
  if (API_Check_App("MyService")) {
      // 安全调用
      DataHandle result(API_Call("MyService", param.get(), 5000), true);
  } else {
      std::cout << "MyService 当前不可用\n";
  }
  ```

### 12.3 日志队列 API

库内部维护一个 FIFO 日志队列，最多存储 **1000 条**消息，溢出时丢弃最旧的消息。

#### `API_Get_Status_Num`

```c
int API_Get_Status_Num(void);
```

返回当前队列中待读取的日志条数。

#### `API_Get_Status`

```c
const char* API_Get_Status(void);
```

取出队列头部的一条日志消息，返回指向内部静态缓冲区的指针（UTF‑8 编码，空终止）。**注意**：该指针在下次调用 `API_Get_Status` 时可能被覆盖，调用者应尽快复制内容。

- **返回**：若队列为空，返回空字符串 `""`。
- **示例**：
  ```cpp
  while (API_Get_Status_Num() > 0) {
      const char* msg = API_Get_Status();
      std::cout << "[库日志] " << msg << std::endl;
  }
  ```

#### `API_Post_Status`

```c
void API_Post_Status(const char* status);
```

向队列中注入一条自定义日志消息，与库自身日志混合输出。

- **参数**：`status` – UTF‑8 字符串，会原样加入队列。
- **用途**：将应用层日志统一纳入 API Hub 的日志流，便于集中监控。
- **示例**：
  ```cpp
  API_Post_Status("应用初始化完成");
  ```

---

## 13. 线程安全与回调上下文（重要）

### 13.1 导出函数线程安全

**所有 API 函数都是完全线程安全的**。您可以在多个线程中同时调用 `API_Call`、`DataHandle::write` 等，无需外部锁。

但**同一 `DataHandle` 对象的写操作（`write`、`seek`、`reset`）应串行化**，避免数据竞争。不同句柄可自由并发。

### 13.2 回调执行上下文

**您的回调函数（`TAPI_Call`、`TAPI_Notify`）是在后台线程池线程中执行的**，而不是在调用 `API_Call` 的线程。

这带来以下约束：
- ❌ **禁止**在回调中调用 `API_Call` 或 `API_Notify` —— 可能导致死锁。
- ❌ **禁止**长时间阻塞（如 `std::this_thread::sleep_for`、等待互斥锁等）。
- ❌ **禁止**直接访问 UI 组件或线程局部存储（除非同步）。
- ✅ **推荐**将耗时任务或需要远程调用的请求放入队列，由独立工作线程处理，回调快速返回。

```cpp
// ❌ 错误做法
static void __cdecl BadCallback(void*, void* input, void*) {
    DataHandle in(input, false);
    // 死锁风险！
    TDataHnd res = API_Call("OtherApp", in.get(), 5000);
}

// ✅ 正确做法
static void __cdecl GoodCallback(void*, void* input, void*) {
    DataHandle in(input, false);
    // 将数据复制或移动，投递到工作队列
    g_queue.Push(in.buffer(), in.size());
    // 快速返回
}
```

### 13.3 执行顺序不保证

由于负载均衡，并发请求可能被路由到不同实例，**调用顺序不保证**。需要顺序的业务请自行实现序列号或单线程调度。

---

## 14. 高级主题

### 14.1 并发调用

利用线程安全轻松实现高并发：

```cpp
#include <thread>
#include <vector>

void call_add(int a, int b) {
    DataHandle param("add");
    param.write(a);
    param.write(b);
    DataHandle result(API_Call("MyService", param.get(), 5000), true);
    if (result && result.size() >= sizeof(int)) {
        int sum;
        result.read(sum);
        // ... 处理结果
    }
}

std::vector<std::thread> threads;
for (int i = 0; i < 100; ++i)
    threads.emplace_back(call_add, i, i*2);
for (auto& t : threads) t.join();
```

### 14.2 IPC vs TCP

- **IPC**（`ipc:服务名`）：同机通信，延迟 < 1 ms，吞吐极高。适合单机微服务。
- **TCP**：跨机通信，支持 IPv4/IPv6，可配置端口。延迟取决于网络。

### 14.3 多实例部署

多个服务实例注册**相同应用名**，客户端自动负载均衡。每个实例可监听不同地址。

### 14.4 自定义类型序列化

由于 `DataHandle::write` 和 `read` 支持任意可平凡复制类型，可直接传递结构体：

```cpp
struct Point { int x, y; };

Point p{10, 20};
DataHandle param("transform");
param.write(p);  // 直接写入结构体

// 回调中读取
Point pt;
in.read(pt);
```

对于非平凡类型（如 `std::string`），需手动序列化（写入长度+数据）。可参考示例中的 `WriteString`/`ReadString` 辅助函数。

---

## 15. 调试与错误处理

### 15.1 利用日志 API 获取详细运行信息

库会在运行过程中自动输出大量诊断信息（连接状态、注册结果、错误原因等）。您可以通过 `API_Get_Status_Num` / `API_Get_Status` 在自己的主循环中拉取这些日志，实时监控框架状态。

**典型用法**（在主循环中定期调用）：
```cpp
void PollLogs() {
    while (API_Get_Status_Num() > 0) {
        const char* msg = API_Get_Status();
        // 将 msg 写入文件、网络或控制台
        std::cout << msg << std::endl;
    }
}
```

也可通过 `API_Post_Status` 注入自定义日志，统一管理所有输出。

### 15.2 捕获异常

```cpp
try {
    // API 操作
} catch (const z_api_hub::ApiError& e) {
    std::cerr << "API Error: " << e.what() << std::endl;
}
```

### 15.3 常见错误

| 错误信息 | 原因 | 解决方案 |
|---------|------|---------|
| `no found app("XXX") api("YYY")` | 目标应用未注册或 API 名不匹配 | 检查大小写，确认客户端已注册成功；使用 `API_Check_App` 提前探测 |
| `bind address already in use` | 端口被占用 | 更换端口或结束占用进程 |
| `timeout` | 响应超时 | 增加超时值，检查网络连通性；查看日志排查目标是否在线 |
| `Prepare_Done failed` | 网络初始化失败 | 查看 `API_Get_Status` 输出的具体错误信息 |

---

## 16. 完整示例：服务端 + 客户端

### 16.1 服务端（使用 RAII + 日志轮询）

```cpp
#include "API_HubTool.hpp"
#include <iostream>
#include <thread>
#include <chrono>

using namespace z_api_hub;

static void __cdecl AddCallback(void*, void* input, void* output) {
    DataHandle in(static_cast<TDataHnd>(input), false);
    DataHandle out(static_cast<TDataHnd>(output), false);
    int a, b;
    if (in.read(a) != sizeof(a) || in.read(b) != sizeof(b)) return;
    int sum = a + b;
    out.write(sum);
}

static void __cdecl EchoCallback(void*, void* input, void* output) {
    DataHandle in(static_cast<TDataHnd>(input), false);
    DataHandle out(static_cast<TDataHnd>(output), false);
    const void* buf = in.buffer();
    int64_t sz = in.size();
    if (sz > 0) out.write(buf, sz);
}

int main() {
    try {
        LibraryLoader loader;
        App app("ServiceApp", "Demo Service");

        API_Reg_Call(app.get(), "add", "Add", nullptr, AddCallback);
        API_Reg_Call(app.get(), "echo", "Echo", nullptr, EchoCallback);

        resetPrepare();
        API_Prepare_Service("0.0.0.0", "127.0.0.1:9898");
        API_Prepare_Service("ipc:demo", "ipc:demo");
        API_Prepare_Client("127.0.0.1:9898", app.get());
        API_Prepare_Client("ipc:demo", app.get());

        if (API_Prepare_Done() != 1) {
            std::cerr << "Prepare failed. Check console output for details." << std::endl;
            return 1;
        }
        std::cout << "Service running. Press Enter to exit." << std::endl;

        // 在主循环中轮询日志
        while (!std::cin.get()) {
            while (API_Get_Status_Num() > 0) {
                const char* msg = API_Get_Status();
                std::cout << "[Log] " << msg << std::endl;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }

        API_Exit_MainThread();
        API_shutdown();
    } catch (const ApiError& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
    return 0;
}
```

### 16.2 客户端（使用 RAII + 状态检查）

```cpp
#include "API_HubTool.hpp"
#include <iostream>

using namespace z_api_hub;

int main() {
    try {
        LibraryLoader loader;
        resetPrepare();
        API_Prepare_Client("ipc:demo", nullptr);
        API_Prepare_Client("127.0.0.1:9898", nullptr);

        if (API_Prepare_Done() != 1) {
            std::cerr << "Connect failed. Check console output for details." << std::endl;
            return 1;
        }

        // 检查主线程是否运行
        if (!API_Check_MainThread()) {
            std::cerr << "Main thread not running." << std::endl;
            return 1;
        }

        // 检查目标应用是否在线
        if (!API_Check_App("ServiceApp")) {
            std::cerr << "ServiceApp not available." << std::endl;
            return 1;
        }

        // 调用 add
        DataHandle param("add");
        param.write(10);
        param.write(20);
        DataHandle result(API_Call("ServiceApp", param.get(), 5000), true);
        if (result && result.size() >= sizeof(int)) {
            int sum;
            result.read(sum);
            std::cout << "10 + 20 = " << sum << std::endl;
        } else {
            std::cout << "add call failed." << std::endl;
        }

        // 调用 echo
        DataHandle param2("echo");
        const char* msg = "Hello from C++ client!";
        param2.write(msg, strlen(msg) + 1);
        DataHandle result2(API_Call("ServiceApp", param2.get(), 5000), true);
        if (result2 && result2.size() > 0) {
            std::string reply(static_cast<const char*>(result2.buffer()), result2.size());
            std::cout << "Echo reply: " << reply << std::endl;
        }

        API_Exit_MainThread();
        API_shutdown();
    } catch (const ApiError& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
    return 0;
}
```

---

## 17. FAQ

**Q1: 为什么我的回调没有被调用？**
A: 检查应用名和 API 名是否完全匹配（大小写）。确认客户端已成功连接并注册（查看控制台输出或使用 `API_Get_Status` 拉取日志）。`API_Prepare_Done` 是否成功？

**Q2: 可以在回调中调用 `API_Call` 吗？**
A: **不可以**。会导致死锁。请将请求放入队列，由独立线程处理。

**Q3: 多个线程同时调用 `API_Call` 安全吗？**
A: 是的，所有导出函数都是线程安全的。但同一 `DataHandle` 的写操作需串行化。

**Q4: 如何处理超时？**
A: `API_Call` 超时后返回的句柄大小为 0。可增加超时值或检查网络。超时值 0 表示无限等待，慎用。

**Q5: 我可以在同一进程运行多个应用吗？**
A: 可以。创建多个 `App` 对象，注册不同的 API 集，分别准备客户端即可。

**Q6: 如何处理大型数据？**
A: 使用 `DataHandle::buffer()` 零拷贝访问，或直接操作指针。可考虑压缩（库内置支持）。

**Q7: 动态注销 API 后，正在进行的调用会怎样？**
A: 正在执行中的回调不会被打断，它们会正常完成。新到达的请求会在广播传播后收到"未找到"错误。

**Q8: 如何查看库内部的详细运行日志？**
A: 使用 `API_Get_Status_Num` 和 `API_Get_Status` 在您的循环中拉取日志。库会输出连接状态、注册结果、错误原因等详细信息。您也可以使用 `API_Post_Status` 注入自定义日志。

---

## 18. 总结与资源

您已掌握 API Hub Tool 的 C++ RAII 包装的全部核心用法，包括新增的状态与检查 API。现在您可以：

- 用现代 C++ 编写高性能服务，暴露给任何语言消费。
- 用 C++ 编写客户端，调用其他语言的服务。
- 利用 IPC 实现微秒级同机通信，或通过 TCP 构建跨云分布式系统。
- 通过新日志 API 实现精细化的运行时监控。

**进一步学习资源：**
- [API_HubTool.hpp](API_HubTool.hpp) —— 完整 C++ RAII API 参考（内含详尽注释）
- [API_HubTool.h](API_HubTool.h) —— 底层 C API 参考
- [Pascal 完整指南](../pascal/API%20Hub%20Tool%20for%20Pascal.md) —— 概念相通，可作为补充
- 示例代码：`HelloWorldSTL.cpp`（RAII 本地调用）、`Service.cpp` / `Client1.cpp`（网络调用）、`func_service.cpp` / `func_client.cpp`（复杂示例）

**社区支持：** 作者（QQ：600585）

---

**从今天起，您的 C++ 代码可以轻松拥抱多语言生态。**  
API Hub Tool 让语言边界消失，让分布式开发回归简单。

## 📚 相关资源（其他语言指南）

- [API Hub Tool C 语言使用指南](API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](../Py/从零到一，掌握多语言互调.md)
- [API Hub for Go 从零到一掌握多语言互调](../Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)
- [zAPI Rust 使用指南](../rust/zAPI%20Rust%20使用指南.md)
- [API Hub Java 使用指南](../java/API%20Hub%20Java%20使用指南.md)
- [API Hub Tool for C# — 完整使用指南](../C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [API Hub Tool for Pascal](../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../node/Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](../Py/web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](../Py/web/js_api.py%20使用指南.md)
