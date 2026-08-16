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
  This unit declares all error codes, types, and external functions.
  It dynamically loads the shared library at runtime, supporting Windows,
  Linux, macOS, and BSD systems. It also installs a status callback that
  redirects C++ library log output to the Pascal Z.Status system.

  The library is loaded using SysUtils.LoadLibrary and GetProcAddress, which
  are available in both Delphi and Free Pascal across all supported platforms.
*)

unit Z.IPC.API;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

{ * AI engine compatible record packing - ensures binary layout matches C structs }
{$IFDEF FPC}
{$PACKENUM 4}    { * Use 4-byte enums to match C compiler defaults }
{$PACKRECORDS C} { * Use C-compatible record alignment (no automatic packing) }
{$ELSE FPC}
{$MINENUMSIZE 4} { * Force Delphi enums to be 4 bytes (matches C int) }
{$ENDIF FPC}

interface

const
  { * Return codes for all IPC operations.
    * These constants are returned by every API function to indicate success
    * or the specific nature of a failure. All negative values are errors.
    * The values must exactly match the C header (z_ipc_api.h).
    * @Example:
    *   if ipc_client_connect(handle, 'my_queue') = IPC_OK then
    *     WriteLn('Connected successfully');
    *   else
    *     WriteLn('Connection failed');
  }
  IPC_OK = 0; { * Operation completed without error }
  IPC_ERR_OPEN = -1; { * Could not open the message queue (does not exist or permission denied) }
  IPC_ERR_SIZE = -2; { * Invalid size (too large, or zero with non‑null data) }
  IPC_ERR_SEND = -3; { * Failed to send a message through the queue }
  IPC_ERR_RECEIVE = -4; { * Failed to receive a message from the queue }
  IPC_ERR_MEMORY = -5; { * Memory allocation failed (shared memory or heap) }
  IPC_ERR_PERMISSION = -6; { * Insufficient permissions to access queue or shared memory }
  IPC_ERR_TIMEOUT = -7; { * Operation timed out (client RPC call) }
  IPC_ERR_TYPE = -8; { * Type mismatch (reserved for future extensions) }
  IPC_ERR_NOT_FOUND = -9; { * Handler or queue not found }
  IPC_ERR_BUSY = -10; { * Resource busy (e.g., handler already registered) }
  IPC_ERR_INVAL = -11; { * Invalid argument (null pointer, empty name, etc.) }
  IPC_ERR_UNKNOWN = -99; { * Unspecified or unexpected error }

