unit z_api_hubtool_helper;

{$ifdef FPC}
  {$mode delphi}{$H+}
  {$modeswitch advancedrecords}
  {$CODEPAGE UTF8}
{$endif}

{-----------------------------------------------------------------------------
  z_api_hubtool_helper – High‑level Pascal wrapper for the API Hub dynamic library.

  This unit provides object‑oriented (RAII) wrappers around the low‑level C
  bindings defined in z_api_hubtool_import. It simplifies memory management
  and offers fluent methods for reading/writing binary data in a type‑safe way.

  Key features:
    * TDataHandle – automatically manages a native TDataHnd; frees it on destruction.
    * TAppHandle – manages an application context and its registered APIs,
      including dynamic unregistration.
    * Global network helpers – ResetPrepare, PrepareService, PrepareClient,
      PrepareDone, CallApp, NotifyApp, SetOption, Shutdown.

  All strings are automatically converted to/from UTF‑8 when passed to the C
  library. The wrapper is thread‑safe as long as the underlying handle is not
  used concurrently in conflicting ways (reads are safe, writes must be serialised).

  @Example (basic usage):
    var
      Data: TDataHandle;
      App: TAppHandle;
    begin
      Data := TDataHandle.Create('add');   // create a data handle for API 'add'
      Data.WriteInt32(5).WriteInt32(7);    // write two integers (chained)
      App := TAppHandle.Create('MyApp', 'My app');
      App.RegisterCall('add', 'adds two ints', nil, @AddCallback);
      // ... network setup, then call remote APIs ...
      Data.Free;  // automatically frees the underlying handle
      App.Free;
    end;
-----------------------------------------------------------------------------}

interface

uses
  Classes, SysUtils, z_api_hubtool_import;   // Low‑level C bindings

