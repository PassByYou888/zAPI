(*
MIT License

Copyright (c) 2026 by.LaoZhang qq600585

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*)
(*
  Z.IPC.API.pas – Native Delphi/FreePascal interface for the z_ipc C library.

  This unit provides a complete Pascal binding to the z_ipc cross‑process
  RPC and notification library. It dynamically loads the underlying C
  shared library at runtime (no static linking required) and exposes
  all C functions as Pascal procedures/functions with cdecl calling
  convention. It also redirects the C++ library’s internal logging
  (std::cerr) to Pascal’s Z.Status.DoStatus system via a status callback.

  The unit automatically handles platform‑specific library naming and
  loading, and it cleans up resources during finalization. All API
  functions are safe to call even if the library is not loaded – they
  return error codes or 0/nil gracefully.
*)

unit Z.IPC.API;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

(* Force 4‑byte enumeration and C‑compatible record packing to match
   the C compiler’s layout for structures passed to the library. *)
{$IFDEF FPC}
  {$PACKENUM 4}
  {$PACKRECORDS C}
{$ELSE FPC}
  {$MINENUMSIZE 4}
{$ENDIF FPC}

interface

(* ============================================================================
   Error codes returned by all IPC functions.
   Negative values indicate an error; IPC_OK (0) means success.
   These constants must match the C header exactly.
   ============================================================================ *)
const
  IPC_OK          = 0;   // Operation completed successfully
  IPC_ERR_OPEN    = -1;  // Could not open the message queue (does not exist or permission denied)
  IPC_ERR_SIZE    = -2;  // Invalid size (too large, or zero with non‑null data)
  IPC_ERR_SEND    = -3;  // Failed to send a message through the queue
  IPC_ERR_RECEIVE = -4;  // Failed to receive a message from the queue
  IPC_ERR_MEMORY  = -5;  // Memory allocation failed (shared memory or heap)
  IPC_ERR_PERMISSION = -6; // Insufficient permissions to access queue or shared memory
  IPC_ERR_TIMEOUT = -7;  // Operation timed out (client RPC call)
  IPC_ERR_TYPE    = -8;  // Type mismatch (reserved for future extensions)
  IPC_ERR_NOT_FOUND = -9; // Handler or queue not found
  IPC_ERR_BUSY    = -10; // Resource busy (e.g., handler already registered)
  IPC_ERR_INVAL   = -11; // Invalid argument (null pointer, empty name, etc.)
  IPC_ERR_UNKNOWN = -99; // Unspecified or unexpected error

type
(* ----------------------------------------------------------------------------
   TSize_t – Platform‑dependent size type matching C's size_t.
   On 64‑bit systems it is a NativeUInt (8 bytes), on 32‑bit it is a Cardinal
   (4 bytes). This guarantees correct parameter sizes when calling C functions.
   ---------------------------------------------------------------------------- *)
{$if defined(CPU64) or defined(CPUX64)}
  TSize_t = NativeUInt;
{$ELSE}
  TSize_t = Cardinal;
{$ENDIF}

  TIPCServerHandle = Integer; // Opaque handle for a server instance (non‑zero if valid)
  TIPCClientHandle = Integer; // Opaque handle for a client instance (non‑zero if valid)

(* ----------------------------------------------------------------------------
   TIPCBinaryReplyHandler – Callback for server‑side binary RPC requests.

   This procedure is called by the server when a client invokes an RPC
   function. It must process the request and produce a reply. The reply
   buffer must be allocated using ipc_alloc() so that the library can
   free it later.

   @param trigger  User‑supplied pointer set during registration (arbitrary data).
   @param data     Pointer to the request payload (may be nil if size = 0).
   @param size     Size of the payload in bytes.
   @param outData  Output buffer pointer – must be allocated with ipc_alloc.
   @param outSize  Size of the output buffer (set to 0 if no reply).

   @warning This callback runs in a worker thread and MUST NOT block.
            Blocking can prevent the server from shutting down gracefully.
   @example
     procedure MyAddHandler(trigger: Pointer; data: Pointer; size: TSize_t;
       out outData: Pointer; out outSize: TSize_t); cdecl;
     var
       a, b, sum: Integer;
     begin
       if size = 0 then begin outData := nil; outSize := 0; Exit; end;
       // Read two integers from the request payload.
       a := PInteger(data)^;
       b := PInteger(PByte(data) + SizeOf(Integer))^;
       sum := a + b;
       outData := ipc_alloc(SizeOf(Integer));   // Allocate reply buffer
       if outData <> nil then begin
         PInteger(outData)^ := sum;
         outSize := SizeOf(Integer);
       end else
         outSize := 0;
     end;
   ---------------------------------------------------------------------------- *)
  TIPCBinaryReplyHandler = procedure(trigger: Pointer; data: Pointer; size: TSize_t; out outData: Pointer; out outSize: TSize_t); cdecl;

(* ----------------------------------------------------------------------------
   TIPCBinaryNotifyHandler – Callback for binary notifications.

   Called when a notification with a matching name is received on the
   client or server side. It is fire‑and‑forget – no reply is expected.

   @param trigger  User‑supplied pointer.
   @param data     Pointer to the notification payload (may be nil).
   @param size     Payload size in bytes.

   @warning This callback runs in a worker/receiver thread and MUST NOT block.
   @example
     procedure MyNotifyHandler(trigger: Pointer; data: Pointer; size: TSize_t); cdecl;
     begin
       WriteLn('Received notification of ', size, ' bytes');
       // Process the data...
     end;
   ---------------------------------------------------------------------------- *)
  TIPCBinaryNotifyHandler = procedure(trigger: Pointer; data: Pointer; size: TSize_t); cdecl;

