# zAPI Rust 使用指南

> **从零开始，用 Rust 接入分布式多语言服务生态**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS%20%7C%20BSD-blue)](https://github.com/PassByYou888/zAPI)
[![Rust](https://img.shields.io/badge/Rust-🦀-orange)](https://www.rust-lang.org/)

</div>

---

## 📖 目录

- [这是什么？](#-这是什么)
- [核心概念速览](#-核心概念速览)
- [环境准备](#-环境准备)
- [第一个程序：Hello World（本地调用）](#-第一个程序hello-world本地调用)
- [第二个程序：服务端与客户端（网络调用）](#-第二个程序服务端与客户端网络调用)
- [数据传递：玩转 DataHandle](#-数据传递玩转-datahandle)
- [回调的禁忌与正确姿势](#-回调的禁忌与正确姿势)
- [动态注销 API（新增）](#-动态注销-api新增)
- [运行时配置（新增）](#-运行时配置新增)
- [并发调用：让程序飞起来](#-并发调用让程序飞起来)
- [实战案例：计算器服务](#-实战案例计算器服务)
- [跨语言互调：Rust 与 Python 对话](#-跨语言互调rust-与-python-对话)
- [常用 API 速查表](#-常用-api-速查表)
- [常见问题与排错](#-常见问题与排错)
- [下一步：游走于各大技术体系](#-下一步游走于各大技术体系)

---

## 💡 这是什么？

**zAPI** 是一个让不同编程语言之间可以互相调用函数的框架。你可以用 Rust 写一个服务，然后用 Python、Go、Java、C#、C++、Pascal、PHP、Node.js 等语言去调用它——反过来也行。

> 底层基于 **C4 分布式服务网格**，自动处理服务发现、负载均衡、断线重连。

**Rust 绑定**是 zAPI 的 10+ 种语言绑定之一。它通过动态加载 `z_api_hub` 核心库，让你在 Rust 中既能**暴露** API 给其他语言调用，也能**调用**其他语言暴露的 API。

---

## 🧠 核心概念速览

| 概念           | 说明                                  | Rust 中的对应                |
| -------------- | ------------------------------------- | ---------------------------- |
| **DataHandle** | 数据的容器，包含 API 名称和二进制载荷 | `DataHandle` 结构体          |
| **AppHandle**  | 应用的容器，可注册多个 API            | `AppHandle` 结构体           |
| **Call API**   | 请求-响应模式，调用方等待结果         | `register_call` + `call`     |
| **Notify API** | 单向通知，调用方不等待响应            | `register_notify` + `notify` |
| **回调函数**   | 服务端处理请求的函数，在后台线程执行  | `extern "C" fn`              |
| **动态注销**   | 运行时移除 API，触发网络广播          | `AppHandle::unregister()`    |
| **运行时配置** | 动态调整全局参数（密码、超时等）      | `set_option()`               |

**两种通信模式**：

- **TCP**：跨机器通信，格式如 `127.0.0.1:9898`
- **IPC**：同一台机器上的进程通信，格式如 `ipc:my_service`，延迟更低

---

## 🔧 环境准备

### 第一步：安装 Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### 第二步：获取动态库

从 [Releases](https://github.com/PassByYou888/zAPI/releases) 下载对应平台的动态库：

| 平台           | 文件                                    |
| -------------- | --------------------------------------- |
| Windows 64-bit | `z_api_hub64.dll` + `z_ipc_64.dll`      |
| Windows 32-bit | `z_api_hub32.dll` + `z_ipc_32.dll`      |
| Linux / BSD    | `libz_api_hub.so` + `libz_ipc.so`       |
| macOS          | `libz_api_hub.dylib` + `libz_ipc.dylib` |

把动态库放在：

- 可执行文件同目录，或
- 系统库路径（Windows 的 `PATH`，Linux 的 `LD_LIBRARY_PATH`）

### 第三步：创建 Rust 项目

```bash
cargo new my_zapi_app --bin
cd my_zapi_app
```

### 第四步：添加依赖

在 `Cargo.toml` 中添加：

```toml
[dependencies]
api_hub_rust = { path = "path/to/zAPI/rust" }  # 或者使用 git 依赖
anyhow = "1.0"
```

> 如果 zAPI 仓库在本地，使用 `path` 引用；也可以直接引用 git 仓库。

---

## 🚀 第一个程序：Hello World（本地调用）

先从最简单的开始：**不启动网络，在同一个进程内测试 API 注册和调用**。

### 代码

创建 `src/main.rs`：

```rust
use api_hub_rust::*;

// 回调函数：接收输入，原样返回（Echo）
extern "C" fn echo_callback(_trigger: *mut std::ffi::c_void, input: DataHnd, output: DataHnd) {
    // 获取输入数据的大小
    let size = get_size(input);
    if size > 0 {
        // 读取输入数据
        let mut buf = vec![0u8; size as usize];
        set_pos(input, 0);
        let _ = read_buffer(input, &mut buf);
        // 写入输出
        let _ = write_buffer(output, &buf);
    }
}

fn main() -> Result<(), ApiError> {
    // 1. 创建应用
    let app = AppHandle::new("HelloApp", "My first zAPI app")?;

    // 2. 注册 API
    app.register_call(
        "echo",                    // API 名称
        "Echoes input back",       // 描述
        std::ptr::null_mut(),      // 用户数据（暂不用）
        echo_callback,             // 回调函数
    )?;

    // 3. 准备调用数据
    let mut param = DataHandle::new("echo")?;
    let msg = b"Hello, zAPI!";
    param.write(msg)?;

    // 4. 本地调用（不经过网络）
    let mut result = app.local_call(&param)?;

    // 5. 读取结果
    let mut buf = vec![0u8; result.size() as usize];
    result.read(&mut buf)?;
    println!("Echo: {}", String::from_utf8_lossy(&buf));

    // 资源自动释放（RAII）
    Ok(())
}
```

### 运行

```bash
cargo run
```

输出：

```
Echo: Hello, zAPI!
```

**恭喜！** 你已经完成了第一个 zAPI 程序。这个程序没有使用任何网络，只是在进程内部测试了 API 的注册和调用。

---

## 🌐 第二个程序：服务端与客户端（网络调用）

现在把服务端和客户端分开，让它们通过网络通信。

### 服务端 (`server.rs`)

```rust
use api_hub_rust::*;

extern "C" fn add_callback(_trigger: *mut std::ffi::c_void, input: DataHnd, output: DataHnd) {
    let mut h = unsafe { DataHandle::from_raw(input) };
    let a = h.read_i32().unwrap_or(0);
    let b = h.read_i32().unwrap_or(0);
    let sum = a + b;
    let _ = write_buffer(output, &sum.to_le_bytes());
    println!("[Server] add({}, {}) = {}", a, b, sum);
}

fn main() -> Result<(), ApiError> {
    // 1. 创建应用并注册 API
    let app = AppHandle::new("CalcService", "Calculator")?;
    app.register_call("add", "a+b", std::ptr::null_mut(), add_callback)?;

    // 2. 准备网络
    reset_prepare();
    prepare_service("0.0.0.0:9898", "127.0.0.1:9898")?;  // 监听所有网卡，公布地址为本地
    prepare_client("127.0.0.1:9898", app.as_raw())?;      // 客户端模式，暴露 app

    // 3. 启动框架
    prepare_done()?;

    // 状态信息由库自动打印到控制台
    println!("服务已启动，按 Enter 退出...");
    let _ = std::io::stdin().read_line(&mut String::new());

    // 4. 优雅关闭
    exit_main_thread();
    shutdown();
    Ok(())
}
```

### 客户端 (`client.rs`)

```rust
use api_hub_rust::*;

fn main() -> Result<(), ApiError> {
    // 1. 准备客户端（不暴露任何 API）
    reset_prepare();
    prepare_client("127.0.0.1:9898", std::ptr::null_mut())?;
    prepare_done()?;

    // 2. 构造请求
    let mut param = DataHandle::new("add")?;
    param.write_i32(10)?;
    param.write_i32(20)?;

    // 3. 远程调用
    let res = call("CalcService", param.as_raw(), 5000)?;  // 超时 5 秒

    // 4. 处理结果
    let size = get_size(res);
    if size == 0 {
        println!("调用超时或失败");
    } else {
        let mut resp = unsafe { DataHandle::from_raw(res) };
        let result = resp.read_i32()?;
        println!("10 + 20 = {}", result);
    }

    // 5. 清理
    exit_main_thread();
    shutdown();
    Ok(())
}
```

### 运行

**终端 1（服务端）**：

```bash
cargo run --bin server
```

**终端 2（客户端）**：

```bash
cargo run --bin client
```

客户端输出：

```
10 + 20 = 30
```

服务端输出：

```
[Server] add(10, 20) = 30
```

---

## 📦 数据传递：玩转 DataHandle

`DataHandle` 是 zAPI 中传递数据的核心。它内部同时存储了 **API 名称**和**二进制载荷**。

### 写入数据

```rust
let mut h = DataHandle::new("my_api")?;

// 写入原始字节
h.write(b"hello")?;

// 写入整数（小端字节序）
h.write_i32(12345)?;
h.write_i64(9876543210)?;

// 写入浮点数
h.write_f64(3.14159)?;

// 写入字符串（长度前缀 + UTF-8 字节）
h.write_string("Hello, world!")?;
```

### 读取数据

```rust
let mut h = unsafe { DataHandle::from_raw(raw_ptr) };

// 读取时需要按写入顺序读取
let bytes = h.read_string()?;   // "hello"
let num = h.read_i32()?;        // 12345
let big = h.read_i64()?;        // 9876543210
let pi = h.read_f64()?;         // 3.14159
let msg = h.read_string()?;     // "Hello, world!"
```

### 位置控制

```rust
let pos = h.pos();      // 获取当前位置
h.set_pos(0);           // 重置到开头
let size = h.size();    // 获取数据总大小
h.set_size(1024);       // 预分配空间
```

### 零拷贝访问

```rust
let ptr = h.buffer();   // 直接获取内部缓冲区指针
// 注意：不要超过 size() 的范围
```

---

## ⚠️ 回调的禁忌与正确姿势

这是 zAPI 中**最重要**的知识点。所有回调函数都在**后台线程池**中执行。

### ❌ 绝对禁止

1. **在回调中调用 `call` 或 `notify`** —— 会导致死锁
2. **在回调中执行长时间阻塞操作** —— 如 `sleep`、等待事件、大量循环
3. **在回调中直接访问 UI** —— 需要通过线程同步机制

### ✅ 正确做法

```rust
extern "C" fn my_callback(_trigger: *mut std::ffi::c_void, input: DataHnd, output: DataHnd) {
    // 1. 快速读取数据
    let mut h = unsafe { DataHandle::from_raw(input) };
    let data = h.read_i32().unwrap_or(0);

    // 2. 快速计算（不要做耗时操作）
    let result = data * 2;

    // 3. 快速写入结果
    let _ = write_buffer(output, &result.to_le_bytes());

    // 4. 立即返回 —— 不要在这里调用 call/notify！
}
```

**如果需要做耗时操作或远程调用**，把任务提交到另一个线程：

```rust
extern "C" fn my_callback(_trigger: *mut std::ffi::c_void, input: DataHnd, output: DataHnd) {
    // 只读取必要数据，然后立即返回
    let mut h = unsafe { DataHandle::from_raw(input) };
    let data = h.read_i32().unwrap_or(0);

    // 把耗时任务交给另一个线程
    std::thread::spawn(move || {
        // 在这里可以安全地调用 call 或做耗时操作
        let result = heavy_computation(data);
        // 通过其他方式返回结果（如消息队列）
    });
}
```

---

## 🔧 动态注销 API（新增）

`AppHandle::unregister()` 方法允许您在运行时移除已注册的 API。

### 使用示例

```rust
let app = AppHandle::new("MyService", "Demo")?;
app.register_call("add", "Addition", std::ptr::null_mut(), add_callback)?;

// ... 运行一段时间后 ...

// 动态注销 'add' API
if app.unregister("add").is_ok() {
    println!("API 'add' unregistered, broadcast in progress.");
}
```

### 关键行为

- **本地立即生效**：API 从本地注册表中同步删除。
- **网络异步广播**：删除操作触发 C4 服务网格广播，传播时间约 3 秒。
- **传播延迟窗口**：在广播传播期间，远程调用可能仍然到达并收到"未找到"错误。

### 使用场景

- **热卸载插件**：动态库插件可先注销自身 API，再安全卸载。
- **临时维护模式**：临时下线某些功能 API，无需重启整个应用。
- **权限动态调整**：根据用户角色或运行时条件，移除敏感 API 暴露。

---

## ⚙️ 运行时配置（新增）

`set_option()` 函数允许您在运行时动态调整 API Hub 框架的全局配置选项。

### 函数签名

```rust
pub fn set_option(option: &str, value: &str)
```

### 支持的选项

| 选项键（主名） | 别名 | 值类型 | 说明 |
|---------------|------|--------|------|
| `password` | `passwd` | 字符串 | 设置 C4 P2PVM 认证令牌。**服务端和客户端必须匹配**。 |
| `Quiet` | — | 布尔 | 启用/禁用静默模式（`True`/`False`）。 |
| `External_Conf_Auto_Save` | `Conf_Auto_Save` | 布尔 | 程序退出时自动保存配置到 `.ini` 文件（默认 `True`）。 |
| `Wait_Connection_ReadyOk` | `Wait_API_Prepare_Done`、`WaitConnect`、`Wait_Ready` | 布尔 | 控制 `prepare_done` 是否阻塞等待所有客户端连接就绪。 |
| `Wait_Connection_Timeout` | `Wait_TimeOut` | 整数（毫秒） | 最大等待时间，默认 `30000`。 |
| `ShowThreadID` | `ShowThread`、`Show_Thread` | 布尔 | 在日志中显示线程 ID。 |
| `ConsoleOutput` | `Console_Output` | 布尔 | 启用/禁用控制台日志输出。 |
| `IPC_Serv_ThreadCount` | `IPC_ThreadCount`、`IPC_Server_ThreadCount` | 整数 | IPC 服务线程池大小，默认 `4`。 |
| `IPC_Serv_MaxQueueLength` | `IPC_MaxQueueLength` | 整数 | IPC 消息队列最大长度，默认 `4096`。 |
| `IPC_Serv_MaxMsgSize` | `IPC_MaxMsgSize` | 整数（字节） | 单条 IPC 消息最大大小，默认 `32768`。 |

### 使用示例

```rust
// 设置认证密码
set_option("password", "my_secret_token");

// 服务端不等待客户端就绪（适合大规模部署）
set_option("Wait_Connection_ReadyOk", "False");

// 提高 IPC 并发能力
set_option("IPC_Serv_ThreadCount", "8");
```

---

## ⚡ 并发调用：让程序飞起来

zAPI 的所有函数（除了 `get_status`）都是**线程安全**的。你可以从任意多个线程同时调用 `call`。

```rust
use api_hub_rust::*;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Instant;

fn main() -> Result<(), ApiError> {
    reset_prepare();
    prepare_client("127.0.0.1:9898", std::ptr::null_mut())?;
    prepare_done()?;

    const THREADS: usize = 20;
    const CALLS_PER_THREAD: usize = 50;

    let counter = std::sync::Arc::new(AtomicUsize::new(0));
    let start = Instant::now();

    let mut handles = vec![];
    for _ in 0..THREADS {
        let counter = counter.clone();
        handles.push(std::thread::spawn(move || {
            for _ in 0..CALLS_PER_THREAD {
                let mut param = DataHandle::new("add").unwrap();
                param.write_i32(1).unwrap();
                param.write_i32(2).unwrap();
                let res = call("CalcService", param.as_raw(), 3000).unwrap();
                if get_size(res) > 0 {
                    counter.fetch_add(1, Ordering::SeqCst);
                }
                // res 会被 drop 自动释放
            }
        }));
    }

    for h in handles {
        h.join().unwrap();
    }

    let elapsed = start.elapsed();
    let total = THREADS * CALLS_PER_THREAD;
    let qps = total as f64 / elapsed.as_secs_f64();
    println!("成功: {} / {}, QPS: {:.2}", counter.load(Ordering::SeqCst), total, qps);

    exit_main_thread();
    shutdown();
    Ok(())
}
```

---

## 🎯 实战案例：计算器服务

这是一个完整的计算器服务端，注册了 `add`、`sub`、`mul`、`div` 四个 API。

### 服务端

```rust
use api_hub_rust::*;
use std::ffi::c_void;

extern "C" fn add_callback(_trigger: *mut c_void, input: DataHnd, output: DataHnd) {
    let mut h = unsafe { DataHandle::from_raw(input) };
    let a = h.read_i32().unwrap_or(0);
    let b = h.read_i32().unwrap_or(0);
    let _ = write_buffer(output, &(a + b).to_le_bytes());
}

extern "C" fn sub_callback(_trigger: *mut c_void, input: DataHnd, output: DataHnd) {
    let mut h = unsafe { DataHandle::from_raw(input) };
    let a = h.read_i32().unwrap_or(0);
    let b = h.read_i32().unwrap_or(0);
    let _ = write_buffer(output, &(a - b).to_le_bytes());
}

extern "C" fn mul_callback(_trigger: *mut c_void, input: DataHnd, output: DataHnd) {
    let mut h = unsafe { DataHandle::from_raw(input) };
    let a = h.read_i32().unwrap_or(0);
    let b = h.read_i32().unwrap_or(0);
    let _ = write_buffer(output, &(a * b).to_le_bytes());
}

extern "C" fn div_callback(_trigger: *mut c_void, input: DataHnd, output: DataHnd) {
    let mut h = unsafe { DataHandle::from_raw(input) };
    let a = h.read_i32().unwrap_or(0);
    let b = h.read_i32().unwrap_or(0);
    let result = if b == 0 { 0 } else { a / b };
    let _ = write_buffer(output, &result.to_le_bytes());
}

fn main() -> Result<(), ApiError> {
    let app = AppHandle::new("CalcService", "Calculator")?;
    app.register_call("add", "Addition", std::ptr::null_mut(), add_callback)?;
    app.register_call("sub", "Subtraction", std::ptr::null_mut(), sub_callback)?;
    app.register_call("mul", "Multiplication", std::ptr::null_mut(), mul_callback)?;
    app.register_call("div", "Division", std::ptr::null_mut(), div_callback)?;

    reset_prepare();
    prepare_service("0.0.0.0:9903", "127.0.0.1:9903")?;
    prepare_client("127.0.0.1:9903", app.as_raw())?;
    prepare_done()?;

    println!("CalcService 已启动，按 Enter 退出...");
    let _ = std::io::stdin().read_line(&mut String::new());

    exit_main_thread();
    shutdown();
    Ok(())
}
```

### 客户端

```rust
use api_hub_rust::*;

fn main() -> Result<(), ApiError> {
    reset_prepare();
    prepare_client("127.0.0.1:9903", std::ptr::null_mut())?;
    prepare_done()?;

    macro_rules! call_calc {
        ($api:expr, $a:expr, $b:expr) => {{
            let mut param = DataHandle::new($api)?;
            param.write_i32($a)?;
            param.write_i32($b)?;
            let res = call("CalcService", param.as_raw(), 3000)?;
            if get_size(res) == 0 {
                println!("{}({}, {}) 超时或失败", $api, $a, $b);
            } else {
                let mut resp = unsafe { DataHandle::from_raw(res) };
                println!("{}({}, {}) = {}", $api, $a, $b, resp.read_i32()?);
            }
            Ok::<_, ApiError>(())
        }};
    }

    call_calc!("add", 10, 5)?;
    call_calc!("sub", 10, 5)?;
    call_calc!("mul", 10, 5)?;
    call_calc!("div", 10, 5)?;

    exit_main_thread();
    shutdown();
    Ok(())
}
```

---

## 🌍 跨语言互调：Rust 与 Python 对话

zAPI 最强大的地方在于**跨语言互调**。下面展示 Rust 服务端 + Python 客户端。

### Rust 服务端（同上）

用上面的 `CalcService`，监听 `127.0.0.1:9903`。

### Python 客户端

```python
from api_hub import C4

# 直接调用 Rust 写的计算服务
client = C4("CalcService", "127.0.0.1:9903")
result = client.add(10, 20)
print(f"10 + 20 = {result}")  # 输出: 10 + 20 = 30
```

**不需要任何额外的序列化代码**——zAPI 自动处理了跨语言的数据传输。

### 反过来：Python 服务端 + Rust 客户端

```python
from api_hub import Server

server = Server("PythonService")

@server.expose("greet")
def greet(name: str) -> str:
    return f"Hello, {name}!"

server.start("127.0.0.1:9904")
```

```rust
// Rust 客户端
use api_hub_rust::*;

fn main() -> Result<(), ApiError> {
    reset_prepare();
    prepare_client("127.0.0.1:9904", std::ptr::null_mut())?;
    prepare_done()?;

    let mut param = DataHandle::new("greet")?;
    param.write_string("Rust")?;
    let res = call("PythonService", param.as_raw(), 3000)?;

    let mut resp = unsafe { DataHandle::from_raw(res) };
    println!("{}", resp.read_string()?);  // 输出: Hello, Rust!

    exit_main_thread();
    shutdown();
    Ok(())
}
```

### 用 PHP 调用 Rust 服务（通过 Bridge）

```php
require_once 'ZAPIBridgeClient.php';
$client = new ZAPIBridgeClient('http://127.0.0.1:8080/v1');
$result = $client->invoke('CalcService', 'add', [10, 20]);
echo "10 + 20 = " . $result . "\n";  // 输出: 30
```

---

## 📋 常用 API 速查表

| 函数                                    | 用途                           | 新增 |
| --------------------------------------- | ------------------------------ | ---- |
| `DataHandle::new(name)`                 | 创建数据句柄                   | |
| `h.write(data)` / `h.read(buf)`         | 读写原始字节                   | |
| `h.write_i32(v)` / `h.read_i32()`       | 读写 32 位整数                 | |
| `h.write_i64(v)` / `h.read_i64()`       | 读写 64 位整数                 | |
| `h.write_f64(v)` / `h.read_f64()`       | 读写 64 位浮点数               | |
| `h.write_string(s)` / `h.read_string()` | 读写字符串（长度前缀）         | |
| `h.pos()` / `h.set_pos(p)`              | 获取/设置读写位置              | |
| `h.size()` / `h.set_size(s)`            | 获取/设置缓冲区大小            | |
| `h.buffer()`                            | 获取内部缓冲区指针（零拷贝）   | |
| `AppHandle::new(name, desc)`            | 创建应用句柄                   | |
| `app.register_call(...)`                | 注册请求-响应 API              | |
| `app.register_notify(...)`              | 注册通知 API                   | |
| `app.unregister(api_name)`              | **动态注销 API（新增）**       | ✅ |
| `app.local_call(&param)`                | 本地同步调用                   | |
| `app.local_notify(&param)`              | 本地通知                       | |
| `reset_prepare()`                       | 重置网络准备                   | |
| `prepare_service(listen, pub)`          | 准备服务端                     | |
| `prepare_client(addr, app)`             | 准备客户端                     | |
| `prepare_done()`                        | 启动网络框架                   | |
| `call(app, param, timeout)`             | 远程同步调用                   | |
| `notify(app, param)`                    | 远程通知                       | |
| `set_option(option, value)`             | **运行时配置（新增）**         | ✅ |
| `exit_main_thread()`                    | 停止事件循环                   | |
| `shutdown()`                            | 关闭框架                       | |

---

## ❓ 常见问题与排错

### Q1: `prepare_done()` 返回错误

检查控制台输出，库会打印详细的错误信息（如端口占用、地址格式错误等）。

常见原因：端口被占用、地址格式错误。

### Q2: 回调没有被触发

- 检查应用名和 API 名**大小写**是否完全一致（`CalcService` ≠ `calcservice`）
- 检查客户端是否成功注册（查看控制台状态日志）
- 确保 `prepare_done()` 成功

### Q3: 内存泄漏

- 每个 `DataHandle` 和 `AppHandle` 都会在 `Drop` 时自动释放
- `call` 返回的句柄如果不包装进 `DataHandle`，需要手动 `free_data_hnd`
- **建议**：始终用 `DataHandle::from_raw()` 包装返回值

### Q4: 回调中调用 `call` 导致死锁

**这是最常见的错误**。记住：**回调中绝对禁止调用 `call` 或 `notify`**。把远程调用放到另一个线程。

### Q5: 程序退出时卡住

确保按顺序调用：

```rust
exit_main_thread();  // 先停止事件循环
shutdown();          // 再释放资源
```

### Q6: 动态注销 API 后，正在进行的调用会怎样？

正在执行中的回调不会被打断，它们会正常完成。新到达的请求会在广播传播后收到"未找到"错误。

---

## 🚀 下一步：游走于各大技术体系

掌握了 Rust 绑定，你就打开了通往整个 zAPI 生态的大门：

| 你想用的语言 | 去这里                                              |
| ------------ | --------------------------------------------------- |
| **Python**   | `../Py/从零到一，掌握多语言互调.md` —— 用 `@expose` 装饰器，一行代码暴露 API |
| **Go**       | `../Go/API Hub for Go 从零到一掌握多语言互调.md` —— 14 个完整示例，从入门到并发压测 |
| **Java**     | `../java/API Hub Java 使用指南.md` —— JNA 绑定，AutoCloseable 资源管理 |
| **C#**       | `../C#/API Hub Tool for C# — 完整使用指南.md` —— .NET 8+，P/Invoke 绑定 |
| **C++**      | `../C++/API Hub Tool C++ 使用指南.md` —— RAII 封装，零成本抽象 |
| **Pascal**   | `../pascal/API Hub Tool for Pascal.md` —— 让 Delphi/FreePascal 融入现代生态 |
| **PHP**      | `../Py/bridge/📖 ZAPI Bridge 完整使用手册.md` —— HTTP 网关接入 |
| **Node.js**  | `../Py/bridge/📖 ZAPI Bridge 完整使用手册.md` —— v2.0 全新体验 |

**一个应用场景**：

- 用 **Rust** 写高性能计算核心
- 用 **Python** 写 AI 推理服务
- 用 **Go** 写 API 网关
- 用 **C#** 写业务前端
- 用 **PHP** 写 Web 管理后台
- 它们全部通过 zAPI 互通互调

**这就是 zAPI 的价值：让所有语言，相互对话。**

---

**🌟 如果这个指南对你有帮助，请给项目一个 Star！**

[GitHub](https://github.com/PassByYou888/zAPI) · [Issues](https://github.com/PassByYou888/zAPI/issues) · [Releases](https://github.com/PassByYou888/zAPI/releases)

</div>

## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](../C++/API%20Hub%20Tool%20C++%20使用指南.md)
- [API Hub Tool C 语言使用指南](../C++/API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](../Py/从零到一，掌握多语言互调.md)
- [API Hub for Go 从零到一掌握多语言互调](../Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)
- [API Hub Java 使用指南](../java/API%20Hub%20Java%20使用指南.md)
- [API Hub Tool for C# — 完整使用指南](../C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [API Hub Tool for Pascal](../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../node/Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](../Py/web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](../Py/web/js_api.py%20使用指南.md)
