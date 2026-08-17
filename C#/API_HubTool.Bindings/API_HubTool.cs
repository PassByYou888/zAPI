/*
* API_HubTool.cs - C# P/Invoke bindings for the API Hub dynamic library.
*
* This file provides managed wrappers for all functions exported by the API Hub
* library. All exported functions are prefixed with "API_", matching the C and
* Pascal bindings.
*
* The library file is loaded automatically by a custom DllImport resolver that
* chooses the correct filename based on the current platform:
*   - Windows 32-bit: z_api_hub32.dll
*   - Windows 64-bit: z_api_hub64.dll
*   - Linux:          libz_api_hub.so
*   - macOS:          libz_api_hub.dylib
*
* ============================================================================
* STRING ENCODING – UTF-8 IS MANDATORY
* ============================================================================
* All string parameters (including API names, descriptions, and network addresses)
* MUST be encoded in **UTF-8** and MUST be null-terminated (i.e., end with a
* byte of value 0).
*
* - UTF-8 is a multi-byte encoding where ASCII characters (0x00–0x7F) occupy
*   one byte, and all other Unicode characters are encoded in 2–4 bytes.
*   The null terminator is the only zero byte in a well-formed UTF-8 string.
* - The library internally decodes UTF-8 input into Unicode, and encodes
*   outgoing strings to UTF-8.
* - This encoding is **platform-independent** and works identically on
*   Windows, Linux, macOS, and BSD.
*
* *Important*: Do **not** use the system ANSI codepage (e.g., CP_ACP on
* Windows). All strings are explicitly marshaled as UTF-8.
*
* ============================================================================
* QUICK START – TYPICAL USAGE PATTERN
* ============================================================================
*
* 1. Create an application handle (AppHnd):
*    AppHnd app = API.API_Create_APPHnd("MyApp", "Example application");
*
* 2. Register your own API callbacks:
*    API.API_Reg_Call(app, "echo", "Echo input", IntPtr.Zero, MyEchoCallback);
*
* 3. Prepare the network (server and/or client):
*    API.API_Reset_Prepare();
*    API.API_Prepare_Service("0.0.0.0", "127.0.0.1:9898");   // TCP service
*    API.API_Prepare_Client("127.0.0.1:9898", app);           // connect to it
*    if (API.API_Prepare_Done() == 1) { ... }                 // start framework
*
* 4. Make a remote call:
*    DataHnd data = API.API_Create_DataHnd("echo");
*    API.WriteString(data, "Hello, world!");
*    DataHnd result = API.API_Call("TargetApp", data, 5000);
*    API.API_Free_DataHnd(data);   // free input handle
*    // process result ...
*    API.API_Free_DataHnd(result);
*
* 5. (Optional) Dynamically unregister an API:
*    if (API.API_UnReg(app, "echo") == 1)
*        Console.WriteLine("API 'echo' unregistered, broadcast in progress.");
*
* 6. (Optional) Adjust runtime options, e.g., authentication password:
*    API.API_SetOption("password", "my_secret_token");
*    API.API_SetOption("Wait_Connection_ReadyOk", "False");   // don't wait for clients
*
* 7. Shutdown and clean up:
*    API.API_Exit_MainThread();   // stop main loop
*    API.API_Free_APPHnd(app);    // free app handle
*    API.API_shutdown();          // shutdown framework
*
* ============================================================================
* IMPORTANT NOTES & BEST PRACTICES (READ BEFORE USING)
* ============================================================================
*
* 1. **THREAD SAFETY**:
*    All exported functions are **fully thread-safe**. They can be called
*    concurrently from any thread without external synchronization.
*
*    However, for a given DataHnd, write operations (API_WriteBuffer,
*    API_SetPos, API_SetSize) should be serialised across threads because they
*    modify the internal buffer state. Read‑only operations (API_GetBuffer,
*    API_GetPos, API_GetSize) are safe even while another thread is writing,
*    as long as the handle is not being freed.
*
*    Different DataHnd instances are independent and can be used concurrently
*    without any restrictions.
*
* 2. **CALLBACK EXECUTION CONTEXT** (⚠️ CRITICAL):
*    Your callbacks (APICallDelegate, APINotifyDelegate) are **executed in
*    background threads** from the library's internal thread pool.
*
*    This means:
*      * **DO NOT** perform long‑blocking operations inside callbacks.
*      * **DO NOT** call API_Call() or API_Notify() from within a callback –
*        this may cause deadlocks because the callback thread may hold internal
*        locks. If you need to make a remote call, offload the request to a
*        separate worker thread and return quickly.
*      * **DO NOT** access UI components or thread‑local storage without
*        proper synchronization (e.g., using Control.Invoke or a thread‑safe
*        queue).
*      * Offload heavy processing to a separate thread or queue to keep
*        callbacks responsive.
*
*    The library guarantees that callbacks are thread‑safe and reentrant,
*    but it is your responsibility to ensure that any shared data accessed
*    from callbacks is properly synchronized.
*
* 3. **EXECUTION ORDER**:
*    The library does **not** guarantee the order of execution for concurrent
*    API calls. Calls are independent and may be executed out‑of‑order because
*    the underlying service mesh distributes requests across multiple
*    application instances for load balancing. If you send calls '1', '2', '3'
*    in that order, the remote side may process them in any order (e.g., '2',
*    '1', '3'). Only the per‑call request‑response semantics are reliable –
*    each call is atomic and returns a correct result, but the global ordering
*    is not preserved.
*
* 4. **DATA HANDLE LIFETIME**:
*    Every DataHnd created with API_Create_DataHnd() MUST be freed with
*    API_Free_DataHnd() when no longer needed. The library does NOT auto‑free
*    them, even after remote calls (it clones the input internally).
*
* 5. **RESULT HANDLES**:
*    API_Call() always returns a valid DataHnd (never a null handle). If the
*    call times out or fails, the handle size will be 0. You must still free
*    it with API_Free_DataHnd().
*
* 6. **CALLBACK DELEGATES MUST BE KEPT ALIVE**:
*    When registering callbacks, the delegate object is converted to a function
*    pointer and passed to the native library. You must keep the delegate
*    alive (e.g., store it in a static variable or a class field) to prevent
*    it from being garbage collected.
*
* 7. **TIMEOUTS**:
*    API_Call() timeout is in milliseconds. 0 means infinite wait (use with
*    caution). On timeout, the returned handle size is 0.
*
* 8. **APPLICATION NAMES**:
*    App names are case‑sensitive and should be unique across the network.
*
* 9. **DYNAMIC UNREGISTRATION (API_UnReg)**:
*    - Immediately removes the API from the local registry.
*    - Triggers an asynchronous network broadcast to all connected peers.
*    - Remote peers stop seeing this API within approximately 3 seconds
*      (depending on network latency and the C4 update interval).
*    - During this short window, remote calls may still be attempted; they will
*      fail gracefully (the remote side receives a "not found" error).
*
* 10. **RUNTIME OPTIONS (API_SetOption)**:
*     Supports keys (case‑insensitive, aliases accepted):
*       - "password" / "passwd" : Sets C4 P2PVM authentication token.
*         Must match on both service and client sides.
*       - "Quiet" : Enable/disable quiet mode (True/False).
*       - "External_Conf_Auto_Save" / "Conf_Auto_Save" : Auto‑save .ini on exit.
*       - "Wait_Connection_ReadyOk" / "Wait_API_Prepare_Done" / ... :
*         Controls whether API_Prepare_Done blocks until all clients are connected.
*         When False, clients auto‑connect later (useful for deployment).
*       - "Wait_Connection_Timeout" / "Wait_TimeOut" : Max wait (ms) when the above is True.
*       - "ShowThreadID" / "ShowThread" / "Show_Thread" : Show thread IDs in logs.
*       - "ConsoleOutput" / "Console_Output" : Enable/disable console logging.
*       - "IPC_Serv_ThreadCount" / "IPC_ThreadCount" / ... : Number of IPC service threads.
*       - "IPC_Serv_MaxQueueLength" / "IPC_MaxQueueLength" / ... : Max IPC queue length.
*       - "IPC_Serv_MaxMsgSize" / "IPC_MaxMsgSize" / ... : Max IPC message size (bytes).
*
* ============================================================================
* ADDITIONAL EXAMPLES
* ============================================================================
*
* Below is a complete local call example (no network required):
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
*     // In Main:
*     AppHnd app = API_Create_APPHnd("LocalDemo", "Local only");
*     APICallDelegate del = AddCallback;
*     GCHandle.Alloc(del);  // prevent collection
*     API_Reg_Call(app, "add", "Addition", IntPtr.Zero, del);
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
*     // Unregister the 'add' API before shutdown (optional)
*     if (API_UnReg(app, "add") == 1)
*         Console.WriteLine("'add' unregistered.");
*
*     // Set a runtime option (e.g., enable quiet mode)
*     API_SetOption("Quiet", "True");
*
*     API_Free_APPHnd(app);
*     API_shutdown();
*
* For more examples, see the companion demo projects (HelloWorld, Service,
* Client1, etc.).
*/

