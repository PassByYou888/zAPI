(*
  ********************************************************************************
  * Z.API_HubTool_Export – C ABI export layer for the API Hub framework.
  *
  * This unit exposes a set of plain C‑style (cdecl) functions that can be
  * called from any programming language that supports dynamic library imports
  * (C, C++, C#, Python, Java, Rust, Go, Pascal, etc.). It acts as a binary
  * bridge between external applications and the internal Pascal objects
  * (TAPI_APP, TAPI_Tool, TAPI_Data) defined in the API_HubTool unit.
  *
  * The exported functions manage:
  *   – Opaque handles for API data (TDataHnd) and application instances
  *     (TAppHnd). These handles must be created and freed using the provided
  *     functions – never dereference them directly.
  *   – Registration of local Call and Notify APIs with user‑supplied cdecl
  *     callbacks.
  *   – Preparation and startup of the underlying C4 distributed communication
  *     layer (TCP and IPC).
  *   – Remote API calls and notifications across a network.
  *
  * The unit also manages a simulated main thread that runs the C4 progress
  * loop, making the library self‑contained for applications that do not have
  * their own main loop.
  *
  * Runtime parameters (timeouts, logging, IPC settings) can be adjusted
  * dynamically via the API_SetOption function. They are not automatically
  * persisted to disk; if persistence is needed, applications should read/write
  * their own configuration files.
  *
  * All string parameters (API names, descriptions, addresses) must be UTF‑8
  * encoded and null‑terminated (PAnsiChar). The library internally decodes
  * them to Pascal strings. The internal binary data handles are encoding‑
  * agnostic – they are just byte buffers.
  *
  * Thread safety: all exported functions are thread‑safe. For a given TDataHnd,
  * write operations must be serialised; read operations are safe.
  * Callbacks are executed in background threads – do not perform blocking
  * operations or call API_Call/API_Notify inside a callback (risk of deadlock).
  * Offload heavy work to separate threads.
  *
  * @Example (local app registration and call in C):
  *   #include "API_HubTool.h"
  *   static void __cdecl AddCallback(void* Trigger, void* Input, void* Output) {
  *       int a, b;
  *       API_ReadBuffer(Input, &a, sizeof(a));
  *       API_ReadBuffer(Input, &b, sizeof(b));
  *       int sum = a + b;
  *       API_WriteBuffer(Output, &sum, sizeof(sum));
  *   }
  *   int main() {
  *       TAppHnd app = API_Create_APPHnd("Demo", "Example");
  *       API_Reg_Call(app, "add", "Add two ints", NULL, AddCallback);
  *       TDataHnd data = API_Create_DataHnd("add");
  *       int a=5, b=7;
  *       API_WriteBuffer(data, &a, sizeof(a));
  *       API_WriteBuffer(data, &b, sizeof(b));
  *       TDataHnd result = API_Local_APP_Call(app, data);
  *       API_Free_DataHnd(data);
  *       if (result) { int sum; API_ReadBuffer(result, &sum, sizeof(sum)); }
  *       API_Free_DataHnd(result);
  *       API_Free_APPHnd(app);
  *       API_shutdown();
  *       return 0;
  *   }
  *
  * For remote calls, prepare a service and clients with API_Prepare_Service/
  * API_Prepare_Client, then start with API_Prepare_Done, and use API_Call/
  * API_Notify with application names.
  *
  * Dependencies: Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.Status, Z.UnicodeMixedLib,
  *   Z.Net.C4, API_HubTool, Z.Net.C4.API_Hub, Z.IPC.API, Z.Notify, Z.Expression, etc.
  ******************************************************************************
*)
unit Z.API_HubTool_Export;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\pascal\zNetV2\source\Z.Define.inc}

interface

type
  { * TDataHnd: Opaque handle to an API data buffer.
    * Internally it is a pointer to a TAPI_Data record, but external code
    * must never dereference it. Use the provided API_* functions to read,
    * write, and manage its contents.
    * Created with API_Create_DataHnd, freed with API_Free_DataHnd. }
  TDataHnd = Pointer;

  { * TAppHnd: Opaque handle to an application context (TAPI_APP).
    * Represents a logical application that can host multiple APIs.
    * Created with API_Create_APPHnd, freed with API_Free_APPHnd. }
  TAppHnd = Pointer;

  { * TAPI_Call: Callback prototype for request‑response (Call) APIs.
    * Must be declared with the cdecl calling convention.
    * @param Trigger  User‑supplied pointer passed to the callback unchanged.
    * @param Input    TDataHnd containing the serialised request parameters.
    *                 Read with API_ReadBuffer / API_GetBuffer.
    * @param Output   TDataHnd to hold the result. Write with
    *                 API_WriteBuffer / API_SetSize. }
  TAPI_Call = procedure(Trigger: Pointer; Input: Pointer; Output: TDataHnd); cdecl;

  { * TAPI_Notify: Callback prototype for one‑way notification (Notify) APIs.
    * Must be cdecl.
    * @param Trigger  User‑supplied pointer.
    * @param Input    TDataHnd containing the notification payload.
    *                 Read with API_ReadBuffer / API_GetBuffer.
    *                 No output is produced. }
  TAPI_Notify = procedure(Trigger: Pointer; Input: TDataHnd); cdecl;

  { ---- DataHnd Operations ---- }

  { * API_Create_DataHnd: Creates a new data handle initialised with the
    * given API name. The internal buffer is empty (size = 0).
    * @param APIName  Null‑terminated UTF‑8 string naming the target API.
    *                 This name will be packed for transmission.
    * @return A new TDataHnd (never nil). Must be freed with API_Free_DataHnd.
    * @Example:
    *   TDataHnd d = API_Create_DataHnd("echo");
    *   int value = 123;
    *   API_WriteBuffer(d, &value, sizeof(value));
    *   // ... use d in a call ...
    *   API_Free_DataHnd(d); }
function API_Create_DataHnd(APIName: pansichar): TDataHnd; cdecl;

{ * API_Free_DataHnd: Destroys a data handle and releases all associated
  * memory. After this call, the handle is invalid.
  * @param Hnd  The handle to free (can be nil, does nothing). }
procedure API_Free_DataHnd(Hnd: TDataHnd); cdecl;

{ * API_GetBuffer: Returns a direct pointer to the raw binary data in the
  * handle. The pointer is valid until the handle is freed or the buffer
  * is resized. Do not free this pointer.
  * @param Hnd  The data handle.
  * @return Pointer to internal memory block, or nil if empty.
  * @Note Useful for zero‑copy read‑only access. }
function API_GetBuffer(Hnd: TDataHnd): Pointer; cdecl;

{ * API_WriteBuffer: Appends or overwrites binary data into the handle's
  * buffer at the current position. The position advances by the number of
  * bytes written. The buffer is automatically enlarged if needed.
  * @param Hnd   The data handle.
  * @param Buff  Source data pointer.
  * @param Size  Number of bytes to write.
  * @return Number of bytes written (normally equals Size).
  * @Example:
  *   API_WriteBuffer(d, &myInt, sizeof(myInt));
  *   API_WriteBuffer(d, "Hello", 5); }
function API_WriteBuffer(Hnd: TDataHnd; Buff: Pointer; Size: int64): int64; cdecl;

{ * API_ReadBuffer: Reads binary data from the handle's buffer into the
  * caller's buffer, starting at the current position. The position
  * advances by the number of bytes actually read.
  * @param Hnd   The data handle.
  * @param Buff  Destination buffer.
  * @param Size  Maximum number of bytes to read.
  * @return Number of bytes actually read (may be less than Size if EOF).
  * @Example:
  *   API_SetPos(d, 0);
  *   int val;
  *   if (API_ReadBuffer(d, &val, sizeof(val)) == sizeof(val))  ... }
function API_ReadBuffer(Hnd: TDataHnd; Buff: Pointer; Size: int64): int64; cdecl;

