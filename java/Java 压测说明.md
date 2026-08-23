# Java 压测说明 —— 高并发场景下的性能验证

> 本文档详细介绍如何使用 Java 绑定提供的 `FuncClient` 对 API Hub 服务进行**真正并发**的性能压测，帮助你评估系统在负载下的延迟、吞吐量和稳定性。
>
> **版本：** 2.1（与 ZAPI 核心 v2.1 同步）

---

## 📌 1. 压测目标

- **验证 API Hub 在并发调用下的性能表现**（延迟分布、QPS）。  
- **对比不同 API 类型**（整数运算、字符串处理、数组操作）的耗时差异。  
- **为生产环境容量规划提供数据参考**（如选择 IPC 还是 TCP，线程池大小等）。  
- **v2.0 新增**：验证 `API_UnReg` 动态注销对性能的影响，以及 `API_SetOption` 运行时配置的调优效果。
- **v2.1 新增**：利用状态与检查 API（`checkMainThread`、`checkApp`、`getStatusNum`/`getStatus`/`postStatus`）在压测过程中实时监控框架状态、探测服务可用性、拉取和注入日志，辅助性能问题定位。

---

## 🧠 2. 压测原理

`FuncClient.java` 采用 **每个调用一个独立线程** 的并发模型：

- 对每个 API（共 13 个），启动 `TOTAL_CALLS` 个线程，每个线程执行一次远程调用。  
- 记录每个调用的**微秒级延迟**，收集所有数据后计算统计指标。  
- 所有调用**同时发起**，模拟高并发场景。  
- 客户端不暴露任何 API（纯消费端），只连接服务端。  
- 依赖底层库的**线程安全**特性，无需加锁串行化。  
- **v2.0 新增**：支持在压测过程中动态调整配置（通过 `API_SetOption`）和动态注销 API（通过 `API_UnReg`）。
- **v2.1 新增**：压测期间可定期调用 `getStatusNum()` / `getStatus()` 拉取库日志，或使用 `checkApp` 探测目标服务是否在线，避免因服务宕机导致大量超时。

---

## ⚙️ 3. 压测参数配置

在 `FuncClient.java` 顶部可调整以下常量：

```java
private static final int TOTAL_CALLS = 100;   // 每个 API 的总调用次数
private static final int TIMEOUT_MS = 5000;   // 单次调用超时（毫秒）
```

- **`TOTAL_CALLS`**：增大可得到更稳定的统计数据，但会增加压测时间。建议 100~1000。  
- **`TIMEOUT_MS`**：根据网络环境调整，IPC 通常 1000ms 足够，TCP 可设为 3000~5000ms。  
- 若需调整 JVM 堆内存或 GC 参数，可在启动脚本中添加 `-Xmx2g -Xms2g` 等。  
- **v2.0 新增**：可通过 `API_SetOption` 动态调整 IPC 线程池大小后再进行压测，对比性能差异。
- **v2.1 新增**：可在压测前后调用 `checkMainThread()` 确认框架主循环运行状态，确保压测环境就绪。

---

## ▶️ 4. 运行压测

### 4.1 启动服务端

在运行压测客户端之前，**必须启动对应的服务端**（`FuncServer`）：

```powershell
.\run_func_server.ps1
```

成功启动后，服务端会监听 `ipc:func_service` 和 `127.0.0.1:9899`。

### 4.2 运行压测客户端

**另开一个终端**，在 `java/` 目录下执行：

```powershell
.\run_func_client.ps1
```

客户端会自动连接服务端，进行预热（执行一次 `add` 调用），然后对每个 API 执行压测，最后输出统计表格。

### 4.3 输出示例

```
=== Java FuncClient – True Concurrent Performance Test ===
Threads per API: 100, total calls per API: 100
Times in milliseconds (ms), QPS = calls/sec

Connected to FuncService.
Warm-up done.

API                 Avg(ms)   Min(ms)   Max(ms) Median(ms) StdDev(ms)     Calls         QPS   Total(s)
----------------------------------------------------------------------------------------------------------------------
add                  1.234     0.987     2.345     1.200     0.321        100      1234.56     0.081
subtract             1.123     0.876     2.111     1.100     0.298        100      1234.56     0.081
multiply             1.456     1.023     2.678     1.400     0.412        100      1234.56     0.081
divide               1.789     1.234     3.456     1.700     0.567        100      1234.56     0.081
to_upper             1.567     1.111     2.890     1.500     0.456        100      1234.56     0.081
to_lower             1.543     1.098     2.765     1.480     0.432        100      1234.56     0.081
reverse              1.678     1.234     3.012     1.600     0.521        100      1234.56     0.081
get_time             1.234     0.987     2.345     1.200     0.321        100      1234.56     0.081
get_random           1.345     1.012     2.567     1.300     0.389        100      1234.56     0.081
echo                 1.234     0.987     2.345     1.200     0.321        100      1234.56     0.081
sum_array            2.345     1.567     4.567     2.200     0.789        100      1234.56     0.081
concat_strings       2.678     1.789     5.123     2.500     0.890        100      1234.56     0.081
sha3                 8.901     6.789    12.345     8.500     1.234        100      1234.56     0.081
```

