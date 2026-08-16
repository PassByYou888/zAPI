# mimalloc4p — Pascal 内存管理器绑定 (mimalloc)

## 1. 概述

**mimalloc4p** 是一个 Pascal 单元，它将 **Microsoft mimalloc** 高性能内存分配器集成到 Delphi 和 Free Pascal (FPC) 项目中。该单元通过替换默认的内存管理器（`GetMem`、`FreeMem`、`ReallocMem` 等），使所有内存分配操作都转为使用 mimalloc，从而获得更高的吞吐量和更低的内存碎片。

mimalloc 是微软开源的内存分配库，专为多线程环境设计，具有以下特点：
- **极快的分配/释放速度**（尤其适合大量小对象）
- **良好的扩展性**（多核 CPU 下性能接近线性）
- **内存安全**（内置边界检查和释放后填充等）

本单元提供了：
- 与 Delphi / FPC 内存管理器完全兼容的钩子函数
- **16 字节对齐头部**，用于存储用户请求的准确大小（保证 `MemSize` 返回正确值）
- **安全的重分配**（`ReallocMem` 失败时原指针保持不变）
- 支持 **Windows (32/64)、Linux、macOS** 平台
- 自动加载对应的动态库（`mimalloc32.dll`、`mimalloc64.dll`、`libmimalloc.so`、`libmimalloc.dylib`）

---

## 2. 仓库地址

