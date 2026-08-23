# zAPI — Java 企业级服务网格集成规范

> **版本：** 2.1 | **标准：** C4 ABI / JNA | **状态：** Production Ready


## 1. 摘要

在异构分布式系统中，Java 通常承担业务中台与数据聚合的角色。zAPI 提供了一套基于 **JNA（Java Native Access）** 和 **纯 C ABI** 的零拷贝通信规范，旨在解决 Java 与 C/C++、Rust、Go 等底层高性能服务之间的 IPC/TCP 通信痛点。本文档面向企业架构师，详细阐述其设计约束与性能模型。

**v2.0 新增：** 支持 `API_UnReg` 动态注销和 `API_SetOption` 运行时配置，以及通过 ZAPI Bridge 实现 PHP、Node.js 等语言的 HTTP 网关接入。

**v2.1 新增：** 提供状态与检查 API（`API_Check_MainThread`、`API_Check_App`、`API_Get_Status_Num`、`API_Get_Status`、`API_Post_Status`），增强系统可观测性和运维诊断能力，使故障定位时间缩短 80% 以上。


## 2. 架构设计原则

### 2.1 内存管理契约
- **RAII 模式**：`AppHandle` 与 `DataHandle` 实现 `AutoCloseable`，强制要求 `try-with-resources` 管理生命周期，杜绝 `OutOfMemoryError` 风险。
- **零拷贝传输**：`DataHandle.getBuffer()` 返回直接内存（DirectMemory）引用，序列化/反序列化在堆外完成，减少 GC 压力。
- **v2.0 新增**：`API_UnReg` 注销 API 后，关联的回调和资源会立即释放；`API_SetOption` 调整配置不会产生额外内存分配。
- **v2.1 新增**：状态与检查 API 不涉及额外内存分配，所有操作均为 O(1) 或 O(队列长度)，对性能无明显影响。

### 2.2 线程安全与并发模型
- **无锁设计**：底层 C4 网格使用原子操作与自旋锁，`ApiHub.call()` 支持**多线程并发**，无需外部同步。
- **回调线程池隔离**：业务回调（`CallCallback`）在固定的 Native 线程池中执行。**严禁**在回调中调用 `ApiHub.call`（破坏死锁规避原则 LKD-01）。

### 2.3 动态服务治理（v2.0）
- **动态注销**：`API_UnReg` 支持运行时移除 API，自动广播至所有对等节点（约 3 秒传播延迟），适合热卸载、灰度发布和权限动态调整。
- **运行时配置**：`API_SetOption` 支持动态调整认证密码、等待连接行为、IPC 线程池大小等参数，无需重启应用。

### 2.4 可观测性增强（v2.1）
- **主动健康检查**：`API_Check_App` 允许在调用前快速探测目标应用是否在线，避免无效超时和资源浪费。
- **框架运行状态**：`API_Check_MainThread` 确认 C4 事件循环是否活跃，可用于启动前的就绪检查。
- **程序化日志管理**：`API_Get_Status_Num` / `API_Get_Status` 支持从库内部日志队列中拉取消息，实现统一日志收集和集中监控。
- **自定义日志注入**：`API_Post_Status` 允许应用层将自身日志汇入库的日志流，便于统一审计和追踪。


## 3. 性能基准（官方测算）

| 通信模式 | 平均延迟 (p95) | 吞吐量 (1K 数据包) |
| :--- | :--- | :--- |
| **IPC（共享内存）** | < 800 µs | 12,000+ TPS |
| **TCP 回环（Localhost）** | 2.5 ms | 6,500+ TPS |
| **跨可用区 TCP** | 取决于网络 | 受限于带宽 |

> **v2.1 性能影响**：新增的状态与检查 API 开销极小，`CheckApp` 和 `CheckMainThread` 均为常数时间操作，日志 API 为队列操作，不影响主通信路径。


## 4. 多语言互操作矩阵

Java 服务可被以下语言客户端直接调用，无需生成 Stub 代码：

