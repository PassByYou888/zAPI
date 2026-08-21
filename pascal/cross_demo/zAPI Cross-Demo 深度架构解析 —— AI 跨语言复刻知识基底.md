# zAPI Cross-Demo 深度架构解析 —— AI 跨语言复刻知识基底

> **文档性质**：本文档是为 AI 模型（大语言模型）编写的“理解蓝图”，旨在让 AI 在阅读后能够准确理解 zAPI 分布式服务网格的核心机制，并具备将 `cross_service` / `cross_node` / `cross_call` 这套 Pascal 示例**等价移植到任意其他编程语言**的能力。
>
> **核心原则**：所有语言绑定（Go、Python、C#、Rust、Java 等）底层调用的是**同一套 C ABI 动态库**（`z_api_hub64.dll` / `libz_api_hub.so`），因此跨语言复刻的本质是 **FFI 调用序列的等价翻译**，而非重新实现。

---

## 一、功能定义：Cross-Demo 是什么

`cross_service`、`cross_node`、`cross_call` 三个程序共同构成了一个 **基于 IPC（进程间通信）的分布式服务网格的最小可行产品（MVP）**。它演示了：

| 组件 | 角色 | 核心职责 |
|------|------|----------|
| `cross_service` | 服务注册中心（信标） | 创建 IPC 端点，作为 C4 服务网格的控制平面，不注册任何业务 API |
| `cross_node` | 无状态工作节点（Worker） | 注册应用 `'demo'`，暴露 `'add'` 和 `'inv_seri'` 两个 Call API，接受远程请求 |
| `cross_call` | 客户端（Consumer） | 连接到同一 IPC 端点，发起远程调用，模拟持续负载 |

**三者共同完成的本质动作**：通过共享的 IPC 通道 `ipc:cross`，将不同进程的代码（Pascal 函数）暴露为可被网络调用的远程过程，并利用 C4 网格实现自动负载均衡。

---

## 二、核心执行流程（控制流）

### 2.1 服务启动流程（顺序敏感）
```
1. cross_service 启动：
   API_Reset_Prepare()       → 清空之前配置
   API_Prepare_Service('ipc:cross', 'ipc:cross') → 绑定 IPC 命名管道
   API_Prepare_Done()        → 阻塞直到监听就绪，返回 1 表示成功

2. cross_node 启动（可多个）：
   API_Create_APPHnd('demo', '...') → 创建应用句柄（内存对象）
   API_Reg_Call(app, 'add', ...)    → 将 Pascal 函数注册到应用
   API_Reg_Call(app, 'inv_seri', ...)
   API_SetOption('Wait_Ready', 'False') → ⚠️ 部署模式开关
   API_Reset_Prepare()
   API_Prepare_Client('ipc:cross', app) → 连接服务端点，同时将 app 暴露给网格
   API_Prepare_Done()          → 阻塞直到连接建立并完成注册

3. cross_call 启动（可多个）：
   API_Reset_Prepare()
   API_Prepare_Client('ipc:cross', nil) → 连接服务端点，不暴露任何 API（纯消费者）
   API_Prepare_Done()
```

### 2.2 远程调用流程（单次 RPC 的事务全景）
```
客户端（cross_call）：
  ① send_ = API_Create_DataHnd('add')      → 创建数据句柄，绑定 API 名称
  ② API_WriteInt32(send_, a)               → 写入第一个参数（追加到缓冲区）
  ③ API_WriteInt32(send_, b)               → 写入第二个参数（位置自动后移）
  ④ return_ = API_Call('demo', send_, 1000) → 同步调用，超时 1000ms
     ├─ 底层：序列化 DataHnd（API名 + 载荷）→ 通过 C4 网格路由 → 选取负载最低的节点
     ├─ 节点：回调函数 do_add_Call 在后台线程池执行
     │  ├─ a = API_ReadInt32(Input)         → 按顺序读取第一个整数
     │  ├─ b = API_ReadInt32(Input)         → 按顺序读取第二个整数
     │  ├─ c = a + b                        → 业务计算
     │  └─ API_WriteInt32(Output, c)        → 写入结果
     └─ 返回：客户端收到结果句柄
  ⑤ result = API_ReadInt32(return_)         → 读取结果
  ⑥ API_Free_DataHnd(send_); API_Free_DataHnd(return_) → 必须释放，防止内存泄漏
```

