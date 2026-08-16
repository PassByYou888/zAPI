# ZAPI Bridge Python 依赖清单

> **版本**：2.0  
> **适用项目**：`zapi_bridge.py`（ZAPI HTTP Bridge 主程序）

---

## 📦 依赖清单

将以下内容保存为 `Py/bridge/requirements.txt`：

```txt
# ============================================================
# ZAPI Bridge – Python 依赖清单
# 安装命令：pip install -r requirements.txt
# ============================================================

# ---------- 核心依赖（必需） ----------
flask>=2.0.0                 # Web 框架
requests>=2.25.0             # HTTP 客户端（用于 Webhook 转发）

# ---------- 可选依赖（性能增强，强烈推荐） ----------
waitress>=2.0.0              # 生产级 WSGI 服务器（替代 Flask 内置）
orjson>=3.8.0                # 高性能 JSON 序列化（比标准库快 3-5 倍）
```

---

## 🚀 安装说明

### 方式一：安装所有依赖（推荐）

```bash
cd Py/bridge
pip install -r requirements.txt
```

### 方式二：手动安装

```bash
pip install flask requests waitress orjson
```

### 方式三：最小安装（仅核心）

```bash
pip install flask requests
```

---

## 📊 版本兼容性

| 包名 | 最低版本 | 推荐版本 | 说明 |
|------|---------|---------|------|
| `flask` | 2.0.0 | 2.3.x | 必须 |
| `requests` | 2.25.0 | 2.31.x | 必须 |
| `waitress` | 2.0.0 | 2.1.x | 可选，生产环境推荐 |
| `orjson` | 3.8.0 | 3.9.x | 可选，性能提升明显 |

---

## ⚠️ 常见问题

### Q1: 安装 `orjson` 失败？

`orjson` 需要 Rust 编译器。如果安装失败，可以跳过它（Bridge 会自动回退到标准库 `json`）：

```bash
pip install flask requests waitress
```

### Q2: 使用虚拟环境？

推荐使用虚拟环境隔离项目依赖：

```bash
python -m venv venv
# Windows
venv\Scripts\activate
# Linux/macOS
source venv/bin/activate
pip install -r requirements.txt
```

### Q3: 如何检查依赖是否已安装？

```bash
pip list | grep -E "flask|requests|waitress|orjson"
```

---

## ✅ 验证安装

运行以下命令确认依赖安装成功：

```python
python -c "import flask, requests; print('✅ 核心依赖 OK')"
```

如果安装了可选依赖：

```python
python -c "import waitress, orjson; print('✅ 性能增强 OK')"
```

---

## 📂 目录结构

```
Py/bridge/
├── requirements.txt     # 依赖清单（本文件）
├── zapi_bridge.py       # 主程序
├── python_webhook.py    # Webhook 示例
├── run_cross_test.ps1   # 测试脚本
├── PHP/                 # PHP 客户端
├── node.js/             # Node.js 客户端 (v2.0)
└── pascal/              # Pascal 示例
```

---

> 💡 **提示**：本项目为纯 Python + 标准库实现，除上述包外无额外依赖。`api_hub` 核心绑定已在项目内提供，无需通过 pip 安装。Bridge v2.0 现已支持 PHP 和 Node.js 双向调用，详见 [📖 ZAPI Bridge 完整使用手册](./📖%20ZAPI%20Bridge%20完整使用手册.md)。

---

## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](../../C++/API%20Hub%20Tool%20C++%20使用指南.md)
- [API Hub Tool C 语言使用指南](../../C++/API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](../从零到一，掌握多语言互调.md)
- [API Hub for Go 从零到一掌握多语言互调](../../Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)
- [zAPI Rust 使用指南](../../rust/zAPI%20Rust%20使用指南.md)
- [API Hub Java 使用指南](../../java/API%20Hub%20Java%20使用指南.md)
- [API Hub Tool for C# — 完整使用指南](../../C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [API Hub Tool for Pascal](../../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../../node/Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../../VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](../web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](../web/js_api.py%20使用指南.md)
- [📖 ZAPI Bridge 完整使用手册](./📖%20ZAPI%20Bridge%20完整使用手册.md)
- [ZAPI 桥接开发踩坑记录](./ZAPI%20桥接开发踩坑记录.md)