(* ----------------------------------------------------------------------------
   TIPCStatusHandler – Callback for receiving individual log characters.

   The library sends each character (as an integer) of its internal log
   output (std::cerr) to this callback. The Pascal binding collects
   characters until a newline is encountered, then forwards the complete
   line to Z.Status.DoStatus.

   @param code  The character code (0‑255) received.
   ---------------------------------------------------------------------------- *)
  TIPCStatusHandler = procedure(code: Integer); cdecl;

(* ============================================================================
   SERVER API – Functions to create, configure, and destroy an IPC server.
   A server listens on a named message queue, registers handlers for RPC
   and notification calls, and can send notifications to clients.
   ============================================================================ *)

(*
  * ipc_server_create – Create a server with default settings.
  * @param queue_name   Name of the main message queue (must be valid).
  * @param thread_count Number of worker threads (0 = auto‑detect).
  * @return A non‑zero server handle on success, or 0 on failure.
  * @note  This is a convenience wrapper; it uses max_queue_length = 1000 and
  *        max_msg_size = 1024. For custom parameters, use ipc_server_create_ex.
  * @example
  *   var h: TIPCServerHandle;
  *   begin
  *     h := ipc_server_create('my_queue', 0);  // auto thread count
  *     if h <> 0 then ... // server is running
  *   end;
*)
function ipc_server_create(queue_name: PAnsiChar; thread_count: Integer): TIPCServerHandle; cdecl;

(*
  * ipc_server_create_ex – Create a server with explicit configuration.
  * @param queue_name        Name of the main queue.
  * @param thread_count      Number of worker threads (0 = auto).
  * @param max_queue_length  Maximum number of pending messages in the queue.
  * @param max_msg_size      Maximum size (in bytes) of control messages.
  * @return A non‑zero server handle on success, or 0 on failure.
  * @note  The server is not actually started until this function returns
  *        successfully. The queue will be created if it does not exist.
  * @example
  *   var h: TIPCServerHandle;
  *   begin
  *     h := ipc_server_create_ex('my_queue', 4, 2000, 2048);
  *     // Creates a server with 4 worker threads, queue capacity 2000,
  *     // and control message size 2048 bytes.
  *   end;
*)
function ipc_server_create_ex(queue_name: PAnsiChar; thread_count: Integer; max_queue_length: TSize_t; max_msg_size: TSize_t): TIPCServerHandle; cdecl;

(*
  * ipc_server_destroy – Stop and destroy a running server.
  * @param handle  The server handle obtained from ipc_server_create( _ex ).
  * @return IPC_OK on success, or an error code (e.g., IPC_ERR_INVAL if handle invalid).
  * @note  This will stop all worker threads and remove the message queue.
  *        The handle becomes invalid after this call.
  * @example
  *   if ipc_server_destroy(h) = IPC_OK then WriteLn('Server stopped');
*)
function ipc_server_destroy(handle: TIPCServerHandle): Integer; cdecl;

(*
  * ipc_server_register_binary_reply – Register an RPC handler on the server.
  * @param handle   Server handle.
  * @param name     Function name that clients will use to call this API.
  * @param handler  Callback of type TIPCBinaryReplyHandler.
  * @param trigger  User‑supplied pointer passed to the handler (can be nil).
  * @return IPC_OK if registered successfully, IPC_ERR_BUSY if a handler
  *         with the same name already exists, or another error code.
  * @note  The handler will be invoked in a worker thread when a matching
  *        REQ message arrives. It must not block.
  * @example
  *   procedure MyAdd(trigger: Pointer; data: Pointer; size: TSize_t; out outData: Pointer; out outSize: TSize_t); cdecl;
  *   ...
  *   ipc_server_register_binary_reply(h, 'add', MyAdd, nil);
*)
function ipc_server_register_binary_reply(handle: TIPCServerHandle; name: PAnsiChar; handler: TIPCBinaryReplyHandler; trigger: Pointer): Integer; cdecl;

(*
  * ipc_server_unregister_binary_reply – Remove an RPC handler.
  * @param handle  Server handle.
  * @param name    Function name to unregister.
  * @return IPC_OK if removed, IPC_ERR_NOT_FOUND if no such handler.
*)
function ipc_server_unregister_binary_reply(handle: TIPCServerHandle; name: PAnsiChar): Integer; cdecl;

(*
  * ipc_server_register_binary_notify – Register a notification handler (client→server).
  * @param handle   Server handle.
  * @param name     Notification name that clients will send.
  * @param handler  Callback of type TIPCBinaryNotifyHandler.
  * @param trigger  User‑supplied pointer.
  * @return IPC_OK on success, IPC_ERR_BUSY if name already taken.
  * @note  This handler is called when a NOTIFY message arrives. It has no reply.
*)
function ipc_server_register_binary_notify(handle: TIPCServerHandle; name: PAnsiChar; handler: TIPCBinaryNotifyHandler; trigger: Pointer): Integer; cdecl;

