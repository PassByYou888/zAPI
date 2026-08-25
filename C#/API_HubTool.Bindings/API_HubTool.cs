/*
 * API_HubTool.cs - API Hub 动态库的 C# P/Invoke 绑定
 *
 * 本文件为 API Hub 动态库导出的所有函数提供托管包装器。
 * 所有导出函数均以 "API_" 为前缀，与 C 和 Pascal 绑定保持一致。
 *
 * 动态库由自定义 DllImport 解析器根据当前平台自动加载：
 *   - Windows 32位: z_api_hub32.dll
 * - Windows 64位: z_api_hub64.dll
 * - Linux:          libz_api_hub.so
 * - macOS:          libz_api_hub.dylib
 *
 * ============================================================================
 * 字符串编码 – 强制使用 UTF-8
 * ============================================================================
 * 所有字符串参数（包括 API 名称、描述、网络地址）必须使用 **UTF-8** 编码，
 * 并且必须以空字符（#0）结尾。
 *
 * - UTF-8 是多字节编码，ASCII 字符（0x00–0x7F）占 1 个字节，其他 Unicode 字符
 *   占 2–4 个字节。空终止符是格式良好的 UTF-8 字符串中唯一的零字节。
 * - 库内部将 UTF-8 输入解码为 Unicode，并将输出字符串编码为 UTF-8。
 * - 此编码是 **平台无关** 的，在 Windows、Linux、macOS 和 BSD 上表现一致。
 *
 * 重要：请勿使用系统 ANSI 代码页（如 Windows 的 CP_ACP）。所有字符串均显式
 * 按 UTF-8 封送。
 *
 * ============================================================================
 * 快速入门 – 典型使用模式
 * ============================================================================
 *
 * 1. 创建应用句柄（AppHnd）：
 *    AppHnd app = API.API_Create_APPHnd("MyApp", "示例应用");
 *
 * 2. 注册自己的 API 回调：
 *    API.API_Reg_Call(app, "echo", "回显输入", IntPtr.Zero, MyEchoCallback);
 *
 * 3. 准备网络（服务端和/或客户端）：
 *    API.API_Reset_Prepare();
 *    API.API_Prepare_Service("0.0.0.0", "127.0.0.1:9898");   // TCP 服务
 *    API.API_Prepare_Client("127.0.0.1:9898", app);           // 连接到此服务
 *    if (API.API_Prepare_Done() == 1) { ... }                 // 启动框架
 *
 * 4. 发起远程调用：
 *    DataHnd data = API.API_Create_DataHnd("echo");
 *    API.WriteString(data, "Hello, world!");
 *    DataHnd result = API.API_Call("TargetApp", data, 5000);
 *    API.API_Free_DataHnd(data);   // 释放输入句柄
 *    // 处理结果 ...
 *    API.API_Free_DataHnd(result);
 *
 * 5. （可选）动态注销 API：
 *    if (API.API_UnReg(app, "echo") == 1)
 *        Console.WriteLine("API 'echo' 已注销，正在广播。");
 *
 * 6. （可选）调整运行时选项，例如认证密码：
 *    API.API_SetOption("password", "my_secret_token");
 *    API.API_SetOption("Wait_Connection_ReadyOk", "False");   // 不等待客户端就绪
 *
 * 7. 关闭和清理：
 *    API.API_Exit_MainThread();   // 停止主循环
 *    API.API_Free_APPHnd(app);    // 释放应用句柄
 *    API.API_shutdown();          // 关闭框架
 *
 * ============================================================================
 * 重要说明与最佳实践（使用前请阅读）
 * ============================================================================
 *
 * 1. **线程安全**：
 *    所有导出函数均是 **完全线程安全** 的，可在任何线程中并发调用，无需外部同步。
 *
 *    但对于同一个 DataHnd，写操作（API_WriteBuffer、API_SetPos、API_SetSize）
 *    应跨线程串行化，因为它们会修改内部缓冲区状态。只读操作（API_GetBuffer、
 *    API_GetPos、API_GetSize）即使在另一个线程写入时也是安全的，只要句柄未被释放。
 *
 *    不同 DataHnd 实例相互独立，可无限制并发使用。
 *
 * 2. **回调执行上下文**（⚠️ 至关重要）：
 *    您的回调（APICallDelegate、APINotifyDelegate）在库内部线程池的 **后台线程**
 *    中执行。
 *
 *    这意味着：
 *      * 回调内部 **禁止** 执行长时间阻塞操作。
 *      * 回调内部 **禁止** 调用 API_Call() 或 API_Notify() – 这可能导致死锁，
 *        因为回调线程可能持有内部锁。如需发起远程调用，请将请求卸载到单独的
 *        工作线程，然后快速返回。
 *      * 回调内部 **禁止** 直接访问 UI 组件或线程局部存储，除非通过适当的同步
 *        机制（如 Control.Invoke 或线程安全队列）。
 *      * 将重处理卸载到单独线程或队列，保持回调响应迅速。
 *
 *    库保证回调是线程安全且可重入的，但您需确保从回调中访问的任何共享数据
 *    都得到正确同步。
 *
 * 3. **执行顺序**：
 *    库 **不保证** 并发 API 调用的执行顺序。调用是独立的，可能乱序执行，
 *    因为底层服务网格为负载均衡将请求分发到多个应用实例。如果您按顺序发送
 *    '1'、'2'、'3'，远程端可能按 '2'、'1'、'3' 处理。只有每个调用的请求-
 *    响应语义是可靠的——每个调用原子地返回正确结果，但全局顺序不保留。
 *
 * 4. **数据句柄生命周期**：
 *    每个通过 API_Create_DataHnd() 创建的 DataHnd 在不再需要时 **必须** 使用
 *    API_Free_DataHnd() 释放。库不会自动释放它们，即使在远程调用后也不会
 *    （它内部克隆输入）。
 *
 * 5. **结果句柄**：
 *    API_Call() 始终返回一个有效的 DataHnd（绝非空句柄）。如果调用超时或失败，
 *    句柄大小将为 0。您仍必须用 API_Free_DataHnd() 释放它。
 *
 * 6. **回调委托必须保持存活**（⚠️ 至关重要）：
 *    注册回调时，委托对象被转换为函数指针并传递给原生库。您必须保持委托存活
 *    （例如存储在静态变量或类字段中）以防止被垃圾回收。本包装器不会自动缓存
 *    委托，您负责其生命周期。
 *
 * 7. **超时**：
 *    API_Call() 的超时单位为毫秒。0 表示无限等待（慎用）。超时时返回的句柄
 *    大小为 0。
 *
 * 8. **应用名称**：
 *    应用名称区分大小写，且应在网络中唯一。
 *
 * 9. **动态注销（API_UnReg）**：
 *    - 立即从本地注册表中移除 API。
 *    - 触发异步网络广播给所有已连接的对等节点。
 *    - 远程对等节点在大约 3 秒内停止看到此 API（取决于网络延迟和 C4 更新间隔）。
 *    - 在此短暂窗口期内，远程调用仍可能被尝试；它们将优雅失败（远端收到
 *      "未找到" 错误）。
 *
 * 10. **运行时选项（API_SetOption）**：
 *     支持以下键（不区分大小写，接受别名）：
 *       - "password" / "passwd" ：设置 C4 P2PVM 认证令牌。
 *         服务端和客户端必须匹配。
 *       - "Quiet" ：启用/禁用静默模式（True/False）。
 *       - "External_Conf_Auto_Save" / "Conf_Auto_Save" ：退出时自动保存 .ini。
 *       - "Wait_Connection_ReadyOk" / "Wait_API_Prepare_Done" / ... ：
 *         控制 API_Prepare_Done 是否阻塞直到所有客户端连接就绪。
 *         设为 False 时，客户端稍后自动连接（适用于部署）。
 *       - "Wait_Connection_Timeout" / "Wait_TimeOut" ：上述为 True 时的最大等待毫秒数。
 *       - "ShowThreadID" / "ShowThread" / "Show_Thread" ：在日志中显示线程 ID。
 *       - "ConsoleOutput" / "Console_Output" ：启用/禁用控制台日志输出。
 *       - "IPC_Serv_ThreadCount" / "IPC_ThreadCount" / ... ：IPC 服务线程池大小。
 *       - "IPC_Serv_MaxQueueLength" / "IPC_MaxQueueLength" / ... ：IPC 消息队列最大长度。
 *       - "IPC_Serv_MaxMsgSize" / "IPC_MaxMsgSize" / ... ：IPC 单条消息最大字节数。
 *
 * ============================================================================
 * 新增功能：同步回调注册（用于 UI 主线程安全调用）
 * ============================================================================
 * 为方便 UI 应用开发，本绑定新增了 API_Reg_Call_Sync 和 API_Reg_Notify_Sync
 * 方法。使用这些方法注册的回调将自动在调用 ProcessSyncQueue 的线程（通常
 * 是主 UI 线程）中执行，业务代码可直接操作 UI 控件，无需手动 Invoke。
 *
 * 典型用法：
 *   1. 在 UI 线程（如 Form_Load）中启动一个定时器或订阅 Application.Idle，
 *      定期调用 API.ProcessSyncQueue()。
 *   2. 使用 API_Reg_Call_Sync 或 API_Reg_Notify_Sync 注册需要访问 UI 的 API。
 *   3. 在回调方法中直接读写 UI 控件，无需任何线程封送代码。
 *
 * 注意事项：
 *   - ProcessSyncQueue 必须在主线程中调用，否则回调将在错误线程执行。
 *   - 回调中不应执行长时间操作，以免阻塞 UI 消息循环。
 *   - 异常会被捕获并输出到调试输出，不会中断后续任务。
 *
 * ============================================================================
 * 关键修复与机制说明（2026-08-25 实战踩坑）
 * ============================================================================
 * 问题现象：使用同步注册回调时，应用程序在收到远程请求后立即崩溃。
 * 根因分析：桥接委托只负责将用户回调入队，然后立即返回。但底层 C 库在桥接
 *           委托返回后会立即释放或重用 input/output 句柄。当主线程随后
 *           执行用户回调时，访问的句柄已无效，导致 Access Violation。
 *
 * 修复方案：在桥接委托中使用 ManualResetEvent 等待用户回调完成。
 *           即：桥接委托将用户回调入队后，阻塞等待一个事件；主线程执行
 *           完用户回调后设置该事件，唤醒桥接线程。这保证了句柄在整个
 *           回调期间始终有效。
 *
 * 技术对比：Pascal 绑定使用 TSoft_Synchronize_Tool.Synchronize，它同样会
 *           阻塞当前线程直到主线程执行完毕。因此我们必须在 C# 中实现
 *           同样的“阻塞等待”语义，否则无法安全地将回调迁移到主线程。
 *
 * 实现细节：
 *   - 每个桥接委托创建一个独立的 ManualResetEvent。
 *   - 用户回调被包装为 Action，入队到 ConcurrentQueue。
 *   - 桥接线程调用 WaitOne() 阻塞，直到主线程执行完 Action 并调用 Set()。
 *   - 使用 using 确保事件被正确释放（即使发生异常）。
 *
 * 风险提示：
 *   - 此机制会增加主线程的负担，若回调执行慢，会拖慢整个 UI。
 *   - 建议仅在必要场景（UI 操作）使用同步注册，其他场景用原生异步注册。
 * ============================================================================
 *
 * ============================================================================
 * 附加示例（无网络本地调用）
 * ============================================================================
 *
 *     using API_HubTool.Bindings;
 *     using static API_HubTool.Bindings.API;
 *
 *     private static void AddCallback(IntPtr trigger, IntPtr input, IntPtr output)
 *     {
 *         DataHnd hInput = new DataHnd { Handle = input };
 *         DataHnd hOutput = new DataHnd { Handle = output };
 *         byte[] buf = ReadAllBytes(hInput);
 *         if (buf.Length >= 8)
 *         {
 *             int a = BitConverter.ToInt32(buf, 0);
 *             int b = BitConverter.ToInt32(buf, 4);
 *             int sum = a + b;
 *             API_WriteBuffer(hOutput, BitConverter.GetBytes(sum), 4);
 *         }
 *     }
 *
 *     // 在 Main 中：
 *     AppHnd app = API_Create_APPHnd("LocalDemo", "仅本地");
 *     // 委托必须保持存活（例如使用 GCHandle.Alloc）。
 *     APICallDelegate del = AddCallback;
 *     GCHandle.Alloc(del);   // 防止回收
 *     API_Reg_Call(app, "add", "加法", IntPtr.Zero, del);
 *
 *     DataHnd data = API_Create_DataHnd("add");
 *     byte[] payload = new byte[8];
 *     BitConverter.GetBytes(10).CopyTo(payload, 0);
 *     BitConverter.GetBytes(20).CopyTo(payload, 4);
 *     API_WriteBuffer(data, payload, 8);
 *
 *     DataHnd result = API_Local_APP_Call(app, data);
 *     API_Free_DataHnd(data);
 *     if (result.IsValid && API_GetSize(result) >= 4)
 *     {
 *         int sum = BitConverter.ToInt32(ReadAllBytes(result), 0);
 *         Console.WriteLine($"10 + 20 = {sum}");
 *         API_Free_DataHnd(result);
 *     }
 *
 *     // 注销 'add' API（可选）
 *     if (API_UnReg(app, "add") == 1)
 *         Console.WriteLine("'add' 已注销。");
 *
 *     // 设置运行时选项（例如启用安静模式）
 *     API_SetOption("Quiet", "True");
 *
 *     API_Free_APPHnd(app);
 *     API_shutdown();
 *
 * 更多示例请参见配套的演示项目（HelloWorld、Service、Client1 等）。
 */

