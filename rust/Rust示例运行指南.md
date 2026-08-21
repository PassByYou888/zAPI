# 🦀 Rust 示例运行指南

> 本文档帮助你在任何环境下正确运行 API Hub 的 Rust 示例代码，快速体验跨语言 RPC 调用。

---

## 📦 前置准备

### 1. 动态库文件

Rust 绑定会动态加载 `z_api_hub64.dll`（Windows）或 `libz_api_hub.so`（Linux/macOS）。确保动态库位于系统搜索路径中：

- **Windows**：将 `Binary/` 目录加入 `PATH`，或将 `z_api_hub64.dll`、`z_ipc_64.dll` 复制到 `rust/` 目录。
- **Linux**：将 `Binary/` 目录加入 `LD_LIBRARY_PATH`，或复制 `libz_api_hub.so`、`libz_ipc.so` 到 `rust/` 目录。
- **macOS**：将 `Binary/` 目录加入 `DYLD_LIBRARY_PATH`，或复制 `libz_api_hub.dylib`、`libz_ipc.dylib` 到 `rust/` 目录。

> **验证**：运行 `cargo run --example echo_server`，若出现 `LibraryLoadFailed` 或 `SymbolNotFound` 错误，说明动态库未正确加载。

### 2. Rust 工具链

确保已安装 Rust 工具链（`rustc`、`cargo`）：

```bash
rustc --version
cargo --version
```

