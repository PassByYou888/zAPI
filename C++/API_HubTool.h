/**
 * @file API_HubTool.h
 * @brief C explicit‑linking wrapper for the API Hub dynamic library.
 *
 * This header provides a complete C binding to the functions exported by the
 * API Hub library. The library itself is built on the C4 distributed framework,
 * offering automatic service discovery, NAT traversal, and fault‑tolerant
 * communication over TCP and IPC.
 *
 * All API functions are resolved at runtime via platform‑specific dynamic
 * loading, so no static import library is required. The wrapper handles
 * library loading and unloading, and performs safety checks to prevent
 * crashes if the library is not loaded.
 *
 * @note This wrapper is intended for use from C and C++ (extern "C").
 *       All callback functions must use the `__cdecl` calling convention
 *       (on Windows) or the default C convention on other platforms.
 *
 * @section encoding_string UTF‑8 Encoding – MANDATORY
 * All string parameters of type `const char*` (including API names,
 * descriptions, and network addresses) **must be encoded in UTF‑8** and
 * **must be null‑terminated** (i.e., end with a byte of value 0).
 *
 * - UTF‑8 is a multi‑byte encoding where ASCII characters (0x00–0x7F)
 *   occupy one byte, and all other Unicode characters are encoded in
 *   2–4 bytes. The null terminator is the only zero byte in a well‑formed
 *   UTF‑8 string (unless the string itself contains a literal zero
 *   character, which is not allowed in C‑style strings).
 * - The library internally decodes UTF‑8 input into Pascal Unicode strings,
 *   and encodes outgoing strings to UTF‑8.
 * - This encoding is **platform‑independent** and works identically on
 *   Windows, Linux, macOS, and BSD.
 *
 * *Important*: Do **not** use the system ANSI codepage (e.g., CP_ACP on
 * Windows). Always pass UTF‑8 bytes.
 *
 * @section usage_typical Typical Usage Pattern
 * 1. Call API_LoadLibrary() once at program startup.
 * 2. Create an application handle with API_Create_APPHnd().
 * 3. Register your API callbacks using API_Reg_Call() or API_Reg_Notify().
 * 4. Prepare network services/clients with API_Prepare_Service() and
 *    API_Prepare_Client().
 * 5. Start the framework with API_Prepare_Done().
 * 6. Invoke remote APIs with API_Call() (synchronous) or API_Notify().
 * 7. On shutdown, call API_Exit_MainThread(), then API_shutdown(),
 *    and finally API_FreeLibrary().
 *
 * @section critical_notes Critical Notes for Developers
 *
 * - **Thread Safety**: All functions are **fully thread‑safe**. They can be
 *   called concurrently from any thread without external synchronization.
 *
 *   However, for a given TDataHnd, write operations (API_WriteBuffer,
 *   API_SetPos, API_SetSize) should be serialized across threads because they
 *   modify the internal buffer state. Read‑only operations (API_GetBuffer,
 *   API_GetPos, API_GetSize) are safe even while another thread is writing,
 *   as long as the handle is not being freed.
 *
 *   Different TDataHnd instances are independent and can be used concurrently
 *   without any restrictions.
 *
 * - **Callback Execution Context** (⚠️ CRITICAL): The callbacks (TAPI_Call,
 *   TAPI_Notify) are **executed in background threads** from the library's
 *   internal thread pool.
 *
 *   This means:
 *     * **DO NOT** perform long‑blocking operations inside callbacks.
 *     * **DO NOT** call API_Call() or API_Notify() from within a callback –
 *       this may cause deadlocks because the callback thread may hold internal
 *       locks. If you need to make a remote call, offload the request to a
 *       separate worker thread and return quickly.
 *     * **DO NOT** access UI components or thread‑local storage without
 *       proper synchronization.
 *     * Offload heavy processing to a separate thread or queue to keep
 *       callbacks responsive.
 *
 *   The library guarantees that callbacks are thread‑safe and reentrant,
 *   but it is your responsibility to ensure that any shared data accessed
 *   from callbacks is properly synchronized.
 *
 * - **Execution Order**: The library does **not** guarantee the order of
 *   execution for concurrent API calls. Calls are independent and may be
 *   executed out‑of‑order because the underlying service mesh distributes
 *   requests across multiple application instances for load balancing.
 *   If you send calls '1', '2', '3' in that order, the remote side may
 *   process them in any order (e.g., '2', '1', '3'). Only the per‑call
 *   request‑response semantics are reliable – each call is atomic and
 *   returns a correct result, but the global ordering is not preserved.
 *
 * - **Data Handles**: Every TDataHnd created with API_Create_DataHnd() MUST
 *   be freed with API_Free_DataHnd(). The library does NOT auto‑free them.
 *
 * - **Callbacks**: Must be `__cdecl`; avoid blocking operations.
 *
 * - **Timeouts**: API_Call() timeout is in milliseconds; 0 means infinite.
 *
 * - **App Names**: Case‑sensitive, should be unique across the network.
 *
 * - **Cross‑Platform**: Works on Windows, Linux, and macOS. When linking,
 *   add `-ldl` on Linux/macOS (no extra libs on Windows).
 *
 * @section example_minimal Minimal Example (C++)
 * @code
 * #include "API_HubTool.h"
 * #include <iostream>
 *
 * static void __cdecl AddCallback(void*, void* Input, void* Output) {
 *     int a, b;
 *     API_ReadBuffer((TDataHnd)Input, &a, sizeof(a));
 *     API_ReadBuffer((TDataHnd)Input, &b, sizeof(b));
 *     int sum = a + b;
 *     API_WriteBuffer((TDataHnd)Output, &sum, sizeof(sum));
 * }
 *
 * int main() {
 *     if (!API_LoadLibrary()) return 1;
 *     TAppHnd app = API_Create_APPHnd("Demo", "Example");
 *     API_Reg_Call(app, "add", "Add two ints", nullptr, AddCallback);
 *     TDataHnd data = API_Create_DataHnd("add");
 *     int a=5, b=7;
 *     API_WriteBuffer(data, &a, sizeof(a));
 *     API_WriteBuffer(data, &b, sizeof(b));
 *     TDataHnd result = API_Local_APP_Call(app, data);
 *     API_Free_DataHnd(data);
 *     if (result) { int sum; API_ReadBuffer(result, &sum, sizeof(sum)); }
 *     API_Free_DataHnd(result);
 *     API_Free_APPHnd(app);
 *     API_shutdown();
 *     API_FreeLibrary();
 *     return 0;
 * }
 * @endcode
 */