---

## 三、ZAPI 机制深度剖析（AI 复刻的核心知识）

### 3.1 寻址三要素（跨语言路由的基石）

| 层级 | 标识符 | 作用域 | 对应代码中的值 |
|------|--------|--------|----------------|
| **网络端点** | `PhysicsAddr_` | 操作系统级（IPC/TCP 地址） | `'ipc:cross'`（所有进程共享） |
| **应用名（AppName）** | 字符串 | C4 网格级（逻辑服务池） | `'demo'`（节点注册，客户端调用） |
| **API 名（APIName）** | 字符串 | 应用级（单个进程内唯一） | `'add'`、`'inv_seri'` |

**调用寻址路径**：`API_Call('demo', ...)` → C4 网格查找所有注册了 `'demo'` 的节点 → 负载均衡选一个 → 在该节点内查找 `'add'` 回调 → 执行。

### 3.2 服务发现与负载均衡机制（内置，零代码）

- **自动注册**：`API_Prepare_Client('ipc:cross', app)` 传入非 `nil` 的 `app` 句柄时，库内部自动将 `app` 的所有 API 广播到网格。
- **自动摘除**：节点进程退出或 `API_Free_APPHnd` 调用后，C4 在约 3 秒内感知并更新路由表。
- **负载均衡策略**：基于各节点的**当前活跃请求数**和**线程池负载**（而非轮询），将新请求发送给最空闲的节点。
- **对业务代码透明**：客户端完全不知道背后有多少节点，每次调用都像调用本地单例一样。

### 3.3 二进制序列化协议（跨语言互通的唯一契约）

**这是所有语言绑定必须严格遵循的核心协议。**

`TDataHnd` 内部是一个**连续字节缓冲区**，写入顺序（客户端）和读取顺序（服务端）**必须完全一致**，且**类型必须匹配**。

`inv_seri` API 是此协议的教科书演示：

**客户端写入顺序**：
```
API_WriteUInt8(send_, 200)      → 1 字节 (0xC8)
API_WriteUInt16(send_, $10)     → 2 字节 (0x10, 0x00) 小端序
API_WriteUInt32(send_, $2F)     → 4 字节 (0x2F, 0x00, 0x00, 0x00)
API_WriteUInt64(send_, $3F)     → 8 字节 (0x3F, 0x00, ...)
API_WriteString(send_, 'hello world') → 4字节长度 + UTF-8字节序列
API_WriteSingle(send_, 3.14)    → 4 字节 IEEE 754
```

**服务端读取顺序（必须完全镜像）**：
```
b   := API_ReadUInt8(Input)     → 1 字节
w   := API_ReadUInt16(Input)    → 2 字节
c   := API_ReadUInt32(Input)    → 4 字节
u64 := API_ReadUInt64(Input)    → 8 字节
s   := API_ReadString(Input)    → 长度前缀 + UTF-8
f   := API_ReadSingle(Input)    → 4 字节
```

**服务端反向写入（`inv_seri` 特色）**：
```
API_WriteSingle(Output, f)      → 先写 float
API_WriteString(Output, s)      → 再写 string
API_WriteUInt64(Output, u64)    → 再写 uint64
...（逆序）
```
这验证了：**读/写位置由 API 函数自动推进，无字段名标签，纯位置依赖**。这就是为什么跨语言调用时，双方必须使用同一份“数据布局协议”。

**关键约束**：
- 所有多字节数值使用**小端序（Little-Endian）**。
- 字符串以 **4 字节长度前缀（UInt32）+ UTF-8 字节** 传输。
- 布尔值以 **1 字节（0/1）** 存储。

