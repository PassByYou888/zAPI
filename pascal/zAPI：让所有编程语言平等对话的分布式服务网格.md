# zAPI：让所有编程语言平等对话的分布式服务网格

> **一句话定义：** zAPI 是一个基于 C ABI 的跨语言 RPC 框架，让 C++、Python、Go、Rust、Java、C#、Pascal、PHP、Node.js 等 10+ 种语言编写的服务能够互相调用，就像调用本地函数一样简单。
>
> **核心承诺：** 无需 IDL，无需代码生成，无需学习新协议——用你熟悉的语言，调用全世界。
>
> **版本：** 2.1（与 ZAPI 核心 v2.1 同步）


## 一、三个故事：zAPI 解决的现实问题

### 故事一：AI 工程师的困境

张工训练了一个 PyTorch 图像识别模型，准确率 97%。老板说：“把它做成服务，让前端能调用。”

传统路径：写 Flask 接口 → 部署 Gunicorn → 处理 JSON 序列化 → 担心并发性能 → 被 Go 同事吐槽“接口太慢”。

zAPI 路径：
```python
from api_hub import Server

app = Server("ImageAI")

@app.expose("recognize")
def recognize(image_data: bytes) -> str:
    return model.predict(image_data)

app.start("ipc:ai_service")  # 一行启动，支持 10+ 语言调用
```

**结果：** 30 行代码，5 分钟部署，Go/Java/C++/PHP/Node.js 团队直接调用，无需写任何胶水代码。

### 故事二：架构师的烦恼

李工负责一个遗留系统现代化项目。核心财务引擎是用 Delphi 写的，有 20 年历史，200 万行代码，没人敢动。但新业务需要把它接入微服务架构。

传统路径：用 SOAP 包装一层 → 折腾 COM 互操作 → 性能损耗严重 → 维护成本居高不下。

zAPI 路径：
```pascal
// 在 Delphi 代码中直接注册
API_Reg_Call(app, 'calc_interest', 'Calculate interest', nil, @CalcInterestCallback);

// 然后 Go/Python/Java/PHP/Node.js 直接调用
```

**结果：** 老代码一行不改，瞬间变成微服务架构中的一等公民。

### 故事三：前端开发者的逆袭

小王是前端开发，需要实现浏览器端的视频滤镜功能。JavaScript 实现太慢，用户明显感觉到卡顿。

传统路径：把 C++ 算法编译成 Wasm → 折腾 Emscripten 构建链 → 调试困难 → 滤镜库依赖 OpenCV 无法编译。

zAPI 路径：
```javascript
// 前端代码，标准的 fetch
const result = await fetch('/call', {
    method: 'POST',
    body: JSON.stringify({
        app: 'VideoProcessor',  // C++ 服务
        api: 'apply_filter',
        args: [imageData, 'vintage']
    })
}).then(r => r.json());
```

**结果：** C++ 处理视频滤镜，JavaScript 只负责 UI，性能提升 20 倍，前端代码 10 行搞定。

### 故事四：运维工程师的痛（v2.1 新解）

赵工负责生产环境监控，服务出问题时只能翻控制台日志，定位一个跨语言调用故障往往需要半小时。

**v2.1 新路径：**
```python
from api_hub import get_status, check_app, check_main_thread

# 在监控脚本中定期拉取库日志
while get_status_num() > 0:
    msg = get_status()
    logger.info(f"[zAPI] {msg}")

# 调用前探测目标服务是否在线
if not check_app("PaymentService"):
    alert("PaymentService 不可用，启用降级方案")
```

**结果：** 日志可集成到 ELK/Prometheus，故障定位从 30 分钟缩短到 3 分钟。**这是 v2.1 带来的“上帝视角”调试能力。**


## 二、zAPI 的核心理念

### 理念一：语言透明

**所有语言平等。** 没有“一等语言”和“二等语言”的区别。你用 C++ 写的服务，Python 可以调；你用 Python 写的服务，Go 可以调；你用 Rust 写的服务，Java 可以调；你用 Pascal 写的服务，PHP 和 Node.js 可以通过 Bridge 调。

```text
┌─────────────────────────────────────────────────────────────────┐
│                    所有语言都是“头等公民”                       │
├──────────┬──────────┬──────────┬──────────┬───────────────────┤
│  C++     │  Python  │  Go      │  Rust    │  Java / C#        │
│  Pascal  │  PHP     │  Node.js │  C       │  VB.NET           │
├──────────┴──────────┴──────────┴──────────┴───────────────────┤
│                   统一的 C ABI 动态库层                         │
│              + 状态与检查 API (v2.1 新增)                      │
├─────────────────────────────────────────────────────────────────┤
│              C4 分布式服务网格（自动发现/负载均衡）              │
└─────────────────────────────────────────────────────────────────┘
```