#pragma once

#include <stdint.h>   // for int64_t, uint64_t

#ifdef __cplusplus
extern "C" {
#endif

    /* ============================================================================
       Opaque handle types
       ============================================================================ */

       /**
        * @brief Opaque handle to a binary data buffer that holds an API name and
        *        its associated payload.
        *
        * A TDataHnd is used for both input parameters and output results. It must be
        * created with API_Create_DataHnd() and destroyed with API_Free_DataHnd().
        * The buffer can be read, written, and resized using the provided functions.
        *
        * @see API_Create_DataHnd, API_Free_DataHnd, API_WriteBuffer, API_ReadBuffer
        */
    typedef void* TDataHnd;

    /**
     * @brief Opaque handle to an application context that groups a set of APIs.
     *
     * Each application has a unique name and can register multiple call‑mode or
     * notify‑mode APIs. The handle is created with API_Create_APPHnd() and must
     * be freed with API_Free_APPHnd().
     *
     * @see API_Create_APPHnd, API_Free_APPHnd, API_Reg_Call, API_Reg_Notify
     */
    typedef void* TAppHnd;

    /* ============================================================================
       Callback function types
       ============================================================================ */

       /**
        * @brief Callback signature for request‑response (call) APIs.
        *
        * This function is invoked when a remote client calls a registered API.
        * It reads input from @p Input, processes it, and writes the result to
        * @p Output. The callback must not block for long periods.
        *
        * @param Trigger   User‑supplied pointer as given to API_Reg_Call().
        * @param Input     Read‑only input data handle (do NOT free it).
        * @param Output    Write‑only output data handle (write the response here;
        *                  do NOT free it).
        *
        * @note The callback must use the `__cdecl` calling convention.
        * @warning This callback is executed in a background thread‑pool thread.
        *          **DO NOT** call API_Call() or API_Notify() from inside the callback,
        *          as this may cause deadlocks. Also avoid long‑blocking operations.
        *          Offload heavy work to separate threads.
        *
        * @see API_Reg_Call
        *
        * @code
        * static void __cdecl MyEcho(void* Trigger, void* Input, void* Output) {
        *     TDataHnd hIn = (TDataHnd)Input, hOut = (TDataHnd)Output;
        *     int64_t size = API_GetSize(hIn);
        *     char* buf = (char*)malloc((size_t)size);
        *     API_SetPos(hIn, 0);
        *     API_ReadBuffer(hIn, buf, size);
        *     API_WriteBuffer(hOut, buf, size);
        *     free(buf);
        * }
        * @endcode
        */
    typedef void(__cdecl* TAPI_Call)(void* Trigger, void* Input, void* Output);

    /**
     * @brief Callback signature for one‑way notification APIs.
     *
     * This function is invoked when a notification is received. It processes the
     * input data but does not produce any output. The callback must not block.
     *
     * @param Trigger   User‑supplied pointer as given to API_Reg_Notify().
     * @param Input     Read‑only input data handle (do NOT free it).
     *
     * @note Must be `__cdecl`.
     * @warning Same callback context restrictions as TAPI_Call: runs in a
     *          background thread; do not call API_Call/API_Notify inside it.
     *
     * @see API_Reg_Notify
     *
     * @code
     * static void __cdecl MyLogger(void* Trigger, void* Input) {
     *     TDataHnd hIn = (TDataHnd)Input;
     *     const char* msg = (const char*)API_GetBuffer(hIn);
     *     printf("Notification: %s\n", msg);
     * }
     * @endcode
     */
    typedef void(__cdecl* TAPI_Notify)(void* Trigger, void* Input);

    /* ============================================================================
       Library loading / unloading
       ============================================================================ */

       /**
        * @brief Loads the dynamic library and resolves all function pointers.
        *
        * This function must be called before any other API function. It searches for
        * the library in the executable's directory first, then falls back to the
        * system path. Platform‑specific library names are used:
        *   - Windows: z_api_hub64.dll (64‑bit) or z_api_hub32.dll (32‑bit)
        *   - Linux: libz_api_hub.so
        *   - macOS: libz_api_hub.dylib
        *
        * @return 1 on success, 0 on failure.
        *
        * @see API_FreeLibrary
        *
        * @code
        * if (!API_LoadLibrary()) {
        *     fprintf(stderr, "Failed to load API Hub library.\n");
        *     exit(1);
        * }
        * @endcode
        */
    int API_LoadLibrary(void);

    /**
     * @brief Unloads the dynamic library and resets all function pointers.
     *
     * Call this at program exit to release the library. After this call, no other
     * API function should be used.
     *
     * @see API_LoadLibrary
     */
    void API_FreeLibrary(void);

    /* ============================================================================
       Data handle operations
       ============================================================================ */

       /**
        * @brief Creates a new data handle initialized with the given API name.
        *
        * The handle is initially empty (size = 0). Use API_WriteBuffer() to add data.
        * The API name is used for routing when the handle is sent in a call or
        * notification.
        *
        * @param APIName   Null‑terminated **UTF‑8** string specifying the target API name.
        * @return A new TDataHnd, or NULL on failure. Must be freed with
        *         API_Free_DataHnd().
        *
        * @see API_Free_DataHnd, API_WriteBuffer, API_ReadBuffer
        *
        * @code
        * TDataHnd h = API_Create_DataHnd("my_api");
        * if (h) {
        *     int data = 42;
        *     API_WriteBuffer(h, &data, sizeof(data));
        *     // ... use h ...
        *     API_Free_DataHnd(h);
        * }
        * @endcode
        */
    TDataHnd API_Create_DataHnd(const char* APIName);

    /**
     * @brief Destroys a data handle and releases its internal resources.
     *
     * After this call, the handle is invalid and must not be used again.
     *
     * @param Hnd   The data handle to free.
     *
     * @see API_Create_DataHnd
     */
    void API_Free_DataHnd(TDataHnd Hnd);

    /**
     * @brief Returns a pointer to the raw binary data stored in the handle.
     *
     * The pointer is valid until the handle is freed or its buffer is resized.
     * Do not free this pointer; it is managed internally.
     *
     * @param Hnd   The data handle.
     * @return Pointer to the internal buffer, or NULL if the handle is invalid
     *         or empty.
     *
     * @note This pointer is read‑only; modifying it may corrupt the internal state.
     *
     * @code
     * const char* data = (const char*)API_GetBuffer(h);
     * int64_t size = API_GetSize(h);
     * // process data[0..size-1]
     * @endcode
     */
    void* API_GetBuffer(TDataHnd Hnd);

    /**
     * @brief Appends binary data to the handle's buffer at the current position.
     *
     * The internal position is advanced by the number of bytes written.
     * The buffer is automatically enlarged if necessary.
     *
     * @param Hnd   The data handle.
     * @param Buff  Pointer to the source data.
     * @param Size  Number of bytes to write.
     * @return The number of bytes actually written (normally equals Size unless
     *         an error occurs).
     *
     * @see API_ReadBuffer, API_SetPos, API_GetPos
     *
     * @code
     * int nums[] = {1, 2, 3};
     * int64_t written = API_WriteBuffer(h, nums, sizeof(nums));
     * @endcode
     */
    int64_t API_WriteBuffer(TDataHnd Hnd, const void* Buff, int64_t Size);

    /**
     * @brief Reads binary data from the handle's buffer into the caller's buffer.
     *
     * The internal position is advanced by the number of bytes read. If the end
     * of the buffer is reached, fewer bytes may be read.
     *
     * @param Hnd   The data handle.
     * @param Buff  Pointer to the destination buffer.
     * @param Size  Maximum number of bytes to read.
     * @return The number of bytes actually read (less than Size if end‑of‑buffer).
     *
     * @see API_WriteBuffer, API_SetPos, API_GetPos
     *
     * @code
     * int nums[3];
     * int64_t read = API_ReadBuffer(h, nums, sizeof(nums));
     * @endcode
     */
    int64_t API_ReadBuffer(TDataHnd Hnd, void* Buff, int64_t Size);

    /**
     * @brief Returns the current read/write position within the data handle.
     *
     * The position is a 0‑based offset from the start of the buffer.
     *
     * @param Hnd   The data handle.
     * @return The current position, or 0 on error.
     *
     * @see API_SetPos
     */
    int64_t API_GetPos(TDataHnd Hnd);

    /**
     * @brief Sets the current read/write position within the data handle.
     *
     * The new position must be between 0 and the size of the buffer. If the
     * position is set beyond the current size, the buffer may be extended with
     * zero bytes.
     *
     * @param Hnd   The data handle.
     * @param Pos_  The new position (0‑based).
     *
     * @see API_GetPos
     */
    void API_SetPos(TDataHnd Hnd, int64_t Pos_);

    /**
     * @brief Returns the total size (in bytes) of the data stored in the handle.
     *
     * @param Hnd   The data handle.
     * @return The current size of the internal buffer, or 0 on error.
     *
     * @see API_SetSize
     */
    int64_t API_GetSize(TDataHnd Hnd);

    /**
     * @brief Resizes the internal buffer of the data handle.
     *
     * If the new size is larger, the new space is uninitialised. If smaller,
     * data beyond the new size is discarded. The current position is not adjusted.
     *
     * @param Hnd    The data handle.
     * @param Size_  The new desired size in bytes.
     *
     * @see API_GetSize
     */
    void API_SetSize(TDataHnd Hnd, int64_t Size_);

    /* ============================================================================
       Application handle operations
       ============================================================================ */

       /**
        * @brief Creates a new application context.
        *
        * The application name must be unique across the network (case‑sensitive).
        * The description is for human readability and can be NULL or empty.
        *
        * @param appName   Unique name for the application (**UTF‑8**).
        * @param Desc      Human‑readable description (**UTF‑8**, can be NULL).
        * @return A new TAppHnd, or NULL on failure. Must be freed with
        *         API_Free_APPHnd().
        *
        * @see API_Free_APPHnd
        *
        * @code
        * TAppHnd app = API_Create_APPHnd("my_app", "My test application");
        * @endcode
        */
    TAppHnd API_Create_APPHnd(const char* appName, const char* Desc);

    /**
     * @brief Destroys an application context and releases all its registered APIs.
     *
     * After this call, the handle is invalid.
     *
     * @param appHnd    The application handle to free.
     *
     * @see API_Create_APPHnd
     */
    void API_Free_APPHnd(TAppHnd appHnd);

    /**
     * @brief Registers a request‑response (call) API within the application.
     *
     * The API name must be unique within the application (case‑sensitive). When a
     * remote client calls this API, the provided callback @p OnCall is invoked.
     *
     * @param appHnd    The application handle.
     * @param APIName   Unique name for this API within the app (**UTF‑8**).
     * @param Desc      Human‑readable description (**UTF‑8**, can be NULL).
     * @param Trigger   User data pointer passed to the callback (can be NULL).
     * @param OnCall    The callback function to execute (must be `__cdecl`).
     * @return 1 if successful, 0 if an API with the same name already exists.
     *
     * @see TAPI_Call, API_Reg_Notify
     *
     * @code
     * static void __cdecl MyEcho(void* Trigger, void* Input, void* Output) {
     *     // echo input to output
     * }
     * ...
     * int ret = API_Reg_Call(app, "echo", "Echoes input", NULL, MyEcho);
     * @endcode
     */
    int API_Reg_Call(TAppHnd appHnd, const char* APIName, const char* Desc,
        void* Trigger, TAPI_Call OnCall);

    /**
     * @brief Registers a one‑way notification API within the application.
     *
     * When a notification is received, the callback @p OnNotify is invoked with
     * the input data. No response is sent back.
     *
     * @param appHnd    The application handle.
     * @param APIName   Unique name for this API within the app (**UTF‑8**).
     * @param Desc      Human‑readable description (**UTF‑8**, can be NULL).
     * @param Trigger   User data pointer passed to the callback.
     * @param OnNotify  The callback function to execute (must be `__cdecl`).
     * @return 1 if successful, 0 if an API with the same name already exists.
     *
     * @see TAPI_Notify, API_Reg_Call
     *
     * @code
     * static void __cdecl MyLogger(void* Trigger, void* Input) {
     *     // process Input
     * }
     * ...
     * int ret = API_Reg_Notify(app, "log", "Logs events", NULL, MyLogger);
     * @endcode
     */
    int API_Reg_Notify(TAppHnd appHnd, const char* APIName, const char* Desc,
        void* Trigger, TAPI_Notify OnNotify);

    /**
     * @brief Unregisters a previously registered API from the application.
     *
     * This function removes the API from the local registry immediately and
     * triggers a network update broadcast. After calling API_UnReg, the change
     * is propagated to all connected C4 services and clients within approximately
     * 3 seconds (depending on network latency and the C4 update interval). Once
     * propagated, the API will no longer be discoverable or callable by remote peers.
     *
     * @param appHnd   The application handle.
     * @param APIName  The name of the API to unregister (**UTF‑8**).
     * @return 1 on success, 0 if the API name does not exist.
     *
     * @note The application's internal API registry is updated immediately,
     *       but the network broadcast is asynchronous. Subsequent remote
     *       calls may still be delivered for a short window (up to ~3 seconds)
     *       until all peers have received the update.
     *
     * @see API_Reg_Call, API_Reg_Notify
     *
     * @code
     * if (API_UnReg(app, "add") == 1) {
     *     printf("API 'add' unregistered, broadcast in progress.\n");
     * }
     * @endcode
     */
    int API_UnReg(TAppHnd appHnd, const char* APIName);

    /**
     * @brief Executes a call API locally within the same application.
     *
     * This bypasses the network and invokes the registered callback directly in
     * the caller's thread. Useful for testing or internal calls.
     *
     * @param appHnd    The application handle.
     * @param Param     Input data handle (must contain the API name and parameters).
     * @return A new data handle containing the result. The caller is responsible
     *         for freeing it with API_Free_DataHnd().
     *
     * @see API_Call, API_Local_APP_Notify
     *
     * @code
     * TDataHnd data = API_Create_DataHnd("echo");
     * API_WriteBuffer(data, "Hello", 6);
     * TDataHnd result = API_Local_APP_Call(app, data);
     * API_Free_DataHnd(data);
     * // process result...
     * API_Free_DataHnd(result);
     * @endcode
     */
    TDataHnd API_Local_APP_Call(TAppHnd appHnd, TDataHnd Param);

    /**
     * @brief Sends a notification locally within the same application.
     *
     * The notification callback is invoked synchronously in the caller's thread.
     * No result is produced.
     *
     * @param appHnd    The application handle.
     * @param Param     Input data handle containing the API name and payload.
     *
     * @see API_Local_APP_Call, API_Notify
     *
     * @code
     * TDataHnd data = API_Create_DataHnd("event");
     * API_WriteBuffer(data, "Event data", 11);
     * API_Local_APP_Notify(app, data);
     * API_Free_DataHnd(data);
     * @endcode
     */
    void API_Local_APP_Notify(TAppHnd appHnd, TDataHnd Param);

    /* ============================================================================
       Network preparation and communication
       ============================================================================ */

       /**
        * @brief Adds a service (listener) to the preparation list.
        *
        * The service will listen on the given address and advertise the provided
        * public address to clients. Supported address formats:
        * - IPv4: "0.0.0.0", "127.0.0.1", "192.168.1.100"
        * - IPv6: "[::1]:8080" or "::1|8080"
        * - Domain: "myhost.com:9090"
        * - IPC: "ipc:my_service" (OS‑specific named pipe / shared memory)
        * If the port is omitted, default 9898 is used (except for IPC, which uses
        * port 0).
        *
        * All address strings must be **UTF‑8** encoded.
        *
        * @param ListeningAddr_   Address to bind to (local, **UTF‑8**).
        * @param PhysicsAddr_     Public address advertised to clients (**UTF‑8**).
        * @return A tag (ID) for this service (currently not used).
        *
        * @note The service does not start until API_Prepare_Done() is called.
        * @see API_Reset_Prepare, API_Prepare_Done
        *
        * @code
        * API_Reset_Prepare();
        * API_Prepare_Service("0.0.0.0", "127.0.0.1:9898");   // TCP service
        * API_Prepare_Service("ipc:test", "ipc:test");         // IPC service
        * API_Prepare_Client("127.0.0.1:9898", app);
        * API_Prepare_Done();
        * @endcode
        */
    int API_Prepare_Service(const char* ListeningAddr_, const char* PhysicsAddr_);

    /**
     * @brief Adds a client connection to the preparation list.
     *
     * The client will connect to the remote service at @p PhysicsAddr_. If an
     * application handle @p appHnd is provided, it will be automatically registered
     * with the service once the connection is established.
     *
     * @param PhysicsAddr_   Address of the remote service (**UTF‑8**).
     * @param appHnd         Optional application handle (can be NULL).
     * @return A tag (ID) for this client.
     *
     * @note The client will automatically reconnect if the connection is lost.
     * @see API_Reset_Prepare, API_Prepare_Done
     *
     * @code
     * API_Prepare_Client("127.0.0.1:9898", NULL);   // only consume
     * API_Prepare_Client("ipc:test", app);          // provide APIs via app
     * @endcode
     */
    int API_Prepare_Client(const char* PhysicsAddr_, TAppHnd appHnd);

    /**
     * @brief Clears all previously prepared services and clients.
     *
     * Call this before preparing a new set of services/clients, especially if you
     * want to change the configuration and restart.
     *
     * @see API_Prepare_Service, API_Prepare_Client
     */
    void API_Reset_Prepare(void);

    /**
     * @brief Starts the entire C4 framework with the prepared services and clients.
     *
     * This function blocks until the network is initialised and the simulated main
     * thread is running. After a successful return, you can invoke remote APIs.
     *
     * @return 1 on success, 0 on failure (check console/log output for errors).
     *
     * @note Do not call this more than once without resetting or shutting down.
     * @see API_Reset_Prepare, API_shutdown, API_Exit_MainThread
     *
     * @code
     * if (API_Prepare_Done() == 1) {
     *     // framework is running
     * } else {
     *     // check error messages from the library's logging
     * }
     * @endcode
     */
    int API_Prepare_Done(void);

    /**
     * @brief Signals the internal main thread to exit gracefully.
     *
     * After calling this, the network loop will stop, but resources are not
     * automatically freed. You should still call API_shutdown() to clean up.
     *
     * @see API_shutdown
     */
    void API_Exit_MainThread(void);

    /**
     * @brief Performs a remote (or local) call to the specified application.
     *
     * This function blocks until a response is received or the timeout expires.
     * The input data handle @p Param is cloned internally; you still must free it
     * with API_Free_DataHnd() after the call.
     *
     * @param appName    Name of the target application (**UTF‑8**).
     * @param Param      Input data handle (contains API name and parameters).
     * @param Timeout_   Maximum wait time in milliseconds (0 = infinite).
     * @return A new data handle containing the result. Must be freed with
     *         API_Free_DataHnd(). If the call fails or times out, the handle will
     *         have size 0.
     *
     * @warning This function is thread‑safe, but the order of concurrent calls is
     *          **not** guaranteed (see Critical Notes above).
     *
     * @see API_Notify, API_Local_APP_Call
     *
     * @code
     * TDataHnd data = API_Create_DataHnd("echo");
     * API_WriteBuffer(data, "Hello", 6);
     * TDataHnd result = API_Call("my_app", data, 5000);
     * API_Free_DataHnd(data);
     * if (API_GetSize(result) > 0) {
     *     // process result
     * }
     * API_Free_DataHnd(result);
     * @endcode
     */
    TDataHnd API_Call(const char* appName, TDataHnd Param, uint64_t Timeout_);

    /**
     * @brief Sends a one‑way notification to the specified application.
     *
     * This function returns immediately; delivery is best‑effort. The input handle
     * @p Param is cloned internally; you must still free it with API_Free_DataHnd().
     *
     * @param appName    Name of the target application (**UTF‑8**).
     * @param Param      Input data handle (contains API name and payload).
     *
     * @see API_Call, API_Local_APP_Notify
     *
     * @code
     * TDataHnd data = API_Create_DataHnd("event");
     * API_WriteBuffer(data, "Event data", 11);
     * API_Notify("my_app", data);
     * API_Free_DataHnd(data);
     * @endcode
     */
    void API_Notify(const char* appName, TDataHnd Param);

    /**
     * @brief Dynamically adjusts global runtime options of the API Hub framework.
     *
     * All changes take effect immediately for subsequent operations (except where
     * noted). This function is intended for runtime tuning without restarting the
     * application or modifying the .ini file. Unknown options are silently ignored.
     *
     * @param Option  Configuration key (**UTF‑8**, case‑insensitive). The following
     *                keys are supported (aliases are accepted):
     *                - "password" / "passwd"   : Sets the C4 P2PVM authentication
     *                  token. This password is used for all new P2PVM connections
     *                  (existing connections are unaffected). It is crucial for
     *                  secure inter‑communication between zAPI components.
     *                  **IMPORTANT**: This must match on both service and client
     *                  sides for successful handshake.
     *                - "Quiet"                : Enable/disable quiet mode (True/False).
     *                  Suppresses most debug logs.
     *                - "External_Conf_Auto_Save" / "Conf_Auto_Save" : Enable/disable
     *                  automatic saving of the current configuration to the .ini file
     *                  on program exit (True/False). Default is True.
     *                - "Wait_Connection_ReadyOk" / "Wait_API_Prepare_Done" /
     *                  "API_Prepare_Done_Wait" / "WaitConnect" / "Wait_Ready" /
     *                  "WaitReady" : Control whether API_Prepare_Done blocks
     *                  until all prepared clients have successfully connected and
     *                  registered their applications. **This is particularly
     *                  important for deployment scenarios**: when set to False,
     *                  the library starts immediately without waiting, and clients
     *                  will automatically connect later when the server becomes
     *                  available (auto‑reconnection). This allows services to
     *                  start independently of the network topology.
     *                - "Wait_Connection_Timeout" / "Wait_TimeOut" / ... : Sets the
     *                  maximum waiting time (in milliseconds) when
     *                  Wait_Connection_ReadyOk is True. Default is 30000.
     *                - "ShowThreadID" / "ShowThread" / "Show_Thread" : Toggle
     *                  display of thread IDs in log messages (True/False).
     *                - "ConsoleOutput" / "Console_Output" : Toggle console
     *                  (stdout/stderr) logging (True/False).
     *                - "IPC_Serv_ThreadCount" / "IPC_ThreadCount" / "IPC_Server_ThreadCount":
     *                  Number of threads in the IPC service thread pool.
     *                - "IPC_Serv_MaxQueueLength" / "IPC_MaxQueueLength" / "IPC_Server_MaxQueueLength":
     *                  Maximum length of the IPC message queue.
     *                - "IPC_Serv_MaxMsgSize" / "IPC_MaxMsgSize" / "IPC_Server_MaxMsgSize":
     *                  Maximum size (in bytes) of a single IPC message.
     *
     * @param Value   New value (**UTF‑8**). For boolean options, accepted values are
     *                "True"/"False", "1"/"0", "Yes"/"No".
     *
     * @note This function has no return value; unknown options are silently ignored.
     *       Changes to the password and wait‑control options are critical for
     *       secure and flexible deployment.
     *
     * @see API_Prepare_Done
     *
     * @code
     * // Example: set authentication password before starting
     * API_SetOption("password", "my_secret_token");
     * // Example: allow clients to connect later
     * API_SetOption("Wait_Connection_ReadyOk", "False");
     * @endcode
     */
    void API_SetOption(const char* Option, const char* Value);

    /**
     * @brief Gracefully shuts down the entire API Hub framework.
     *
     * This stops all services, disconnects all clients, and releases internal
     * resources. After calling this, the library state is reset and you can
     * potentially re‑initialise by calling Prepare functions again.
     *
     * @see API_Exit_MainThread
     */
    void API_shutdown(void);

#ifdef __cplusplus
}
#endif