如果未安装，请访问 [rustup.rs](https://rustup.rs/) 安装。

---

## 🗂️ 项目结构

```
rust/
├── Cargo.toml              # 项目配置和依赖
├── Cargo.lock              # 依赖锁定文件
├── src/
│   ├── lib.rs              # 核心绑定库（API Hub Rust 绑定）
│   ├── main.rs             # 综合测试入口
│   └── test_runner.rs      # 测试用例（本地调用、远程IPC、通知等）
├── examples/               # 所有示例代码（20个独立可执行文件）
│   ├── calc_server.rs
│   ├── calc_client.rs
│   ├── echo_server.rs
│   ├── echo_client.rs
│   ├── file_server.rs
│   ├── file_client.rs
│   ├── log_server.rs
│   ├── log_client.rs
│   ├── pubsub_server.rs
│   ├── pubsub_client.rs
│   ├── config_server.rs
│   ├── config_client.rs
│   ├── concurrent_client.rs
│   └── cross_client.rs
├── check_all_rs.ps1        # Windows 批量检查脚本
├── check_all_rs.sh         # Linux/macOS 批量检查脚本
└── Rust示例运行指南.md     # 本文档
```

---

## 🚀 运行方式

### 方式一：运行综合测试（main.rs）

`src/main.rs` 是一个综合测试入口，会自动运行 `test_runner` 模块中的所有测试用例，包括本地调用、远程 IPC 调用、通知等。适合快速验证环境是否正常。

```bash
cd D:\CoreLibrary\API_Hub_Tool\DLL-Build\rust
cargo run
```

**预期输出**：
```
=== API Hub Rust 综合测试 ===

-- 本地调用演示 --
本地 add(5,7) = 12

-- 启动网络服务 (IPC) --
[INFO] 服务已启动。查看控制台输出以获取状态信息。

-- 远程调用演示 --
  测试 add:
   发送 add(10,20) ...
    远程 add(10,20) = 30
  测试 echo:
   发送 echo ...
    远程 echo -> 'Hello from Rust!'
  测试 get_time:
   发送 get_time ...
    远程 get_time -> '...'

-- 通知测试 --
[Notify] Received: Notification from Rust client

-- 本地通知测试 --
[Notify] Received: Local notification

测试完成。按 Enter 退出...
```

> **注意**：如果测试卡住或失败，请检查动态库是否正确加载，或查看控制台输出的详细错误信息。

---

### 方式二：运行单个示例（examples/）

每个 `examples/*.rs` 文件都是一个独立的可执行程序。使用 `cargo run --example <示例名>` 运行。

**基本命令格式**：
```bash
cargo run --example <示例名>
```

**常用示例**：

| 示例名 | 说明 | 运行命令 |
|--------|------|----------|
| `echo_server` | 回显服务端（监听 IPC） | `cargo run --example echo_server` |
| `echo_client` | 回显客户端（调用 echo_server） | `cargo run --example echo_client` |
| `calc_server` | 计算服务端（加减乘除） | `cargo run --example calc_server` |
| `calc_client` | 计算客户端 | `cargo run --example calc_client` |
| `concurrent_client` | 并发压测客户端 | `cargo run --example concurrent_client` |
| `cross_client` | 跨语言调用示例 | `cargo run --example cross_client` |

> **重要**：服务端和客户端需**同时运行**，先启动服务端，再启动客户端。

---

## 📌 完整示例列表（20个）

| 示例名 | 角色 | 说明 |
|--------|------|------|
| `echo_server` | 服务端 | 回显服务，接收字符串并原样返回 |
| `echo_client` | 客户端 | 调用 echo_server，发送并打印回显结果 |
| `calc_server` | 服务端 | 计算服务，支持 add/sub/mul/div |
| `calc_client` | 客户端 | 调用 calc_server 进行算术运算 |
| `file_server` | 服务端 | 文件传输服务（分块传输） |
| `file_client` | 客户端 | 上传/下载文件 |
| `log_server` | 服务端 | 日志收集服务 |
| `log_client` | 客户端 | 发送日志通知 |
| `pubsub_server` | 服务端 | 发布订阅服务 |
| `pubsub_client` | 客户端 | 订阅/发布消息 |
| `config_server` | 服务端 | 配置中心服务 |
| `config_client` | 客户端 | 读写配置 |
| `concurrent_client` | 客户端 | 并发压测，展示线程安全和高吞吐 |
| `cross_client` | 客户端 | 跨语言调用示例（调用其他语言服务） |

---

## 🔧 常用 Cargo 命令

| 命令 | 说明 |
|------|------|
| `cargo run` | 运行综合测试（main.rs） |
| `cargo run --example <示例名>` | 运行单个示例 |
| `cargo build` | 编译（Debug 模式） |
| `cargo build --release` | 编译（Release 模式，性能优化） |
| `cargo run --example <示例名> --release` | 以 Release 模式运行示例 |
| `cargo check` | 检查代码，不编译（快速） |
| `cargo clean` | 清理编译产物 |

---

## 🧪 验证环境是否就绪

运行以下命令快速验证：

```bash
cd D:\CoreLibrary\API_Hub_Tool\DLL-Build\rust
cargo run
```

如果综合测试全部通过，说明环境和动态库配置正确。

---

## ❓ 常见问题

### Q1：运行时提示 `LibraryLoadFailed` 或 `SymbolNotFound`

**原因**：动态库未找到或符号未正确加载。

**解决**：
- 检查 `Binary/` 目录下的动态库是否与当前平台匹配（64位/32位）。
- 将动态库复制到 `rust/` 目录下，或设置 `PATH`/`LD_LIBRARY_PATH`。
- 在 Windows 下，确保 `z_ipc_64.dll` 与 `z_api_hub64.dll` 在同一目录。

### Q2：`cargo run` 报错 `no library named ... found`

**原因**：Rust 依赖未正确拉取。

**解决**：
```bash
cargo update
cargo build
```

### Q3：服务端启动后客户端连不上

**原因**：IPC 地址不一致，或服务端未完全启动。

**解决**：
- 确保服务端和客户端使用相同的 IPC 地址（如 `ipc:test_service`）。
- 等待服务端 `prepare_done()` 完成后再启动客户端。
- 检查控制台输出，查看是否有 `bind address already in use` 等错误。

### Q4：示例运行后卡住，没有输出

**原因**：服务端可能阻塞等待输入（如 `read_line`），或客户端等待服务端响应。

**解决**：
- 按提示操作（如按 Enter 继续）。
- 检查服务端是否正常运行。
- 增加超时时间（如 `call(..., 5000)` 改为 `10000`）。

### Q5：Windows 下运行提示 `VCRUNTIME140.dll` 缺失

**原因**：缺少 Visual C++ Redistributable。

**解决**：安装 `vc_redist.x64.exe`（位于 `Binary/` 目录），或从微软官网下载。

---

## 📚 进一步学习

- 完整的 Rust 使用指南：[zAPI Rust 使用指南.md](./zAPI%20Rust%20使用指南.md)
- 各示例源码：`examples/` 目录，每个文件都有注释说明。
- Rust 绑定 API 文档：查看 `src/lib.rs` 顶部的文档注释。

---

**现在，选一个示例，开始你的跨语言调用之旅吧！** 🚀