type
  { * TSize_t – Platform-independent size type matching C's size_t.
    * On 64-bit platforms it is 8 bytes (NativeUInt), on 32-bit it is 4 bytes
    * (Cardinal). This ensures correct data sizes when calling C functions.
  }
{$IFDEF CPU64}
  TSize_t = NativeUInt;
{$ELSE}
  TSize_t = Cardinal;
{$ENDIF}
  TIPCServerHandle = Integer; { * Opaque handle for a server instance (non-zero if valid) }
  TIPCClientHandle = Integer; { * Opaque handle for a client instance (non-zero if valid) }

  { * TIPCServerConfig – Configuration record for server creation.
    * This struct must have the exact same memory layout as the C
    * 'ipc_server_config_t' from z_ipc_api.h. Because the C header uses
    * '#pragma pack(1)', we use 'packed record' in Pascal to force 1-byte
    * alignment, ensuring the fields are placed without padding.
    * @Field thread_count   : Number of worker threads (0 = auto-detect).
    * @Field max_queue_length: Maximum number of pending messages in the queue.
    * @Field max_msg_size   : Maximum size (in bytes) of control messages.
    * @Example:
    *   var cfg: TIPCServerConfig;
    *   begin
    *     cfg.thread_count := 0;       // Auto-detect thread count
    *     cfg.max_queue_length := 1000;
    *     cfg.max_msg_size := 1024;
    *     handle := ipc_server_create_ex('my_queue', @cfg);
    *   end;
  }
  TIPCServerConfig = packed record
    thread_count: Integer;
    max_queue_length: TSize_t;
    max_msg_size: TSize_t;
  end;

  PIPCServerConfig = ^TIPCServerConfig;

  { * TIPCBinaryReplyHandler – Callback for server-side binary RPC requests.
    * This is a cdecl procedure that the server calls when a client invokes
    * an RPC function. The implementation must process the request and produce
    * a reply. The reply buffer must be allocated using ipc_alloc() so that
    * the caller (the library) can later free it.
    * @Param trigger : User-supplied pointer (set during registration).
    * @Param data    : Pointer to the request payload (may be nil if size=0).
    * @Param size    : Size of the payload in bytes.
    * @Param outData : Output buffer pointer – must be allocated with ipc_alloc.
    * @Param outSize : Output buffer size (0 if no reply).
    * @Warning This callback runs in a worker thread and MUST NOT block.
    * @Example:
    *   procedure MyEchoHandler(trigger: Pointer; data: Pointer; size: TSize_t;
    *     out outData: Pointer; out outSize: TSize_t); cdecl;
    *   begin
    *     if size = 0 then begin outData := nil; outSize := 0; Exit; end;
    *     outData := ipc_alloc(size);    // Allocate reply buffer
    *     if outData <> nil then begin
    *       Move(data^, outData^, size); // Copy payload to reply
    *       outSize := size;
    *     end else outSize := 0;
    *   end;
  }
  TIPCBinaryReplyHandler = procedure(trigger: Pointer; data: Pointer; size: TSize_t; out outData: Pointer; out outSize: TSize_t); cdecl;

  { * TIPCBinaryNotifyHandler – Callback for binary notifications.
    * This is a cdecl procedure called when a notification with a matching
    * name is received. It can be used on both the client and server sides.
    * Unlike the reply handler, there is no return value – it's fire-and-forget.
    * @Param trigger : User-supplied pointer.
    * @Param data    : Pointer to the notification payload (may be nil).
    * @Param size    : Payload size in bytes.
    * @Warning This callback runs in a worker/receiver thread and MUST NOT block.
    * @Example:
    *   procedure MyNotifyHandler(trigger: Pointer; data: Pointer; size: TSize_t);
    *   cdecl;
    *   begin
    *     WriteLn('Received notification of ', size, ' bytes');
    *   end;
  }
  TIPCBinaryNotifyHandler = procedure(trigger: Pointer; data: Pointer; size: TSize_t); cdecl;

  { * TIPCStatusHandler – Callback for receiving status/log characters.
    * This callback receives individual characters (as integers) from the
    * library's internal logging (std::cerr). The Pascal binding collects
    * characters until a newline is encountered, then forwards the line to
    * Z.Status.DoStatus. See Do_Status_handler for the implementation.
  }
  TIPCStatusHandler = procedure(code: Integer); cdecl;

  { *****************************************************************************
    SERVER API
    These functions manage an IPC server that listens on a named queue and
    dispatches RPC requests and notifications to registered handlers.
    The server must be created with ipc_server_create or ipc_server_create_ex,
    and then handlers can be registered. Finally, ipc_server_destroy cleans up.
    ***************************************************************************** }

function ipc_server_create(queue_name: PAnsiChar; thread_count: Integer): TIPCServerHandle; cdecl;
function ipc_server_create_ex(queue_name: PAnsiChar; cfg: PIPCServerConfig): TIPCServerHandle; cdecl;
function ipc_server_destroy(handle: TIPCServerHandle): Integer; cdecl;
function ipc_server_register_binary_reply(handle: TIPCServerHandle; name: PAnsiChar; handler: TIPCBinaryReplyHandler; trigger: Pointer): Integer; cdecl;
function ipc_server_unregister_binary_reply(handle: TIPCServerHandle; name: PAnsiChar): Integer; cdecl;
function ipc_server_register_binary_notify(handle: TIPCServerHandle; name: PAnsiChar; handler: TIPCBinaryNotifyHandler; trigger: Pointer): Integer; cdecl;
function ipc_server_unregister_binary_notify(handle: TIPCServerHandle; name: PAnsiChar): Integer; cdecl;
function ipc_server_send_notify_binary(handle: TIPCServerHandle; client_resp_queue: PAnsiChar; func_name: PAnsiChar; data: Pointer; size: TSize_t): Integer; cdecl;

{ *****************************************************************************
  CLIENT API
  These functions create and manage client connections to an IPC server.
  A client is created with ipc_client_create, then connected with
  ipc_client_connect. After connection, it can make RPC calls and send
  notifications. Use ipc_client_destroy to clean up.
  ***************************************************************************** }

function ipc_client_create: TIPCClientHandle; cdecl;
function ipc_client_destroy(handle: TIPCClientHandle): Integer; cdecl;
function ipc_client_connect(handle: TIPCClientHandle; queue_name: PAnsiChar): Integer; cdecl;
function ipc_client_disconnect(handle: TIPCClientHandle): Integer; cdecl;
function ipc_client_get_resp_queue_name(handle: TIPCClientHandle): PAnsiChar; cdecl;
function ipc_client_register_binary_notify(handle: TIPCClientHandle; name: PAnsiChar; handler: TIPCBinaryNotifyHandler; trigger: Pointer): Integer; cdecl;
function ipc_client_unregister_binary_notify(handle: TIPCClientHandle; name: PAnsiChar): Integer; cdecl;
function ipc_client_call_binary(handle: TIPCClientHandle; func_name: PAnsiChar; send_data: Pointer; send_size: TSize_t; out outData: Pointer; out outSize: TSize_t): Integer; cdecl;
function ipc_client_notify_binary(handle: TIPCClientHandle; func_name: PAnsiChar; send_data: Pointer; send_size: TSize_t): Integer; cdecl;
function ipc_client_set_timeout(handle: TIPCClientHandle; milliseconds: Integer): Integer; cdecl;
function ipc_client_is_connected(handle: TIPCClientHandle): Integer; cdecl;