using System;
using System.Runtime.InteropServices;
using System.Text;

namespace API_HubTool.Bindings
{
    // ----------------------------------------------------------------------------
    // Helper for UTF-8 string marshaling
    // ----------------------------------------------------------------------------
    internal static class UTF8Marshal
    {
        /// <summary>
        /// Converts a managed string to a null-terminated UTF-8 byte array.
        /// For null input, returns null; for empty string, returns a byte array with a single zero byte.
        /// </summary>
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
        /// Allocates unmanaged memory for a UTF-8 string (including null terminator)
        /// and copies the bytes. For null input, returns IntPtr.Zero.
        /// For empty string, allocates one byte (null terminator).
        /// </summary>
        public static IntPtr AllocUTF8(string str)
        {
            if (str == null) return IntPtr.Zero;
            byte[] bytes = StringToUTF8Bytes(str);
            IntPtr ptr = Marshal.AllocHGlobal(bytes.Length);
            Marshal.Copy(bytes, 0, ptr, bytes.Length);
            return ptr;
        }

        /// <summary>
        /// Frees a pointer allocated by AllocUTF8.
        /// </summary>
        public static void FreeUTF8(IntPtr ptr)
        {
            if (ptr != IntPtr.Zero)
                Marshal.FreeHGlobal(ptr);
        }

