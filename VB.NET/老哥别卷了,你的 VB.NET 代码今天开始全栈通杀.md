# 🧓 老哥别卷了！你的 VB.NET 代码，今天开始"全栈通杀"

> **"干了二十年 VB，没想到有一天能指着 Python 说：你过来啊！"** —— 某位 50+ 老哥跑通 zAPI 后的真实感慨
>
> **版本：** 2.0（与 ZAPI 核心 v2.0 同步）

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![VB.NET](https://img.shields.io/badge/VB.NET-.NET%20Framework%204.6%2B%20%7C%20.NET%20Core-512BD4.svg)](https://docs.microsoft.com/en-us/dotnet/visual-basic/)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS%20%7C%20BSD-lightgrey.svg)]()

---

## 🤯 老哥，是不是觉得 VB.NET 越来越"边缘"了？

你从 VB6 时代一路肝到 VB.NET，WinForms、WPF 玩得比自家遥控器还熟。项目稳如泰山，客户夸你靠谱。直到有一天，老板端着枸杞茶走过来，幽幽地说：

*"老张啊，咱们要上微服务了，Python 那个 AI 模型你得调一下，Go 写的网关你也得对接，还有 Rust 那个高性能模块……"*

你低头看了看自己写了二十年的 VB.NET，又抬头看了看旁边小年轻噼里啪啦敲的 YAML 和 Dockerfile——**内心 OS：我他妈是造了什么孽，要受这罪？**

你想让 VB.NET 调 C++ 的底层库？——得写 DllExport，头文件对到老花镜都碎了两副。  
你想调 Python 的推理服务？——中间搭个 Flask，JSON 序列化写到吐，还得处理超时重试。  
你想跟 Go、Rust、Java、Node.js、PHP 聊天？——每个都给你整一套 HTTP + Protobuf，**比带孙子写作业还心累**。

**是不是感觉 VB.NET 快成"语言孤岛"了？**

**别慌，zAPI 来了。** 你的 VB.NET 代码今天开始"全栈通杀"——想调谁调谁，想被谁调被谁调，**再也不用看小年轻脸色了**。

> **v2.0 新特性：** 现在不仅 C++/Python/Go 能调，PHP 和 Node.js 也能通过 [ZAPI Bridge](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md) 调用你的 VB.NET 服务了。

---

## 🎯 zAPI 是啥？一句话给你整明白

**zAPI 是一个让 VB.NET 和其他十几种编程语言（C#、C++、Python、Go、Rust、Java、Node.js、PHP、Web.js、Pascal、Delphi、FPC……）能"无缝互捅"的 RPC 框架。**

不需要写复杂的 P/Invoke 声明，不需要折腾 COM 互操作，不需要搭 HTTP 服务——**你只需要像调用 Win32 API 一样声明几个函数，VB.NET 就能调全世界。**

```text
┌─────────────┐                    ┌──────────────────┐      C ABI      ┌─────────────┐
│   VB.NET    │ ──── P/Invoke ──── │  z_api_hub       │ ─────────────── │  zAPI Core  │
│  (你的代码) │ ◄─── 返回结果 ──── │  动态库          │ ◄────────────── │  (DLL/SO)   │
└─────────────┘                    └──────────────────┘                 └─────────────┘
                                                                              │
                                                                              ▼
                                                                 ┌─────────────────────┐
                                                                 │ C++ / Python / Go   │
                                                                 │ Rust / Java / C#    │
                                                                 │ Node.js / PHP       │
                                                                 │ Web.js / Pascal     │
                                                                 └─────────────────────┘
```

**翻译成人话：** 你的 VB.NET 调用 `API_Call`，zAPI 内核转手就把请求扔给目标语言的服务，然后把结果给你送回来——**比你泡杯茶还快，你甚至感觉不到中间隔了十八层。**

---

## ✨ 核心亮点（老哥，看完你就知道这玩意儿多顶）

| 特性 | 有多猛？ |
|------|---------|
| 🌍 **12+ 语言通杀** | VB.NET、C#、C++、Python、Go、Rust、Java、Node.js、PHP、Web.js（浏览器里的 JS）、Pascal、Delphi、FPC——**全部拿下，一个不落** |
| ⚡ **IPC 延迟 < 1ms** | 同机通信快到你怀疑人生，3000+ 请求/秒——**比你敲回车还快** |
| 🔌 **TCP + IPC 双模** | 跨机器用 TCP，同机用 IPC，一个地址字符串搞定——**不用改代码，真·一次编写到处运行** |
| 🔄 **自动服务发现** | 基于 C4 服务网格，自动注册、负载均衡、断线重连——**注册中心和配置中心全省了，老板还以为你偷懒** |
| 🧵 **全线程安全** | 1000 个线程同时调用无压力——**放心开 Task，不会翻车** |
| 🚀 **零配置加载** | P/Invoke 自动加载动态库——**不用手动 LoadLibrary，不用操心路径** |
| 🎯 **Call + Notify 双模式** | 要结果还是要速度？**你自己选** |
| 🔧 **动态注销 API（v2.0）** | `API_UnReg` —— 运行时移除 API，自动广播至所有对等节点（约 3 秒传播），适合热卸载插件 |
| ⚙️ **运行时配置（v2.0）** | `API_SetOption` —— 动态调整认证密码、等待连接、IPC 线程池等参数，无需重启 |

---

## 🚀 5 分钟闪电上手（老哥，不骗你）

### 第一步：下载动态库（别慌，不需要你编译）

从 [Releases](https://github.com/PassByYou888/zAPI/releases) 下载对应平台的库，放到输出目录（比如 `bin\Debug\net8.0`）：

| 平台 | 核心库 | IPC 依赖库 |
|------|--------|-----------|
| Windows 64-bit | `z_api_hub64.dll` | `z_ipc_64.dll` |
| Windows 32-bit | `z_api_hub32.dll` | `z_ipc_32.dll` |
| Linux / BSD | `z_api_hub.so` | `libz_ipc.so` |
| macOS | `z_api_hub.dylib` | `libz_ipc.dylib` |

**下载解压，扔进 bin 目录，完事。比装个输入法还简单。**

### 第二步：引用绑定项目（就一行代码的事儿）

本项目已经给你准备好了 `ApiHubTool.Bindings` 类库（VB.NET 版），你只需要在你的项目里引用它：

```xml
<ProjectReference Include="..\ApiHubTool.Bindings\ApiHubTool.Bindings.vbproj" />
```

然后在你代码顶部加一句：

```vb.net
Imports ApiHubTool
```

**完事儿。动态库会自动加载，不用你操心。**

### 第三步：写个服务端（算个加法，简单到哭）

```vb.net
Imports ApiHubTool
Imports System.Runtime.InteropServices

Module Service
    Private Sub AddCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
        Dim hIn = New DataHnd With {.Handle = input}
        Dim hOut = New DataHnd With {.Handle = output}
        Dim buf = API.ReadAllBytes(hIn)
        If buf.Length >= 8 Then
            Dim a = BitConverter.ToInt32(buf, 0)
            Dim b = BitConverter.ToInt32(buf, 4)
            Dim sum = a + b
            API.API_WriteBuffer(hOut, BitConverter.GetBytes(sum), 4)
            Console.WriteLine($"[Service] add({a},{b}) = {sum}")
        End If
    End Sub

    Sub Main()
        Dim app = API.API_Create_APPHnd("ServiceApp", "Demo Service")
        Dim addDel As APICallDelegate = AddressOf AddCallback
        GCHandle.Alloc(addDel)  ' 防止被 GC 回收，老哥别忘！
        API.API_Reg_Call(app, "add", "Addition", IntPtr.Zero, addDel)

        ' v2.0 新增：运行时配置（可选）
        API.API_SetOption("Wait_Connection_ReadyOk", "False")

        API.API_Reset_Prepare()
        API.API_Prepare_Service("ipc:demo_service", "ipc:demo_service")
        API.API_Prepare_Client("ipc:demo_service", app)

        If API.API_Prepare_Done() <> 1 Then
            Console.WriteLine("启动失败")
            Return
        End If

        Console.WriteLine("服务已启动，按 Enter 退出...")
        Console.ReadLine()

        API.API_Exit_MainThread()
        API.API_Free_APPHnd(app)
        API.API_shutdown()
    End Sub
End Module
```

### 第四步：写个客户端（远程调用，比点外卖还简单）

```vb.net
Imports ApiHubTool

Module Client
    Sub Main()
        API.API_Reset_Prepare()
        API.API_Prepare_Client("ipc:demo_service", AppHnd.Null)

        If API.API_Prepare_Done() <> 1 Then
            Console.WriteLine("连接失败")
            Return
        End If

        Dim param = API.API_Create_DataHnd("add")
        Dim payload(7) As Byte
        BitConverter.GetBytes(10).CopyTo(payload, 0)
        BitConverter.GetBytes(20).CopyTo(payload, 4)
        API.API_WriteBuffer(param, payload, 8)

        Dim result = API.API_Call("ServiceApp", param, 3000)
        API.API_Free_DataHnd(param)

        If result.IsValid AndAlso API.API_GetSize(result) >= 4 Then
            Dim sum = BitConverter.ToInt32(API.ReadAllBytes(result), 0)
            Console.WriteLine($"10 + 20 = {sum}")
            API.API_Free_DataHnd(result)
        Else
            Console.WriteLine("调用超时或失败")
        End If

        API.API_Exit_MainThread()
        API.API_shutdown()
    End Sub
End Module
```

### 第五步：运行（开两个命令行窗口，服务端先跑）

客户端输出：

```
10 + 20 = 30
```

**从下载到跑通，不到 5 分钟。你甚至还没想好中午点哪家外卖。**

---

## 🧠 核心概念（老哥，一分钟给你整明白）

| 概念 | 说白了就是 |
|------|-----------|
| `DataHnd` | 一个"快递包裹"，里面装着 API 名称和二进制数据 |
| `AppHnd` | 你的"服务营业执照"，代表你注册的一组 API |
| `API_Call` | "打电话"——同步等对方回复 |
| `API_Notify` | "发微信"——发了就跑，不等回复 |
| `API_UnReg` | **"注销营业执照"（v2.0）—— 运行时移除 API，热卸载插件** |
| `API_SetOption` | **"调参数"（v2.0）—— 运行时调整配置，不用重启** |
| 回调（`APICallDelegate`） | 你的"接线员"，接到请求后处理业务 |

**数据流向：** 你创建包裹 → 塞数据 → 发出去 → 对方接线员拆包 → 处理 → 塞回结果 → 你拆包取结果。**跟淘宝购物流程差不多，只不过快了几万倍。**

---

## ⚠️ 老哥，这条特别重要！（敲黑板）

你的回调函数运行在**后台线程池**里，所以：

### ❌ 千万别干这些事

1. **在回调里调用 `API_Call` 或 `API_Notify`** —— 会死锁，**比 VB6 的 `On Error Resume Next` 还难搞**
2. **在回调里 `Thread.Sleep` 或等事件** —— 会把线程池堵死，**比早高峰还堵**
3. **在回调里直接更新 UI** —— 除非用 `Control.Invoke`，否则等着报跨线程错误吧

### ✅ 正确姿势

```vb.net
' 回调里只做快速入队，让 Task 去处理
Public Sub GoodCallback(ByVal trigger As IntPtr, ByVal input As IntPtr, ByVal output As IntPtr)
    Task.Run(Sub()
        ' 在这里可以安全地调用 API_Call
        Dim res = API.API_Call("TargetApp", input, 5000)
        ' 处理结果...
    End Sub)
End Sub
```

**记住：回调要"秒进秒出"，别在里面搞大动作。就像接电话时只说"好的我知道了"，挂了再处理——别在电话里跟人家算微积分。**

---

## 🌍 跨语言互调矩阵（全绿，随便调）

**你的 VB.NET 服务，可以被下面任何语言调用；反过来，你的 VB.NET 也能调下面任何语言的服务：**

| 语言 | 能不能互调？ | v2.0 新特性 |
|------|-------------|-------------|
| **VB.NET** | ✅ 自己调自己，当然行 | — |
| **C#** | ✅ | — |
| **C / C++** | ✅ | — |
| **Python** | ✅ | — |
| **Go** | ✅ | — |
| **Rust** | ✅ | — |
| **Java** | ✅ | — |
| **Node.js** | ✅ | ✅ 通过 Bridge v2.0 |
| **PHP** | ✅ | ✅ 通过 Bridge v2.0 |
| **Web.js（浏览器里的 JS）** | ✅ | ✅ 通过 Bridge v2.0 |
| **Pascal / Delphi / FPC** | ✅ | — |

**看懂了吗？你的 VB.NET 代码一夜之间变成了"全能翻译官"，跟谁都能唠嗑。**

---

## 📊 性能数据（老哥，别眨眼）

| 场景 | 延迟 | 吞吐量 |
|------|------|--------|
| 本地 IPC（同机） | **< 1 ms** | **3000+ 次/秒** |
| 本地 TCP | ~2–5 ms | ~2500 次/秒 |
| 跨机器 TCP | 取决于网速 | ~500–1000 次/秒 |

**IPC 模式下，你眨一下眼睛的时间，够它调 3000 次。** 比你敲 `Console.WriteLine` 还快。

---

## 🎯 应用场景（老哥，你的 VB.NET 能有多秀？）

| 场景 | VB.NET 能干啥？ |
|------|----------------|
| **遗留系统现代化** | 把十几年的 VB.NET 系统通过 zAPI 暴露成微服务，**让 Python 和 Go 来调它，老板直接看傻，年终奖稳了** |
| **工业自动化** | VB.NET 写的控制系统，跟 C++ 的高性能模块、Python 的数据分析无缝对接——**工业 4.0 来了，你的代码没掉队** |
| **桌面应用 + AI** | VB.NET 桌面应用直接调用 Python 的 AI 推理服务，**不用搭 Web 服务，不用写 JSON，省下的时间可以摸鱼** |
| **跨团队协作** | 老团队用 VB.NET，新团队用 Rust/Go，算法团队用 Python——**zAPI 当翻译官，大家各写各的，互不干扰，一团和气** |
| **热更新（v2.0）** | 用 `API_UnReg` 注销旧 API，重新注册新 API，**不停机更新服务** |

**你的 VB.NET 代码不再是"历史包袱"，而是"企业核心资产"。**

---

## 🐛 调试小贴士（专治各种不服）

库会在控制台自动输出详细的运行日志（包括连接状态、注册信息、错误原因）。你可以在 `<可执行文件名>.api-tool.ini` 配置文件中调整日志行为。

**常见报错及解决方案（都是血泪经验）：**

| 报错信息 | 原因 | 怎么治？ |
|---------|------|---------|
| `bind address already in use` | 端口被占 | 换端口或杀掉占用的进程，**用 `netstat -ano` 查** |
| `no found app("XXX") api("YYY")` | 应用名或 API 名写错了 | 检查大小写，必须一模一样，**VB 不区分大小写但底层 C 区分！** |
| `timeout` | 超时 | 增加超时值，看看服务还在不在，**ping 一下** |

---

## ❓ 常见问题（FAQ）

**Q1: 动态库加载失败怎么办？**

A: 确认 `z_api_hub64.dll`（或对应平台）在输出目录或系统 `PATH` 里。检查 32/64 位是否匹配。**别问为什么，问就是经验。**

**Q2: 回调里能调 `API_Call` 吗？**

A: **不能！** 会死锁。用 `Task.Run` 丢到另一个线程去调。**这条是红线，踩了别怪我没提醒。**

**Q3: 多线程调用安全吗？**

A: 除了状态日志相关函数外，其他函数都线程安全。放心开 `Task`。**底层用的是无锁数据结构，比你写的锁高效多了。**

**Q4: 支持哪些系统？**

A: Windows、Linux、macOS、FreeBSD、OpenBSD、NetBSD——**全平台通吃，你换系统都不用改代码。**

**Q5: 跟 C# 的绑定有啥区别？**

A: 语法上 VB.NET 更"啰嗦"一点，但功能完全一样——**都是 P/Invoke，底层调的是同一个 DLL，性能没差别。**

**Q6: 动态注销 API 后，正在进行的调用会怎样？**（v2.0）

A: 正在执行中的回调不会被打断，它们会正常完成。新到达的请求会在广播传播后（约 3 秒）收到"未找到"错误。

---

## 🧓 老哥，最后说两句

你写了二十年代码，技术功底扎实，什么 COM、DCOM、Win32 API 都玩过。现在这个时代，**微服务、AI、云原生**是大势所趋，但你不需要重新学一门语言——zAPI 让你用最熟悉的 VB.NET，照样玩转整个技术生态。

**你的经验很值钱，你的代码也很值钱。** 别让语言限制你的想象力。

---

## 📦 完整示例代码（项目里都有）

本项目包含 5 个 VB.NET 示例，从入门到压测全覆盖：

| 项目 | 说明 |
|------|------|
| `HelloWorld` | 本地调用，无网络，验证基本流程（**适合第一次跑**） |
| `Service` + `Client` | 基础服务端 + 客户端，IPC 通信 |
| `FuncService` | **12 个 API 的功能服务端**（加减乘除、大小写转换、反转、时间、随机数、数组求和、字符串拼接） |
| `FuncClient` | **真正并发压测客户端**，每个 API 开 100 个线程，统计延迟分布和 QPS |

**所有代码都是 VB.NET，开箱即跑，拿来就改。**

---

## 🤝 社区 & 支持

- **开源首页**：[https://github.com/PassByYou888/zAPI](https://github.com/PassByYou888/zAPI)
- **仓库地址**：[https://github.com/PassByYou888/zAPI.git](https://github.com/PassByYou888/zAPI.git)
- **作者 QQ**：`600585`

**Star、Fork、Issue、PR——来者不拒，你的每一个 Star 都是我们熬夜写代码的动力。**

---

## 📄 许可证

**MIT License** —— 随便用，随便改，拿去卖钱也行，**不用谢我，谢 MIT 就行。**

---

> **"让每一种语言，都能轻松调用全世界。"**  
> 这不是科幻片，是 zAPI 每天都在做的事。

**现在，去给你的 VB.NET 项目开个"全栈通杀"外挂吧。** 🚀

## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](../C++/API%20Hub%20Tool%20C++%20使用指南.md)
- [API Hub Tool C 语言使用指南](../C++/API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](../Py/从零到一，掌握多语言互调.md)
- [API Hub for Go 从零到一掌握多语言互调](../Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)
- [zAPI Rust 使用指南](../rust/zAPI%20Rust%20使用指南.md)
- [API Hub Java 使用指南](../java/API%20Hub%20Java%20使用指南.md)
- [API Hub Tool for C# — 完整使用指南](../C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [API Hub Tool for Pascal](../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../node/Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](../Py/web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](../Py/web/js_api.py%20使用指南.md)
- [📖 ZAPI Bridge 完整使用手册](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)
