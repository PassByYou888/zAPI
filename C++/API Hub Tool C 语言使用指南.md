# API Hub Tool C 语言使用指南

**从零开始，用 C 语言打造跨语言分布式系统**

**版本：** 2.0（与 ZAPI 核心 v2.0 同步）

---

## 目录

1. [概述](#1-概述)
2. [环境准备与库加载](#2-环境准备与库加载)
3. [核心概念速览](#3-核心概念速览)
4. [数据句柄（TDataHnd）操作](#4-数据句柄tdatahnd操作)
5. [应用句柄（TAppHnd）与 API 注册](#5-应用句柄tapphnd与-api-注册)
6. [本地调用（无网络）](#6-本地调用无网络)
7. [动态注销 API（新增）](#7-动态注销-api新增)
8. [运行时配置（新增）](#8-运行时配置新增)
9. [网络层准备与启动](#9-网络层准备与启动)
10. [远程调用与通知](#10-远程调用与通知)
11. [线程安全与回调上下文（重要）](#11-线程安全与回调上下文重要)
12. [高级主题](#12-高级主题)
13. [调试与错误处理](#13-调试与错误处理)
14. [完整示例：服务端 + 客户端](#14-完整示例服务端--客户端)
15. [FAQ](#15-faq)
16. [总结与资源](#16-总结与资源)

---

## 1. 概述

API Hub Tool 是一个**基于纯 C ABI 的分布式 RPC 框架**，它允许您用 C 语言编写服务端和客户端，并让这些服务被任何支持 C 动态库调用的语言（Python、C#、Java、Go、Rust、Pascal、PHP、Node.js 等）无缝调用。反之，您也可以用 C 语言调用其他语言编写的服务。

**核心设计哲学：**
- **极简接口**：只有 20 多个函数，覆盖创建、读写、注册、调用、关闭全流程。
- **显式生命周期**：所有句柄（TDataHnd、TAppHnd）都由您显式创建和释放，无隐藏开销。
- **跨语言通用**：纯 C ABI，任何支持 FFI 的语言都能直接使用。
- **内置服务网格**：自动服务发现、负载均衡、断线重连、NAT 穿透，开箱即用。
- **v2.0 新增**：支持 `API_UnReg` 动态注销 API 和 `API_SetOption` 运行时配置。

本指南将手把手带您从零开始掌握 API Hub 的 C 语言接口，并理解其背后的关键设计。

---

## 2. 环境准备与库加载

### 2.1 动态库文件

根据您的操作系统和位数，下载对应的动态库：

| 平台 | 文件名 |
|------|--------|
| Windows 64-bit | `z_api_hub64.dll` |
| Windows 32-bit | `z_api_hub32.dll` |
| Linux (包括 BSD) | `libz_api_hub.so` |
| macOS | `z_api_hub.dylib` |

将动态库放在可执行文件目录或系统搜索路径（Windows 的 `PATH`，Linux 的 `LD_LIBRARY_PATH`，macOS 的 `DYLD_LIBRARY_PATH`）。

**依赖库**（需与主库同目录）：
- Windows：`z_ipc_64.dll` / `z_ipc_32.dll`
- Linux/BSD：`libz_ipc.so`
- macOS：`libz_ipc.dylib`（如有）

### 2.2 包含头文件

从项目获取 `API_HubTool.h` 和 `API_HubTool.c`。将它们放在您的源码目录中。

在您的 C 源文件中包含头文件：

```c
#include "API_HubTool.h"
```

### 2.3 编译与链接

将 `API_HubTool.c` 与您的代码一起编译，并链接必要的系统库：

- **Windows**：无需额外库（默认链接 kernel32）。
- **Linux / macOS**：需要链接 `libdl`（动态加载库）。

示例（Linux）：
```bash
gcc -o myapp myapp.c API_HubTool.c -ldl
```

### 2.4 加载动态库

在所有 API 调用之前，必须调用 `API_LoadLibrary()`。它会在可执行文件目录和系统路径中查找动态库，并解析所有函数指针。

```c
if (!API_LoadLibrary()) {
    fprintf(stderr, "Failed to load API Hub library.\n");
    return 1;
}
```

退出时调用 `API_FreeLibrary()` 释放库句柄。

---

## 3. 核心概念速览

在开始编码前，理解以下三个核心概念：

- **TDataHnd（数据句柄）**：一个二进制缓冲区，内部存储了"API 名称"和"载荷数据"。用于输入参数和输出结果。
- **TAppHnd（应用句柄）**：一个逻辑应用，可以注册多个 API，在网络中具有唯一名称。
- **回调函数（TAPI_Call / TAPI_Notify）**：实现业务逻辑的函数，必须使用 `__cdecl` 调用约定。
- **动态注销（v2.0）**：`API_UnReg` 运行时移除 API，触发网络广播（约 3 秒传播）。
- **运行时配置（v2.0）**：`API_SetOption` 动态调整认证密码、等待连接、IPC 线程池等参数。

**数据流**：
1. 创建 TDataHnd，指定 API 名称，写入参数。
2. 调用 `API_Call`（远程）或 `API_Local_APP_Call`（本地）。
3. 底层将请求路由到目标应用，调用对应的回调函数。
4. 回调函数从输入 TDataHnd 读取参数，处理后写入输出 TDataHnd。
5. 调用方从返回的 TDataHnd 中读取结果。

---

## 4. 数据句柄（TDataHnd）操作

数据句柄是 API Hub 中最基本的操作单元。所有读写操作都围绕它进行。

### 4.1 创建与释放

```c
// 创建一个数据句柄，关联 API 名称 "add"
TDataHnd h = API_Create_DataHnd("add");
if (!h) { /* 错误处理 */ }

// 使用完毕后必须释放
API_Free_DataHnd(h);
```

**注意**：`API_Create_DataHnd` 内部会复制 API 名称，所以您传入的字符串可以立即释放。

### 4.2 写入数据

```c
int a = 5, b = 7;
API_WriteBuffer(h, &a, sizeof(a));  // 从当前位置追加
API_WriteBuffer(h, &b, sizeof(b));
```

`API_WriteBuffer` 始终从当前读写位置开始写入，写入后位置自动后移。初始位置为 0。

### 4.3 读取数据

```c
int sum;
API_SetPos(h, 0);                  // 重置到开头
API_ReadBuffer(h, &sum, sizeof(sum));
```

### 4.4 位置与大小管理

```c
int64_t pos = API_GetPos(h);        // 当前偏移
API_SetPos(h, 0);                   // 跳到开头
int64_t size = API_GetSize(h);      // 总大小
API_SetSize(h, 1024);               // 调整大小（截断或扩展）
```

### 4.5 直接缓冲区访问（零拷贝）

```c
void* raw = API_GetBuffer(h);
int64_t size = API_GetSize(h);
// 直接读写 raw[0..size-1]，但不要越界，也不要 free(raw)
```

`API_GetBuffer` 返回内部指针，可用于高效访问，但只应在句柄的生命周期内使用，且不要释放。

---

## 5. 应用句柄（TAppHnd）与 API 注册

### 5.1 创建应用

```c
TAppHnd app = API_Create_APPHnd("MyService", "My service description");
if (!app) { /* 错误 */ }
```

应用名在网络中必须唯一，区分大小写。

### 5.2 注册 Call API

```c
// 回调函数原型
static void __cdecl MyAdd(void* trigger, void* input, void* output) {
    TDataHnd hIn = (TDataHnd)input;
    TDataHnd hOut = (TDataHnd)output;
    int a, b;
    if (API_ReadBuffer(hIn, &a, sizeof(a)) != sizeof(a)) return;
    if (API_ReadBuffer(hIn, &b, sizeof(b)) != sizeof(b)) return;
    int sum = a + b;
    API_WriteBuffer(hOut, &sum, sizeof(sum));
}

// 注册
int ret = API_Reg_Call(app, "add", "Add two integers", NULL, MyAdd);
if (ret != 1) { /* 名称已存在或错误 */ }
```

参数说明：
- `trigger`：用户自定义指针，回调时会原样传回，可用于传递上下文。
- `input`：只读的 TDataHnd，不要释放。
- `output`：只写的 TDataHnd，用于写入结果。

### 5.3 注册 Notify API

```c
static void __cdecl MyLogger(void* trigger, void* input) {
    TDataHnd hIn = (TDataHnd)input;
    // 读取并记录数据，无输出
}

API_Reg_Notify(app, "log", "Log a message", NULL, MyLogger);
```

### 5.4 释放应用

```c
API_Free_APPHnd(app);
```

释放后所有注册的 API 也会被清理。

---

## 6. 本地调用（无网络）

本地调用用于在同一个进程内测试 API，不经过网络，完全同步。

```c
TDataHnd param = API_Create_DataHnd("add");
int a = 10, b = 20;
API_WriteBuffer(param, &a, sizeof(a));
API_WriteBuffer(param, &b, sizeof(b));

TDataHnd result = API_Local_APP_Call(app, param);
API_Free_DataHnd(param);   // 输入句柄仍需释放

if (result && API_GetSize(result) >= sizeof(int)) {
    int sum;
    API_SetPos(result, 0);
    API_ReadBuffer(result, &sum, sizeof(sum));
    printf("sum = %d\n", sum);
}
API_Free_DataHnd(result);
```

本地调用非常适合单元测试和调试。

---

## 7. 动态注销 API（新增）

`API_UnReg` 允许您在运行时移除已注册的 API。

### 7.1 函数签名

```c
int API_UnReg(TAppHnd appHnd, const char* APIName);
```

### 7.2 使用示例

```c
// 注册 API
API_Reg_Call(app, "add", "Addition", NULL, MyAdd);

// ... 运行一段时间后 ...

// 动态注销 'add' API
if (API_UnReg(app, "add") == 1) {
    printf("API 'add' unregistered, broadcast in progress.\n");
} else {
    printf("API 'add' not found.\n");
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

## 8. 运行时配置（新增）

`API_SetOption` 允许您在运行时动态调整 API Hub 框架的全局配置选项。

### 8.1 函数签名

```c
void API_SetOption(const char* Option, const char* Value);
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

```c
// 设置认证密码（必须在 PrepareDone 之前调用）
API_SetOption("password", "my_secret_token");

// 服务端不等待客户端就绪（适合大规模部署）
API_SetOption("Wait_Connection_ReadyOk", "False");

// 提高 IPC 并发能力
API_SetOption("IPC_Serv_ThreadCount", "8");

// 开启详细日志（调试时使用）
API_SetOption("ConsoleOutput", "True");
API_SetOption("ShowThreadID", "True");
```

---

## 9. 网络层准备与启动

### 9.1 地址匹配规则

- **服务端**：`ListeningAddr_` 是**本地绑定**地址（如 `0.0.0.0` 表示监听所有接口）。`PhysicsAddr_` 是**对外公布**的地址，客户端将使用此地址连接。
- **客户端**：`PhysicsAddr_` 必须与服务端的 `PhysicsAddr_` **完全一致**（包括端口）。对于 IPC，双方必须使用相同的服务名（如 `ipc:my_service`）。

### 9.2 重置准备状态

```c
API_Reset_Prepare();
```

### 9.3 准备服务端（监听器）

```c
// TCP 服务，监听所有接口，公布地址为 127.0.0.1:9898
API_Prepare_Service("0.0.0.0", "127.0.0.1:9898");

// IPC 服务（同机通信，延迟极低）
API_Prepare_Service("ipc:my_service", "ipc:my_service");
```

### 9.4 准备客户端

```c
// 连接到 TCP 服务，并将应用 app 注册到服务端
API_Prepare_Client("127.0.0.1:9898", app);

// IPC 客户端
API_Prepare_Client("ipc:my_service", app);
```

如果不需要暴露 API（纯消费端），第二个参数传 `NULL`。

### 9.5 启动框架

```c
if (API_Prepare_Done() != 1) {
    // 失败，检查控制台输出
    fprintf(stderr, "Prepare failed. Check console output for details.\n");
    // 清理并退出
}
```

`API_Prepare_Done` 会阻塞直到所有服务/客户端初始化完成。

> **调试说明**：库会将详细的运行日志（包括连接状态、注册信息、错误原因）自动输出到控制台。你可以在 `<可执行文件名>.api-tool.ini` 配置文件中调整日志行为。

### 9.6 停止事件循环

```c
API_Exit_MainThread();
```

---

## 10. 远程调用与通知

### 10.1 `API_Call` 同步调用

```c
TDataHnd param = API_Create_DataHnd("add");
// ... 写入参数 ...

// 调用应用 "MyService" 的 "add" API，超时 5000ms
TDataHnd result = API_Call("MyService", param, 5000);
API_Free_DataHnd(param);   // 输入句柄仍需释放

if (result && API_GetSize(result) > 0) {
    // 处理结果
    API_Free_DataHnd(result);
} else {
    // 超时或失败（result 可能为 NULL 或 size=0）
    if (result) API_Free_DataHnd(result);
}
```

**重要**：`API_Call` 返回的句柄永远非 `NULL`（除非内部错误），但可能大小为 0。您**必须**检查大小并总是释放返回的句柄。

### 10.2 `API_Notify` 单向通知

```c
TDataHnd param = API_Create_DataHnd("log");
const char* msg = "Hello";
API_WriteBuffer(param, msg, strlen(msg) + 1);
API_Notify("MyService", param);
API_Free_DataHnd(param);   // 调用后仍需释放
```

`API_Notify` 立即返回，不等待响应。

---

## 11. 线程安全与回调上下文（重要）

### 11.1 导出函数线程安全

**所有导出函数都是完全线程安全的**。您可以在多个线程中同时调用 `API_Call`、`API_WriteBuffer` 等，无需外部锁。

但**同一 TDataHnd 的写操作（`API_WriteBuffer`、`API_SetPos`、`API_SetSize`）应串行化**，避免数据竞争。

### 11.2 回调执行上下文

**您的回调函数（`TAPI_Call`、`TAPI_Notify`）是在后台线程池线程中执行的**，而不是在调用 `API_Call` 的线程。

这带来以下约束：
- ❌ **禁止**在回调中调用 `API_Call` 或 `API_Notify` —— 可能导致死锁，因为回调线程可能持有内部锁。
- ❌ **禁止**长时间阻塞（如 `sleep`、等待事件、大量循环）。
- ❌ **禁止**直接访问 UI 组件或线程局部存储。
- ✅ **推荐**将耗时任务或远程调用请求放入队列，由独立工作线程处理，回调快速返回。

示例（正确做法）：
```c
// 在回调中不要直接调用 API_Call
static void __cdecl GoodCallback(void* trigger, void* input, void* output) {
    // 将任务提交给工作线程
    PostTaskToWorker(input);
    // 快速返回，工作线程会处理后续
}
```

### 11.3 执行顺序不保证

由于负载均衡，并发请求可能被路由到不同实例，**调用顺序不保证**。如果您发送 `1,2,3`，远程可能以 `2,1,3` 处理。需要顺序的业务请自行实现序列号或单线程调度。

---

## 12. 高级主题

### 12.1 并发调用

由于 API 函数是线程安全的，可以轻松实现高并发：

```c
#include <pthread.h>

void* call_add(void* arg) {
    TDataHnd param = API_Create_DataHnd("add");
    int a = rand() % 100, b = rand() % 100;
    API_WriteBuffer(param, &a, sizeof(a));
    API_WriteBuffer(param, &b, sizeof(b));
    TDataHnd res = API_Call("MyService", param, 5000);
    API_Free_DataHnd(param);
    if (res && API_GetSize(res) >= sizeof(int)) {
        int sum;
        API_SetPos(res, 0);
        API_ReadBuffer(res, &sum, sizeof(sum));
        // ... 处理结果
        API_Free_DataHnd(res);
    }
    return NULL;
}

// 创建 100 个线程同时调用
pthread_t threads[100];
for (int i = 0; i < 100; ++i)
    pthread_create(&threads[i], NULL, call_add, NULL);
for (int i = 0; i < 100; ++i)
    pthread_join(threads[i], NULL);
```

### 12.2 IPC vs TCP

- **IPC**（`ipc:服务名`）：同机通信，使用操作系统命名管道或共享内存，延迟 < 1 ms，吞吐极高。适合单机微服务。
- **TCP**：跨机通信，支持 IPv4/IPv6，可配置端口。延迟取决于网络。

您可以在同一程序中同时暴露 IPC 和 TCP 服务，客户端按需连接。

### 12.3 多实例部署

要实现负载均衡，只需在不同进程或机器上启动多个服务端实例，注册**相同的应用名**。客户端会自动发现所有实例，并将请求发送给负载最低的那一个。

每个实例应使用不同的监听地址（不同端口或 IPC 名称），但公布地址（`PhysicsAddr_`）可以相同。

### 12.4 零拷贝优化

使用 `API_GetBuffer` 直接访问内部缓冲区，避免复制。例如在回调中处理大块数据：

```c
static void __cdecl BigDataCallback(void* trigger, void* input, void* output) {
    TDataHnd hIn = (TDataHnd)input;
    void* data = API_GetBuffer(hIn);
    int64_t size = API_GetSize(hIn);
    // 直接处理 data，无需复制
    // 但不要修改或释放它
}
```

---

## 13. 调试与错误处理

### 13.1 控制台日志

库会在控制台自动输出详细的运行日志（包括连接状态、注册信息、错误原因）。你可以在 `<可执行文件名>.api-tool.ini` 配置文件中调整日志行为。

### 13.2 常见错误

| 错误信息 | 原因 | 解决方案 |
|---------|------|---------|
| `no found app("XXX") api("YYY")` | 目标应用未注册或未暴露该 API | 检查应用名和 API 名大小写，确认客户端已成功注册 |
| `bind address already in use` | 端口被占用 | 更换端口或结束占用进程 |
| `timeout` | 响应超时 | 增加超时值，检查网络连通性 |

### 13.3 安全退出

标准退出流程：

```c
API_Exit_MainThread();   // 停止内部事件循环
API_Free_APPHnd(app);    // 释放应用句柄（在退出前释放）
API_shutdown();          // 关闭所有网络资源
API_FreeLibrary();       // 卸载动态库
```

顺序很重要：先停止主线程，再释放资源，避免悬空指针。

---

## 14. 完整示例：服务端 + 客户端

### 14.1 服务端（service.c）

```c
#include "API_HubTool.h"
#include <stdio.h>
#include <string.h>

static void __cdecl AddCallback(void* trigger, void* input, void* output) {
    int a, b;
    TDataHnd hIn = (TDataHnd)input, hOut = (TDataHnd)output;
    if (API_ReadBuffer(hIn, &a, sizeof(a)) != sizeof(a)) return;
    if (API_ReadBuffer(hIn, &b, sizeof(b)) != sizeof(b)) return;
    int sum = a + b;
    API_WriteBuffer(hOut, &sum, sizeof(sum));
}

static void __cdecl EchoCallback(void* trigger, void* input, void* output) {
    TDataHnd hIn = (TDataHnd)input, hOut = (TDataHnd)output;
    int64_t size = API_GetSize(hIn);
    if (size > 0) {
        char* buf = malloc((size_t)size);
        if (!buf) return;
        API_SetPos(hIn, 0);
        API_ReadBuffer(hIn, buf, size);
        API_WriteBuffer(hOut, buf, size);
        free(buf);
    }
}

int main() {
    if (!API_LoadLibrary()) return 1;
    TAppHnd app = API_Create_APPHnd("ServiceApp", "Demo Service");
    API_Reg_Call(app, "add", "Add", NULL, AddCallback);
    API_Reg_Call(app, "echo", "Echo", NULL, EchoCallback);

    API_Reset_Prepare();
    API_Prepare_Service("0.0.0.0", "127.0.0.1:9898");
    API_Prepare_Service("ipc:demo", "ipc:demo");
    API_Prepare_Client("127.0.0.1:9898", app);
    API_Prepare_Client("ipc:demo", app);

    if (API_Prepare_Done() != 1) {
        fprintf(stderr, "Prepare failed. Check console output for details.\n");
        API_Free_APPHnd(app);
        API_shutdown();
        API_FreeLibrary();
        return 1;
    }
    printf("Service running. Press Enter to exit.\n");
    getchar();

    API_Exit_MainThread();
    API_Free_APPHnd(app);
    API_shutdown();
    API_FreeLibrary();
    return 0;
}
```

### 14.2 客户端（client.c）

```c
#include "API_HubTool.h"
#include <stdio.h>

int main() {
    if (!API_LoadLibrary()) return 1;
    // 纯消费端，不注册 API
    API_Reset_Prepare();
    API_Prepare_Client("ipc:demo", NULL);
    API_Prepare_Client("127.0.0.1:9898", NULL);

    if (API_Prepare_Done() != 1) {
        fprintf(stderr, "Connect failed. Check console output for details.\n");
        API_shutdown();
        API_FreeLibrary();
        return 1;
    }

    // 调用 add
    TDataHnd param = API_Create_DataHnd("add");
    int a = 10, b = 20;
    API_WriteBuffer(param, &a, sizeof(a));
    API_WriteBuffer(param, &b, sizeof(b));
    TDataHnd result = API_Call("ServiceApp", param, 5000);
    API_Free_DataHnd(param);
    if (result && API_GetSize(result) >= sizeof(int)) {
        int sum;
        API_SetPos(result, 0);
        API_ReadBuffer(result, &sum, sizeof(sum));
        printf("10 + 20 = %d\n", sum);
    }
    if (result) API_Free_DataHnd(result);

    // 调用 echo
    param = API_Create_DataHnd("echo");
    const char* msg = "Hello from C client!";
    API_WriteBuffer(param, msg, strlen(msg) + 1);
    result = API_Call("ServiceApp", param, 5000);
    API_Free_DataHnd(param);
    if (result && API_GetSize(result) > 0) {
        char buf[256] = {0};
        API_SetPos(result, 0);
        int64_t sz = API_GetSize(result);
        if (sz < sizeof(buf)) {
            API_ReadBuffer(result, buf, sz);
            printf("Echo reply: %s\n", buf);
        }
    }
    if (result) API_Free_DataHnd(result);

    API_Exit_MainThread();
    API_shutdown();
    API_FreeLibrary();
    return 0;
}
```

---

## 15. FAQ

**Q1: 为什么我的回调没有被调用？**
A: 检查应用名和 API 名是否完全匹配（大小写）。确认客户端已成功连接并注册（查看状态日志）。`API_Prepare_Done` 是否成功？

**Q2: 可以在回调中调用 `API_Call` 吗？**
A: **不可以**。这会导致死锁。请将远程调用请求放入队列，由独立线程处理。

**Q3: 多个线程同时调用 `API_Call` 安全吗？**
A: 是的，所有导出函数都是线程安全的。但同一 TDataHnd 的写操作需串行化。

**Q4: 如何处理超时？**
A: `API_Call` 超时后返回的句柄大小为 0。您可以增加超时值或检查网络状态。超时值为 0 表示无限等待，慎用。

**Q5: 我可以在同一进程运行多个应用吗？**
A: 可以。创建多个 TAppHnd，注册不同的 API 集，分别准备客户端即可。

**Q6: 多个服务实例如何负载均衡？**
A: 启动多个进程，每个注册相同的应用名，客户端会自动感知并轮询负载最低的实例。

**Q7: 动态注销 API 后，正在进行的调用会怎样？**
A: 正在执行中的回调不会被打断，它们会正常完成。新到达的请求会在广播传播后收到"未找到"错误。

---

## 16. 总结与资源

您已掌握了 API Hub Tool 的 C 语言全部核心用法。现在您可以：

- 用 C 编写高性能服务，暴露给任何语言消费。
- 用 C 编写客户端，调用其他语言的服务。
- 利用 IPC 实现微秒级同机通信，或通过 TCP 构建跨云分布式系统。

**进一步学习资源：**
- [API_HubTool.h](API_HubTool.h) —— 完整 C API 参考（内含详尽注释）
- [API_HubTool.hpp](API_HubTool.hpp) —— 如果您偏爱 C++，可以使用 RAII 包装
- [Pascal 完整指南](../pascal/API%20Hub%20Tool%20for%20Pascal.md) —— 概念相通，可作为补充
- 示例代码：`HelloWorld.c`（本地调用）、`Service.c` / `Client1.c`（网络调用）

**社区支持：**
- 作者：（QQ：600585）

---

**从今天起，您的 C 代码不再孤单。**
API Hub Tool 让语言边界消失，让分布式开发回归简单。

## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](API%20Hub%20Tool%20C++%20使用指南.md)
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