{ * API_GetPos: Returns the current read/write position (zero‑based).
  * @param Hnd  The data handle.
  * @return Current offset in bytes. }
function API_GetPos(Hnd: TDataHnd): int64; cdecl;

{ * API_SetPos: Sets the current read/write position. If the new position
  * is beyond the current size, the buffer is extended with zero bytes.
  * @param Hnd   The data handle.
  * @param Pos_  New position (must be >= 0). }
procedure API_SetPos(Hnd: TDataHnd; Pos_: int64); cdecl;

{ * API_GetSize: Returns the total size (in bytes) of the data stored in
  * the handle.
  * @param Hnd  The data handle.
  * @return Current buffer size. }
function API_GetSize(Hnd: TDataHnd): int64; cdecl;

{ * API_SetSize: Resizes the internal buffer to the specified size.
  * If larger, the added space is uninitialised; if smaller, data beyond
  * the new size is discarded.
  * @param Hnd    The data handle.
  * @param Size_  New desired size in bytes. }
procedure API_SetSize(Hnd: TDataHnd; Size_: int64); cdecl;

{ ---- AppHnd Operations ---- }

{ * API_Create_APPHnd: Creates a new application context with the given
  * name and description. The handle encapsulates a TAPI_APP object that
  * can host a set of APIs. It must be freed with API_Free_APPHnd.
  * @param appName  Unique application identifier (UTF‑8, case‑sensitive).
  * @param Desc     Human‑readable description (UTF‑8, can be empty).
  * @return A new TAppHnd (never nil).
  * @Note The application name is used for remote routing.
  * @Example:
  *   TAppHnd app = API_Create_APPHnd("my_app", "Example application");
  *   // register APIs...
  *   API_Free_APPHnd(app); }
function API_Create_APPHnd(appName, Desc: pansichar): TAppHnd; cdecl;

{ * API_Free_APPHnd: Destroys an application context and frees all
  * registered APIs and associated resources. The handle becomes invalid.
  * @param appHnd  The application handle. }
procedure API_Free_APPHnd(appHnd: TAppHnd); cdecl;

{ * API_Reg_Call: Registers a Call‑mode API within the application.
  * The API name must be unique inside the application. When a call is
  * made (locally or remotely), the provided OnCall callback is invoked.
  * @param appHnd   The application handle.
  * @param APIName  Unique API name (UTF‑8, case‑sensitive).
  * @param Desc     Optional description (UTF‑8).
  * @param Trigger  User data passed to the callback.
  * @param OnCall   cdecl function pointer implementing the API.
  * @return 1 if registration succeeded, 0 if the API name already exists. }
function API_Reg_Call(appHnd: TAppHnd; APIName, Desc: pansichar; Trigger: Pointer; OnCall: TAPI_Call): integer; cdecl;

{ * API_Reg_Notify: Registers a Notify‑mode API.
  * Similar to API_Reg_Call but for one‑way notifications. The callback
  * receives only an input handle and produces no response.
  * @param appHnd    The application handle.
  * @param APIName   Unique API name (UTF‑8).
  * @param Desc      Optional description.
  * @param Trigger   User data passed to callback.
  * @param OnNotify  cdecl function pointer.
  * @return 1 on success, 0 if the name already exists. }
function API_Reg_Notify(appHnd: TAppHnd; APIName, Desc: pansichar; Trigger: Pointer; OnNotify: TAPI_Notify): integer; cdecl;

{ * API_UnReg: Removes a previously registered API from the application.
  * This function also triggers a network update broadcast. After calling
  * API_UnReg, the change is propagated to all connected C4 services and
  * clients within approximately 3 seconds (depending on network latency
  * and the C4 update interval). Once propagated, the API will no longer
  * be discoverable or callable by remote peers.
  * @param appHnd   The application handle.
  * @param APIName  The name of the API to unregister (UTF‑8).
  * @return 1 on success, 0 if the API name does not exist.
  * @Note The application's internal API registry is updated immediately,
  *       but the network broadcast is asynchronous. Subsequent remote
  *       calls may still be delivered for a short window (up to ~3 seconds)
  *       until all peers have received the update.
  * @SeeAlso API_Reg_Call, API_Reg_Notify }
function API_UnReg(appHnd: TAppHnd; APIName: pansichar): integer; cdecl;

{ * API_Local_APP_Call: Executes a Call‑mode API locally within the
  * application, bypassing the network. This is a synchronous call that
  * returns a new data handle containing the result. The caller must free
  * both the input and result handles.
  * @param appHnd  The application handle.
  * @param Param   Input data handle (created with API_Create_DataHnd,
  *                containing the API name and parameters).
  * @return A new TDataHnd with the result (size 0 if the API was not
  *         found or an error occurred). Must be freed.
  * @Note The input handle is not freed by this function; call
  *       API_Free_DataHnd on it separately.
  * @Example:
  *   TDataHnd d = API_Create_DataHnd("echo");
  *   API_WriteBuffer(d, "hello", 5);
  *   TDataHnd res = API_Local_APP_Call(app, d);
  *   API_Free_DataHnd(d);
  *   // process res...
  *   API_Free_DataHnd(res); }
function API_Local_APP_Call(appHnd: TAppHnd; Param: TDataHnd): TDataHnd; cdecl;

{ * API_Local_APP_Notify: Sends a notification locally within the
  * application. This is synchronous but does not wait for any result.
  * @param appHnd  The application handle.
  * @param Param   Input data handle (created with API_Create_DataHnd).
  * @Note The input handle is not freed by this function; the caller must
  *       free it separately. }
procedure API_Local_APP_Notify(appHnd: TAppHnd; Param: TDataHnd); cdecl;

{ ---- Advanced Communication Service ---- }

{ * API_Prepare_Service: Prepares a C4 service (listener) that will be
  * started when API_Prepare_Done is called. Multiple services can be
  * prepared.
  * This function can be called at any time (even before or after
  * API_Prepare_Done) – if the main thread is already running, the service
  * is created immediately; otherwise it is queued.
  * @param ListeningAddr_  Address to bind the listening socket (UTF‑8).
  *        Supported formats:
  *          - IPv4: "0.0.0.0" or "127.0.0.1:9898"
  *          - IPv6: "[::1]:8080" or "::1|8080"
  *          - Domain: "myhost.com:9090"
  *          - IPC: "ipc:my_service" (port ignored)
  *        If no port is given, default 9898 is used.
  * @param PhysicsAddr_    Public address advertised to clients (same
  *        format). Clients will connect to this address.
  * @return A tag (integer ID) that can be used to identify this service.
  *         Returns -1 if a service with the same listening address/port
  *         has already been prepared (duplicate detection).
  * @Note Services and clients can be prepared in any order; clients will
  *       wait for services to appear.
  * @Note This function is not intended to be called concurrently on the same
  *       address/port from multiple threads. While it will detect duplicates,
  *       calling it concurrently may lead to inconsistent state or error
  *       returns. It is safe to call from different threads as long as they
  *       do not race on the same address.
  * @Example:
  *   API_Reset_Prepare();
  *   API_Prepare_Service("0.0.0.0", "127.0.0.1:9898");   // TCP
  *   API_Prepare_Service("ipc:test", "ipc:test");        // IPC
  *   API_Prepare_Client("127.0.0.1:9898", app);
  *   API_Prepare_Done(); }
function API_Prepare_Service(ListeningAddr_, PhysicsAddr_: pansichar): integer; cdecl;