type
  { *
    * TDataHandle – RAII wrapper for a native data handle (TDataHnd).
    *
    * A data handle is an opaque pointer that holds a binary buffer along with
    * the name of the API it is intended for. This class encapsulates that
    * handle and automatically frees it (if owned) when the object is destroyed.
    *
    * Ownership:
    *   - When created with Create(const APIName: string), the object owns the
    *     handle and will call API_Free_DataHnd in its destructor.
    *   - When created with Create(AHandle: TDataHnd; Owned: Boolean), ownership
    *     is controlled by the Owned parameter. If Owned is True, the handle
    *     is freed on destruction; if False, the handle is left untouched
    *     (useful for wrapping handles received from callbacks or other sources).
    *
    * All write methods (WriteInt32, WriteString, etc.) are fluent: they return
    * Self so calls can be chained. The current position automatically advances
    * after each write/read. You can manually control position with SetPos/GetPos.
    *
    * Thread safety:
    *   - The underlying library functions are thread‑safe.
    *   - For a given TDataHandle, write operations (WriteBuffer, SetPos, SetSize)
    *     must be serialised across threads. Reads (ReadXXX, GetPos, GetSize) are
    *     safe concurrently with other reads, but not with concurrent writes.
    *
    * @Example:
    *   var
    *     D: TDataHandle;
    *     I: Integer;
    *     S: string;
    *   begin
    *     D := TDataHandle.Create('echo');          // Create for API 'echo'
    *     D.WriteString('Hello');                  // Write a string
    *     D.SetPos(0);                             // Rewind to beginning
    *     if D.ReadString(S) then                  // Read it back
    *       WriteLn(S);
    *     D.Free;                                  // Frees the underlying handle
    *   end;
  }
  TDataHandle = class
  private
    FHandle: TDataHnd;   // Raw pointer to the native data handle
    FOwned: Boolean;     // Whether we own the handle and should free it
  public
    { *
      * Creates a new data handle with a given API name.
      * The internal buffer is initially empty (size = 0). The object will
      * own the handle and free it on destruction.
      * @param APIName – Name of the target API (UTF‑8, case‑sensitive).
      * @raises Exception if the native creation fails (returns nil).
      * @Example:
      *   var D: TDataHandle;
      *   begin
      *     D := TDataHandle.Create('add');   // create for 'add' API
      *     D.WriteInt32(10).WriteInt32(20);  // write parameters
      *     // ... use D ...
      *     D.Free;   // automatically calls API_Free_DataHnd
      *   end;
    }
    constructor Create(const APIName: string); overload;

    { *
      * Wraps an existing native handle.
      * @param AHandle – The native handle to wrap.
      * @param Owned – If True, the destructor will call API_Free_DataHnd;
      *                if False, the handle is not freed (useful for borrowed
      *                handles, e.g., from callbacks).
      * @Example (in a callback):
      *   procedure MyCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
      *   var
      *     InHnd: TDataHandle;
      *   begin
      *     InHnd := TDataHandle.Create(TDataHnd(Input), False); // borrowed
      *     // read from InHnd ...
      *     InHnd.Free;   // does NOT free the native handle
      *   end;
    }
    constructor Create(AHandle: TDataHnd; Owned: Boolean = False); overload;

    { *
      * Destructor: if Owned is True and the handle is non‑nil, calls
      * API_Free_DataHnd to release the native handle.
    }
    destructor Destroy; override;

    { *
      * Writes raw binary data into the buffer at the current position.
      * The position is advanced by Size bytes. The buffer is automatically
      * enlarged if needed.
      * @param Buffer – The source data (passed by reference, can be any type).
      * @param Size – Number of bytes to write.
      * @return The number of bytes actually written (normally equals Size).
      * @Example:
      *   var
      *     D: TDataHandle;
      *     I: Integer;
      *   begin
      *     D := TDataHandle.Create('test');
      *     I := 12345;
      *     D.WriteBuffer(I, SizeOf(I));   // writes the integer as raw bytes
      *   end;
    }
    function WriteBuffer(const Buffer; Size: Int64): Int64;

    { *
      * Reads raw binary data from the current position into a buffer.
      * The position is advanced by the number of bytes read.
      * @param Buffer – Destination variable (passed by reference).
      * @param Size – Maximum bytes to read.
      * @return The number of bytes actually read (may be less than Size if
      *         the end of the buffer is reached).
    }
    function ReadBuffer(var Buffer; Size: Int64): Int64;

    // ---- Fluent write methods (all return Self for chaining) ----

    function WriteInt8(Value: Int8): TDataHandle;       // Writes a signed 8‑bit integer (little‑endian)
    function WriteUInt8(Value: UInt8): TDataHandle;     // Writes an unsigned 8‑bit integer
    function WriteInt16(Value: Int16): TDataHandle;     // Writes a signed 16‑bit integer
    function WriteUInt16(Value: UInt16): TDataHandle;   // Writes an unsigned 16‑bit integer
    function WriteInt32(Value: Int32): TDataHandle;     // Writes a signed 32‑bit integer
    function WriteUInt32(Value: UInt32): TDataHandle;   // Writes an unsigned 32‑bit integer
    function WriteInt64(Value: Int64): TDataHandle;     // Writes a signed 64‑bit integer
    function WriteUInt64(Value: UInt64): TDataHandle;   // Writes an unsigned 64‑bit integer
    function WriteSingle(Value: Single): TDataHandle;   // Writes a 32‑bit IEEE 754 float
    function WriteDouble(Value: Double): TDataHandle;   // Writes a 64‑bit IEEE 754 float

    { *
      * Writes a UTF‑8 string with a 32‑bit length prefix.
      * Format: [Int32 length] + [UTF‑8 bytes].
      * @param Value – The string to encode and write.
      * @return Self for chaining.
      * @Example:
      *   D.WriteString('Hello, world!'); // writes length then bytes
    }
    function WriteString(const Value: string): TDataHandle;

    // ---- Read methods (return Boolean indicating success) ----

    function ReadInt8(out Value: Int8): Boolean;       // Reads a signed 8‑bit integer
    function ReadUInt8(out Value: UInt8): Boolean;     // Reads an unsigned 8‑bit integer
    function ReadInt16(out Value: Int16): Boolean;     // Reads a signed 16‑bit integer
    function ReadUInt16(out Value: UInt16): Boolean;   // Reads an unsigned 16‑bit integer
    function ReadInt32(out Value: Int32): Boolean;     // Reads a signed 32‑bit integer
    function ReadUInt32(out Value: UInt32): Boolean;   // Reads an unsigned 32‑bit integer
    function ReadInt64(out Value: Int64): Boolean;     // Reads a signed 64‑bit integer
    function ReadUInt64(out Value: UInt64): Boolean;   // Reads an unsigned 64‑bit integer
    function ReadSingle(out Value: Single): Boolean;   // Reads a 32‑bit float
    function ReadDouble(out Value: Double): Boolean;   // Reads a 64‑bit float

    { *
      * Reads a UTF‑8 string with a 32‑bit length prefix.
      * @param Value – Output string (decoded from UTF‑8).
      * @return True if the entire length‑prefixed string was successfully read;
      *         False otherwise (in which case Value is set to empty string).
    }
    function ReadString(out Value: string): Boolean;

    // ---- Position and size management ----

    { * Returns the current read/write position (byte offset from the start). }
    function GetPos: Int64;

    { *
      * Sets the current read/write position.
      * If Pos_ exceeds the current size, the buffer is extended with zero bytes.
    }
    procedure SetPos(Pos_: Int64);
    property Pos: Int64 read GetPos write SetPos;

    { * Returns the total size of the payload (in bytes). }
    function GetSize: Int64;

    { *
      * Resizes the internal buffer. If the new size is smaller, data is truncated.
      * If larger, new space is uninitialised.
    }
    procedure SetSize(Size_: Int64);
    property Size: Int64 read GetSize write SetSize;

    { *
      * Returns a direct pointer to the internal buffer (zero‑copy access).
      * The pointer is valid until the handle is freed or resized.
      * Do not free this pointer yourself.
    }
    function GetBuffer: Pointer;
    property Buffer: Pointer read GetBuffer;

    { * Returns the raw native handle (TDataHnd). }
    property Handle: TDataHnd read FHandle;
  end;

  { *
    * TAppHandle – RAII wrapper for an application handle (TAppHnd).
    *
    * An application is a logical container that groups a set of APIs under a
    * unique name. It is used to register callbacks that can be invoked locally
    * or remotely via the network. The handle is automatically freed when the
    * object is destroyed.
    *
    * In addition to registration, this class supports dynamic unregistration
    * of individual APIs. When an API is unregistered, a network broadcast
    * is triggered; remote peers will stop seeing the API after approximately
    * 3 seconds (depending on network conditions).
    *
    * @Example:
    *   var
    *     App: TAppHandle;
    *   begin
    *     App := TAppHandle.Create('MyService', 'Example service');
    *     if App.RegisterCall('add', 'adds two ints', nil, @AddCallback) then
    *       WriteLn('Registered add');
    *     // ... later, if we want to remove the API:
    *     if App.Unregister('add') then
    *       WriteLn('Unregistered add (broadcast in progress)');
    *     // ...
    *     App.Free;   // automatically calls API_Free_APPHnd
    *   end;
  }
  TAppHandle = class
  private
    FHandle: TAppHnd;   // Raw application handle
    FName: string;      // Application name (for reference)
  public
    { *
      * Creates a new application context.
      * @param AppName – Unique application name (UTF‑8, case‑sensitive).
      * @param Desc – Human‑readable description (UTF‑8, may be empty).
      * @raises Exception if the native creation fails.
    }
    constructor Create(const AppName, Desc: string);

    { * Destructor: frees the application handle and all registered APIs. }
    destructor Destroy; override;

    { *
      * Registers a request‑response (Call) API.
      * @param APIName – Unique API name within this app (UTF‑8).
      * @param Desc – Optional description (UTF‑8).
      * @param Trigger – User data that will be passed to the callback.
      * @param OnCall – cdecl callback function that implements the API.
      * @return True if registration succeeded, False if the API name already exists.
    }
    function RegisterCall(const APIName, Desc: string; Trigger: Pointer; OnCall: TAPI_Call): Boolean;

    { *
      * Registers a one‑way notification (Notify) API.
      * @param APIName – Unique API name.
      * @param Desc – Optional description.
      * @param Trigger – User data for the callback.
      * @param OnNotify – cdecl notification handler.
      * @return True if registration succeeded.
    }
    function RegisterNotify(const APIName, Desc: string; Trigger: Pointer; OnNotify: TAPI_Notify): Boolean;

    { *
      * Unregisters a previously registered API from this application.
      * The API is immediately removed from the local registry and a network
      * broadcast is triggered. Remote peers will stop seeing this API within
      * approximately 3 seconds (depending on network latency and the C4
      * update interval). During that short window, remote calls may still
      * be attempted; they will fail gracefully (the remote side will receive
      * a "not found" error).
      * @param APIName – The name of the API to unregister (UTF‑8).
      * @return True if the API was found and unregistered, False otherwise.
      * @SeeAlso RegisterCall, RegisterNotify
    }
    function Unregister(const APIName: string): Boolean;

    { *
      * Synchronously invokes a Call API locally (bypassing the network).
      * @param Param – Input data handle (must contain the API name and payload).
      * @return A new TDataHandle containing the result (caller must free it).
      * @raises Exception if the underlying call fails.
    }
    function LocalCall(Param: TDataHandle): TDataHandle;

    { *
      * Sends a notification locally (no response).
      * @param Param – Input data handle.
    }
    procedure LocalNotify(Param: TDataHandle);

    { * Returns the raw application handle. }
    property Handle: TAppHnd read FHandle;
    { * Returns the application name. }
    property Name: string read FName;
  end;

