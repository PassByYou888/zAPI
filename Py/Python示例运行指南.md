# 🐍 Python 示例运行指南

本文档帮助你在 **任何目录** 下正确运行 API Hub 的 Python 示例代码，避免 `ModuleNotFoundError`。

---

## 📦 环境准备

### 1. 动态库文件

确保 `Binary/` 目录下的动态库（`z_api_hub64.dll`、`z_ipc_64.dll` 等）位于系统搜索路径中，或复制到 `Py/` 目录下。

> 如果运行时提示找不到库，请检查 `PATH`（Windows）或 `LD_LIBRARY_PATH`（Linux）是否包含库所在目录。

### 2. Python 依赖

本包依赖 **Python 3.8+**，无需额外安装第三方库（仅使用标准库和 `ctypes`）。

---

## 🗂️ 项目目录结构（关键部分）

```
Py/
├── api_hub/                  ← 核心绑定包（必须）
│   ├── __init__.py
│   ├── core.py
│   ├── _native.py
│   └── ...
├── examples/                 ← 所有示例代码
│   ├── basic/                ← 最简入门示例
│   ├── client_server/        ← 服务端/客户端分离
│   ├── advanced/             ← 高级模式（发布/订阅、任务队列等）
│   ├── ai/                   ← AI 场景（联邦学习、自主代理）
│   ├── data/                 ← 数据操作（数据库、文件传输）
│   ├── microservices/        ← 微服务模式（限流、熔断、配置中心）
│   └── ml/                   ← 机器学习推理
├── bridge/                   ← ZAPI Bridge（HTTP 网关 + Webhook）
│   ├── zapi_bridge.py        ← 主网关（供 PHP/Node.js 调用）
│   ├── python_webhook.py     ← Python Webhook 服务
│   ├── node.js/              ← Node.js 客户端
│   ├── PHP/                  ← PHP 客户端
│   └── pascal/               ← Pascal 测试
├── cross/                    ← 二进制序列化 + 并发调用演示
│   ├── cross_service.py      ← 服务注册中心（信标）
│   ├── cross_node.py         ← 工作节点（暴露 add 和 inv_seri）
│   ├── cross_call.py         ← 并发客户端（多线程调用）
│   ├── cross_bridge.py       ← 轻量 HTTP 中转（供 PHP/Node.js 调用）
│   ├── nodejs/               ← Node.js 客户端
│   ├── php/                  ← PHP 客户端
│   └── webjs/                ← 浏览器 HTML 页面
├── node/                     ← Node.js 网关示例
│   └── gateway.py            ← 简单的 Python 网关（供 Node 调用）
├── web/                      ← 浏览器直接调用示例
│   └── js_api.py             ← 自带 HTML 页面的网关
├── init_demo_env.ps1         ← 环境初始化脚本（PowerShell）
├── run.ps1                   ← 快速运行单个脚本
└── run_all.ps1               ← 批量运行所有示例
```

---

## ✅ 正确运行示例的两种方式

### 方式一：从 `Py` 目录以模块方式运行（推荐）

```bash
# 切换到 Py 目录
cd D:\CoreLibrary\API_Hub_Tool\DLL-Build\Py

# 运行 hello_world 示例
python -m examples.basic.hello_world
```

**原理**：`-m` 会将当前目录加入 `sys.path`，从而自动找到 `api_hub` 包。

### 方式二：设置环境变量 `PYTHONPATH`

**Windows (PowerShell)**：
```powershell
$env:PYTHONPATH = "D:\CoreLibrary\API_Hub_Tool\DLL-Build\Py"
python D:\CoreLibrary\API_Hub_Tool\DLL-Build\Py\examples\basic\hello_world.py
```

**Linux / macOS**：
```bash
export PYTHONPATH="/path/to/Py:$PYTHONPATH"
python /path/to/Py/examples/basic/hello_world.py
```

设置后，无论你在哪个目录运行示例，都能正常导入 `api_hub`。

---

## 📌 常用示例速览

