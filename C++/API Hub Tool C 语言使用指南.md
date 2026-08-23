# API Hub Tool C 语言使用指南

**从零开始，用 C 语言打造跨语言分布式系统**

**版本：** 2.1（与 ZAPI 核心 v2.1 同步）

---

## 目录

1. [概述](#1-概述)
2. [环境准备与库加载](#2-环境准备与库加载)
3. [核心概念速览](#3-核心概念速览)
4. [数据句柄（TDataHnd）操作](#4-数据句柄tdatahnd操作)
5. [应用句柄（TAppHnd）与 API 注册](#5-应用句柄tapphnd与-api-注册)
6. [本地调用（无网络）](#6-本地调用无网络)
7. [动态注销 API](#7-动态注销-api)
8. [运行时配置](#8-运行时配置)
9. [网络层准备与启动](#9-网络层准备与启动)
10. [远程调用与通知](#10-远程调用与通知)
11. [线程安全与回调上下文（重要）](#11-线程安全与回调上下文重要)
12. [状态与检查 API（新增）](#12-状态与检查-api新增)
13. [调试与错误处理](#13-调试与错误处理)
14. [高级主题](#14-高级主题)
15. [完整示例：服务端 + 客户端](#15-完整示例服务端--客户端)
16. [FAQ](#16-faq)
17. [总结与资源](#17-总结与资源)

---

## 1. 概述

API Hub Tool 是一个**基于纯 C ABI 的分布式 RPC 框架**，允许您用 C 语言编写服务端和客户端，并让这些服务被任何支持 C 动态库调用的语言（Python、C#、Java、Go、Rust、Pascal、PHP、Node.js 等）无缝调用。反之，您也可以用 C 语言调用其他语言编写的服务。

**核心设计哲学：**
- **极简接口**：只有 **30 个函数**，覆盖创建、读写、注册、调用、状态查询、关闭全流程。
- **显式生命周期**：所有句柄（TDataHnd、TAppHnd）都由您显式创建和释放，无隐藏开销。
- **跨语言通用**：纯 C ABI，任何支持 FFI 的语言都能直接使用。
- **内置服务网格**：自动服务发现、负载均衡、断线重连、NAT 穿透，开箱即用。
- **v2.1 新增**：新增 `API_Check_MainThread`、`API_Check_App`、`API_Get_Status_Num`、`API_Get_Status`、`API_Post_Status` 五个状态与检查 API，方便调试和监控。

本指南将手把手带您从零开始掌握 API Hub 的 C 语言接口，并理解其背后的关键设计。

---

## 3. 核心概念速览

在开始编码前，理解以下核心概念：

- **TDataHnd（数据句柄）**：二进制缓冲区，存储"API 名称"和"载荷数据"。用于输入参数和输出结果。
- **TAppHnd（应用句柄）**：逻辑应用，可以注册多个 API，在网络中具有唯一名称。
- **回调函数（TAPI_Call / TAPI_Notify）**：实现业务逻辑的函数，必须使用 `__cdecl` 调用约定。
- **动态注销**：`API_UnReg` 运行时移除 API，触发网络广播（约 3 秒传播）。
- **运行时配置**：`API_SetOption` 动态调整认证密码、等待连接、IPC 线程池等参数。
- **状态与检查（v2.1 新增）**：`API_Check_MainThread` 检查主循环是否运行，`API_Check_App` 探测应用是否在线，`API_Get_Status_Num`/`API_Get_Status`/`API_Post_Status` 提供日志队列访问。

**数据流**：
1. 创建 TDataHnd，指定 API 名称，写入参数。
2. 调用 `API_Call`（远程）或 `API_Local_APP_Call`（本地）。
3. 底层将请求路由到目标应用，调用对应的回调函数。
4. 回调函数从输入 TDataHnd 读取参数，处理后写入输出 TDataHnd。
5. 调用方从返回的 TDataHnd 中读取结果。

---

## 12. 状态与检查 API（新增）

本版本新增了五个函数，用于查询框架运行状态和获取日志信息，极大方便了调试和运维。

### 12.1 `API_Check_MainThread`

```c
int API_Check_MainThread(void);
```

检查模拟主线程（C4 事件循环）是否正在运行。

- **返回值**：`1` 表示正在运行，`0` 表示已停止或尚未启动。
- **用途**：在调用远程 API 前确认框架已就绪，或在退出前确认主循环状态。
- **示例**：
  ```c
  if (API_Check_MainThread()) {
      printf("主线程正在运行\n");
  } else {
      printf("主线程已停止\n");
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
  ```c
  if (API_Check_App("MyService")) {
      // 安全调用
      TDataHnd result = API_Call("MyService", param, 5000);
  } else {
      printf("MyService 当前不可用\n");
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
  ```c
  while (API_Get_Status_Num() > 0) {
      const char* msg = API_Get_Status();
      printf("[库日志] %s\n", msg);
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
  ```c
  API_Post_Status("应用初始化完成");
  ```

---

## 13. 调试与错误处理

### 13.1 利用日志 API 获取详细运行信息

库会在运行过程中自动输出大量诊断信息（连接状态、注册结果、错误原因等）。您可以通过 `API_Get_Status_Num` / `API_Get_Status` 在自己的主循环中拉取这些日志，实时监控框架状态。

**典型用法**（在主循环中定期调用）：
```c
void PollLogs() {
    while (API_Get_Status_Num() > 0) {
        const char* msg = API_Get_Status();
        // 将 msg 写入文件、网络或控制台
        fputs(msg, stdout);
        fputc('\n', stdout);
    }
}
```

也可通过 `API_Post_Status` 注入自定义日志，统一管理所有输出。

### 13.2 常见错误

| 错误信息 | 原因 | 解决方案 |
|---------|------|---------|
| `no found app("XXX") api("YYY")` | 目标应用未注册或 API 名不匹配 | 检查大小写，确认客户端已注册成功；使用 `API_Check_App` 提前探测 |
| `bind address already in use` | 端口被占用 | 更换端口或结束占用进程 |
| `timeout` | 响应超时 | 增加超时值，检查网络连通性；查看日志排查目标是否在线 |
| `Prepare_Done failed` | 网络初始化失败 | 查看 `API_Get_Status` 输出的具体错误信息 |

### 13.3 安全退出

标准退出流程：
```c
API_Exit_MainThread();   // 停止内部事件循环
API_Free_APPHnd(app);    // 释放应用句柄
API_shutdown();          // 关闭所有网络资源
API_FreeLibrary();       // 卸载动态库
```
顺序很重要：先停止主线程，再释放资源，避免悬空指针。

---

## 15. 完整示例：服务端 + 客户端

（原有示例代码保持不变，此处省略重复内容，仅补充日志轮询片段）

### 15.1 服务端（带日志轮询）

```c
// ... 注册 API，准备网络，启动框架 ...

// 在主循环中加入日志轮询
while (!g_bExit) {
    // 处理命令...
    PollLogs();           // 拉取并输出日志
    Sleep(100);
}
```

---

## 16. FAQ

（新增 Q8）

**Q8: 如何查看库内部的详细运行日志？**  
A: 使用 `API_Get_Status_Num` 和 `API_Get_Status` 在您的循环中拉取日志。库会输出连接状态、注册结果、错误原因等详细信息，极大方便调试。您也可以使用 `API_Post_Status` 注入自定义日志。

---

## 17. 总结与资源

您已掌握了 API Hub Tool 的 C 语言全部核心用法，包括新增的状态与检查 API。现在您可以：

- 用 C 编写高性能服务，暴露给任何语言消费。
- 用 C 编写客户端，调用其他语言的服务。
- 利用 IPC 实现微秒级同机通信，或通过 TCP 构建跨云分布式系统。
- 通过新日志 API 实现精细化的运行时监控。

**进一步学习资源：**
- [API_HubTool.h](API_HubTool.h) —— 完整 C API 参考（内含详尽注释）
- [API_HubTool.hpp](API_HubTool.hpp) —— C++ RAII 包装
- [Pascal 完整指南](../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- 示例代码：`HelloWorld.c`、`Service.c`、`Client1.c`、`func_service.c` 等

**社区支持：** 作者（QQ：600585）

---

**从今天起，您的 C 代码不再孤单。**  
API Hub Tool 让语言边界消失，让分布式开发回归简单。