using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Threading;   // 需要 ManualResetEvent

namespace API_HubTool.Bindings
{
    // ----------------------------------------------------------------------------
    // UTF-8 字符串封送辅助类
    // ----------------------------------------------------------------------------
    internal static class UTF8Marshal
    {
        /// <summary>
        /// 将托管字符串转换为以空字符结尾的 UTF-8 字节数组。
        /// 若输入为 null，返回 null；若为空字符串，返回仅包含一个空字节的数组。
        /// </summary>
        /// <param name="str">要转换的托管字符串。</param>
        /// <returns>UTF-8 字节数组（含空终止符），或 null。</returns>
        public static byte[] StringToUTF8Bytes(string str)
        {
            if (str == null) return null;
            byte[] utf8 = Encoding.UTF8.GetBytes(str);
            byte[] withNull = new byte[utf8.Length + 1];
            Array.Copy(utf8, withNull, utf8.Length);
            withNull[utf8.Length] = 0;
            return withNull;
        }

        /// <summary>
        /// 为 UTF-8 字符串分配非托管内存（含空终止符）并复制字节。
        /// 若输入为 null，返回 IntPtr.Zero。
        /// 若为空字符串，分配一个字节（空终止符）。
        /// </summary>
        /// <param name="str">要分配的托管字符串。</param>
        /// <returns>指向非托管内存的指针，或 IntPtr.Zero。</returns>
        public static IntPtr AllocUTF8(string str)
        {
            if (str == null) return IntPtr.Zero;
            byte[] bytes = StringToUTF8Bytes(str);
            IntPtr ptr = Marshal.AllocHGlobal(bytes.Length);
            Marshal.Copy(bytes, 0, ptr, bytes.Length);
            return ptr;
        }