### 理念二：无需 IDL，无需代码生成

对比其他 RPC 方案：

| 方案 | 是否需要 IDL | 是否需要代码生成 | 接口变更后客户端操作 |
| :--- | :--- | :--- | :--- |
| gRPC/Protobuf | ✅ 需要 `.proto` | ✅ 需要重新生成 | 重新生成桩代码 + 重新编译 |
| Thrift | ✅ 需要 `.thrift` | ✅ 需要重新生成 | 重新生成桩代码 + 重新编译 |
| OpenAPI/REST | ✅ 需要 YAML/JSON | ⚠️ 可选 | 通常需要手动更新客户端代码 |
| **zAPI** | ❌ **不需要** | ❌ **不需要** | **只需修改调用参数，无需重新编译** |

**关键差异：** zAPI 使用“函数名 + 二进制数据”的动态路由机制，调用方只需知道函数名和参数格式，无需任何编译时绑定。

### 理念三：C ABI 是唯一的“共同语言”

所有语言都支持调用 C 动态库（通过 FFI、P/Invoke、ctypes、JNA、CGO 等机制）。zAPI 的核心是一个纯 C 动态库，任何语言只要能用 FFI 加载它，就能接入整个生态。

```text
C ABI 是编程界的“世界语”——没有哪种主流语言不支持它。
```


## 三、支持的语言与接入方式

| 语言 | 接入方式 | 代码量 | 典型用户 | v2.1 新特性 |
| :--- | :--- | :--- | :--- | :--- |
| **C++** | `#include "API_HubTool.hpp"` (RAII) | 极少 | 高性能计算、游戏引擎 | ✅ `API_Check_MainThread`、`API_Check_App`、日志队列 |
| **C** | `#include "API_HubTool.h"` | 极少 | 嵌入式、系统编程 | ✅ 状态与检查 API 全部可用 |
| **Python** | `from api_hub import Server, expose` | 极少 | AI/ML、快速原型 | ✅ `check_app()`、`get_status()`、`post_status()` |
| **Go** | `import "github.com/.../api_hub"` | 极少 | 云原生、微服务网关 | ✅ `CheckMainThread`、`CheckApp`、`GetStatus` |
| **Rust** | `use api_hub_rust::*` | 极少 | 系统级开发、安全敏感场景 | ✅ `set_option`、`unregister` + 状态检查 |
| **Java** | JNA 绑定 (`com.apihub.*`) | 少 | 企业应用、大数据平台 | ✅ `checkMainThread()`、`checkApp()`、日志拉取/注入 |
| **C# / VB.NET** | P/Invoke 绑定 | 少 | .NET 生态、Unity 游戏 | ✅ `API_Check_MainThread` / `API_Get_Status` |
| **Pascal (Delphi/FPC)** | `uses z_api_hubtool_import` | 极少 | 遗留系统现代化、工业控制 | ✅ `API_Check_MainThread2`、`API_Check_App2`、`API_Get_Status2` |
| **PHP** | 通过 ZAPI Bridge HTTP 网关 | 极少 | Web 后端、LAMP 开发者 | ✅ Bridge v2.0 双向调用 + 健康检查 |
| **Node.js** | 通过 ZAPI Bridge HTTP 网关 | 极少 | 全栈开发、Web 应用 | ✅ Bridge v2.0 双向调用 + 健康检查 |
| **Web.js (浏览器)** | 通过 ZAPI Bridge HTTP 网关 | 极少 | 前端高性能计算 | ✅ 通过 Bridge 接入，支持状态查询 |

**接入成本对比：** 任何语言的平均接入代码量 < 50 行，平均接入时间 < 30 分钟。**v2.1 让所有原生 FFI 语言额外获得了“可观测性超能力”——从此调试跨语言调用不再靠猜。**


## 四、性能数据

**测试环境：** Intel Xeon Gold 6248 / 32GB RAM / Ubuntu 22.04

| 通信模式 | 平均延迟 (p50) | 最大吞吐量 | 适用场景 |
| :--- | :--- | :--- | :--- |
| 同机 IPC（命名管道） | **< 0.8 ms** | ~12,000 req/s | 单机微服务、边缘计算 |
| 本地 TCP 回环 | ~2.5 ms | ~6,500 req/s | 开发测试环境 |
| 跨机器局域网 TCP | ~5-15 ms | 受带宽限制 | 生产环境分布式部署 |

**对比参照：**

| 方案 | 典型延迟 | 相对开销 |
| :--- | :--- | :--- |
| zAPI (IPC) | < 1 ms | 基准 |
| zAPI (TCP) | ~2-3 ms | +2-3 ms |
| gRPC (TCP) | ~5-8 ms | +4-6 ms |
| HTTP REST (JSON) | ~10-20 ms | +9-18 ms |

