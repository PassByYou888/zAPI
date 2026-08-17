# CONTRIBUTING.md — zAPI 动态库构建指南（完整版）

> 📍 **本文档位于 `Src/` 目录下**，是构建 zAPI 动态库的完整指引。
>
> 📦 **zAPI 项目根目录**：`D:\CoreLibrary\API_Hub_Tool\DLL-Build\`（以下简称为项目根目录）

本文档面向所有希望从源码自行构建 zAPI 动态库的开发者，涵盖 **Windows** 和 **Linux** 两大平台。无论您是资深开发者还是刚入门的小白，按步骤操作即可顺利完成构建。

**本文档的目标：看完这一篇，就能搞定构建，不需要翻其他文档。**

---

## 📖 目录

1. [前置知识](#一前置知识)
2. [构建方式总览](#二构建方式总览)
3. [Windows 平台构建](#三windows-平台构建)
4. [Linux 平台构建（有 Lazarus 支持）](#四linux-平台构建有-lazarus-支持)
5. [Linux 平台构建（无 Lazarus 支持 — 以 LoongArch64 为例）](#五linux-平台构建无-lazarus-支持--以-loongarch64-为例)
6. [mimalloc 动态库的特别说明](#六mimalloc-动态库的特别说明)
7. [构建后的文件清单](#七构建后的文件清单)
8. [快速参考](#八快速参考)


## 一、前置知识

### 1.1 什么是 zAPI？

zAPI 是一个**跨语言 RPC 框架**，允许不同编程语言（C++、Python、Go、Rust、Java、Pascal、C#、PHP、Node.js 等）之间进行高效通信。它包含两个核心组件：

- **zAPI RPC 层**：基于 C4 服务网格，负责服务发现、负载均衡、跨语言路由
- **zIPC 进程通信组件**：基于共享内存 + 零拷贝，同机通信延迟 < 1ms

### 1.2 什么是 mimalloc4p？

`mimalloc4p` 是微软开源高性能内存分配器 [mimalloc](https://github.com/microsoft/mimalloc) 的 Pascal 语言绑定。zAPI 依赖它来获得高性能、低碎片的多线程内存管理能力。详见 [mimalloc4p 仓库](https://github.com/PassByYou888/mimalloc4p)。

### 1.3 依赖组件

zAPI 依赖两个核心子模块，克隆时必须一并拉取：

| 组件 | 仓库地址 | 说明 |
|------|----------|------|
| **zIPC** | https://github.com/PassByYou888/zIPC | 进程间通信核心库 |
| **mimalloc4p** | https://github.com/PassByYou888/mimalloc4p | mimalloc Pascal 绑定 |

### 1.4 构建 zAPI 动态库的三种方式

| 场景 | 推荐方式 | 详见章节 |
|------|----------|----------|
| **Windows 用户（开箱即用）** | 直接使用 `Binary/` 中的预编译 DLL | 无需构建 |
| **Windows（想自己构建）** | 安装 Lazarus，用 `lazbuild` 一键构建 | [第三章](#三windows-平台构建) |
| **Linux（有 Lazarus 支持）** | 用包管理器安装 Lazarus，`lazbuild` 构建 | [第四章](#四linux-平台构建有-lazarus-支持) |
| **Linux（无 Lazarus 支持，如 LoongArch64）** | 先手动编译 `lazbuild`，再用它构建 | [第五章](#五linux-平台构建无-lazarus-支持--以-loongarch64-为例) |


## 二、构建方式总览

### 2.1 核心构建命令

无论什么平台，构建 zAPI 动态库的核心命令只有一条：

```bash
lazbuild z_api_hub.lpi
```

唯一的问题是：**你的系统上是否有 `lazbuild` 这个工具？**

- ✅ **有** → 直接跳到对应平台的构建章节（第三或第四章）
- ❌ **没有** → 先按第五章手动编译 `lazbuild`

### 2.2 项目目录结构（关键路径）

```
D:\CoreLibrary\API_Hub_Tool\DLL-Build\     ← 项目根目录
├── Binary\                               ← 预编译动态库（可直接使用）
│   ├── z_api_hub64.dll
│   ├── z_api_hub32.dll
│   ├── mimalloc64.dll
│   ├── mimalloc32.dll
│   └── ...
├── Src\                                  ← ⭐ 核心源码和构建脚本
│   ├── Z.API_HubTool.pas                 ← 核心 RPC 框架
│   ├── Z.API_HubTool_Export.pas          ← C ABI 导出层
│   ├── Z.Net.C4.API_Hub.pas              ← C4 服务网格集成
│   ├── z_api_hub.lpi                     ← ⭐ 主项目文件（构建动态库）
│   ├── z_api_hub.lpr                     ← 程序入口
│   ├── CONTRIBUTING.md                   ← 本文档
│   ├── 三步构建 lazbuild.md
│   └── FPC 3.3.1 预编译包清单.md
├── C++\                                  ← C/C++ 绑定和示例
├── Py\                                   ← Python 绑定和 Bridge
├── Go\                                   ← Go 绑定
├── java\                                 ← Java 绑定
├── rust\                                 ← Rust 绑定
├── C#\                                   ← C# 绑定
├── pascal\                               ← Pascal 完整文档
└── VB.NET\                               ← VB.NET 绑定
```

> **💡 关键提示**：所有 Pascal 源码和构建项目都在 `Src/` 目录中。构建时请确保当前目录在 `Src/` 下。


## 三、Windows 平台构建

### 3.1 ⚠️ 重要：克隆仓库时必须包含子模块

```cmd
git clone --recursive https://github.com/PassByYou888/zAPI.git
cd zAPI\Src
```

如果已经克隆但忘记拉取子模块，执行：

```cmd
git submodule update --init --recursive
```

### 3.2 安装 Lazarus

1. 访问 https://www.lazarus-ide.org
2. 下载适用于 Windows 的安装包（推荐最新稳定版，如 Lazarus 2.2.6+）
3. 运行安装程序，按提示完成安装（建议安装到 `C:\lazarus`）

### 3.3 配置环境变量

将 Lazarus 的安装目录（例如 `C:\lazarus`）添加到系统 `PATH` 环境变量中。

**验证方法**：打开命令提示符（CMD），输入：

```cmd
lazbuild --version
```

如果能看到版本信息，说明环境变量配置成功。

### 3.4 构建动态库

```cmd
cd D:\CoreLibrary\API_Hub_Tool\DLL-Build\Src
lazbuild z_api_hub.lpi
```

### 3.5 构建产物

| 目标 | 文件 | 位置 |
|------|------|------|
| Windows 32位 | `z_api_hub32.dll` 或 `z_api_hub.dll` | `Src\` 目录 |
| Windows 64位 | `z_api_hub64.dll` | `Src\` 目录 |

### 3.6 关于 mimalloc 的说明（Windows）

Windows 平台下，zAPI 使用 `mimalloc4p` 仓库中**附带的预编译 DLL**：

| 架构 | 文件 |
|------|------|
| 32 位 | `mimalloc32.dll` |
| 64 位 | `mimalloc64.dll` |

这些 DLL 已包含在 `Binary/` 目录中，您可以直接使用。

> **⚠️ 重要**：预编译的 mimalloc DLL 使用 **Visual Studio 2022** 编译，运行时需要安装 **VC++ 可再发行组件**。请从 [微软官方](https://aka.ms/vs/17/release/vc_redist.x64.exe) 下载对应架构的版本。


## 四、Linux 平台构建（有 Lazarus 支持）

如果你的 Linux 发行版提供了 Lazarus 包，构建流程和 Windows 几乎一样简单。

### 4.1 ⚠️ 重要：克隆仓库时必须包含子模块

```bash
git clone --recursive https://github.com/PassByYou888/zAPI.git
cd zAPI/Src
```

### 4.2 安装 Lazarus

**方法一：使用系统包管理器（如果可用）**

```bash
# Debian / Ubuntu
sudo apt-get update
sudo apt-get install lazarus

