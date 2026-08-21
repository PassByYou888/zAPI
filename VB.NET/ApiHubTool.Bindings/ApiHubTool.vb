Imports System
Imports System.Runtime.InteropServices
Imports System.Text

''' <summary>
''' Opaque data handle that holds an API name and its binary payload.
''' Must be created with <see cref="API.API_Create_DataHnd"/> and freed with <see cref="API.API_Free_DataHnd"/>.
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
''' Opaque application handle that groups a set of APIs.
''' Created with <see cref="API.API_Create_APPHnd"/> and freed with <see cref="API.API_Free_APPHnd"/>.
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
''' Callback delegate for request‑response (Call) APIs.
''' Executed in a background thread‑pool thread – do NOT block or call API_Call/API_Notify inside.
''' </summary>
''' <param name="trigger">User data pointer passed during registration.</param>
''' <param name="input">Read‑only input data handle (do not free).</param>
''' <param name="output">Write‑only output data handle for the response (do not free).</param>
<UnmanagedFunctionPointer(CallingConvention.Cdecl)>
Public Delegate Sub APICallDelegate(trigger As IntPtr, input As IntPtr, output As IntPtr)

''' <summary>
''' Callback delegate for one‑way notification (Notify) APIs.
''' Same threading and safety restrictions as <see cref="APICallDelegate"/>.
''' </summary>
<UnmanagedFunctionPointer(CallingConvention.Cdecl)>
Public Delegate Sub APINotifyDelegate(trigger As IntPtr, input As IntPtr)

''' <summary>
''' Static class providing all API Hub functions.
''' The library is loaded automatically via a custom DllImport resolver.
''' <para>All string parameters are marshaled as UTF‑8 (using <see cref="UnmanagedType.LPUTF8Str"/>).</para>
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
    ' Data Handle Operations
    ' ======================================================================

    ''' <summary>
    ''' Creates a new data handle with the given API name.
    ''' The internal payload is initially empty (size = 0).
    ''' </summary>
    ''' <param name="apiName">Target API name (UTF‑8).</param>
    ''' <returns>A new <see cref="DataHnd"/>; must be freed with <see cref="API_Free_DataHnd"/>.</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Create_DataHnd(<MarshalAs(UnmanagedType.LPUTF8Str)> apiName As String) As DataHnd
    End Function

    ''' <summary>
    ''' Destroys a data handle and releases all resources.
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_Free_DataHnd(hnd As DataHnd)
    End Sub

    ''' <summary>
    ''' Returns a direct pointer to the internal buffer (zero‑copy access).
    ''' Do not free this pointer; it is managed by the library.
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_GetBuffer(hnd As DataHnd) As IntPtr
    End Function

    ''' <summary>
    ''' Writes binary data at the current position. The buffer is enlarged if needed.
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_WriteBuffer(hnd As DataHnd, buffer As Byte(), size As Long) As Long
    End Function

    ''' <summary>
    ''' Reads binary data from the current position into the provided buffer.
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_ReadBuffer(hnd As DataHnd, buffer As Byte(), size As Long) As Long
    End Function

    ''' <summary>
    ''' Returns the current read/write position (byte offset).
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_GetPos(hnd As DataHnd) As Long
    End Function

    ''' <summary>
    ''' Sets the current read/write position. Extends the buffer with zeros if beyond current size.
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_SetPos(hnd As DataHnd, pos As Long)
    End Sub

    ''' <summary>
    ''' Returns the total size (in bytes) of the payload.
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_GetSize(hnd As DataHnd) As Long
    End Function

    ''' <summary>
    ''' Resizes the internal buffer. Truncates data if smaller, uninitialised if larger.
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_SetSize(hnd As DataHnd, size As Long)
    End Sub

    ' ======================================================================
    ' Application Handle Operations
    ' ======================================================================

    ''' <summary>
    ''' Creates a new application context with a unique name and optional description.
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Create_APPHnd(<MarshalAs(UnmanagedType.LPUTF8Str)> appName As String,
                                             <MarshalAs(UnmanagedType.LPUTF8Str)> desc As String) As AppHnd
    End Function

    ''' <summary>
    ''' Destroys an application handle and releases all registered APIs.
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_Free_APPHnd(appHnd As AppHnd)
    End Sub

    ''' <summary>
    ''' Registers a request‑response (Call) API.
    ''' </summary>
    ''' <param name="appHnd">Application handle.</param>
    ''' <param name="apiName">Unique API name (UTF‑8).</param>
    ''' <param name="desc">Optional description (UTF‑8).</param>
    ''' <param name="trigger">User data pointer.</param>
    ''' <param name="onCall">Callback delegate.</param>
    ''' <returns>1 on success, 0 if the API name already exists.</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Reg_Call(appHnd As AppHnd,
                                        <MarshalAs(UnmanagedType.LPUTF8Str)> apiName As String,
                                        <MarshalAs(UnmanagedType.LPUTF8Str)> desc As String,
                                        trigger As IntPtr,
                                        onCall As APICallDelegate) As Integer
    End Function

    ''' <summary>
    ''' Registers a one‑way notification (Notify) API.
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Reg_Notify(appHnd As AppHnd,
                                          <MarshalAs(UnmanagedType.LPUTF8Str)> apiName As String,
                                          <MarshalAs(UnmanagedType.LPUTF8Str)> desc As String,
                                          trigger As IntPtr,
                                          onNotify As APINotifyDelegate) As Integer
    End Function

    ''' <summary>
    ''' Unregisters a previously registered API from the application.
    ''' <para>
    ''' The API is <b>immediately</b> removed from the local registry and a network
    ''' broadcast is triggered. Remote peers will stop seeing this API within
    ''' approximately 3 seconds (depending on network latency and the C4 update
    ''' interval). During that short window, remote calls may still be attempted;
    ''' they will fail gracefully (the remote side receives a "not found" error).
    ''' </para>
    ''' <para>
    ''' Use this function to dynamically unload plugins, temporarily disable
    ''' services, or adjust exposed functionality at runtime without restarting
    ''' the application.
    ''' </para>
    ''' </summary>
    ''' <param name="appHnd">Application handle.</param>
    ''' <param name="apiName">Name of the API to unregister (UTF‑8).</param>
    ''' <returns>1 on success, 0 if the API name does not exist.</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_UnReg(appHnd As AppHnd,
                                     <MarshalAs(UnmanagedType.LPUTF8Str)> apiName As String) As Integer
    End Function

    ''' <summary>
    ''' Executes a Call API locally (within the same process), bypassing the network.
    ''' </summary>
    ''' <returns>A new <see cref="DataHnd"/> containing the result; caller must free it.</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Local_APP_Call(appHnd As AppHnd, param As DataHnd) As DataHnd
    End Function

    ''' <summary>
    ''' Sends a notification locally (no result).
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_Local_APP_Notify(appHnd As AppHnd, param As DataHnd)
    End Sub

    ' ======================================================================
    ' Network Preparation & Communication
    ' ======================================================================

    ''' <summary>
    ''' Prepares a service (listener) that will be started when <see cref="API_Prepare_Done"/> is called.
    ''' </summary>
    ''' <param name="listeningAddr">Local address to bind (e.g., "0.0.0.0:9898" or "ipc:my_service").</param>
    ''' <param name="physicsAddr">Public address advertised to clients (must match clients' address).</param>
    ''' <returns>A service tag (informational).</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Prepare_Service(<MarshalAs(UnmanagedType.LPUTF8Str)> listeningAddr As String,
                                               <MarshalAs(UnmanagedType.LPUTF8Str)> physicsAddr As String) As Integer
    End Function

    ''' <summary>
    ''' Prepares a client connection.
    ''' </summary>
    ''' <param name="physicsAddr">Remote service address (must match service's advertised address).</param>
    ''' <param name="appHnd">Optional application handle to expose (can be <see cref="AppHnd.Null"/>).</param>
    ''' <returns>A client tag (informational).</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Prepare_Client(<MarshalAs(UnmanagedType.LPUTF8Str)> physicsAddr As String,
                                              appHnd As AppHnd) As Integer
    End Function

    ''' <summary>
    ''' Clears all previously prepared services and clients.
    ''' Call before preparing a new set.
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_Reset_Prepare()
    End Sub

    ''' <summary>
    ''' Starts the network framework with all prepared services/clients.
    ''' This call blocks until the framework is ready.
    ''' </summary>
    ''' <returns>1 on success, 0 on failure (check console output for details).</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Prepare_Done() As Integer
    End Function

    ''' <summary>
    ''' Signals the internal main loop to exit gracefully.
    ''' Must be followed by <see cref="API_shutdown"/> to release resources.
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_Exit_MainThread()
    End Sub

    ''' <summary>
    ''' Performs a remote (or local) synchronous call.
    ''' </summary>
    ''' <param name="appName">Target application name (case‑sensitive).</param>
    ''' <param name="param">Input data handle (cloned internally; caller must still free it).</param>
    ''' <param name="timeout">Maximum wait time in milliseconds (0 = infinite).</param>
    ''' <returns>A new <see cref="DataHnd"/> containing the result. The handle is never null;
    ''' if the call times out or fails, its size will be 0. Must be freed by the caller.</returns>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Function API_Call(<MarshalAs(UnmanagedType.LPUTF8Str)> appName As String,
                                    param As DataHnd,
                                    timeout As UInt64) As DataHnd
    End Function

    ''' <summary>
    ''' Sends a one‑way notification (fire‑and‑forget).
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_Notify(<MarshalAs(UnmanagedType.LPUTF8Str)> appName As String, param As DataHnd)
    End Sub

    ''' <summary>
    ''' Dynamically adjusts global runtime options of the API Hub framework.
    ''' </summary>
    ''' <param name="optionName">Configuration key (UTF‑8, case‑insensitive). Supported keys:
    ''' <list type="bullet">
    '''   <item><term>"password" / "passwd"</term><description>Sets the C4 P2PVM authentication token.
    '''       Must match on both service and client sides. Affects new connections only.</description></item>
    '''   <item><term>"Quiet"</term><description>Enable/disable quiet mode (True/False).</description></item>
    '''   <item><term>"External_Conf_Auto_Save" / "Conf_Auto_Save"</term><description>Auto‑save .ini on exit (True/False).</description></item>
    '''   <item><term>"Wait_Connection_ReadyOk" / "Wait_API_Prepare_Done" / ...</term><description>
    '''       Controls whether <see cref="API_Prepare_Done"/> blocks until all clients are connected.
    '''       When False, clients auto‑connect later (important for deployment).</description></item>
    '''   <item><term>"Wait_Connection_Timeout" / "Wait_TimeOut"</term><description>Max wait (ms) when the above is True.</description></item>
    '''   <item><term>"ShowThreadID" / "ShowThread" / "Show_Thread"</term><description>Show thread IDs in logs (True/False).</description></item>
    '''   <item><term>"ConsoleOutput" / "Console_Output"</term><description>Enable/disable console logging (True/False).</description></item>
    '''   <item><term>"IPC_Serv_ThreadCount" / "IPC_ThreadCount" / "IPC_Server_ThreadCount"</term><description>IPC service thread pool size.</description></item>
    '''   <item><term>"IPC_Serv_MaxQueueLength" / "IPC_MaxQueueLength" / "IPC_Server_MaxQueueLength"</term><description>Max IPC queue length.</description></item>
    '''   <item><term>"IPC_Serv_MaxMsgSize" / "IPC_MaxMsgSize" / "IPC_Server_MaxMsgSize"</term><description>Max IPC message size (bytes).</description></item>
    ''' </list>
    ''' </param>
    ''' <param name="optionValue">New value (UTF‑8). For booleans, accepts "True"/"False", "1"/"0", "Yes"/"No".</param>
    ''' <remarks>Unknown options are silently ignored. This function has no return value.</remarks>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_SetOption(<MarshalAs(UnmanagedType.LPUTF8Str)> optionName As String,
                                    <MarshalAs(UnmanagedType.LPUTF8Str)> optionValue As String)
    End Sub

    ''' <summary>
    ''' Gracefully shuts down the entire framework: stops services, disconnects clients,
    ''' and releases internal resources. After this, you can re‑initialise.
    ''' </summary>
    <DllImport(DllName, CallingConvention:=CallingConvention.Cdecl)>
    Public Shared Sub API_shutdown()
    End Sub

    ' ======================================================================
    ' Convenience Helpers (Existing)
    ' ======================================================================

    ''' <summary>
    ''' Reads all bytes from the handle (resets position to 0).
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
    ''' Writes a byte array to the handle at the current position.
    ''' </summary>
    Public Shared Function WriteBytes(hnd As DataHnd, data As Byte()) As Long
        Return API_WriteBuffer(hnd, data, data.Length)
    End Function

    ''' <summary>
    ''' Reads a null‑terminated UTF-8 string from the handle.
    ''' </summary>
    Public Shared Function ReadString(hnd As DataHnd) As String
        Dim bytes = ReadAllBytes(hnd)
        Dim len = Array.IndexOf(bytes, CByte(0))
        If len < 0 Then len = bytes.Length
        Return Encoding.UTF8.GetString(bytes, 0, len)
    End Function

    ''' <summary>
    ''' Writes a UTF‑8 string to the handle, appending a null terminator.
    ''' </summary>
    Public Shared Sub WriteString(hnd As DataHnd, str As String)
        Dim bytes = Encoding.UTF8.GetBytes(str)
        Dim nullTerm(bytes.Length) As Byte
        Array.Copy(bytes, 0, nullTerm, 0, bytes.Length)
        nullTerm(bytes.Length) = 0
        WriteBytes(hnd, nullTerm)
    End Sub

    ' ======================================================================
    ' NEW: Atomic Type Helpers (Pascal‑compatible, little‑endian)
    ' Added 2026-08-20, matching z_api_hubtool_import.pas exactly.
    ' All write methods return Boolean indicating success (full bytes written).
    ' All read methods return the value via ByRef and return Boolean.
    ' ======================================================================

    ' ---------- Write Helpers ----------

    ''' <summary>
    ''' Writes a signed 8‑bit integer (1 byte) to the handle at the current position.
    ''' </summary>
    ''' <returns>True if the byte was successfully written.</returns>
    Public Shared Function WriteInt8(hnd As DataHnd, value As SByte) As Boolean
        Dim b As Byte = CByte(value)
        Return WriteBytes(hnd, {b}) = 1
    End Function

    ''' <summary>
    ''' Writes an unsigned 8‑bit integer (1 byte) to the handle.
    ''' </summary>
    Public Shared Function WriteUInt8(hnd As DataHnd, value As Byte) As Boolean
        Return WriteBytes(hnd, {value}) = 1
    End Function

    ''' <summary>
    ''' Writes a signed 16‑bit integer (2 bytes, little‑endian) to the handle.
    ''' </summary>
    Public Shared Function WriteInt16(hnd As DataHnd, value As Short) As Boolean
        Return WriteBytes(hnd, BitConverter.GetBytes(value)) = 2
    End Function

    ''' <summary>
    ''' Writes an unsigned 16‑bit integer (2 bytes, little‑endian) to the handle.
    ''' </summary>
    Public Shared Function WriteUInt16(hnd As DataHnd, value As UShort) As Boolean
        Return WriteBytes(hnd, BitConverter.GetBytes(value)) = 2
    End Function

    ''' <summary>
    ''' Writes a signed 32‑bit integer (4 bytes, little‑endian) to the handle.
    ''' </summary>
    Public Shared Function WriteInt32(hnd As DataHnd, value As Integer) As Boolean
        Return WriteBytes(hnd, BitConverter.GetBytes(value)) = 4
    End Function

    ''' <summary>
    ''' Writes an unsigned 32‑bit integer (4 bytes, little‑endian) to the handle.
    ''' </summary>
    Public Shared Function WriteUInt32(hnd As DataHnd, value As UInteger) As Boolean
        Return WriteBytes(hnd, BitConverter.GetBytes(value)) = 4
    End Function

    ''' <summary>
    ''' Writes a signed 64‑bit integer (8 bytes, little‑endian) to the handle.
    ''' </summary>
    Public Shared Function WriteInt64(hnd As DataHnd, value As Long) As Boolean
        Return WriteBytes(hnd, BitConverter.GetBytes(value)) = 8
    End Function

    ''' <summary>
    ''' Writes an unsigned 64‑bit integer (8 bytes, little‑endian) to the handle.
    ''' </summary>
    Public Shared Function WriteUInt64(hnd As DataHnd, value As ULong) As Boolean
        Return WriteBytes(hnd, BitConverter.GetBytes(value)) = 8
    End Function

    ''' <summary>
    ''' Writes a 32‑bit IEEE 754 single‑precision float (4 bytes, little‑endian) to the handle.
    ''' </summary>
    Public Shared Function WriteSingle(hnd As DataHnd, value As Single) As Boolean
        Return WriteBytes(hnd, BitConverter.GetBytes(value)) = 4
    End Function

    ''' <summary>
    ''' Writes a 64‑bit IEEE 754 double‑precision float (8 bytes, little‑endian) to the handle.
    ''' </summary>
    Public Shared Function WriteDouble(hnd As DataHnd, value As Double) As Boolean
        Return WriteBytes(hnd, BitConverter.GetBytes(value)) = 8
    End Function

    ''' <summary>
    ''' Writes a UTF‑8 encoded string followed by a null terminator (#0).
    ''' This matches the standard "UTF‑8 + #0" format used across all languages.
    ''' The position is advanced by Length(UTF8String) + 1 bytes.
    ''' </summary>
    ''' <returns>True if the entire string (including the trailing null) was written.</returns>
    Public Shared Function WriteStringNullTerminated(hnd As DataHnd, str As String) As Boolean
        Dim bytes = Encoding.UTF8.GetBytes(str)
        Dim totalLen = bytes.Length + 1
        Dim buf(totalLen - 1) As Byte
        Array.Copy(bytes, 0, buf, 0, bytes.Length)
        buf(bytes.Length) = 0
        Return WriteBytes(hnd, buf) = totalLen
    End Function

    ' ---------- Read Helpers ----------

    ''' <summary>
    ''' Reads a signed 8‑bit integer (1 byte) from the current position.
    ''' </summary>
    ''' <returns>True if the byte was successfully read.</returns>
    Public Shared Function ReadInt8(hnd As DataHnd, ByRef value As SByte) As Boolean
        Dim b(0) As Byte
        If API_ReadBuffer(hnd, b, 1) <> 1 Then
            Return False
        End If
        value = CSByte(b(0))
        Return True
    End Function

    ''' <summary>
    ''' Reads an unsigned 8‑bit integer (1 byte) from the current position.
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
    ''' Reads a signed 16‑bit integer (2 bytes, little‑endian) from the current position.
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
    ''' Reads an unsigned 16‑bit integer (2 bytes, little‑endian) from the current position.
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
    ''' Reads a signed 32‑bit integer (4 bytes, little‑endian) from the current position.
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
    ''' Reads an unsigned 32‑bit integer (4 bytes, little‑endian) from the current position.
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
    ''' Reads a signed 64‑bit integer (8 bytes, little‑endian) from the current position.
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
    ''' Reads an unsigned 64‑bit integer (8 bytes, little‑endian) from the current position.
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
    ''' Reads a 32‑bit IEEE 754 single‑precision float (4 bytes, little‑endian) from the current position.
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
    ''' Reads a 64‑bit IEEE 754 double‑precision float (8 bytes, little‑endian) from the current position.
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
    ''' Reads a UTF‑8 encoded string terminated by a null byte (#0) from the current position.
    ''' The read position is advanced past the terminating null.
    ''' If no null terminator is found, the position remains unchanged and False is returned.
    ''' </summary>
    ''' <returns>True if a null terminator was found and the string was read.</returns>
    ''' <param name="hnd">Data handle.</param>
    ''' <param name="value">Output string (empty if no data or no null found).</param>
    Public Shared Function ReadStringNullTerminated(hnd As DataHnd, ByRef value As String) As Boolean
        Dim size = API_GetSize(hnd)
        Dim pos = API_GetPos(hnd)
        If pos >= size Then
            value = ""
            Return False
        End If
        ' Read all remaining bytes
        Dim remaining = CInt(size - pos)
        Dim buf(remaining - 1) As Byte
        Dim read = API_ReadBuffer(hnd, buf, remaining)
        If read = 0 Then
            value = ""
            Return False
        End If
        ' Find null terminator
        Dim nulPos = Array.IndexOf(buf, CByte(0), 0, CInt(read))
        If nulPos >= 0 Then
            ' Found null: extract string without it, and move position to after the null
            API_SetPos(hnd, pos + nulPos + 1)
            Dim strBytes(nulPos - 1) As Byte
            Array.Copy(buf, 0, strBytes, 0, nulPos)
            value = Encoding.UTF8.GetString(strBytes)
            Return True
        Else
            ' No null found: restore position to original, return False
            API_SetPos(hnd, pos)
            value = ""
            Return False
        End If
    End Function

End Class