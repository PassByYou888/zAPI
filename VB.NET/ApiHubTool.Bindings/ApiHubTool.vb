Imports System
Imports System.Runtime.InteropServices
Imports System.Text

''' <summary>
''' 不透明数据句柄，持有 API 名称及其二进制载荷。
''' 必须使用 <see cref="API.API_Create_DataHnd"/> 创建，并使用 <see cref="API.API_Free_DataHnd"/> 释放。
''' </summary>
Public Structure DataHnd
    Public Handle As IntPtr

    Public ReadOnly Property IsValid As Boolean
        Get
            Return Handle <> IntPtr.Zero
        End Get
    End Property

    Public Shared ReadOnly Null As DataHnd = New DataHnd With {.Handle = IntPtr.Zero}

    Public Overrides Function Equals(obj As Object) As Boolean
        Return TypeOf obj Is DataHnd AndAlso DirectCast(obj, DataHnd).Handle = Handle
    End Function

    Public Overrides Function GetHashCode() As Integer
        Return Handle.GetHashCode()
    End Function

    Public Shared Operator =(left As DataHnd, right As DataHnd) As Boolean
        Return left.Handle = right.Handle
    End Operator

    Public Shared Operator <>(left As DataHnd, right As DataHnd) As Boolean
        Return Not (left = right)
    End Operator
End Structure

''' <summary>
''' 不透明应用句柄，用于分组一组 API。
''' 必须使用 <see cref="API.API_Create_APPHnd"/> 创建，并使用 <see cref="API.API_Free_APPHnd"/> 释放。
''' </summary>
Public Structure AppHnd
    Public Handle As IntPtr

    Public ReadOnly Property IsValid As Boolean
        Get
            Return Handle <> IntPtr.Zero
        End Get
    End Property

    Public Shared ReadOnly Null As AppHnd = New AppHnd With {.Handle = IntPtr.Zero}

    Public Overrides Function Equals(obj As Object) As Boolean
        Return TypeOf obj Is AppHnd AndAlso DirectCast(obj, AppHnd).Handle = Handle
    End Function

    Public Overrides Function GetHashCode() As Integer
        Return Handle.GetHashCode()
    End Function

    Public Shared Operator =(left As AppHnd, right As AppHnd) As Boolean
        Return left.Handle = right.Handle
    End Operator

    Public Shared Operator <>(left As AppHnd, right As AppHnd) As Boolean
        Return Not (left = right)
    End Operator
End Structure