# Fedora / RHEL / CentOS（需要启用 EPEL）
sudo dnf install lazarus
```

**方法二：从官网下载安装包**
- 访问 https://www.lazarus-ide.org
- 下载适用于你 Linux 发行版的安装包
- 按安装包说明完成安装

### 4.3 验证安装

```bash
lazbuild --version
```

### 4.4 构建动态库

```bash
cd /path/to/zAPI/Src
lazbuild z_api_hub.lpi
```

### 4.5 构建产物

| 平台 | 文件 | 位置 |
|------|------|------|
| Linux | `libz_api_hub.so` | `Src/` 目录 |

### 4.6 关于 mimalloc 的说明（Linux）

Linux 下，mimalloc **需要自行编译生成 `libmimalloc.so`**。详见 [第六章](#六mimalloc-动态库的特别说明)。


## 五、Linux 平台构建（无 Lazarus 支持 — 以 LoongArch64 为例）

> **本指南针对您的文件定制**
>
> - FPC 压缩包：`fpc-3.3.1.loongarch64-linux.tar.gz`（原生龙芯包）
> - Lazarus 源码包：`lazarus_4_8.zip`（来自 Git 标签 `lazarus_4_8` 的打包）
> - 操作系统：Loongnix / 任何 RHEL 系 Linux / Debian/Ubuntu
> - **所有步骤均需手动执行**，每步配有详细解释，确保您完全理解操作意图。
> - **流程通用性**：仅需替换架构名和压缩包名，即可迁移到其他 Linux 架构（x86_64、ARM、RISC‑V 等）。
> - **关于路径**：以下示例中，假设您的压缩包放在 `~/downloads/` 目录下。请您根据实际情况替换为您的真实路径。
> - FPC 3.3.1 全系统打包 + Lazarus 4.8 分支源码，总共约 10 GB，百度网盘：[https://pan.baidu.com/s/1wnlNAjCv3-KaURp3kOaZzw](https://pan.baidu.com/s/1wnlNAjCv3-KaURp3kOaZzw) 提取码：`vl5t`
>
> **作者：老张 qq600585**

### 5.1 准备工作

**确认文件位置**

将以下两个文件放到同一个目录，例如 `~/downloads/`（请根据实际修改）：

- `fpc-3.3.1.loongarch64-linux.tar.gz`
- `lazarus_4_8.zip`

**解压 Lazarus 源码包（.zip 格式）**

`.zip` 格式在 Linux 下使用 `unzip` 命令解压，绝大多数 Linux 发行版默认已安装该工具。若未安装，可通过包管理器快速安装：

```bash
# RHEL / CentOS / Loongnix
yum install -y unzip