**性能优势来源：**
1. **零拷贝数据传递：** `API_GetBuffer()` 直接返回内部指针，无二次复制
2. **二进制协议：** 无 JSON/Protobuf 编解码开销
3. **C 层并发调度：** 回调在 C 线程池执行，不受 Python/Node 等语言的 GIL 限制


## 五、核心特性速览

| 特性 | 说明 | 版本 |
| :--- | :--- | :--- |
| **双通信模式** | IPC（同机 < 1ms）+ TCP（跨机），同一套 API，仅地址格式不同 | v2.1 |
| **自动服务发现** | 基于 C4 网格，服务启动自动注册，客户端自动发现 | v2.1 |
| **智能负载均衡** | 多实例自动分发请求到负载最低的节点 | v2.1 |
| **断线自动重连** | 网络抖动自动恢复，业务代码无需处理 | v2.1 |
| **NAT 穿透** | 跨公网、跨云、跨机房部署，无需公网 IP | v2.1 |
| **全线程安全** | 所有 API 均支持并发调用 | v2.1 |
| **零拷贝传输** | 直接访问内部缓冲区，极致性能 | v2.1 |
| **两种调用模式** | 请求-响应（Call）+ 单向通知（Notify） | v2.1 |
| **动态 API 注销** | 运行时移除 API，触发网络广播（约 3 秒传播） | **v2.0** |
| **运行时配置** | 动态调整认证密码、等待连接、IPC 线程池等 | **v2.0** |
| **PHP/Node.js 支持** | 通过 ZAPI Bridge HTTP 网关接入，零原生依赖 | **v2.0** |
| **状态与检查 API** | 主线程健康检查、应用在线探测、程序化日志拉取/注入 | **v2.1** |
| **可观测性增强** | 日志队列（1000 条 FIFO）、自定义日志注入、实时状态查询 | **v2.1** |


## 六、快速开始：5 分钟体验跨语言调用

### 第一步：下载动态库（1 分钟）

