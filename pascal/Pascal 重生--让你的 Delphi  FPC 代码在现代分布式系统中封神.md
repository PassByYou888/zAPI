# 🏛️ Pascal 重生：让你的 Delphi / FPC 代码在现代分布式系统中“封神”

> **“你以为是老古董？不，它现在是微服务架构里的‘太上皇’。”**
>
> 适用于：Delphi 10.x+ | Free Pascal 3.2+ | 所有 64/32 位 Windows/Linux/macOS
>
> **版本：** 2.1（与 ZAPI 核心 v2.1 同步）

---

## 📜 这玩意儿到底是啥？

想象一下，你有一套用 Pascal 写了二十年的进销存系统，稳如泰山，客户用的很爽。突然有一天，老板说：“我们要上 AI 预测，要用 Go 写网关，要让 Rust 处理并发——你的老系统，得能跟他们说话。”

放在以前，你可能会去翻 SOAP 或者搞 COM 互操作，然后血压拉满。但现在，**zAPI 来了**。

**zAPI 的 Pascal 绑定，就是一套能让你的 Delphi / FPC 代码瞬间拥有“跨语言超能力”的工具包。** 你的 Pascal 函数，可以一秒变成远程 API；你的老系统，可以直接调用 Python 训练的 TensorFlow 模型，或者被 Go 微服务优雅地编排。

> **核心真相：** 我们没有改造你的编译器，只是在你的 Pascal 代码和全世界之间，架了一座 C 语言级别的“通天塔”。

> **v2.1 新特性：** 新增了 **五状态与检查 API**——`API_Check_MainThread`（检查事件循环是否运行）、`API_Check_App`（探测目标应用在线）、`API_Get_Status_Num`/`API_Get_Status`（程序化拉取日志）、`API_Post_Status`（注入自定义日志），极大提升了调试和运维能力。同时继承 v2.0 的 **动态注销**（`API_UnReg`）、**运行时配置**（`API_SetOption`）以及 **PHP/Node.js Bridge** 支持，让 Pascal 服务在现代分布式网格中如鱼得水。

---

## 🆚 它跟“古典互联网”的那些破事有啥区别？

| 你以前怎么干的 | 血压指数 | 用 zAPI 怎么干 | 爽度指数 |
| :--- | :--- | :--- | :--- |
| 写 SOAP 服务，配一堆 WSDL，被 XML 搞到眼花。 | 💢💢💢💢💢 | `API_Reg_Call('myApi', @MyPascalFunc);` 一行注册。 | ⭐⭐⭐⭐⭐ |
| 用 `subprocess` 调用 Python，解析 stdout 字符串，一不留神就乱码。 | 💢💢💢 | `API_Call('PythonService', data, 3000);` 直接拿结果。 | ⭐⭐⭐⭐⭐ |
| 为了调一个 C++ 加密库，折腾 DLL 导出，经常 Access Violation。 | 💢💢💢💢 | `API_WriteBuffer` + `API_ReadBuffer` 传数据，零拷贝，不崩溃。 | ⭐⭐⭐⭐⭐ |
| 想让 Go 来调你 Delphi 写的函数？写 CGO 绑定的心态崩了。 | 💢💢💢💢💢 | 应用名 + API 名注册，Go 直接 `Call`，啥额外代码不用写。 | ⭐⭐⭐⭐⭐ |
| 想让 PHP 或 Node.js 调你的老代码？搭 HTTP 服务写到怀疑人生。 | 💢💢💢💢 | 通过 ZAPI Bridge 一行注册，PHP/Node.js 直接用。 | ⭐⭐⭐⭐⭐ |
| 服务出问题，想看一眼内部状态和日志？只能翻控制台或写文件。 | 💢💢💢 | `API_Get_Status` 拉取实时日志，`API_Check_App` 探测服务在线，调试如虎添翼。 | ⭐⭐⭐⭐⭐ |