(*
  * ipc_server_unregister_binary_notify – Remove a notification handler.
*)
function ipc_server_unregister_binary_notify(handle: TIPCServerHandle; name: PAnsiChar): Integer; cdecl;

(*
  * ipc_server_send_notify_binary – Send a binary notification to a specific client.
  * @param handle             Server handle.
  * @param client_resp_queue  The client's response queue name (obtained via
  *                           ipc_client_get_resp_queue_name).
  * @param func_name          Notification name (must be registered on the client).
  * @param data               Payload pointer (may be nil if size = 0).
  * @param size               Payload size in bytes.
  * @return IPC_OK on success, error code otherwise.
  * @note  This is a fire‑and‑forget operation; the server does not wait for
  *        an acknowledgment. The payload is sent via shared memory.
  * @example
  *   var clientQueue: PAnsiChar;
  *   ...
  *   clientQueue := ipc_client_get_resp_queue_name(clientHandle);
  *   ipc_server_send_notify_binary(serverHandle, clientQueue, 'update', @data, len);
*)
function ipc_server_send_notify_binary(handle: TIPCServerHandle; client_resp_queue: PAnsiChar; func_name: PAnsiChar; data: Pointer; size: TSize_t): Integer; cdecl;

(* ============================================================================
   CLIENT API – Functions to create, connect, and communicate with a server.
   A client connects to a server's main queue and can perform RPC calls and
   send notifications. It also receives notifications from the server via
   a private response queue.
   ============================================================================ *)

(*
  * ipc_client_create – Create a new client instance.
  * @return A non‑zero client handle, or 0 on failure.
  * @note  The client is not yet connected; use ipc_client_connect.
*)
function ipc_client_create: TIPCClientHandle; cdecl;

(*
  * ipc_client_destroy – Destroy a client and release resources.
  * @param handle  Client handle.
  * @return IPC_OK on success.
  * @note  The client will be disconnected automatically if connected.
*)
function ipc_client_destroy(handle: TIPCClientHandle): Integer; cdecl;

(*
  * ipc_client_connect – Connect the client to a server's queue.
  * @param handle      Client handle.
  * @param queue_name  Name of the server's main queue.
  * @return IPC_OK on success, IPC_ERR_OPEN if the queue does not exist or
  *         cannot be opened.
  * @note  This function opens the server's queue and creates a private
  *        response queue for this client. It does not perform a handshake;
  *        the higher‑level wrapper handles that.
*)
function ipc_client_connect(handle: TIPCClientHandle; queue_name: PAnsiChar): Integer; cdecl;

(*
  * ipc_client_disconnect – Disconnect the client from the server.
  * @param handle  Client handle.
  * @return IPC_OK on success.
  * @note  This closes the response queue and stops the receiver thread.
*)
function ipc_client_disconnect(handle: TIPCClientHandle): Integer; cdecl;

(*
  * ipc_client_get_resp_queue_name – Get the name of this client's response queue.
  * @param handle  Client handle.
  * @return Pointer to a null‑terminated string, or nil if not connected.
  * @note  The returned string is owned by the client and valid until disconnect.
  *        This name is needed by the server to send notifications to this client.
*)
function ipc_client_get_resp_queue_name(handle: TIPCClientHandle): PAnsiChar; cdecl;

(*
  * ipc_client_register_binary_notify – Register a handler for server→client notifications.
  * @param handle   Client handle.
  * @param name     Notification name (must match what the server sends).
  * @param handler  Callback of type TIPCBinaryNotifyHandler.
  * @param trigger  User‑supplied pointer.
  * @return IPC_OK on success, IPC_ERR_BUSY if already registered.
  * @note  The handler runs in the client's receiver thread and must not block.
  * @example
  *   procedure OnServerUpdate(trigger: Pointer; data: Pointer; size: TSize_t); cdecl;
  *   begin
  *     // Process server notification
  *   end;
  *   ...
  *   ipc_client_register_binary_notify(client, 'update', OnServerUpdate, nil);
*)
function ipc_client_register_binary_notify(handle: TIPCClientHandle; name: PAnsiChar; handler: TIPCBinaryNotifyHandler; trigger: Pointer): Integer; cdecl;

(*
  * ipc_client_unregister_binary_notify – Unregister a notification handler.
*)
function ipc_client_unregister_binary_notify(handle: TIPCClientHandle; name: PAnsiChar): Integer; cdecl;

(*
  * ipc_client_call_binary – Perform a synchronous binary RPC call.
  * @param handle      Client handle.
  * @param func_name   Function name on the server.
  * @param send_data   Request payload pointer (may be nil if send_size = 0).
  * @param send_size   Payload size.
  * @param outData     Output pointer that will receive the reply buffer
  *                    (allocated with ipc_alloc; caller must free with ipc_free).
  * @param outSize     Output size of the reply.
  * @return IPC_OK on success, IPC_ERR_TIMEOUT if the call times out, or other
  *         error codes.
  * @note  This function blocks until the server replies or the timeout expires.
  *        The timeout can be set with ipc_client_set_timeout.
  * @example
  *   var replyData: Pointer; replySize: TSize_t;
  *   begin
  *     if ipc_client_call_binary(client, 'add', @params, SizeOf(params),
  *         replyData, replySize) = IPC_OK then
  *     begin
  *       // Process replyData
  *       ipc_free(replyData); // Must free
  *     end;
  *   end;
*)
function ipc_client_call_binary(handle: TIPCClientHandle; func_name: PAnsiChar; send_data: Pointer; send_size: TSize_t; out outData: Pointer; out outSize: TSize_t): Integer; cdecl;