| 示例                                      | 说明                                                         | 运行命令（从 Py 目录）                                  |
| ----------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------- |
| `examples/basic/hello_world.py`           | 最简单的服务端 + 本地调用                                    | `python -m examples.basic.hello_world`                  |
| `examples/basic/calculator.py`            | 计算器服务（加减乘除）                                       | `python -m examples.basic.calculator`                   |
| `examples/client_server/demo_server.py`   | 服务端（注册加法 API）                                       | `python -m examples.client_server.demo_server`          |
| `examples/client_server/demo_client.py`   | 客户端（调用加法）                                           | `python -m examples.client_server.demo_client`          |
| `examples/advanced/pubsub.py`             | 发布/订阅模式                                                | `python -m examples.advanced.pubsub`                    |
| `examples/advanced/task_queue.py`         | 任务队列（生产者/消费者）                                    | `python -m examples.advanced.task_queue`                |
| `examples/ai/federated_learning.py`       | 联邦学习（聚合模型更新）                                     | `python -m examples.ai.federated_learning`              |
| `examples/ai/autonomous_agent.py`         | 自主代理（感知-决策-行动）                                   | `python -m examples.ai.autonomous_agent`                |
| `examples/data/database.py`               | 键值数据库服务                                               | `python -m examples.data.database`                      |
| `examples/ml/nlp_service.py`              | 简单 NLP（情感分析 + 翻译通知）                              | `python -m examples.ml.nlp_service`                     |
| `cross/cross_service.py`                  | 服务注册中心（IPC 信标）                                     | `python -m cross.cross_service`                         |
| `cross/cross_node.py`                     | 工作节点（注册 `add` 和 `inv_seri`，使用二进制序列化）       | `python -m cross.cross_node`                            |
| `cross/cross_call.py`                     | 并发客户端（10 秒持续调用，演示二进制通信）                  | `python -m cross.cross_call`                            |
| `cross/cross_bridge.py`                   | 轻量 HTTP 网关（供 PHP/Node.js 调用 `add` 和 `inv_seri`）    | `python -m cross.cross_bridge --port 8081`              |
| `bridge/zapi_bridge.py`                   | 完整 HTTP 网关（支持 Webhook 注册、双向调用）                | `python -m bridge.zapi_bridge`                          |
| `web/js_api.py`                           | 浏览器调用网关（自带 HTML 页面，访问 http://127.0.0.1:8080） | `python -m web.js_api --port 8080 --endpoint ipc:gateway` |

> **注意**：涉及服务端/客户端分离的示例（如 `client_server`、`cross` 系列），请先启动服务端（`_service` 或 `_node`），再启动客户端（`_client` 或 `_call`）。`cross` 系列中，`cross_service` 是信标，必须先启动；`cross_node` 和 `cross_call` 可同时启动。

---

## 🧪 验证环境是否就绪

运行以下命令快速检查：

```bash
cd Py
python -c "from api_hub import DataHandle; print('✅ 导入成功')"
```

如果输出成功，则环境配置正确。

---

## ❓ 常见问题

### Q1：运行示例时出现 `ModuleNotFoundError: No module named 'api_hub'`

**原因**：Python 找不到 `api_hub` 包。

**解决**：
- 确保你位于 `Py` 目录，并使用 `python -m` 方式运行。
- 或者设置 `PYTHONPATH` 环境变量（见方式二）。
- 也可以运行 `.\init_demo_env.ps1`（Windows）自动设置环境变量。

### Q2：动态库加载失败（`OSError: cannot load library`）

**原因**：`z_api_hub64.dll` 或 `libz_api_hub.so` 不在系统搜索路径中。

**解决**：
- 将 `Binary/` 目录加入 `PATH`（Windows）或 `LD_LIBRARY_PATH`（Linux）。
- 或复制动态库到 `Py/` 目录下。
- 或运行 `.\init_demo_env.ps1`（Windows）自动添加 `Binary` 到 `PATH`。

### Q3：`API_Prepare_Done` 返回 0

**原因**：端口或 IPC 地址被占用，或地址格式错误。

**解决**：
- 检查控制台输出的详细错误信息。
- 更换地址（如 `ipc:calc_service` 改为 `ipc:my_service`）或端口。
- 确保之前运行的进程已完全退出（检查任务管理器）。

### Q4：示例运行后卡住，没有输出

**原因**：服务端可能阻塞等待输入（如 `input()`）。

**解决**：按提示操作，或检查是否启动了对应的服务端/客户端。

### Q5：`cross_call.py` 或 `cross_node.py` 连接失败

**原因**：`cross_service.py` 未先启动，或 IPC 地址不匹配。

**解决**：先启动 `cross_service.py`，确保输出 `[OK] Service registry ready on ipc:cross`，再启动其他 cross 脚本。

---

## 📚 进一步学习

- 完整的 Python 使用指南：[从零到一，掌握多语言互调.md](./从零到一，掌握多语言互调.md)
- 各场景示例源码：`examples/` 目录，每个文件都有注释说明。
- 跨语言互调和 Bridge 使用：[ZAPI Bridge 完整使用手册.md](./bridge/📖 ZAPI Bridge 完整使用手册.md)

---

**现在，选一个示例，开始你的跨语言调用之旅吧！** 🚀
