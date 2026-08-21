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
  * their own main loop. A configuration file (<executable>.api-tool.ini) is
  * automatically created on first run to allow runtime tuning of timeouts,
  * logging, and C4 options without recompilation.
  *
  * All string parameters (API names, descriptions, addresses) must be UTF‑8
  * encoded and null‑terminated (PAnsiChar). The library internally decodes
  * them to Pascal strings. The internal binary data handles are encoding‑
  * agnostic – they are just byte buffers.
  *
  * Thread safety: all exported functions are thread‑safe except for
  * API_Get_Status (not implemented in this unit). For a given TDataHnd,
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
function API_Create_DataHnd(APIName: PAnsiChar): TDataHnd; cdecl;

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
function API_WriteBuffer(Hnd: TDataHnd; Buff: Pointer; Size: Int64): Int64; cdecl;

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
function API_ReadBuffer(Hnd: TDataHnd; Buff: Pointer; Size: Int64): Int64; cdecl;

{ * API_GetPos: Returns the current read/write position (zero‑based).
  * @param Hnd  The data handle.
  * @return Current offset in bytes. }
function API_GetPos(Hnd: TDataHnd): Int64; cdecl;

{ * API_SetPos: Sets the current read/write position. If the new position
  * is beyond the current size, the buffer is extended with zero bytes.
  * @param Hnd   The data handle.
  * @param Pos_  New position (must be >= 0). }
procedure API_SetPos(Hnd: TDataHnd; Pos_: Int64); cdecl;

{ * API_GetSize: Returns the total size (in bytes) of the data stored in
  * the handle.
  * @param Hnd  The data handle.
  * @return Current buffer size. }
function API_GetSize(Hnd: TDataHnd): Int64; cdecl;

{ * API_SetSize: Resizes the internal buffer to the specified size.
  * If larger, the added space is uninitialised; if smaller, data beyond
  * the new size is discarded.
  * @param Hnd    The data handle.
  * @param Size_  New desired size in bytes. }
procedure API_SetSize(Hnd: TDataHnd; Size_: Int64); cdecl;

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
function API_Create_APPHnd(appName, Desc: PAnsiChar): TAppHnd; cdecl;

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
function API_Reg_Call(appHnd: TAppHnd; APIName, Desc: PAnsiChar; Trigger: Pointer; OnCall: TAPI_Call): Integer; cdecl;

{ * API_Reg_Notify: Registers a Notify‑mode API.
  * Similar to API_Reg_Call but for one‑way notifications. The callback
  * receives only an input handle and produces no response.
  * @param appHnd    The application handle.
  * @param APIName   Unique API name (UTF‑8).
  * @param Desc      Optional description.
  * @param Trigger   User data passed to callback.
  * @param OnNotify  cdecl function pointer.
  * @return 1 on success, 0 if the name already exists. }
function API_Reg_Notify(appHnd: TAppHnd; APIName, Desc: PAnsiChar; Trigger: Pointer; OnNotify: TAPI_Notify): Integer; cdecl;

{ * --------------------------------------------------------------------------
  * API_UnReg: Removes a previously registered API from the application.
  * This function also triggers a network update broadcast. After calling
  * API_UnReg, the change is propagated to all connected C4 services and
  * clients within approximately 3 seconds (depending on network latency
  * and the C4 update interval). Once propagated, the API will no longer
  * be discoverable or callable by remote peers.
  *
  * @param appHnd   The application handle.
  * @param APIName  The name of the API to unregister (UTF‑8).
  * @return 1 on success, 0 if the API name does not exist.
  *
  * @Note The application's internal API registry is updated immediately,
  *       but the network broadcast is asynchronous. Subsequent remote
  *       calls may still be delivered for a short window (up to ~3 seconds)
  *       until all peers have received the update.
  * @SeeAlso API_Reg_Call, API_Reg_Notify
  * -------------------------------------------------------------------------- }
function API_UnReg(appHnd: TAppHnd; APIName: PAnsiChar): Integer; cdecl;

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
  * @Note Services and clients can be prepared in any order; clients will
  *       wait for services to appear.
  * @Example:
  *   API_Reset_Prepare();
  *   API_Prepare_Service("0.0.0.0", "127.0.0.1:9898");   // TCP
  *   API_Prepare_Service("ipc:test", "ipc:test");        // IPC
  *   API_Prepare_Client("127.0.0.1:9898", app);
  *   API_Prepare_Done(); }
function API_Prepare_Service(ListeningAddr_, PhysicsAddr_: PAnsiChar): Integer; cdecl;

