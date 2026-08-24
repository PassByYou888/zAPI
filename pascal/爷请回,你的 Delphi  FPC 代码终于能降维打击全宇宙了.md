# 🐫 爷青回！你的 Delphi / FPC 代码终于能“降维打击”全宇宙了

> **“二十年的老代码，一夜之间成了微服务架构的C位担当。”** —— 某位 Delphi 老司机在跑通 zAPI 后的朋友圈
>
> **版本：** 2.1（与 ZAPI 核心 v2.1 同步）

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Delphi](https://img.shields.io/badge/Delphi-10+-red.svg)](https://www.embarcadero.com/products/delphi)
[![FPC](https://img.shields.io/badge/FPC-3.2+-blue.svg)](https://www.freepascal.org/)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS%20%7C%20BSD-lightgrey.svg)]()


## 🧓 当你发现 Pascal 还没凉，而且还能暴打 Python 的时候……

你正在维护一套写了二十年的 Delphi 系统，代码稳如老狗，客户用了都说好。

直到有一天，老板盯着你，语重心长地说：*“我们要搞 AI，要上微服务，要让 Go 和 Rust 来调用咱们的核心业务……”*

你低头看了看手里的 Pascal，又抬头看了看旁边工位小年轻写的 Node.js，默默打开了招聘网站——**不是你想跑，是这路不对。**

但，**别急着投简历**。

zAPI 来了。它让你的 Delphi / FPC 代码一夜之间变成“分布式服务网格里的老大哥”——**不仅能被 Python、Go、Rust、Java、C#、Node.js、PHP 随便调，你还能反过来调它们。**

**这不是做梦，这是今晚就能跑通的代码。**


## 🎯 zAPI 是什么？一句话让你秒懂

**zAPI 是一个让 Pascal（Delphi / Free Pascal）和十几种其他语言（C++、Python、Go、Rust、Java、C#、VB.Net、C、Node.js、PHP、甚至浏览器里的 JavaScript）能“无缝互捅”的 RPC 框架。**

不需要写 COM 组件，不需要折腾 SOAP，不需要搭 HTTP 服务，不需要操心序列化协议——**你只需要在项目里引用一个 Pascal 单元（`z_api_hubtool_import.pas`），然后你的老代码就能跟整个技术栈“称兄道弟”。**

```text
┌─────────────┐                    ┌──────────────────┐      C ABI      ┌─────────────┐
│   Pascal    │ ──── 直接调用 ──── │  z_api_hub       │ ─────────────── │  zAPI Core  │
│  (Delphi/   │ ◄─── 返回结果 ──── │  动态库          │ ◄────────────── │  (DLL/SO)   │
│   FPC)      │                    │  (自动加载)      │                 │  v2.1 新增: │
└─────────────┘                    └──────────────────┘                 │  状态与检查 │
                                                                        │  API 全家桶 │
                                                                              │
                                                                              ▼
                                                                 ┌─────────────────────┐
                                                                 │ C++ / Python / Go   │
                                                                 │ Rust / Java / C#    │
                                                                 │ VB.Net / C / Node   │
                                                                 │ PHP / Web.js/…全明星│
                                                                 └─────────────────────┘
```

**简单说：你的 Pascal 代码调用 `API_Call`，zAPI 核心库转手就找到目标语言的服务，把结果快递回来——整个过程比你点外卖还快，你甚至感觉不到中间隔了十几层。v2.1 还让你能随时掏出 `API_Check_App` 看看对方在不在线，掏出 `API_Get_Status` 瞅一眼内部日志，**调试起来比翻监控还方便**。**


## ✨ 核心亮点（不多 BB，直接上硬货）

| 特性 | 有多牛？ | v2.1 升级 |
|------|---------|----------|
| 🌍 **12+ 语言绑定** | Pascal（Delphi/FPC）、Node.js、PHP、Web.js、Python、C++、Go、Rust、Java、C#、VB.Net、C……全家桶都给你配齐了，随便挑 | ✅ PHP、Node.js 已原生支持（v2.0） |
| ⚡ **IPC 延迟 < 1ms** | 同机通信快到你怀疑人生，3000+ 请求/秒，**比 Delphi 的 Code Insight 反应还快** | — |
| 🔌 **TCP + IPC 双模** | 跨机器用 TCP，同机用 IPC，一个地址字符串搞定，**不用改代码** | — |
| 🔄 **自动服务发现** | 基于 C4 网格，自动注册、负载均衡、断线重连——**注册中心和配置中心都省了** | — |
| 🧵 **全线程安全** | 1000 个线程同时调用无压力，**放心开 TThread，不会翻车** | — |
| 🚀 **零配置加载** | `external` 自动加载动态库，**不用手动 LoadLibrary** | — |
| 🎯 **Call + Notify 双模式** | 要结果还是要速度？自己选 | — |
| 🔧 **动态注销 API** | 运行时移除 API，触发网络广播（约 3 秒传播），适合热卸载插件 | ✅ v2.0 已支持 |
| ⚙️ **运行时配置** | 动态调整认证密码、等待连接、IPC 线程池等参数，无需重启 | ✅ v2.0 已支持 |
| 📊 **状态与检查 API** | 主线程健康检查、应用在线探测、程序化日志拉取/注入 | ✅ **v2.1 全新加入** |


## 🚀 5 分钟闪电上手（真的，不骗你）

### 第一步：下载动态库（别慌，不需要你编译）

从 [Releases](https://github.com/PassByYou888/zAPI/releases) 下载对应平台的库，放到可执行目录：

| 平台 | 核心库 | IPC 依赖库 |
|------|--------|-----------|
| Windows 64-bit | `z_api_hub64.dll` | `z_ipc_64.dll` |
| Windows 32-bit | `z_api_hub32.dll` | `z_ipc_32.dll` |
| Linux / BSD | `libz_api_hub.so` | `libz_ipc.so` |
| macOS | `libz_api_hub.dylib` | `libz_ipc.dylib` |

**下载解压，完事，比装个 QQ 还简单。**

### 第二步：引用一个单元（就一行）

```pascal
uses
  z_api_hubtool_import;   // 就这一行，别眨眼
```

动态库会在你第一次调用 API 时自动加载，**就像外卖小哥自动按门铃一样省心。**

### 第三步：写个服务端（算个加法，带 v2.1 状态检查）

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
    // v2.1 新增：检查主线程是否正常运行
    if API_Check_MainThread = 1 then
      Writeln('✅ 主线程运行正常');

    // v2.1 新增：检查本应用是否已在网格中注册
    if API_Check_App('CalcService') = 1 then
      Writeln('✅ CalcService 已成功注册到服务网格');

    Writeln('✅ Pascal 服务已就绪，按 Enter 退出...');
    Readln;
  end;

  // v2.0 新增：动态注销 API（可选）
  API_UnReg(app, 'add');

  API_Exit_MainThread;
  API_Free_APPHnd(app);
  API_shutdown;
end.
```

### 第四步：写个客户端（远程调用，带 v2.1 日志拉取）

```pascal
program CalcClient;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  z_api_hubtool_import;

var
  param, result: TDataHnd;
  a, b, sum: Integer;
  logMsg: string;
begin
  API_Reset_Prepare;
  API_Prepare_Client('ipc:calc_service', nil);

  if API_Prepare_Done <> 1 then
  begin
    Writeln('连接失败');

    // v2.1 新增：拉取库日志看看发生了什么
    while API_Get_Status_Num > 0 do
    begin
      logMsg := API_Get_Status2;
      Writeln('[日志] ', logMsg);
    end;

    Halt(1);
  end;

  // v2.1 新增：调用前检查目标服务是否在线
  if API_Check_App('CalcService') = 0 then
  begin
    Writeln('⚠️ CalcService 当前不可用，请检查服务端是否启动');
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

  // v2.1 新增：注入一条自定义日志
  API_Post_Status2('客户端调用完成，结果=' + IntToStr(sum));

  API_Exit_MainThread;
  API_shutdown;
end.
```

### 第五步：运行（开两个终端）

服务端先跑，客户端再跑，客户端输出：

```
10 + 20 = 30
```

**从下载到跑通，不到 5 分钟。你甚至还没想好中午点哪家外卖。v2.1 还顺手帮你把健康检查和日志拉取都安排上了。**


## 🧠 核心概念（一分钟扫盲）

| 概念 | 说白了就是 |
|------|-----------|
| `TDataHnd` | 一个“快递包裹”，里面装着 API 名称和二进制数据 |
| `TAppHnd` | 你的“服务营业执照”，代表你注册的一组 API |
| `API_Call` | “打电话”——同步等待对方回复 |
| `API_Notify` | “发微信”——发了就跑，不等回复 |
| `API_UnReg` | **“注销营业执照”（v2.0）** —— 运行时移除 API，热卸载插件 |
| `API_SetOption` | **“调参数”（v2.0）** —— 运行时调整配置，不用重启 |
| `API_Check_MainThread` | **“看引擎是否点火”（v2.1）** —— 检查 C4 事件循环是否在跑 |
| `API_Check_App` | **“查对方在线否”（v2.1）** —— 探测目标应用是否已注册 |
| `API_Get_Status` / `API_Post_Status` | **“翻监控/写日志”（v2.1）** —— 程序化拉取/注入日志 |
| 回调（`TAPI_Call`） | 你的“接线员”，接到请求后处理业务 |

**数据流向：** 你创建包裹 → 塞数据 → 发出去 → 对方的接线员拆包 → 处理 → 塞回结果 → 你拆包取结果。跟淘宝购物流程差不多，只不过快了几万倍。


## ⚠️ 给老司机们的特别提醒（这个很重要）

你的回调函数（`TAPI_Call` / `TAPI_Notify`）运行在**后台线程池**里，所以：

### ❌ 千万别干这些事

1. **在回调里调用 `API_Call` 或 `API_Notify`** —— 会死锁，**比 Delphi 的 EAccessViolation 还难搞**
2. **在回调里 `Sleep` 或等事件** —— 会把线程池堵死
3. **在回调里直接更新 UI** —— 除非用 `TThread.Synchronize`

### ✅ 正确姿势

```pascal
// 回调里只做快速入队，让工作线程去处理
procedure GoodCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      // 在这里可以安全地调用 API_Call
      Res := API_Call('TargetApp', Data, 5000);
    end
  ).Start;
end;
```

**记住：回调要“秒进秒出”，别在里面搞大动作。就像接电话时只说“好的，我马上处理”，挂了再干活——别在电话里跟人家算微积分。**


## 🌍 跨语言互调矩阵（全绿，无红）

**你的 Pascal 服务，可以被下面任何语言调用；反过来，你的 Pascal 也能调下面任何语言的服务：**

| 语言 | 能不能互调？ | 备注 |
|------|-------------|------|
| **Pascal (Delphi/FPC)** | ✅ 自己调自己，当然行 | — |
| **C / C++** | ✅ | 穿一条裤子的兄弟 |
| **Python** | ✅ | AI 时代的万能胶水 |
| **Go** | ✅ | 云原生时代的红人 |
| **Rust** | ✅ | 号称最安全的语言 |
| **Java** | ✅ | 企业级应用的老对手 |
| **C#** | ✅ | .NET 生态的兄弟 |
| **VB.Net** | ✅ | 同上 |
| **Node.js** | ✅ | 通过 Bridge v2.0 |
| **PHP** | ✅ | 通过 Bridge v2.0 |
| **Web.js（浏览器里的 JS）** | ✅ | 通过 Bridge v2.0 |
| **……还有更多** | ✅ | 只要支持 C ABI 或 HTTP |

**看懂了吗？你的老 Delphi 系统一夜之间变成了“全能翻译官”，跟谁都能唠嗑。v2.1 还给了你一副“望远镜”和“听诊器”——`API_Check_App` 让你看清谁在线，`API_Get_Status` 让你听清内部动静。**


## 📊 性能数据（别眨眼）

| 场景 | 延迟 | 吞吐量 |
|------|------|--------|
| 本地 IPC（同机） | **< 1 ms** | **3000+ 次/秒** |
| 本地 TCP | ~2–5 ms | ~2500 次/秒 |
| 跨机器 TCP | 取决于网速 | ~500–1000 次/秒 |

**IPC 模式下，你眨一下眼睛的时间，够它调 3000 次。** 比你的老板催你改 bug 还快。


## 🎯 应用场景（你的 Pascal 代码能有多秀？）

| 场景 | Pascal 能干啥？ |
|------|----------------|
| **遗留系统现代化** | 把二十年的 Delphi 系统通过 zAPI 暴露成微服务，**让 Python 和 Go 来调它，老板直接看傻** |
| **工业自动化** | Delphi 写的控制系统，跟 C++ 的高性能模块、Python 的数据分析无缝对接——**工业 4.0 来了，你的代码没掉队** |
| **桌面应用 + AI** | Delphi 桌面应用直接调用 Python 的 AI 推理服务，**不用搭 Web 服务，不用写 JSON** |
| **跨团队协作** | 老团队用 Delphi，新团队用 Rust/Go，算法团队用 Python——**zAPI 当翻译官，大家各写各的，互不干扰** |
| **热更新（v2.0）** | 用 `API_UnReg` 注销旧 API，重新注册新 API，**不停机更新服务** |
| **智能可观测性（v2.1）** | 用 `API_Check_App` 做依赖健康检查，用 `API_Get_Status` 拉取日志集成到监控系统，**故障定位从小时级变分钟级** |


## 🐛 调试小贴士（v2.1 增强版）

当服务或客户端出现问题时，你有 **三条路** 可以走：

**① 看控制台** —— 库默认会将详细的运行日志（包括连接状态、注册信息、错误原因）打印到标准输出（`ConsoleOutput=True`）。

**② 拉日志（v2.1 新增）** —— 在主循环中调用 `API_Get_Status_Num` + `API_Get_Status2` 程序化拉取日志，集成到你的日志系统：

```pascal
while API_Get_Status_Num > 0 do
begin
  LogMsg := API_Get_Status2;
  MyLogger.Write('[zAPI] ' + LogMsg);
end;
```

**③ 写日志（v2.1 新增）** —— 用 `API_Post_Status2` 注入你自己的日志，统一汇入 zAPI 日志流。

**常见报错及解决方案：**

| 报错信息 | 原因 | 怎么治？ |
|---------|------|---------|
| `bind address already in use` | 端口被占 | 换端口或杀掉占用的进程 |
| `no found app("XXX") api("YYY")` | 应用名或 API 名写错了 | 检查大小写，必须一模一样；用 `API_Check_App` 提前探测 |
| `timeout` | 超时 | 增加超时值，用 `API_Check_App` 看看服务还在不在 |

如果问题仍然存在，请检查防火墙设置、网络连通性，并确认动态库版本与程序位数匹配。


## ❓ 常见问题（FAQ）

**Q1: 动态库加载失败怎么办？**

A: 确认 `z_api_hub64.dll`（或对应平台）在可执行文件目录或系统 `PATH` 里。检查 32/64 位是否匹配。

**Q2: 回调里能调 `API_Call` 吗？**

A: **不能！** 会死锁。把远程调用丢给另一个线程去做。

**Q3: 多线程调用安全吗？**

A: **所有导出函数都是完全线程安全的**，放心开线程并发调用。

**Q4: 支持哪些系统？**

A: Windows、Linux、macOS、FreeBSD、OpenBSD、NetBSD——**全平台通吃**。

**Q5: v2.1 新增了什么？**

A: **五个状态与检查 API**，让你从“盲调”进化到“上帝视角”：

| API | 作用 |
|-----|------|
| `API_Check_MainThread` | 检查 C4 事件循环是否在运行（主线程健康） |
| `API_Check_App` | 基于本地缓存探测目标应用是否在线 |
| `API_Get_Status_Num` | 获取日志队列中有多少条待读消息 |
| `API_Get_Status` / `API_Get_Status2` | 从队列中取出一条日志消息 |
| `API_Post_Status` / `API_Post_Status2` | 向日志队列注入自定义日志 |

**同时继承 v2.0 全部特性**：动态注销（`API_UnReg`）、运行时配置（`API_SetOption`）、PHP/Node.js Bridge 支持。

**Q6: 动态注销后，正在进行的调用会怎样？**

A：正在执行中的回调不会被打断，它们会正常完成。新到达的请求会在广播传播后（约 3 秒）收到“未找到”错误。这是分布式系统的正常最终一致性行为。


## 📚 API 速查表（存一下，以后有用）

| 函数 | 干啥的？ | 版本 |
|------|---------|------|
| `API_Create_DataHnd` | 创建数据包裹 | v2.1 |
| `API_Free_DataHnd` | 销毁包裹 | v2.1 |
| `API_WriteBuffer` | 往包裹里塞数据 | v2.1 |
| `API_ReadBuffer` | 从包裹里取数据 | v2.1 |
| `API_GetPos` / `API_SetPos` | 查看/设置包裹里的“读指针”位置 | v2.1 |
| `API_GetSize` / `API_SetSize` | 查看/调整包裹大小 | v2.1 |
| `API_Create_APPHnd` | 注册你的“服务公司” | v2.1 |
| `API_Free_APPHnd` | 注销公司 | v2.1 |
| `API_Reg_Call` | 注册一个“电话客服” | v2.1 |
| `API_Reg_Notify` | 注册一个“短信客服” | v2.1 |
| `API_UnReg` | **“吊销执照”——运行时注销 API，热卸载** | **v2.0** |
| `API_SetOption` | **“调参数”——运行时配置，不用重启** | **v2.0** |
| `API_Check_MainThread` | **“看引擎是否点火”——检查主线程** | **v2.1** |
| `API_Check_App` | **“查对方在线否”——探测应用** | **v2.1** |
| `API_Get_Status_Num` / `API_Get_Status` | **“翻监控”——拉取日志** | **v2.1** |
| `API_Post_Status` | **“写日志”——注入日志** | **v2.1** |
| `API_Local_APP_Call` | 本地测试（不联网） | v2.1 |
| `API_Reset_Prepare` | 重置网络配置 | v2.1 |
| `API_Prepare_Service` | 启动一个服务监听 | v2.1 |
| `API_Prepare_Client` | 连到别人家的服务 | v2.1 |
| `API_Prepare_Done` | 正式开张营业 | v2.1 |
| `API_Exit_MainThread` | 打烊前通知 | v2.1 |
| `API_Call` | 打电话（远程调用） | v2.1 |
| `API_Notify` | 发短信（单向通知） | v2.1 |
| `API_shutdown` | 彻底关门，释放资源 | v2.1 |


## 🤝 社区 & 支持

- **开源首页**：[https://github.com/PassByYou888/zAPI](https://github.com/PassByYou888/zAPI)
- **仓库地址**：[https://github.com/PassByYou888/zAPI.git](https://github.com/PassByYou888/zAPI.git)
- **作者 QQ**：`600585`

**Star、Fork、Issue、PR——来者不拒，你的每一个 Star 都是我们熬夜写代码的动力。**


## 📄 许可证

**MIT License** —— 随便用，随便改，拿去卖钱也行，不用谢我。


> **“让每一种语言，都能轻松调用全世界。”**  
> 这不是科幻片，这是 zAPI 每天都在做的事。

**现在，去给你的 Pascal 项目开个“跨语言外挂”吧。v2.1 还附赠了“监控仪表盘”能力，你值得拥有。** 🚀

## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](../C++/API%20Hub%20Tool%20C++%20使用指南.md)
- [API Hub Tool C 语言使用指南](../C++/API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](../Py/从零到一，掌握多语言互调.md)
- [API Hub for Go 从零到一掌握多语言互调](../Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)
- [zAPI Rust 使用指南](../rust/zAPI%20Rust%20使用指南.md)
- [API Hub Java 使用指南](../java/API%20Hub%20Java%20使用指南.md)
- [API Hub Tool for C# — 完整使用指南](../C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [API Hub Tool for Pascal](API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../node/Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](../Py/web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](../Py/web/js_api.py%20使用指南.md)
- [📖 ZAPI Bridge 完整使用手册](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)
- [序列化通信技术指南：Call 与 Notify 的选型与实现](../pascal/SequenceData/序列化通信技术指南：Call%20与%20Notify%20的选型与实现.md)