{ * API_Prepare_Client: Prepares a C4 client (connector) that will connect
  * to a service when API_Prepare_Done is called. If an application handle
  * is provided, the client will automatically register that application's
  * APIs with the service upon connection.
  * Like API_Prepare_Service, this function can be called before or after
  * the main thread is started; if the main thread is already running,
  * the connection attempt is initiated immediately.
  * @param PhysicsAddr_  Address of the remote service to connect to
  *                      (same format as for API_Prepare_Service).
  * @param appHnd        Optional TAppHnd. If non‑nil, the client exposes
  *                      this application; if nil, it acts as a consumer.
  * @return A tag for this client. Returns -1 if a client with the same
  *         address has already been prepared (duplicate detection).
  * @Note The client automatically reconnects if the connection is lost.
  *       Upon reconnection, the application (if provided) is re‑registered.
  * @Note Concurrent preparation of clients with the same address from
  *       different threads is not supported; it may lead to duplicate
  *       detection errors or undefined behaviour.
  * @Example:
  *   API_Prepare_Client("127.0.0.1:9898", nil);   // consume only
  *   API_Prepare_Client("ipc:test", app);        // provide APIs via app }
function API_Prepare_Client(PhysicsAddr_: pansichar; appHnd: TAppHnd): integer; cdecl;

{ * API_Reset_Prepare: Clears all previously prepared services and clients.
  * Call this before preparing a new set to avoid conflicts.
  * @Note This function does not affect already running services/clients;
  *       it only clears the preparation queue. }
procedure API_Reset_Prepare(); cdecl;

{ * API_Prepare_Done: Starts the C4 framework with all prepared services
  * and clients. This function blocks until the framework is initialised.
  * It also launches a simulated main thread that runs the C4 progress loop.
  * @return 1 if successful, 0 on failure.
  * @Note After this call, remote APIs can be invoked with API_Call/Notify.
  *       The main thread continues until API_Exit_MainThread is called.
  *       Do not call this again without resetting or shutting down.
  *       Check logs via API_Get_Status on failure. }
function API_Prepare_Done: integer; cdecl;

{ * API_Exit_MainThread: Signals the simulated main thread to exit
  * gracefully. After this call, the network loop stops, but resources
  * are not automatically freed. You should still call API_shutdown. }
procedure API_Exit_MainThread; cdecl;

{ * API_Call: Performs a remote (or local) call to the specified application.
  * This function blocks until the response is received or the timeout expires.
  * @param appName   Target application name (UTF‑8, case‑sensitive).
  * @param Param     Input data handle (API name + parameters). The function
  *                  reads the buffer content synchronously and serialises it
  *                  for transmission; it does not take ownership of the handle.
  *                  The caller remains responsible for freeing it with
  *                  API_Free_DataHnd after this call returns.
  * @param Timeout_  Maximum wait in milliseconds. 0 means infinite.
  * @return A new TDataHnd containing the result. If the call times out or
  *         fails, the handle has size 0 (but is still valid). Must be freed
  *         with API_Free_DataHnd.
  * @Note The function first tries to find a local instance of the target
  *       application to avoid network round‑trip. }
function API_Call(appName: pansichar; Param: TDataHnd; Timeout_: uint64): TDataHnd; cdecl;

{ * API_Notify: Sends a one‑way notification to the specified application.
  * Returns immediately after the notification has been sent (it does not
  * wait for any response). The input data is read synchronously and serialised
  * before return; the caller can safely free the handle afterwards.
  * @param appName  Target application name (UTF‑8).
  * @param Param    Input data handle (API name + payload). The caller must
  *                 free it with API_Free_DataHnd after this call.
  * @Example:
  *   TDataHnd d = API_Create_DataHnd("event");
  *   API_WriteBuffer(d, "hello", 5);
  *   API_Notify("my_app", d);
  *   API_Free_DataHnd(d); }
procedure API_Notify(appName: pansichar; Param: TDataHnd); cdecl;

{ * API_Check_MainThread: Checks whether the simulated main thread (which runs
  * the C4 progress loop) is currently active.
  * @return 1 if the simulated main thread is running, 0 otherwise.
  * @Note This function can be used to determine whether remote communication
  *       is available (API_Prepare_Done has been called and the loop is running).
  *       After API_Exit_MainThread is called, this returns 0. }
function API_Check_MainThread(): integer; cdecl;

{ * API_Check_App: Checks whether an application with the given name is
  * currently registered on the network (either locally or on any remote client
  * that has been discovered).
  * @param appName  Application name to look for (UTF‑8, case‑sensitive).
  * @return 1 if at least one instance of the application is available,
  *         0 otherwise.
  * @Note This function performs a quick lookup but does not guarantee that
  *       the application is still online at the moment of a subsequent call.
  *       It is useful for probing availability before making a call. }
function API_Check_App(appName: pansichar): integer; cdecl;

{ * API_SetOption: Dynamically adjusts global runtime options of the API Hub
  * framework. All changes take effect immediately for subsequent operations
  * (except where noted). This function is intended for runtime tuning
  * without restarting the application.
  * @param Option  Configuration key (UTF‑8, case‑insensitive). Supported keys:
  *                - "password" / "passwd"   : C4 P2PVM authentication token.
  *                - "Quiet"                : Enable/disable quiet mode (True/False).
  *                - "External_Conf_Auto_Save" / "Conf_Auto_Save" : (no effect,
  *                  kept for compatibility)
  *                - "Wait_Connection_ReadyOk" : Whether API_Prepare_Done blocks
  *                  until all clients are ready (True/False).
  *                - "Wait_Connection_Timeout" : Timeout in milliseconds for
  *                  the above wait.
  *                - "ShowThreadID" / "ShowThread" : Show thread IDs in logs.
  *                - "ConsoleOutput" / "Console_Output" : Enable console logging.
  *                - "IPC_Serv_ThreadCount" : IPC server thread pool size.
  *                - "IPC_Serv_MaxQueueLength" : IPC message queue length.
  *                - "IPC_Serv_MaxMsgSize" : Maximum IPC message size in bytes.
  * @param Value   New value (UTF‑8). Boolean values accept "True"/"False",
  *                "1"/"0", "Yes"/"No".
  * @Note Unknown options are silently ignored. This is by design to avoid
  *       breaking external programs that may pass unsupported keys.
  *       Changes to password and wait‑control options are critical for
  *       secure and flexible deployment. }
procedure API_SetOption(Option, Value: pansichar); cdecl;

{ * API_Get_Status_Num: Returns the number of pending log messages in the
  * internal status buffer.
  * @return The number of messages currently queued.
  * @Note This function is thread‑safe and can be called concurrently with
  *       API_Get_Status. }
function API_Get_Status_Num(): integer; cdecl;

{ * API_Get_Status: Retrieves the next log message from the internal status
  * buffer (FIFO order). The returned pointer points to a static 64‑KB internal
  * buffer. The data is valid only until the next call to this function (or any
  * other function that might modify the buffer). To keep the message, the
  * caller must copy it immediately.
  * Messages longer than 65,534 bytes are silently truncated.
  * @return PAnsiChar pointing to a null‑terminated UTF‑8 string, or an empty
  *         string if no message is available.
  * @Note The returned pointer must not be freed by the caller.
  * @SeeAlso API_Get_Status_Num }
function API_Get_Status(): pansichar; cdecl;

{ * API_Post_Status: Injects a user‑supplied log message into the internal
  * status buffer, as if it were generated by the library itself. This is
  * useful for merging external logging with the API Hub's own status stream.
  * @param status  Null‑terminated UTF‑8 string containing the message to add.
  * @Note The message is appended to the buffer and will be retrievable via
  *       API_Get_Status in FIFO order. The function does not modify the
  *       original string. }
procedure API_Post_Status(status: pansichar); cdecl;

{ * API_shutdown: Gracefully shuts down the entire API Hub framework,
  * including all services, clients, and the simulated main thread.
  * After this call, the library state is reset and you can re‑initialise
  * by calling the preparation functions again. }
procedure API_shutdown; cdecl;

implementation

uses
  SysUtils,
  Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.status, Z.UnicodeMixedLib,
  Z.Parsing, Z.MemoryStream, Z.ListEngine, Z.TextDataEngine,
  Z.Net, Z.Net.C4, Z.Net.C4_Console_APP, Z.API_HubTool, Z.Net.C4.API_Hub,
  Z.IPC.API, Z.Net.Server.IPC, Z.Int128, Z.Notify, Z.Expression;

{ ---- UTF‑8 string decoding helper ---- }

{ * DS: Decodes a null‑terminated UTF‑8 string (PAnsiChar) into a TAPI_String.
  * This is used throughout the unit to convert external UTF‑8 inputs to
  * internal Unicode strings. }
function DS(P: Pointer): TAPI_String;
begin
  Result.ReadUTF8AnsiChar(P);
end;

{ ---- DataHnd Implementation ---- }

{ * API_Create_DataHnd: Creates a new data handle with the given API name.
  * Reads the UTF‑8 name, creates a TAPI_Data record with a TMemory_Param_Tool,
  * and returns the handle. }
function API_Create_DataHnd(APIName: pansichar): TDataHnd;
var
  s: TAPI_String;
begin
  s := DS(APIName);
  Result := TAPI_Data.New_Param(s);
end;

{ * API_Free_DataHnd: Frees the TAPI_Data record pointed to by Hnd. }
procedure API_Free_DataHnd(Hnd: TDataHnd);
begin
  TAPI_Data.Free_Data(Hnd);
end;

{ * API_GetBuffer: Returns the raw data pointer from the TAPI_Data record. }
function API_GetBuffer(Hnd: TDataHnd): Pointer;
begin
  Result := PAPI_Data(Hnd)^.GetBuffer;
end;

{ * API_WriteBuffer: Delegates to TAPI_Data.WriteBuff. }
function API_WriteBuffer(Hnd: TDataHnd; Buff: Pointer; Size: int64): int64;
begin
  Result := PAPI_Data(Hnd)^.WriteBuff(Buff, Size);
end;

{ * API_ReadBuffer: Delegates to TAPI_Data.ReadBuff. }
function API_ReadBuffer(Hnd: TDataHnd; Buff: Pointer; Size: int64): int64;
begin
  Result := PAPI_Data(Hnd)^.ReadBuff(Buff, Size);
end;

{ * API_GetPos: Delegates to TAPI_Data.Get_Pos. }
function API_GetPos(Hnd: TDataHnd): int64;
begin
  Result := PAPI_Data(Hnd)^.Get_Pos;
end;

{ * API_SetPos: Delegates to TAPI_Data.Set_Pos. }
procedure API_SetPos(Hnd: TDataHnd; Pos_: int64);
begin
  PAPI_Data(Hnd)^.Set_Pos(Pos_);
end;

{ * API_GetSize: Delegates to TAPI_Data.Get_Size. }
function API_GetSize(Hnd: TDataHnd): int64;
begin
  Result := PAPI_Data(Hnd)^.Get_Size;
end;

{ * API_SetSize: Delegates to TAPI_Data.Set_Size. }
procedure API_SetSize(Hnd: TDataHnd; Size_: int64);
begin
  PAPI_Data(Hnd)^.Set_Size(Size_);
end;

{ ---- AppHnd Implementation ---- }

{ * API_Create_APPHnd: Creates a TAPI_APP object, sets its name and
  * description from UTF‑8 strings, and returns the handle. }
function API_Create_APPHnd(appName, Desc: pansichar): TAppHnd;
var
  app: TAPI_APP;
begin
  app := TAPI_APP.Create;
  app.Name := DS(appName);
  app.Desc := DS(Desc);
  if app.Desc = '' then
      app.Desc := 'No Description';
  Result := app;
end;

{ * API_Free_APPHnd: Frees the TAPI_APP object.
  * Also iterates over all C4 clients and clears any reference to this app
  * to avoid dangling pointers. }
procedure API_Free_APPHnd(appHnd: TAppHnd);
var
  app: TAPI_APP;
  arry: TC40_Custom_Client_Array;
  i: integer;
  Cli: TC40_API_HUB_Client;
begin
  app := appHnd;
  arry := C40_ClientPool.SearchClass(TC40_API_HUB_Client);
  for i := 0 to length(arry) - 1 do
    begin
      Cli := arry[i] as TC40_API_HUB_Client;
      if Cli.app = app then
          Cli.app := nil;
    end;
  DisposeObject(app);
end;

{ * API_Reg_Call: Registers a Call API by decoding UTF‑8 names and calling
  * app.API.Reg_Call. Returns 1 on success, 0 on failure. }
function API_Reg_Call(appHnd: TAppHnd; APIName, Desc: pansichar; Trigger: Pointer; OnCall: TAPI_Call): integer;
var
  app: TAPI_APP;
  APIName__, Desc__: TAPI_String;
begin
  app := appHnd;
  APIName__ := DS(APIName);
  Desc__ := DS(Desc);
  Result := if_(app.API.Reg_Call(APIName__, Desc__, Trigger, OnCall), 1, 0);
end;

{ * API_Reg_Notify: Registers a Notify API similarly. }
function API_Reg_Notify(appHnd: TAppHnd; APIName, Desc: pansichar; Trigger: Pointer; OnNotify: TAPI_Notify): integer;
var
  app: TAPI_APP;
  APIName__, Desc__: TAPI_String;
begin
  app := appHnd;
  APIName__ := DS(APIName);
  Desc__ := DS(Desc);
  Result := if_(app.API.Reg_Notify(APIName__, Desc__, Trigger, OnNotify), 1, 0);
end;

{ * API_UnReg: Unregisters an API by name. Immediately removes the API from
  * the local registry and triggers a network broadcast to all peers.
  * The broadcast is asynchronous; propagation typically completes within
  * about 3 seconds. }
function API_UnReg(appHnd: TAppHnd; APIName: pansichar): integer;
var
  app: TAPI_APP;
  APIName__: TAPI_String;
begin
  app := appHnd;
  APIName__ := DS(APIName);
  Result := if_(app.API.UnReg(APIName__), 1, 0);
end;

{ * API_Local_APP_Call: Executes a Call locally.
  * 1) Creates a temporary TMem64 and packs the input handle.
  * 2) Invokes app.API.Execute_Call (which runs the callback synchronously).
  * 3) Wraps the result in a new TDataHnd and returns it.
  * The temporary TMem64 is freed after use. }
