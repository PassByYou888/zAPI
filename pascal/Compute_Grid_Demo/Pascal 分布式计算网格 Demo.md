# Pascal 分布式计算网格 Demo —— 基于 C4 服务网格的负载均衡计算集群

## 项目位置

本 Demo 位于项目根目录的 **`DLL-Build\pascal\Compute_Grid_Demo\`** 下，完整路径为：

```
DLL-Build/
├── pascal/
│   ├── Compute_Grid_Demo/           ← 本 Demo 所在目录
│   │   ├── build.bat                ← 一键编译脚本
│   │   ├── clear_.bat               ← 清理临时文件
│   │   ├── compute_service.lpi      ← 服务注册中心项目
│   │   ├── compute_service.lpr
│   │   ├── compute_node.lpi         ← 计算节点项目
│   │   ├── compute_node.lpr
│   │   ├── compute_node_run_10x.bat ← 启动 10 个节点
│   │   ├── compute_call.lpi         ← 计算客户端项目
│   │   ├── compute_call.lpr
│   │   ├── compute_call_run_20x.bat ← 启动 20 个客户端
│   │   └── Pascal 分布式计算网格 Demo.md  ← 本文档
│   ├── z_api_hubtool_import.pas     ← 核心 C 绑定
│   ├── z_api_hubtool_helper.pas     ← RAII 封装
│   └── ...（其他示例）
└── Binary/                          ← 动态库（运行时必需）
    ├── z_api_hub64.dll
    ├── z_ipc_64.dll
    └── ...
