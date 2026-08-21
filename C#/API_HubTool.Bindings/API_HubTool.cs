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
* 6. **CALLBACK DELEGATES MUST BE KEPT ALIVE** (⚠️ CRITICAL):
*    When registering callbacks, the delegate object is converted to a function
*    pointer and passed to the native library. You must keep the delegate
*    alive (e.g., store it in a static variable or a class field) to prevent
*    it from being garbage collected. This wrapper does NOT automatically
*    cache the delegate; you are responsible for its lifetime.
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
*     // The delegate must be kept alive manually (e.g., using GCHandle.Alloc).
*     APICallDelegate del = AddCallback;
*     GCHandle.Alloc(del);   // prevent collection
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
using System.Buffers.Binary;

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
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void APICallDelegate(IntPtr trigger, IntPtr input, IntPtr output);

    /// <summary>
    /// Callback delegate for one‑way notification (Notify) APIs.
    /// Must use <see cref="CallingConvention.Cdecl"/>.
    /// </summary>
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

        // ---------- Private native imports ----------

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
        /// <param name="apiName">Target API name (UTF‑8, null‑terminated). Must not be null.</param>
        /// <returns>A new <see cref="DataHnd"/>. Must be freed with <see cref="API_Free_DataHnd"/>.</returns>
        /// <exception cref="ArgumentNullException">Thrown when <paramref name="apiName"/> is null.</exception>
        public static DataHnd API_Create_DataHnd(string apiName)
        {
            if (apiName == null)
                throw new ArgumentNullException(nameof(apiName));
            IntPtr ptr = UTF8Marshal.AllocUTF8(apiName);
            try { return Native_Create_DataHnd(ptr); }
            finally { UTF8Marshal.FreeUTF8(ptr); }
        }

        /// <summary>
        /// Destroys a data handle and releases all associated resources.
        /// </summary>
        public static void API_Free_DataHnd(DataHnd hnd) => Native_Free_DataHnd(hnd);

        /// <summary>
        /// Returns a direct pointer to the raw binary data stored in the handle.
        /// </summary>
        public static IntPtr API_GetBuffer(DataHnd hnd) => Native_GetBuffer(hnd);

        /// <summary>
        /// Appends binary data to the handle's buffer at the current position.
        /// </summary>
        public static long API_WriteBuffer(DataHnd hnd, byte[] buffer, long size) => Native_WriteBuffer(hnd, buffer, size);

        // --------------------------------------------------------------------
        //  ATOMIC WRITE HELPERS
        // --------------------------------------------------------------------
        public static bool API_WriteInt8(DataHnd hnd, sbyte value)
        {
            byte[] bytes = { unchecked((byte)value) };
            return API_WriteBuffer(hnd, bytes, 1) == 1;
        }

        public static bool API_WriteUInt8(DataHnd hnd, byte value)
        {
            byte[] bytes = { value };
            return API_WriteBuffer(hnd, bytes, 1) == 1;
        }

        public static bool API_WriteInt16(DataHnd hnd, short value)
        {
            Span<byte> bytes = stackalloc byte[2];
            BinaryPrimitives.WriteInt16LittleEndian(bytes, value);
            return API_WriteBuffer(hnd, bytes.ToArray(), 2) == 2;
        }

        public static bool API_WriteUInt16(DataHnd hnd, ushort value)
        {
            Span<byte> bytes = stackalloc byte[2];
            BinaryPrimitives.WriteUInt16LittleEndian(bytes, value);
            return API_WriteBuffer(hnd, bytes.ToArray(), 2) == 2;
        }

        public static bool API_WriteInt32(DataHnd hnd, int value)
        {
            Span<byte> bytes = stackalloc byte[4];
            BinaryPrimitives.WriteInt32LittleEndian(bytes, value);
            return API_WriteBuffer(hnd, bytes.ToArray(), 4) == 4;
        }

        public static bool API_WriteUInt32(DataHnd hnd, uint value)
        {
            Span<byte> bytes = stackalloc byte[4];
            BinaryPrimitives.WriteUInt32LittleEndian(bytes, value);
            return API_WriteBuffer(hnd, bytes.ToArray(), 4) == 4;
        }

        public static bool API_WriteInt64(DataHnd hnd, long value)
        {
            Span<byte> bytes = stackalloc byte[8];
            BinaryPrimitives.WriteInt64LittleEndian(bytes, value);
            return API_WriteBuffer(hnd, bytes.ToArray(), 8) == 8;
        }

        public static bool API_WriteUInt64(DataHnd hnd, ulong value)
        {
            Span<byte> bytes = stackalloc byte[8];
            BinaryPrimitives.WriteUInt64LittleEndian(bytes, value);
            return API_WriteBuffer(hnd, bytes.ToArray(), 8) == 8;
        }

        public static bool API_WriteSingle(DataHnd hnd, float value)
        {
            Span<byte> bytes = stackalloc byte[4];
            BinaryPrimitives.WriteSingleLittleEndian(bytes, value);
            return API_WriteBuffer(hnd, bytes.ToArray(), 4) == 4;
        }

        public static bool API_WriteDouble(DataHnd hnd, double value)
        {
            Span<byte> bytes = stackalloc byte[8];
            BinaryPrimitives.WriteDoubleLittleEndian(bytes, value);
            return API_WriteBuffer(hnd, bytes.ToArray(), 8) == 8;
        }

        /// <summary>
        /// Writes a UTF‑8 encoded string, followed by a null terminator (#0), to the buffer.
        /// </summary>
        /// <exception cref="ArgumentNullException">Thrown when <paramref name="value"/> is null.</exception>
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
        //  READ OPERATIONS
        // --------------------------------------------------------------------

        public static long API_ReadBuffer(DataHnd hnd, byte[] buffer, long size) => Native_ReadBuffer(hnd, buffer, size);

        // --------------------------------------------------------------------
        //  ATOMIC READ HELPERS
        // --------------------------------------------------------------------
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
        /// Reads a null‑terminated UTF‑8 string from the current position.
        /// The position is advanced to the byte after the terminating null.
        /// </summary>
        /// <param name="hnd">Data handle.</param>
        /// <param name="value">Output string.</param>
        /// <returns>True if a null terminator was found; false if end of buffer reached.</returns>
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

            // Scan from startPos until we find a null or reach the end.
            long nullPos = startPos;
            while (nullPos < size)
            {
                // Marshal.ReadByte accepts an IntPtr and an int offset.
                // Since nullPos is long, we need to cast to int (safe as buffer size < 2GB in practice).
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

            // Advance position to after the null terminator
            API_SetPos(hnd, nullPos + 1);

            value = Encoding.UTF8.GetString(utf8Bytes);
            return true;
        }

        /// <summary>
        /// Reads a null‑terminated UTF‑8 string from the current position.
        /// Returns empty string if no null terminator is found.
        /// </summary>
        public static string API_ReadString(DataHnd hnd)
        {
            API_ReadString(hnd, out string value);
            return value;
        }

        // --------------------------------------------------------------------
        //  POSITION AND SIZE
        // --------------------------------------------------------------------
        public static long API_GetPos(DataHnd hnd) => Native_GetPos(hnd);
        public static void API_SetPos(DataHnd hnd, long pos) => Native_SetPos(hnd, pos);
        public static long API_GetSize(DataHnd hnd) => Native_GetSize(hnd);
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
        /// </summary>
        /// <exception cref="ArgumentNullException">Thrown when <paramref name="appName"/> is null.</exception>
        public static AppHnd API_Create_APPHnd(string appName, string desc)
        {
            if (appName == null)
                throw new ArgumentNullException(nameof(appName));
            IntPtr pName = UTF8Marshal.AllocUTF8(appName);
            IntPtr pDesc = UTF8Marshal.AllocUTF8(desc);
            try { return Native_Create_APPHnd(pName, pDesc); }
            finally { UTF8Marshal.FreeUTF8(pName); UTF8Marshal.FreeUTF8(pDesc); }
        }

        public static void API_Free_APPHnd(AppHnd appHnd) => Native_Free_APPHnd(appHnd);

        /// <summary>
        /// Registers a request‑response (Call) API within the application.
        /// </summary>
        /// <exception cref="ArgumentNullException">Thrown when <paramref name="apiName"/> is null.</exception>
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
        /// Registers a one‑way notification (Notify) API within the application.
        /// </summary>
        /// <exception cref="ArgumentNullException">Thrown when <paramref name="apiName"/> is null.</exception>
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
        /// Unregisters a previously registered API from the application.
        /// </summary>
        /// <exception cref="ArgumentNullException">Thrown when <paramref name="apiName"/> is null.</exception>
        public static int API_UnReg(AppHnd appHnd, string apiName)
        {
            if (apiName == null)
                throw new ArgumentNullException(nameof(apiName));
            IntPtr pName = UTF8Marshal.AllocUTF8(apiName);
            try { return Native_UnReg(appHnd, pName); }
            finally { UTF8Marshal.FreeUTF8(pName); }
        }

        public static DataHnd API_Local_APP_Call(AppHnd appHnd, DataHnd param) => Native_Local_APP_Call(appHnd, param);
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

        /// <exception cref="ArgumentNullException">Thrown when either parameter is null.</exception>
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

        /// <exception cref="ArgumentNullException">Thrown when <paramref name="physicsAddr"/> is null.</exception>
        public static int API_Prepare_Client(string physicsAddr, AppHnd appHnd)
        {
            if (physicsAddr == null)
                throw new ArgumentNullException(nameof(physicsAddr));
            IntPtr pPhysics = UTF8Marshal.AllocUTF8(physicsAddr);
            try { return Native_Prepare_Client(pPhysics, appHnd); }
            finally { UTF8Marshal.FreeUTF8(pPhysics); }
        }

        public static void API_Reset_Prepare() => Native_Reset_Prepare();
        public static int API_Prepare_Done() => Native_Prepare_Done();
        public static void API_Exit_MainThread() => Native_Exit_MainThread();

        /// <exception cref="ArgumentNullException">Thrown when <paramref name="appName"/> is null.</exception>
        public static DataHnd API_Call(string appName, DataHnd param, ulong timeout)
        {
            if (appName == null)
                throw new ArgumentNullException(nameof(appName));
            IntPtr pName = UTF8Marshal.AllocUTF8(appName);
            try { return Native_Call(pName, param, timeout); }
            finally { UTF8Marshal.FreeUTF8(pName); }
        }

        /// <exception cref="ArgumentNullException">Thrown when <paramref name="appName"/> is null.</exception>
        public static void API_Notify(string appName, DataHnd param)
        {
            if (appName == null)
                throw new ArgumentNullException(nameof(appName));
            IntPtr pName = UTF8Marshal.AllocUTF8(appName);
            try { Native_Notify(pName, param); }
            finally { UTF8Marshal.FreeUTF8(pName); }
        }

        /// <exception cref="ArgumentNullException">Thrown when either parameter is null.</exception>
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

        public static void API_shutdown() => Native_shutdown();

        #endregion

        #region Convenience Helper Methods

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

        public static long WriteBytes(DataHnd hnd, byte[] data)
        {
            return API_WriteBuffer(hnd, data, data.Length);
        }

        public static string ReadString(DataHnd hnd)
        {
            byte[] bytes = ReadAllBytes(hnd);
            int len = Array.IndexOf(bytes, (byte)0);
            if (len < 0) len = bytes.Length;
            return Encoding.UTF8.GetString(bytes, 0, len);
        }

        /// <exception cref="ArgumentNullException">Thrown when <paramref name="str"/> is null.</exception>
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
    }
}