function API_Local_APP_Call(appHnd: TAppHnd; Param: TDataHnd): TDataHnd;
var
  app: TAPI_APP;
  tmp: TMem64;
begin
  app := appHnd;
  tmp := TMem64.Create;
  PAPI_Data(Param).Data_Param.EncryptToMem(tmp);
  Result := TAPI_Data.New_Result_From(app.API.Execute_Call(tmp));
  DisposeObject(tmp);
end;

{ * API_Local_APP_Notify: Sends a notification locally.
  * Packs the input handle and calls app.API.Execute_Notify. }
procedure API_Local_APP_Notify(appHnd: TAppHnd; Param: TDataHnd);
var
  app: TAPI_APP;
  tmp: TMem64;
begin
  app := appHnd;
  tmp := TMem64.Create;
  PAPI_Data(Param).Data_Param.EncryptToMem(tmp);
  app.API.Execute_Notify(tmp);
  DisposeObject(tmp);
end;

{ ---- Advanced Communication Service Implementation ---- }

{ * Internal record that binds a tag (ID) to an application handle and
  * address information for a service or client. This is used to match
  * prepared clients with their applications when they connect. }
type
  TAppHnd_Bind_Tag = record
    appHnd: TAppHnd;
    Tag: integer;
    IsService, IsClient: boolean;
    Listen, Addr, Port: TAPI_String;
    procedure Init;
  end;

  TAppHnd_Bind_Tag_List = class(TBigList<TAppHnd_Bind_Tag>)
  public
    procedure DoFree(var Data: TAppHnd_Bind_Tag); override;
    function CompareData(const Data_1, Data_2: TAppHnd_Bind_Tag): boolean; override;
  end;