        /// <summary>
        /// Reads a null-terminated UTF-8 string from an IntPtr and returns a managed string.
        /// Returns null if ptr is IntPtr.Zero.
        /// </summary>
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
    /// Opaque data handle that holds an API name and its associated binary payload.
    /// Used for both input parameters and output results.
    /// Must be created with <see cref="API.API_Create_DataHnd"/> and freed with
    /// <see cref="API.API_Free_DataHnd"/>.
    /// </summary>
    /// <remarks>
    /// This structure contains only an IntPtr handle; all operations are performed
    /// through API functions. Do not manipulate the handle pointer directly.
    /// </remarks>
    /// <example>
    /// <code>
    /// DataHnd data = API_Create_DataHnd("my_api");
    /// // write data ...
    /// API_Free_DataHnd(data); // must be freed
    /// </code>
    /// </example>
    public struct DataHnd : IEquatable<DataHnd>
    {
        /// <summary>Raw handle pointer.</summary>
        public IntPtr Handle;

        /// <summary>Indicates whether the handle is valid (non-zero).</summary>
        public bool IsValid => Handle != IntPtr.Zero;

        /// <summary>Represents a null handle (zero value).</summary>
        public static readonly DataHnd Null = new DataHnd { Handle = IntPtr.Zero };

        /// <inheritdoc/>
        public override bool Equals(object obj) => obj is DataHnd other && Equals(other);

        /// <inheritdoc/>
        public bool Equals(DataHnd other) => Handle == other.Handle;

        /// <inheritdoc/>
        public override int GetHashCode() => Handle.GetHashCode();

        /// <summary>Equality operator.</summary>
        public static bool operator ==(DataHnd a, DataHnd b) => a.Equals(b);

        /// <summary>Inequality operator.</summary>
        public static bool operator !=(DataHnd a, DataHnd b) => !a.Equals(b);
    }

    /// <summary>
    /// Opaque application handle that groups a set of APIs.
    /// Created with <see cref="API.API_Create_APPHnd"/> and freed with
    /// <see cref="API.API_Free_APPHnd"/>.
    /// </summary>
    /// <remarks>
    /// An application can register multiple Call and Notify APIs and expose them
    /// over the network.
    /// </remarks>
    /// <example>
    /// <code>
    /// AppHnd app = API_Create_APPHnd("MyApp", "My application");
    /// // register APIs...
    /// API_Free_APPHnd(app);
    /// </code>
    /// </example>
    public struct AppHnd : IEquatable<AppHnd>
    {
        /// <summary>Raw handle pointer.</summary>
        public IntPtr Handle;

        /// <summary>Indicates whether the handle is valid (non-zero).</summary>
        public bool IsValid => Handle != IntPtr.Zero;

        /// <summary>Represents a null handle (zero value).</summary>
        public static readonly AppHnd Null = new AppHnd { Handle = IntPtr.Zero };

        /// <inheritdoc/>
        public override bool Equals(object obj) => obj is AppHnd other && Equals(other);

        /// <inheritdoc/>
        public bool Equals(AppHnd other) => Handle == other.Handle;

        /// <inheritdoc/>
        public override int GetHashCode() => Handle.GetHashCode();

        /// <summary>Equality operator.</summary>
        public static bool operator ==(AppHnd a, AppHnd b) => a.Equals(b);

        /// <summary>Inequality operator.</summary>
        public static bool operator !=(AppHnd a, AppHnd b) => !a.Equals(b);
    }

    /// <summary>
    /// Callback delegate for request‑response (Call) APIs.
    /// Must use <see cref="CallingConvention.Cdecl"/>.
    /// </summary>
    /// <param name="trigger">User‑supplied pointer passed during registration.</param>
    /// <param name="input">Read‑only input data handle (do not free).</param>
    /// <param name="output">Write‑only output data handle for the response (do not free).</param>
    /// <remarks>
    /// <para>
    /// This callback is executed in a background thread‑pool thread. It must not
    /// block or perform long‑running operations. Use <see cref="API.API_WriteBuffer"/>
    /// to write the response to the output handle.
    /// </para>
    /// <para>
    /// <b>DO NOT call API_Call() or API_Notify() from within this callback</b> –
    /// this may cause deadlocks.
    /// </para>
    /// <para>
    /// Ensure the delegate instance is kept alive (e.g., stored in a static field)
    /// to prevent garbage collection.
    /// </para>
    /// </remarks>
    /// <example>
    /// Simple echo callback:
    /// <code>
    /// private static void EchoCallback(IntPtr trigger, IntPtr input, IntPtr output)
    /// {
    ///     DataHnd hInput = new DataHnd { Handle = input };
    ///     DataHnd hOutput = new DataHnd { Handle = output };
    ///     byte[] data = ReadAllBytes(hInput);
    ///     API_WriteBuffer(hOutput, data, data.Length);
    /// }
    /// </code>
    /// </example>
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void APICallDelegate(IntPtr trigger, IntPtr input, IntPtr output);