# Debian / Ubuntu
apt install -y unzip
```

**解压命令**：

```bash
cd ~/downloads
unzip lazarus_4_8.zip
```

解压后会得到一个目录（通常名为 `lazarus` 或 `lazarus-4.8`）。进入该目录，确认其中包含 `lcl`、`components` 等子目录，这就是 Lazarus 源码根目录。

> **关于 FPC 压缩包**：`fpc-3.3.1.loongarch64-linux.tar.gz` 是标准的 `.tar.gz` 格式，Linux 系统自带的 `tar` 命令即可解压，无需额外工具。

### 5.2 第一步：安装系统编译依赖

**目的**：安装编译 Lazarus 所需的基础开发工具和图形库。

以 root 执行：

```bash
# RHEL / CentOS / Loongnix
yum install -y make gcc gcc-c++ binutils subversion zip unzip \
    libX11-devel gtk2-devel gdk-pixbuf2-devel cairo-devel pango-devel \
    gdb rsync cmake gtk3-devel glibc-devel

# Debian / Ubuntu
apt install -y make gcc g++ binutils subversion zip unzip \
    libx11-dev libgtk2.0-dev libgdk-pixbuf2.0-dev libcairo2-dev libpango1.0-dev \
    gdb rsync cmake libgtk-3-dev