procedure TAppHnd_Bind_Tag.Init;
begin
  appHnd := nil;
  Tag := 0;
  IsService := False;
  IsClient := False;
  Listen := '';
  Addr := '';
  Port := '';
end;

procedure TAppHnd_Bind_Tag_List.DoFree(var Data: TAppHnd_Bind_Tag);
begin
  Data.Init();
  inherited DoFree(Data);
end;

function TAppHnd_Bind_Tag_List.CompareData(const Data_1, Data_2: TAppHnd_Bind_Tag): boolean;
begin
  Result :=
    (Data_1.appHnd = Data_2.appHnd) and (Data_1.Tag = Data_2.Tag) and (Data_1.IsService = Data_2.IsService) and (Data_1.IsClient = Data_2.IsClient) and Data_1.Listen.Same(@Data_2.Listen) and Data_1.Addr.Same(@Data_2.Addr);
end;

var
  Prepare_Commands: TPascalStringList = nil;
  Tag_Seed: integer = 0;
  AppHnd_Bind_Tag_List: TAppHnd_Bind_Tag_List = nil;

  { * API_Reset_Prepare: Clears prepared commands and tag mappings. }
procedure API_Reset_Prepare();
begin
  Prepare_Commands.Clear;
  AppHnd_Bind_Tag_List.Clear;
end;

{ * Temporary event bridge for C4 PhysicsService.
  * It logs service start/stop and link success events. }
type
  TTemp_C40_PhysicsService_Bridge__ = class(TCore_InterfacedObject_Intermediate, IC40_PhysicsService_Event)
  public
    procedure C40_PhysicsService_Build_Network(Sender: TC40_PhysicsService; Custom_Service_: TC40_Custom_Service);
    procedure C40_PhysicsService_Start(Sender: TC40_PhysicsService);
    procedure C40_PhysicsService_Stop(Sender: TC40_PhysicsService);
    procedure C40_PhysicsService_LinkSuccess(Sender: TC40_PhysicsService; Custom_Service_: TC40_Custom_Service; Trigger_: TCore_Object);
    procedure C40_PhysicsService_UserOut(Sender: TC40_PhysicsService; Custom_Service_: TC40_Custom_Service; Trigger_: TCore_Object);
  end;

procedure TTemp_C40_PhysicsService_Bridge__.C40_PhysicsService_Build_Network(Sender: TC40_PhysicsService; Custom_Service_: TC40_Custom_Service);
begin
  { Nothing to do – the network is already built. }
end;

procedure TTemp_C40_PhysicsService_Bridge__.C40_PhysicsService_Start(Sender: TC40_PhysicsService);
begin
  if Sender.IPC_Mode then
      DoStatus('API-Hub Service Listening: "%s" OK, Host: "%s"', [Sender.ListeningAddr.Text, Sender.PhysicsAddr.Text])
  else
      DoStatus('API-Hub Service Listening: "%s" OK, Host: "%s"', [Build_Host_URL(Sender.ListeningAddr, Sender.PhysicsPort), Build_Host_URL(Sender.PhysicsAddr, Sender.PhysicsPort)]);
end;

procedure TTemp_C40_PhysicsService_Bridge__.C40_PhysicsService_Stop(Sender: TC40_PhysicsService);
begin
  DoStatus('API-Hub Service Listening: "%s" Stop', [Build_Host_URL(Sender.ListeningAddr, Sender.PhysicsPort)]);
end;

procedure TTemp_C40_PhysicsService_Bridge__.C40_PhysicsService_LinkSuccess(Sender: TC40_PhysicsService; Custom_Service_: TC40_Custom_Service; Trigger_: TCore_Object);
var
  serv: TC40_API_HUB_Service;
  user_io: TC40_API_HUB_Service_RecvTunnel_NoAuth;
begin
  serv := Custom_Service_ as TC40_API_HUB_Service;
  user_io := Trigger_ as TC40_API_HUB_Service_RecvTunnel_NoAuth;
  DoStatus('API-Hub Service Link Successed IO "%s"', [user_io.Owner.GetPeerIP]);
end;

procedure TTemp_C40_PhysicsService_Bridge__.C40_PhysicsService_UserOut(Sender: TC40_PhysicsService; Custom_Service_: TC40_Custom_Service; Trigger_: TCore_Object);
var
  serv: TC40_API_HUB_Service;
  user_io: TC40_API_HUB_Service_RecvTunnel_NoAuth;
begin
  serv := Custom_Service_ as TC40_API_HUB_Service;
  user_io := Trigger_ as TC40_API_HUB_Service_RecvTunnel_NoAuth;
  DoStatus('API-Hub Service User-out IO "%s"', [user_io.Owner.GetPeerIP]);
end;