> **注意**：实际数值取决于硬件、网络、负载等。上述仅为示意。  
> 这些状态日志由库自动输出到控制台，也可通过 `getStatusNum()` / `getStatus()` 程序化拉取。

---

## 📊 5. 结果解读

| 列名        | 含义                                                                 |
| ----------- | -------------------------------------------------------------------- |
| **API**     | 被测试的 API 名称                                                     |
| **Avg(ms)** | 平均延迟（毫秒）                                                      |
| **Min(ms)** | 最小延迟（毫秒）                                                      |
| **Max(ms)** | 最大延迟（毫秒）                                                      |
| **Median(ms)** | 中位数延迟（毫秒）——更接近典型值，不受极端值影响                      |
| **StdDev(ms)** | 标准差——反映延迟波动程度，越小越稳定                                  |
| **Calls**   | 实际完成的调用次数（可能因超时失败而小于 `TOTAL_CALLS`）              |
| **QPS**     | 每秒查询数（吞吐量），计算公式：`Calls / Total(s)`                    |
| **Total(s)** | 从发起所有调用到全部完成的总耗时（秒）                                |

**重点关注**：
- **Avg 与 Median 的差距**：若 Avg 远大于 Median，说明存在长尾延迟（可能有慢调用）。
- **StdDev**：过大表示性能不稳定，需排查网络或服务端负载。
- **QPS**：评估系统承载能力，可根据此值规划部署规模。

---

## 🛠️ 6. 调整压测强度

### 6.1 修改调用次数

直接修改 `TOTAL_CALLS`。例如改为 1000：

```java
private static final int TOTAL_CALLS = 1000;
```

### 6.2 切换协议

默认连接 `ipc:func_service`，也可改用 TCP（修改 `prepareClient` 地址）：

```java
ApiHub.prepareClient("127.0.0.1:9899", null);
```

同时确保服务端也监听该地址（`FuncServer` 已监听 `0.0.0.0` 并公布 `127.0.0.1:9899`）。

### 6.3 增加 JVM 资源

若 `TOTAL_CALLS` 很大（如 >5000），可能耗尽线程资源或内存，可调整 JVM 参数：

- 增加堆内存：`-Xmx4g -Xms4g`  
- 增加线程栈大小（如需）：`-Xss2m`  
- 启用 G1GC：`-XX:+UseG1GC`

修改 `run_func_client.ps1` 中的 `java` 命令，例如：

```powershell
java -Xmx4g -Xms4g -cp "$JNA_JAR;$OUT_DIR" demo.FuncClient
```

### 6.4 预热与稳定性

- 代码已包含一次预热调用（`add`），消除 JIT 编译影响。  
- 若需多次预热，可循环调用 `func_add` 若干次。  
- 建议在稳定环境下多次运行，取平均值。

### 6.5 v2.0 新增：动态配置调优压测

可以在压测过程中使用 `API_SetOption` 动态调整配置，对比不同配置下的性能差异：

```java
// 在压测前调整 IPC 线程池大小
ApiHub.setOption("IPC_Serv_ThreadCount", "8");

// 或调整等待连接行为
ApiHub.setOption("Wait_Connection_ReadyOk", "False");

// 然后进行压测...
```

### 6.6 v2.1 新增：状态监控辅助调优

在压测过程中，可启动一个独立线程定期拉取库日志，用于监控是否有异常或错误信息：

```java
new Thread(() -> {
    while (!Thread.currentThread().isInterrupted()) {
        while (ApiHub.getStatusNum() > 0) {
            String msg = ApiHub.getStatus();
            System.err.println("[监控] " + msg); // 或写入文件
        }
        Thread.sleep(100);
    }
}).start();
```

也可在压测前使用 `checkApp("FuncService")` 确认服务已注册，避免因服务未启动导致全部调用失败。

---

## ⚠️ 7. 注意事项