{ * API_Prepare_Client: Prepares a C4 client (connector) that will connect
  * to a service when API_Prepare_Done is called. If an application handle
  * is provided, the client will automatically register that application's
  * APIs with the service upon connection.
  * @param PhysicsAddr_  Address of the remote service to connect to
  *                      (same format as for API_Prepare_Service).
  * @param appHnd        Optional TAppHnd. If non‑nil, the client exposes
  *                      this application; if nil, it acts as a consumer.
  * @return A tag for this client.
  * @Note The client automatically reconnects if the connection is lost.
  *       Upon reconnection, the application (if provided) is re‑registered.
  * @Example:
  *   API_Prepare_Client("127.0.0.1:9898", nil);   // consume only
  *   API_Prepare_Client("ipc:test", app);        // provide APIs via app }
function API_Prepare_Client(PhysicsAddr_: PAnsiChar; appHnd: TAppHnd): Integer; cdecl;

{ * API_Reset_Prepare: Clears all previously prepared services and clients.
  * Call this before preparing a new set to avoid conflicts. }
procedure API_Reset_Prepare(); cdecl;

{ * API_Prepare_Done: Starts the C4 framework with all prepared services
  * and clients. This function blocks until the framework is initialised.
  * It also launches a simulated main thread that runs the C4 progress loop.
  * @return 1 if successful, 0 on failure.
  * @Note After this call, remote APIs can be invoked with API_Call/Notify.
  *       The main thread continues until API_Exit_MainThread is called.
  *       Do not call this again without resetting or shutting down.
  *       Check logs via API_Get_Status (not implemented here) on failure. }
function API_Prepare_Done: Integer; cdecl;

{ * API_Exit_MainThread: Signals the simulated main thread to exit
  * gracefully. After this call, the network loop stops, but resources
  * are not automatically freed. You should still call API_shutdown. }
procedure API_Exit_MainThread; cdecl;

{ * API_Call: Performs a remote (or local) call to the specified
  * application. This function blocks until the response is received or
  * the timeout expires.
  * @param appName   Target application name (UTF‑8, case‑sensitive).
  * @param Param     Input data handle (API name + parameters). The handle
  *                  is cloned internally; the caller must still free it.
  * @param Timeout_  Maximum wait in milliseconds. 0 means infinite.
  * @return A new TDataHnd containing the result. If the call times out or
  *         fails, the handle has size 0 (but is still valid). Must free.
  * @Note The function first tries to find a local instance of the target
  *       application to avoid network round‑trip. }
function API_Call(appName: PAnsiChar; Param: TDataHnd; Timeout_: UInt64): TDataHnd; cdecl;

{ * API_Notify: Sends a one‑way notification to the specified application.
  * Returns immediately without waiting for any response.
  * @param appName  Target application name (UTF‑8).
  * @param Param    Input data handle (API name + payload).
  *                 The caller must free it after this call.
  * @Example:
  *   TDataHnd d = API_Create_DataHnd("event");
  *   API_WriteBuffer(d, "hello", 5);
  *   API_Notify("my_app", d);
  *   API_Free_DataHnd(d); }
procedure API_Notify(appName: PAnsiChar; Param: TDataHnd); cdecl;

{ * --------------------------------------------------------------------------
  * API_SetOption: Dynamically adjusts global runtime options of the API Hub
  * framework. All changes take effect immediately for subsequent operations
  * (except where noted). This function is intended for runtime tuning
  * without restarting the application or modifying the .ini file.
  *
  * @param Option  Configuration key (UTF‑8, case‑insensitive). The following
  *                keys are supported (aliases are accepted):
  *                - "password" / "passwd"   : Sets the C4 P2PVM authentication
  *                  token. This password is used for all new P2PVM connections
  *                  (existing connections are unaffected). It is crucial for
  *                  secure inter‑communication between zAPI components.
  *                  **IMPORTANT**: This must match on both service and client
  *                  sides for successful handshake.
  *
  *                - "Quiet"                : Enable/disable quiet mode (True/False).
  *                  Suppresses most debug logs.
  *
  *                - "External_Conf_Auto_Save" / "Conf_Auto_Save" : Enable/disable
  *                  automatic saving of the current configuration to the .ini file
  *                  on program exit (True/False). Default is True.
  *
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
  *
  *                - "Wait_Connection_Timeout" / "Wait_TimeOut" / ... : Sets the
  *                  maximum waiting time (in milliseconds) when
  *                  Wait_Connection_ReadyOk is True. Default is 30000.
  *
  *                - "ShowThreadID" / "ShowThread" / "Show_Thread" : Toggle
  *                  display of thread IDs in log messages (True/False).
  *
  *                - "ConsoleOutput" / "Console_Output" : Toggle console
  *                  (stdout/stderr) logging (True/False).
  *
  *                - "IPC_Serv_ThreadCount" / "IPC_ThreadCount" / "IPC_Server_ThreadCount":
  *                  Number of threads in the IPC service thread pool.
  *
  *                - "IPC_Serv_MaxQueueLength" / "IPC_MaxQueueLength" / "IPC_Server_MaxQueueLength":
  *                  Maximum length of the IPC message queue.
  *
  *                - "IPC_Serv_MaxMsgSize" / "IPC_MaxMsgSize" / "IPC_Server_MaxMsgSize":
  *                  Maximum size (in bytes) of a single IPC message.
  *
  * @param Value   New value (UTF‑8). For boolean options, accepted values are
  *                "True"/"False", "1"/"0", "Yes"/"No".
  *
  * @Note This function has no return value; unknown options are silently ignored.
  *       Changes to the password and wait‑control options are critical for
  *       secure and flexible deployment. See the comments in the implementation
  *       for detailed internal behaviour.
  * -------------------------------------------------------------------------- }
procedure API_SetOption(Option, Value: PAnsiChar); cdecl;

{ * API_shutdown: Gracefully shuts down the entire API Hub framework,
  * including all services, clients, and the simulated main thread.
  * After this call, the library state is reset and you can re‑initialise
  * by calling the preparation functions again. }
procedure API_shutdown; cdecl;

implementation

uses
  SysUtils,
  Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.Status, Z.UnicodeMixedLib,
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
function API_Create_DataHnd(APIName: PAnsiChar): TDataHnd;
var
  s: TAPI_String;
begin
  s := DS(APIName); // Decode UTF‑8 name.
  Result := TAPI_Data.New_Param(s); // Create and initialise a parameter record.
end;

{ * API_Free_DataHnd: Frees the TAPI_Data record pointed to by Hnd. }
procedure API_Free_DataHnd(Hnd: TDataHnd);
begin
  TAPI_Data.Free_Data(Hnd); // Static method releases all owned objects.
end;

{ * API_GetBuffer: Returns the raw data pointer from the TAPI_Data record. }
function API_GetBuffer(Hnd: TDataHnd): Pointer;
begin
  Result := PAPI_Data(Hnd)^.GetBuffer; // Calls record method.
end;

{ * API_WriteBuffer: Delegates to TAPI_Data.WriteBuff. }
function API_WriteBuffer(Hnd: TDataHnd; Buff: Pointer; Size: Int64): Int64;
begin
  Result := PAPI_Data(Hnd)^.WriteBuff(Buff, Size);
end;

{ * API_ReadBuffer: Delegates to TAPI_Data.ReadBuff. }
function API_ReadBuffer(Hnd: TDataHnd; Buff: Pointer; Size: Int64): Int64;
begin
  Result := PAPI_Data(Hnd)^.ReadBuff(Buff, Size);
end;

{ * API_GetPos: Delegates to TAPI_Data.Get_Pos. }
function API_GetPos(Hnd: TDataHnd): Int64;
begin
  Result := PAPI_Data(Hnd)^.Get_Pos;
end;

{ * API_SetPos: Delegates to TAPI_Data.Set_Pos. }
procedure API_SetPos(Hnd: TDataHnd; Pos_: Int64);
begin
  PAPI_Data(Hnd)^.Set_Pos(Pos_);
end;

{ * API_GetSize: Delegates to TAPI_Data.Get_Size. }
function API_GetSize(Hnd: TDataHnd): Int64;
begin
  Result := PAPI_Data(Hnd)^.Get_Size;
end;

{ * API_SetSize: Delegates to TAPI_Data.Set_Size. }
procedure API_SetSize(Hnd: TDataHnd; Size_: Int64);
begin
  PAPI_Data(Hnd)^.Set_Size(Size_);
end;

{ ---- AppHnd Implementation ---- }

{ * API_Create_APPHnd: Creates a TAPI_APP object, sets its name and
  * description from UTF‑8 strings, and returns the handle. }
function API_Create_APPHnd(appName, Desc: PAnsiChar): TAppHnd;
var
  app: TAPI_APP;
begin
  app := TAPI_APP.Create; // Create the application object.
  app.Name := DS(appName); // Set name from UTF‑8.
  app.Desc := DS(Desc); // Set description.
  if app.Desc = '' then
      app.Desc := 'No Description'; // Provide a default if empty.
  Result := app; // Return as opaque handle.
end;

{ * API_Free_APPHnd: Frees the TAPI_APP object. }
procedure API_Free_APPHnd(appHnd: TAppHnd);
var
  app: TAPI_APP;
  arry: TC40_Custom_Client_Array; // Array of all C4 clients.
  i: Integer;
  Cli: TC40_API_HUB_Client;
begin
  app := appHnd;
  // search all c4-client
  arry := C40_ClientPool.SearchClass(TC40_API_HUB_Client);

  for i := 0 to length(arry) - 1 do
    begin
      Cli := arry[i] as TC40_API_HUB_Client;
      if Cli.app = app then
          Cli.app := nil;
    end;

  DisposeObject(app); // Safely destroy the object.
end;

{ * API_Reg_Call: Registers a Call API by decoding UTF‑8 names and calling
  * app.API.Reg_Call. Returns 1 on success, 0 on failure. }
function API_Reg_Call(appHnd: TAppHnd; APIName, Desc: PAnsiChar; Trigger: Pointer; OnCall: TAPI_Call): Integer;
var
  app: TAPI_APP;
  APIName__, Desc__: TAPI_String;
begin
  app := appHnd; // Get the application object.
  APIName__ := DS(APIName); // Decode API name.
  Desc__ := DS(Desc); // Decode description.
  Result := if_(app.API.Reg_Call(APIName__, Desc__, Trigger, OnCall), 1, 0);
end;

{ * API_Reg_Notify: Registers a Notify API similarly. }
function API_Reg_Notify(appHnd: TAppHnd; APIName, Desc: PAnsiChar; Trigger: Pointer; OnNotify: TAPI_Notify): Integer;
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
function API_UnReg(appHnd: TAppHnd; APIName: PAnsiChar): Integer;
var
  app: TAPI_APP;
  APIName__: TAPI_String;
begin
  app := appHnd;
  APIName__ := DS(APIName);
  Result := if_(app.API.UnReg(APIName__), 1, 0);
end;

{ * API_Local_APP_Call: Executes a Call locally. It packs the input handle
  * into a TMem64, calls app.API.Execute_Call, and returns the result as a
  * new TDataHnd. The temporary TMem64 is freed after use. }
function API_Local_APP_Call(appHnd: TAppHnd; Param: TDataHnd): TDataHnd;
var
  app: TAPI_APP;
  tmp: TMem64;
begin
  app := appHnd;
  tmp := TMem64.Create; // Temporary buffer for packing.
  PAPI_Data(Param).Data_Param.EncryptToMem(tmp); // Pack API name and payload.
  Result := TAPI_Data.New_Result_From(app.API.Execute_Call(tmp)); // Execute and wrap result.
  DisposeObject(tmp); // Free temporary.
end;

{ * API_Local_APP_Notify: Sends a notification locally. It packs the input
  * and calls app.API.Execute_Notify. }
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
    appHnd: TAppHnd; // Application handle to bind.
    Tag: Integer; // Unique tag returned by Prepare functions.
    IsService, IsClient: Boolean; // Role flags.
    Listen, Addr: TAPI_String; // Listening and advertised addresses.
    procedure Init; // Initialises all fields to default values.
  end;

  { * List of TAppHnd_Bind_Tag records with automatic memory management.
    * Used to store all prepared services and clients until startup. }
  TAppHnd_Bind_Tag_List = class(TBigList<TAppHnd_Bind_Tag>)
  public
    procedure DoFree(var Data: TAppHnd_Bind_Tag); override;
    function CompareData(const Data_1, Data_2: TAppHnd_Bind_Tag): Boolean; override;
  end;

  { * TAppHnd_Bind_Tag.Init: Sets all fields to default empty values. }
procedure TAppHnd_Bind_Tag.Init;
begin
  appHnd := nil;
  Tag := 0;
  IsService := False;
  IsClient := False;
  Listen := '';
  Addr := '';
end;

{ * TAppHnd_Bind_Tag_List.DoFree: Called when a record is removed, resets it. }
procedure TAppHnd_Bind_Tag_List.DoFree(var Data: TAppHnd_Bind_Tag);
begin
  Data.Init();
  inherited DoFree(Data);
end;

{ * TAppHnd_Bind_Tag_List.CompareData: Compares two records for equality. }
function TAppHnd_Bind_Tag_List.CompareData(const Data_1, Data_2: TAppHnd_Bind_Tag): Boolean;
begin
  Result :=
    (Data_1.appHnd = Data_2.appHnd)
    and (Data_1.Tag = Data_2.Tag)
    and (Data_1.IsService = Data_2.IsService)
    and (Data_1.IsClient = Data_2.IsClient)
    and Data_1.Listen.Same(@Data_2.Listen)
    and Data_1.Addr.Same(@Data_2.Addr)
    ;
end;

var
  Prepare_Commands: TPascalStringList = nil; // List of C4 command strings to execute.
  Tag_Seed: Integer = 0; // Auto‑incrementing tag counter.
  AppHnd_Bind_Tag_List: TAppHnd_Bind_Tag_List = nil; // Tag mapping list.

  { * API_Prepare_Service: Builds a C4 'Service' command string and stores
    * the tag and addresses. It decodes UTF‑8 addresses, handles IPC detection,
    * and defaults port to 9898. The command is added to Prepare_Commands. }
function API_Prepare_Service(ListeningAddr_, PhysicsAddr_: PAnsiChar): Integer;
var
  Listen, Host, Port: U_String;
  Cmd_: U_String;
begin
  Listen := DS(ListeningAddr_).Text; // Decode listening address.
  Host := DS(PhysicsAddr_).Text; // Decode advertised address.
  { For IPC, port is 0; otherwise default to 9898 and parse host:port }
  if Is_IPC_Addr(Host.Text) or Is_IPC_Addr(Listen.Text) then
      Port := '0'
  else
    begin
      Port := '9898'; // Default port.
      ExtractHostAddress(Host, Port); // Extract host and port from string.
      ExtractHostAddress(Listen, Port);
    end;
  { Build the command string with the tag embedded. }
  Cmd_ := PFormat('Service("%s","%s",%s,"APIHub@Tag=%d")', [Listen.Text, Host.Text, Port.Text, Tag_Seed]);
  Result := Tag_Seed; // Return the tag.
  Prepare_Commands.Add(Cmd_); // Append to preparation list.
  with AppHnd_Bind_Tag_List.Add_Null^ do // Store the tag with address info.
    begin
      Data.Init();
      Data.appHnd := nil; // No app for a service.
      Data.Tag := Tag_Seed;
      Data.IsService := True;
      Data.Listen := Listen;
      Data.Addr := Build_Host_URL(Host, Port); // Build full URL.
    end;
  AtomInc(Tag_Seed); // Increment for next item.
  DoStatus('API_Prepare_Service: %s', [Cmd_.Text]); // Log the command.
end;

{ * API_Prepare_Client: Builds a C4 'KeepAlive' command (client) and stores
  * the tag with the provided application handle. If appHnd is nil, the
  * client will not register any application. }
function API_Prepare_Client(PhysicsAddr_: PAnsiChar; appHnd: TAppHnd): Integer;
var
  Host, Port: U_String;
  Cmd_: TAPI_String;
begin
  Host := DS(PhysicsAddr_).Text; // Decode target address.
  if Is_IPC_Addr(Host.Text) then
      Port := '0'
  else
    begin
      Port := '9898';
      ExtractHostAddress(Host, Port);
    end;
  { Build the KeepAlive command with the tag. }
  Cmd_ := PFormat('KeepAlive("%s",%s,"APIHub@Tag=%d")', [Host.Text, Port.Text, Tag_Seed]);
  Result := Tag_Seed;
  Prepare_Commands.Add(Cmd_);
  with AppHnd_Bind_Tag_List.Add_Null^ do
    begin
      Data.Init();
      Data.appHnd := appHnd; // Store the application handle.
      Data.Tag := Tag_Seed;
      Data.IsClient := True;
      Data.Listen := '';
      Data.Addr := Build_Host_URL(Host, Port);
    end;
  AtomInc(Tag_Seed);
  DoStatus('API_Prepare_Client: %s', [Cmd_.Text]);
end;

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

{ * This is the key method: when a client builds its network, we iterate
  * over the tag list and, if the client's tag matches, assign the stored
  * app handle to the client. This causes the app to be registered. }
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
            Cli.app := Queue^.Data.appHnd; // Assign the app to the client.
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
  Init_Running, Init_Successed, Simulated_Main_Thread_Running: Boolean;
  Temp_C40_PhysicsTunnel_Bridge__: TTemp_C40_PhysicsTunnel_Bridge__;
  Temp_C40_PhysicsService_Bridge__: TTemp_C40_PhysicsService_Bridge__;
  Wait_Connection_ReadyOk: Boolean;
  Wait_Connection_Timeout: TTimeTick;

  { * Entry point for the simulated main thread. It transfers the prepared
    * commands to the C4 global array, sets up event bridges, starts the C4
    * framework, and then runs the progress loop until stopped. }
procedure Simulated_Main_Thread();
var
  i: Integer;
  tk: TTimeTick;
  Cli: TC40_API_HUB_Client;
  Prepare_Cli_Num, Online_Num: Integer;
begin
  DoStatus('API-Hub Main Thread Begin');

  { Copy prepared commands into the global C4AppParam array. }
  SetLength(C40AppParam, Prepare_Commands.Count);
  for i := 0 to Prepare_Commands.Count - 1 do
      C40AppParam[i] := Prepare_Commands[i];

  C40AppParsingTextStyle := TTextStyle.tsC; // Use C‑style command parsing.
  On_C40_PhysicsTunnel_Event_Console := Temp_C40_PhysicsTunnel_Bridge__;

  Init_Successed := C40_Extract_CmdLine(); // Parse and start the C4 framework.

  if Init_Successed and Wait_Connection_ReadyOk then
    begin
      { Count how many clients were prepared. }
      Prepare_Cli_Num := 0;
      if AppHnd_Bind_Tag_List.Num > 0 then
        with AppHnd_Bind_Tag_List.Repeat_ do
          repeat
            if Queue^.Data.IsClient then
                Inc(Prepare_Cli_Num);
          until Not Next;

      if Prepare_Cli_Num > 0 then
        begin
          tk := GetTimeTick + Wait_Connection_Timeout;
          repeat
            C40Progress(10); // Pump the network.
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
                  until Not Next;
              end;
            Init_Successed := Online_Num >= Prepare_Cli_Num;
          until Init_Successed or ((Wait_Connection_Timeout > 0) and (GetTimeTick() > tk));
        end;
    end;

  Init_Running := False; // Signal that initialisation is done.

  if Init_Successed then
    while Simulated_Main_Thread_Running do
        C40Progress(if_(Running_API_Num.V > 0, 0, 10)); // Main event loop.

  try
      C40Clean(); // Clean up C4 resources.
  except
  end;
  DoStatus('API-Hub Main Thread Exit');
end;

{ * API_Prepare_Done: Starts the simulated main thread and waits for
  * initialisation to complete. Returns 1 on success, 0 on failure. }
function API_Prepare_Done: Integer;
begin
  if Simulated_Main_Thread_Running then
      exit;

  Open_Core_Dispatch_Thread();
  Init_Running := True;
  Init_Successed := False;
  Simulated_Main_Thread_Running := True;

  Begin_Simulator_Main_Thread(Simulated_Main_Thread); // Start the simulated main thread.
  while Init_Running do
      Boot_Thread_Sync_Tool.Check_Synchronize(10); // Pump messages while waiting.
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

{ * API_Call: Performs a call. It finds a connected API Hub client, packs
  * the input parameter into a TMem64, and calls Wait_Execute_Call on the
  * client with the given timeout. Returns a new data handle with the result,
  * or an empty handle on failure. }
function API_Call(appName: PAnsiChar; Param: TDataHnd; Timeout_: UInt64): TDataHnd;
var
  Cli: TC40_API_HUB_Client;
  tmp, Output: TMem64;
begin
  try
      Cli := Z.Net.C4.C40_ClientPool.FindConnectedClass(TC40_API_HUB_Client) as TC40_API_HUB_Client;
  except
      Cli := nil;
  end;

  Output := nil;
  if Cli <> nil then
    begin
      tmp := TMem64.Create; // Temporary buffer.
      PAPI_Data(Param).Data_Param.EncryptToMem(tmp); // Pack input.
      try
          Output := Cli.Wait_Execute_Call(DS(appName), tmp, Timeout_);
      except
        try
          DoStatus('API_Call(%s, ...) except do re-call', [DS(appName).Text]);
          Output := Cli.Wait_Execute_Call(DS(appName), tmp, Timeout_);
        except
          DoStatus('API_Call(%s, ...) except do re-call', [DS(appName).Text]);
          Output := Cli.Wait_Execute_Call(DS(appName), tmp, Timeout_);
        end;
      end;
      DisposeObject(tmp);
    end
  else
    begin
      DoStatus('"%s" no connection', [DS(appName).Text]);
    end;
  if Output = nil then
      Output := TMem64.Create; // Return an empty result on failure.
  Result := TAPI_Data.New_Result_From(Output); // Wrap the result in a TDataHnd.
end;

{ * API_Notify: Sends a notification. Finds a connected client, packs the
  * input, and calls Send_Execute_Notify. Returns immediately. }
procedure API_Notify(appName: PAnsiChar; Param: TDataHnd);
var
  Cli: TC40_API_HUB_Client;
  tmp: TMem64;
begin
  try
      Cli := Z.Net.C4.C40_ClientPool.FindConnectedClass(TC40_API_HUB_Client) as TC40_API_HUB_Client;
  except
      exit;
  end;

  if Cli = nil then
      exit;
  tmp := TMem64.Create;
  PAPI_Data(Param).Data_Param.EncryptToMem(tmp);
  try
      Cli.Send_Execute_Notify(DS(appName), tmp);
  except
    try
      DoStatus('API_Notify(%s, ...) except do re-call', [DS(appName).Text]);
      Cli.Send_Execute_Notify(DS(appName), tmp);
    except
      DoStatus('API_Notify(%s, ...) except do re-call', [DS(appName).Text]);
      Cli.Send_Execute_Notify(DS(appName), tmp);
    end;
  end;
  DisposeObject(tmp);
end;

var
  External_Conf_FileName: TAPI_String;
  External_Conf_Auto_Save: Boolean = True;

  { * --------------------------------------------------------------------------
    * API_SetOption: Implementation. This function updates global runtime
    * parameters. See the interface comment for a full list of supported
    * options. The changes take effect immediately for new operations.
    *
    * Important notes:
    *   - Password update affects only new P2PVM connections; existing tunnels
    *     are not re‑authenticated.
    *   - Wait_Connection_ReadyOk and Wait_Connection_Timeout are read during
    *     API_Prepare_Done. Changing them after API_Prepare_Done has no effect.
    *   - IPC parameters affect newly created IPC servers/clients.
    * -------------------------------------------------------------------------- }
procedure API_SetOption(Option, Value: PAnsiChar);
var
  opt, V, tmp: TAPI_String;
  L: Integer;
  i: Integer;
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
      Z.Status.StatusThreadID := EStrToBool(V.Text);
      DoStatus('Status Thread ID = %s', [umlBoolToStr(Z.Status.StatusThreadID).Text]);
    end
  else if opt.Same('ConsoleOutput', 'Console_Output') then
    begin
      Z.Status.ConsoleOutput := EStrToBool(V.Text);
      DoStatus('Console Output = %s', [umlBoolToStr(Z.Status.ConsoleOutput).Text]);
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

{ * API_shutdown: Stops the main thread, unloads the IPC library, and closes
  * the core dispatch thread. }
procedure API_shutdown;
begin
  API_Exit_MainThread();
  UnloadIPCLibrary();
  Close_Core_Dispatch_Thread();
end;

{ * Init_External_Conf: Creates or loads the external configuration file.
  * Reads settings and applies them to global variables. }
procedure Init_External_Conf;
var
  mName_: TAPI_String;
  External_Conf: TTextDataEngine;
begin
  External_Conf := TTextDataEngine.Create;
  External_Conf.AutoUpdateDefaultValue := False;
  try
    mName_.Text := GetModuleName(0); // Get the executable name.
    External_Conf_FileName := mName_ + '.api-tool.ini';
    External_Conf_Auto_Save := True;

    if umlFileExists(External_Conf_FileName.Text) then
      begin
        External_Conf.LoadFromFile(External_Conf_FileName);
        External_Conf.HStringList['options'].Trim_Value_Space_And_Semicolon_Comment;
      end;

    { Apply settings from the configuration file. }
    Wait_Connection_ReadyOk := External_Conf.GetDefaultText_Bool('options', 'Wait_Connection_ReadyOk', Wait_Connection_ReadyOk);
    Wait_Connection_Timeout := External_Conf.GetDefaultText_I64('options', 'Wait_Connection_Timeout', Wait_Connection_Timeout);
    Z.Status.StatusThreadID := External_Conf.GetDefaultText_Bool('options', 'ShowThreadID', Z.Status.StatusThreadID);
    Z.Status.ConsoleOutput := External_Conf.GetDefaultText_Bool('options', 'ConsoleOutput', Z.Status.ConsoleOutput);
    TZNet_Server_IPC.IPC_Serv_ThreadCount := External_Conf.GetDefaultText_I32('options', 'IPC_Serv_ThreadCount', TZNet_Server_IPC.IPC_Serv_ThreadCount);
    TZNet_Server_IPC.IPC_Serv_MaxQueueLength := External_Conf.GetDefaultText_I64('options', 'IPC_Serv_MaxQueueLength', TZNet_Server_IPC.IPC_Serv_MaxQueueLength);
    TZNet_Server_IPC.IPC_Serv_MaxMsgSize := External_Conf.GetDefaultText_I64('options', 'IPC_Serv_MaxMsgSize', TZNet_Server_IPC.IPC_Serv_MaxMsgSize);
    C40ReadConfig(External_Conf.HStringList['C4-Options'].Trim_Value_Space_And_Semicolon_Comment);
  except
  end;
  DisposeObjectAndNil(External_Conf);
end;

{ * Free_External_Conf: If the configuration file does not exist, creates it
  * with default content. }
procedure Free_External_Conf;
{$REGION 'INI_Text'}
const
  Conf_Text =
    '; ============================================================================'#13#10 +
    '; API Hub Runtime Configuration File'#13#10 +
    '; This file is automatically generated by the Z.API_HubTool_Export library on'#13#10 +
    '; first run (if it does not already exist). Modify this file and restart your'#13#10 +
    '; application for changes to take effect.'#13#10 +
    '; ============================================================================'#13#10 +
    #13#10 +
    '[options]'#13#10 +
    '; ----------------------------------------------------------------------------'#13#10 +
    '; General Options'#13#10 +
    '; ----------------------------------------------------------------------------'#13#10 +
    #13#10 +
    '; Whether to wait for all prepared C4 clients to be fully connected and'#13#10 +
    '; initialized before API_Prepare_Done returns.'#13#10 +
    '; True  : API_Prepare_Done will block until all clients are ready or timeout.'#13#10 +
    '; False : API_Prepare_Done returns immediately without waiting.'#13#10 +
    '; Default: True'#13#10 +
    'Wait_Connection_ReadyOk=True'#13#10 +
    #13#10 +
    '; Maximum timeout (in milliseconds) to wait for connections to become ready'#13#10 +
    '; when Wait_Connection_ReadyOk is True.'#13#10 +
    '; After this timeout, API_Prepare_Done returns even if some clients are not'#13#10 +
    '; connected.'#13#10 +
    '; Default: 30000 (30 seconds)'#13#10 +
    'Wait_Connection_Timeout=30000'#13#10 +
    #13#10 +
    '; Whether to include thread IDs in log messages (via DoStatus).'#13#10 +
    '; In library mode (DLL/shared object), this is forced to False to reduce noise.'#13#10 +
    '; Default: False (library mode) / depends on host application'#13#10 +
    'ShowThreadID=False'#13#10 +
    #13#10 +
    '; Whether to allow log messages to be printed to the console (stdout/stderr).'#13#10 +
    '; In library mode, this is forced to True for easier debugging.'#13#10 +
    '; Default: True (library mode)'#13#10 +
    'ConsoleOutput=True'#13#10 +
    #13#10 +
    '; Thread pool size for the IPC (Inter-Process Communication) service.'#13#10 +
    '; Affects the concurrency of TZNet_Server_IPC when handling incoming requests.'#13#10 +
    '; Default: 4'#13#10 +
    'IPC_Serv_ThreadCount=4'#13#10 +
    #13#10 +
    '; Maximum length (number of messages) of the IPC message queue.'#13#10 +
    '; If exceeded, new messages may be dropped or blocked.'#13#10 +
    '; Default: 4096'#13#10 +
    'IPC_Serv_MaxQueueLength=4096'#13#10 +
    #13#10 +
    '; Maximum size (in bytes) of a single IPC message.'#13#10 +
    '; Messages exceeding this limit will be rejected to prevent memory exhaustion.'#13#10 +
    '; Default: 32768 (32 KB)'#13#10 +
    'IPC_Serv_MaxMsgSize=32768'#13#10 +
    #13#10 +
    #13#10 +
    '[C4-Options]'#13#10 +
    '; ----------------------------------------------------------------------------'#13#10 +
    '; C4 Distributed Service Framework Configuration'#13#10 +
    '; These parameters are passed to C40ReadConfig and control the behaviour of'#13#10 +
    '; the underlying C4 kernel, including service discovery, reconnection, and'#13#10 +
    '; network timeouts.'#13#10 +
    '; ----------------------------------------------------------------------------'#13#10 +
    #13#10 +
    '; Whether to enable quiet mode for the C4 framework.'#13#10 +
    '; True  : Suppresses most log output (only errors and critical info).'#13#10 +
    '; False : Prints detailed debug information.'#13#10 +
    '; In library mode, this is set to True by default.'#13#10 +
    'Quiet=True'#13#10 +
    #13#10 +
    '; Health-check interval (in milliseconds) for C4 services and clients.'#13#10 +
    '; Each component will periodically call its SafeCheck method for self-diagnosis.'#13#10 +
    '; Default: 45000 (45 seconds)'#13#10 +
    'SafeCheckTime=45000'#13#10 +
    #13#10 +
    '; Delay (in seconds) before automatically reconnecting after a physical'#13#10 +
    '; connection loss. Supports floating-point values (e.g., 5.0).'#13#10 +
    '; Default: 5.0'#13#10 +
    'PhysicsReconnectionDelayTime=5'#13#10 +
    #13#10 +
    '; Debounce delay (in milliseconds) for propagating service info updates to'#13#10 +
    '; the Dispatch (DP) service. Multiple updates within this window are merged'#13#10 +
    '; into a single broadcast to reduce network overhead.'#13#10 +
    '; Default: 1000 (1 second)'#13#10 +
    'UpdateServiceInfoDelayTime=1000'#13#10 +
    #13#10 +
    '; Idle timeout (in milliseconds) for a PhysicsService (server-side).'#13#10 +
    '; If no communication activity occurs within this period, the connection is'#13#10 +
    '; automatically closed.'#13#10 +
    '; Default: 900000 (15 minutes)'#13#10 +
    'PhysicsServiceTimeout=900000'#13#10 +
    #13#10 +
    '; Idle timeout (in milliseconds) for a PhysicsTunnel (client-side).'#13#10 +
    '; If no communication activity occurs within this period, the connection is'#13#10 +
    '; automatically closed.'#13#10 +
    '; Default: 900000 (15 minutes)'#13#10 +
    'PhysicsTunnelTimeout=900000'#13#10 +
    #13#10 +
    '; Threshold (in milliseconds) after which a persistent network failure'#13#10 +
    '; (disconnection) triggers a forced cleanup of the corresponding physical'#13#10 +
    '; tunnel and its associated resources. Prevents zombie connections from'#13#10 +
    '; lingering indefinitely.'#13#10 +
    '; Default: 604800000 (7 days)'#13#10 +
    'KillIDCFaultTimeout=604800000'#13#10 +
    #13#10 +
    '; Whether to allow each C4 service to use its own subdirectory for storing'#13#10 +
    '; configuration and data files. In library mode, this is forced to False to'#13#10 +
    '; avoid creating extra folders in the working directory.'#13#10 +
    '; Default: False'#13#10 +
    'EnablePerServiceDirectory=False'#13#10;
{$ENDREGION 'INI_Text'}

var
  buff_: TBytes;
begin
  if not External_Conf_Auto_Save then
      exit;
  if not umlFileExists(External_Conf_FileName.Text) then
    begin
      buff_ := TAPI_String(Conf_Text).UTF8; // Convert default text to UTF‑8.
      SaveMemory(@buff_[0], length(buff_), External_Conf_FileName.Text);
      SetLength(buff_, 0);
    end;
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
Wait_Connection_Timeout := 30 * 1000; // 30 seconds default.
if IsLibrary then
  begin
    Z.Status.StatusThreadID := False; // Disable thread ID in logs for library.
    Z.Status.ConsoleOutput := True; // Enable console output.
    Z.Net.C4.C40SetQuietMode(True); // Quiet mode.
  end;
C40_EnablePerServiceDirectory := False; // Avoid creating subdirectories.
Init_External_Conf(); // Load configuration.

finalization

API_Exit_MainThread(); // Ensure the main loop stops.
On_C40_PhysicsTunnel_Event_Console := nil;
On_C40_PhysicsService_Event_Console := nil;
DisposeObjectAndNil(Prepare_Commands);
DisposeObjectAndNil(AppHnd_Bind_Tag_List);
DisposeObjectAndNil(Temp_C40_PhysicsTunnel_Bridge__);
DisposeObjectAndNil(Temp_C40_PhysicsService_Bridge__);
Free_External_Conf(); // Create configuration file if missing.

end.