{ * Temporary event bridge for C4 PhysicsTunnel.
  * When a dependent client is built, it matches the client's tag to an
  * application handle and sets the client's APP property, triggering
  * registration of the app's APIs. }
type
  TTemp_C40_PhysicsTunnel_Bridge__ = class(TCore_InterfacedObject_Intermediate, IC40_PhysicsTunnel_Event)
  public
    constructor Create;
    procedure C40_PhysicsTunnel_Connected(Sender: TC40_PhysicsTunnel);
    procedure C40_PhysicsTunnel_Disconnect(Sender: TC40_PhysicsTunnel);
    procedure C40_PhysicsTunnel_Build_Network(Sender: TC40_PhysicsTunnel; Custom_Client_: TC40_Custom_Client);
    procedure C40_PhysicsTunnel_Client_Connected(Sender: TC40_PhysicsTunnel; Custom_Client_: TC40_Custom_Client);
  end;

constructor TTemp_C40_PhysicsTunnel_Bridge__.Create;
begin
  inherited Create;
end;

procedure TTemp_C40_PhysicsTunnel_Bridge__.C40_PhysicsTunnel_Connected(Sender: TC40_PhysicsTunnel);
begin
  DoStatus('Connection %s Successed', [Build_Host_URL(Sender.PhysicsAddr, Sender.PhysicsPort)]);
end;

procedure TTemp_C40_PhysicsTunnel_Bridge__.C40_PhysicsTunnel_Disconnect(Sender: TC40_PhysicsTunnel);
begin
  DoStatus('%s Disconnected', [Build_Host_URL(Sender.PhysicsAddr, Sender.PhysicsPort)]);
end;

procedure TTemp_C40_PhysicsTunnel_Bridge__.C40_PhysicsTunnel_Build_Network(Sender: TC40_PhysicsTunnel; Custom_Client_: TC40_Custom_Client);
begin
  if Sender.IPC_Mode then
      DoStatus('Ready Network: "%s"', [Sender.PhysicsAddr.Text])
  else
      DoStatus('Ready Network: "%s"', [Build_Host_URL(Sender.PhysicsAddr, Sender.PhysicsPort)]);
end;

procedure TTemp_C40_PhysicsTunnel_Bridge__.C40_PhysicsTunnel_Client_Connected(Sender: TC40_PhysicsTunnel; Custom_Client_: TC40_Custom_Client);
var
  Cli: TC40_API_HUB_Client;
  tmp: TAPI_String;
begin
  if AppHnd_Bind_Tag_List.Num > 0 then
    with AppHnd_Bind_Tag_List.Repeat_ do
      repeat
        if Custom_Client_.Tag = Queue^.Data.Tag then
          begin
            Cli := (Custom_Client_ as TC40_API_HUB_Client);
            Cli.app := Queue^.Data.appHnd;
            if Cli.app <> nil then
              begin
                if Cli.C40PhysicsTunnel.IPC_Mode then
                    DoStatus('APP %s "%s" Ready OK, Connection "%s"', [Cli.app.Name.Text, Cli.app.Desc.Text, Cli.C40PhysicsTunnel.PhysicsAddr.Text])
                else
                    DoStatus('APP %s "%s" Ready OK, Connection "%s"', [Cli.app.Name.Text, Cli.app.Desc.Text, Build_Host_URL(Cli.C40PhysicsTunnel.PhysicsAddr, Cli.C40PhysicsTunnel.PhysicsPort)]);

                if Cli.app.API.API_Pool.Num > 0 then
                  with Cli.app.API.API_Pool.Repeat_ do
                    repeat
                      if Assigned(Queue^.Data.Data.Second.On_Call) then
                          tmp := 'call'
                      else if Assigned(Queue^.Data.Data.Second.On_Notify) then
                          tmp := 'notify'
                      else
                          tmp := 'error';
                      DoStatus('  (%s) (%s) "%s"', [tmp.Text, Queue^.Data.Data.Primary, Queue^.Data.Data.Second.Desc.Text]);
                    until not Next;
              end;
          end;
      until not Next;
end;

var
  Init_Running, Init_Successed, Simulated_Main_Thread_Running: boolean;
  Temp_C40_PhysicsTunnel_Bridge__: TTemp_C40_PhysicsTunnel_Bridge__;
  Temp_C40_PhysicsService_Bridge__: TTemp_C40_PhysicsService_Bridge__;
  Wait_Connection_ReadyOk: boolean;
  Wait_Connection_Timeout: TTimeTick;

procedure Do_Post_RUn_C40_Extract_CmdLine;
begin
  C40_Extract_CmdLine();
end;

{ * API_Prepare_Service: Builds a C4 'Service' command string and stores
  * the tag and addresses. It decodes UTF‑8 addresses, handles IPC detection,
  * and defaults port to 9898. The command is added to Prepare_Commands.
  * If the main thread is already running (Init_Successed = True), the service
  * is started immediately by injecting the command into the C4 parser. }
function API_Prepare_Service(ListeningAddr_, PhysicsAddr_: pansichar): integer;
var
  Listen, Host, Port: U_String;
  Cmd_: U_String;
  running: boolean;
begin
  Listen := DS(ListeningAddr_).Text;
  Host := DS(PhysicsAddr_).Text;
  if Is_IPC_Addr(Host.Text) or Is_IPC_Addr(Listen.Text) then
      Port := '0'
  else
    begin
      Port := '9898';
      ExtractHostAddress(Host, Port);
      ExtractHostAddress(Listen, Port);
    end;
  // Duplicate detection – check if a service with this address already exists
  // either in the running system or in the preparation queue.
  if Init_Successed and Simulated_Main_Thread_Running then
    begin
      if Z.Net.C4.C40_PhysicsServicePool.ExistsListenAddr(Listen, EStrToInt(Port)) then
        begin
          DoStatus('error: repeat listen addr:%s port:%s', [Listen.Text, Port.Text]);
          Result := -1;
          Exit;
        end;
    end;

  if AppHnd_Bind_Tag_List.Num > 0 then
    begin
      with AppHnd_Bind_Tag_List.Repeat_ do
        repeat
          if Listen.Same(Queue^.Data.Listen.Text) and Port.Same(Queue^.Data.Port.Text) and (Queue^.Data.IsService) then
            begin
              DoStatus('prepare error: repeat listen addr:%s port:%s', [Listen.Text, Port.Text]);
              Result := -1;
              Exit;
            end;
        until not Next;
    end;

  Cmd_ := PFormat('Service("%s","%s",%s,"APIHub@Tag=%d")', [Listen.Text, Host.Text, Port.Text, Tag_Seed]);
  Result := Tag_Seed;
  Prepare_Commands.Add(Cmd_);
  with AppHnd_Bind_Tag_List.Add_Null^ do
    begin
      Data.Init();
      Data.appHnd := nil;
      Data.Tag := Tag_Seed;
      Data.IsService := True;
      Data.Listen := Listen;
      Data.Addr := Build_Host_URL(Host, Port);
      Data.Port := Port;
    end;
  AtomInc(Tag_Seed);

  // If the main thread is already running, execute the command immediately.
  if Init_Successed and Simulated_Main_Thread_Running then
    begin
      SetLength(C40AppParam, 1);
      C40AppParam[0] := Cmd_;
      C40AppParsingTextStyle := TTextStyle.tsC;
      DoStatus('Run %s', [Cmd_.Text]);
      if TCompute.CurrentThread = Z.Core.Main_Thread then
        begin
          Do_Post_RUn_C40_Extract_CmdLine();
        end
      else
        begin
          Z.Core.MainThreadProgress.PostC1(Do_Post_RUn_C40_Extract_CmdLine, @running, nil);
          while running do
              TCompute.Sleep(10);
        end;
      SetLength(C40AppParam, 0);
    end
  else
    begin
      DoStatus('API_Prepare_Service: %s', [Cmd_.Text]);
    end;
end;

{ * API_Prepare_Client: Similar to API_Prepare_Service but for clients.
  * Builds a 'KeepAlive' command and optionally binds an app handle.
  * If the main thread is already running, the client connection is initiated
  * immediately. }
function API_Prepare_Client(PhysicsAddr_: pansichar; appHnd: TAppHnd): integer;
var
  Host, Port: U_String;
  Cmd_: TAPI_String;
  full_url: TAPI_String;
  running: boolean;
begin
  Host := DS(PhysicsAddr_).Text;
  if Is_IPC_Addr(Host.Text) then
      Port := '0'
  else
    begin
      Port := '9898';
      ExtractHostAddress(Host, Port);
    end;

  if Init_Successed and Simulated_Main_Thread_Running then
    begin
      if Z.Net.C4.C40_PhysicsTunnelPool.ExistsPhysicsAddr(Host, EStrToInt(Port)) then
        begin
          DoStatus('error: repeat connection addr:%s port:%s', [Host.Text, Port.Text]);
          Result := -1;
          Exit;
        end;
    end;

  if AppHnd_Bind_Tag_List.Num > 0 then
    begin
      full_url := Build_Host_URL(Host, Port);
      with AppHnd_Bind_Tag_List.Repeat_ do
        repeat
          if full_url.Same(Queue^.Data.Addr) and (Queue^.Data.IsClient) then
            begin
              DoStatus('prepare error: repeat connection addr:%s port:%s', [Host.Text, Port.Text]);
              Result := -1;
              Exit;
            end;
        until not Next;
    end;

  Cmd_ := PFormat('KeepAlive("%s",%s,"APIHub@Tag=%d")', [Host.Text, Port.Text, Tag_Seed]);
  Result := Tag_Seed;
  Prepare_Commands.Add(Cmd_);
  with AppHnd_Bind_Tag_List.Add_Null^ do
    begin
      Data.Init();
      Data.appHnd := appHnd;
      Data.Tag := Tag_Seed;
      Data.IsClient := True;
      Data.Listen := '';
      Data.Addr := Build_Host_URL(Host, Port);
      Data.Port := Port;
    end;
  AtomInc(Tag_Seed);

  if Init_Successed and Simulated_Main_Thread_Running then
    begin
      SetLength(C40AppParam, 1);
      C40AppParam[0] := Cmd_;
      C40AppParsingTextStyle := TTextStyle.tsC;
      DoStatus('Run %s', [Cmd_.Text]);
      if TCompute.CurrentThread = Z.Core.Main_Thread then
        begin
          Do_Post_RUn_C40_Extract_CmdLine();
        end
      else
        begin
          Z.Core.MainThreadProgress.PostC1(Do_Post_RUn_C40_Extract_CmdLine, @running, nil);
          while running do
              TCompute.Sleep(10);
        end;
      SetLength(C40AppParam, 0);
    end
  else
    begin
      DoStatus('API_Prepare_Client: %s', [Cmd_.Text]);
    end;
end;

{ * Entry point for the simulated main thread.
  * 1) Copies all prepared commands into the global C40AppParam array.
  * 2) Sets up event bridges and parses the commands via C40_Extract_CmdLine.
  * 3) If Wait_Connection_ReadyOk is True, polls until all prepared clients
  *    are connected and registered (or timeout).
  * 4) Runs the C4 progress loop until Simulated_Main_Thread_Running becomes False.
  * 5) Cleans up C4 resources on exit. }
