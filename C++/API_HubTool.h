/**
 * @file API_HubTool.h
 * @brief C explicit‑linking wrapper – strictly matches Pascal export table.
 *
 * All functions declared here are either directly exported from the dynamic
 * library (the 30 functions marked as 'exported') or implemented as helpers
 * in the C wrapper itself using API_WriteBuffer / API_ReadBuffer.
 *
 * @section export_table Exported Functions (30 total)
 * 1  API_shutdown
 * 2  API_SetOption
 * 3  API_Notify
 * 4  API_Call
 * 5  API_Exit_MainThread
 * 6  API_Prepare_Done
 * 7  API_Reset_Prepare
 * 8  API_Prepare_Client
 * 9  API_Prepare_Service
 * 10 API_Local_APP_Notify
 * 11 API_Local_APP_Call
 * 12 API_UnReg
 * 13 API_Reg_Notify
 * 14 API_Reg_Call
 * 15 API_Free_APPHnd
 * 16 API_Create_APPHnd
 * 17 API_SetSize
 * 18 API_GetSize
 * 19 API_SetPos
 * 20 API_GetPos
 * 21 API_ReadBuffer
 * 22 API_WriteBuffer
 * 23 API_GetBuffer
 * 24 API_Free_DataHnd
 * 25 API_Create_DataHnd
 * 26 API_Check_MainThread   (新增)
 * 27 API_Check_App          (新增)
 * 28 API_Get_Status_Num     (新增)
 * 29 API_Get_Status         (新增)
 * 30 API_Post_Status        (新增)
 *
 * ============================================================================
 * STRING ENCODING – UTF-8 IS MANDATORY
 * ============================================================================
 * All string parameters (API names, descriptions, network addresses, etc.)
 * MUST be encoded in **UTF-8** and MUST be null-terminated (i.e., end with a
 * byte of value 0).
 *
 * - UTF-8 is a multi-byte encoding where ASCII characters (0x00–0x7F) occupy
 *   one byte, and all other Unicode characters are encoded in 2–4 bytes.
 * - The null terminator is the only zero byte in a well-formed UTF-8 string.
 * - The library internally decodes UTF-8 input into Unicode, and encodes
 *   outgoing strings to UTF-8.
 * - This encoding is **platform-independent** and works identically on
 *   Windows, Linux, macOS, and BSD.
 *
 * *Important*: Do **not** use the system ANSI codepage (e.g., CP_ACP on
 * Windows). All strings are explicitly marshaled as UTF-8.
 *
 * ============================================================================
 * IMPORTANT NOTES & BEST PRACTICES (READ BEFORE USING)
 * ============================================================================
 *
 * 1. **THREAD SAFETY**:
 *    All exported functions are **fully thread-safe**. They can be called
 *    concurrently from any thread without external synchronization.
 *
 *    However, for a given TDataHnd, write operations (API_WriteBuffer,
 *    API_SetPos, API_SetSize) should be serialised across threads because they
 *    modify the internal buffer state. Read‑only operations (API_GetBuffer,
 *    API_GetPos, API_GetSize) are safe even while another thread is writing,
 *    as long as the handle is not being freed.
 *
 *    Different TDataHnd instances are independent and can be used concurrently
 *    without any restrictions.
 *
 * 2. **CALLBACK EXECUTION CONTEXT** (⚠️ CRITICAL):
 *    Your callbacks (TAPI_Call, TAPI_Notify) are **executed in background
 *    threads** from the library's internal thread pool.
 *
 *    This means:
 *      * **DO NOT** perform long‑blocking operations inside callbacks.
 *      * **DO NOT** call API_Call() or API_Notify() from within a callback –
 *        this may cause deadlocks because the callback thread may hold internal
 *        locks. If you need to make a remote call, offload the request to a
 *        separate worker thread and return quickly.
 *      * **DO NOT** access UI components or thread‑local storage without
 *        proper synchronization (e.g., using a message queue).
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
 *    Every TDataHnd created with API_Create_DataHnd() MUST be freed with
 *    API_Free_DataHnd() when no longer needed. The library does NOT auto‑free
 *    them, even after remote calls (it clones the input internally).
 *
 * 5. **RESULT HANDLES**:
 *    API_Call() always returns a valid TDataHnd (never a null handle). If the
 *    call times out or fails, the handle size will be 0. You must still free
 *    it with API_Free_DataHnd().
 *
 * 6. **TIMEOUTS**:
 *    API_Call() timeout is in milliseconds. 0 means infinite wait (use with
 *    caution). On timeout, the returned handle size is 0.
 *
 * 7. **APPLICATION NAMES**:
 *    App names are case‑sensitive and should be unique across the network.
 *
 * 8. **DYNAMIC UNREGISTRATION (API_UnReg)**:
 *    - Immediately removes the API from the local registry.
 *    - Triggers an asynchronous network broadcast to all connected peers.
 *    - Remote peers stop seeing this API within approximately 3 seconds
 *      (depending on network latency and the C4 update interval).
 *    - During this short window, remote calls may still be attempted; they will
 *      fail gracefully (the remote side receives a "not found" error).
 *
 * 9. **RUNTIME OPTIONS (API_SetOption)**:
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
 * 10. **STATUS LOGGING** (新增):
 *     - API_Get_Status_Num() returns the number of pending log messages.
 *     - API_Get_Status() retrieves the next message (UTF‑8, null‑terminated) from an
 *       internal static buffer. The pointer is valid until the next call.
 *     - API_Post_Status() injects custom log messages into the same queue.
 *     - This is useful for integrating external logging with the library's internal logs.
 */