(*
  * ipc_client_notify_binary – Send a binary notification (fire‑and‑forget).
  * @param handle      Client handle.
  * @param func_name   Notification name (must be registered on the server).
  * @param send_data   Payload pointer.
  * @param send_size   Payload size.
  * @return IPC_OK on success, error code otherwise.
  * @note  This function does not wait for a reply.
*)
function ipc_client_notify_binary(handle: TIPCClientHandle; func_name: PAnsiChar; send_data: Pointer; send_size: TSize_t): Integer; cdecl;

(*
  * ipc_client_set_timeout – Set the timeout for RPC calls.
  * @param handle        Client handle.
  * @param milliseconds  Timeout in milliseconds (> 0).
  * @return IPC_OK on success, IPC_ERR_INVAL if timeout <= 0.
  * @note  The default timeout is 5000 ms. This setting affects all subsequent
  *        call_binary calls for this client.
*)
function ipc_client_set_timeout(handle: TIPCClientHandle; milliseconds: Integer): Integer; cdecl;

(*
  * ipc_client_is_connected – Check if the client is connected.
  * @param handle  Client handle.
  * @return 1 if connected, 0 otherwise.
*)
function ipc_client_is_connected(handle: TIPCClientHandle): Integer; cdecl;

(* ============================================================================
   MEMORY MANAGEMENT – Functions to allocate/free buffers that cross the API boundary.
   These are wrappers around malloc/free and must be used for any buffer that
   is passed from Pascal to C or vice versa.
   ============================================================================ *)

(*
  * ipc_alloc – Allocate a memory block.
  * @param size  Number of bytes.
  * @return Pointer to allocated memory, or nil on failure.
  * @note  This memory must be freed with ipc_free. It is used by reply
  *        handlers and by the client to allocate reply buffers.
*)
function ipc_alloc(size: TSize_t): Pointer; cdecl;

(*
  * ipc_free – Free a memory block allocated with ipc_alloc.
  * @param ptr  Pointer to free (nil is safe).
*)
procedure ipc_free(ptr: Pointer); cdecl;

(* ============================================================================
   UTILITIES – Global logging, cleanup, and shutdown.
   ============================================================================ *)

(*
  * ipc_Set_Status_handler – Install a callback to receive log output.
  * @param handler  A TIPCStatusHandler procedure, or nil to remove.
  * @note  The library sends characters from std::cerr to this callback.
  *        This allows integration with Pascal's logging system (e.g., DoStatus).
*)
procedure ipc_Set_Status_handler(handler: TIPCStatusHandler); cdecl;

(*
  * ipc_cleanup – Remove a named queue from the system.
  * @param queue_name  Name of the queue to remove.
  * @note  This is a convenience function that forcibly removes the queue,
  *        useful for cleaning up leftovers from a previous run.
*)
procedure ipc_cleanup(queue_name: PAnsiChar); cdecl;

(*
  * ipc_shutdown – Shut down the library and release all global resources.
  * @note  This stops all servers and clients and should be called before
  *        the application exits.
*)
procedure ipc_shutdown; cdecl;

(*
  * Do_Status_handler – The status callback installed by the library.
  * This procedure collects characters until a newline, then forwards the
  * complete line to Z.Status.DoStatus. It is used internally by the unit.
*)
procedure Do_Status_handler(i_char: Integer); cdecl;

(*
  * LoadIPCLibrary – Dynamically load the z_ipc shared library.
  * @return True if the library was loaded and all exports were resolved.
  * @note  This is called automatically during unit initialization, but can
  *        be called manually if needed.
*)
function LoadIPCLibrary: Boolean;

(*
  * UnloadIPCLibrary – Unload the shared library and release resources.
  * @note  Called automatically during unit finalization. It calls ipc_shutdown
  *        before unloading.
*)
procedure UnloadIPCLibrary;


function GetDefaultLibraryName: string;

implementation

uses
{$IFDEF MSWINDOWS}
  windows,
{$ENDIF MSWINDOWS}
  SysUtils,         // Provides LoadLibrary, GetProcAddress, FreeLibrary
  Z.Core,           // Core utilities (e.g., DisposeObject)
  Z.PascalStrings,  // String handling (e.g., TPascalString)
  Z.MemoryStream,   // Memory stream (TMem64)
  Z.Status,         // DoStatus logging
  Z.UPascalStrings, // Unicode string helpers
  Z.UnicodeMixedLib; // Mixed‑encoding utilities

{$IFDEF DELPHI}
type
  TLibHandle = THandle; // Delphi compatibility: THandle is already defined
{$ENDIF DELPHI}

var
  LibHandle: TLibHandle = 0; // Handle to the loaded shared library (0 = not loaded)

  // Function pointer types for each C API function.
  // These types define the exact signatures expected by the C library.