    /// <summary>
    /// Callback delegate for one‑way notification (Notify) APIs.
    /// Must use <see cref="CallingConvention.Cdecl"/>.
    /// </summary>
    /// <param name="trigger">User‑supplied pointer passed during registration.</param>
    /// <param name="input">Read‑only input data handle (do not free).</param>
    /// <remarks>
    /// No response is produced. The callback must return quickly and must not
    /// block. Same thread‑safety and lifetime considerations as <see cref="APICallDelegate"/>.
    /// </remarks>
    /// <example>
    /// <code>
    /// private static void LogNotifyCallback(IntPtr trigger, IntPtr input)
    /// {
    ///     DataHnd hInput = new DataHnd { Handle = input };
    ///     string msg = ReadString(hInput);
    ///     Console.WriteLine($"[Notify] {msg}");
    /// }
    /// </code>
    /// </example>
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void APINotifyDelegate(IntPtr trigger, IntPtr input);

    /// <summary>
    /// Static class providing all API Hub functions.
    /// The library is loaded automatically via a custom DllImport resolver.
    /// </summary>
    public static class API
    {
        // The logical library name used in DllImport; actual filename is resolved dynamically.
        private const string DllName = "z_api_hub";

        // Static constructor: sets up the custom DllImport resolver.
        static API()
        {
            NativeLibrary.SetDllImportResolver(typeof(API).Assembly, (libraryName, assembly, searchPath) =>
            {
                if (libraryName == DllName)
                {
                    string libName;

                    if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                    {
                        // ✅ Select 32‑bit or 64‑bit DLL based on process bitness
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
                        libName = "libz_api_hub"; // unknown platform, fallback to logical name
                    }

                    return NativeLibrary.Load(libName, assembly, searchPath);
                }
                return IntPtr.Zero;
            });
        }

        // ---------- Private native imports (entry points match C library) ----------

        #region Data Handle Operations

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
        /// Creates a new data handle initialised with the given API name.
        /// The handle's internal buffer is empty (size = 0).
        /// </summary>
        /// <param name="apiName">Target API name (UTF‑8, null‑terminated).</param>
        /// <returns>A new <see cref="DataHnd"/>. Must be freed with <see cref="API_Free_DataHnd"/>.</returns>
        /// <remarks>
        /// The API name is copied internally, so you may free the input string
        /// immediately after the call.
        /// </remarks>
        /// <example>
        /// <code>
        /// DataHnd data = API_Create_DataHnd("add");
        /// // write two integers...
        /// // use data in a call...
        /// API_Free_DataHnd(data);
        /// </code>
        /// </example>
        public static DataHnd API_Create_DataHnd(string apiName)
        {
            IntPtr ptr = UTF8Marshal.AllocUTF8(apiName);
            try { return Native_Create_DataHnd(ptr); }
            finally { UTF8Marshal.FreeUTF8(ptr); }
        }

        /// <summary>
        /// Destroys a data handle and releases all associated resources.
        /// The handle becomes invalid and must not be used afterwards.
        /// </summary>
        /// <param name="hnd">Handle to free. Does nothing if invalid.</param>
        /// <remarks>
        /// Every handle created with <see cref="API_Create_DataHnd"/> must be freed
        /// with this function to avoid memory leaks.
        /// </remarks>
        public static void API_Free_DataHnd(DataHnd hnd) => Native_Free_DataHnd(hnd);

        /// <summary>
        /// Returns a direct pointer to the raw binary data stored in the handle.
        /// The pointer is valid until the handle is freed or the buffer is resized.
        /// <para>Do not free this pointer; it is managed by the library.</para>
        /// </summary>
        /// <param name="hnd">Data handle.</param>
        /// <returns>Pointer to the internal buffer, or <see cref="IntPtr.Zero"/> if
        /// the handle is invalid or empty.</returns>
        /// <remarks>
        /// The pointer is read‑only; modifying it may corrupt internal state.
        /// Use <see cref="API_ReadBuffer"/> for safe reading.
        /// </remarks>
        public static IntPtr API_GetBuffer(DataHnd hnd) => Native_GetBuffer(hnd);

        /// <summary>
        /// Appends binary data to the handle's buffer at the current position.
        /// The position advances by the number of bytes written.
        /// The buffer is automatically enlarged if necessary.
        /// </summary>
        /// <param name="hnd">Data handle.</param>
        /// <param name="buffer">Source data buffer.</param>
        /// <param name="size">Number of bytes to write.</param>
        /// <returns>The number of bytes actually written (normally equals <paramref name="size"/>).</returns>
        /// <remarks>
        /// If writing fails (e.g., invalid handle), the return value may be less than size.
        /// </remarks>
        /// <example>
        /// <code>
        /// DataHnd data = API_Create_DataHnd("test");
        /// byte[] nums = { 1, 2, 3, 4 };
        /// API_WriteBuffer(data, nums, nums.Length);
        /// </code>
        /// </example>
        public static long API_WriteBuffer(DataHnd hnd, byte[] buffer, long size) => Native_WriteBuffer(hnd, buffer, size);

        /// <summary>
        /// Reads binary data from the handle's buffer into the caller's buffer,
        /// starting from the current position. The position advances by the number
        /// of bytes read.
        /// </summary>
        /// <param name="hnd">Data handle.</param>
        /// <param name="buffer">Destination buffer.</param>
        /// <param name="size">Maximum number of bytes to read.</param>
        /// <returns>The actual number of bytes read (may be less than size if end‑of‑buffer).</returns>
        /// <remarks>
        /// Typically you call <see cref="API_GetSize"/> first to know the required buffer size.
        /// </remarks>
        /// <example>
        /// <code>
        /// long size = API_GetSize(data);
        /// byte[] buffer = new byte[size];
        /// API_SetPos(data, 0);
        /// long read = API_ReadBuffer(data, buffer, size);
        /// </code>
        /// </example>
        public static long API_ReadBuffer(DataHnd hnd, byte[] buffer, long size) => Native_ReadBuffer(hnd, buffer, size);

