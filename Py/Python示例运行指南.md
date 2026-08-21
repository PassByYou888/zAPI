# 🐍 Python 示例运行指南

> 本文档帮助你在 **任何目录** 下正确运行 API Hub 的 Python 示例代码，避免 `ModuleNotFoundError`。

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
├── api_hub/                 ← 核心绑定包（必须）
│   ├── __init__.py
│   ├── core.py
│   ├── _native.py
│   └── ...
├── examples/                ← 所有示例代码
│   ├── basic/
│   │   ├── hello_world.py
│   │   ├── calculator.py
│   │   └── echo.py
│   ├── client_server/
│   │   ├── demo_server.py
│   │   └── demo_client.py
│   └── ...（更多场景）
├── bridge/                  ← ZAPI Bridge 相关
├── web/                     ← 浏览器网关
└── 运行Python示例指南.md    ← 本文档
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

| 示例                          | 说明                               | 运行命令（从 Py 目录）                          |
| ----------------------------- | ---------------------------------- | ----------------------------------------------- |
| `examples/basic/hello_world.py` | 最简单的服务端 + 本地调用          | `python -m examples.basic.hello_world`          |
| `examples/basic/calculator.py`  | 计算器服务（加减乘除）             | `python -m examples.basic.calculator`           |
| `examples/client_server/demo_server.py` | 服务端（注册加法 API）       | `python -m examples.client_server.demo_server`  |
| `examples/client_server/demo_client.py` | 客户端（调用加法）           | `python -m examples.client_server.demo_client`  |
| `bridge/zapi_bridge.py`         | HTTP 网关（PHP/Node.js 调用）      | `python -m bridge.zapi_bridge`                  |
| `web/js_api.py`                 | 浏览器调用网关（自带 HTML 页面）   | `python -m web.js_api --port 8080`              |

> **注意**：服务端和客户端需**同时运行**，先启动服务端，再启动客户端。

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

### Q2：动态库加载失败（`OSError: cannot load library`）

**原因**：`z_api_hub64.dll` 或 `libz_api_hub.so` 不在系统搜索路径中。

**解决**：
- 将 `Binary/` 目录加入 `PATH`（Windows）或 `LD_LIBRARY_PATH`（Linux）。
- 或复制动态库到 `Py/` 目录下。

### Q3：`API_Prepare_Done` 返回 0

**原因**：端口或 IPC 地址被占用，或地址格式错误。

**解决**：
- 检查控制台输出的详细错误信息。
- 更换地址（如 `ipc:calc_service` 改为 `ipc:my_service`）或端口。

### Q4：示例运行后卡住，没有输出

**原因**：服务端可能阻塞等待输入（如 `input()`）。

**解决**：按提示操作，或检查是否启动了对应的服务端/客户端。

---

## 📚 进一步学习

- 完整的 Python 使用指南：[从零到一，掌握多语言互调.md](./从零到一，掌握多语言互调.md)
- 各场景示例源码：`examples/` 目录，每个文件都有注释说明。

---

**现在，选一个示例，开始你的跨语言调用之旅吧！** 🚀