**结论：** zAPI 不是让 Pascal 变得“年轻”，而是让它直接“封神”，坐在那里等着别人来朝拜，或者它去巡视别人的领地。**v2.1 让运维和调试也进入了“上帝视角”时代。**

---

## ⚙️ 核心作战单元（老司机 5 分钟扫盲）

看代码之前，先记住这几个比美女还让你惦记的概念：

1.  **`TDataHnd`（数据快递盒）**：什么都能装（整数、字符串、结构体）。你往里写，别人往外读。它自带“API 名称”标签，不会送错门。
2.  **`TAppHnd`（你的营业执照）**：你的应用在网络里的唯一身份证。你用这个名字行走江湖，别人喊这个名字找到你。
3.  **`API_Call`（打电话）**：同步喊一嗓子，必须等对方回话（带回执）。
4.  **`API_Notify`（发短信）**：发了就跑，不等回复，主打一个“爱咋咋地”。
5.  **`API_UnReg`（注销执照）**—— **v2.0 新增**：运行时移除 API，支持热卸载插件、临时维护、权限动态调整，约 3 秒广播传播。
6.  **`API_SetOption`（调参数）**—— **v2.0 新增**：运行时调整认证密码、等待连接、IPC 线程池等参数，无需重启应用。
7.  **`API_Check_MainThread`（看引擎是否点火）**—— **v2.1 新增**：检查 C4 事件循环是否正常运行，用于启动前就绪确认。
8.  **`API_Check_App`（查对方在线否）**—— **v2.1 新增**：基于本地缓存快速探测目标应用是否在线，避免无效超时。
9.  **`API_Get_Status` / `API_Post_Status`（日志任我取/写）**—— **v2.1 新增**：程序化拉取库内部日志，或注入自定义日志，实现集中监控。

> **🚨 生死线（敲黑板）：** 你的回调函数（`TAPI_Call`）是运行在**后台线程池**的。这意味着里面**绝对禁止**调用 `API_Call` 或 `API_Notify`（会死锁），也**绝对禁止** `Sleep(10000)` 或写死循环。你的任务就是**快速拆包 -> 处理 -> 打包返回**，像特工一样，一秒解决战斗。

---

## 🚀 闪电上手：让“加法”变成跨语言核武器

### 第一步：把子弹上膛（动态库）

从 `Binary` 文件夹拿这两个文件，扔到你的 EXE 同目录：

*   `z_api_hub64.dll` 或 `z_api_hub32.dll`
*   `z_ipc_64.dll` 或 `z_ipc_32.dll`

> 就这两步，没有任何环境变量要配，没有注册表要改。

### 第二步：引用一个单元，解锁全身经脉

在你的 Delphi / FPC 项目里，只需要一句话：

```pascal
uses
  z_api_hubtool_import;  // 就这一行，魔法开始
```

这个单元干了什么？它用 `external` 声明了所有函数，你的 EXE 启动时会自动去找同目录的 `z_api_hub64.dll`，比去食堂打饭还自动化。

### 第三步：写一个“加法”服务端（20 行搞定）

```pascal
program CalcServer;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  z_api_hubtool_import;

// 【1】定义接线员：谁来处理“加法”请求？
procedure AddCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
var
  a, b, sum: Integer;
begin
  // 拆包：从 Input 里读两个整数
  API_ReadBuffer(Input, @a, SizeOf(a));
  API_ReadBuffer(Input, @b, SizeOf(b));
  // 干活：算个和
  sum := a + b;
  // 打包：写进 Output
  API_WriteBuffer(Output, @sum, SizeOf(sum));
  Writeln(Format('[Pascal Service] %d + %d = %d', [a, b, sum]));
end;

var
  app: TAppHnd;
begin
  // 【2】注册营业执照（应用名唯一，别的语言就靠这个找你）
  app := API_Create_APPHnd('PascalCalc', 'Pascal Calculator');

  // 【3】把“加法”这个 API 挂到营业执照下面
  API_Reg_Call(app, 'add', 'a+b', nil, @AddCallback);

  // 【4】v2.0 新增：运行时配置（可选）
  API_SetOption('Wait_Connection_ReadyOk', 'False');

  // 【5】启动网络监听（IPC：同机超跑模式，延迟 < 1ms）
  API_Reset_Prepare;
  API_Prepare_Service('ipc:pascal_service', 'ipc:pascal_service');
  API_Prepare_Client('ipc:pascal_service', app);

  if API_Prepare_Done = 1 then
  begin
    Writeln('✅ Pascal 服务已就绪，按 Enter 退出...');
    Readln;
  end;

  // 【6】v2.0 新增：动态注销 API（可选）
  API_UnReg(app, 'add');

  // 【7】体面地退出
  API_Exit_MainThread;
  API_Free_APPHnd(app);
  API_shutdown;
end.
```