        /// <summary>
        /// Returns the current read/write position within the handle's buffer
        /// (byte offset).
        /// </summary>
        /// <param name="hnd">Data handle.</param>
        /// <returns>Current position (0‑based).</returns>
        public static long API_GetPos(DataHnd hnd) => Native_GetPos(hnd);

        /// <summary>
        /// Sets the current read/write position within the handle's buffer.
        /// If the new position exceeds the current size, the buffer is extended
        /// with zero bytes.
        /// </summary>
        /// <param name="hnd">Data handle.</param>
        /// <param name="pos">New position (must be >= 0).</param>
        public static void API_SetPos(DataHnd hnd, long pos) => Native_SetPos(hnd, pos);

        /// <summary>
        /// Returns the total size (in bytes) of the data stored in the handle.
        /// </summary>
        /// <param name="hnd">Data handle.</param>
        /// <returns>Current buffer size.</returns>
        public static long API_GetSize(DataHnd hnd) => Native_GetSize(hnd);

        /// <summary>
        /// Resizes the internal buffer of the data handle.
        /// If the new size is larger, the added space is uninitialised. If smaller,
        /// data beyond the new size is discarded.
        /// </summary>
        /// <param name="hnd">Data handle.</param>
        /// <param name="size">New desired size in bytes.</param>
        public static void API_SetSize(DataHnd hnd, long size) => Native_SetSize(hnd, size);

        #endregion

        #region Application Handle Operations

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
        /// Creates a new application context with a unique name and optional description.
        /// This handle serves as a container for registering APIs.
        /// </summary>
        /// <param name="appName">Unique application identifier (case‑sensitive, UTF‑8).</param>
        /// <param name="desc">Human‑readable description (UTF‑8, can be null or empty).</param>
        /// <returns>A new <see cref="AppHnd"/>. Must be freed with <see cref="API_Free_APPHnd"/>.</returns>
        /// <remarks>
        /// The application name is used for network routing and must be unique
        /// across the distributed system.
        /// </remarks>
        /// <example>
        /// <code>
        /// AppHnd app = API_Create_APPHnd("Calculator", "Provides addition and echo services");
        /// </code>
        /// </example>
        public static AppHnd API_Create_APPHnd(string appName, string desc)
        {
            IntPtr pName = UTF8Marshal.AllocUTF8(appName);
            IntPtr pDesc = UTF8Marshal.AllocUTF8(desc);
            try { return Native_Create_APPHnd(pName, pDesc); }
            finally { UTF8Marshal.FreeUTF8(pName); UTF8Marshal.FreeUTF8(pDesc); }
        }

        /// <summary>
        /// Destroys an application context and releases all registered APIs and resources.
        /// The handle becomes invalid and must not be used afterwards.
        /// </summary>
        /// <param name="appHnd">Application handle.</param>
        public static void API_Free_APPHnd(AppHnd appHnd) => Native_Free_APPHnd(appHnd);

        /// <summary>
        /// Registers a request‑response (Call) API within the application.
        /// The API name must be unique inside this application.
        /// </summary>
        /// <param name="appHnd">Application handle.</param>
        /// <param name="apiName">Unique API name (case‑sensitive, UTF‑8).</param>
        /// <param name="desc">Optional description (UTF‑8, can be null).</param>
        /// <param name="trigger">User data pointer passed to the callback.</param>
        /// <param name="onCall">Callback implementing the API.</param>
        /// <returns>1 if successful, 0 if the API name already exists.</returns>
        /// <remarks>
        /// <para>The callback delegate must be kept alive (e.g., stored in a static
        /// variable or GCHandle).</para>
        /// <para>This function is thread‑safe.</para>
        /// </remarks>
        /// <example>
        /// <code>
        /// private static void AddCallback(IntPtr trigger, IntPtr input, IntPtr output)
        /// {
        ///     // read two integers from input, write sum to output
        /// }
        /// 
        /// APICallDelegate del = AddCallback;
        /// GCHandle.Alloc(del);  // prevent GC
        /// API_Reg_Call(app, "add", "Addition", IntPtr.Zero, del);
        /// </code>
        /// </example>
        public static int API_Reg_Call(AppHnd appHnd, string apiName, string desc, IntPtr trigger, APICallDelegate onCall)
        {
            IntPtr pName = UTF8Marshal.AllocUTF8(apiName);
            IntPtr pDesc = UTF8Marshal.AllocUTF8(desc);
            try { return Native_Reg_Call(appHnd, pName, pDesc, trigger, onCall); }
            finally { UTF8Marshal.FreeUTF8(pName); UTF8Marshal.FreeUTF8(pDesc); }
        }