{------------------- Global network functions (safe wrappers) -------------------}

{ *
  * Clears all previously prepared services and clients.
  * Call this before preparing a new set of services/clients.
}
procedure ResetPrepare;

{ *
  * Adds a service (listener) to the preparation list.
  * @param ListeningAddr – Local address to bind (e.g., "0.0.0.0:9898" or "ipc:test").
  * @param PhysicsAddr – Public address advertised to clients.
  * @return A service tag (informational, may be ignored).
}
function PrepareService(const ListeningAddr, PhysicsAddr: string): Integer; overload;

{ *
  * Adds a service (listener) to the preparation list.
  * @param ListeningAddr – Local address to bind (e.g., "0.0.0.0:9898" or "ipc:test").
  * @param PhysicsAddr – Public address advertised to clients.
  * @param App – Optional application handle to expose (may be nil).
  * @return A service tag (informational, may be ignored).
}
function PrepareService(const ListeningAddr, PhysicsAddr: string; App: TAppHandle): Integer; overload;

{ *
  * Adds a client connection to the preparation list.
  * @param PhysicsAddr – Address of the remote service.
  * @param App – Optional application handle to expose (may be nil).
  * @return A client tag.
}
function PrepareClient(const PhysicsAddr: string; App: TAppHandle): Integer;

