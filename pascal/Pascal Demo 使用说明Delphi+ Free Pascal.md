# Pascal Demo 使用说明（Delphi / Free Pascal）

**版本：** 2.0（与 ZAPI 核心 v2.0 同步）

本目录提供了一套完整的 **Pascal 绑定** 和 **示例程序**，让您的 Delphi 或 Free Pascal 应用能够轻松接入 **zAPI** 分布式服务网格，实现跨语言、跨进程、跨机器的函数调用。

> **v2.0 新特性：** 支持 `API_UnReg` 动态注销 API 和 `API_SetOption` 运行时配置；PHP 和 Node.js 可通过 ZAPI Bridge 调用 Pascal 服务。

---

## 📂 文件结构

```text
pascal/
├── z_api_hubtool_import.pas          // 核心绑定单元（自动加载动态库）
├── z_api_hubtool_helper.pas          // RAII 封装（TDataHandle、TAppHandle 等）
├── zAPIBench_API_Check.lpr           // 单 API 功能验证工具
├── zAPIBenchServer.lpr               // 20 个 API 的压测服务端
├── zAPIBenchClient.lpr               // 并发压测客户端（每调用一线程）
├── fpc_tester_for_zAPI.lpr           // 完整功能测试套件
└── ZCoreSrc/                         // Z 系列基础库（用于压测服务端/客户端）
    └── ...（依赖单元）
```

---

## 🚀 快速上手（5 分钟）

### 1️⃣ 获取动态库