        /// <summary>
        /// Registers a one‑way notification (Notify) API within the application.
        /// The callback does not produce a response.
        /// </summary>
        /// <param name="appHnd">Application handle.</param>
        /// <param name="apiName">Unique API name (case‑sensitive, UTF‑8).</param>
        /// <param name="desc">Optional description (UTF‑8, can be null).</param>
        /// <param name="trigger">User data pointer passed to the callback.</param>
        /// <param name="onNotify">Notification handler callback.</param>
        /// <returns>1 on success, 0 if the API name already exists.</returns>
        public static int API_Reg_Notify(AppHnd appHnd, string apiName, string desc, IntPtr trigger, APINotifyDelegate onNotify)
        {
            IntPtr pName = UTF8Marshal.AllocUTF8(apiName);
            IntPtr pDesc = UTF8Marshal.AllocUTF8(desc);
            try { return Native_Reg_Notify(appHnd, pName, pDesc, trigger, onNotify); }
            finally { UTF8Marshal.FreeUTF8(pName); UTF8Marshal.FreeUTF8(pDesc); }
        }

        /// <summary>
        /// Unregisters a previously registered API from the application.
        /// </summary>
        /// <param name="appHnd">Application handle.</param>
        /// <param name="apiName">The name of the API to unregister (UTF‑8).</param>
        /// <returns>1 on success, 0 if the API name does not exist.</returns>
        /// <remarks>
        /// <para>
        /// The API is <b>immediately</b> removed from the local registry.
        /// A network update broadcast is triggered asynchronously.
        /// Remote peers will stop seeing this API within approximately 3 seconds
        /// (depending on network latency and the C4 update interval).
        /// During that short window, remote calls may still be attempted; they will
        /// fail gracefully (the remote side will receive a "not found" error).
        /// </para>
        /// <para>
        /// Use this function to dynamically unload plugins, temporarily disable
        /// services, or adjust exposed functionality at runtime without restarting
        /// the application.
        /// </para>
        /// </remarks>
        /// <example>
        /// <code>
        /// if (API_UnReg(app, "add") == 1)
        ///     Console.WriteLine("API 'add' unregistered, broadcast in progress.");
        /// </code>
        /// </example>
        public static int API_UnReg(AppHnd appHnd, string apiName)
        {
            IntPtr pName = UTF8Marshal.AllocUTF8(apiName);
            try { return Native_UnReg(appHnd, pName); }
            finally { UTF8Marshal.FreeUTF8(pName); }
        }

        /// <summary>
        /// Executes a Call API locally within the same application, bypassing the network.
        /// The call is synchronous.
        /// </summary>
        /// <param name="appHnd">Application handle.</param>
        /// <param name="param">Input data handle (must contain the API name and parameters).</param>
        /// <returns>A new <see cref="DataHnd"/> containing the result. The caller must free it.
        /// If the API is not found or an error occurs, the handle size will be 0.</returns>
        /// <remarks>
        /// The input handle is not freed by this function; the caller must free it separately.
        /// This is useful for testing or internal calls.
        /// </remarks>
        /// <example>
        /// <code>
        /// DataHnd data = API_Create_DataHnd("add");
        /// // write parameters ...
        /// DataHnd result = API_Local_APP_Call(app, data);
        /// API_Free_DataHnd(data);
        /// // process result...
        /// API_Free_DataHnd(result);
        /// </code>
        /// </example>
        public static DataHnd API_Local_APP_Call(AppHnd appHnd, DataHnd param) => Native_Local_APP_Call(appHnd, param);

        /// <summary>
        /// Sends a notification locally within the same application.
        /// No result is produced.
        /// </summary>
        /// <param name="appHnd">Application handle.</param>
        /// <param name="param">Input data handle containing the API name and payload.</param>
        /// <remarks>
        /// The input handle is not freed by this function.
        /// </remarks>
        public static void API_Local_APP_Notify(AppHnd appHnd, DataHnd param) => Native_Local_APP_Notify(appHnd, param);

        #endregion

        #region Network Preparation and Communication

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

        /// <summary>
        /// Prepares a service (listener) that will be started when
        /// <see cref="API_Prepare_Done"/> is called. Multiple services can be prepared.
        /// </summary>
        /// <param name="listeningAddr">Address to bind (UTF‑8). Supported formats:
        ///   - IPv4: "0.0.0.0", "127.0.0.1"
        ///   - IPv6: "[::1]:8080" or "::1|8080"
        ///   - Domain: "myhost.com:9090"
        ///   - IPC: "ipc:my_service" (OS‑specific IPC)
        ///   If no port is given, default 9898 is used (IPC uses port 0).</param>
        /// <param name="physicsAddr">Public address advertised to clients (UTF‑8), same format.</param>
        /// <returns>A tag (ID) for this service (mostly informational).</returns>
        /// <remarks>
        /// The service does not start until <see cref="API_Prepare_Done"/> is called.
        /// Multiple services can be prepared in the same process.
        /// </remarks>
        public static int API_Prepare_Service(string listeningAddr, string physicsAddr)
        {
            IntPtr pListen = UTF8Marshal.AllocUTF8(listeningAddr);
            IntPtr pPhysics = UTF8Marshal.AllocUTF8(physicsAddr);
            try { return Native_Prepare_Service(pListen, pPhysics); }
            finally { UTF8Marshal.FreeUTF8(pListen); UTF8Marshal.FreeUTF8(pPhysics); }
        }