```

> **为什么需要这些？**
>
> - `make`, `gcc`, `binutils`：编译必需品。
> - `gtk2-devel`, `cairo-devel`：LCL 图形库依赖，即使只编译 `lazbuild`（无 GUI），部分 Makefile 仍会引用，缺失会导致链接错误。
> - `cmake`：一些构建辅助工具需要。

**验证**：

```bash
make --version
gcc --version
cmake --version
```

均应正常输出。

### 5.3 第二步：部署 FPC 并配置搜索路径

**目的**：安装 FPC 编译器本体，配置单元搜索路径，确保后续编译能找到所有 `.ppu`。

**① 解压 FPC 包**

```bash
cd ~/downloads
FPC_TARBALL="fpc-3.3.1.loongarch64-linux.tar.gz"
mkdir -p /tmp/fpc_deploy
tar -xzf "$FPC_TARBALL" -C /tmp/fpc_deploy
```

解压后，`/tmp/fpc_deploy` 下会得到 `bin/`、`lib/`、`share/` 三个目录。

**② 复制文件到系统目录**

```bash
\cp -rf /tmp/fpc_deploy/bin/* /usr/bin/
\cp -rf /tmp/fpc_deploy/lib/* /usr/lib/
\cp -rf /tmp/fpc_deploy/share/* /usr/share/
```

> 使用 `\cp` 避免交互式覆盖提示。

**③ 创建后端编译器软链接**

龙芯架构的后端编译器名为 `ppcloongarch64`：

```bash
ln -sf /usr/lib/fpc/3.3.1/ppcloongarch64 /usr/bin/ppcloongarch64
```

> 这样 `fpc` 命令才能调用到实际编译器。

**④ 生成基础 `fpc.cfg`**

```bash
/usr/bin/fpcmkcfg -d basepath=/usr -o /etc/fpc.cfg
```

若提示 `fpcmkcfg` 不存在，请检查第②步是否完整复制。

**⑤ 将所有单元子目录添加到配置（关键步骤）**

> **注意**：不要直接复制绝对路径，请先进入目录查看实际架构名称。

```bash
# 进入 FPC 单元根目录
cd /usr/lib/fpc/3.3.1/units

# 列出所有架构目录，找到您的目标（例如 loongarch64-linux）
ls

# 根据列出的名称，进入对应的架构目录（请将 loongarch64-linux 替换为实际看到的名称）
cd loongarch64-linux   # 请替换为实际目录名

# 现在将当前目录下的所有子目录添加到 fpc.cfg
find . -type d -print | sed 's|^\.||' | while read dir; do
    [ -n "$dir" ] && echo "-Fu$(pwd)${dir}"
done >> /etc/fpc.cfg
```

> **为什么这样做？**
> 不同架构的目录名不同（例如 x86_64-linux、aarch64-linux 等），通过 `ls` 查看后再进入，可以避免因硬编码路径导致的错误。`$(pwd)` 会动态获取当前绝对路径，确保添加的路径正确。

**⑥ 清理临时文件（可选）**

```bash
rm -rf /tmp/fpc_deploy
```

**验证 FPC**：

```bash
fpc -iV          # 应输出 3.3.1
ppcloongarch64 -iV  # 同样输出版本号
```

### 5.4 第三步：编译 `lazbuild`

**目的**：从 Lazarus 源码编译出命令行工具 `lazbuild`，用于后续自动化构建。

**① 进入 Lazarus 源码目录**

根据您在第 5.1 步中解压得到的实际目录名，进入 Lazarus 源码根目录：

```bash
cd /path/to/lazarus   # 请替换为实际的 Lazarus 源码目录路径
```

> 例如，如果您在 `~/downloads/` 下解压得到 `lazarus-4.8`，则执行 `cd ~/downloads/lazarus-4.8`。

**② 编译 `lazbuild`**

```bash
make clean
make lazbuild
```

> 此过程约需 3~5 分钟，若内存较小可添加 `-j1` 限制并行数：`make lazbuild -j1`。

**③ 复制 `lazbuild` 到系统路径**

```bash
cp lazbuild /usr/local/bin/
```

**④ 配置 `lazbuild` 的 Lazarus 目录（关键步骤）**

`lazbuild` 需要知道 Lazarus 源码的位置（即包含 `lcl`、`components` 等子目录的根目录），否则后续使用时可能报错 `Invalid Lazarus directory ""`。

**推荐做法**：

- **将 Lazarus 源码移动到固定位置**（例如 `/usr/local/share/lazarus`）：
  ```bash
  # 首先确认当前目录是 Lazarus 源码根目录（包含 lcl、components 等）
  # 假设当前在 /path/to/lazarus
  mkdir -p /usr/local/share
  rm -rf /usr/local/share/lazarus          # 如果已存在则先删除
  mv . /usr/local/share/lazarus            # 将当前目录整体移动
  # 注意：移动后当前目录会消失，需要切换到新位置
  cd /usr/local/share/lazarus
  ```

- **设置环境变量 `LAZARUS_DIR`**（永久生效）：
  ```bash
  echo 'export LAZARUS_DIR=/usr/local/share/lazarus' >> ~/.bashrc
  source ~/.bashrc
  ```
  这样以后直接运行 `lazbuild` 就会自动识别该目录。

- **或者在每次调用时使用 `--lazarusdir` 参数**（临时方案）：
  ```bash
  lazbuild --lazarusdir=/usr/local/share/lazarus 项目文件.lpi
  ```

> **为什么要这么做？**
> `lazbuild` 编译时记录的是编译时的临时路径，但该路径在解压后可能被删除或移动。将 Lazarus 源码固定到标准目录并配置环境变量，可以保证任何时候都能找到所需的 LCL 单元，避免编译失败。

**⑤ 验证**

```bash
lazbuild --version
```

应显示 Lazarus 4.8 版本信息。同时确认 `lazbuild` 能找到 Lazarus 目录（可尝试不带参数运行 `lazbuild`，应显示帮助信息，无报错）。

### 5.5 第四步：克隆并构建 zAPI

```bash
git clone --recursive https://github.com/PassByYou888/zAPI.git
cd zAPI/Src
# 如果之前已经设置了 LAZARUS_DIR，直接运行
lazbuild z_api_hub.lpi
# 如果未设置，使用 --lazarusdir
# lazbuild --lazarusdir=/usr/local/share/lazarus z_api_hub.lpi
```

### 5.6 常见问题与解决

| 问题 | 原因 | 解决办法 |
| ---- | ---- | -------- |
| `fpc -iV` 报 `ppcloongarch64 can't be executed` | 未创建软链接 | 执行第二步第③条 |
| `make lazbuild` 报 `gtk/gtk.h: No such file` | 图形库未安装 | 重新执行第一步，安装 `gtk2-devel` |
| 找不到 `DB`、`Variants` 等单元 | `fpc.cfg` 缺少子目录 | 重新执行第二步第⑤条，确保所有子目录添加 |
| `unzip: command not found` | 未安装 unzip | 安装 `unzip`（yum/apt install unzip）|
| 解压后目录名不匹配 | 压缩包内顶层目录名不同 | 使用 `ls` 查看实际目录名，再 `cd` 进入 |
| `lazbuild` 报 `Invalid Lazarus directory ""` | 未设置 Lazarus 路径 | 执行第三步第④条，设置 `LAZARUS_DIR` |

### 5.7 通用性说明

- **不同架构**：只需将 `ARCH` 改为对应名称（如 `x86_64`、`arm`、`aarch64`、`riscv64`），并下载对应的 FPC 包。Lazarus 源码通用。
- **不同发行版**：调整包管理器命令（`yum`/`apt`/`pacman`）即可，后续步骤完全相同。
- **离线编译**：所有资源均来自本地压缩包，无需联网。

**掌握这套流程，您可以在任何 Linux 平台上快速构建 `lazbuild`，实现 Lazarus 项目的命令行自动化编译。**


## 六、mimalloc 动态库的特别说明

zAPI 依赖 mimalloc 高性能内存分配器。不同平台的处理方式不同：

| 平台 | mimalloc 来源 | 说明 |
|------|---------------|------|
| **Windows** | `Binary/` 中的预编译 DLL | `mimalloc32.dll` / `mimalloc64.dll`，直接使用 |
| **Linux** | 需自行编译 | 见下文编译步骤 |

### Linux 下编译 mimalloc 的步骤

```bash
# 1. 安装依赖
# Debian / Ubuntu
sudo apt-get update
sudo apt-get install git cmake build-essential

# CentOS / RHEL / Fedora
sudo yum install git cmake gcc-c++ make
# 或
sudo dnf install git cmake gcc-c++ make

# 2. 克隆并编译 mimalloc
git clone https://github.com/microsoft/mimalloc.git
cd mimalloc
git checkout v2.1.7   # 推荐使用稳定版本
mkdir build && cd build
cmake .. -DMI_BUILD_SHARED=ON
make -j$(nproc)
```

编译完成后，`build` 目录下会生成 `libmimalloc.so.2.x`。

### 部署 mimalloc

将编译好的 `libmimalloc.so*` 复制到以下任一位置：

```bash
# 方式一：复制到系统库路径（推荐）
sudo cp build/libmimalloc.so* /usr/lib/

# 方式二：复制到 zAPI 项目目录（便于分发）
cp build/libmimalloc.so* /path/to/zAPI/Binary/

# 方式三：设置环境变量（临时）
export LD_LIBRARY_PATH=/path/to/mimalloc/build:$LD_LIBRARY_PATH
```


## 七、构建后的文件清单

| 平台 | 动态库文件 | 位置 |
|------|-----------|------|
| Windows 32位 | `z_api_hub32.dll` 或 `z_api_hub.dll` | `Src\` |
| Windows 64位 | `z_api_hub64.dll` | `Src\` |
| Linux | `libz_api_hub.so` | `Src/` |

### 依赖的 mimalloc 动态库

| 平台 | mimalloc 文件 | 来源 |
|------|--------------|------|
| Windows 32位 | `mimalloc32.dll` | `Binary/`（预编译） |
| Windows 64位 | `mimalloc64.dll` | `Binary/`（预编译） |
| Linux | `libmimalloc.so.2.x` | 自行编译（见第六章） |

### 建议

构建完成后，建议将生成的动态库复制到项目根目录的 `Binary/` 文件夹中，与预编译版本放在一起便于管理和分发。


## 八、快速参考

### 8.1 各平台构建命令速查

| 平台 | 前置条件 | 构建命令 |
|------|----------|----------|
| **Windows** | 安装 Lazarus，配置 PATH | `cd Src && lazbuild z_api_hub.lpi` |
| **Linux**（有 Lazarus） | 安装 Lazarus | `cd Src && lazbuild z_api_hub.lpi` |
| **Linux**（无 Lazarus） | 先按第五章编译 `lazbuild` | `cd Src && lazbuild z_api_hub.lpi`（需确保 `LAZARUS_DIR` 已设置） |

### 8.2 完整构建流程（通用）

```bash
# 1. 克隆仓库（必须带 --recursive）
git clone --recursive https://github.com/PassByYou888/zAPI.git
cd zAPI/Src

# 2. 确保有 lazbuild（如果没有，参考第五章）
lazbuild --version

# 3. 构建
lazbuild z_api_hub.lpi

# 4. 检查产物
ls -la *.dll *.so 2>/dev/null || echo "构建完成"
```

### 8.3 相关仓库

| 仓库 | 说明 |
|------|------|
| [zAPI](https://github.com/PassByYou888/zAPI) | 主仓库 |
| [zIPC](https://github.com/PassByYou888/zIPC) | 进程通信组件（子模块） |
| [mimalloc4p](https://github.com/PassByYou888/mimalloc4p) | mimalloc Pascal 绑定（子模块） |
| [microsoft/mimalloc](https://github.com/microsoft/mimalloc) | 上游 mimalloc 源码 |

### 8.4 相关文档

| 文档 | 说明 |
|------|------|
| [《三步构建 lazbuild》](./三步构建 lazbuild.md) | 手动编译 lazbuild 完整教程 |
| [《FPC 3.3.1 预编译包清单》](./FPC%203.3.1%20预编译包清单.md) | FPC 预编译包平台索引 |
| [zAPI 项目根目录 README](../readme.md) | 项目总览和语言绑定索引 |

### 8.5 获取帮助

如遇问题，请检查：

1. **是否使用 `--recursive` 克隆**（子模块是否完整）
2. Lazarus / FPC 是否正确安装（`lazbuild --version`、`fpc -iV`）
3. 环境变量 `PATH` 是否包含 Lazarus 目录
4. Linux 下 mimalloc 是否已编译并正确部署
5. 对于手动编译 `lazbuild` 的情况，请仔细阅读同目录的 [《三步构建 lazbuild》](./三步构建 lazbuild.md) 文档

---

*本文档基于 zAPI 项目实际构建流程编写，如有更新请以官方文档为准。*