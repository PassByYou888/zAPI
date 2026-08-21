## 🚀 Cross Demo 全语言实战手册 —— 一键入群，多端齐飞

> *“别光看，上手撸！下面每种语言都给你写好了‘一键入群’的姿势，脚本全给你备好了。”*

---

### 🐍 Python —— 开箱即用的胶水王（也是跳板总指挥）

```bash
cd Py/cross

# 终端1：启动信标（必须最先跑）
python cross_service.py

# 终端2：启动工人（可以开 N 个）
python cross_node.py

# 终端3：启动甲方（10 秒后自动退）
python cross_call.py
```

**懒人专属**：项目提供了 `run.ps1` 脚本，可以一键运行任意 Python 脚本：
```powershell
.\run.ps1 .\cross\cross_service.py  # 启动信标
.\run.ps1 .\cross\cross_node.py     # 启动工人
.\run.ps1 .\cross\cross_call.py     # 启动客户端
```
想跑所有 Python 示例？`.\run_all.ps1` 安排！

---

### 🏛️ Pascal (Delphi / FPC) —— 老当益壮，微服务披袈裟

**编译（二选一）**：
```bash
cd pascal/cross_demo

# 方式一：用项目自带的 build.bat（Windows）
build.bat

# 方式二：手动 lazbuild
lazbuild -B cross_service.lpi
lazbuild -B cross_node.lpi
lazbuild -B cross_call.lpi
```

**运行**：
```bash
# Windows
cross_service.exe
cross_node.exe
cross_call.exe

# Linux/macOS（先 chmod +x）
./cross_service
./cross_node
./cross_call
```

**清理**：`clear_.bat` 一键删除所有 EXE 和临时文件。

**全局编译**：根目录下的 `build_demo.bat` / `build_demo.ps1` 可以一次性编译所有 Pascal 示例（包括压测工具）。

---

### ⚡ C / C++ —— 硬核玩家的速度与激情

```bash
cd C++/CrossDemo

# 用 CMake 构建
mkdir build && cd build
cmake ..
make

# 运行
./CrossService   # 信标
./CrossNode      # 工人（可多开）
./CrossCall      # 甲方
```

**提示**：如果你喜欢 IDE，直接用 Visual Studio 或 CLion 打开 `CMakeLists.txt` 即可。

---

### 🦀 Rust —— 内存安全的狂战士

```bash
cd rust

# 直接跑（Cargo 会自动编译）
cargo run --example cross_service
cargo run --example cross_node
cargo run --example cross_call
```

**检查所有示例编译**：`.\check_all_rs.ps1` 一键检查所有 Rust 示例是否能通过编译。

---

### 🐹 Go —— 云原生时代的“卷王”

```bash
cd Go/demos

# 直接跑
go run cross_service/main.go
go run cross_node/main.go
go run cross_call/main.go
```

**懒人专用**：根目录下的 `run_demo.ps1` 可以交互式选择 demo：
```powershell
.\run_demo.ps1              # 列出所有 demo，让你选
.\run_demo.ps1 cross_service # 直接启动 cross_service
```

**一键体检**：`check_all.ps1` 编译检查所有 Go demo，确保一切正常。

---

### ☕ Java —— 企业级架构师的体面

**编译**：
```bash
cd java
.\build.ps1   # 编译所有 Java 类到 out 目录
```

**运行**（每个组件都有独立脚本）：
```powershell
.\run_cross_service.ps1   # 信标
.\run_cross_node.ps1      # 工人（可多开）
.\run_cross_call.ps1      # 甲方（10 秒后自动退）
```

**其他示例**：
- `.\run_server.ps1` / `.\run_client.ps1` —— 基础 demo
- `.\run_func_server.ps1` / `.\run_func_client.ps1` —— 功能压测

> Java 使用 JNA 加载动态库，脚本已自动配置 `PATH`，你只管双击！

---

### 🔷 C# / .NET —— 微软生态钉子户的尊严

```bash
cd C#

# 用 dotnet CLI
dotnet run --project CrossService
dotnet run --project CrossNode
dotnet run --project CrossCall
```

或者用 Visual Studio 打开 `API_Hub_Demo.sln`，直接编译运行。

---

### 📐 VB.NET —— 老哥别卷了，你的代码今天开始全栈通杀

```bash
cd VB.NET

# 用 dotnet CLI
dotnet run --project CrossService
dotnet run --project CrossNode
dotnet run --project CrossCall
```

同样可以用 Visual Studio 打开解决方案 `ApiHubTool.VB.NET.sln`。

---

### 🌉 PHP / Node.js / Web.js —— 通过“跳板”入场

> *“我们虽然不能直接调 C 库，但我们可以调 Python 桥啊！”*

#### 第一步：启动跳板（Python 桥）
```bash
cd Py/cross
python cross_bridge.py   # 默认监听 8081 端口
```

#### 第二步：各跳板语言客户端

**PHP：**
```bash
cd Py/cross/php
php php_cross_client.php
```

**Node.js：**
```bash
cd Py/cross/nodejs
node node_cross_client.js
```

**Web.js（浏览器）：**  
打开 `Py/cross/webjs/web_cross_client.html`，点击按钮。

> **注意**：PHP、Node.js、浏览器目前**只能当甲方（Caller）**，不能当工人（Worker）。  
> 如果想让它们也能提供服务给别人调，请参考 `Py/bridge/` 下的完整版 `zapi_bridge.py`（支持 Webhook 注册）。

---

## 🎯 混合部署 —— 这才是真正的“全明星阵容”

你可以这样玩：

- 用一个 **Pascal** 节点当信标
- 开 3 个 **Python** 节点当工人
- 开 2 个 **Go** 节点当工人（它们自动加入同一集群）
- 开 1 个 **Rust** 节点当工人
- 用 **Java** 客户端疯狂发请求
- 让 **C#** 客户端也掺和一脚
- 最后用 **浏览器** 点一下按钮，看着 6 个窗口同时刷屏

**完全不用改任何代码**，因为它们都遵循同一套二进制协议，都注册同一个应用名 `demo`。

这就是 **zAPI Cross Demo 给你的超能力——让全语言“蜂群”在你电脑上嗡嗡作响。** 🐝