        /// <summary>
        /// Prepares a client that will connect to a remote service when
        /// <see cref="API_Prepare_Done"/> is called. If an application handle is provided,
        /// the client will automatically register that app's APIs with the service.
        /// </summary>
        /// <param name="physicsAddr">Remote service address (UTF‑8, same format as <see cref="API_Prepare_Service"/>).</param>
        /// <param name="appHnd">Optional application handle to expose (can be <see cref="AppHnd.Null"/>).</param>
        /// <returns>A tag (ID) for this client.</returns>
        /// <remarks>
        /// The client automatically reconnects if the connection is lost. On reconnection,
        /// the associated application is re‑registered.
        /// </remarks>
        public static int API_Prepare_Client(string physicsAddr, AppHnd appHnd)
        {
            IntPtr pPhysics = UTF8Marshal.AllocUTF8(physicsAddr);
            try { return Native_Prepare_Client(pPhysics, appHnd); }
            finally { UTF8Marshal.FreeUTF8(pPhysics); }
        }

        /// <summary>
        /// Clears all previously prepared services and clients.
        /// Call this before preparing a new set of services/clients to avoid conflicts.
        /// </summary>
        public static void API_Reset_Prepare() => Native_Reset_Prepare();

        /// <summary>
        /// Starts the framework with all prepared services and clients.
        /// This function blocks until the framework is fully initialised and the
        /// simulated main thread is running. After a successful return, remote APIs
        /// can be invoked.
        /// </summary>
        /// <returns>1 on success, 0 on failure. Error details are printed to the console
        /// (default) or can be redirected via the configuration file.</returns>
        /// <remarks>
        /// <para>Do not call this more than once without resetting or shutting down.</para>
        /// <para>It is recommended to prepare services before clients, but clients
        /// can be prepared earlier and will wait for services.</para>
        /// <para>
        /// On failure, check the console output for detailed error messages (e.g., port already in use).
        /// Logging can be configured via the <c>&lt;executable&gt;.api-tool.ini</c> file.
        /// </para>
        /// </remarks>
        public static int API_Prepare_Done() => Native_Prepare_Done();

        /// <summary>
        /// Signals the internal main thread to exit gracefully.
        /// The network loop will stop, but resources are not automatically freed.
        /// You should still call <see cref="API_shutdown"/> to clean up.
        /// </summary>
        public static void API_Exit_MainThread() => Native_Exit_MainThread();

        /// <summary>
        /// Performs a remote (or local) call to the specified application.
        /// This function blocks until a response is received or the timeout expires.
        /// </summary>
        /// <param name="appName">Target application name (case‑sensitive, UTF‑8).</param>
        /// <param name="param">Input data handle (the library clones it internally;
        /// caller must still free it).</param>
        /// <param name="timeout">Maximum wait time in milliseconds. 0 means infinite.</param>
        /// <returns>A new <see cref="DataHnd"/> containing the result. If the call
        /// times out or fails, the handle size will be 0 (but still valid).
        /// The caller must free it with <see cref="API_Free_DataHnd"/>.</returns>
        /// <remarks>
        /// This function tries to find a local instance first to avoid network
        /// round‑trip. Concurrent calls may be executed out‑of‑order (see notes above).
        /// </remarks>
        /// <example>
        /// <code>
        /// DataHnd data = API_Create_DataHnd("echo");
        /// WriteString(data, "Hello");
        /// DataHnd result = API_Call("MyApp", data, 5000);
        /// API_Free_DataHnd(data);
        /// if (API_GetSize(result) > 0)
        /// {
        ///     string reply = ReadString(result);
        ///     Console.WriteLine(reply);
        /// }
        /// API_Free_DataHnd(result);
        /// </code>
        /// </example>
        public static DataHnd API_Call(string appName, DataHnd param, ulong timeout)
        {
            IntPtr pName = UTF8Marshal.AllocUTF8(appName);
            try { return Native_Call(pName, param, timeout); }
            finally { UTF8Marshal.FreeUTF8(pName); }
        }

        /// <summary>
        /// Sends a one‑way notification to the specified application.
        /// This function returns immediately; delivery is best‑effort.
        /// </summary>
        /// <param name="appName">Target application name (UTF‑8).</param>
        /// <param name="param">Input data handle (cloned internally; caller must still free it).</param>
        public static void API_Notify(string appName, DataHnd param)
        {
            IntPtr pName = UTF8Marshal.AllocUTF8(appName);
            try { Native_Notify(pName, param); }
            finally { UTF8Marshal.FreeUTF8(pName); }
        }