{ *
  * Starts the network framework with all prepared services/clients.
  * @return True on success, False on failure (check console output for errors).
}
function PrepareDone: Boolean;

{ * Signals the internal main thread to exit gracefully. }
procedure ExitMainThread;

{ *
  * Performs a remote (or local) synchronous call.
  * @param AppName – Target application name.
  * @param Param – Input data handle (cloned internally; caller must still free it).
  * @param TimeoutMs – Maximum wait in milliseconds (0 = infinite).
  * @return A new TDataHandle containing the result (caller must free it).
  *         The handle is never nil; if the call times out or fails, its size will be 0.
  * @raises Exception if the native call returns nil (should never happen per spec).
}
function CallApp(const AppName: string; Param: TDataHandle; TimeoutMs: UInt64): TDataHandle;

{ *
  * Sends a one‑way notification (fire‑and‑forget).
  * @param AppName – Target application name.
  * @param Param – Input data handle (cloned internally; caller still must free it).
}
procedure NotifyApp(const AppName: string; Param: TDataHandle);

{ *
  * Dynamically adjusts global runtime options of the API Hub framework.
  * All changes take effect immediately for subsequent operations.
  * This is a direct wrapper around the low‑level API_SetOption.
  *
  * Supported Option keys (case‑insensitive, aliases accepted):
  *   - "password" / "passwd" : Sets the C4 P2PVM authentication token.
  *     **Must match on both service and client sides** for successful handshake.
  *   - "Quiet" : Enable/disable quiet mode (True/False).
  *   - "External_Conf_Auto_Save" / "Conf_Auto_Save" : Auto‑save .ini on exit (True/False).
  *   - "Wait_Connection_ReadyOk" / "Wait_API_Prepare_Done" / ... :
  *     Control whether API_Prepare_Done blocks until all clients are connected.
  *     When False, clients auto‑connect later (important for deployment).
  *   - "Wait_Connection_Timeout" / "Wait_TimeOut" : Max wait (ms) when the above is True.
  *   - "ShowThreadID" / "ShowThread" / "Show_Thread" : Show thread IDs in logs.
  *   - "ConsoleOutput" / "Console_Output" : Enable/disable console logging.
  *   - "IPC_Serv_ThreadCount" / "IPC_ThreadCount" / "IPC_Server_ThreadCount" :
  *     Number of threads in the IPC service thread pool.
  *   - "IPC_Serv_MaxQueueLength" / "IPC_MaxQueueLength" / "IPC_Server_MaxQueueLength" :
  *     Maximum IPC message queue length.
  *   - "IPC_Serv_MaxMsgSize" / "IPC_MaxMsgSize" / "IPC_Server_MaxMsgSize" :
  *     Maximum IPC message size (bytes).
  *
  * @param Option – Configuration key (UTF‑8).
  * @param Value – New value (UTF‑8). For boolean, accepts "True"/"False", "1"/"0", "Yes"/"No".
  * @Note Unknown options are silently ignored. This function has no return value.
  * @SeeAlso API_SetOption in z_api_hubtool_import for detailed semantics.
}
procedure SetOption(const Option, Value: string);