''' <summary>
''' 请求‑响应（Call）API 的回调委托。
''' 回调在后台线程池中执行 —— 禁止阻塞，禁止在内部调用 API_Call/API_Notify。
''' </summary>
''' <param name="trigger">注册时传入的用户数据指针。</param>
''' <param name="input">只读的输入句柄（禁止释放）。</param>
''' <param name="output">只写的输出句柄，用于写入响应（禁止释放）。</param>
<UnmanagedFunctionPointer(CallingConvention.Cdecl)>
Public Delegate Sub APICallDelegate(trigger As IntPtr, input As IntPtr, output As IntPtr)

''' <summary>
''' 单向通知（Notify）API 的回调委托。
''' 线程与安全约束同 <see cref="APICallDelegate"/>。
''' </summary>
<UnmanagedFunctionPointer(CallingConvention.Cdecl)>
Public Delegate Sub APINotifyDelegate(trigger As IntPtr, input As IntPtr)

''' <summary>
''' 提供所有 API Hub 函数的静态类。
''' 动态库通过自定义 DllImport 解析器自动加载。
''' <para>所有字符串参数均以 UTF‑8 编码封送（使用 <see cref="UnmanagedType.LPUTF8Str"/>）。</para>
''' <para>所有导出函数均为<b>线程安全</b>，可并发调用。</para>
''' <para>通过 <see cref="API_Reg_Call"/> 和 <see cref="API_Reg_Notify"/> 注册的回调在后台线程池中执行，
''' 禁止阻塞，禁止调用 API_Call/API_Notify（有死锁风险），耗时任务应分流到独立线程。</para>
''' <para>动态注销（<see cref="API_UnReg"/>）会立即从本地移除 API，并触发异步网络广播（传播约 3 秒）。</para>
''' </summary>
Public NotInheritable Class API

    Private Const DllName As String = "z_api_hub"

    Shared Sub New()
        NativeLibrary.SetDllImportResolver(GetType(API).Assembly,
                Function(libraryName, assembly, searchPath)
                    If libraryName = DllName Then
                        Dim libName As String
                        If RuntimeInformation.IsOSPlatform(OSPlatform.Windows) Then
                            libName = If(IntPtr.Size = 8, "z_api_hub64.dll", "z_api_hub32.dll")
                        ElseIf RuntimeInformation.IsOSPlatform(OSPlatform.Linux) Then
                            libName = "libz_api_hub.so"
                        ElseIf RuntimeInformation.IsOSPlatform(OSPlatform.OSX) Then
                            libName = "libz_api_hub.dylib"
                        Else
                            libName = "libz_api_hub"
                        End If
                        Return NativeLibrary.Load(libName, assembly, searchPath)
                    End If
                    Return IntPtr.Zero
                End Function)
    End Sub

    ' ======================================================================
    ' 数据句柄操作
    ' ======================================================================

    ''' <summary>
    ''' 使用给定的 API 名称创建数据句柄。
    ''' 内部载荷初始为空（大小 = 0）。
    ''' </summary>
    ''' <param name="apiName">目标 API 名称（UTF‑8）。</param>
    ''' <returns>新的 <see cref="DataHnd"/>；必须使用 <see cref="API_Free_DataHnd"/> 释放。</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Create_DataHnd(<MarshalAs(UnmanagedType.LPUTF8Str)> apiName As String) As DataHnd
    End Function

    ''' <summary>
    ''' 销毁数据句柄，释放所有资源。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_Free_DataHnd(hnd As DataHnd)
    End Sub

    ''' <summary>
    ''' 返回内部缓冲区的直接指针（零拷贝访问）。
    ''' 不要释放此指针，由库管理。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_GetBuffer(hnd As DataHnd) As IntPtr
    End Function

    ''' <summary>
    ''' 在当前位置写入二进制数据。缓冲区会自动扩容。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_WriteBuffer(hnd As DataHnd, buffer As Byte(), size As Long) As Long
    End Function

    ''' <summary>
    ''' 从当前位置读取二进制数据到提供的缓冲区。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_ReadBuffer(hnd As DataHnd, buffer As Byte(), size As Long) As Long
    End Function

    ''' <summary>
    ''' 返回当前读写位置（字节偏移）。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_GetPos(hnd As DataHnd) As Long
    End Function

    ''' <summary>
    ''' 设置当前读写位置。若超出当前大小，则用零扩展缓冲区。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_SetPos(hnd As DataHnd, pos As Long)
    End Sub

    ''' <summary>
    ''' 返回载荷的总大小（字节）。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_GetSize(hnd As DataHnd) As Long
    End Function

    ''' <summary>
    ''' 调整内部缓冲区大小。若缩小则截断，若扩大则未初始化。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_SetSize(hnd As DataHnd, size As Long)
    End Sub

    ' ======================================================================
    ' 应用句柄操作
    ' ======================================================================

    ''' <summary>
    ''' 使用唯一名称和可选描述创建应用上下文。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Create_APPHnd(<MarshalAs(UnmanagedType.LPUTF8Str)> appName As String,
                                             <MarshalAs(UnmanagedType.LPUTF8Str)> desc As String) As AppHnd
    End Function

    ''' <summary>
    ''' 销毁应用句柄，释放所有已注册的 API。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_Free_APPHnd(appHnd As AppHnd)
    End Sub

    ''' <summary>
    ''' 注册一个请求‑响应（Call）API。
    ''' </summary>
    ''' <param name="appHnd">应用句柄。</param>
    ''' <param name="apiName">唯一 API 名称（UTF‑8）。</param>
    ''' <param name="desc">可选描述（UTF‑8）。</param>
    ''' <param name="trigger">用户数据指针。</param>
    ''' <param name="onCall">回调委托。</param>
    ''' <returns>1 成功，0 表示 API 名称已存在。</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Reg_Call(appHnd As AppHnd,
                                        <MarshalAs(UnmanagedType.LPUTF8Str)> apiName As String,
                                        <MarshalAs(UnmanagedType.LPUTF8Str)> desc As String,
                                        trigger As IntPtr,
                                        onCall As APICallDelegate) As Integer
    End Function

    ''' <summary>
    ''' 注册一个单向通知（Notify）API。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Reg_Notify(appHnd As AppHnd,
                                          <MarshalAs(UnmanagedType.LPUTF8Str)> apiName As String,
                                          <MarshalAs(UnmanagedType.LPUTF8Str)> desc As String,
                                          trigger As IntPtr,
                                          onNotify As APINotifyDelegate) As Integer
    End Function

    ''' <summary>
    ''' 从应用中注销先前注册的 API。
    ''' <para>
    ''' API 会<b>立即</b>从本地注册表中移除，并触发网络广播。
    ''' 远程对等节点约 3 秒后不再看到此 API（取决于网络延迟和 C4 更新间隔）。
    ''' 在该短暂窗口期内，远程调用仍可能到达，但会优雅失败（收到“未找到”错误）。
    ''' </para>
    ''' <para>
    ''' 用于动态卸载插件、临时禁用服务或在不重启应用的情况下调整暴露功能。
    ''' </para>
    ''' </summary>
    ''' <param name="appHnd">应用句柄。</param>
    ''' <param name="apiName">要注销的 API 名称（UTF‑8）。</param>
    ''' <returns>1 成功，0 表示 API 名称不存在。</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_UnReg(appHnd As AppHnd,
                                     <MarshalAs(UnmanagedType.LPUTF8Str)> apiName As String) As Integer
    End Function

    ''' <summary>
    ''' 在本地（同一进程内）执行 Call API，绕过网络。
    ''' </summary>
    ''' <returns>包含结果的新 <see cref="DataHnd"/>；调用者必须释放。</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Local_APP_Call(appHnd As AppHnd, param As DataHnd) As DataHnd
    End Function

    ''' <summary>
    ''' 在本地发送通知（无结果）。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_Local_APP_Notify(appHnd As AppHnd, param As DataHnd)
    End Sub

    ' ======================================================================
    ' 网络准备与通信
    ' ======================================================================

    ''' <summary>
    ''' 准备一个服务（监听器），将在 <see cref="API_Prepare_Done"/> 调用时启动。
    ''' </summary>
    ''' <param name="listeningAddr">本地绑定地址（如 "0.0.0.0:9898" 或 "ipc:my_service"）。</param>
    ''' <param name="physicsAddr">向客户端公布的公共地址（必须与客户端使用的地址一致）。</param>
    ''' <returns>服务标签（仅作参考）。</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Prepare_Service(<MarshalAs(UnmanagedType.LPUTF8Str)> listeningAddr As String,
                                               <MarshalAs(UnmanagedType.LPUTF8Str)> physicsAddr As String) As Integer
    End Function

    ''' <summary>
    ''' 准备一个客户端连接。
    ''' </summary>
    ''' <param name="physicsAddr">远程服务地址（必须与服务公布的地址一致）。</param>
    ''' <param name="appHnd">可选应用句柄（可为 <see cref="AppHnd.Null"/>）。</param>
    ''' <returns>客户端标签（仅作参考）。</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Prepare_Client(<MarshalAs(UnmanagedType.LPUTF8Str)> physicsAddr As String,
                                              appHnd As AppHnd) As Integer
    End Function

    ''' <summary>
    ''' 清除所有已准备的服务和客户端。
    ''' 在准备新配置之前调用。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_Reset_Prepare()
    End Sub

    ''' <summary>
    ''' 启动网络框架，包含所有已准备的服务/客户端。
    ''' 此调用将阻塞直到框架就绪。
    ''' </summary>
    ''' <returns>1 成功，0 失败（详情请查看控制台输出）。</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Prepare_Done() As Integer
    End Function

    ''' <summary>
    ''' 通知内部主循环优雅退出。
    ''' 必须后跟 <see cref="API_shutdown"/> 以释放资源。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_Exit_MainThread()
    End Sub

    ''' <summary>
    ''' 执行远程（或本地）同步调用。
    ''' </summary>
    ''' <param name="appName">目标应用名（区分大小写）。</param>
    ''' <param name="param">输入数据句柄（内部会克隆，调用者仍需释放原句柄）。</param>
    ''' <param name="timeout">最大等待毫秒数（0 表示无限）。</param>
    ''' <returns>包含结果的新 <see cref="DataHnd"/>。句柄永不为空；
    ''' 若超时或失败，其大小为 0。调用者必须释放。</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Call(<MarshalAs(UnmanagedType.LPUTF8Str)> appName As String,
                                    param As DataHnd,
                                    timeout As UInt64) As DataHnd
    End Function

    ''' <summary>
    ''' 发送单向通知（fire‑and‑forget）。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_Notify(<MarshalAs(UnmanagedType.LPUTF8Str)> appName As String, param As DataHnd)
    End Sub

    ''' <summary>
    ''' 动态调整 API Hub 框架的全局运行时选项。
    ''' </summary>
    ''' <param name="optionName">配置键（UTF‑8，不区分大小写）。支持的键：
    ''' <list type="bullet">
    '''   <item><term>"password" / "passwd"</term><description>设置 C4 P2PVM 认证令牌。
    '''       服务端和客户端必须匹配。仅影响新建连接。</description></item>
    '''   <item><term>"Quiet"</term><description>启用/禁用静默模式（True/False）。</description></item>
    '''   <item><term>"External_Conf_Auto_Save" / "Conf_Auto_Save"</term><description>退出时自动保存 .ini（True/False）。</description></item>
    '''   <item><term>"Wait_Connection_ReadyOk" / "Wait_API_Prepare_Done" / ...</term><description>
    '''       控制 <see cref="API_Prepare_Done"/> 是否阻塞直到所有客户端连接就绪。
    '''       设为 False 时客户端将稍后自动连接（适用于部署）。</description></item>
    '''   <item><term>"Wait_Connection_Timeout" / "Wait_TimeOut"</term><description>上述等待的最大毫秒数。</description></item>
    '''   <item><term>"ShowThreadID" / "ShowThread" / "Show_Thread"</term><description>在日志中显示线程 ID（True/False）。</description></item>
    '''   <item><term>"ConsoleOutput" / "Console_Output"</term><description>启用/禁用控制台日志（True/False）。</description></item>
    '''   <item><term>"IPC_Serv_ThreadCount" / "IPC_ThreadCount" / "IPC_Server_ThreadCount"</term><description>IPC 服务线程池大小。</description></item>
    '''   <item><term>"IPC_Serv_MaxQueueLength" / "IPC_MaxQueueLength" / "IPC_Server_MaxQueueLength"</term><description>IPC 消息队列最大长度。</description></item>
    '''   <item><term>"IPC_Serv_MaxMsgSize" / "IPC_MaxMsgSize" / "IPC_Server_MaxMsgSize"</term><description>IPC 单条消息最大字节数。</description></item>
    ''' </list>
    ''' </param>
    ''' <param name="optionValue">新值（UTF‑8）。布尔值接受 "True"/"False"、"1"/"0"、"Yes"/"No"。</param>
    ''' <remarks>未知选项被静默忽略。此函数无返回值。</remarks>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_SetOption(<MarshalAs(UnmanagedType.LPUTF8Str)> optionName As String,
                                    <MarshalAs(UnmanagedType.LPUTF8Str)> optionValue As String)
    End Sub

    ''' <summary>
    ''' 优雅关闭整个框架：停止服务、断开客户端、释放内部资源。
    ''' 之后可重新初始化。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_shutdown()
    End Sub

    ' ======================================================================
    ' 新增：状态与诊断函数（2026-08-24 添加）
    ' 提供对内部日志队列和网络状态的编程式访问。
    ' ======================================================================

    ''' <summary>
    ''' 返回内部状态队列中待读取的日志消息数量。
    ''' 此函数<b>线程安全</b>，可与 <see cref="API_Get_Status"/> 和 <see cref="API_Post_Status"/> 并发调用。
    ''' </summary>
    ''' <returns>当前队列中的消息条数。</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl, EntryPoint:="API_Get_Status_Num")>
    Private Shared Function API_Get_Status_Num_Internal() As Integer
    End Function

    ''' <summary>
    ''' 从状态队列中取出一条日志消息（FIFO 顺序）。
    ''' 返回的指针指向内部缓冲区，该缓冲区在下次调用时会被覆盖。
    ''' 调用者必须立即复制数据。
    ''' </summary>
    ''' <returns>指向以 NUL 结尾的 UTF‑8 字符串的指针；若队列为空则返回 <see cref="IntPtr.Zero"/>。</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl, EntryPoint:="API_Get_Status")>
    Private Shared Function API_Get_Status_Internal() As IntPtr
    End Function

    ''' <summary>
    ''' 向内部状态队列中注入一条自定义日志消息。
    ''' 消息将被追加，可通过 <see cref="API_Get_Status"/> 读取。
    ''' 此函数<b>线程安全</b>。
    ''' </summary>
    ''' <param name="status">要添加的消息（UTF‑8）。</param>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl, EntryPoint:="API_Post_Status")>
    Private Shared Sub API_Post_Status_Internal(<MarshalAs(UnmanagedType.LPUTF8Str)> status As String)
    End Sub

    ''' <summary>
    ''' 检查模拟主线程（C4 事件循环）是否正在运行。
    ''' 返回 1 表示运行中，0 表示已停止或尚未启动。
    ''' 此函数<b>线程安全</b>。
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl, EntryPoint:="API_Check_MainThread")>
    Private Shared Function API_Check_MainThread_Internal() As Integer
    End Function

    ''' <summary>
    ''' 检查网络中是否存在指定名称的应用。
    ''' 查询基于本地缓存，可能略有过时（通常 < 3 秒）。
    ''' 返回 1 表示存在至少一个实例，0 表示不存在。
    ''' 此函数<b>线程安全</b>。
    ''' </summary>
    ''' <param name="appName">应用名称（UTF‑8，区分大小写）。</param>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl, EntryPoint:="API_Check_App")>
    Private Shared Function API_Check_App_Internal(<MarshalAs(UnmanagedType.LPUTF8Str)> appName As String) As Integer
    End Function

    ' ---------- 公共包装器 ----------

    ''' <summary>
    ''' 返回内部状态队列中待读取的日志消息数量。
    ''' </summary>
    Public Shared Function API_Get_Status_Num() As Integer
        Return API_Get_Status_Num_Internal()
    End Function

    ''' <summary>
    ''' 从状态队列中取出一条日志消息（FIFO 顺序）。
    ''' 返回的字符串是内部缓冲区的副本，因此后续调用不会影响其有效性。
    ''' 若队列为空，返回空字符串。
    ''' <para>此函数<b>线程安全</b>。</para>
    ''' <para>消息超过 64 KB 会被截断；队列最多容纳 1000 条消息。</para>
    ''' </summary>
    Public Shared Function API_Get_Status() As String
        Dim ptr = API_Get_Status_Internal()
        If ptr = IntPtr.Zero Then Return ""
        Return Marshal.PtrToStringUTF8(ptr)
    End Function

    ''' <summary>
    ''' 向内部状态队列中注入一条自定义日志消息。
    ''' 消息将被追加，可通过 <see cref="API_Get_Status"/> 读取。
    ''' 此函数<b>线程安全</b>。
    ''' </summary>
    ''' <param name="status">要添加的消息（UTF‑8）。</param>
    Public Shared Sub API_Post_Status(status As String)
        API_Post_Status_Internal(status)
    End Sub

    ''' <summary>
    ''' 检查模拟主线程（C4 事件循环）是否正在运行。
    ''' </summary>
    ''' <returns>True 表示正在运行，False 表示已停止。</returns>
    Public Shared Function API_Check_MainThread() As Boolean
        Return API_Check_MainThread_Internal() <> 0
    End Function

    ''' <summary>
    ''' 检查网络中是否存在指定名称的应用。
    ''' 查询基于本地缓存，可能略有过时（通常 < 3 秒）。
    ''' </summary>
    ''' <param name="appName">应用名称（UTF‑8，区分大小写）。</param>
    ''' <returns>True 表示存在至少一个实例，False 表示不存在。</returns>
    Public Shared Function API_Check_App(appName As String) As Boolean
        Return API_Check_App_Internal(appName) <> 0
    End Function

    ' ======================================================================
    ' 便利辅助函数（原有）
    ' ======================================================================

    ''' <summary>
    ''' 从句柄中读取所有字节（重置位置到 0）。
    ''' </summary>
    Public Shared Function ReadAllBytes(hnd As DataHnd) As Byte()
        Dim size = API_GetSize(hnd)
        If size <= 0 Then Return Array.Empty(Of Byte)()
        Dim buffer(size - 1) As Byte
        API_SetPos(hnd, 0)
        Dim read = API_ReadBuffer(hnd, buffer, size)
        If read <> size Then
            Array.Resize(buffer, CInt(read))
        End If
        Return buffer
    End Function

    ''' <summary>
    ''' 将字节数组写入句柄的当前位置。
    ''' </summary>
    Public Shared Function WriteBytes(hnd As DataHnd, data As Byte()) As Long
        Return API_WriteBuffer(hnd, data, data.Length)
    End Function

    ''' <summary>
    ''' 从句柄中读取以 NUL 结尾的 UTF‑8 字符串。
    ''' </summary>
    Public Shared Function ReadString(hnd As DataHnd) As String
        Dim bytes = ReadAllBytes(hnd)
        Dim len = Array.IndexOf(bytes, CByte(0))
        If len < 0 Then len = bytes.Length
        Return Encoding.UTF8.GetString(bytes, 0, len)
    End Function

    ''' <summary>
    ''' 将 UTF‑8 字符串写入句柄，并追加一个 NUL 终止符。
    ''' </summary>
    Public Shared Sub WriteString(hnd As DataHnd, str As String)
        Dim bytes = Encoding.UTF8.GetBytes(str)
        Dim nullTerm(bytes.Length) As Byte
        Array.Copy(bytes, 0, nullTerm, 0, bytes.Length)
        nullTerm(bytes.Length) = 0
        WriteBytes(hnd, nullTerm)
    End Sub

    ' ======================================================================
    ' 原子类型辅助（与 Pascal 兼容，小端序）
    ' 2026-08-20 添加，完全匹配 z_api_hubtool_import.pas
    ' 所有写方法返回 Boolean 表示成功（完整写入所需字节）。
    ' 所有读方法通过 ByRef 返回值，并返回 Boolean。
    ' ======================================================================

    ' ---------- 写辅助 ----------

    ''' <summary>
    ''' 写入有符号 8 位整数（1 字节）到当前位置。
    ''' </summary>
    ''' <returns>True 表示成功写入该字节。</returns>
    Public Shared Function WriteInt8(hnd As DataHnd, value As SByte) As Boolean
        Dim b As Byte = CByte(value)
        Return WriteBytes(hnd, {b}) = 1
    End Function

    ''' <summary>
    ''' 写入无符号 8 位整数（1 字节）到当前位置。
    ''' </summary>
    Public Shared Function WriteUInt8(hnd As DataHnd, value As Byte) As Boolean
        Return WriteBytes(hnd, {value}) = 1
    End Function

    ''' <summary>
    ''' 写入有符号 16 位整数（2 字节，小端序）到当前位置。
    ''' </summary>
    Public Shared Function WriteInt16(hnd As DataHnd, value As Short) As Boolean
        Return WriteBytes(hnd, BitConverter.GetBytes(value)) = 2
    End Function

    ''' <summary>
    ''' 写入无符号 16 位整数（2 字节，小端序）到当前位置。
    ''' </summary>
    Public Shared Function WriteUInt16(hnd As DataHnd, value As UShort) As Boolean
        Return WriteBytes(hnd, BitConverter.GetBytes(value)) = 2
    End Function

    ''' <summary>
    ''' 写入有符号 32 位整数（4 字节，小端序）到当前位置。
    ''' </summary>
    Public Shared Function WriteInt32(hnd As DataHnd, value As Integer) As Boolean
        Return WriteBytes(hnd, BitConverter.GetBytes(value)) = 4
    End Function

    ''' <summary>
    ''' 写入无符号 32 位整数（4 字节，小端序）到当前位置。
    ''' </summary>
    Public Shared Function WriteUInt32(hnd As DataHnd, value As UInteger) As Boolean
        Return WriteBytes(hnd, BitConverter.GetBytes(value)) = 4
    End Function

    ''' <summary>
    ''' 写入有符号 64 位整数（8 字节，小端序）到当前位置。
    ''' </summary>
    Public Shared Function WriteInt64(hnd As DataHnd, value As Long) As Boolean
        Return WriteBytes(hnd, BitConverter.GetBytes(value)) = 8
    End Function

    ''' <summary>
    ''' 写入无符号 64 位整数（8 字节，小端序）到当前位置。
    ''' </summary>
    Public Shared Function WriteUInt64(hnd As DataHnd, value As ULong) As Boolean
        Return WriteBytes(hnd, BitConverter.GetBytes(value)) = 8
    End Function

    ''' <summary>
    ''' 写入 32 位 IEEE 754 单精度浮点数（4 字节，小端序）到当前位置。
    ''' </summary>
    Public Shared Function WriteSingle(hnd As DataHnd, value As Single) As Boolean
        Return WriteBytes(hnd, BitConverter.GetBytes(value)) = 4
    End Function

    ''' <summary>
    ''' 写入 64 位 IEEE 754 双精度浮点数（8 字节，小端序）到当前位置。
    ''' </summary>
    Public Shared Function WriteDouble(hnd As DataHnd, value As Double) As Boolean
        Return WriteBytes(hnd, BitConverter.GetBytes(value)) = 8
    End Function

    ''' <summary>
    ''' 写入 UTF‑8 编码的字符串，后跟一个 NUL 终止符（#0）。
    ''' 此格式为跨语言标准 "UTF‑8 + #0"。
    ''' 位置会前进 Length(UTF8String) + 1 字节。
    ''' </summary>
    ''' <returns>True 表示完整写入了字符串（含终止符）。</returns>
    Public Shared Function WriteStringNullTerminated(hnd As DataHnd, str As String) As Boolean
        Dim bytes = Encoding.UTF8.GetBytes(str)
        Dim totalLen = bytes.Length + 1
        Dim buf(totalLen - 1) As Byte
        Array.Copy(bytes, 0, buf, 0, bytes.Length)
        buf(bytes.Length) = 0
        Return WriteBytes(hnd, buf) = totalLen
    End Function

    ' ---------- 读辅助 ----------

    ''' <summary>
    ''' 从当前位置读取有符号 8 位整数（1 字节）。
    ''' </summary>
    ''' <returns>True 表示成功读取该字节。</returns>
    Public Shared Function ReadInt8(hnd As DataHnd, ByRef value As SByte) As Boolean
        Dim b(0) As Byte
        If API_ReadBuffer(hnd, b, 1) <> 1 Then
            Return False
        End If
        value = CSByte(b(0))
        Return True
    End Function

    ''' <summary>
    ''' 从当前位置读取无符号 8 位整数（1 字节）。
    ''' </summary>
    Public Shared Function ReadUInt8(hnd As DataHnd, ByRef value As Byte) As Boolean
        Dim b(0) As Byte
        If API_ReadBuffer(hnd, b, 1) <> 1 Then
            Return False
        End If
        value = b(0)
        Return True
    End Function

    ''' <summary>
    ''' 从当前位置读取有符号 16 位整数（2 字节，小端序）。
    ''' </summary>
    Public Shared Function ReadInt16(hnd As DataHnd, ByRef value As Short) As Boolean
        Dim b(1) As Byte
        If API_ReadBuffer(hnd, b, 2) <> 2 Then
            Return False
        End If
        value = BitConverter.ToInt16(b, 0)
        Return True
    End Function

    ''' <summary>
    ''' 从当前位置读取无符号 16 位整数（2 字节，小端序）。
    ''' </summary>
    Public Shared Function ReadUInt16(hnd As DataHnd, ByRef value As UShort) As Boolean
        Dim b(1) As Byte
        If API_ReadBuffer(hnd, b, 2) <> 2 Then
            Return False
        End If
        value = BitConverter.ToUInt16(b, 0)
        Return True
    End Function

    ''' <summary>
    ''' 从当前位置读取有符号 32 位整数（4 字节，小端序）。
    ''' </summary>
    Public Shared Function ReadInt32(hnd As DataHnd, ByRef value As Integer) As Boolean
        Dim b(3) As Byte
        If API_ReadBuffer(hnd, b, 4) <> 4 Then
            Return False
        End If
        value = BitConverter.ToInt32(b, 0)
        Return True
    End Function

    ''' <summary>
    ''' 从当前位置读取无符号 32 位整数（4 字节，小端序）。
    ''' </summary>
    Public Shared Function ReadUInt32(hnd As DataHnd, ByRef value As UInteger) As Boolean
        Dim b(3) As Byte
        If API_ReadBuffer(hnd, b, 4) <> 4 Then
            Return False
        End If
        value = BitConverter.ToUInt32(b, 0)
        Return True
    End Function

    ''' <summary>
    ''' 从当前位置读取有符号 64 位整数（8 字节，小端序）。
    ''' </summary>
    Public Shared Function ReadInt64(hnd As DataHnd, ByRef value As Long) As Boolean
        Dim b(7) As Byte
        If API_ReadBuffer(hnd, b, 8) <> 8 Then
            Return False
        End If
        value = BitConverter.ToInt64(b, 0)
        Return True
    End Function

    ''' <summary>
    ''' 从当前位置读取无符号 64 位整数（8 字节，小端序）。
    ''' </summary>
    Public Shared Function ReadUInt64(hnd As DataHnd, ByRef value As ULong) As Boolean
        Dim b(7) As Byte
        If API_ReadBuffer(hnd, b, 8) <> 8 Then
            Return False
        End If
        value = BitConverter.ToUInt64(b, 0)
        Return True
    End Function

    ''' <summary>
    ''' 从当前位置读取 32 位 IEEE 754 单精度浮点数（4 字节，小端序）。
    ''' </summary>
    Public Shared Function ReadSingle(hnd As DataHnd, ByRef value As Single) As Boolean
        Dim b(3) As Byte
        If API_ReadBuffer(hnd, b, 4) <> 4 Then
            Return False
        End If
        value = BitConverter.ToSingle(b, 0)
        Return True
    End Function

    ''' <summary>
    ''' 从当前位置读取 64 位 IEEE 754 双精度浮点数（8 字节，小端序）。
    ''' </summary>
    Public Shared Function ReadDouble(hnd As DataHnd, ByRef value As Double) As Boolean
        Dim b(7) As Byte
        If API_ReadBuffer(hnd, b, 8) <> 8 Then
            Return False
        End If
        value = BitConverter.ToDouble(b, 0)
        Return True
    End Function

    ''' <summary>
    ''' 从当前位置读取以 NUL 字节（#0）终止的 UTF‑8 字符串。
    ''' 读取位置会前进到终止符之后。
    ''' 若未找到 NUL 终止符，位置保持不变并返回 False。
    ''' </summary>
    ''' <returns>True 表示找到了 NUL 终止符并读取了字符串。</returns>
    ''' <param name="hnd">数据句柄。</param>
    ''' <param name="value">输出的字符串（若无数据或未找到 NUL 则为空）。</param>
    Public Shared Function ReadStringNullTerminated(hnd As DataHnd, ByRef value As String) As Boolean
        Dim size = API_GetSize(hnd)
        Dim pos = API_GetPos(hnd)
        If pos >= size Then
            value = ""
            Return False
        End If
        ' 读取剩余所有字节
        Dim remaining = CInt(size - pos)
        Dim buf(remaining - 1) As Byte
        Dim read = API_ReadBuffer(hnd, buf, remaining)
        If read = 0 Then
            value = ""
            Return False
        End If
        ' 查找 NUL 终止符
        Dim nulPos = Array.IndexOf(buf, CByte(0), 0, CInt(read))
        If nulPos >= 0 Then
            ' 找到 NUL：提取字符串（不含 NUL），并将位置移到 NUL 之后
            API_SetPos(hnd, pos + nulPos + 1)
            Dim strBytes(nulPos - 1) As Byte
            Array.Copy(buf, 0, strBytes, 0, nulPos)
            value = Encoding.UTF8.GetString(strBytes)
            Return True
        Else
            ' 未找到 NUL：恢复原位置，返回 False
            API_SetPos(hnd, pos)
            value = ""
            Return False
        End If
    End Function

End Class