{ *****************************************************************************
  MEMORY MANAGEMENT
  Functions to allocate and free memory that is passed across the API boundary.
  These are wrappers around malloc/free and must be used for any buffer that
  crosses between Pascal and C code.
  ***************************************************************************** }

function ipc_alloc(size: TSize_t): Pointer; cdecl;
procedure ipc_free(ptr: Pointer); cdecl;

{ *****************************************************************************
  UTILITIES
  Global helper functions for logging, cleanup, and shutdown.
  ***************************************************************************** }

procedure ipc_Set_Status_handler(handler: TIPCStatusHandler); cdecl;
procedure ipc_cleanup(queue_name: PAnsiChar); cdecl;
procedure ipc_shutdown; cdecl;

procedure Do_Status_handler(i_char: Integer); cdecl;

{ * LoadIPCLibrary – Loads the z_ipc shared library and resolves all symbols.
  * This function is called automatically during unit initialization but can
  * be called manually if needed. It looks for the library in the system path
  * or current directory using platform-specific naming conventions.
  * @Returns True if the library was loaded and all exports were found.
  * @SeeAlso UnloadIPCLibrary
}
function LoadIPCLibrary: Boolean;

{ * UnloadIPCLibrary – Unloads the z_ipc shared library and frees resources.
  * This function calls ipc_shutdown to stop all servers and clients, then
  * unloads the library. It is called automatically during unit finalization.
  * @SeeAlso LoadIPCLibrary
}
procedure UnloadIPCLibrary;

implementation

uses
{$IFDEF MSWINDOWS}
  windows,
{$ENDIF MSWINDOWS}
  SysUtils, {* Provides LoadLibrary, GetProcAddress, FreeLibrary on all platforms}
  Z.Core, {* Core utility functions}
  Z.PascalStrings, {* String handling extensions}
  Z.MemoryStream, {* Memory stream classes}
  Z.Status, Z.UPascalStrings, Z.UnicodeMixedLib;
{ * Global status/logging system (DoStatus) }

{$IFDEF DELPHI}


type
  TLibHandle = THandle;
{$ENDIF DELPHI}


var
  LibHandle: TLibHandle = 0; { * Handle to the loaded shared library (0 = not loaded) }

  { * Function pointer types for each API function – these match the C signatures.
    Each type defines the exact parameter list and return type of the
    corresponding C function. The pointers are assigned when the library loads.
  }
type
  Tipc_server_create = function(queue_name: PAnsiChar; thread_count: Integer): TIPCServerHandle; cdecl;
  Tipc_server_create_ex = function(queue_name: PAnsiChar; cfg: PIPCServerConfig): TIPCServerHandle; cdecl;
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
  { * Global function pointers for each API call. These are assigned by
    LoadIPCLibrary and checked in the wrapper functions before use.
    If the library is not loaded, calling any API function will return
    an error (or 0/null) instead of crashing.
  }
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

  { * GetDefaultLibraryName – Returns the platform-specific file name of the z_ipc library.
    This function determines the correct library name based on the operating
    system and architecture (32-bit vs 64-bit). The Pascal binding uses this
    name when calling LoadLibrary.
    @Returns The library file name (e.g., 'z_ipc_64.dll' on Windows 64-bit).
  }
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
  { * On FreeBSD/OpenBSD, shared libraries typically use the .so extension }
  Result := 'libz_ipc.so';
{$ELSE}
  Result := '';
{$ENDIF}
end;

{ * LoadIPCLibrary – Loads the z_ipc shared library and resolves all exports.
  This function is called automatically during unit initialization. It does:
  1. If the library is already loaded, returns True.
  2. Gets the default library name for the current platform.
  3. Calls LoadLibrary to load the shared library into the process.
  4. Uses GetProcAddress to resolve each C function by name.
  5. If any export is missing, unloads the library and returns False.
  6. Installs the status callback (Do_Status_handler) to capture logs.
  @Returns True if the library was successfully loaded and all symbols found.
}
function LoadIPCLibrary: Boolean;
var
  LibName: string;
  P: {$IFDEF FPC}PAnsiChar{$ELSE FPC}PWideChar{$ENDIF FPC};