**GitHub**: [https://github.com/PassByYou888/mimalloc4p](https://github.com/PassByYou888/mimalloc4p)

仓库中包含了：
- 本单元的源代码 (`mimalloc4p.pas`)
- 预编译的 mimalloc 动态库（Windows 和 Linux）
- 示例程序
- 构建和部署说明 (`README.md`)

---

## 3. 编译与部署

### 3.1 环境要求

- **Delphi** (XE 或更高) 或 **Free Pascal** (3.0+)
- 目标平台对应的 **mimalloc 动态库**（可以从仓库的 `lib/` 目录获取，或自行编译）

### 3.2 获取 mimalloc 动态库

#### 使用预编译库
仓库的 `lib/` 目录下通常包含：
- `mimalloc32.dll` – Windows 32 位
- `mimalloc64.dll` – Windows 64 位
- `libmimalloc.so` – Linux (x86_64)
- `libmimalloc.dylib` – macOS

将这些文件复制到你的应用程序可执行文件目录，或系统搜索路径中。

#### 从源码编译
你也可以自行编译 mimalloc：
```bash
git clone https://github.com/microsoft/mimalloc.git
cd mimalloc
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4
sudo make install   # Linux/macOS
```
或使用 Visual Studio 打开 `ide/vs2019/mimalloc.sln` 进行编译。

### 3.3 集成到项目

1. 将 `mimalloc4p.pas` 文件放置到你的项目源码目录，或添加到搜索路径。
2. 在需要启用 mimalloc 的**主程序**（或第一个引用它的单元）中，将 `mimalloc4p` 添加到 `uses` 子句。
   ```pascal
   program MyApp;
   uses
     mimalloc4p,  // 放在最前面，确保加载时替换内存管理器
     ...;
   ```
3. 确保动态库在运行时可以被加载（见上文）。
4. 编译运行，所有内存操作将自动使用 mimalloc。

### 3.4 注意事项

- 如果你在 FPC 下使用多线程，此单元提供了非空的 `InitThread` / `DoneThread` 回调，FPC 才能正确初始化线程局部存储（TLS），否则多线程程序会崩溃。
- 该单元会在单元初始化 (`initialization`) 时自动安装内存钩子，在终结 (`finalization`) 时恢复原管理器。因此无需额外调用安装函数。
- 如果需要在运行时切换管理器，可以调用 `InstallMemoryHook` 和 `UnInstallMemoryHook`（但通常不推荐）。

---

## 4. 核心特性详解

### 4.1 16 字节对齐头部

为了确保 `MemSize` 返回正确的用户请求大小（而不依赖 mimalloc 内部元数据），本单元在每个分配块前预留了 **16 字节** 的头部。头部中存储了用户原始请求的字节数。这样做的好处：
- `MemSize` 始终准确，不会受对齐或填充影响。
- 保证了 16 字节对齐，满足 SSE/AVX 指令集的内存对齐要求。

### 4.2 安全的重分配

`ReallocMem` 的实现遵循标准语义：
- 当新大小为 0 时，释放原内存，返回 `nil`。
- 当原指针为 `nil` 时，执行普通分配。
- 当内存不足时，**原指针保持不变**，返回 `nil`（不丢失原数据）。这符合 Delphi/FPC 的预期行为。

### 4.3 线程安全

mimalloc 本身是线程安全的，且本单元在 FPC 下提供了必要的线程初始化回调，确保在多线程环境下正常工作。

---

## 5. 使用示例

### 5.1 自动使用（推荐）

将 `mimalloc4p` 加入到 `uses` 列表，无需任何额外代码：

```pascal
program TestMimalloc;

{$APPTYPE CONSOLE}

uses
  mimalloc4p,
  SysUtils;

var
  P: Pointer;
  Size: NativeInt;
begin
  GetMem(P, 1024);          // 由 mimalloc 分配
  FillChar(P^, 1024, 0);
  Size := MemSize(P);       // 返回 1024（准确值）
  WriteLn('Allocated: ', Size);
  FreeMem(P);
end.
```

### 5.2 手动调用 mimalloc 函数（不经过 RTL）

如果你需要直接使用 mimalloc 的原始函数（如 `mi_malloc`、`mi_free`），可以这样：

```pascal
uses mimalloc4p;  // 该单元已经外部声明了 mi_malloc 等

var
  Raw, P: Pointer;
begin
  Raw := mi_malloc(100 + HEADER_SIZE); // HEADER_SIZE 在本单元中为 16
  if Raw <> nil then
  begin
    SetStoredSize(Raw, 100);           // 存储用户大小
    P := Raw + HEADER_SIZE;            // 用户指针
    // 使用 P ...
    mi_free(Raw);                      // 释放必须传入 Raw
  end;
end;
```

> 注意：`HEADER_SIZE`、`SetStoredSize`、`GetStoredSize` 均为本单元内部实现，若需在外部使用，需自行声明。

---

## 6. 平台与库文件对照

| 平台           | 动态库文件名        |
|----------------|---------------------|
| Windows 32-bit | `mimalloc32.dll`    |
| Windows 64-bit | `mimalloc64.dll`    |
| Linux          | `libmimalloc.so`    |
| macOS          | `libmimalloc.dylib` |

编译时，编译器会根据平台自动选择对应的库名。

---

## 7. 常见问题

**Q: 程序启动时提示找不到动态库？**  
A: 确保动态库位于应用程序目录、系统 PATH 或 LD_LIBRARY_PATH 中。如果使用 Delphi 的 `delayed` 加载，也可以忽略该错误直到第一次调用。

**Q: 如何验证 mimalloc 已生效？**  
A: 可以编写一个小程序大量分配/释放，对比启用前后的性能差异，或者使用内存分析工具查看堆分配器名称。

**Q: 是否会影响已有的第三方内存管理（如 FastMM）？**  
A: 本单元替换的是全局内存管理器，如果之前已安装 FastMM，则会覆盖。可以按需选择。

**Q: 此单元与 `mimalloc.pas` 有何区别？**  
A: `mimalloc4p` 是该仓库的特定版本，修复了历史版本中关于 16 字节对齐、FPC 线程安全、重分配安全等问题，并提供了 Z‑framework 风格的集成。

---

## 8. 许可证

本单元（`mimalloc4p.pas`）的代码遵循与 Z‑framework 相同的许可证（BSD 风格）。底层的 mimalloc 库使用 MIT 许可证。

---

## 9. 更多信息

- **mimalloc 官网**: [https://microsoft.github.io/mimalloc/](https://microsoft.github.io/mimalloc/)
- **mimalloc GitHub**: [https://github.com/microsoft/mimalloc](https://github.com/microsoft/mimalloc)
- **mimalloc4p 仓库**: [https://github.com/PassByYou888/mimalloc4p](https://github.com/PassByYou888/mimalloc4p)
- **Z‑framework 文档**: 参见主手册

---

*文档版本 1.0 – 基于 mimalloc4p.pas 及相关资源整理。*