procedure Simulated_Main_Thread();
var
  i: integer;
  tk: TTimeTick;
  Cli: TC40_API_HUB_Client;
  Prepare_Cli_Num, Online_Num: integer;
begin
  DoStatus('API-Hub Main Thread Begin');

  SetLength(C40AppParam, Prepare_Commands.Count);
  for i := 0 to Prepare_Commands.Count - 1 do
      C40AppParam[i] := Prepare_Commands[i];

  if Prepare_Commands.Count > 0 then
    begin
      C40AppParsingTextStyle := TTextStyle.tsC;
      On_C40_PhysicsTunnel_Event_Console := Temp_C40_PhysicsTunnel_Bridge__;

      Init_Successed := C40_Extract_CmdLine();

      if Init_Successed and Wait_Connection_ReadyOk then
        begin
          Prepare_Cli_Num := 0;
          if AppHnd_Bind_Tag_List.Num > 0 then
            with AppHnd_Bind_Tag_List.Repeat_ do
              repeat
                if Queue^.Data.IsClient then
                    Inc(Prepare_Cli_Num);
              until not Next;

          if Prepare_Cli_Num > 0 then
            begin
              tk := GetTimeTick + Wait_Connection_Timeout;
              repeat
                C40Progress(10);
                Online_Num := 0;
                if AppHnd_Bind_Tag_List.Num > 0 then
                  begin
                    with AppHnd_Bind_Tag_List.Repeat_ do
                      repeat
                        if Queue^.Data.IsClient then
                          begin
                            Cli := C40_ClientPool.FindTag(Queue^.Data.Tag) as TC40_API_HUB_Client;
                            if (Cli <> nil) and (Cli.Connected) and ((Cli.app = nil) or Cli.API_APP_Is_Online) then
                                Inc(Online_Num);
                          end;
                      until not Next;
                  end;
                Init_Successed := Online_Num >= Prepare_Cli_Num;
              until Init_Successed or ((Wait_Connection_Timeout > 0) and (GetTimeTick() > tk));
            end;
        end;
    end
  else
    begin
      Init_Successed := True;
    end;

  Init_Running := False;

  if Init_Successed then
    while Simulated_Main_Thread_Running do
        C40Progress(if_(Running_API_Num.V > 0, 0, 10));

  try
      C40Clean();
  except
  end;
  DoStatus('API-Hub Main Thread Exit');
end;

{ * API_Prepare_Done: Starts the simulated main thread and waits for
  * initialisation to complete. Returns 1 on success, 0 on failure. }
function API_Prepare_Done: integer;
begin
  if Simulated_Main_Thread_Running then
      Exit;

  Open_Core_Dispatch_Thread();
  Init_Running := True;
  Init_Successed := False;
  Simulated_Main_Thread_Running := True;

  Begin_Simulator_Main_Thread(Simulated_Main_Thread);
  while Init_Running do
      Boot_Thread_Sync_Tool.Check_Synchronize(10);
  Result := if_(Init_Successed, 1, 0);
end;

{ * API_Exit_MainThread: Signals the main loop to stop and waits for the
  * simulator thread to finish. }
procedure API_Exit_MainThread;
begin
  Simulated_Main_Thread_Running := False;
  while Simulator_Main_Thread_Activted do
      Boot_Thread_Sync_Tool.Check_Synchronize(10);
end;

var
  Find_Class_Critical: TCritical = nil;

  { * API_Call: Performs a call. It finds a connected API Hub client, packs
    * the input parameter into a TMem64, and calls Wait_Execute_Call on the
    * client with the given timeout. Returns a new data handle with the result,
    * or an empty handle on failure. }
function API_Call(appName: pansichar; Param: TDataHnd; Timeout_: uint64): TDataHnd;
var
  Cli: TC40_API_HUB_Client;
  tmp, Output: TMem64;
begin
  try
    Find_Class_Critical.Lock;
    try
        Cli := Z.Net.C4.C40_ClientPool.FindClass(TC40_API_HUB_Client) as TC40_API_HUB_Client;
    finally
        Find_Class_Critical.unLock;
    end;
  except
      Cli := nil;
  end;

  Output := nil;
  if Cli <> nil then
    begin
      tmp := TMem64.Create;
      PAPI_Data(Param).Data_Param.EncryptToMem(tmp);
      try
          Output := Cli.Wait_Execute_Call(DS(appName), tmp, Timeout_);
      except
          DoStatus('API_Call(%s, ...) except', [DS(appName).Text]);
      end;
      DisposeObject(tmp);
    end
  else
    begin
      DoStatus('"%s" no connection', [DS(appName).Text]);
    end;
  if Output = nil then
      Output := TMem64.Create;
  Result := TAPI_Data.New_Result_From(Output);
end;

{ * API_Notify: Sends a notification. Finds a connected client, packs the
  * input, and calls Send_Execute_Notify. Returns immediately. }
procedure API_Notify(appName: pansichar; Param: TDataHnd);
var
  Cli: TC40_API_HUB_Client;
  tmp: TMem64;
begin
  try
    Find_Class_Critical.Lock;
    try
        Cli := Z.Net.C4.C40_ClientPool.FindClass(TC40_API_HUB_Client) as TC40_API_HUB_Client;
    finally
        Find_Class_Critical.unLock;
    end;
  except
      Exit;
  end;

  if Cli = nil then
      Exit;
  tmp := TMem64.Create;
  PAPI_Data(Param).Data_Param.EncryptToMem(tmp);
  try
      Cli.Send_Execute_Notify(DS(appName), tmp);
  except
      DoStatus('API_Notify(%s, ...) except', [DS(appName).Text]);
  end;
  DisposeObject(tmp);
end;

{ * API_Check_MainThread: Returns 1 if the simulated main thread is active. }
function API_Check_MainThread(): integer;
begin
  Result := if_(Simulator_Main_Thread_Activted, 1, 0);
end;

{ * API_Check_App: Checks if the given application name is available. }
function API_Check_App(appName: pansichar): integer;
begin
  Result := if_((Find_Local_APP_Hub(DS(appName), False) <> nil) or (Find_Remote_APP_Hub(DS(appName), False) <> nil), 1, 0);
end;

var
  External_Conf_FileName: TAPI_String;
  External_Conf_Auto_Save: boolean = True;

  { * API_SetOption: Implementation. See interface comment for details. }
procedure API_SetOption(Option, Value: pansichar);
var
  opt, V, tmp: TAPI_String;
  L: integer;
  i: integer;