begin
  Result := False;
  if LibHandle <> 0 then
      Exit(True);

  LibName := GetDefaultLibraryName;
  if LibName = '' then
      Exit;

  { * Load the shared library using the platform's dynamic linker.
    On Windows this loads a .dll, on Linux/macOS it loads .so/.dylib.
  }
  LibHandle := LoadLibrary(PChar(LibName));
  if LibHandle = 0 then
    begin
      // search dll-self directory

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

  { * Resolve each function pointer by name using GetProcAddress.
    The names must match the C exports exactly (case-sensitive).
    All C functions are declared with extern "C", so they are unmangled.
  }
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

  { * Verify that all symbols were found. If any are missing, the library
    may be an incompatible version. Unload and return False.
  }
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
      { * Install the status handler to capture C++ library logs.
        Do_Status_handler will receive characters from std::cerr.
      }
      ipc_Set_Status_handler(Do_Status_handler);
      Result := True;
      Exit;
    end;

  { * If any exports are missing, clean up and return False }
  FreeLibrary(LibHandle);
  LibHandle := 0;
  DoStatus('IPC library loaded but missing some exports.');
  Result := False;
end;

{ * UnloadIPCLibrary – Unloads the z_ipc library and clears function pointers.
  This is called during unit finalization. It calls ipc_shutdown to stop
  all servers and clients, then unloads the library.
}
procedure UnloadIPCLibrary;
begin
  if LibHandle <> 0 then
    begin
      ipc_shutdown(); { * Stop all servers and clients }
      FreeLibrary(LibHandle);
      LibHandle := 0;
    end;
  { * Clear all function pointers to prevent accidental use after unload }
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

{ * Wrapper functions for all API calls.
  Each wrapper checks whether the corresponding function pointer is assigned.
  If the library is not loaded, it returns a safe error value (0, nil, or
  IPC_ERR_UNKNOWN) instead of calling a nil pointer.
}

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
      Result := _ipc_server_create_ex(queue_name, cfg);
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
  IPC_Status_buff: TMem64 = nil; { * Buffer that collects log characters until newline }
  IPC_Status_Critical: TCritical = nil; { * Critical section protecting the buffer }

  { * Do_Status_handler – Status callback installed via ipc_Set_Status_handler.
    This procedure receives individual characters from the C++ library's
    std::cerr stream (via the custom streambuf). It collects characters
    into a buffer until a newline (ASCII 10) or carriage return (ASCII 13)
    is received, then passes the complete line to Z.Status.DoStatus.
    @Param i_char The character code (0-255) received from the library.
    @Warning This runs in a C++ thread context and must be thread-safe.
    @Example:
    When the C++ library calls std::cerr << "Hello" << std::endl;
    this handler receives 'H', 'e', 'l', 'l', 'o', and finally 10 (newline).
    It then calls DoStatus('Hello') to log the message.
  }
procedure Do_Status_handler(i_char: Integer); cdecl;
var
  buff: TBytes;
  log_: TPascalString;
begin
  IPC_Status_Critical.Acquire; { * Enter critical section to protect the buffer }
  try
    if (i_char in [10, 13]) then { * Newline or carriage return – flush the buffer }
      begin
        if (IPC_Status_buff.size > 0) then
          begin
            SetLength(buff, IPC_Status_buff.size);
            CopyPtr(IPC_Status_buff.memory, @buff[0], IPC_Status_buff.size);
            IPC_Status_buff.Clear;
            log_.ANSI := buff;
            log_ := log_.TrimChar(#32#9#13); { * Remove trailing whitespace }
            SetLength(buff, 0);
            DoStatus(log_);
            log_ := '';
          end
        else if i_char = 10 then { * Empty line – just output a blank line }
            DoStatus('');
      end
    else
      begin
        { * Append the character to the buffer. If the character is less than
          255 (8-bit), store as a single byte; otherwise as a 16-bit value.
          This handles both ASCII and Unicode characters from the library.
        }
        if i_char < $FF then
            IPC_Status_buff.WriteUInt8(i_char)
        else
            IPC_Status_buff.WriteUInt16(i_char);
      end;
  except
    { * Swallow any exceptions to avoid crashing the C++ caller }
  end;
  IPC_Status_Critical.Release; { * Leave critical section }
end;

initialization

IPC_Status_buff := TMem64.CustomCreate($FF);
IPC_Status_Critical := TCritical.Create;
LibHandle := 0;

finalization

if LibHandle <> 0 then
    UnloadIPCLibrary;
DisposeObjectAndNil(IPC_Status_buff);
DisposeObjectAndNil(IPC_Status_Critical);

end.
 