### 第四步：用“外援”（Python 或 PHP）来调你的 Pascal

**Python 客户端**（装好 `api_hub` 包）：

```python
from api_hub import C4

# 连上你的 Pascal 服务（地址必须完全一样）
client = C4("PascalCalc", "ipc:pascal_service")

# 调用 "add" API —— 此刻正在远程执行上面那段 Pascal 代码！
result = client.add(10, 20)
print(f"Python 说：Pascal 算出了 {result}")  # 输出 30
```

**PHP 客户端（v2.0 新增）**（通过 ZAPI Bridge）：

```php
<?php
require_once 'ZAPIBridgeClient.php';

$client = new ZAPIBridgeClient('http://127.0.0.1:8080/v1');
$result = $client->invoke('PascalCalc', 'add', [10, 20]);
echo "PHP 说：Pascal 算出了 " . $result . "\n";  // 输出 30
?>
```

**看到了吗？** 你什么都没干，Pascal 就变成了一个被 Python 和 PHP 调用的微服务。反过来，如果 Python 那边注册了 `AIService`，你的 Pascal 客户端也可以用 `API_Call('AIService', ...)` 去调它。

---

## 🗺️ 跨语言互调能力矩阵（全绿无红）

你的 Pascal 服务，可以被下面任何语言按在地上“摩擦”（调用）；反过来，你的 Pascal 也能去“摩擦”下面任何语言的服务。

| 语言 | 能互调？ | 感受如何？ | v2.1 新特性 |
| :--- | :--- | :--- | :--- |
| **Pascal (Delphi/FPC)** | ✅ | 自己打自己，那叫一个丝滑。 | — |
| **C / C++** | ✅ | 穿一条裤子的兄弟，内存布局完全一样。 | — |
| **Python** | ✅ | AI 时代的万能胶水，现在粘上你了。 | — |
| **Go** | ✅ | 云原生时代的红人，也要喊你一声大哥。 | — |
| **Rust** | ✅ | 号称最安全的语言，也要跟你借数据。 | — |
| **Java / C#** | ✅ | 企业级应用的老对手，现在握手言和。 | — |
| **PHP** | ✅ | Web 后端的老大哥，现在也要来调你的老代码。 | ✅ 通过 Bridge 双向调用 |
| **Node.js** | ✅ | 前端小年轻也得通过网关来调你的老古董。 | ✅ 通过 Bridge 双向调用 |
| **Web.js (浏览器)** | ✅ | 浏览器直接调，前端也要用你的 Pascal 算力。 | — |

**结论：** 你的老代码一夜之间变成了“全语言翻译官”，从被时代遗忘的角落，直接空降到技术生态的 C 位。**v2.1 让所有语言都能通过新状态 API 共享运行状态，调试和监控不再是盲人摸象。**

---

## 🧠 高阶玩法：你的 Pascal 代码能有多秀？