type
  Tipc_server_create = function(queue_name: PAnsiChar; thread_count: Integer): TIPCServerHandle; cdecl;
  Tipc_server_create_ex = function(queue_name: PAnsiChar; thread_count: Integer; max_queue_length: TSize_t; max_msg_size: TSize_t): TIPCServerHandle; cdecl;
  Tipc_server_destroy = function(handle: TIPCServerHandle): Integer; cdecl;
  Tipc_server_register_binary_reply = function(handle: TIPCServerHandle; name: PAnsiChar; handler: TIPCBinaryReplyHandler; trigger: Pointer): Integer; cdecl;
  Tipc_server_unregister_binary_reply = function(handle: TIPCServerHandle; name: PAnsiChar): Integer; cdecl;
  Tipc_server_register_binary_notify = function(handle: TIPCServerHandle; name: PAnsiChar; handler: TIPCBinaryNotifyHandler; trigger: Pointer): Integer; cdecl;
  Tipc_server_unregister_binary_notify = function(handle: TIPCServerHandle; name: PAnsiChar): Integer; cdecl;
  Tipc_server_send_notify_binary = function(handle: TIPCServerHandle; client_resp_queue: PAnsiChar; func_name: PAnsiChar; data: Pointer; size: TSize_t): Integer; cdecl;
  Tipc_client_create = function: TIPCClientHandle; cdecl;
  Tipc_client_destroy = function(handle: TIPCClientHandle): Integer; cdecl;
  Tipc_client_connect = function(handle: TIPCClientHandle; queue_name: PAnsiChar): Integer; cdecl;
  Tipc_client_disconnect = function(handle: TIPCClientHandle): Integer; cdecl;
  Tipc_client_get_resp_queue_name = function(handle: TIPCClientHandle): PAnsiChar; cdecl;
  Tipc_client_register_binary_notify = function(handle: TIPCClientHandle; name: PAnsiChar; handler: TIPCBinaryNotifyHandler; trigger: Pointer): Integer; cdecl;
  Tipc_client_unregister_binary_notify = function(handle: TIPCClientHandle; name: PAnsiChar): Integer; cdecl;
  Tipc_client_call_binary = function(handle: TIPCClientHandle; func_name: PAnsiChar; send_data: Pointer; send_size: TSize_t; out outData: Pointer; out outSize: TSize_t): Integer; cdecl;
  Tipc_client_notify_binary = function(handle: TIPCClientHandle; func_name: PAnsiChar; send_data: Pointer; send_size: TSize_t): Integer; cdecl;
  Tipc_client_set_timeout = function(handle: TIPCClientHandle; milliseconds: Integer): Integer; cdecl;
  Tipc_client_is_connected = function(handle: TIPCClientHandle): Integer; cdecl;
  Tipc_alloc = function(size: TSize_t): Pointer; cdecl;
  Tipc_free = procedure(ptr: Pointer); cdecl;
  Tipc_Set_Status_handler = procedure(handler: TIPCStatusHandler); cdecl;
  Tipc_cleanup = procedure(queue_name: PAnsiChar); cdecl;
  Tipc_shutdown = procedure; cdecl;

var
  // Global function pointers assigned when the library is loaded.
  // These are nil if the library is not loaded.
  _ipc_server_create: Tipc_server_create = nil;
  _ipc_server_create_ex: Tipc_server_create_ex = nil;
  _ipc_server_destroy: Tipc_server_destroy = nil;
  _ipc_server_register_binary_reply: Tipc_server_register_binary_reply = nil;
  _ipc_server_unregister_binary_reply: Tipc_server_unregister_binary_reply = nil;
  _ipc_server_register_binary_notify: Tipc_server_register_binary_notify = nil;
  _ipc_server_unregister_binary_notify: Tipc_server_unregister_binary_notify = nil;
  _ipc_server_send_notify_binary: Tipc_server_send_notify_binary = nil;
  _ipc_client_create: Tipc_client_create = nil;
  _ipc_client_destroy: Tipc_client_destroy = nil;
  _ipc_client_connect: Tipc_client_connect = nil;
  _ipc_client_disconnect: Tipc_client_disconnect = nil;
  _ipc_client_get_resp_queue_name: Tipc_client_get_resp_queue_name = nil;
  _ipc_client_register_binary_notify: Tipc_client_register_binary_notify = nil;
  _ipc_client_unregister_binary_notify: Tipc_client_unregister_binary_notify = nil;
  _ipc_client_call_binary: Tipc_client_call_binary = nil;
  _ipc_client_notify_binary: Tipc_client_notify_binary = nil;
  _ipc_client_set_timeout: Tipc_client_set_timeout = nil;
  _ipc_client_is_connected: Tipc_client_is_connected = nil;
  _ipc_alloc: Tipc_alloc = nil;
  _ipc_free: Tipc_free = nil;
  _ipc_Set_Status_handler: Tipc_Set_Status_handler = nil;
  _ipc_cleanup: Tipc_cleanup = nil;
  _ipc_shutdown: Tipc_shutdown = nil;

(*
  * GetDefaultLibraryName – Returns the platform‑specific file name of the z_ipc library.
  * @return The library file name (e.g., 'z_ipc_64.dll' on Windows 64‑bit,
  *         'libz_ipc.so' on Linux).
  * @note  The name is chosen based on the OS and architecture.
*)
function GetDefaultLibraryName: string;
begin
{$IF Defined(MSWINDOWS)}
  {$IF Defined(CPU64)}
    Result := 'z_ipc_64.dll';
  {$ELSE}
    Result := 'z_ipc_32.dll';
  {$ENDIF}
{$ELSEIF Defined(LINUX)}
  Result := 'libz_ipc.so';
{$ELSEIF Defined(DARWIN)}
  Result := 'libz_ipc.dylib';
{$ELSEIF Defined(BSD)}
  // On FreeBSD/OpenBSD, shared libraries typically use the .so extension.
  Result := 'libz_ipc.so';
{$ELSE}
  Result := '';
{$ENDIF}
end;