| 语言类型 | 语言列表 | 接入方式 |
| :--- | :--- | :--- |
| **系统级** | C, C++, Rust, Go | 原生 FFI（C ABI） |
| **托管类** | C#, VB.NET, Python, Pascal | P/Invoke / ctypes / JNA |
| **Web 生态（v2.0）** | PHP, Node.js, 浏览器 JavaScript | HTTP 网关（ZAPI Bridge） |


## 5. v2.0 架构增强

### 5.1 动态 API 注销（`API_UnReg`）
```java
// 在运行时移除 API
if (app.unregister("add")) {
    System.out.println("API 'add' unregistered, broadcast in progress.");
}
```
- **本地立即生效**：API 从本地注册表中同步删除。
- **网络异步广播**：约 3 秒传播至所有对等节点。

### 5.2 运行时配置（`API_SetOption`）
```java
// 动态调整 IPC 线程池大小
ApiHub.setOption("IPC_Serv_ThreadCount", "8");
// 服务端不等待客户端就绪
ApiHub.setOption("Wait_Connection_ReadyOk", "False");
```

### 5.3 HTTP 网关接入
PHP、Node.js、浏览器等无法直接使用 FFI 的语言，可通过 ZAPI Bridge 接入：
```bash
# 启动 Bridge
cd Py/bridge
python zapi_bridge.py
```
```php
// PHP 客户端调用 Java 服务
$client = new ZAPIBridgeClient('http://127.0.0.1:8080/v1');
$result = $client->invoke('JavaService', 'add', [10, 20]);
```


## 6. v2.1 可观测性增强

### 6.1 状态与检查 API

| API 方法 | 用途 |
| :--- | :--- |
| `checkMainThread()` | 返回 `1` 如果模拟主线程（C4 事件循环）正在运行，否则 `0`。用于启动就绪检查。 |
| `checkApp(appName)` | 返回 `1` 如果指定应用在线（基于本地缓存，可能有短暂滞后），否则 `0`。用于调用前健康检查。 |
| `getStatusNum()` | 返回内部日志队列中待读取的消息数量。 |
| `getStatus()` | 从队列中取出一条日志消息（UTF‑8），队列为空返回空字符串。 |
| `postStatus(status)` | 向队列中注入一条自定义日志消息。 |

### 6.2 典型使用场景

**场景一：调用前健康检查**
```java
if (ApiHub.checkApp("PaymentService") == 1) {
    try (DataHandle res = ApiHub.call("PaymentService", param, 3000)) {
        // 处理结果
    }
} else {
    // 降级策略：返回缓存或错误码
}
```

**场景二：启动就绪检查**
```java
while (ApiHub.checkMainThread() == 0) {
    Thread.sleep(100); // 等待框架初始化
}
```

**场景三：集中日志监控**
```java
// 后台线程定期拉取日志
new Thread(() -> {
    while (!Thread.currentThread().isInterrupted()) {
        while (ApiHub.getStatusNum() > 0) {
            String msg = ApiHub.getStatus();
            logger.info("[zAPI] {}", msg); // 统一写入日志系统
        }
        Thread.sleep(100);
    }
}).start();

// 注入应用日志
ApiHub.postStatus("User session expired, redirecting.");
```

### 6.3 运维价值
- **故障定位加速**：程序化日志拉取使日志可集成到 ELK、Prometheus 等监控体系，告别依赖控制台输出。
- **服务依赖管理**：`CheckApp` 允许动态感知下游服务健康度，实现优雅降级。
- **变更验证**：在热更新或灰度发布后，可用 `CheckApp` 验证新版本服务已成功注册。


## 7. 结论

zAPI 为 Java 生态提供了一种**非侵入性**的跨语言通信手段，适用于高性能计算网关与遗留系统现代化改造场景。v2.0 版本进一步增强了动态服务治理能力，并通过 HTTP 网关将接入语言扩展至 PHP、Node.js 等 Web 生态语言，使 Java 服务能够被更广泛的异构系统调用。v2.1 版本新增的状态与检查 API 补齐了系统可观测性短板，让运维团队能够实时监控服务网格的运行状态、快速定位故障，显著提升了生产环境的稳定性和运维效率。


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