#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

    /* ============================================================================
       Opaque handle types
       ============================================================================ */
    typedef void* TDataHnd;
    typedef void* TAppHnd;

    /* ============================================================================
       Callback types
       ============================================================================ */
    typedef void(__cdecl* TAPI_Call)(void* Trigger, void* Input, void* Output);
    typedef void(__cdecl* TAPI_Notify)(void* Trigger, void* Input);

    /* ============================================================================
       Library loading / unloading
       ============================================================================ */
       /**
        * @brief Loads the API Hub dynamic library.
        * @return 1 on success, 0 on failure.
        * @note Must be called before any other API function.
        */
    int  API_LoadLibrary(void);

    /**
     * @brief Unloads the dynamic library and clears all function pointers.
     */
    void API_FreeLibrary(void);

    /* ============================================================================
       30 EXPORTED FUNCTIONS (matches Pascal external declarations)
       ============================================================================ */

       /* ----- Data Handle ----- */
    TDataHnd API_Create_DataHnd(const char* APIName);
    void     API_Free_DataHnd(TDataHnd Hnd);
    void* API_GetBuffer(TDataHnd Hnd);
    int64_t  API_WriteBuffer(TDataHnd Hnd, const void* Buff, int64_t Size);
    int64_t  API_ReadBuffer(TDataHnd Hnd, void* Buff, int64_t Size);
    int64_t  API_GetPos(TDataHnd Hnd);
    void     API_SetPos(TDataHnd Hnd, int64_t Pos_);
    int64_t  API_GetSize(TDataHnd Hnd);
    void     API_SetSize(TDataHnd Hnd, int64_t Size_);

    /* ----- Application Handle ----- */
    TAppHnd  API_Create_APPHnd(const char* appName, const char* Desc);
    void     API_Free_APPHnd(TAppHnd appHnd);
    int      API_Reg_Call(TAppHnd appHnd, const char* APIName, const char* Desc,
        void* Trigger, TAPI_Call OnCall);
    int      API_Reg_Notify(TAppHnd appHnd, const char* APIName, const char* Desc,
        void* Trigger, TAPI_Notify OnNotify);
    int      API_UnReg(TAppHnd appHnd, const char* APIName);
    TDataHnd API_Local_APP_Call(TAppHnd appHnd, TDataHnd Param);
    void     API_Local_APP_Notify(TAppHnd appHnd, TDataHnd Param);

    /* ----- Network and Remote Calls ----- */
    int      API_Prepare_Service(const char* ListeningAddr_, const char* PhysicsAddr_);
    int      API_Prepare_Client(const char* PhysicsAddr_, TAppHnd appHnd);
    void     API_Reset_Prepare(void);
    int      API_Prepare_Done(void);
    void     API_Exit_MainThread(void);
    TDataHnd API_Call(const char* appName, TDataHnd Param, uint64_t Timeout_);
    void     API_Notify(const char* appName, TDataHnd Param);
    void     API_SetOption(const char* Option, const char* Value);
    void     API_shutdown(void);

    /* ----- Status and Checks (新增) ----- */
    /**
     * @brief Checks whether the simulated main thread (the C4 event loop) is running.
     * @return 1 if running, 0 if stopped or not yet started.
     */
    int      API_Check_MainThread(void);

    /**
     * @brief Checks whether an application with the given name is available on the network.
     *        This query is based on a local cache and may be slightly stale.
     * @param appName Application name (UTF‑8, case‑sensitive).
     * @return 1 if at least one instance exists, 0 otherwise.
     */
    int      API_Check_App(const char* appName);

    /**
     * @brief Returns the number of pending log messages in the internal status queue.
     * @return Number of messages.
     */
    int      API_Get_Status_Num(void);

    /**
     * @brief Retrieves the next log message from the status queue (FIFO order).
     *        The returned pointer points to a static internal buffer; the data is
     *        valid until the next call to this function.
     *        The message is UTF‑8 encoded and null‑terminated.
     * @return Pointer to the message string, or an empty string if no message is available.
     * @note The caller must NOT free the returned pointer.
     */
    const char* API_Get_Status(void);

    /**
     * @brief Injects a custom log message into the internal status queue.
     * @param status The message to add (UTF‑8, null‑terminated).
     */
    void     API_Post_Status(const char* status);

    /* ============================================================================
       HELPER FUNCTIONS – implemented in C, NOT exported from DLL
       These mirror the Pascal implementations in z_api_hubtool_import.pas
       ============================================================================ */

       /* ----- Atomic write helpers (return 1 on success, 0 on failure) ----- */
    int API_WriteInt8(TDataHnd Hnd, int8_t  Value);
    int API_WriteUInt8(TDataHnd Hnd, uint8_t Value);
    int API_WriteInt16(TDataHnd Hnd, int16_t Value);
    int API_WriteUInt16(TDataHnd Hnd, uint16_t Value);
    int API_WriteInt32(TDataHnd Hnd, int32_t Value);
    int API_WriteUInt32(TDataHnd Hnd, uint32_t Value);
    int API_WriteInt64(TDataHnd Hnd, int64_t Value);
    int API_WriteUInt64(TDataHnd Hnd, uint64_t Value);
    int API_WriteSingle(TDataHnd Hnd, float   Value);
    int API_WriteDouble(TDataHnd Hnd, double  Value);

    /**
     * @brief Writes a UTF‑8 string followed by a null terminator (#0).
     *        Matches Pascal's API_WriteString exactly.
     * @param Hnd   Data handle.
     * @param Value Null‑terminated UTF‑8 string (may be empty).
     * @return 1 if full string + null was written, 0 otherwise.
     */
    int API_WriteString(TDataHnd Hnd, const char* Value);

    /* ----- Atomic read helpers (return 1 on success, 0 on failure) ----- */
    int API_ReadInt8(TDataHnd Hnd, int8_t* pValue);
    int API_ReadUInt8(TDataHnd Hnd, uint8_t* pValue);
    int API_ReadInt16(TDataHnd Hnd, int16_t* pValue);
    int API_ReadUInt16(TDataHnd Hnd, uint16_t* pValue);
    int API_ReadInt32(TDataHnd Hnd, int32_t* pValue);
    int API_ReadUInt32(TDataHnd Hnd, uint32_t* pValue);
    int API_ReadInt64(TDataHnd Hnd, int64_t* pValue);
    int API_ReadUInt64(TDataHnd Hnd, uint64_t* pValue);
    int API_ReadSingle(TDataHnd Hnd, float* pValue);
    int API_ReadDouble(TDataHnd Hnd, double* pValue);

    /**
     * @brief Reads a null‑terminated UTF‑8 string from the current position.
     *        Matches Pascal's API_ReadString exactly.
     *        The position is advanced past the null terminator.
     * @param Hnd     Data handle.
     * @param pBuf    Output buffer (must be at least bufSize bytes).
     * @param bufSize Size of output buffer.
     * @return 1 if null terminator found and string copied, 0 otherwise.
     * @note If buffer is too small, returns 0 and position is NOT advanced.
     *       If successful, position is advanced past the null.
     */
    int API_ReadString(TDataHnd Hnd, char* pBuf, size_t bufSize);

#ifdef __cplusplus
}
#endif