(*
  * LoadIPCLibrary – Loads the z_ipc shared library and resolves all exports.
  * @return True if the library was successfully loaded and all symbols found.
  * @note  This function is called automatically during unit initialization.
  *        It installs the status callback (Do_Status_handler) to capture logs.
  *        If any export is missing, the library is unloaded and False is returned.
*)
function LoadIPCLibrary: Boolean;
var
  LibName: string;
  P: {$IFDEF FPC}PAnsiChar{$ELSE FPC}PWideChar{$ENDIF FPC};
begin
  Result := False;
  if LibHandle <> 0 then
      Exit(True); // Already loaded

  LibName := GetDefaultLibraryName;
  if LibName = '' then
      Exit;

  // First attempt: load from system path.
  LibHandle := LoadLibrary(PChar(LibName));
  if LibHandle = 0 then
  begin
    // Second attempt: load from the same directory as the executable.
{$IFDEF FPC}
    P := umlCombineFileName(umlGetFilePath(GetModuleName(0)), GetDefaultLibraryName).BuildAnsiChar;
    LibHandle := LoadLibrary(P);
    U_String.FreeAnsiChar(P);
{$ELSE FPC}
    P := umlCombineFileName(umlGetFilePath(GetModuleName(0)), GetDefaultLibraryName).BuildWideChar;
    LibHandle := LoadLibrary(P);
    U_String.FreeWideChar(P);
{$ENDIF FPC}
    if LibHandle = 0 then
    begin
      DoStatus('Failed to load IPC library: ' + LibName);
      Exit;
    end;
  end;

  // Resolve each exported function by name.
  // All functions are declared with extern "C", so names are unmangled.
  _ipc_server_create := GetProcAddress(LibHandle, 'ipc_server_create');
  _ipc_server_create_ex := GetProcAddress(LibHandle, 'ipc_server_create_ex');
  _ipc_server_destroy := GetProcAddress(LibHandle, 'ipc_server_destroy');
  _ipc_server_register_binary_reply := GetProcAddress(LibHandle, 'ipc_server_register_binary_reply');
  _ipc_server_unregister_binary_reply := GetProcAddress(LibHandle, 'ipc_server_unregister_binary_reply');
  _ipc_server_register_binary_notify := GetProcAddress(LibHandle, 'ipc_server_register_binary_notify');
  _ipc_server_unregister_binary_notify := GetProcAddress(LibHandle, 'ipc_server_unregister_binary_notify');
  _ipc_server_send_notify_binary := GetProcAddress(LibHandle, 'ipc_server_send_notify_binary');
  _ipc_client_create := GetProcAddress(LibHandle, 'ipc_client_create');
  _ipc_client_destroy := GetProcAddress(LibHandle, 'ipc_client_destroy');
  _ipc_client_connect := GetProcAddress(LibHandle, 'ipc_client_connect');
  _ipc_client_disconnect := GetProcAddress(LibHandle, 'ipc_client_disconnect');
  _ipc_client_get_resp_queue_name := GetProcAddress(LibHandle, 'ipc_client_get_resp_queue_name');
  _ipc_client_register_binary_notify := GetProcAddress(LibHandle, 'ipc_client_register_binary_notify');
  _ipc_client_unregister_binary_notify := GetProcAddress(LibHandle, 'ipc_client_unregister_binary_notify');
  _ipc_client_call_binary := GetProcAddress(LibHandle, 'ipc_client_call_binary');
  _ipc_client_notify_binary := GetProcAddress(LibHandle, 'ipc_client_notify_binary');
  _ipc_client_set_timeout := GetProcAddress(LibHandle, 'ipc_client_set_timeout');
  _ipc_client_is_connected := GetProcAddress(LibHandle, 'ipc_client_is_connected');
  _ipc_alloc := GetProcAddress(LibHandle, 'ipc_alloc');
  _ipc_free := GetProcAddress(LibHandle, 'ipc_free');
  _ipc_Set_Status_handler := GetProcAddress(LibHandle, 'ipc_Set_Status_handler');
  _ipc_cleanup := GetProcAddress(LibHandle, 'ipc_cleanup');
  _ipc_shutdown := GetProcAddress(LibHandle, 'ipc_shutdown');

  // Verify that all exports were found. If any are missing, unload and fail.
  if Assigned(_ipc_server_create) and Assigned(_ipc_server_create_ex) and
    Assigned(_ipc_server_destroy) and Assigned(_ipc_server_register_binary_reply) and
    Assigned(_ipc_server_unregister_binary_reply) and Assigned(_ipc_server_register_binary_notify) and
    Assigned(_ipc_server_unregister_binary_notify) and Assigned(_ipc_server_send_notify_binary) and
    Assigned(_ipc_client_create) and Assigned(_ipc_client_destroy) and
    Assigned(_ipc_client_connect) and Assigned(_ipc_client_disconnect) and
    Assigned(_ipc_client_get_resp_queue_name) and Assigned(_ipc_client_register_binary_notify) and
    Assigned(_ipc_client_unregister_binary_notify) and Assigned(_ipc_client_call_binary) and
    Assigned(_ipc_client_notify_binary) and Assigned(_ipc_client_set_timeout) and
    Assigned(_ipc_client_is_connected) and Assigned(_ipc_alloc) and
    Assigned(_ipc_free) and Assigned(_ipc_Set_Status_handler) and
    Assigned(_ipc_cleanup) and Assigned(_ipc_shutdown) then
  begin
    // Install the status handler to capture log output.
    ipc_Set_Status_handler(Do_Status_handler);
    Result := True;
    Exit;
  end;

  // If we get here, some exports are missing – clean up.
  FreeLibrary(LibHandle);
  LibHandle := 0;
  DoStatus('IPC library loaded but missing some exports.');
  Result := False;