1. **服务端必须先启动**，否则客户端会连接失败。可使用 `checkApp("FuncService")` 提前验证。  
2. **确保动态库路径正确**：脚本已设置 `PATH`，若手动运行需确保 `z_api_hub64.dll` 可被找到。  
3. **避免在压测期间进行其他高负载操作**（如大文件读写、编译等），以免干扰结果。  
4. **超时设置**：若 `TOTAL_CALLS` 很大，网络拥塞可能导致部分调用超时，返回空句柄。此时 `Calls` 会小于 `TOTAL_CALLS`，可适当增加 `TIMEOUT_MS`。  
5. **线程数等于调用次数**：每个调用一个线程，对于 `TOTAL_CALLS=1000`，会创建 1000 个线程，系统资源消耗较大。可根据实际情况调整并发度（如使用线程池限制并发数），但本示例为了体现"真正并发"而采用此设计。  
6. **结果受环境影响**：不同硬件、操作系统、网络协议（IPC vs TCP）结果差异明显，请基于实际部署环境测试。  
7. **v2.0 新增**：如果压测过程中需要热卸载某个 API，可使用 `API_UnReg` 观察其对系统的影响。  
8. **v2.1 新增**：压测过程中若发现大量超时，可使用 `checkMainThread()` 检查框架主线程是否正常，或使用 `getStatusNum()` 拉取日志查看具体错误信息。

---

## 🐛 8. 常见问题

### Q1：压测时报 `OutOfMemoryError: unable to create new native thread`
- **原因**：`TOTAL_CALLS` 过大，系统无法创建这么多线程。  
- **解决**：减小 `TOTAL_CALLS`，或改用固定线程池（如 `Executors.newFixedThreadPool(100)`）并分批执行。

### Q2：部分 API 延迟特别高（如 `sha3`）
- **原因**：SHA3 哈希计算较耗 CPU，服务端处理慢。  
- **解决**：这是正常现象，表明 CPU 密集型操作会影响响应时间。可考虑将此类操作异步化或增加服务端实例。

### Q3：QPS 与预期不符
- **排查**：
  - 检查服务端是否有瓶颈（CPU、内存、网络）。  
  - 确认是否使用了 IPC（比 TCP 快很多）。  
  - 检查控制台输出或使用 `getStatus()` 拉取日志，查看是否有错误信息。  
  - 尝试减小 `TOTAL_CALLS` 排除线程创建开销的影响。  
  - 尝试使用 `API_SetOption` 调整 IPC 线程池大小。
  - 使用 `checkApp("FuncService")` 确认服务端已正常注册。

### Q4：压测过程中客户端或服务端崩溃
- **原因**：可能是动态库版本不匹配、内存泄漏或线程冲突。  
- **解决**：确保使用最新稳定版本的 API Hub 动态库；检查代码中句柄是否正确释放（`try-with-resources`）；增加 JVM 堆内存；使用 `getStatusNum()` / `getStatus()` 查看崩溃前的日志信息。

### Q5：v2.0 动态注销是否影响压测？
- **解答**：`API_UnReg` 触发网络广播（约 3 秒），在此期间可能有轻微性能波动，属于正常现象。压测时应避免在压测过程中频繁注销 API。

### Q6：如何确认压测环境已就绪？
- **解答**：压测前可调用 `checkMainThread()` 确认框架主线程运行，调用 `checkApp("FuncService")` 确认目标服务在线，确保环境正常。

---

## 📈 9. 扩展：自定义压测

你可以基于 `FuncClient` 的框架，添加自己的 API 压测：

1. 在 `actions` Map 中添加新的条目，定义 `Callable<Void>`。  
2. 确保对应的服务端已注册该 API。  
3. 重新编译运行即可。

例如，测试一个 `echo` 大字符串的 API：

```java
actions.put("echo_large", () -> {
    try (DataHandle p = new DataHandle("echo_large")) {
        p.writeStringNullTerminated("x".repeat(1024)); // 1KB 字符串
        try (DataHandle r = ApiHub.call("FuncService", p, TIMEOUT_MS)) {
            r.readStringNullTerminated();
        }
    }
    return null;
});
```

> **跨语言字符串提醒**：使用 `writeStringNullTerminated` / `readStringNullTerminated` 确保与其他语言（C++/Python/Go/Pascal）兼容。

---

## 📝 10. 总结

通过 `FuncClient` 压测，你可以获得 API Hub 在真实并发下的性能画像，从而指导架构决策和容量规划。结合延迟分布和 QPS，你能够：

- 判断是否满足业务 SLA。  
- 对比不同协议（IPC vs TCP）的性能差异。  
- 识别慢 API 并针对性优化（如缓存、异步处理）。  
- 为集群扩容提供依据。  
- **v2.0 新增**：验证动态配置（`API_SetOption`）对性能的影响，评估热卸载（`API_UnReg`）的场景适用性。
- **v2.1 新增**：利用状态与检查 API 实现压测过程中的实时监控和问题定位，提升压测效率。

现在就开始你的压测吧！如果遇到任何问题，请检查控制台输出或使用 `getStatus()` 拉取日志——它们是最好的"诊断工具"。

---

*[返回 Java 使用指南](./API%20Hub%20Java%20使用指南.md)*  
*[项目源码](https://github.com/PassByYou888/zAPI)*

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