{ *
  * Gracefully shuts down the entire API Hub framework.
  * Releases all resources; after this, you may re‑initialise.
}
procedure Shutdown;

implementation

{------------------------- TDataHandle --------------------------------------}

constructor TDataHandle.Create(const APIName: string);
{
  * Creates a new native data handle by calling the low‑level API.
  * Converts the Pascal string to a null‑terminated UTF‑8 string.
  * Raises an exception if the native handle is nil.
}
begin
  inherited Create;
  FHandle := API_Create_DataHnd(PAnsiChar(Utf8String(APIName)));
  if FHandle = nil then
    raise Exception.Create('TDataHandle.Create: API_Create_DataHnd failed');
  FOwned := True;  // we own the newly created handle
end;

constructor TDataHandle.Create(AHandle: TDataHnd; Owned: Boolean);
{
  * Wraps an existing native handle. The Owned flag determines whether the
  * destructor will free the handle. This is useful for wrapping borrowed
  * handles (e.g., from callbacks) without taking ownership.
}
begin
  inherited Create;
  FHandle := AHandle;
  FOwned := Owned;
end;

destructor TDataHandle.Destroy;
{
  * If we own the handle and it is non‑nil, free it using API_Free_DataHnd.
}
begin
  if FOwned and (FHandle <> nil) then
    API_Free_DataHnd(FHandle);
  inherited;
end;

function TDataHandle.WriteBuffer(const Buffer; Size: Int64): Int64;
{
  * Passes the address of the buffer and its size to the low‑level write function.
  * The buffer is passed by reference (const) so we take its address with @.
}
begin
  Result := API_WriteBuffer(FHandle, @Buffer, Size);
end;

function TDataHandle.ReadBuffer(var Buffer; Size: Int64): Int64;
{
  * Reads data from the current position into the caller's variable.
  * The variable is passed by reference, so we can modify it directly.
}
begin
  Result := API_ReadBuffer(FHandle, @Buffer, Size);
end;

// ---------- Fluent write methods ----------
// Each method writes a value of a specific type and returns Self for chaining.