*   **降维打击：** 把 Delphi 写的一整套财务引擎，通过 zAPI 暴露出去，让 Java 的微服务去调。老板问你咋做到的，你就说“祖传代码，自带仙气”。
*   **AI 赋能：** 你的 Pascal 桌面程序，直接调用 Python 的 PyTorch 做图像识别，不需要搭 Flask，不需要写 JSON，数据直接在内存里飞。
*   **工业 4.0：** 用 Free Pascal 写的 PLC 上位机，通过 IPC 和 C++ 写的运动控制卡实时通信，延迟比传统串口低两个数量级。
*   **热更新（v2.0）：** 用 `API_UnReg` 动态注销旧 API，重新注册新版本，**实现不停机更新**，再也不用半夜爬起来重启服务了。
*   **Web 生态融合（v2.0）：** 通过 ZAPI Bridge，让 PHP 和 Node.js 直接调用你的 Pascal 核心逻辑，**Web 团队和桌面团队彻底打通**。
*   **智能可观测性（v2.1）：** 在主循环中定期调用 `API_Get_Status` 拉取库日志，配合 `API_Post_Status` 注入应用日志，实现统一日志流；调用前用 `API_Check_App` 探测依赖服务是否在线，优雅降级。**让故障定位从小时级缩短到分钟级。**

---

## ❓ 老兵不死，只问 FAQ

**Q1：我的 Delphi 是 7.0，能用吗？**
A：官方建议 Delphi 10.x+ / FPC 3.2+。但如果你非要战，用 Delphi 7 调 `stdcall` 可能得改一下 `cdecl` 声明——去翻一下 `z_api_hubtool_import.pas` 里的调用约定，改改就能战。但我们不保证每个坑都填平了。

**Q2：回调里真的不能调 `API_Call` 吗？我就想调一下。**
A：**不能！** 这是红线中的红线。一旦调了，轻则死锁卡死，重则进程崩给你看。把那个“远程调用”放到另一个线程里去执行，回调里只负责把数据丢进队列。

**Q3：这玩意儿是不是只认 Windows？**
A：错。`libz_api_hub.so` 和 `libz_ipc.so` 就是给 Linux 和 BSD 准备的。Free Pascal 在 Linux 上编译完，直接跑，啥都不用改。macOS 也有 `dylib`。

**Q4：我跑不起来，提示 `External exception` 或找不到 DLL。**
A：99% 是 `z_api_hub64.dll` 不在 EXE 同级目录。检查一下是不是 32/64 位搞混了，或者 `PATH` 环境变量里没有。

**Q5：v2.1 新增了啥？我该关注哪些？**
A：**① 状态与检查 API**：`API_Check_MainThread`（检查主线程是否运行）、`API_Check_App`（探测应用在线）、`API_Get_Status_Num`/`API_Get_Status`（拉取日志）、`API_Post_Status`（注入日志）——这些让你能像监控普通应用一样监控 zAPI 框架，极大提升运维体验。**② 继承 v2.0 所有特性**（动态注销、运行时配置、PHP/Node.js Bridge）。

**Q6：动态注销后，正在进行的调用会怎样？**
A：正在执行中的回调不会被打断，它们会正常完成。新到达的请求会在广播传播后（约 3 秒）收到“未找到”错误。这是分布式系统的正常最终一致性行为。

**Q7：日志队列会不会溢出？**
A：内部 FIFO 队列最多缓存 **1000 条**消息，溢出时丢弃最旧消息。建议主循环定期调用 `API_Get_Status` 消费日志，避免积压。

---

## 📜 附：老司机的最后一句忠告

你写了二十年代码，什么 COM、DCOM、Win32 API 都玩过。现在这个时代，微服务、AI、云原生是大势所趋，但你不需要重新学一门语言——zAPI 让你用最熟悉的 Pascal，照样玩转整个技术生态。

**去给那个二十年前写的 EXE 披上微服务的袈裟吧，它值得这一切。** 🚀

---

**[⬆ 回到顶层] | [GitHub 仓库](https://github.com/PassByYou888/zAPI) | [📖 ZAPI Bridge 完整使用手册](../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)**

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