        /// <summary>
        /// 释放由 AllocUTF8 分配的指针。
        /// </summary>
        /// <param name="ptr">要释放的指针。</param>
        public static void FreeUTF8(IntPtr ptr)
        {
            if (ptr != IntPtr.Zero)
                Marshal.FreeHGlobal(ptr);
        }

        /// <summary>
        /// 从 IntPtr 读取以空字符结尾的 UTF-8 字符串并返回托管字符串。
        /// 若 ptr 为 IntPtr.Zero，返回 null。
        /// </summary>
        /// <param name="ptr">指向 UTF-8 字符串的指针。</param>
        /// <returns>托管字符串，或 null。</returns>
        public static string PtrToStringUTF8(IntPtr ptr)
        {
            if (ptr == IntPtr.Zero) return null;
            int len = 0;
            while (Marshal.ReadByte(ptr, len) != 0) len++;
            byte[] bytes = new byte[len];
            Marshal.Copy(ptr, bytes, 0, len);
            return Encoding.UTF8.GetString(bytes);
        }
    }

    /// <summary>
    /// 不透明的数据句柄，包含 API 名称及其关联的二进制载荷。
    /// 用于输入参数和输出结果。
    /// 必须使用 <see cref="API.API_Create_DataHnd"/> 创建，并用 <see cref="API.API_Free_DataHnd"/> 释放。
    /// </summary>
    public struct DataHnd : IEquatable<DataHnd>
    {
        /// <summary>原始句柄指针。</summary>
        public IntPtr Handle;

        /// <summary>指示句柄是否有效（非零）。</summary>
        public bool IsValid => Handle != IntPtr.Zero;

        /// <summary>表示空句柄（零值）。</summary>
        public static readonly DataHnd Null = new DataHnd { Handle = IntPtr.Zero };

        /// <inheritdoc/>
        public override bool Equals(object obj) => obj is DataHnd other && Equals(other);

        /// <inheritdoc/>
        public bool Equals(DataHnd other) => Handle == other.Handle;

        /// <inheritdoc/>
        public override int GetHashCode() => Handle.GetHashCode();

        /// <summary>相等运算符。</summary>
        public static bool operator ==(DataHnd a, DataHnd b) => a.Equals(b);

        /// <summary>不等运算符。</summary>
        public static bool operator !=(DataHnd a, DataHnd b) => !a.Equals(b);
    }

    /// <summary>
    /// 不透明的应用句柄，用于组织一组 API。
    /// 使用 <see cref="API.API_Create_APPHnd"/> 创建，用 <see cref="API.API_Free_APPHnd"/> 释放。
    /// </summary>
    public struct AppHnd : IEquatable<AppHnd>
    {
        /// <summary>原始句柄指针。</summary>
        public IntPtr Handle;

        /// <summary>指示句柄是否有效（非零）。</summary>
        public bool IsValid => Handle != IntPtr.Zero;

        /// <summary>表示空句柄（零值）。</summary>
        public static readonly AppHnd Null = new AppHnd { Handle = IntPtr.Zero };

        /// <inheritdoc/>
        public override bool Equals(object obj) => obj is AppHnd other && Equals(other);

        /// <inheritdoc/>
        public bool Equals(AppHnd other) => Handle == other.Handle;

        /// <inheritdoc/>
        public override int GetHashCode() => Handle.GetHashCode();

        /// <summary>相等运算符。</summary>
        public static bool operator ==(AppHnd a, AppHnd b) => a.Equals(b);

        /// <summary>不等运算符。</summary>
        public static bool operator !=(AppHnd a, AppHnd b) => !a.Equals(b);
    }

    /// <summary>
    /// 请求-响应（Call）API 的回调委托。
    /// 必须使用 <see cref="CallingConvention.Cdecl"/> 调用约定。
    /// </summary>
    /// <param name="trigger">用户数据指针（注册时传入）。</param>
    /// <param name="input">输入数据句柄（只读）。</param>
    /// <param name="output">输出数据句柄（只写）。</param>
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void APICallDelegate(IntPtr trigger, IntPtr input, IntPtr output);

    /// <summary>
    /// 单向通知（Notify）API 的回调委托。
    /// 必须使用 <see cref="CallingConvention.Cdecl"/> 调用约定。
    /// </summary>
    /// <param name="trigger">用户数据指针（注册时传入）。</param>
    /// <param name="input">输入数据句柄（只读）。</param>
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void APINotifyDelegate(IntPtr trigger, IntPtr input);

    /// <summary>
    /// 提供所有 API Hub 函数的静态类。
    /// 通过自定义 DllImport 解析器自动加载动态库。
    /// </summary>
    public static class API
    {
        // 在 DllImport 中使用的逻辑库名；实际文件名由解析器动态决定。
        private const string DllName = "z_api_hub";

        // 静态构造函数：设置自定义 DllImport 解析器。
        static API()
        {
            NativeLibrary.SetDllImportResolver(typeof(API).Assembly, (libraryName, assembly, searchPath) =>
            {
                if (libraryName == DllName)
                {
                    string libName;

                    if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                    {
                        if (IntPtr.Size == 8)
                            libName = "z_api_hub64.dll";
                        else
                            libName = "z_api_hub32.dll";
                    }
                    else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
                    {
                        libName = "libz_api_hub.so";
                    }
                    else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                    {
                        libName = "libz_api_hub.dylib";
                    }
                    else
                    {
                        libName = "libz_api_hub"; // 未知平台，回退到逻辑名
                    }

                    return NativeLibrary.Load(libName, assembly, searchPath);
                }
                return IntPtr.Zero;
            });
        }

        // ---------- 私有原生导入 ----------

        #region 数据句柄操作

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Create_DataHnd")]
        private static extern DataHnd Native_Create_DataHnd(IntPtr apiName);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Free_DataHnd")]
        private static extern void Native_Free_DataHnd(DataHnd hnd);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_GetBuffer")]
        private static extern IntPtr Native_GetBuffer(DataHnd hnd);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_WriteBuffer")]
        private static extern long Native_WriteBuffer(DataHnd hnd, byte[] buffer, long size);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_ReadBuffer")]
        private static extern long Native_ReadBuffer(DataHnd hnd, byte[] buffer, long size);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_GetPos")]
        private static extern long Native_GetPos(DataHnd hnd);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_SetPos")]
        private static extern void Native_SetPos(DataHnd hnd, long pos);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_GetSize")]
        private static extern long Native_GetSize(DataHnd hnd);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_SetSize")]
        private static extern void Native_SetSize(DataHnd hnd, long size);

        /// <summary>
        /// 创建一个新的数据句柄，并用给定的 API 名称初始化。
        /// 句柄的内部缓冲区为空（大小 = 0）。
        /// </summary>
        /// <param name="apiName">目标 API 名称（UTF-8，以空字符结尾）。不能为 null。</param>
        /// <returns>新的 <see cref="DataHnd"/>。必须用 <see cref="API_Free_DataHnd"/> 释放。</returns>
        /// <exception cref="ArgumentNullException">当 <paramref name="apiName"/> 为 null 时抛出。</exception>
        public static DataHnd API_Create_DataHnd(string apiName)
        {
            if (apiName == null)
                throw new ArgumentNullException(nameof(apiName));
            IntPtr ptr = UTF8Marshal.AllocUTF8(apiName);
            try { return Native_Create_DataHnd(ptr); }
            finally { UTF8Marshal.FreeUTF8(ptr); }
        }

        /// <summary>
        /// 销毁数据句柄并释放所有关联资源。
        /// </summary>
        /// <param name="hnd">要释放的数据句柄。</param>
        public static void API_Free_DataHnd(DataHnd hnd) => Native_Free_DataHnd(hnd);

        /// <summary>
        /// 返回指向句柄中原始二进制数据的直接指针（零拷贝访问）。
        /// 指针在句柄释放或缓冲区调整大小前有效。切勿释放此指针。
        /// </summary>
        /// <param name="hnd">数据句柄。</param>
        /// <returns>指向内部缓冲区的指针，若为空则返回 IntPtr.Zero。</returns>
        public static IntPtr API_GetBuffer(DataHnd hnd) => Native_GetBuffer(hnd);