### 3.4 线程模型与回调死锁红线（⚠️ 最高优先级）

**导出函数（`API_Call`、`API_WriteBuffer` 等）**：完全线程安全，可在任意线程并发调用。

**回调函数（如 `do_add_Call`）**：
- **执行线程**：由 zAPI 库内部的 **C 级线程池** 调度，**不是**调用 `API_Call` 的线程。
- **AI 复刻时必须遵守的铁律**：
  - ❌ **禁止**在回调中调用 `API_Call` 或 `API_Notify` → 会导致死锁（回调线程可能持有内部锁，而 `API_Call` 需要获取同一锁）。
  - ❌ **禁止**在回调中执行长时间阻塞操作（`Sleep`、等待事件、重型循环）。
  - ❌ **禁止**在回调中直接操作 UI。
  - ✅ **推荐**：回调只做快速数据读写（微秒级），耗时任务通过消息队列交给应用层线程池。

### 3.5 `Wait_Ready` 部署模式（运维关键）

`API_SetOption('Wait_Connection_ReadyOk', 'False')`（在代码中简写为 `'Wait_Ready'`）：

| 设置 | `API_Prepare_Done` 行为 | 适用场景 |
|------|-------------------------|----------|
| `True`（默认） | 阻塞等待所有已准备的客户端连接成功并完成应用注册，超时后返回失败 | 传统同步部署，所有节点必须同时就绪 |
| `False` | 立即返回，**不等待客户端连接**。客户端会自动重连，直到服务出现 | 弹性部署（如 Kubernetes），允许节点先于服务启动 |

`cross_node` 使用 `False`，这意味着即使 `cross_service` 尚未启动，节点也能先行运行，等 `cross_service` 上线后自动接入。这是**零停机扩容**和**无序启动**的基石。

---

## 四、AI 跨语言复刻检查清单

当您需要将 Cross-Demo 移植到目标语言（Go、Python、Rust、C#、Java 等）时，请确保**按此清单实现等价语义**：

### 4.1 动态库加载
- [ ] 实现平台自适应的动态库加载（Windows: `z_api_hub64.dll`，Linux: `libz_api_hub.so`，macOS: `libz_api_hub.dylib`）。
- [ ] 所有 C 函数指针必须正确解析（`API_Create_DataHnd`、`API_WriteInt32`、`API_Call`、`API_Free_DataHnd` 等约 20 个函数）。

### 4.2 数据句柄（DataHnd）RAII 封装
- [ ] 创建句柄时绑定 API 名称（`API_Create_DataHnd`）。
- [ ] 提供类型化写入方法：`WriteUInt8`、`WriteUInt16`、`WriteUInt32`、`WriteUInt64`、`WriteString`（UTF-8）、`WriteSingle`、`WriteDouble`、`WriteInt32` 等。
- [ ] 提供类型化读取方法，**顺序与写入严格对应**。
- [ ] 确保每个 `Create` 都有对应的 `Free`（使用 `defer`/`try-finally`/`using` 等 RAII 惯用法）。

### 4.3 应用句柄（AppHnd）与回调注册
- [ ] 创建应用（`API_Create_APPHnd`），指定唯一应用名（如 `'demo'`）。
- [ ] 注册 Call 回调（`API_Reg_Call`），回调签名必须遵循 C ABI 约束：
  - 参数为 `(trigger: void*, input: DataHnd, output: DataHnd)`。
  - 使用 `cdecl` 或语言对应的 C 调用约定。
- [ ] 回调内部只做快速读写，不调用 `API_Call`，不阻塞。

### 4.4 网络准备与启动（必须严格按顺序）
- [ ] `API_Reset_Prepare()`（每次重新配置前调用）。
- [ ] 服务端（`cross_service`）：`API_Prepare_Service(addr, addr)`。
- [ ] 节点（`cross_node`）：`API_Prepare_Client(addr, app)`（传入应用句柄以暴露 API）。
- [ ] 客户端（`cross_call`）：`API_Prepare_Client(addr, null)`（纯消费）。
- [ ] `API_Prepare_Done()`（启动网格，阻塞直到就绪或超时）。