end;

(*
  * UnloadIPCLibrary – Unloads the library and clears function pointers.
  * @note  This is called during unit finalization. It shuts down all
  *        servers/clients before unloading.
*)
procedure UnloadIPCLibrary;
begin
  if LibHandle <> 0 then
  begin
    ipc_Set_Status_handler(nil);
    ipc_shutdown(); // Stop all servers and clients
    FreeLibrary(LibHandle);
    LibHandle := 0;
  end;
  // Clear all function pointers to prevent accidental use after unload.
  _ipc_server_create := nil;
  _ipc_server_create_ex := nil;
  _ipc_server_destroy := nil;
  _ipc_server_register_binary_reply := nil;
  _ipc_server_unregister_binary_reply := nil;
  _ipc_server_register_binary_notify := nil;
  _ipc_server_unregister_binary_notify := nil;
  _ipc_server_send_notify_binary := nil;
  _ipc_client_create := nil;
  _ipc_client_destroy := nil;
  _ipc_client_connect := nil;
  _ipc_client_disconnect := nil;
  _ipc_client_get_resp_queue_name := nil;
  _ipc_client_register_binary_notify := nil;
  _ipc_client_unregister_binary_notify := nil;
  _ipc_client_call_binary := nil;
  _ipc_client_notify_binary := nil;
  _ipc_client_set_timeout := nil;
  _ipc_client_is_connected := nil;
  _ipc_alloc := nil;
  _ipc_free := nil;
  _ipc_Set_Status_handler := nil;
  _ipc_cleanup := nil;
  _ipc_shutdown := nil;
end;

(* ----------------------------------------------------------------------------
   Wrapper functions for all API calls.
   Each wrapper checks if the corresponding function pointer is assigned.
   If the library is not loaded, it returns a safe error value (0, nil, or
   IPC_ERR_UNKNOWN) instead of calling a nil pointer.
   ---------------------------------------------------------------------------- *)

function ipc_server_create; cdecl;
begin
  if not Assigned(_ipc_server_create) then
      Result := 0
  else
      Result := _ipc_server_create(queue_name, thread_count);
end;

function ipc_server_create_ex; cdecl;
begin
  if not Assigned(_ipc_server_create_ex) then
      Result := 0
  else
      Result := _ipc_server_create_ex(queue_name, thread_count, max_queue_length, max_msg_size);
end;

function ipc_server_destroy; cdecl;
begin
  if not Assigned(_ipc_server_destroy) then
      Result := IPC_ERR_UNKNOWN
  else
      Result := _ipc_server_destroy(handle);
end;

function ipc_server_register_binary_reply; cdecl;
begin
  if not Assigned(_ipc_server_register_binary_reply) then
      Result := IPC_ERR_UNKNOWN
  else
      Result := _ipc_server_register_binary_reply(handle, name, handler, trigger);
end;

function ipc_server_unregister_binary_reply; cdecl;
begin
  if not Assigned(_ipc_server_unregister_binary_reply) then
      Result := IPC_ERR_UNKNOWN
  else
      Result := _ipc_server_unregister_binary_reply(handle, name);
end;

function ipc_server_register_binary_notify; cdecl;
begin
  if not Assigned(_ipc_server_register_binary_notify) then
      Result := IPC_ERR_UNKNOWN
  else
      Result := _ipc_server_register_binary_notify(handle, name, handler, trigger);
end;

function ipc_server_unregister_binary_notify; cdecl;
begin
  if not Assigned(_ipc_server_unregister_binary_notify) then
      Result := IPC_ERR_UNKNOWN
  else
      Result := _ipc_server_unregister_binary_notify(handle, name);
end;

function ipc_server_send_notify_binary; cdecl;
begin
  if not Assigned(_ipc_server_send_notify_binary) then
      Result := IPC_ERR_UNKNOWN
  else
      Result := _ipc_server_send_notify_binary(handle, client_resp_queue, func_name, data, size);
end;

function ipc_client_create; cdecl;
begin
  if not Assigned(_ipc_client_create) then
      Result := 0
  else
      Result := _ipc_client_create;
end;

function ipc_client_destroy; cdecl;
begin
  if not Assigned(_ipc_client_destroy) then
      Result := IPC_ERR_UNKNOWN
  else
      Result := _ipc_client_destroy(handle);
end;

function ipc_client_connect; cdecl;
begin
  if not Assigned(_ipc_client_connect) then
      Result := IPC_ERR_UNKNOWN
  else
      Result := _ipc_client_connect(handle, queue_name);
end;