        /// <summary>
        /// 在当前位置向句柄缓冲区写入二进制数据。缓冲区自动扩容，位置后移。
        /// </summary>
        /// <param name="hnd">数据句柄。</param>
        /// <param name="buffer">源数据字节数组。</param>
        /// <param name="size">要写入的字节数。</param>
        /// <returns>实际写入的字节数（通常等于 size）。</returns>
        public static long API_WriteBuffer(DataHnd hnd, byte[] buffer, long size) => Native_WriteBuffer(hnd, buffer, size);

        // --------------------------------------------------------------------
        //  原子写入辅助
        // --------------------------------------------------------------------

        /// <summary>写入 8 位有符号整数（小端序）。</summary>
        public static bool API_WriteInt8(DataHnd hnd, sbyte value)
        {
            byte[] bytes = { unchecked((byte)value) };
            return API_WriteBuffer(hnd, bytes, 1) == 1;
        }

        /// <summary>写入 8 位无符号整数（小端序）。</summary>
        public static bool API_WriteUInt8(DataHnd hnd, byte value)
        {
            byte[] bytes = { value };
            return API_WriteBuffer(hnd, bytes, 1) == 1;
        }

        /// <summary>写入 16 位有符号整数（小端序）。</summary>
        public static bool API_WriteInt16(DataHnd hnd, short value)
        {
            Span<byte> bytes = stackalloc byte[2];
            BinaryPrimitives.WriteInt16LittleEndian(bytes, value);
            return API_WriteBuffer(hnd, bytes.ToArray(), 2) == 2;
        }

        /// <summary>写入 16 位无符号整数（小端序）。</summary>
        public static bool API_WriteUInt16(DataHnd hnd, ushort value)
        {
            Span<byte> bytes = stackalloc byte[2];
            BinaryPrimitives.WriteUInt16LittleEndian(bytes, value);
            return API_WriteBuffer(hnd, bytes.ToArray(), 2) == 2;
        }

        /// <summary>写入 32 位有符号整数（小端序）。</summary>
        public static bool API_WriteInt32(DataHnd hnd, int value)
        {
            Span<byte> bytes = stackalloc byte[4];
            BinaryPrimitives.WriteInt32LittleEndian(bytes, value);
            return API_WriteBuffer(hnd, bytes.ToArray(), 4) == 4;
        }

        /// <summary>写入 32 位无符号整数（小端序）。</summary>
        public static bool API_WriteUInt32(DataHnd hnd, uint value)
        {
            Span<byte> bytes = stackalloc byte[4];
            BinaryPrimitives.WriteUInt32LittleEndian(bytes, value);
            return API_WriteBuffer(hnd, bytes.ToArray(), 4) == 4;
        }

        /// <summary>写入 64 位有符号整数（小端序）。</summary>
        public static bool API_WriteInt64(DataHnd hnd, long value)
        {
            Span<byte> bytes = stackalloc byte[8];
            BinaryPrimitives.WriteInt64LittleEndian(bytes, value);
            return API_WriteBuffer(hnd, bytes.ToArray(), 8) == 8;
        }

        /// <summary>写入 64 位无符号整数（小端序）。</summary>
        public static bool API_WriteUInt64(DataHnd hnd, ulong value)
        {
            Span<byte> bytes = stackalloc byte[8];
            BinaryPrimitives.WriteUInt64LittleEndian(bytes, value);
            return API_WriteBuffer(hnd, bytes.ToArray(), 8) == 8;
        }

        /// <summary>写入 32 位单精度浮点数（小端序 IEEE 754）。</summary>
        public static bool API_WriteSingle(DataHnd hnd, float value)
        {
            Span<byte> bytes = stackalloc byte[4];
            BinaryPrimitives.WriteSingleLittleEndian(bytes, value);
            return API_WriteBuffer(hnd, bytes.ToArray(), 4) == 4;
        }

        /// <summary>写入 64 位双精度浮点数（小端序 IEEE 754）。</summary>
        public static bool API_WriteDouble(DataHnd hnd, double value)
        {
            Span<byte> bytes = stackalloc byte[8];
            BinaryPrimitives.WriteDoubleLittleEndian(bytes, value);
            return API_WriteBuffer(hnd, bytes.ToArray(), 8) == 8;
        }

        /// <summary>
        /// 向缓冲区写入 UTF-8 编码的字符串，后跟一个空终止符（#0）。
        /// </summary>
        /// <param name="hnd">数据句柄。</param>
        /// <param name="value">要写入的字符串。</param>
        /// <returns>成功返回 true，失败返回 false。</returns>
        /// <exception cref="ArgumentNullException">当 <paramref name="value"/> 为 null 时抛出。</exception>
        public static bool API_WriteString(DataHnd hnd, string value)
        {
            if (value == null)
                throw new ArgumentNullException(nameof(value));
            byte[] utf8Bytes = Encoding.UTF8.GetBytes(value);
            long bytesWritten = API_WriteBuffer(hnd, utf8Bytes, utf8Bytes.Length);
            if (bytesWritten != utf8Bytes.Length)
                return false;
            byte[] nullTerm = new byte[1] { 0 };
            return API_WriteBuffer(hnd, nullTerm, 1) == 1;
        }

        // --------------------------------------------------------------------
        //  读取操作
        // --------------------------------------------------------------------

        /// <summary>
        /// 从当前位置读取二进制数据到调用者缓冲区。位置后移。
        /// </summary>
        /// <param name="hnd">数据句柄。</param>
        /// <param name="buffer">目标字节数组。</param>
        /// <param name="size">要读取的最大字节数。</param>
        /// <returns>实际读取的字节数（可能小于 size）。</returns>
        public static long API_ReadBuffer(DataHnd hnd, byte[] buffer, long size) => Native_ReadBuffer(hnd, buffer, size);

        // --------------------------------------------------------------------
        //  原子读取辅助
        // --------------------------------------------------------------------

        /// <summary>读取 8 位有符号整数（小端序）。</summary>
        public static bool API_ReadInt8(DataHnd hnd, out sbyte value)
        {
            byte[] buffer = new byte[1];
            if (API_ReadBuffer(hnd, buffer, 1) != 1)
            {
                value = 0;
                return false;
            }
            value = unchecked((sbyte)buffer[0]);
            return true;
        }

        /// <summary>读取 8 位无符号整数（小端序）。</summary>
        public static bool API_ReadUInt8(DataHnd hnd, out byte value)
        {
            byte[] buffer = new byte[1];
            if (API_ReadBuffer(hnd, buffer, 1) != 1)
            {
                value = 0;
                return false;
            }
            value = buffer[0];
            return true;
        }

        /// <summary>读取 16 位有符号整数（小端序）。</summary>
        public static bool API_ReadInt16(DataHnd hnd, out short value)
        {
            byte[] buffer = new byte[2];
            if (API_ReadBuffer(hnd, buffer, 2) != 2)
            {
                value = 0;
                return false;
            }
            value = BinaryPrimitives.ReadInt16LittleEndian(buffer);
            return true;
        }

        /// <summary>读取 16 位无符号整数（小端序）。</summary>
        public static bool API_ReadUInt16(DataHnd hnd, out ushort value)
        {
            byte[] buffer = new byte[2];
            if (API_ReadBuffer(hnd, buffer, 2) != 2)
            {
                value = 0;
                return false;
            }
            value = BinaryPrimitives.ReadUInt16LittleEndian(buffer);
            return true;
        }

