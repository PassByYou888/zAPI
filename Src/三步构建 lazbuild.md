## 三步构建 lazbuild（手动操作版 · 适配 loongarch64 + lazarus_4_8）

### 在 LoongArch64 Linux 上离线编译 Lazarus 命令行工具

---

> **📌 本指南针对您的文件定制**  
>
> - FPC 压缩包：`fpc-3.3.1.loongarch64-linux.tar.gz`（原生龙芯包）  
> - Lazarus 源码包：`lazarus_4_8.rar`（来自 Git 标签 `lazarus_4_8` 的打包）  
> - 操作系统：Loongnix / 任何 RHEL 系 Linux  
> - **所有步骤均需手动执行**，每步配有详细解释，确保您完全理解操作意图。  
> - **流程通用性**：仅需替换架构名和压缩包名，即可迁移到其他 Linux 架构（x86_64、ARM、RISC‑V 等）。  
> - **关于路径**：以下示例中，假设您的压缩包放在 `~/downloads/` 目录下。请您根据实际情况替换为您的真实路径（例如 `/home/你的用户名/downloads/` 或 `/root/downloads/`）。  
> - fpc3.3.1全系统打包+lazarus4.8分支源码,总共10G左右,百度网盘：[https://pan.baidu.com/s/1wnlNAjCv3-KaURp3kOaZzw](https://pan.baidu.com/s/1wnlNAjCv3-KaURp3kOaZzw) 提取码：vl5t
>
> **作者：老张 qq600585**

---

## 📦 准备工作

### 1. 确认文件位置

将以下两个文件放到同一个目录，例如 `~/downloads/`（请根据实际修改）：

- `fpc-3.3.1.loongarch64-linux.tar.gz`
- `lazarus_4_8.rar`

### 2. 安装解压工具（若未安装）

`.rar` 文件需要 `unrar` 或 `7z` 解压：

```bash
yum install -y unrar   # RHEL/CentOS/Loongnix
# 或 apt install unrar （Debian/Ubuntu）
# 或使用 7z: yum install p7zip
```

### 3. 确定架构

本机为 `loongarch64`，已确认。

---

## 🔧 第一步：安装系统编译依赖

**目的**：安装编译 Lazarus 所需的基础开发工具和图形库。

以 root 执行：

```bash
yum install -y make gcc gcc-c++ binutils subversion zip unzip \
    libX11-devel gtk2-devel gdk-pixbuf2-devel cairo-devel pango-devel \
    gdb rsync cmake gtk3-devel glibc-devel	
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

---

## 📂 第二步：部署 FPC 并配置搜索路径

**目的**：安装 FPC 编译器本体，配置单元搜索路径，确保后续编译能找到所有 `.ppu`。

### 操作步骤

#### ① 解压 FPC 包

```bash
cd ~/downloads
FPC_TARBALL="fpc-3.3.1.loongarch64-linux.tar.gz"
mkdir -p /tmp/fpc_deploy
tar -xzf "$FPC_TARBALL" -C /tmp/fpc_deploy
```

解压后，`/tmp/fpc_deploy` 下会得到 `bin/`、`lib/`、`share/` 三个目录。

#### ② 复制文件到系统目录

```bash
\cp -rf /tmp/fpc_deploy/bin/* /usr/bin/
\cp -rf /tmp/fpc_deploy/lib/* /usr/lib/
\cp -rf /tmp/fpc_deploy/share/* /usr/share/
```

> 使用 `\cp` 避免交互式覆盖提示。

#### ③ 创建后端编译器软链接

龙芯架构的后端编译器名为 `ppcloongarch64`：

```bash
ln -sf /usr/lib/fpc/3.3.1/ppcloongarch64 /usr/bin/ppcloongarch64
```

> 这样 `fpc` 命令才能调用到实际编译器。

#### ④ 生成基础 `fpc.cfg`

```bash
/usr/bin/fpcmkcfg -d basepath=/usr -o /etc/fpc.cfg
```

若提示 `fpcmkcfg` 不存在，请检查第②步是否完整复制。

#### ⑤ 将所有单元子目录添加到配置

```bash
UNITS_DIR="/usr/lib/fpc/3.3.1/units/loongarch64-linux"
cd "$UNITS_DIR"
find . -type d -print | sed 's|^\.||' | while read dir; do
    [ -n "$dir" ] && echo "-Fu${UNITS_DIR}${dir}"
done >> /etc/fpc.cfg
```

> **关键**：这一步保证了编译器能搜索到 `fcl-db`、`rtl-objpas`、`fcl-xml` 等所有包的单元文件，避免后续编译报 `Can't find unit xxx`。

#### ⑥ 清理临时文件（可选）

```bash
rm -rf /tmp/fpc_deploy
```

### 验证 FPC

```bash
fpc -iV          # 应输出 3.3.1
ppcloongarch64 -iV  # 同样输出版本号
```

---

## 🛠️ 第三步：编译 `lazbuild`

**目的**：从 Lazarus 源码编译出命令行工具 `lazbuild`，用于后续自动化构建。

### 操作步骤

#### ① 解压 Lazarus 源码（.rar 格式）

```bash
cd ~/downloads
LAZARUS_RAR="lazarus_4_8.rar"
mkdir -p /tmp/lazarus_build
cd /tmp/lazarus_build
unrar x ~/downloads/"$LAZARUS_RAR"
```

> 若 `unrar` 不可用，可使用 `7z x`：`7z x ~/downloads/lazarus_4_8.rar`。

解压后会得到目录名（通常是 `lazarus` 或 `lazarus-4.8`）。您可以查看：

```bash
ls
```

假设解压出的目录名为 `lazarus`，则进入：

```bash
cd lazarus
```

（如果目录名不同，请使用实际名称）

#### ② 编译 `lazbuild`

```bash
make clean
make lazbuild
```

> 此过程约需 3~5 分钟，若内存较小可添加 `-j1` 限制并行数：`make lazbuild -j1`。

#### ③ 复制到系统路径

```bash
cp lazbuild /usr/local/bin/
```

### 验证

```bash
lazbuild --version
```

应显示 Lazarus 4.8 版本信息。

---

## 🧪 最终验证

```bash
fpc -iV
lazbuild --version
```

一切正常，则环境已就绪。

---

## 📌 常见问题与解决

| 问题                                            | 原因                   | 解决办法                                |
| ----------------------------------------------- | ---------------------- | --------------------------------------- |
| `fpc -iV` 报 `ppcloongarch64 can't be executed` | 未创建软链接           | 执行第二步第③条                         |
| `make lazbuild` 报 `gtk/gtk.h: No such file`    | 图形库未安装           | 重新执行第一步，安装 `gtk2-devel`       |
| 找不到 `DB`、`Variants` 等单元                  | `fpc.cfg` 缺少子目录   | 重新执行第二步第⑤条，确保所有子目录添加 |
| `unrar: command not found`                      | 未安装解压工具         | `yum install unrar`                     |
| 解压后目录名不匹配                              | 压缩包内顶层目录名不同 | 使用 `ls` 查看实际目录名，再 `cd` 进入  |

---

## 💡 通用性说明

- **不同架构**：只需将 `ARCH` 改为对应名称（如 `x86_64`、`arm`、`aarch64`、`riscv64`），并下载对应的 FPC 包。Lazarus 源码通用。
- **不同发行版**：调整包管理器命令（`yum`/`apt`/`pacman`）即可，后续步骤完全相同。
- **离线编译**：所有资源均来自本地压缩包，无需联网。

**掌握这套流程，您可以在任何 Linux 平台上快速构建 `lazbuild`，实现 Lazarus 项目的命令行自动化编译。**

---

## 🚀 使用 `lazbuild` 编译项目

编译成功后，您可以：

```bash
lazbuild /path/to/your_project.lpi
```

或批量处理：

```bash
for lpi in *.lpi; do lazbuild --build-mode=Release "$lpi"; done
```

更多用法请参考文档中的“批处理化”章节。

---

> **文档作者：老张 qq600585**  
> 本指南基于龙芯平台实测，欢迎反馈问题。