function TDataHandle.WriteInt8(Value: Int8): TDataHandle;
begin
  WriteBuffer(Value, SizeOf(Value));
  Result := Self;
end;

function TDataHandle.WriteUInt8(Value: UInt8): TDataHandle;
begin
  WriteBuffer(Value, SizeOf(Value));
  Result := Self;
end;

function TDataHandle.WriteInt16(Value: Int16): TDataHandle;
begin
  WriteBuffer(Value, SizeOf(Value));
  Result := Self;
end;

function TDataHandle.WriteUInt16(Value: UInt16): TDataHandle;
begin
  WriteBuffer(Value, SizeOf(Value));
  Result := Self;
end;

function TDataHandle.WriteInt32(Value: Int32): TDataHandle;
begin
  WriteBuffer(Value, SizeOf(Value));
  Result := Self;
end;

function TDataHandle.WriteUInt32(Value: UInt32): TDataHandle;
begin
  WriteBuffer(Value, SizeOf(Value));
  Result := Self;
end;

function TDataHandle.WriteInt64(Value: Int64): TDataHandle;
begin
  WriteBuffer(Value, SizeOf(Value));
  Result := Self;
end;

function TDataHandle.WriteUInt64(Value: UInt64): TDataHandle;
begin
  WriteBuffer(Value, SizeOf(Value));
  Result := Self;
end;

function TDataHandle.WriteSingle(Value: Single): TDataHandle;
begin
  WriteBuffer(Value, SizeOf(Value));
  Result := Self;
end;

function TDataHandle.WriteDouble(Value: Double): TDataHandle;
begin
  WriteBuffer(Value, SizeOf(Value));
  Result := Self;
end;

function TDataHandle.WriteString(const Value: string): TDataHandle;
{
  * Encodes the Pascal string as UTF‑8, writes a 32‑bit length prefix,
  * then writes the raw bytes. The length prefix allows the receiver to
  * know how many bytes to read.
}
var
  Utf8: UTF8String;
  Len: Int32;
begin
  Utf8 := UTF8Encode(Value);          // Convert to UTF‑8 bytes
  Len := Length(Utf8);                // Length in bytes
  WriteInt32(Len);                    // Write length prefix (4 bytes)
  if Len > 0 then
    API_WriteBuffer(FHandle, PByte(Utf8), Len);   // Write the bytes
  Result := Self;
end;

// ---------- Read methods ----------
// Each method attempts to read a value of a specific type.
// Returns True if the required number of bytes were successfully read.

function TDataHandle.ReadInt8(out Value: Int8): Boolean;
begin
  Result := ReadBuffer(Value, SizeOf(Value)) = SizeOf(Value);
end;

function TDataHandle.ReadUInt8(out Value: UInt8): Boolean;
begin
  Result := ReadBuffer(Value, SizeOf(Value)) = SizeOf(Value);
end;

function TDataHandle.ReadInt16(out Value: Int16): Boolean;
begin
  Result := ReadBuffer(Value, SizeOf(Value)) = SizeOf(Value);
end;

function TDataHandle.ReadUInt16(out Value: UInt16): Boolean;
begin
  Result := ReadBuffer(Value, SizeOf(Value)) = SizeOf(Value);
end;

function TDataHandle.ReadInt32(out Value: Int32): Boolean;
begin
  Result := ReadBuffer(Value, SizeOf(Value)) = SizeOf(Value);
end;

function TDataHandle.ReadUInt32(out Value: UInt32): Boolean;
begin
  Result := ReadBuffer(Value, SizeOf(Value)) = SizeOf(Value);
end;

function TDataHandle.ReadInt64(out Value: Int64): Boolean;
begin
  Result := ReadBuffer(Value, SizeOf(Value)) = SizeOf(Value);
end;

function TDataHandle.ReadUInt64(out Value: UInt64): Boolean;
begin
  Result := ReadBuffer(Value, SizeOf(Value)) = SizeOf(Value);
end;

function TDataHandle.ReadSingle(out Value: Single): Boolean;
begin
  Result := ReadBuffer(Value, SizeOf(Value)) = SizeOf(Value);