        /// <summary>读取 32 位有符号整数（小端序）。</summary>
        public static bool API_ReadInt32(DataHnd hnd, out int value)
        {
            byte[] buffer = new byte[4];
            if (API_ReadBuffer(hnd, buffer, 4) != 4)
            {
                value = 0;
                return false;
            }
            value = BinaryPrimitives.ReadInt32LittleEndian(buffer);
            return true;
        }

        /// <summary>读取 32 位无符号整数（小端序）。</summary>
        public static bool API_ReadUInt32(DataHnd hnd, out uint value)
        {
            byte[] buffer = new byte[4];
            if (API_ReadBuffer(hnd, buffer, 4) != 4)
            {
                value = 0;
                return false;
            }
            value = BinaryPrimitives.ReadUInt32LittleEndian(buffer);
            return true;
        }

        /// <summary>读取 64 位有符号整数（小端序）。</summary>
        public static bool API_ReadInt64(DataHnd hnd, out long value)
        {
            byte[] buffer = new byte[8];
            if (API_ReadBuffer(hnd, buffer, 8) != 8)
            {
                value = 0;
                return false;
            }
            value = BinaryPrimitives.ReadInt64LittleEndian(buffer);
            return true;
        }

        /// <summary>读取 64 位无符号整数（小端序）。</summary>
        public static bool API_ReadUInt64(DataHnd hnd, out ulong value)
        {
            byte[] buffer = new byte[8];
            if (API_ReadBuffer(hnd, buffer, 8) != 8)
            {
                value = 0;
                return false;
            }
            value = BinaryPrimitives.ReadUInt64LittleEndian(buffer);
            return true;
        }

        /// <summary>读取 32 位单精度浮点数（小端序 IEEE 754）。</summary>
        public static bool API_ReadSingle(DataHnd hnd, out float value)
        {
            byte[] buffer = new byte[4];
            if (API_ReadBuffer(hnd, buffer, 4) != 4)
            {
                value = 0;
                return false;
            }
            value = BinaryPrimitives.ReadSingleLittleEndian(buffer);
            return true;
        }

        /// <summary>读取 64 位双精度浮点数（小端序 IEEE 754）。</summary>
        public static bool API_ReadDouble(DataHnd hnd, out double value)
        {
            byte[] buffer = new byte[8];
            if (API_ReadBuffer(hnd, buffer, 8) != 8)
            {
                value = 0;
                return false;
            }
            value = BinaryPrimitives.ReadDoubleLittleEndian(buffer);
            return true;
        }

        /// <summary>
        /// 从当前位置读取一个以空字符结尾的 UTF-8 字符串。
        /// 位置会移到终止空字节之后。
        /// </summary>
        /// <param name="hnd">数据句柄。</param>
        /// <param name="value">输出字符串。</param>
        /// <returns>如果找到空终止符则返回 true；如果到达缓冲区末尾则返回 false。</returns>
        public static bool API_ReadString(DataHnd hnd, out string value)
        {
            long startPos = API_GetPos(hnd);
            long size = API_GetSize(hnd);
            if (startPos >= size)
            {
                value = string.Empty;
                return false;
            }

            IntPtr buffer = API_GetBuffer(hnd);
            if (buffer == IntPtr.Zero)
            {
                value = string.Empty;
                return false;
            }

            // 从 startPos 开始扫描，直到找到空字节或到达末尾。
            long nullPos = startPos;
            while (nullPos < size)
            {
                if (Marshal.ReadByte(buffer, (int)nullPos) == 0)
                    break;
                nullPos++;
            }

            if (nullPos >= size)
            {
                value = string.Empty;
                return false;
            }

            int byteLen = (int)(nullPos - startPos);
            byte[] utf8Bytes = new byte[byteLen];
            Marshal.Copy(buffer + (int)startPos, utf8Bytes, 0, byteLen);

            // 将位置移到空终止符之后
            API_SetPos(hnd, nullPos + 1);

            value = Encoding.UTF8.GetString(utf8Bytes);
            return true;
        }

        /// <summary>
        /// 从当前位置读取一个以空字符结尾的 UTF-8 字符串。
        /// 如果未找到空终止符，返回空字符串。
        /// </summary>
        /// <param name="hnd">数据句柄。</param>
        /// <returns>读取的字符串，或空字符串。</returns>
        public static string API_ReadString(DataHnd hnd)
        {
            API_ReadString(hnd, out string value);
            return value;
        }

        // --------------------------------------------------------------------
        //  位置和大小
        // --------------------------------------------------------------------

        /// <summary>获取当前读写位置（字节偏移，从 0 开始）。</summary>
        public static long API_GetPos(DataHnd hnd) => Native_GetPos(hnd);

        /// <summary>设置当前读写位置。若超出大小，缓冲区扩展并填充零。</summary>
        public static void API_SetPos(DataHnd hnd, long pos) => Native_SetPos(hnd, pos);

        /// <summary>获取缓冲区总大小（字节）。</summary>
        public static long API_GetSize(DataHnd hnd) => Native_GetSize(hnd);

        /// <summary>调整缓冲区大小（截断或扩展）。</summary>
        public static void API_SetSize(DataHnd hnd, long size) => Native_SetSize(hnd, size);

        #endregion

        #region 应用句柄操作

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Create_APPHnd")]
        private static extern AppHnd Native_Create_APPHnd(IntPtr appName, IntPtr desc);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Free_APPHnd")]
        private static extern void Native_Free_APPHnd(AppHnd appHnd);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Reg_Call")]
        private static extern int Native_Reg_Call(AppHnd appHnd, IntPtr apiName, IntPtr desc, IntPtr trigger, APICallDelegate onCall);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Reg_Notify")]
        private static extern int Native_Reg_Notify(AppHnd appHnd, IntPtr apiName, IntPtr desc, IntPtr trigger, APINotifyDelegate onNotify);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_UnReg")]
        private static extern int Native_UnReg(AppHnd appHnd, IntPtr apiName);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Local_APP_Call")]
        private static extern DataHnd Native_Local_APP_Call(AppHnd appHnd, DataHnd param);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Local_APP_Notify")]
        private static extern void Native_Local_APP_Notify(AppHnd appHnd, DataHnd param);

        /// <summary>
        /// 创建一个新的应用上下文，具有唯一名称和可选描述。
        /// </summary>
        /// <param name="appName">应用名称（UTF-8，区分大小写，网络中唯一）。不能为 null。</param>
        /// <param name="desc">描述信息（UTF-8，可为空）。</param>
        /// <returns>新的 <see cref="AppHnd"/>，必须用 <see cref="API_Free_APPHnd"/> 释放。</returns>
        /// <exception cref="ArgumentNullException">当 <paramref name="appName"/> 为 null 时抛出。</exception>
        public static AppHnd API_Create_APPHnd(string appName, string desc)
        {
            if (appName == null)
                throw new ArgumentNullException(nameof(appName));
            IntPtr pName = UTF8Marshal.AllocUTF8(appName);
            IntPtr pDesc = UTF8Marshal.AllocUTF8(desc);
            try { return Native_Create_APPHnd(pName, pDesc); }
            finally { UTF8Marshal.FreeUTF8(pName); UTF8Marshal.FreeUTF8(pDesc); }
        }

        /// <summary>
        /// 销毁应用句柄，释放所有已注册 API 及关联资源。
        /// </summary>
        /// <param name="appHnd">要释放的应用句柄。</param>
        public static void API_Free_APPHnd(AppHnd appHnd) => Native_Free_APPHnd(appHnd);