        /// <summary>
        /// Dynamically adjusts global runtime options of the API Hub framework.
        /// All changes take effect immediately for subsequent operations (except where noted).
        /// This function is intended for runtime tuning without restarting the application
        /// or modifying the .ini file. Unknown options are silently ignored.
        /// </summary>
        /// <param name="option">Configuration key (UTF‑8, case‑insensitive). Supported keys
        /// (aliases accepted) include:
        ///   <list type="bullet">
        ///     <item><term>"password" / "passwd"</term><description>Sets the C4 P2PVM authentication token.
        ///       Must match on both service and client sides. Affects new connections only.</description></item>
        ///     <item><term>"Quiet"</term><description>Enable/disable quiet mode (True/False). Suppresses debug logs.</description></item>
        ///     <item><term>"External_Conf_Auto_Save" / "Conf_Auto_Save"</term><description>Auto‑save .ini on exit (True/False).</description></item>
        ///     <item><term>"Wait_Connection_ReadyOk" / "Wait_API_Prepare_Done" / ...</term><description>
        ///       Controls whether <see cref="API_Prepare_Done"/> blocks until all clients are connected.
        ///       When False, clients auto‑connect later (important for deployment).</description></item>
        ///     <item><term>"Wait_Connection_Timeout" / "Wait_TimeOut"</term><description>Max wait (ms) when the above is True.</description></item>
        ///     <item><term>"ShowThreadID" / "ShowThread" / "Show_Thread"</term><description>Show thread IDs in logs (True/False).</description></item>
        ///     <item><term>"ConsoleOutput" / "Console_Output"</term><description>Enable/disable console logging (True/False).</description></item>
        ///     <item><term>"IPC_Serv_ThreadCount" / "IPC_ThreadCount" / "IPC_Server_ThreadCount"</term><description>IPC service thread pool size.</description></item>
        ///     <item><term>"IPC_Serv_MaxQueueLength" / "IPC_MaxQueueLength" / "IPC_Server_MaxQueueLength"</term><description>Max IPC queue length.</description></item>
        ///     <item><term>"IPC_Serv_MaxMsgSize" / "IPC_MaxMsgSize" / "IPC_Server_MaxMsgSize"</term><description>Max IPC message size (bytes).</description></item>
        ///   </list>
        /// </param>
        /// <param name="value">New value (UTF‑8). For boolean options, accepts "True"/"False", "1"/"0", "Yes"/"No".</param>
        /// <remarks>
        /// This function has no return value; unknown options are silently ignored.
        /// The password and wait‑control options are critical for secure and flexible deployment.
        /// Changes to IPC settings affect new connections only.
        /// </remarks>
        /// <example>
        /// <code>
        /// // Set authentication password before starting
        /// API_SetOption("password", "my_secret_token");
        /// // Allow clients to connect later (don't block Prepare_Done)
        /// API_SetOption("Wait_Connection_ReadyOk", "False");
        /// // Enable quiet mode to reduce logs
        /// API_SetOption("Quiet", "True");
        /// </code>
        /// </example>
        public static void API_SetOption(string option, string value)
        {
            IntPtr pOption = UTF8Marshal.AllocUTF8(option);
            IntPtr pValue = UTF8Marshal.AllocUTF8(value);
            try { Native_SetOption(pOption, pValue); }
            finally { UTF8Marshal.FreeUTF8(pOption); UTF8Marshal.FreeUTF8(pValue); }
        }

        /// <summary>
        /// Gracefully shuts down the entire API Hub framework:
        /// stops all services, disconnects all clients, and releases internal resources.
        /// After this call, the library state is reset and you can re‑initialise by
        /// calling Prepare functions again.
        /// </summary>
        public static void API_shutdown() => Native_shutdown();

        #endregion

        #region Convenience Helper Methods

        /// <summary>
        /// Reads all data from the handle into a new byte array.
        /// Resets the position to 0 before reading.
        /// </summary>
        /// <param name="hnd">Data handle.</param>
        /// <returns>A byte array containing all data.</returns>
        /// <example>
        /// <code>
        /// byte[] allData = ReadAllBytes(data);
        /// </code>
        /// </example>
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
        /// Writes a byte array to the handle's current position.
        /// </summary>
        /// <param name="hnd">Data handle.</param>
        /// <param name="data">Bytes to write.</param>
        /// <returns>The number of bytes written.</returns>
        public static long WriteBytes(DataHnd hnd, byte[] data)
        {
            return API_WriteBuffer(hnd, data, data.Length);
        }

        /// <summary>
        /// Reads a null‑terminated UTF-8 string from the handle.
        /// </summary>
        /// <param name="hnd">Data handle.</param>
        /// <returns>The decoded string (without the null terminator).</returns>
        /// <example>
        /// <code>
        /// string text = ReadString(data);
        /// </code>
        /// </example>
        public static string ReadString(DataHnd hnd)
        {
            byte[] bytes = ReadAllBytes(hnd);
            int len = Array.IndexOf(bytes, (byte)0);
            if (len < 0) len = bytes.Length;
            return Encoding.UTF8.GetString(bytes, 0, len);
        }

        /// <summary>
        /// Writes a UTF-8 string to the handle, appending a null terminator.
        /// </summary>
        /// <param name="hnd">Data handle.</param>
        /// <param name="str">String to write.</param>
        /// <remarks>
        /// The string is encoded as UTF-8 and a zero byte (null) is appended,
        /// matching the library's convention for null‑terminated strings.
        /// </remarks>
        /// <example>
        /// <code>
        /// WriteString(data, "Hello");
        /// </code>
        /// </example>
        public static void WriteString(DataHnd hnd, string str)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(str);
            byte[] nullTerminated = new byte[bytes.Length + 1];
            Array.Copy(bytes, 0, nullTerminated, 0, bytes.Length);
            nullTerminated[bytes.Length] = 0;
            WriteBytes(hnd, nullTerminated);
        }

        #endregion
    }
}