end;

function TDataHandle.ReadDouble(out Value: Double): Boolean;
begin
  Result := ReadBuffer(Value, SizeOf(Value)) = SizeOf(Value);
end;

function TDataHandle.ReadString(out Value: string): Boolean;
{
  * Reads a 32‑bit length prefix, then reads that many bytes as UTF‑8 and
  * decodes them to a Pascal string. If reading the length fails or the
  * byte count cannot be fully read, the function returns False.
}
var
  Len: Int32;
  Utf8: UTF8String;
begin
  Result := ReadInt32(Len);          // Try to read length
  if not Result then
    Exit;
  SetLength(Utf8, Len);
  if Len > 0 then
    Result := ReadBuffer(Utf8[1], Len) = Len;   // Read the bytes
  if Result then
    Value := UTF8Decode(Utf8)
  else
    Value := '';
end;

// ---------- Position and size ----------

function TDataHandle.GetPos: Int64;
{
  * Returns the current read/write position by calling the low‑level function.
}
begin
  Result := API_GetPos(FHandle);
end;

procedure TDataHandle.SetPos(Pos_: Int64);
{
  * Sets the current position. If the new position is beyond the end of the
  * buffer, the buffer is extended with zero bytes.
}
begin
  API_SetPos(FHandle, Pos_);
end;

function TDataHandle.GetSize: Int64;
{
  * Returns the total size of the payload in bytes.
}
begin
  Result := API_GetSize(FHandle);
end;

procedure TDataHandle.SetSize(Size_: Int64);
{
  * Resizes the internal buffer. If the new size is smaller, data is truncated;
  * if larger, new space is uninitialised.
}
begin
  API_SetSize(FHandle, Size_);
end;

function TDataHandle.GetBuffer: Pointer;
{
  * Returns a direct pointer to the internal buffer. The pointer is valid until
  * the handle is freed or the buffer is resized. Do not free this pointer.
}
begin
  Result := API_GetBuffer(FHandle);
end;

{------------------------- TAppHandle ----------------------------------------}

constructor TAppHandle.Create(const AppName, Desc: string);
{
  * Creates an application handle by calling the low‑level API.
  * Both strings are converted to UTF‑8 before being passed to the C function.
}
begin
  FHandle := API_Create_APPHnd(PAnsiChar(Utf8String(AppName)),
    PAnsiChar(Utf8String(Desc)));
  if FHandle = nil then
    raise Exception.Create('TAppHandle.Create: API_Create_APPHnd failed');
  FName := AppName;
end;

destructor TAppHandle.Destroy;
{
  * Frees the application handle using API_Free_APPHnd.
}
begin
  if FHandle <> nil then
    API_Free_APPHnd(FHandle);
  inherited;
end;

function TAppHandle.RegisterCall(const APIName, Desc: string; Trigger: Pointer; OnCall: TAPI_Call): Boolean;
{
  * Registers a Call API by converting the Pascal strings to UTF‑8 and
  * invoking the low‑level registration function. Returns True if the
  * registration succeeded (i.e., the API name was unique).
}
begin
  Result := API_Reg_Call(FHandle,
    PAnsiChar(Utf8String(APIName)),
    PAnsiChar(Utf8String(Desc)),
    Trigger,
    OnCall) = 1;
end;

function TAppHandle.RegisterNotify(const APIName, Desc: string; Trigger: Pointer; OnNotify: TAPI_Notify): Boolean;
{
  * Registers a Notify API similarly.
}
begin
  Result := API_Reg_Notify(FHandle,
    PAnsiChar(Utf8String(APIName)),
    PAnsiChar(Utf8String(Desc)),
    Trigger,
    OnNotify) = 1;
end;

function TAppHandle.Unregister(const APIName: string): Boolean;
{
  * Unregisters an API using the low‑level API_UnReg.
  * Returns True if the API existed and was removed.
  * A network broadcast is triggered asynchronously.
}
begin
  Result := API_UnReg(FHandle, PAnsiChar(Utf8String(APIName))) = 1;