        /// <summary>
        /// 在应用中注册一个请求-响应（Call）API。
        /// 回调将在后台线程池中执行（非 UI 线程）。
        /// </summary>
        /// <param name="appHnd">应用句柄。</param>
        /// <param name="apiName">API 名称（UTF-8，应用内唯一）。</param>
        /// <param name="desc">描述（UTF-8，可为空）。</param>
        /// <param name="trigger">用户数据指针，回调时原样传回。</param>
        /// <param name="onCall">回调委托（必须使用 Cdecl 调用约定）。</param>
        /// <returns>1 成功，0 失败（名称已存在）。</returns>
        /// <exception cref="ArgumentNullException">当 <paramref name="apiName"/> 为 null 时抛出。</exception>
        public static int API_Reg_Call(AppHnd appHnd, string apiName, string desc, IntPtr trigger, APICallDelegate onCall)
        {
            if (apiName == null)
                throw new ArgumentNullException(nameof(apiName));
            IntPtr pName = UTF8Marshal.AllocUTF8(apiName);
            IntPtr pDesc = UTF8Marshal.AllocUTF8(desc);
            try { return Native_Reg_Call(appHnd, pName, pDesc, trigger, onCall); }
            finally { UTF8Marshal.FreeUTF8(pName); UTF8Marshal.FreeUTF8(pDesc); }
        }

        /// <summary>
        /// 在应用中注册一个单向通知（Notify）API。
        /// 回调将在后台线程池中执行（非 UI 线程）。
        /// </summary>
        /// <param name="appHnd">应用句柄。</param>
        /// <param name="apiName">API 名称（UTF-8，应用内唯一）。</param>
        /// <param name="desc">描述（UTF-8，可为空）。</param>
        /// <param name="trigger">用户数据指针。</param>
        /// <param name="onNotify">回调委托（必须使用 Cdecl 调用约定）。</param>
        /// <returns>1 成功，0 失败（名称已存在）。</returns>
        /// <exception cref="ArgumentNullException">当 <paramref name="apiName"/> 为 null 时抛出。</exception>
        public static int API_Reg_Notify(AppHnd appHnd, string apiName, string desc, IntPtr trigger, APINotifyDelegate onNotify)
        {
            if (apiName == null)
                throw new ArgumentNullException(nameof(apiName));
            IntPtr pName = UTF8Marshal.AllocUTF8(apiName);
            IntPtr pDesc = UTF8Marshal.AllocUTF8(desc);
            try { return Native_Reg_Notify(appHnd, pName, pDesc, trigger, onNotify); }
            finally { UTF8Marshal.FreeUTF8(pName); UTF8Marshal.FreeUTF8(pDesc); }
        }

        /// <summary>
        /// 从应用中注销先前注册的 API。
        /// 本地立即生效，网络广播约 3 秒传播。
        /// </summary>
        /// <param name="appHnd">应用句柄。</param>
        /// <param name="apiName">要注销的 API 名称（UTF-8）。</param>
        /// <returns>1 成功（API 已移除），0 失败（名称不存在）。</returns>
        /// <exception cref="ArgumentNullException">当 <paramref name="apiName"/> 为 null 时抛出。</exception>
        public static int API_UnReg(AppHnd appHnd, string apiName)
        {
            if (apiName == null)
                throw new ArgumentNullException(nameof(apiName));
            IntPtr pName = UTF8Marshal.AllocUTF8(apiName);
            try { return Native_UnReg(appHnd, pName); }
            finally { UTF8Marshal.FreeUTF8(pName); }
        }

        /// <summary>
        /// 在本地同步执行 Call API（绕过网络）。用于单元测试或内部调用。
        /// </summary>
        /// <param name="appHnd">应用句柄。</param>
        /// <param name="param">输入数据句柄（不会被释放）。</param>
        /// <returns>新的结果数据句柄（必须释放），失败时大小为 0。</returns>
        public static DataHnd API_Local_APP_Call(AppHnd appHnd, DataHnd param) => Native_Local_APP_Call(appHnd, param);

        /// <summary>
        /// 在本地发送通知（无返回）。
        /// </summary>
        /// <param name="appHnd">应用句柄。</param>
        /// <param name="param">输入数据句柄（不会被释放）。</param>
        public static void API_Local_APP_Notify(AppHnd appHnd, DataHnd param) => Native_Local_APP_Notify(appHnd, param);

        #endregion

        #region 网络准备与通信

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Prepare_Service")]
        private static extern int Native_Prepare_Service(IntPtr listeningAddr, IntPtr physicsAddr);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Prepare_Client")]
        private static extern int Native_Prepare_Client(IntPtr physicsAddr, AppHnd appHnd);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Reset_Prepare")]
        private static extern void Native_Reset_Prepare();

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Prepare_Done")]
        private static extern int Native_Prepare_Done();

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Exit_MainThread")]
        private static extern void Native_Exit_MainThread();

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Call")]
        private static extern DataHnd Native_Call(IntPtr appName, DataHnd param, ulong timeout);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Notify")]
        private static extern void Native_Notify(IntPtr appName, DataHnd param);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_SetOption")]
        private static extern void Native_SetOption(IntPtr option, IntPtr value);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_shutdown")]
        private static extern void Native_shutdown();

