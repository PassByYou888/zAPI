**zAPI** is a **cross-language RPC framework** based on **pure C ABI**, enabling services written in 10+ languages — C++, Python, Go, Rust, Java, C#, Pascal, PHP, Node.js, and more — to call each other as easily as calling local functions.

> **Core Promise:** No IDL, no code generation, no new protocols to learn — use your familiar language, call the world.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS%20%7C%20BSD-blue)](https://github.com/PassByYou888/zAPI)
[![Rust](https://img.shields.io/badge/Rust-🦀-orange)](https://www.rust-lang.org/)
[![Go](https://img.shields.io/badge/Go-🐹-00ADD8)](https://golang.org/)
[![Python](https://img.shields.io/badge/Python-🐍-3776AB)](https://www.python.org/)
[![Java](https://img.shields.io/badge/Java-☕-007396)](https://www.java.com/)
[![C#](https://img.shields.io/badge/C%23-🔷-512BD4)](https://docs.microsoft.com/en-us/dotnet/csharp/)
[![C++](https://img.shields.io/badge/C%2B%2B-⚡-00599C)](https://isocpp.org/)
[![Pascal](https://img.shields.io/badge/Pascal-📐-E34F26)](https://www.freepascal.org/)
[![PHP](https://img.shields.io/badge/PHP-🐘-777BB4)](https://www.php.net/)
[![Node.js](https://img.shields.io/badge/Node.js-🟢-339933)](https://nodejs.org/)

---

## 🌟 About This Project: Open Source & Non-Commercial

**zAPI is a fully open, non-commercial open-source project.**

- ✅ **Always Free**: MIT licensed — any individual, team, or organization can use it freely, including for commercial purposes
- ✅ **No Commercial Ties**: No paid features, no subscription plans, no "enterprise edition"
- ✅ **Community Driven**: All development decisions come from community contributors, not a commercial entity
- ✅ **Open Collaboration**: Contributions of all kinds are welcome — code, docs, tests, issue discussions
- ✅ **Transparent Development**: All source code is public, builds are reproducible, no closed-source components

> 💡 **Our Belief:** Cross-language communication should be a fundamental right for every developer, not limited by commercial barriers. zAPI will always remain open, free, and community-driven.

---

## 📦 One C ABI, Infinite Possibilities

zAPI is built on a **pure C dynamic library**. Any language that supports FFI can connect. No IDL, no code generation, no complex configuration — **just a header file, and your functions can run across languages, processes, and machines**.

```c
// Register an API in C
static void __cdecl AddCallback(void* trigger, void* input, void* output) {
    int a, b;
    API_ReadBuffer((TDataHnd)input, &a, sizeof(a));
    API_ReadBuffer((TDataHnd)input, &b, sizeof(b));
    int sum = a + b;
    API_WriteBuffer((TDataHnd)output, &sum, sizeof(sum));
}

int main() {
    // The library is loaded automatically when the first API function is called.
    // No manual API_LoadLibrary() is needed.
    TAppHnd app = API_Create_APPHnd("Calc", "Calculator");
    API_Reg_Call(app, "add", "Add two ints", NULL, AddCallback);
    // Prepare network...
    API_Prepare_Service("0.0.0.0", "127.0.0.1:9898");
    API_Prepare_Client("127.0.0.1:9898", app);
    API_Prepare_Done();
    // This API can now be called from any language
}
```

---

## 🚀 Key Features

| Feature | Description |
|---------|-------------|
| **🌍 10+ Language Bindings** | C++, Python, Go, Rust, Java, C#, Pascal, VB.NET, PHP, Node.js, Web.js — out of the box |
| **⚡ High Performance** | IPC mode < 1ms latency, 10,000+ requests/second |
| **🔌 Dual Communication Modes** | TCP (cross-machine) + IPC (same-machine microsecond latency) |
| **🔄 Automatic Service Discovery** | C4-based service mesh with auto-registration, discovery, and load balancing |
| **🛡️ Fault Tolerance & Reconnection** | Auto-reconnect on disconnect; services re-register automatically |
| **🧵 Full Thread Safety** | All APIs support concurrent calls |
| **📦 Zero-Copy Transfer** | Direct internal buffer access for maximum performance |
| **🎯 Two Call Modes** | Request-Response (Call) + One-Way Notification (Notify) |
| **🔧 Dynamic API Unregistration** | `API_UnReg` – remove an API at runtime; broadcast change to all peers (~3s propagation) |
| **⚙️ Runtime Configuration** | `API_SetOption` – adjust authentication, wait‑connection, IPC thread pool, etc. without restart |
| **🔧 Zero-Configuration Startup** | Auto-generates config file on first run; tune without recompilation |

---

## 🎯 Supported Languages

zAPI supports two integration models:

- **Native FFI Bindings** – Languages that can directly load C libraries via FFI (C, C++, Python, Go, Rust, Java, C#, Pascal, VB.NET).
- **HTTP Gateway (ZAPI Bridge)** – Languages that cannot directly load C libraries, using a lightweight HTTP → zAPI gateway (PHP, Node.js, Web.js, and any language with HTTP support).

| Language | Integration Method | Docs | Examples |
|----------|-------------------|------|----------|
| **C++** | Native FFI (RAII) | [📖 Guide](./C++/API%20Hub%20Tool%20C++%20使用指南.md) (CN) | [7 examples](./C++) |
| **C** | Native FFI (explicit load) | [📖 Guide](./C++/API%20Hub%20Tool%20C%20语言使用指南.md) (CN) | [7 examples](./C++) |
| **Python** | Native FFI (`ctypes` + `@expose`) | [📖 Complete Guide](./Py/从零到一，掌握多语言互调.md) (CN) | [20+ examples](./Py/examples/) |
| **Go** | Native FFI (CGO) | [📖 Complete Guide](./Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md) (CN) | [14 examples](./Go/demos/) |
| **Rust** | Native FFI (`libloading` + RAII) | [📖 Guide](./rust/zAPI%20Rust%20使用指南.md) (CN) | [14 examples](./rust/examples/) |
| **Java** | Native FFI (JNA + AutoCloseable) | [📖 Guide](./java/API%20Hub%20Java%20使用指南.md) (CN) | [4 examples](./java/demo/) |
| **C#** | Native FFI (P/Invoke + .NET 8+) | [📖 Complete Guide](./C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md) (CN) | [7 examples](./C%23/) |
| **VB.NET** | Native FFI (P/Invoke) | [📖 Guide](./VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md) (CN) | [5 examples](./VB.NET/) |
| **Pascal (Delphi/FPC)** | Native FFI (`external` auto-load) | [📖 Complete Guide](./pascal/API%20Hub%20Tool%20for%20Pascal.md) (CN) | [3 examples](./pascal/) |
| **PHP** | HTTP Gateway (ZAPI Bridge) | [📖 Bridge Guide](./Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md) (CN) | [PHP client](./Py/bridge/PHP/) |
| **Node.js v2.0** | HTTP Gateway (ZAPI Bridge) | [📖 Bridge Guide](./Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md) (CN) | [Node.js client](./Py/bridge/node.js/) |
| **Web.js (Browser)** | HTTP Gateway (ZAPI Bridge) | [📖 js_api Guide](./Py/web/js_api.py%20使用指南.md) (CN) | [js_api example](./Py/web/js_api.py) |

> **Node.js v2.0** now uses the **ZAPI Bridge** — a lightweight Python HTTP gateway that provides full bidirectional cross-language calling without native dependencies. This replaces the previous npm-based approach. For details, see the [Bridge Complete Guide](./Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md).

> Any language that supports the C ABI can be integrated — you can even write bindings for your own language.

---

## 🚀 5-Minute Quick Start

### Step 1: Get the Dynamic Library

Download the appropriate libraries for your platform from [Releases](https://github.com/PassByYou888/zAPI/releases):

| Platform | Core Library | IPC Dependency |
|----------|--------------|----------------|
| Windows 64-bit | `z_api_hub64.dll` | `z_ipc_64.dll` |
| Linux | `libz_api_hub.so` | `libz_ipc.so` |
| macOS | `libz_api_hub.dylib` | `libz_ipc.dylib` |

Place them in your executable directory or system library path.

### Step 2: Write a Service in Python

```python
# service.py
from api_hub import Server

app = Server("Calculator")

@app.expose("add")
def add(a: int, b: int) -> int:
    return a + b

if __name__ == "__main__":
    app.start("ipc:calc_service")
    input("Press Enter to stop...")
    app.stop()
```

### Step 3: Write a Client in Go (Native FFI)

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

    param, _ := client.CreateDataHnd("add")
    client.WriteInt32(param, 10)
    client.WriteInt32(param, 20)

    result, _ := client.Call("Calculator", param, 3000)
    sum, _ := client.ReadInt32(result)

    fmt.Printf("10 + 20 = %d\n", sum)  // Output: 10 + 20 = 30
}
```

### Step 4: Or Write a Client in PHP (HTTP Gateway)

```php
<?php
require_once 'Py/bridge/PHP/ZAPIBridgeClient.php';

$client = new ZAPIBridgeClient('http://127.0.0.1:8080/v1');
$result = $client->invoke('Calculator', 'add', [10, 20]);
echo "10 + 20 = " . $result . "\n";  // Output: 10 + 20 = 30
?>
```

**Run:**
```bash
# Terminal 1: Start Python service
python service.py

# Terminal 2: Start ZAPI Bridge (HTTP gateway)
cd Py/bridge
python zapi_bridge.py

# Terminal 3: Run Go client (native)
go run client.go

# Or run PHP client (via HTTP gateway)
php client.php
```

**Python service called by Go (native) or PHP (via HTTP gateway) — no extra configuration needed.**

---

## 🛠️ Building zAPI from Source

If you need to build the zAPI dynamic library from source (e.g., for special platforms or custom builds), please refer to the complete build guide:

> 📖 **[《CONTRIBUTING.md》—— zAPI Build Guide](./Src/CONTRIBUTING.md)**

The guide covers:

| Platform | Build Method |
|----------|--------------|
| **Windows** | Install Lazarus → `lazbuild z_api_hub.lpi` |
| **Linux (with Lazarus package)** | Install Lazarus via package manager → `lazbuild z_api_hub.lpi` |
| **Linux (no Lazarus / FPC version too low)** | Build `lazbuild` manually (using FPC 3.3.1) → build zAPI |

**Core build command (prerequisite: Lazarus installed, FPC ≥ 3.2.2):**

```bash
git clone --recursive https://github.com/PassByYou888/zAPI.git
cd zAPI/Src
lazbuild z_api_hub.lpi
```

> ⚠️ **Note**: You must use the `--recursive` flag when cloning to pull all submodules (zIPC, mimalloc4p). FPC version must be ≥ 3.2.2; otherwise, please refer to the "Manual lazbuild Build" route in the build guide.

---

## 📊 Performance Benchmarks

**Test Environment:** Intel Xeon Gold 6248 / 32GB RAM / Ubuntu 22.04

| Communication Mode | Avg Latency (p50) | Max Throughput | Use Case |
|--------------------|-------------------|----------------|----------|
| Same-machine IPC (named pipe) | **< 0.8 ms** | ~12,000 req/s | Single-node microservices, edge computing |
| Local TCP loopback | ~2.5 ms | ~6,500 req/s | Development/testing environments |
| Cross-machine LAN TCP | ~5-15 ms | Bandwidth-limited | Production distributed deployment |

**Comparison Reference:**

| Solution | Typical Latency | Overhead |
|----------|-----------------|----------|
| zAPI (IPC) | < 1 ms | Baseline |
| zAPI (TCP) | ~2-3 ms | +2-3 ms |
| gRPC (TCP) | ~5-8 ms | +4-6 ms |
| HTTP REST (JSON) | ~10-20 ms | +9-18 ms |

**Why so fast?**
1. **Zero-copy data transfer:** `API_GetBuffer()` returns internal pointers directly
2. **Binary protocol:** No JSON/Protobuf encoding/decoding overhead
3. **C-level concurrency scheduling:** Callbacks execute in C thread pools, unaffected by Python/Node GILs

---

## 🌐 Full Language Interoperability Matrix

**Any language client can call any language server:**

| Server ↓ / Client → | C++ | Python | Go | Rust | Java | C# | Pascal | PHP | Node | Web |
|---------------------|-----|--------|-----|------|------|-----|--------|-----|------|-----|
| **C++** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Python** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Go** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Rust** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Java** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **C#** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Pascal** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

> PHP and Node.js clients use the ZAPI Bridge (HTTP gateway) to communicate with all servers.

---

## 📂 Project Structure

```
zAPI/
├── Binary/                # Dynamic libraries & executables
│   ├── z_api_hub64.dll    # Core dynamic library
│   └── z_ipc_64.dll       # IPC support library
├── Src/                   # ⭐ Core source code & build scripts
│   ├── z_api_hub.lpi      # Main project file (build the dynamic library)
│   ├── CONTRIBUTING.md    # Complete build guide
│   └── ...
├── C++/                   # C/C++ bindings + examples
├── Py/                    # Python bindings + 20+ examples
│   ├── api_hub/           # Python core bindings
│   ├── bridge/            # 🌉 ZAPI Bridge (PHP/Node.js/Pascal HTTP gateway)
│   │   ├── PHP/           # PHP client library
│   │   ├── node.js/       # Node.js client library (v2.0)
│   │   └── pascal/        # Pascal Bridge examples
│   ├── node/              # Node.js gateway (legacy, replaced by bridge)
│   └── web/               # Web.js browser gateway
├── Go/                    # Go bindings + 14 examples
├── java/                  # Java bindings + JNA
├── rust/                  # Rust bindings + 14 examples
├── C#/                    # C# bindings + 7 examples
├── VB.NET/                # VB.NET bindings + 5 examples
├── pascal/                # Pascal complete documentation
└── node/                  # Node.js client examples (legacy)
```

---

## 🧩 ZAPI HTTP Bridge

The **ZAPI Bridge** is an HTTP ↔ zAPI gateway that enables bidirectional cross‑language calls for PHP, Node.js, and any language that can make HTTP requests.

**Key Features:**
- 🌉 **Bidirectional**: Call zAPI services from PHP/Node.js, and expose PHP/Node.js functions as zAPI services
- 🐘 **PHP Support**: Full client library with `invoke()`, `notify()`, `registerHook()`, `unregisterHook()`
- 🟢 **Node.js v2.0**: Modern client with Promise-based API, replaces legacy npm-based approach
- 📦 **Zero Native Dependencies**: No FFI, no compilation — just HTTP
- 🚀 **High Performance**: Typical latency 1-3ms for local calls
- 🔧 **Hot Registration**: Register/unregister webhooks at runtime

### Bridge Documentation
- [📖 ZAPI Bridge Complete Guide](./Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)
- [🐍 Python Dependencies](./Py/bridge/ZAPI%20Bridge%20Python%20依赖清单.md)
- [🛠️ Development Pitfalls](./Py/bridge/ZAPI%20桥接开发踩坑记录.md)
- [🧪 Cross‑Language Test Suite](./Py/bridge/run_cross_test.ps1)

### PHP Client Example
```php
require_once 'ZAPIBridgeClient.php';
$client = new ZAPIBridgeClient('http://127.0.0.1:8080/v1');
$result = $client->invoke('Calculator', 'add', [10, 20]);
```

### Node.js Client Example (v2.0)
```javascript
const { ZAPIBridgeClient } = require('./ZAPIBridgeClient');
const client = new ZAPIBridgeClient('http://127.0.0.1:8080/v1');
const result = await client.invoke('Calculator', 'add', [10, 20]);
```

---

## 🔒 Thread Safety & Callback Execution Context

> **All zAPI functions are fully thread-safe.** You can call `API_Call` from thousands of threads concurrently — the library handles it all.

**But pay attention to callback execution context:**

Callbacks (`TAPI_Call` / `TAPI_Notify`) execute in **background thread pools**. This means:

- ❌ **NEVER** call `API_Call` or `API_Notify` from within a callback — may deadlock
- ❌ **NEVER** perform long-running blocking operations in callbacks
- ❌ **NEVER** directly access UI components from callbacks
- ✅ **Recommended:** Offload expensive tasks to your own worker threads asynchronously

```cpp
// ❌ WRONG: Calling API_Call inside a callback
static void __cdecl BadCallback(void* trigger, void* input, void* output) {
    // DEADLOCK RISK!
    TDataHnd result = API_Call("OtherApp", input, 5000);
}

// ✅ CORRECT: Offload task asynchronously
static void __cdecl GoodCallback(void* trigger, void* input, void* output) {
    // Push request to a queue; worker thread handles it
    WorkQueue.push(input);
    // Return immediately
}
```

---

## 🏗️ Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                    Application Layer (10+ Languages)          │
├──────────┬──────────┬──────────┬──────────┬───────────────────┤
│  C++     │  Python  │  Go      │  Rust    │  Java / C#        │
│  Pascal  │  VB.NET  │  C       │          │                   │
├──────────┴──────────┴──────────┴──────────┴───────────────────┤
│                    Unified C ABI Dynamic Library Layer        │
├───────────────────────────────────────────────────────────────┤
│              C4 Distributed Service Mesh                      │
│            (Auto-Discovery / Load Balancing)                  │
├───────────────────────────────────────────────────────────────┤
│         TCP        │        IPC        │   Auto Service       │
│      (Cross-node)  │  (Same-node)      │   Discovery          │
├───────────────────────────────────────────────────────────────┤
│                   ZAPI Bridge (HTTP Gateway)                  │
│          PHP / Node.js / Web.js / Any HTTP Client             │
└───────────────────────────────────────────────────────────────┘
```

---

## 📖 Documentation

### Quick Start (English Overview)
- [zAPI: Make All Languages Talk](./pascal/zAPI：让所有编程语言平等对话的分布式服务网格.md) (CN) — Project overview
- [zAPI Empire Treasure Map](./pascal/zAPI%20帝国藏宝图：一分钟速通全语言版图.md) (CN) — Project structure overview

### Complete Guides
> Also check the [Pascal Demo](./pascal/Pascal%20Demo%20使用说明Delphi+%20Free%20Pascal.md) for a quick start.
 (Chinese — Use AI/Translation Tools)

| Language | Documentation |
|----------|---------------|
| **C++** | [API Hub Tool C++ Guide](./C++/API%20Hub%20Tool%20C++%20使用指南.md) |
| **C** | [API Hub Tool C Guide](./C++/API%20Hub%20Tool%20C%20语言使用指南.md) |
| **Python** | [Master Multi-Language Interop from Zero](./Py/从零到一，掌握多语言互调.md) |
| **Go** | [API Hub for Go — Complete Guide](./Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md) |
| **Rust** | [zAPI Rust Guide](./rust/zAPI%20Rust%20使用指南.md) |
| **Java** | [API Hub Java Guide](./java/API%20Hub%20Java%20使用指南.md) |
| **C#** | [API Hub Tool for C# — Complete Guide](./C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md) |
| **VB.NET** | [VB.NET Full-Stack Domination](./VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md) |
| **Pascal** | [API Hub Tool for Pascal — Complete Guide](./pascal/API%20Hub%20Tool%20for%20Pascal.md) |
| **PHP** | [ZAPI Bridge Complete Guide](./Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md) |
| **Node.js** | [ZAPI Bridge Complete Guide](./Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md) |
| **Web.js** | [js_api.py Guide](./Py/web/js_api.py%20使用指南.md) |

### Architecture Case Studies (Chinese)
- [Go Microservices: Replacing gRPC with zAPI — 60% Lower Latency](./Go/Go%20微服务架构实战：用%20zAPI%20替换%20gRPC%20后，我们的延迟大幅降低.md)
- [Python Microservices: Why We Chose zAPI Over Flask](./Py/web/Python%20微服务选型：为什么我们用%20zAPI%20替代%20Flask%20作为推理服务网关.md)
- [Browser Calling C++: Three Solutions Compared](./Py/web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)

---

## 🤝 Contributing

We welcome all forms of contribution:

- 🐛 Report bugs
- 💡 Suggest new features
- 📝 Improve documentation
- 🔧 Submit Pull Requests
- 🌍 Write bindings for more languages

> **Build Guide**: If you need to build the zAPI dynamic library from source, please refer to [CONTRIBUTING.md](./Src/CONTRIBUTING.md).

---

## 📄 License

**MIT License** — Free to use, modify, and distribute, even for commercial projects.

---

## ⭐ Star Support

If this project helps you, please give us a Star! Your support keeps us motivated.

---

**Make all languages talk to each other.**

[GitHub](https://github.com/PassByYou888/zAPI) · [Issues](https://github.com/PassByYou888/zAPI/issues) · [Releases](https://github.com/PassByYou888/zAPI/releases)