从 [Releases](https://github.com/PassByYou888/zAPI/releases) 下载对应平台的动态库，并放置到可执行文件目录或系统 `PATH` 中：

| 平台           | 核心库               | IPC 依赖库       |
| -------------- | -------------------- | ---------------- |
| Windows 64-bit | `z_api_hub64.dll`    | `z_ipc_64.dll`   |
| Windows 32-bit | `z_api_hub32.dll`    | `z_ipc_32.dll`   |
| Linux / BSD    | `z_api_hub.so`       | `libz_ipc.so`    |
| macOS          | `z_api_hub.dylib`    | `libz_ipc.dylib` |

**注意**：动态库会自动加载，无需手动 `LoadLibrary`。

---

### 2️⃣ 编译最简单的服务端（CalcServer）

新建一个控制台程序，引用 `z_api_hubtool_import.pas`，编写如下代码：

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
  API_ReadBuffer(Input, @a, SizeOf(a));
  API_ReadBuffer(Input, @b, SizeOf(b));
  sum := a + b;
  API_WriteBuffer(Output, @sum, SizeOf(sum));
end;

var
  app: TAppHnd;
begin
  app := API_Create_APPHnd('CalcService', 'Calculator');
  API_Reg_Call(app, 'add', 'a+b', nil, @AddCallback);

  // v2.0 新增：运行时配置（可选）
  API_SetOption('Wait_Connection_ReadyOk', 'False');

  API_Reset_Prepare;
  API_Prepare_Service('ipc:calc_service', 'ipc:calc_service');
  API_Prepare_Client('ipc:calc_service', app);

  if API_Prepare_Done = 1 then
  begin
    Writeln('服务已启动，按 Enter 退出...');
    Readln;
  end;

  // v2.0 新增：动态注销 API（可选）
  API_UnReg(app, 'add');

  API_Exit_MainThread;
  API_Free_APPHnd(app);
  API_shutdown;
end.
```

**编译**（Free Pascal）：

```bash
fpc CalcServer.lpr
```

**编译**（Delphi）：
直接将 `z_api_hubtool_import.pas` 添加到项目，编译即可（无需任何额外设置）。

---

### 3️⃣ 编写客户端并调用

```pascal
program CalcClient;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  z_api_hubtool_import;

var
  param, result: TDataHnd;
  a, b, sum: Integer;
begin
  API_Reset_Prepare;
  API_Prepare_Client('ipc:calc_service', nil);

  if API_Prepare_Done <> 1 then
  begin
    Writeln('连接失败');
    Halt(1);
  end;

  param := API_Create_DataHnd('add');
  a := 10; b := 20;
  API_WriteBuffer(param, @a, SizeOf(a));
  API_WriteBuffer(param, @b, SizeOf(b));

  result := API_Call('CalcService', param, 3000);
  API_Free_DataHnd(param);

  if API_GetSize(result) >= SizeOf(Integer) then
  begin
    API_SetPos(result, 0);
    API_ReadBuffer(result, @sum, SizeOf(sum));
    Writeln('10 + 20 = ', sum);
  end;

  API_Free_DataHnd(result);
  API_Exit_MainThread;
  API_shutdown;
end.
```

运行后输出：

```text
10 + 20 = 30
```

---

## 📦 核心文件说明

### `z_api_hubtool_import.pas`（必需）

- 所有 C 函数的 Pascal 声明（`external` 自动加载）。
- 定义了 `TDataHnd`、`TAppHnd`、`TAPI_Call`、`TAPI_Notify` 等类型。
- 包含完整的 API 参考文档（注释）。
- **完全兼容 Delphi 和 Free Pascal**，可直接复制到任何项目中使用。
- **v2.0 新增**：`API_UnReg` 和 `API_SetOption` 函数声明。

### `z_api_hubtool_helper.pas`（可选）

- 提供 `TDataHandle` 和 `TAppHandle` 的 RAII 封装（自动释放）。
- 简化读写操作，支持方法链式调用（如 `WriteInt32(5).WriteInt32(7)`）。
- 提供全局便捷函数（`CallApp`、`NotifyApp`、`ResetPrepare` 等）。
- **同样完全兼容 Delphi/FPC**，建议在新项目中使用。
- **v2.0 新增**：`TAppHandle.Unregister` 方法和全局 `SetOption` 函数。

---

## 🔧 编译与运行

### 使用 Free Pascal（Lazarus）

- 将 `z_api_hubtool_import.pas`（和 `z_api_hubtool_helper.pas`）添加到项目。
- 确保动态库在可执行目录或 `PATH` 中。
- 直接编译，无需额外链接选项。

### 使用 Delphi（任何版本，包括旧版）

- 将上述两个单元添加到项目（`Project → Add to Project`）。
- 无需修改任何代码，直接编译。
- **注意**：如果使用较旧版本的 Delphi（如 2007），`cdecl` 调用约定已支持，无需调整。

### 依赖项

- 仅依赖标准 RTL（System、SysUtils 等）。
- 压测服务端/客户端（`zAPIBenchServer`/`zAPIBenchClient`）还依赖 `ZCoreSrc` 目录中的 Z 系列库（如 Z.Json、Z.Expression 等），但**核心绑定本身不依赖任何 Z 库**。

---

## 📊 提供的示例程序

### 1. `zAPIBench_API_Check.lpr` – 功能验证工具

- 顺序测试 BenchServer 的 20 个 API。
- 打印每个 API 的请求/响应 JSON，自动判断结果正确性。
- **用途**：快速排查 API 是否正常工作，验证接口变更兼容性。

### 2. `zAPIBenchServer.lpr` – 压测服务端（20 个 API）

- 包含算术、哈希、加密（模拟 Base64）、字符串操作、时间戳、随机数等 20 个 API。
- 同时监听 IPC（`ipc:bench_service`）和 TCP（`127.0.0.1:9898`）。
- **用途**：作为压力测试的目标服务器，也作为跨语言服务演示。

### 3. `zAPIBenchClient.lpr` – 并发压测客户端

- 每个 API 调用在独立线程中执行（每调用一线程）。
- 统计平均、最小、最大、中位数、标准差、成功率、QPS。
- **用途**：评估服务端在高并发下的性能和稳定性。

### 4. `fpc_tester_for_zAPI.lpr` – 完整功能测试套件

- 覆盖 TDataHandle 所有读写方法、TAppHandle 注册/调用、并发、性能、资源泄漏、UTF-8 国际化等。
- **用途**：验证绑定单元的正确性，适合开发者运行自检。

---

## 🧠 核心 API 速查

| 函数 / 类                         | 说明                            | v2.0 新增 |
| --------------------------------- | ------------------------------- | --------- |
| `API_Create_DataHnd(apiName)`     | 创建数据句柄（参数/结果容器）   | |
| `API_WriteBuffer`                 | 写入二进制数据                  | |
| `API_ReadBuffer`                  | 读取二进制数据                  | |
| `API_GetSize` / `API_SetSize`     | 获取/设置缓冲区大小             | |
| `API_GetPos` / `API_SetPos`       | 获取/设置读写位置               | |
| `API_Create_APPHnd(appName)`      | 创建应用句柄（暴露 API 的容器） | |
| `API_Reg_Call` / `API_Reg_Notify` | 注册请求-响应 / 单向通知 API    | |
| `API_UnReg`                       | **动态注销 API（v2.0）**        | ✅ |
| `API_SetOption`                   | **运行时配置（v2.0）**          | ✅ |
| `API_Local_APP_Call`              | 本地调用（不经过网络）          | |
| `API_Call`                        | 远程同步调用                    | |
| `API_Notify`                      | 远程单向通知                    | |
| `API_Reset_Prepare`               | 清除网络配置                    | |
| `API_Prepare_Service`             | 准备服务端监听                  | |
| `API_Prepare_Client`              | 准备客户端连接（可暴露应用）    | |
| `API_Prepare_Done`                | 启动网络框架（阻塞直到就绪）    | |
| `API_Exit_MainThread`             | 停止内部事件循环                | |
| `API_shutdown`                    | 关闭框架，释放资源              | |

---

## ⚠️ 重要注意事项

### 🔴 回调执行上下文

- 所有回调（`TAPI_Call` / `TAPI_Notify`）在 **后台线程池** 中执行。
- **禁止**在回调中调用 `API_Call` 或 `API_Notify`（会导致死锁）。
- **禁止**长时间阻塞（如 `Sleep`、等待事件）。
- **推荐**：回调只做快速数据读写，耗时任务请异步提交到自己的工作线程。

### 🟢 UTF-8 编码

- 所有字符串参数（API 名称、描述、地址）必须为 **UTF-8** 编码，并以 `#0` 结尾。
- 使用 `PAnsiChar(Utf8String(...))` 进行转换。
- 在 Delphi 中，`string` 类型默认是 Unicode（UTF-16），但 `PAnsiChar` 期望的是 UTF-8 字节，**不要直接强制转换**。

**正确做法**：

```pascal
API_Reg_Call(app, PAnsiChar(Utf8String('中文API')), ...);
```

### 🟡 线程安全

- 所有导出函数均线程安全。
- 同一 `TDataHnd` 的写操作需串行化；不同句柄可并发操作。

### 🟣 多实例部署

- 在多个进程中启动相同应用名的服务，客户端会自动负载均衡。
- 每个实例监听不同地址（如不同 IPC 名称或不同 TCP 端口）。

### 🔵 v2.0 新特性注意事项

- **动态注销**：`API_UnReg` 立即从本地移除 API，网络广播约 3 秒传播。
- **运行时配置**：`API_SetOption` 支持动态调整认证密码、等待连接、IPC 线程池等。
- **PHP/Node.js 支持**：通过 ZAPI Bridge 调用 Pascal 服务，详见 [Bridge 完整手册](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)。

---

## 🧩 迁移到 Delphi（无痛）

**所有 Pascal 绑定代码（`z_api_hubtool_import.pas` 和 `z_api_hubtool_helper.pas`）都是纯 Delphi/FPC 兼容代码，无需任何修改即可在 Delphi 中编译。**

1. 将 `.pas` 文件复制到您的 Delphi 项目目录。
2. 在项目中添加单元引用（`uses z_api_hubtool_import;`）。
3. 编译运行——动态库自动加载。

**Delphi 版本要求**：Delphi 2007 及以上（支持 `cdecl` 和泛型语法）。

---

## 🛠 更多资源

- [API Hub Tool for Pascal 完整指南](./API%20Hub%20Tool%20for%20Pascal.md)
- [zAPI 概览](./zAPI：让所有编程语言平等对话的分布式服务网格.md)
- [其他语言绑定（C++、Python、Go 等）](../)
- [📖 ZAPI Bridge 完整使用手册](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)

---

## 🤝 社区与支持

- GitHub：[https://github.com/PassByYou888/zAPI](https://github.com/PassByYou888/zAPI)
- 作者 QQ：`600585`
- 欢迎 Star、Fork、Issue 和 PR！

---

**现在，您可以在 Delphi 或 Free Pascal 中直接使用 zAPI，让您的 Pascal 代码融入多语言分布式生态！** 🚀

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
- [📖 ZAPI Bridge 完整使用手册](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)