        // ---------- 新增的导出函数 ----------

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Check_MainThread")]
        private static extern int Native_Check_MainThread();

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Check_App")]
        private static extern int Native_Check_App(IntPtr appName);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Get_Status_Num")]
        private static extern int Native_Get_Status_Num();

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Get_Status")]
        private static extern IntPtr Native_Get_Status();

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, EntryPoint = "API_Post_Status")]
        private static extern void Native_Post_Status(IntPtr status);

        /// <summary>
        /// 准备一个服务监听器（可多次调用以启动多个服务）。
        /// 可在 <see cref="API_Prepare_Done"/> 前后调用。
        /// </summary>
        /// <param name="listeningAddr">本地绑定地址（UTF-8），如 "0.0.0.0:9898" 或 "ipc:my_service"。</param>
        /// <param name="physicsAddr">对外公布的地址（UTF-8），客户端将连接到此地址。</param>
        /// <returns>内部标签（可忽略），重复准备返回 -1。</returns>
        /// <exception cref="ArgumentNullException">当任一参数为 null 时抛出。</exception>
        public static int API_Prepare_Service(string listeningAddr, string physicsAddr)
        {
            if (listeningAddr == null)
                throw new ArgumentNullException(nameof(listeningAddr));
            if (physicsAddr == null)
                throw new ArgumentNullException(nameof(physicsAddr));
            IntPtr pListen = UTF8Marshal.AllocUTF8(listeningAddr);
            IntPtr pPhysics = UTF8Marshal.AllocUTF8(physicsAddr);
            try { return Native_Prepare_Service(pListen, pPhysics); }
            finally { UTF8Marshal.FreeUTF8(pListen); UTF8Marshal.FreeUTF8(pPhysics); }
        }

        /// <summary>
        /// 准备一个客户端连接。若提供应用句柄，则自动将该应用注册到服务网格。
        /// 可在 <see cref="API_Prepare_Done"/> 前后调用。
        /// </summary>
        /// <param name="physicsAddr">远程服务地址（UTF-8），必须与服务的公布地址一致。</param>
        /// <param name="appHnd">可选应用句柄（若提供则暴露此应用，否则纯消费）。</param>
        /// <returns>内部标签（可忽略），重复准备返回 -1。</returns>
        /// <exception cref="ArgumentNullException">当 <paramref name="physicsAddr"/> 为 null 时抛出。</exception>
        public static int API_Prepare_Client(string physicsAddr, AppHnd appHnd)
        {
            if (physicsAddr == null)
                throw new ArgumentNullException(nameof(physicsAddr));
            IntPtr pPhysics = UTF8Marshal.AllocUTF8(physicsAddr);
            try { return Native_Prepare_Client(pPhysics, appHnd); }
            finally { UTF8Marshal.FreeUTF8(pPhysics); }
        }

        /// <summary>
        /// 清除所有已准备的服务/客户端配置。重新配置前调用。
        /// </summary>
        public static void API_Reset_Prepare() => Native_Reset_Prepare();

        /// <summary>
        /// 启动 C4 网络框架，阻塞直到所有准备的服务/客户端初始化完成。
        /// 之后可进行远程调用。
        /// </summary>
        /// <returns>1 成功，0 失败（错误信息输出到控制台）。</returns>
        public static int API_Prepare_Done() => Native_Prepare_Done();

        /// <summary>
        /// 通知内部事件循环退出，停止网络处理。通常后接 <see cref="API_shutdown"/>。
        /// </summary>
        public static void API_Exit_MainThread() => Native_Exit_MainThread();

        /// <summary>
        /// 同步远程调用（或本地优化）。阻塞直到收到响应或超时。
        /// </summary>
        /// <param name="appName">目标应用名（UTF-8）。</param>
        /// <param name="param">输入数据句柄（内部克隆，调用者仍需释放原句柄）。</param>
        /// <param name="timeout">超时毫秒数，0 表示无限等待。</param>
        /// <returns>新的结果数据句柄（必须释放），失败时大小为 0。</returns>
        /// <exception cref="ArgumentNullException">当 <paramref name="appName"/> 为 null 时抛出。</exception>
        public static DataHnd API_Call(string appName, DataHnd param, ulong timeout)
        {
            if (appName == null)
                throw new ArgumentNullException(nameof(appName));
            IntPtr pName = UTF8Marshal.AllocUTF8(appName);
            try { return Native_Call(pName, param, timeout); }
            finally { UTF8Marshal.FreeUTF8(pName); }
        }

        /// <summary>
        /// 单向通知（fire-and-forget），不等待响应。
        /// </summary>
        /// <param name="appName">目标应用名（UTF-8）。</param>
        /// <param name="param">输入数据句柄（调用者仍需负责释放）。</param>
        /// <exception cref="ArgumentNullException">当 <paramref name="appName"/> 为 null 时抛出。</exception>
        public static void API_Notify(string appName, DataHnd param)
        {
            if (appName == null)
                throw new ArgumentNullException(nameof(appName));
            IntPtr pName = UTF8Marshal.AllocUTF8(appName);
            try { Native_Notify(pName, param); }
            finally { UTF8Marshal.FreeUTF8(pName); }
        }

        /// <summary>
        /// 动态调整全局运行时配置，无需重启。
        /// </summary>
        /// <param name="option">配置键（UTF-8，不区分大小写）。</param>
        /// <param name="value">新值（UTF-8）。布尔值接受 True/False, 1/0, Yes/No。</param>
        /// <exception cref="ArgumentNullException">当任一参数为 null 时抛出。</exception>
        public static void API_SetOption(string option, string value)
        {
            if (option == null)
                throw new ArgumentNullException(nameof(option));
            if (value == null)
                throw new ArgumentNullException(nameof(value));
            IntPtr pOption = UTF8Marshal.AllocUTF8(option);
            IntPtr pValue = UTF8Marshal.AllocUTF8(value);
            try { Native_SetOption(pOption, pValue); }
            finally { UTF8Marshal.FreeUTF8(pOption); UTF8Marshal.FreeUTF8(pValue); }
        }

        /// <summary>
        /// 完全关闭框架，停止所有服务、断开客户端、释放资源。
        /// 建议先调用 <see cref="API_Exit_MainThread"/>，再调用本方法。
        /// </summary>
        public static void API_shutdown() => Native_shutdown();

        // ---------- 新增的公共状态和检查 API ----------

        /// <summary>
        /// 检查模拟主线程（C4 事件循环）当前是否正在运行。
        /// </summary>
        /// <returns>1 表示运行中，0 表示已停止或未启动。</returns>
        public static int API_Check_MainThread() => Native_Check_MainThread();

        /// <summary>
        /// 检查网络上是否存在具有给定名称的应用。
        /// 此查询基于本地缓存，可能略有滞后。
        /// </summary>
        /// <param name="appName">应用名称（UTF-8，区分大小写）。</param>
        /// <returns>1 表示至少存在一个实例，0 表示不存在。</returns>
        /// <exception cref="ArgumentNullException">当 <paramref name="appName"/> 为 null 时抛出。</exception>
        public static int API_Check_App(string appName)
        {
            if (appName == null)
                throw new ArgumentNullException(nameof(appName));
            IntPtr pName = UTF8Marshal.AllocUTF8(appName);
            try { return Native_Check_App(pName); }
            finally { UTF8Marshal.FreeUTF8(pName); }
        }

        /// <summary>
        /// 返回内部状态队列中待处理的日志消息数量（FIFO，最多 1000 条）。
        /// </summary>
        public static int API_Get_Status_Num() => Native_Get_Status_Num();

        /// <summary>
        /// 从状态队列中取出下一条日志消息（FIFO 顺序）。
        /// 消息为 UTF-8 编码并以空字符结尾。返回的字符串是内部缓冲区的副本，后续调用仍有效。
        /// </summary>
        /// <returns>下一条状态消息，如果队列为空则返回空字符串。</returns>
        public static string API_Get_Status()
        {
            IntPtr ptr = Native_Get_Status();
            if (ptr == IntPtr.Zero)
                return string.Empty;
            return UTF8Marshal.PtrToStringUTF8(ptr) ?? string.Empty;
        }

        /// <summary>
        /// 向内部状态队列注入一条自定义日志消息。
        /// </summary>
        /// <param name="status">要添加的消息（UTF-8）。</param>
        /// <exception cref="ArgumentNullException">当 <paramref name="status"/> 为 null 时抛出。</exception>
        public static void API_Post_Status(string status)
        {
            if (status == null)
                throw new ArgumentNullException(nameof(status));
            IntPtr pStatus = UTF8Marshal.AllocUTF8(status);
            try { Native_Post_Status(pStatus); }
            finally { UTF8Marshal.FreeUTF8(pStatus); }
        }

        #endregion

        #region 便利辅助方法

        /// <summary>
        /// 读取数据句柄的全部内容并返回字节数组。
        /// </summary>
        /// <param name="hnd">数据句柄。</param>
        /// <returns>包含所有数据的字节数组。</returns>
        public static byte[] ReadAllBytes(DataHnd hnd)
        {
            long size = API_GetSize(hnd);
            if (size <= 0)
                return Array.Empty<byte>();
            byte[] buffer = new byte[size];
            API_SetPos(hnd, 0);
            long read = API_ReadBuffer(hnd, buffer, size);
            if (read != size)
                Array.Resize(ref buffer, (int)read);
            return buffer;
        }

        /// <summary>
        /// 将字节数组写入数据句柄（从当前位置开始）。
        /// </summary>
        /// <param name="hnd">数据句柄。</param>
        /// <param name="data">要写入的字节数组。</param>
        /// <returns>实际写入的字节数。</returns>
        public static long WriteBytes(DataHnd hnd, byte[] data)
        {
            return API_WriteBuffer(hnd, data, data.Length);
        }

        /// <summary>
        /// 读取数据句柄中的 UTF-8 字符串（直到空终止符）。
        /// </summary>
        /// <param name="hnd">数据句柄。</param>
        /// <returns>读取的字符串。</returns>
        public static string ReadString(DataHnd hnd)
        {
            byte[] bytes = ReadAllBytes(hnd);
            int len = Array.IndexOf(bytes, (byte)0);
            if (len < 0) len = bytes.Length;
            return Encoding.UTF8.GetString(bytes, 0, len);
        }

        /// <summary>
        /// 将 UTF-8 字符串写入数据句柄（自动追加空终止符）。
        /// </summary>
        /// <param name="hnd">数据句柄。</param>
        /// <param name="str">要写入的字符串。</param>
        /// <exception cref="ArgumentNullException">当 <paramref name="str"/> 为 null 时抛出。</exception>
        public static void WriteString(DataHnd hnd, string str)
        {
            if (str == null)
                throw new ArgumentNullException(nameof(str));
            byte[] bytes = Encoding.UTF8.GetBytes(str);
            byte[] nullTerminated = new byte[bytes.Length + 1];
            Array.Copy(bytes, 0, nullTerminated, 0, bytes.Length);
            nullTerminated[bytes.Length] = 0;
            WriteBytes(hnd, nullTerminated);
        }

        #endregion

        // =========================================================================
        //  新增：同步回调注册机制（用于 UI 主线程安全调用）
        // =========================================================================

        #region 同步回调注册机制（新增）

        // 内部同步任务队列（线程安全），用于存放待执行的用户回调
        private static readonly ConcurrentQueue<Action> _syncQueue = new ConcurrentQueue<Action>();

        /// <summary>
        /// 将 Action 入队到同步队列。此方法由桥接委托调用，线程安全。
        /// </summary>
        private static void EnqueueSyncAction(Action action)
        {
            if (action == null) return;
            _syncQueue.Enqueue(action);
        }

        /// <summary>
        /// 创建一个桥接委托，用于将用户回调包装为同步执行。
        /// 该桥接委托在 C 线程池触发时，会创建一个 ManualResetEvent，
        /// 将用户回调入队，然后阻塞等待该事件，直到主线程执行完回调后设置事件。
        /// 
        /// 【关键修复说明】
        /// 早期实现仅将回调入队即返回，导致底层 C 库在桥接返回后立即释放或重用
        /// input/output 句柄，用户回调后续访问时发生 Access Violation 崩溃。
        /// 修复方案为：桥接委托必须阻塞等待用户回调实际执行完毕，保证句柄在
        /// 整个回调期间有效。这完全复刻了 Pascal 绑定中 TSoft_Synchronize_Tool
        /// 的同步等待语义。
        /// 
        /// 【性能影响】
        /// 此机制会增加主线程负担，回调执行期间会阻塞后台线程，因此不适合
        /// 高吞吐或低延迟场景。仅建议在需要操作 UI 等主线程资源的回调中使用。
        /// </summary>
        private static APICallDelegate CreateSyncCallBridge(APICallDelegate userDelegate)
        {
            return (trigger, input, output) =>
            {
                // 创建等待事件，用于同步等待主线程执行完成
                using (var mre = new ManualResetEvent(false))
                {
                    // 将用户回调包装为 Action 并入队
                    EnqueueSyncAction(() =>
                    {
                        try
                        {
                            // 执行用户回调（此时 input/output 仍有效）
                            userDelegate(trigger, input, output);
                        }
                        finally
                        {
                            // 无论成功或异常，都唤醒等待的桥接线程
                            mre.Set();
                        }
                    });

                    // 阻塞当前线程（C 线程池线程），直到主线程执行完回调并设置事件
                    mre.WaitOne();
                }
                // 此处桥接委托返回，此时用户回调已经执行完毕，句柄可以被安全释放
            };
        }

        /// <summary>
        /// 创建桥接委托（Notify 版本），同样采用阻塞等待机制。
        /// </summary>
        private static APINotifyDelegate CreateSyncNotifyBridge(APINotifyDelegate userDelegate)
        {
            return (trigger, input) =>
            {
                using (var mre = new ManualResetEvent(false))
                {
                    EnqueueSyncAction(() =>
                    {
                        try
                        {
                            userDelegate(trigger, input);
                        }
                        finally
                        {
                            mre.Set();
                        }
                    });
                    mre.WaitOne();
                }
            };
        }

        /// <summary>
        /// 注册一个 Call 模式的 API，其回调将在主线程（UI 线程）中执行。
        /// 使用时必须定期调用 <see cref="ProcessSyncQueue"/> 来驱动队列。
        /// 
        /// 内部实现：用户回调被桥接委托包装，桥接委托会阻塞等待用户回调执行完毕，
        /// 确保 input/output 句柄在回调期间有效，避免因句柄提前释放导致的崩溃。
        /// </summary>
        /// <param name="appHnd">应用句柄。</param>
        /// <param name="apiName">API 名称（UTF-8）。</param>
        /// <param name="desc">描述（可为空）。</param>
        /// <param name="trigger">用户数据指针，回调时原样传回。</param>
        /// <param name="onCall">业务回调委托（将在主线程执行）。</param>
        /// <returns>1 成功，0 失败（名称已存在）。</returns>
        /// <exception cref="ArgumentNullException">当 apiName 或 onCall 为 null 时抛出。</exception>
        public static int API_Reg_Call_Sync(AppHnd appHnd, string apiName, string desc,
                                              IntPtr trigger, APICallDelegate onCall)
        {
            if (apiName == null)
                throw new ArgumentNullException(nameof(apiName));
            if (onCall == null)
                throw new ArgumentNullException(nameof(onCall));

            // 创建桥接委托并注册
            var bridge = CreateSyncCallBridge(onCall);
            return API_Reg_Call(appHnd, apiName, desc, trigger, bridge);
        }

        /// <summary>
        /// 注册一个 Call 模式的 API（不带 trigger 参数的重载）。
        /// </summary>
        public static int API_Reg_Call_Sync(AppHnd appHnd, string apiName, string desc,
                                              APICallDelegate onCall)
        {
            return API_Reg_Call_Sync(appHnd, apiName, desc, IntPtr.Zero, onCall);
        }

        /// <summary>
        /// 注册一个 Notify 模式的 API，其回调将在主线程（UI 线程）中执行。
        /// </summary>
        /// <param name="appHnd">应用句柄。</param>
        /// <param name="apiName">API 名称（UTF-8）。</param>
        /// <param name="desc">描述（可为空）。</param>
        /// <param name="trigger">用户数据指针。</param>
        /// <param name="onNotify">业务回调委托（将在主线程执行）。</param>
        /// <returns>1 成功，0 失败（名称已存在）。</returns>
        /// <exception cref="ArgumentNullException">当 apiName 或 onNotify 为 null 时抛出。</exception>
        public static int API_Reg_Notify_Sync(AppHnd appHnd, string apiName, string desc,
                                                IntPtr trigger, APINotifyDelegate onNotify)
        {
            if (apiName == null)
                throw new ArgumentNullException(nameof(apiName));
            if (onNotify == null)
                throw new ArgumentNullException(nameof(onNotify));

            var bridge = CreateSyncNotifyBridge(onNotify);
            return API_Reg_Notify(appHnd, apiName, desc, trigger, bridge);
        }

        /// <summary>
        /// 注册一个 Notify 模式的 API（不带 trigger 参数的重载）。
        /// </summary>
        public static int API_Reg_Notify_Sync(AppHnd appHnd, string apiName, string desc,
                                                APINotifyDelegate onNotify)
        {
            return API_Reg_Notify_Sync(appHnd, apiName, desc, IntPtr.Zero, onNotify);
        }

        /// <summary>
        /// 处理同步队列中的所有待执行任务。
        /// 此方法应由主线程（UI 线程）定期调用，例如通过定时器或 Application.Idle 事件。
        /// 它会按入队顺序依次执行所有回调。
        /// 单个回调中的异常会被捕获并输出到调试输出，不会影响后续回调。
        /// 
        /// 【驱动机制】
        /// 每个同步回调被入队时，其关联的 ManualResetEvent 处于未设置状态，
        /// 导致调用桥接的后台线程阻塞。主线程调用此方法，从队列中取出 Action
        /// 并执行，执行完毕后 Action 内部会设置事件，从而唤醒阻塞的后台线程。
        /// 这样保证了 input/output 句柄的生命周期安全。
        /// </summary>
        public static void ProcessSyncQueue()
        {
            while (_syncQueue.TryDequeue(out Action action))
            {
                try
                {
                    action();
                }
                catch (Exception ex)
                {
                    // 捕获异常并输出，避免单个任务导致队列处理中断
                    Debug.WriteLine($"同步回调执行异常: {ex.Message}");
                    Debug.WriteLine(ex.StackTrace);
                }
            }
        }

        #endregion 同步回调注册机制
    }
}