begin
  opt := DS(Option);
  V := DS(Value);

  if opt.Same('password', 'passwd') then
    begin
      Z.Net.C4.C40_Password := V;
      for i := 0 to tmp.L - 1 do
          tmp.Append(if_(TMT19937.Rand32 mod 2 = 0, '*', '**'));
      DoStatus('Update Password = %s', [tmp.Text]);
    end
  else if opt.Same('Quiet') then
    begin
      C40SetQuietMode(EStrToBool(V.Text));
      DoStatus('Quiet = %s', [umlBoolToStr(EStrToBool(V.Text)).Text]);
    end
  else if opt.Same('External_Conf_Auto_Save', 'Conf_Auto_Save') then
    begin
      External_Conf_Auto_Save := EStrToBool(V.Text);
      DoStatus('External Config Auto Save(.api-tool.ini) = %s', [umlBoolToStr(External_Conf_Auto_Save).Text]);
    end
  else if opt.Same('Wait_Connection_ReadyOk', 'Wait_API_Prepare_Done', 'API_Prepare_Done_Wait', 'WaitConnect', 'Wait_Ready', 'WaitReady') then
    begin
      Wait_Connection_ReadyOk := EStrToBool(V.Text);
      DoStatus('Wait Connection ReadyOk = %s', [umlBoolToStr(Wait_Connection_ReadyOk).Text]);
    end
  else if opt.Same('Wait_Connection_Timeout', 'Wait_TimeOut', 'API_Prepare_Done_TimeOut', 'WaitTimeOut') then
    begin
      Wait_Connection_Timeout := EStrToUInt64(V.Text);
      DoStatus('Wait Connection TimeOut = %s', [umlTimeTickToStr(Wait_Connection_Timeout).Text]);
    end
  else if opt.Same('ShowThreadID', 'ShowThread', 'Show_Thread') then
    begin
      Z.status.StatusThreadID := EStrToBool(V.Text);
      DoStatus('Status Thread ID = %s', [umlBoolToStr(Z.status.StatusThreadID).Text]);
    end
  else if opt.Same('ConsoleOutput', 'Console_Output') then
    begin
      Z.status.ConsoleOutput := EStrToBool(V.Text);
      DoStatus('Console Output = %s', [umlBoolToStr(Z.status.ConsoleOutput).Text]);
    end
  else if opt.Same('IPC_Serv_ThreadCount', 'IPC_ThreadCount', 'IPC_Server_ThreadCount') then
    begin
      TZNet_Server_IPC.IPC_Serv_ThreadCount := EStrToInt(V.Text);
      DoStatus('Interprocess Communication Server Thread Count = %s', [umlIntToStr(TZNet_Server_IPC.IPC_Serv_ThreadCount).Text]);
    end
  else if opt.Same('IPC_Serv_MaxQueueLength', 'IPC_MaxQueueLength', 'IPC_Server_MaxQueueLength') then
    begin
      TZNet_Server_IPC.IPC_Serv_MaxQueueLength := EStrToInt(V.Text);
      DoStatus('Interprocess Communication Server Max Queue Length = %s', [umlIntToStr(TZNet_Server_IPC.IPC_Serv_MaxQueueLength).Text]);
    end
  else if opt.Same('IPC_Serv_MaxMsgSize', 'IPC_MaxMsgSize', 'IPC_Server_MaxMsgSize') then
    begin
      TZNet_Server_IPC.IPC_Serv_MaxMsgSize := EStrToInt(V.Text);
      DoStatus('Interprocess Communication Server Max Msg Size = %s', [umlIntToStr(TZNet_Server_IPC.IPC_Serv_MaxMsgSize).Text]);
    end;
end;

{ ---- Status Buffer Implementation ---- }

type
  TStatus_Buffer = class(TOrderStruct<TBytes>)
  public
    procedure DoFree(var Data: TBytes); override;
  end;

var
  Status_Pool: TStatus_Buffer = nil;
  Status_Critical__: TCritical = nil;
  Status_Buff: array [0 .. $FFFF] of byte;

procedure TStatus_Buffer.DoFree(var Data: TBytes);
begin
  SetLength(Data, 0);
  inherited DoFree(Data);
end;

{ * backcall_DoStatus: Hook called by the global DoStatus system.
  * It locks the status pool, discards old messages if the queue exceeds 1000,
  * and pushes the new message as UTF‑8 bytes. }
procedure backcall_DoStatus(Text_: SystemString; const ID: integer);
begin
  Status_Critical__.Lock;
  try
    while Status_Pool.Num > 1000 do
        Status_Pool.Next;
    Status_Pool.Push(TPascalString(Text_).UTF8);
  finally
      Status_Critical__.unLock;
  end;
end;

{ * API_Get_Status_Num: Returns the number of queued messages.
  * Thread‑safe via Status_Critical__ lock. }
function API_Get_Status_Num(): integer;
begin
  Status_Critical__.Lock;
  try
      Result := Status_Pool.Num;
  finally
      Status_Critical__.unLock;
  end;
end;

{ * API_Get_Status: Retrieves the oldest message from the queue.
  * The message is copied into a static 64‑KB buffer (Status_Buff) and null‑terminated.
  * If the message is longer than 64KB-1, it is truncated.
  * The pointer is valid until the next call to API_Get_Status.
  * After copying, the message is removed from the queue. }
function API_Get_Status(): pansichar;
var
  L: integer;
begin
  Result := @Status_Buff;
  Status_Critical__.Lock;
  Status_Buff[0] := 0;
  Status_Buff[1] := 0;
  try
    if Status_Pool.Num > 0 then
      begin
        L := length(Status_Pool.First^.Data);
        if L > 0 then
          begin
            CopyPtr(@Status_Pool.First^.Data[0], @Status_Buff, Min(L, SizeOf(Status_Buff) - 1));
            Status_Buff[Min(L, SizeOf(Status_Buff) - 1)] := 0;
          end;
        Status_Pool.Next;
      end;
  finally
      Status_Critical__.unLock;
  end;
end;

{ * API_Post_Status: Converts the input UTF‑8 string to a Pascal string and
  * injects it into the status system via DoStatus. }
procedure API_Post_Status(status: pansichar);
begin
  Status_Critical__.Lock;
  try
      Post_To_DoStatus_Queue(TCompute.CurrentThread, TPascalString.ReadUTF8AnsiCharTo(status), 0);
  finally
      Status_Critical__.unLock;
  end;
end;

{ * API_shutdown: Stops the main thread, unloads the IPC library, and closes
  * the core dispatch thread. }
procedure API_shutdown;
begin
  API_Exit_MainThread();
  UnloadIPCLibrary();
  Close_Core_Dispatch_Thread();
end;

initialization

Prepare_Commands := TPascalStringList.Create;
Tag_Seed := 1;
AppHnd_Bind_Tag_List := TAppHnd_Bind_Tag_List.Create;
Init_Running := True;
Init_Successed := False;
Simulated_Main_Thread_Running := False;
Temp_C40_PhysicsTunnel_Bridge__ := TTemp_C40_PhysicsTunnel_Bridge__.Create;
On_C40_PhysicsTunnel_Event_Console := Temp_C40_PhysicsTunnel_Bridge__;
Temp_C40_PhysicsService_Bridge__ := TTemp_C40_PhysicsService_Bridge__.Create;
On_C40_PhysicsService_Event_Console := Temp_C40_PhysicsService_Bridge__;
Wait_Connection_ReadyOk := True;
Wait_Connection_Timeout := 30 * 1000;
if IsLibrary then
  begin
    Z.status.StatusThreadID := False;
    Z.status.ConsoleOutput := True;
    Z.Net.C4.C40SetQuietMode(True);
  end;
C40_EnablePerServiceDirectory := False;

Find_Class_Critical := TCritical.Create('Find_Class_Critical');

Status_Pool := TStatus_Buffer.Create;
Status_Critical__ := TCritical.Create('Status_Critical__');
AddDoStatusHookC(Status_Pool, backcall_DoStatus);

finalization

API_Exit_MainThread();
On_C40_PhysicsTunnel_Event_Console := nil;
On_C40_PhysicsService_Event_Console := nil;
DisposeObjectAndNil(Prepare_Commands);
DisposeObjectAndNil(AppHnd_Bind_Tag_List);
DisposeObjectAndNil(Temp_C40_PhysicsTunnel_Bridge__);
DisposeObjectAndNil(Temp_C40_PhysicsService_Bridge__);
DisposeObjectAndNil(Find_Class_Critical);
RemoveDoStatusHook(Status_Pool);
DisposeObjectAndNil(Status_Pool);
DisposeObjectAndNil(Status_Critical__);

end.