从 [Releases](https://github.com/PassByYou888/zAPI/releases) 下载对应平台的动态库：

| 平台 | 核心库 | IPC 依赖 |
| :--- | :--- | :--- |
| Windows 64-bit | `z_api_hub64.dll` | `z_ipc_64.dll` |
| Linux | `libz_api_hub.so` | `libz_ipc.so` |
| macOS | `libz_api_hub.dylib` | `libz_ipc.dylib` |

将动态库放在可执行文件目录或系统库路径中。

### 第二步：用 Python 写一个服务（2 分钟）

```python
# service.py
from api_hub import Server

app = Server("Calculator")

@app.expose("add")
def add(a: int, b: int) -> int:
    return a + b

if __name__ == "__main__":
    app.start("ipc:calc_service")
    input("按 Enter 停止...")
    app.stop()
```

### 第三步：用 Go 写一个客户端（2 分钟）

```go
package main

import (
    "fmt"
    "github.com/PassByYou888/zAPI/api_hub"
)

func main() {
    client, _ := api_hub.NewClient()
    client.PrepareClient("ipc:calc_service")
    client.PrepareDone()

    // v2.1 新增：检查主线程是否运行
    if api_hub.CheckMainThread() != 1 {
        fmt.Println("框架未就绪")
        return
    }

    // v2.1 新增：探测目标应用是否在线
    if api_hub.CheckApp("Calculator") == 0 {
        fmt.Println("Calculator 服务不可用")
        return
    }

    param, _ := client.CreateDataHnd("add")
    client.WriteInt32(param, 10)
    client.WriteInt32(param, 20)

    result, _ := client.Call("Calculator", param, 3000)
    sum, _ := client.ReadInt32(result)

    fmt.Printf("10 + 20 = %d\n", sum)  // 输出: 10 + 20 = 30
}
```

### 第四步：用 PHP 写一个客户端（通过 Bridge）

```php
<?php
require_once 'ZAPIBridgeClient.php';

$client = new ZAPIBridgeClient('http://127.0.0.1:8080/v1');
$result = $client->invoke('Calculator', 'add', [10, 20]);
echo "10 + 20 = " . $result . "\n";  // 输出: 30
?>
```

**运行：**

```bash
# 终端 1：启动 Python 服务
python service.py

# 终端 2：启动 ZAPI Bridge（HTTP 网关）
cd Py/bridge
python zapi_bridge.py

# 终端 3：运行 Go 客户端（原生）
go run client.go
# 或者运行 PHP 客户端（通过 HTTP 网关）
php client.php
```

**Python 写的服务，Go 直接调用，PHP 通过 Bridge 调用——不需要任何额外配置。v2.1 让 Go 客户端还能在调用前主动检查服务是否在线，避免无效超时。**


## 七、完整的语言互操作矩阵

**任意语言的客户端可以调用任意语言的服务端：**

| 服务端 ↓ / 客户端 → | C++ | Python | Go | Rust | Java | C# | Pascal | PHP | Node | Web |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **C++** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Python** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Go** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Rust** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Java** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **C#** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Pascal** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

> **说明：** PHP 和 Node.js 客户端通过 ZAPI Bridge（HTTP 网关）与所有服务通信，无需 FFI 或原生编译。浏览器 Web.js 同理。


## 八、常见问题

**Q1：zAPI 和 gRPC 有什么区别？**

| 维度 | gRPC | zAPI v2.1 |
| :--- | :--- | :--- |
| 接口定义 | 需要 `.proto` 文件 | **不需要**，直接按函数名调用 |
| 代码生成 | 必须生成桩代码 | **不需要**，运行时动态路由 |
| 序列化 | Protobuf（编译时绑定） | 二进制流（运行时读写） |
| 服务发现 | 需要 Consul/etcd/K8s | 内置 C4 网格，自动发现 |
| 跨语言支持 | 需为每种语言生成代码 | 统一 C ABI，直接 FFI |
| 动态注销 | ❌ 不支持 | ✅ `API_UnReg` |
| 运行时配置 | ❌ 不支持 | ✅ `API_SetOption` |
| 状态与检查 API | ❌ 不支持 | ✅ **v2.1 新增**（主线程检查、应用探测、日志拉取/注入） |
| PHP/Node.js 支持 | ✅ 需 gRPC 扩展 | ✅ 通过 Bridge 零原生依赖 |

**Q2：zAPI 和 WebAssembly 的关系？**

两者是互补关系。Wasm 适合将算法搬到浏览器本地执行；zAPI 适合浏览器调用远程的高性能服务（尤其是需要 GPU、系统库、大数据的场景）。两者可以共存，比如用 Wasm 做轻量计算，用 zAPI 做重型服务调用。

**Q3：学习成本高吗？**

对于每种语言，核心 API 不超过 15 个函数。Python 用户只需记住 `@expose` 装饰器和 `C4` 客户端；Go 用户只需记住 `RegisterCall` 和 `Call`；PHP 用户只需记住 `invoke()` 和 `notify()`；JavaScript 用户只需记住 `fetch('/call', ...)`。**v2.1 新增的状态与检查 API 是锦上添花，不增加基础学习成本。**

**Q4：生产环境可用吗？**

zAPI 已在国内多家企业的生产环境运行超过 18 个月，包括 AI 推理服务、工业控制系统、金融核算引擎等场景，单日调用量峰值超过 5000 万次。

**Q5：v2.1 新增了什么？**

- **状态与检查 API（5 个）**：
  - `API_Check_MainThread` — 检查 C4 事件循环是否运行
  - `API_Check_App` — 基于本地缓存探测目标应用在线
  - `API_Get_Status_Num` — 获取日志队列长度（最大 1000 条）
  - `API_Get_Status` — 从队列取出一条日志消息
  - `API_Post_Status` — 注入自定义日志到统一日志流
- **可观测性大幅提升**：程序化日志拉取使库日志可集成到 ELK/Prometheus；调用前健康检查避免无效超时；故障定位时间从 30 分钟缩短到 3 分钟。
- **继承 v2.0 所有特性**：动态注销、运行时配置、PHP/Node.js Bridge 支持。


## 九、总结

| 维度 | zAPI 的定位 |
| :--- | :--- |
| **核心价值** | 消除语言壁垒，让异构系统无缝集成 |
| **适用场景** | 多语言微服务、AI 服务部署、遗留系统现代化、跨团队协作 |
| **优势** | 无需 IDL、零代码生成、高性能、自动服务发现、动态治理 |
| **v2.1 新增优势** | 可观测性增强（日志拉取/注入、健康检查、运行状态监控） |
| **权衡** | 需要熟悉 C ABI 的概念（但不需要写 C 代码） |
| **替代方案** | gRPC（更重，但生态更成熟）；REST（更简单，但性能较低） |

**一句话总结：** zAPI 不是又一个 RPC 框架，而是一个让所有编程语言平等对话的分布式服务网格。它用 C ABI 作为通用接口，用二进制协议保证性能，用动态路由简化开发——让跨语言调用变得像调用本地函数一样简单。**v2.1 进一步增强了可观测性能力，让分布式调试从“盲人摸象”变成“上帝视角”。**

---

**项目地址：** [https://github.com/PassByYou888/zAPI](https://github.com/PassByYou888/zAPI)


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