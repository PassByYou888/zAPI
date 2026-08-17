# CONTRIBUTING.md — zAPI 动态库构建指南

本文档介绍如何从源码构建 zAPI 动态库，涵盖 Windows 和 Linux 两大平台。

**核心构建命令**（前提：已安装 Lazarus，FPC ≥ 3.2.2）：

```bash
git clone --recursive https://github.com/PassByYou888/zAPI.git
cd zAPI/Src
lazbuild z_api_hub.lpi
```

> 克隆时必须使用 `--recursive` 拉取所有子模块（zIPC、mimalloc4p）。


## 构建方式选择

| 场景 | 方式 |
|------|------|
| Windows | 安装 Lazarus → `lazbuild z_api_hub.lpi` |
| Linux（有 Lazarus 包） | 包管理器安装 Lazarus → `lazbuild z_api_hub.lpi` |
| Linux（无 Lazarus 包） | 手动编译 `lazbuild` → 构建 zAPI |


## Windows 构建

1. 安装 Lazarus（https://www.lazarus-ide.org）
2. 将 Lazarus 安装目录（如 `C:\lazarus`）加入 `PATH`
3. 验证：`lazbuild --version`
4. 在 `Src/` 目录下执行：

```cmd
lazbuild z_api_hub.lpi
```

产物：`z_api_hub32.dll` / `z_api_hub64.dll`


## Linux 构建（有 Lazarus 包）

```bash
# Debian/Ubuntu
sudo apt install lazarus

# Fedora/RHEL/CentOS（启用 EPEL）
sudo dnf install lazarus
```

验证后执行：

```bash
cd Src
lazbuild z_api_hub.lpi
```

产物：`libz_api_hub.so`


## Linux 构建（无 Lazarus 包 — 以 LoongArch64 为例）

适用于龙芯、RISC‑V 等没有官方 Lazarus 包的架构。

### 准备文件

- `fpc-3.3.1.loongarch64-linux.tar.gz`
- `lazarus_4_8.zip`

下载地址：https://pan.baidu.com/s/1wnlNAjCv3-KaURp3kOaZzw 提取码：`vl5t`

### 第一步：安装编译依赖

```bash
# RHEL/CentOS/Loongnix
yum install -y make gcc gcc-c++ binutils subversion zip unzip \
    libX11-devel gtk2-devel gdk-pixbuf2-devel cairo-devel pango-devel \
    gdb rsync cmake gtk3-devel glibc-devel

# Debian/Ubuntu
apt install -y make gcc g++ binutils subversion zip unzip \
    libx11-dev libgtk2.0-dev libgdk-pixbuf2.0-dev libcairo2-dev libpango1.0-dev \
    gdb rsync cmake libgtk-3-dev
```

### 第二步：部署 FPC

```bash
cd ~/downloads
mkdir -p /tmp/fpc_deploy
tar -xzf fpc-3.3.1.loongarch64-linux.tar.gz -C /tmp/fpc_deploy

\cp -rf /tmp/fpc_deploy/bin/* /usr/bin/
\cp -rf /tmp/fpc_deploy/lib/* /usr/lib/
\cp -rf /tmp/fpc_deploy/share/* /usr/share/

ln -sf /usr/lib/fpc/3.3.1/ppcloongarch64 /usr/bin/ppcloongarch64

/usr/bin/fpcmkcfg -d basepath=/usr -o /etc/fpc.cfg
```

**配置单元搜索路径**（关键步骤）：

```bash
cd /usr/lib/fpc/3.3.1/units
ls                           # 查看架构目录名
cd loongarch64-linux         # 替换为实际目录名
find . -type d -print | sed 's|^\.||' | while read dir; do
    [ -n "$dir" ] && echo "-Fu$(pwd)${dir}"
done >> /etc/fpc.cfg
```

验证：

```bash
fpc -iV          # 应输出 3.3.1
ppcloongarch64 -iV
```

### 第三步：编译 lazbuild

```bash
cd ~/downloads
unzip lazarus_4_8.zip
cd lazarus          # 替换为实际解压目录名

make clean
make lazbuild
cp lazbuild /usr/local/bin/
```

**配置 Lazarus 目录**：

```bash
mkdir -p /usr/local/share
mv . /usr/local/share/lazarus
cd /usr/local/share/lazarus
echo 'export LAZARUS_DIR=/usr/local/share/lazarus' >> ~/.bashrc
source ~/.bashrc
```

验证：`lazbuild --version`

### 第四步：构建 zAPI

```bash
cd /path/to/zAPI/Src
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


## 常见问题

| 问题 | 解决方案 |
|------|----------|
| `ppcloongarch64 can't be executed` | 创建软链接 `ln -sf /usr/lib/fpc/3.3.1/ppcloongarch64 /usr/bin/ppcloongarch64` |
| `gtk/gtk.h: No such file` | 安装图形库（`gtk2-devel` 或 `libgtk2.0-dev`） |
| 找不到 `DB`、`Variants` 单元 | 重新执行第二步的单元路径配置 |
| `lazbuild: Invalid Lazarus directory ""` | 设置 `LAZARUS_DIR` 环境变量 |


## 构建产物

| 平台 | 文件 |
|------|------|
| Windows 32位 | `z_api_hub32.dll` |
| Windows 64位 | `z_api_hub64.dll` |
| Linux | `libz_api_hub.so` |


## 相关仓库

- [zAPI](https://github.com/PassByYou888/zAPI)（主仓库）
- [zIPC](https://github.com/PassByYou888/zIPC)（子模块）
- [mimalloc4p](https://github.com/PassByYou888/mimalloc4p)（子模块）
- [microsoft/mimalloc](https://github.com/microsoft/mimalloc)（上游）