end;

function TAppHandle.LocalCall(Param: TDataHandle): TDataHandle;
{
  * Invokes the local call, which executes the callback synchronously in the
  * caller's thread. Returns a new owned data handle containing the result.
  * The caller is responsible for freeing it.
}
var
  Res: TDataHnd;
begin
  Res := API_Local_APP_Call(FHandle, Param.Handle);
  if Res = nil then
    raise Exception.Create('TAppHandle.LocalCall: API_Local_APP_Call failed');
  Result := TDataHandle.Create(Res, True);  // Create owned wrapper
end;

procedure TAppHandle.LocalNotify(Param: TDataHandle);
{
  * Sends a notification locally. No result is returned.
}
begin
  API_Local_APP_Notify(FHandle, Param.Handle);
end;

{------------------- Global network functions -------------------------------}

procedure ResetPrepare;
{
  * Calls the low‑level API_Reset_Prepare to clear all prepared services/clients.
}
begin
  API_Reset_Prepare;
end;

function PrepareService(const ListeningAddr, PhysicsAddr: string): Integer;
{
  * Converts addresses to UTF‑8 and calls API_Prepare_Service.
}
begin
  Result := API_Prepare_Service(PAnsiChar(Utf8String(ListeningAddr)),
    PAnsiChar(Utf8String(PhysicsAddr)));
end;

function PrepareClient(const PhysicsAddr: string; App: TAppHandle): Integer;
{
  * Converts the address and extracts the raw application handle (if any)
  * before calling API_Prepare_Client.
}
var
  AppPtr: TAppHnd;
begin
  if Assigned(App) then
    AppPtr := App.Handle
  else
    AppPtr := nil;
  Result := API_Prepare_Client(PAnsiChar(Utf8String(PhysicsAddr)), AppPtr);
end;

function PrepareService(const ListeningAddr, PhysicsAddr: string; App: TAppHandle): Integer; overload;
{
  * Converts addresses to UTF‑8 and calls API_Prepare_Service.
  * Converts the address and extracts the raw application handle (if any)
  * before calling API_Prepare_Client.
}
begin
  Result := API_Prepare_Service(PAnsiChar(Utf8String(ListeningAddr)),
    PAnsiChar(Utf8String(PhysicsAddr)));

  PrepareClient(PAnsiChar(Utf8String(PhysicsAddr)), App);
end;

function PrepareDone: Boolean;
{
  * Calls API_Prepare_Done and returns True if the return value equals 1.
}
begin
  Result := API_Prepare_Done = 1;
end;

procedure ExitMainThread;
{
  * Calls API_Exit_MainThread to signal the internal event loop to stop.
}
begin
  API_Exit_MainThread;
end;

function CallApp(const AppName: string; Param: TDataHandle; TimeoutMs: UInt64): TDataHandle;
{
  * Converts AppName to UTF‑8, calls API_Call, and wraps the result in a new
  * TDataHandle with ownership (True). The caller must free the returned handle.
  * Raises an exception only if the native call returns nil (should not happen).
}
var
  Res: TDataHnd;
begin
  Res := API_Call(PAnsiChar(Utf8String(AppName)), Param.Handle, TimeoutMs);
  if Res = nil then
    raise Exception.Create('CallApp: API_Call returned nil (should not happen)');
  Result := TDataHandle.Create(Res, True);
end;

procedure NotifyApp(const AppName: string; Param: TDataHandle);
{
  * Converts AppName to UTF‑8 and calls API_Notify.
}
begin
  API_Notify(PAnsiChar(Utf8String(AppName)), Param.Handle);
end;

procedure SetOption(const Option, Value: string);
{
  * Wrapper for API_SetOption – converts strings to UTF‑8 and forwards.
  * See the interface comment for a full list of supported options.
}
begin
  API_SetOption(PAnsiChar(Utf8String(Option)), PAnsiChar(Utf8String(Value)));
end;

procedure Shutdown;
{
  * Calls API_shutdown to gracefully shut down the entire framework.
}
begin
  API_shutdown;
end;

end.

