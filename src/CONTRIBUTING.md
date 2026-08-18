# CONTRIBUTING.md — zAPI 动态库构建指南

本文档介绍如何从源码构建 zAPI 动态库，涵盖 Windows 和 Linux 两大平台。

**核心构建命令**（前提：已安装 Lazarus，FPC ≥ 3.2.2）：

```bash
git clone --recursive https://github.com/PassByYou888/zAPI.git
cd zAPI/src
lazbuild z_api_hub.lpi
```

> 克隆时必须使用 `--recursive` 拉取所有子模块（zIPC、mimalloc4p）。


## 构建方式选择

| 场景 | 方式 |
|------|------|
| Windows | 安装 Lazarus → 配置 PATH → `lazbuild z_api_hub.lpi` |
| Linux（有 Lazarus 包） | 包管理器安装 Lazarus → `lazbuild z_api_hub.lpi` |
| Linux（无 Lazarus 包） | 先手动编译 `lazbuild`，再构建 zAPI |


## Windows 构建

1. 安装 Lazarus（https://www.lazarus-ide.org）
2. **将 Lazarus 安装目录（如 `C:\lazarus`）加入系统 `PATH` 环境变量**
   - 打开 **系统属性** → **高级** → **环境变量** → 编辑 `Path` → 添加 Lazarus 目录
3. 验证：`lazbuild --version`
4. 在 `src/` 目录下执行：

```cmd
lazbuild z_api_hub.lpi
```


## Linux 构建（有 Lazarus 包）

```bash
# Debian/Ubuntu
sudo apt install lazarus

# Fedora/RHEL/CentOS（启用 EPEL）
sudo dnf install lazarus
```

验证后执行：

```bash
cd src
lazbuild z_api_hub.lpi
```


## Linux 构建（无 Lazarus 包）

适用于龙芯（LoongArch64）、RISC‑V 等没有官方 Lazarus 包的架构。

**详细操作步骤请参考同目录下的 [`三步构建 lazbuild.md`](./三步构建%20lazbuild.md)**，该文档完整涵盖了：

- 系统编译依赖安装
- FPC 编译器部署与 `fpc.cfg` 配置
- Lazarus 源码编译生成 `lazbuild`
- 常见问题与排错

简要流程如下：

```bash
# 1. 安装编译依赖（以 RHEL/CentOS 为例）
yum install -y make gcc gcc-c++ binutils subversion zip unzip \
    libX11-devel gtk2-devel gdk-pixbuf2-devel cairo-devel pango-devel \
    gdb rsync cmake gtk3-devel glibc-devel

# 2. 部署 FPC 3.3.1
# （详细步骤见 三步构建 lazbuild.md）

# 3. 编译 lazbuild
# （详细步骤见 三步构建 lazbuild.md）

# 4. 构建 zAPI
cd zAPI/src
lazbuild z_api_hub.lpi
```


## mimalloc 动态库

| 平台 | 来源 |
|------|------|
| Windows | `Binary/mimalloc32.dll` / `mimalloc64.dll`（预编译） |
| Linux | 需自行编译 |

Linux 下编译 mimalloc：

```bash
git clone https://github.com/microsoft/mimalloc.git
cd mimalloc
git checkout v2.1.7
mkdir build && cd build
cmake .. -DMI_BUILD_SHARED=ON
make -j$(nproc)
```

产物：`build/libmimalloc.so.2.x`，复制到 `/usr/lib/` 或 `Binary/`。

> 更多详情请参考 [mimalloc 官方文档](https://github.com/microsoft/mimalloc)。


## 构建产物

| 平台 | 文件 |
|------|------|
| Windows 32位 | `z_api_hub32.dll` |
| Windows 64位 | `z_api_hub64.dll` |
| Linux | `libz_api_hub.so` |


## 相关文档

- [`三步构建 lazbuild.md`](./三步构建%20lazbuild.md) — 手动编译 lazbuild 完整教程
- [zAPI 项目根目录 README](../readme.md) — 项目总览和语言绑定索引


## 相关外部项目

zAPI 依赖或参考了以下开源项目：

| 项目 | 说明 | 仓库地址 |
|------|------|----------|
| **mimalloc** | 微软高性能内存分配器，zAPI Windows 版默认使用 | https://github.com/microsoft/mimalloc |
| **jemalloc** | FreeBSD 系高性能内存分配器，可替代 mimalloc | https://github.com/jemalloc/jemalloc |
| **tcmalloc** | Google 高性能内存分配器（gperftools） | https://github.com/gperftools/gperftools |
| **snappy** | Google 快速压缩/解压缩库，zAPI 可选压缩方案 | https://github.com/google/snappy |

如需替换 zAPI 的内存分配器或压缩库，请参考上述项目的构建文档。