### 4.5 运行时配置（可选但推荐）
- [ ] `API_SetOption('Wait_Connection_ReadyOk', 'False')` 在 `Prepare_Done` 之前调用，以启用部署模式。

### 4.6 资源清理（防止泄漏）
- [ ] 退出前调用 `API_Exit_MainThread()`（停止事件循环）。
- [ ] 调用 `API_Free_APPHnd(app)`（释放应用句柄，自动注销 API）。
- [ ] 调用 `API_shutdown()`（关闭网络资源）。

### 4.7 并发客户端模拟（对应 `cross_call` 的 `Do_Compute`）
- [ ] 使用目标语言的原生线程/协程，循环调用 `add__` 和 `inv_seri_` 的封装函数。
- [ ] 每次调用构造新的 `DataHnd`，调用后立即释放。
- [ ] 设置运行时长（如 10 秒），观察负载均衡效果。

---

## 五、AI 移植时的常见陷阱

| 陷阱 | 说明 | 规避方法 |
|------|------|----------|
| **字符串编码** | C 层期望 **UTF-8 + 空终止符**，而各语言默认字符串编码不同（如 C# 为 UTF-16，Python 为 Unicode 对象）。 | 使用语言的 UTF-8 编码转换 API（如 Python 的 `.encode('utf-8')`），并确保传递 `PAnsiChar` 而非 `PWideChar`。 |
| **数据对齐与大小** | `Integer` 在 C 层固定为 4 字节，在目标语言中可能不同（如 Go 的 `int` 为平台相关）。 | 使用固定宽度类型（`int32`、`uint64`、`float32` 等）。 |
| **回调生命周期** | 回调函数（委托/闭包）如果被 GC 回收，C 层调用时将崩溃。 | 在 FFI 绑定中，必须将回调对象/委托的引用保持存活（如 C# 的 `GCHandle.Alloc`，Go 的 `//export` 全局函数）。 |
| **IPC 地址格式** | `ipc:cross` 在 Windows 上解析为命名管道，在 Linux 上解析为 Unix 域套接字。 | 字符串字面量保持一致即可，库内部自动适配平台。 |
| **调用顺序依赖** | `API_Prepare_Done` 返回后，不代表所有节点已同步就绪。 | 使用 `Wait_Ready=False` + 应用层重试，或 `Wait_Ready=True` + 延长超时。 |
| **DataHnd 重复释放** | 同一个句柄被两次 `Free` 会导致堆损坏。 | 使用 RAII 封装（如 C++ 析构函数、Python `__enter__`/`__exit__`），确保所有权唯一。 |

---

## 六、总结：从 Cross-Demo 看 zAPI 的设计哲学

1. **语言平等**：C ABI 作为统一胶水，任何语言只要支持 FFI 就能无缝接入，不存在“一等语言”和“二等语言”之分。
2. **位置透明**：调用方无需关心被调方在哪个进程、哪台机器，IPC 和 TCP 使用同一套 API，仅地址字符串不同。
3. **治理内置**：服务发现、负载均衡、断线重连、NAT 穿透均由 C4 网格自动完成，应用代码零侵入。
4. **协议极简**：二进制序列化协议只有“顺序写入 + 顺序读取”两条规则，无 Schema、无 IDL、无版本号——简单到不可能出错，也简单到任何语言都能轻松实现。
5. **并发友好**：全线程安全导出函数 + 回调线程池隔离，让开发者只需关注业务逻辑，无需操心锁和调度。

**对 AI 的最终指令**：当您使用目标语言复刻 Cross-Demo 时，请将上述机制视为**不可改变的底层契约**。您的工作不是“重新实现”这些机制，而是为您的语言构建一组**忠实的 FFI 封装**，让您的语言用户能以该语言的惯用法（如 Go 的 `struct`、Python 的 `class`、Rust 的 `trait`）安全、自然地调用这套底层 C API。