function ipc_client_disconnect; cdecl;
begin
  if not Assigned(_ipc_client_disconnect) then
      Result := IPC_ERR_UNKNOWN
  else
      Result := _ipc_client_disconnect(handle);
end;

function ipc_client_get_resp_queue_name; cdecl;
begin
  if not Assigned(_ipc_client_get_resp_queue_name) then
      Result := nil
  else
      Result := _ipc_client_get_resp_queue_name(handle);
end;

function ipc_client_register_binary_notify; cdecl;
begin
  if not Assigned(_ipc_client_register_binary_notify) then
      Result := IPC_ERR_UNKNOWN
  else
      Result := _ipc_client_register_binary_notify(handle, name, handler, trigger);
end;

function ipc_client_unregister_binary_notify; cdecl;
begin
  if not Assigned(_ipc_client_unregister_binary_notify) then
      Result := IPC_ERR_UNKNOWN
  else
      Result := _ipc_client_unregister_binary_notify(handle, name);
end;

function ipc_client_call_binary; cdecl;
begin
  if not Assigned(_ipc_client_call_binary) then
      Result := IPC_ERR_UNKNOWN
  else
      Result := _ipc_client_call_binary(handle, func_name, send_data, send_size, outData, outSize);
end;

function ipc_client_notify_binary; cdecl;
begin
  if not Assigned(_ipc_client_notify_binary) then
      Result := IPC_ERR_UNKNOWN
  else
      Result := _ipc_client_notify_binary(handle, func_name, send_data, send_size);
end;

function ipc_client_set_timeout; cdecl;
begin
  if not Assigned(_ipc_client_set_timeout) then
      Result := IPC_ERR_UNKNOWN
  else
      Result := _ipc_client_set_timeout(handle, milliseconds);
end;

function ipc_client_is_connected; cdecl;
begin
  if not Assigned(_ipc_client_is_connected) then
      Result := 0
  else
      Result := _ipc_client_is_connected(handle);
end;

function ipc_alloc; cdecl;
begin
  if not Assigned(_ipc_alloc) then
      Result := nil
  else
      Result := _ipc_alloc(size);
end;

procedure ipc_free; cdecl;
begin
  if Assigned(_ipc_free) then
      _ipc_free(ptr);
end;

procedure ipc_Set_Status_handler; cdecl;
begin
  if Assigned(_ipc_Set_Status_handler) then
      _ipc_Set_Status_handler(handler);
end;

procedure ipc_cleanup; cdecl;
begin
  if Assigned(_ipc_cleanup) then
      _ipc_cleanup(queue_name);
end;

procedure ipc_shutdown; cdecl;
begin
  if Assigned(_ipc_shutdown) then
      _ipc_shutdown;
end;

var
  IPC_Status_buff: TMem64 = nil;      // Buffer that collects log characters until newline
  IPC_Status_Critical: TCritical = nil; // Critical section protecting the buffer

(*
  * Do_Status_handler – Status callback installed via ipc_Set_Status_handler.
  * This procedure receives individual characters from the C++ library's
  * std::cerr stream (via the custom streambuf). It collects characters
  * into a buffer until a newline (ASCII 10) or carriage return (ASCII 13)
  * is received, then passes the complete line to Z.Status.DoStatus.
  * @param i_char  The character code (0‑255) received from the library.
  * @warning This runs in a C++ thread context and must be thread‑safe.
  * @example
  *   When the C++ library calls std::cerr << "Hello" << std::endl;
  *   this handler receives 'H','e','l','l','o', and finally 10 (newline).
  *   It then calls DoStatus('Hello') to log the message.
*)
procedure Do_Status_handler(i_char: Integer); cdecl;
var
  buff: TBytes;
  log_: TPascalString;
begin
  IPC_Status_Critical.Acquire; // Enter critical section to protect the buffer
  try
    if (i_char in [10, 13]) then // Newline or carriage return – flush the buffer
    begin
      if (IPC_Status_buff.size > 0) then
      begin
        SetLength(buff, IPC_Status_buff.size);
        CopyPtr(IPC_Status_buff.memory, @buff[0], IPC_Status_buff.size);
        IPC_Status_buff.Clear;
        log_.ANSI := buff;
        log_ := log_.TrimChar(#32#9#13); // Remove trailing whitespace
        SetLength(buff, 0);
        DoStatus(log_);
        log_ := '';
      end
      else if i_char = 10 then // Empty line – just output a blank line
        DoStatus('');
    end
    else
    begin
      // Append the character to the buffer.
      // If the character is less than 255 (8‑bit), store as a single byte;
      // otherwise store as a 16‑bit value. This handles both ASCII and Unicode.
      if i_char < $FF then
        IPC_Status_buff.WriteUInt8(i_char)
      else
        IPC_Status_buff.WriteUInt16(i_char);
    end;
  except
    // Swallow any exceptions to avoid crashing the C++ caller.
  end;
  IPC_Status_Critical.Release; // Leave critical section
end;

initialization
  IPC_Status_buff := TMem64.CustomCreate($FF); // Pre‑allocate buffer
  IPC_Status_Critical := TCritical.Create;
  LibHandle := 0;

finalization
  if LibHandle <> 0 then
    UnloadIPCLibrary;
  DisposeObjectAndNil(IPC_Status_buff);
  DisposeObjectAndNil(IPC_Status_Critical);

end.
 