```

> 项目根目录包含全部语言绑定（C++、C#、Go、Java、Python、Rust、VB.NET）的示例，本 Demo 是 Pascal 语言中展示**分布式服务网格**能力的典型代表。

---

## 1. 概述

本项目演示了如何使用 **zAPI（API Hub）** 配合 **Z‑framework** 构建一个 **分布式表达式计算网格**。通过三个简单的 Pascal 程序（`compute_service`、`compute_node`、`compute_call`），你可以快速搭建一个支持 **动态扩容**、**自动负载均衡** 的计算集群，用于执行字符串表达式的远程求值。

整个系统基于 **C4 分布式服务网格**，使用 **IPC（进程间通信）** 进行同机高速通信，延迟极低，适合在单机内构建微服务式的计算网格。你也可以将 IPC 地址替换为 TCP 地址，轻松扩展到多机集群。

**专业定位**：这是一个**无状态 Worker 池 + 自动服务发现 + 客户端‑服务端解耦** 的典型分布式计算架构，与 **Kubernetes Deployment + Service** 的微服务模式异曲同工，但更轻量，适用于边缘计算、高性能计算、实时数据分析等场景。

---

## 2. 组件说明

| 组件 | 文件名 | 角色 | 说明 |
|------|--------|------|------|
| **服务注册中心**（Coordinator） | `compute_service` | 服务网格协调者 | 创建 IPC 服务端点 `ipc:compute_grid`，供所有节点和客户端连接。它本身不提供任何 API，仅作为 C4 网格的“信标”，类似于 **Consul / etcd** 的服务注册功能。 |
| **计算节点**（Worker） | `compute_node` | 工作节点（Worker） | 注册应用名为 `'pas'`，并暴露一个 `'exp'` Call API。该 API 接收一个字符串表达式（如 `"3 + 5 * 2"`），使用 Z.Expression 引擎求值，返回结果字符串。多个节点可同时运行，自动形成负载均衡池，每个节点都是**无状态**的，易于水平扩展。 |
| **计算客户端**（Caller） | `compute_call` | 任务发起者 | 连接 IPC 服务，循环生成随机算术表达式（如 `"123 + 456"`），调用远程 API `'exp'` 并打印结果。可同时启动大量客户端模拟高并发请求。 |

---

## 3. 体系架构

```text
┌─────────────────────────────────────────────────────────────────┐
│                      IPC 服务网格                              │
│                 ipc:compute_grid                               │
│              (由 compute_service 创建)                         │
└────────────────────────┬────────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ▼                ▼                ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ compute_node │  │ compute_node │  │ compute_node │  ... (可扩展至 N 个)
│  (Worker 1)  │  │  (Worker 2)  │  │  (Worker 3)  │
│  app='pas'   │  │  app='pas'   │  │  app='pas'   │
│  api='exp'   │  │  api='exp'   │  │  api='exp'   │
└──────────────┘  └──────────────┘  └──────────────┘
                         ▲
                         │ 自动负载均衡 (C4)
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ▼                ▼                ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ compute_call │  │ compute_call │  │ compute_call │  ... (可扩展至 M 个)
│  (Client 1)  │  │  (Client 2)  │  │  (Client 3)  │
└──────────────┘  └──────────────┘  └──────────────┘
```

- **服务注册中心**（`compute_service`）先启动，建立 IPC 端点，相当于 **服务网格的控制平面**。
- **计算节点**（`compute_node`）随后启动，连接到服务端点并注册自己的应用 `'pas'`，类似于 **Kubernetes Pod 加入集群**。
- **客户端**（`compute_call`）最后启动，连接到同一端点，通过 `API_Call('pas', ...)` 发送请求。
- C4 网格自动感知所有注册了 `'pas'` 的节点，并将客户端的请求 **按负载均衡策略**（基于当前活跃请求数和线程池状态）分发到各节点，实现了 **透明路由**。

---

## 4. 负载均衡机制

在 zAPI 中，**负载均衡是自动的、无需额外配置的**：

- 当多个进程注册了 **相同的应用名**（本例中为 `'pas'`）时，C4 网格会将这些节点视为同一个逻辑应用的多个实例，形成 **服务池（Service Pool）**。
- 客户端调用 `API_Call('pas', ...)` 时，C4 会根据各节点的 **当前负载**（活跃请求数、线程数等）自动选择负载最低的节点进行路由，**无需引入额外的负载均衡器（如 Nginx、HAProxy）**。
- 即使某个节点宕机，C4 也会自动将其从路由表中移除，请求会透明地转发到其他健康节点，实现了 **容错（Fault Tolerance）** 和 **高可用（High Availability）**，这与 **微服务中的断路器模式（Circuit Breaker）** 有异曲同工之妙。

本例中，`compute_node` 均注册 `'pas'`，因此所有节点构成一个计算池。启动的节点越多，整个集群的吞吐量越大；启动的客户端越多，并行请求的压力越大，系统会自动适应。这种设计符合 **反应式系统（Reactive Systems）** 的弹性（Resilience）原则。

---

## 5. 使用方法

### ⚠️ 第一步：编译（必须先做！）

在运行任何程序之前，**必须先编译**三个可执行文件。进入 `Compute_Grid_Demo` 目录，双击运行 `build.bat`（或执行 `build.bat`）：

```batch
lazbuild -B compute_service.lpi
lazbuild -B compute_node.lpi
lazbuild -B compute_call.lpi
```

编译产物为 `compute_service.exe`、`compute_node.exe`、`compute_call.exe`。

> 确保你的 Lazarus / FPC 环境已安装 **Z‑framework** 和 **zAPI** 绑定单元（`z_api_hubtool_import`、`z_api_hubtool_helper`）。若编译报错，请检查库路径是否正确。

### 第二步：启动服务注册中心（Coordinator）

```bash
compute_service.exe
```
该进程会一直运行，保持 IPC 端点可用。看到 `计算服务启动成功` 即可。

### 第三步：启动计算节点（Worker）—— **分布式可视化的关键**

- 你可以手动启动多个 `compute_node.exe`，也可以直接运行 **`compute_node_run_10x.bat`**：
  ```batch
  compute_node_run_10x.bat
  ```
  该批处理会通过 `start` 命令一次性打开 **10 个独立的控制台窗口**，每个窗口运行一个 `compute_node.exe` 实例。

- **🎯 此时最精彩的场景出现了**：你会看到 **10 个窗口同时在疯狂地打印日志** —— 每个节点都在接收客户端发来的计算请求，并将表达式和求值结果实时输出到自己的窗口上。

- 由于 C4 网格的负载均衡机制，客户端发来的海量请求会被 **自动打散、均匀地分发** 到这 10 个节点上。你观察各个窗口的打印内容就会发现：**同一个时刻，有的窗口在处理 `100 + 200`，有的在处理 `500 * 3`，有的在处理 `800 / 4`** —— 请求被分散到了不同的计算单元，**这就是分布式计算最直观、最生动的可视化呈现**。这种“多窗口齐鸣”的场景，与 **Hadoop / Spark 集群中多个 TaskManager 同时处理数据分片** 的现象完全一致。

- 你可以启动任意数量的节点（几十个甚至上百个），节点越多，窗口越多，整个桌面上“此起彼伏”的计算反馈就越壮观，集群的吞吐量也随之线性提升。

### 第四步：启动计算客户端（Caller）

- 同样可以手动启动或多个启动，`compute_call_run_20x.bat` 会启动 20 个客户端：
  ```batch
  compute_call_run_20x.bat
  ```
- 每个客户端会持续 60 秒，每秒约发起 1000 次计算请求（由代码中的 `TCompute.Sleep(1)` 控制），然后自动退出。
- 你可以通过修改批处理文件中的循环次数启动上百个客户端，以模拟高并发压力。

> **注意**：`compute_call_run_20x.bat` 使用 `start` 命令在后台启动，不会阻塞主命令行。如果想观察单个客户端的输出，可以手动运行一个 `compute_call.exe`。

### 观察效果总结

1. **10 个节点窗口**：每个窗口都实时显示收到的 `"计算公式 X op Y"` 和 `"计算结果 Z"`，请求被负载均衡器均匀打散。
2. **20 个客户端窗口**：每个窗口持续发送请求并接收返回结果，形成持续不断的计算压力。
3. 若某个节点因故关闭，C4 网格会在数秒内感知并将其从路由表中剔除，剩余节点继续承载所有请求 —— 容错性一目了然。

---

## 6. 代码关键点解析

### 6.1 计算节点（`compute_node.lpr`）

```pascal
app := API_Create_APPHnd2('pas', 'pascal语言实现的api');
API_Reg_Call2(app, 'exp', 'exp("expression")', nil, do_exp_Call);
API_SetOption2('Wait_Ready', 'False');  // 部署模式：不等待所有客户端就绪
API_Reset_Prepare();
API_Prepare_Client2('ipc:compute_grid', app);
API_Prepare_Done();
```

- 应用名固定为 `'pas'`，所有节点共用此名，形成集群。
- `API_SetOption2('Wait_Ready', 'False')` 使得节点启动后立即就绪，不必等待其他客户端连接，适合大规模部署。
- 回调 `do_exp_Call` 使用 `Z.Expression` 引擎求值，通过 `EvaluateExpressionValue(tsC, exp)` 支持 C 风格表达式（加减乘除、括号等）。

### 6.2 客户端（`compute_call.lpr`）

```pascal
send_ := API_Create_DataHnd2('exp');
p := TPascalString(exp_).BuildUTF8AnsiChar(siz);
API_WriteBuffer(send_, p, siz);
TPascalString.FreeUTF8AnsiChar(p);
return_ := API_Call2('pas', send_, 1000);
```

- 调用应用名 `'pas'`，API 名 `'exp'`，超时 1000ms。
- 参数以 UTF‑8 字符串传递，返回值同样为 UTF‑8 字符串。
- 循环持续 60 秒，随机生成形如 `"123 + 456"` 的表达式。

### 6.3 服务注册中心（`compute_service.lpr`）

```pascal
API_Reset_Prepare();
API_Prepare_Service2('ipc:compute_grid', 'ipc:compute_grid');
if API_Prepare_Done() <> 1 then ...
```

- 此程序仅创建服务端点，不注册任何应用。它的存在使得后续的节点和客户端能够“找到”彼此，类似于 **ZooKeeper 的临时节点** 或 **etcd 的租约**。

---

## 7. 扩展与性能调优

### 7.1 增加节点数量

节点数量越多，集群总吞吐量越大。你可以修改 `compute_node_run_10x.bat` 中的循环次数，例如改为 50 或 100，启动更多节点。注意系统资源（CPU、内存）限制，IPC 通信非常轻量，通常可以支持数百个节点。

### 7.2 增加客户端数量

客户端数量代表并发请求压力。`compute_call_run_20x.bat` 可修改为更大数值。如果节点数不足，客户端可能会遇到超时（因为请求排队），此时增加节点即可缓解。

### 7.3 切换为 TCP 网络

若需跨机部署，只需将 IPC 地址改为 TCP 地址，例如：
- 服务端：`API_Prepare_Service2('0.0.0.0:9898', '127.0.0.1:9898')`
- 节点和客户端：`API_Prepare_Client2('127.0.0.1:9898', app)`（客户端第二个参数为 nil）

所有通信自动切换为 TCP，无需修改业务代码。这相当于从 **本地进程间通信** 升级为 **跨主机 RPC**，实现真正意义上的分布式。

### 7.4 调整超时时间

客户端 `API_Call` 的超时设为 1000ms，若表达式计算较复杂或网络延迟高，可适当增大（例如 3000ms）。

### 7.5 关闭调试日志

若需减少控制台输出以提高性能，可在 `compute_node` 中设置 `API_SetOption2('ConsoleOutput', 'False')`，或修改 `.ini` 配置文件。

---

## 8. 专业术语与设计模式

本 Demo 体现了多种经典的分布式系统设计理念：

- **服务网格（Service Mesh）**：C4 网格自动处理服务发现、负载均衡、健康检查，无需应用代码介入。
- **无状态 Worker（Stateless Worker）**：每个 `compute_node` 不保存任何会话状态，可随意增减。
- **水平扩展（Horizontal Scaling）**：通过增加节点线性提升吞吐量。
- **容错性（Fault Tolerance）**：节点崩溃后自动摘除，剩余节点继续服务。
- **客户端负载均衡（Client‑Side Load Balancing）**：由 C4 库在调用端直接决策路由，无中心化 LB 单点。
- **最终一致性（Eventual Consistency）**：节点注册/注销信息会在数秒内同步到全网。

这些特性使得本架构可适用于 **实时数据分析**、**科学计算**、**金融高频交易** 等对性能与可靠性要求极高的领域。

---

## 9. 注意事项

- **必须先编译**：不要跳过 `build.bat` 步骤直接运行。
- **回调线程安全**：`do_exp_Call` 运行在 C4 线程池中，请勿在其中调用 `API_Call` 或 `API_Notify`（会导致死锁）。
- **UTF‑8 编码**：所有字符串传递必须使用 UTF‑8，本例通过 `BuildUTF8AnsiChar` / `ReadUTF8AnsiChar` 正确处理。
- **资源释放**：`API_Free_DataHnd` 必须调用，防止内存泄漏。
- **服务注册中心先启动**：虽然 C4 支持自动重连，但推荐先启动 `compute_service`。

---

## 10. 总结

通过这三个简单的 Pascal 程序，你完整体验了基于 **zAPI** 和 **C4 服务网格** 的分布式计算架构：

- **自动服务发现**：节点注册后，客户端无需配置即可找到它们。
- **透明负载均衡**：多个节点自动分担请求，无需额外代码。
- **水平扩展能力**：通过增加节点和客户端，集群性能近乎线性提升。
- **实时可视化反馈**：打开 10 个节点窗口，每个窗口都在疯狂输出计算结果，请求被自动打散到各个窗口——这正是分布式计算最直观、最震撼的视觉呈现。

这套方案可直接应用于实际的微服务场景，例如将计算密集型任务（AI 推理、图像处理、金融计算）分散到多个工作节点，而调用方只需通过 `API_Call` 即可获得结果，完全隐藏了分布式复杂性。

现在，**先运行 `build.bat` 编译，然后启动你的计算网格**，亲眼见证 10 个窗口“此起彼伏”的计算反馈吧！🚀
