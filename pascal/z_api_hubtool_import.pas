(*
2026-08-17 11:02
update by.精灵 qq289161766
unit z_api_hubtool_import 修改一处编译开关（第229行）：

{$IFDEF MSWINDOWS}
const
  {$IF Defined(CPU64) or Defined(CPUX64)}
    libapi_hub = 'z_api_hub64.dll';   // 64‑bit Windows
  {$ELSE}
    libapi_hub = 'z_api_hub32.dll';   // 32‑bit Windows
  {$ENDIF}
{$ELSE}
  {$IFDEF DARWIN}
    const
      libapi_hub = 'libz_api_hub.dylib';   // macOS
  {$ELSE}
    // Linux, BSD, and other ELF‑based systems
    const
      libapi_hub = 'libz_api_hub.so';
  {$ENDIF}
{$ENDIF}
*)
{*******************************************************************************
  ██████  ██████  ██    ██  █████  ██████  ██ ██   ██
  ██   ██ ██   ██ ██    ██ ██   ██ ██   ██ ██ ██   ██
  ██████  ██████  ██    ██ ███████ ██████  ██ ███████
  ██   ██ ██   ██ ██    ██ ██   ██ ██   ██ ██ ██   ██
  ██   ██ ██   ██  ██████  ██   ██ ██   ██ ██ ██   ██

  z_api_hubtool_import – Core Pascal Binding (Master Reference)

  ═══════════════════════════════════════════════════════════════════════════════
  Purpose
  ═══════════════════════════════════════════════════════════════════════════════
  This unit provides Pascal bindings to the API Hub dynamic library
  (z_api_hub64.dll / .so / .dylib). It serves as the "master reference" for
  all other language bindings (C++, Python, Go, Java, Rust, C#, etc.) –
  every binding adheres to the semantics defined here.

  With this unit you can:
    • Expose any Pascal function as a cross‑language remote API (Call or Notify)
    • Transparently call services written in C++/Python/Go/Java/Rust/C#/Node.js
    • Perform high‑performance RPC within a process, between processes (IPC),
      or across machines (TCP)
    • Leverage automatic service discovery, load balancing, reconnection,
      and NAT traversal

  ═══════════════════════════════════════════════════════════════════════════════
  Design Philosophy – "Define Once, Use Everywhere"
  ═══════════════════════════════════════════════════════════════════════════════
  All language bindings share exactly the same C ABI and binary data format.
  Thus, an API registered in Pascal can be called from Python, and a Rust
  service can be consumed by C#. There is no "first‑class" vs "second‑class"
  language – all are equal.

  This unit is the contract; any implementation that follows this contract
  is fully interoperable.

  ═══════════════════════════════════════════════════════════════════════════════
  Core Concepts (Must Read)
  ═══════════════════════════════════════════════════════════════════════════════
  • TDataHnd   : Data handle – a container holding an API name and a binary
                 payload. Used for input parameters and output results.
                 Must be explicitly created and freed.
  • TAppHnd    : Application handle – represents a logical application that
                 can register multiple APIs. The application name must be
                 unique across the network (case‑sensitive).
  • Call       : Request‑response mode. The client blocks until the server
                 returns a result.
  • Notify     : One‑way notification mode. The client sends and returns
                 immediately without waiting for a response.
  • Callback   : A TAPI_Call / TAPI_Notify function registered by the server,
                 invoked by the library in background thread‑pool threads.

  ═══════════════════════════════════════════════════════════════════════════════
  Threading Model & Callback Constraints (⚠️ CRITICAL)
  ═══════════════════════════════════════════════════════════════════════════════
  1. All exported functions (except a few deprecated logging functions) are
     **fully thread‑safe** and may be called concurrently from any number of
     threads.

  2. Callbacks (TAPI_Call / TAPI_Notify) are executed in the library's
     internal thread pool.
     ⚠️ Therefore, inside a callback you MUST:
        • NOT perform long‑blocking operations (Sleep, waiting on events,
          heavy loops, etc.)
        • NOT call API_Call or API_Notify – this will cause deadlocks
        • NOT directly access UI components (use TThread.Synchronize or
          other synchronization)
        • Offload heavy work or remote calls to separate worker threads
          and return quickly

  3. Execution order: concurrent calls may be load‑balanced to different
     instances – order is not guaranteed. If you need strict ordering,
     implement your own coordination (e.g., sequence numbers or single‑thread
     dispatching).

  ═══════════════════════════════════════════════════════════════════════════════
  String Encoding – UTF‑8 is Mandatory
  ═══════════════════════════════════════════════════════════════════════════════
  All PAnsiChar parameters (API names, descriptions, network addresses, etc.)
  MUST be UTF‑8 encoded and null‑terminated (ending with #0).
  Do NOT use the system ANSI code page (e.g., CP_ACP on Windows). This library
  always processes byte streams as UTF‑8, regardless of platform.

  In Delphi, use UTF8String or convert with UTF8Encode before passing.

  ═══════════════════════════════════════════════════════════════════════════════
  Typical Usage Flow
  ═══════════════════════════════════════════════════════════════════════════════
  1. Create an application handle (API_Create_APPHnd)
  2. Register API callbacks (API_Reg_Call / API_Reg_Notify)
  3. Prepare the network (API_Reset_Prepare → API_Prepare_Service /
     API_Prepare_Client)
  4. Start the framework (API_Prepare_Done) – blocks until ready
  5. During runtime, call remote APIs (API_Call / API_Notify)
  6. On exit: API_Exit_MainThread → API_shutdown (or rely on finalization)

  ═══════════════════════════════════════════════════════════════════════════════
  Resource Management – Handle Lifecycle
  ═══════════════════════════════════════════════════════════════════════════════
  • Every TDataHnd created with API_Create_DataHnd MUST be freed with
    API_Free_DataHnd.
  • Every TAppHnd created with API_Create_APPHnd MUST be freed with
    API_Free_APPHnd.
  • The TDataHnd returned by API_Call is never nil, but its size may be 0
    on timeout/failure – you MUST still free it.
  • The Input/Output handles passed to callbacks are managed by the library;
    do NOT free them inside the callback.

  ═══════════════════════════════════════════════════════════════════════════════
  Configuration File
  ═══════════════════════════════════════════════════════════════════════════════
  On first run, the library creates <executable>.api-tool.ini. You can adjust
  thread pool size, timeouts, logging behaviour, etc. without recompiling.

  ═══════════════════════════════════════════════════════════════════════════════
  Error Diagnosis
  ═══════════════════════════════════════════════════════════════════════════════
  The library prints detailed logs (connection status, registration info,
  error causes) to stdout/stderr. Logging verbosity can be controlled via the
  .ini file.

  ═══════════════════════════════════════════════════════════════════════════════
  License
  ═══════════════════════════════════════════════════════════════════════════════
  MIT License – free to use, modify, and distribute, including commercial use.

  ═══════════════════════════════════════════════════════════════════════════════
  This file is the "Absolute Correct Core" – all other language bindings
  are derived from it. Any AI or human developer reading this file will
  fully understand the semantics and constraints of the API Hub framework.
  ═══════════════════════════════════════════════════════════════════════════════
*******************************************************************************}

unit z_api_hubtool_import;

{$ifdef FPC}
  {$mode delphi}{$H+}
  {$CODEPAGE UTF8}
{$endif}

{$R-}

interface

uses SysUtils;

{===============================================================================
  1. Type Definitions
===============================================================================}

type
  {****************************************************************************
    TDataHnd
    Opaque pointer to an internal binary buffer.
    Purpose: carries an API name + payload data for input and output.
    Create: API_Create_DataHnd
    Free:   API_Free_DataHnd
    Thread safety:
      - Read operations (API_GetBuffer, API_GetPos, API_GetSize) are safe
        as long as the handle is not being written concurrently.
      - Write operations (API_WriteBuffer, API_SetPos, API_SetSize) must be
        serialized for the same handle.
      - Different handles can be used concurrently without restriction.
  ****************************************************************************}
  TDataHnd = Pointer;

  {****************************************************************************
    TAppHnd
    Opaque pointer to an application context.
    An application groups a set of APIs under a unique name (case‑sensitive).
    Clients route requests by "application name + API name".
    Create: API_Create_APPHnd
    Free:   API_Free_APPHnd
    Thread safe: the handle itself is thread‑safe; registration and local
    calls can be performed concurrently from multiple threads.
  ****************************************************************************}
  TAppHnd = Pointer;

  {****************************************************************************
    TAPI_Call
    Callback type for request‑response (Call) APIs.
    Parameters:
      Trigger : user pointer supplied at registration, passed back as‑is.
      Input   : TDataHnd containing the serialized request (read‑only, do not free).
      Output  : TDataHnd for writing the response (write‑only, do not free).
    Calling convention: cdecl.
    Execution context: background thread‑pool thread (not the main thread).
    ⚠️ WARNINGS:
      • Do NOT call API_Call or API_Notify inside this callback (deadlock risk).
      • Do NOT perform long‑blocking operations (Sleep, waiting, heavy loops).
      • Do NOT directly access UI components (must synchronize to main thread).
      • Offload heavy tasks to separate worker threads and return quickly.
    Example:
      procedure MyAdd(Trigger: Pointer; Input, Output: Pointer); cdecl;
      var
        a, b, sum: Integer;
      begin
        API_ReadBuffer(Input, @a, SizeOf(a));
        API_ReadBuffer(Input, @b, SizeOf(b));
        sum := a + b;
        API_WriteBuffer(Output, @sum, SizeOf(sum));
      end;
  ****************************************************************************}
  TAPI_Call = procedure(Trigger: Pointer; Input: Pointer; Output: TDataHnd); cdecl;

  {****************************************************************************
    TAPI_Notify
    Callback type for one‑way notification (Notify) APIs.
    Parameters:
      Trigger : user pointer supplied at registration.
      Input   : TDataHnd containing the notification payload (read‑only, do not free).
    No output, no return value.
    Calling convention: cdecl.
    Execution context: background thread‑pool thread.
    ⚠️ Same warnings as TAPI_Call: do NOT call API_Call/API_Notify, do NOT block.
    Example:
      procedure MyLogger(Trigger: Pointer; Input: Pointer); cdecl;
      var
        msg: PAnsiChar;
      begin
        msg := API_GetBuffer(Input);
        WriteLn('Notify: ', msg);
      end;
  ****************************************************************************}
  TAPI_Notify = procedure(Trigger: Pointer; Input: TDataHnd); cdecl;

{===============================================================================
  2. Dynamic Library Name (Platform Adaptive)
===============================================================================}

{$IFDEF MSWINDOWS}
const
  {$IF Defined(CPU64) or Defined(CPUX64)}
    libapi_hub = 'z_api_hub64.dll';   // 64-bit Windows
  {$ELSE}
  libapi_hub = 'z_api_hub32.dll';   // 32-bit Windows
  {$ENDIF}
{$ELSE}
  {$IFDEF DARWIN}
    const
      libapi_hub = 'libz_api_hub.dylib';   // macOS
  {$ELSE}
    // Linux, BSD, and other ELF‑based systems
    const
      libapi_hub = 'libz_api_hub.so';
  {$ENDIF}
{$ENDIF}

{===============================================================================
  3. Data Handle Operations
===============================================================================}

  {****************************************************************************
    3.1 API_Create_DataHnd
    Creates a data handle associated with the given API name.
    Parameters:
      APIName : UTF‑8 encoded API name (null‑terminated).
    Returns:
      New TDataHnd. Never returns nil under normal conditions.
    Notes:
      • The API name is copied internally; you may free the input string
        immediately after the call.
      • The initial payload is empty (size = 0).
      • Must be freed with API_Free_DataHnd.
    Thread safe: Yes.
    Example:
      var d: TDataHnd;
      begin
        d := API_Create_DataHnd('add');
        API_WriteBuffer(d, @a, SizeOf(a));
        ...
        API_Free_DataHnd(d);
      end;
  ****************************************************************************}
function API_Create_DataHnd(APIName: pansichar): TDataHnd; cdecl; external libapi_hub name 'API_Create_DataHnd';
function API_Create_DataHnd2(APIName: string): TDataHnd;   // convenience overload, auto UTF‑8

  {****************************************************************************
    3.2 API_Free_DataHnd
    Destroys a data handle and releases all associated memory.
    Parameters:
      Hnd : handle to free (passing nil is harmless).
    Thread safe: Yes, but the handle must not be used after being freed.
  ****************************************************************************}
procedure API_Free_DataHnd(Hnd: TDataHnd); cdecl; external libapi_hub name 'API_Free_DataHnd';

  {****************************************************************************
    3.3 API_GetBuffer
    Returns a direct pointer to the internal buffer (zero‑copy access).
    Parameters:
      Hnd : data handle.
    Returns:
      Pointer to the internal buffer, or nil if the handle has no data.
    Notes:
      • The pointer is valid until the handle is freed or the buffer is resized.
      • You may read and write, but must NOT exceed the size returned by
        API_GetSize.
      • Do NOT free this pointer.
    Thread safe: read‑only access is safe; concurrent writes must be serialized.
    Example:
      var p: PByte; sz: Int64;
      begin
        sz := API_GetSize(h);
        p := API_GetBuffer(h);
        // process p[0..sz-1]
      end;
  ****************************************************************************}
function API_GetBuffer(Hnd: TDataHnd): Pointer; cdecl; external libapi_hub name 'API_GetBuffer';
function API_GetBuffer2(Hnd: TDataHnd; Offset: nativeint): Pointer;   // returns pointer with offset

  {****************************************************************************
    3.4 API_WriteBuffer
    Writes binary data into the handle's buffer at the current position.
    The position advances, and the buffer is automatically enlarged if needed.
    Parameters:
      Hnd  : data handle.
      Buff : source data pointer.
      Size : number of bytes to write.
    Returns:
      Number of bytes actually written (normally equals Size).
    Thread safe: write operations on the same handle must be serialized;
      different handles can be written concurrently.
    Example:
      var i: Integer;
      begin
        i := 12345;
        API_WriteBuffer(d, @i, SizeOf(i));
      end;
  ****************************************************************************}
function API_WriteBuffer(Hnd: TDataHnd; Buff: Pointer; Size: int64): int64; cdecl; external libapi_hub name 'API_WriteBuffer';

// ========================== ATOMIC WRITE HELPERS ==========================
// All write helpers return True if the full number of bytes was written.
// They use little‑endian byte order and operate at the current read/write position.

{****************************************************************************
  3.4a API_WriteInt8
  Writes a signed 8‑bit integer (1 byte) to the buffer at the current position.
  Parameters:
    Hnd   : data handle.
    Value : signed 8‑bit value.
  Returns:
    True if the byte was successfully written.
  Thread safe: write operations on the same handle must be serialized.
  Example:
    if API_WriteInt8(d, 127) then ...
****************************************************************************}
function API_WriteInt8(Hnd: TDataHnd; Value: int8): boolean;

{****************************************************************************
  3.4b API_WriteUInt8
  Writes an unsigned 8‑bit integer (1 byte) to the buffer.
****************************************************************************}
function API_WriteUInt8(Hnd: TDataHnd; Value: uint8): boolean;

{****************************************************************************
  3.4c API_WriteInt16
  Writes a signed 16‑bit integer (2 bytes, little‑endian) to the buffer.
****************************************************************************}
function API_WriteInt16(Hnd: TDataHnd; Value: int16): boolean;

{****************************************************************************
  3.4d API_WriteUInt16
  Writes an unsigned 16‑bit integer (2 bytes, little‑endian) to the buffer.
****************************************************************************}
function API_WriteUInt16(Hnd: TDataHnd; Value: uint16): boolean;

{****************************************************************************
  3.4e API_WriteInt32
  Writes a signed 32‑bit integer (4 bytes, little‑endian) to the buffer.
****************************************************************************}
function API_WriteInt32(Hnd: TDataHnd; Value: int32): boolean;

{****************************************************************************
  3.4f API_WriteUInt32
  Writes an unsigned 32‑bit integer (4 bytes, little‑endian) to the buffer.
****************************************************************************}
function API_WriteUInt32(Hnd: TDataHnd; Value: uint32): boolean;

{****************************************************************************
  3.4g API_WriteInt64
  Writes a signed 64‑bit integer (8 bytes, little‑endian) to the buffer.
****************************************************************************}
function API_WriteInt64(Hnd: TDataHnd; Value: int64): boolean;

{****************************************************************************
  3.4h API_WriteUInt64
  Writes an unsigned 64‑bit integer (8 bytes, little‑endian) to the buffer.
****************************************************************************}
function API_WriteUInt64(Hnd: TDataHnd; Value: uint64): boolean;

{****************************************************************************
  3.4i API_WriteSingle
  Writes a 32‑bit IEEE 754 single‑precision float (4 bytes, little‑endian).
****************************************************************************}
function API_WriteSingle(Hnd: TDataHnd; Value: single): boolean;

{****************************************************************************
  3.4j API_WriteDouble
  Writes a 64‑bit IEEE 754 double‑precision float (8 bytes, little‑endian).
****************************************************************************}
function API_WriteDouble(Hnd: TDataHnd; Value: double): boolean;

{****************************************************************************
  3.4k API_WriteString
  Writes a UTF‑8 encoded Pascal string, followed by a null terminator (#0).
  This matches the standard "UTF‑8 + #0" format used across all languages.
  Parameters:
    Hnd   : data handle.
    Value : Pascal string (will be encoded as UTF‑8 internally).
  Returns:
    True if the string (including the trailing null) was fully written.
  Thread safe: write operations on the same handle must be serialized.
  Example:
    if API_WriteString(d, 'Hello') then ...
  Note: The position is advanced by Length(UTF8String(Value)) + 1 bytes.
****************************************************************************}
function API_WriteString(Hnd: TDataHnd; const Value: string): boolean;

  {****************************************************************************
    3.5 API_ReadBuffer
    Reads binary data from the current position into the caller's buffer.
    The position advances.
    Parameters:
      Hnd  : data handle.
      Buff : destination buffer pointer.
      Size : maximum bytes to read.
    Returns:
      Number of bytes actually read (may be less than Size if the buffer end
      is reached).
    Thread safe: reads and writes on the same handle must not be concurrent;
      multiple reads can be concurrent.
    Example:
      var i: Integer;
      begin
        API_SetPos(d, 0);
        if API_ReadBuffer(d, @i, SizeOf(i)) = SizeOf(i) then ...
      end;
  ****************************************************************************}
function API_ReadBuffer(Hnd: TDataHnd; Buff: Pointer; Size: int64): int64; cdecl; external libapi_hub name 'API_ReadBuffer';

// ========================== ATOMIC READ HELPERS ==========================
// All read helpers return True if the full number of bytes was read.
// They use little‑endian byte order and operate at the current read/write position.

{****************************************************************************
  3.5a API_ReadInt8
  Reads a signed 8‑bit integer (1 byte) from the current position.
  Parameters:
    Hnd   : data handle.
    out Value : the read value (only valid if function returns True).
  Returns:
    True if the byte was successfully read.
  Thread safe: reads on the same handle are safe as long as no concurrent write.
  Example:
    var v: Int8;
    if API_ReadInt8(d, v) then ...
****************************************************************************}
function API_ReadInt8(Hnd: TDataHnd; out Value: int8): boolean; overload;

{****************************************************************************
  3.5b API_ReadUInt8
  Reads an unsigned 8‑bit integer (1 byte).
****************************************************************************}
function API_ReadUInt8(Hnd: TDataHnd; out Value: uint8): boolean; overload;

{****************************************************************************
  3.5c API_ReadInt16
  Reads a signed 16‑bit integer (2 bytes, little‑endian).
****************************************************************************}
function API_ReadInt16(Hnd: TDataHnd; out Value: int16): boolean; overload;

{****************************************************************************
  3.5d API_ReadUInt16
  Reads an unsigned 16‑bit integer (2 bytes, little‑endian).
****************************************************************************}
function API_ReadUInt16(Hnd: TDataHnd; out Value: uint16): boolean; overload;

{****************************************************************************
  3.5e API_ReadInt32
  Reads a signed 32‑bit integer (4 bytes, little‑endian).
****************************************************************************}
function API_ReadInt32(Hnd: TDataHnd; out Value: int32): boolean; overload;

{****************************************************************************
  3.5f API_ReadUInt32
  Reads an unsigned 32‑bit integer (4 bytes, little‑endian).
****************************************************************************}
function API_ReadUInt32(Hnd: TDataHnd; out Value: uint32): boolean; overload;

{****************************************************************************
  3.5g API_ReadInt64
  Reads a signed 64‑bit integer (8 bytes, little‑endian).
****************************************************************************}
function API_ReadInt64(Hnd: TDataHnd; out Value: int64): boolean; overload;

{****************************************************************************
  3.5h API_ReadUInt64
  Reads an unsigned 64‑bit integer (8 bytes, little‑endian).
****************************************************************************}
function API_ReadUInt64(Hnd: TDataHnd; out Value: uint64): boolean; overload;

{****************************************************************************
  3.5i API_ReadSingle
  Reads a 32‑bit IEEE 754 single‑precision float (4 bytes, little‑endian).
****************************************************************************}
function API_ReadSingle(Hnd: TDataHnd; out Value: single): boolean; overload;

{****************************************************************************
  3.5j API_ReadDouble
  Reads a 64‑bit IEEE 754 double‑precision float (8 bytes, little‑endian).
****************************************************************************}
function API_ReadDouble(Hnd: TDataHnd; out Value: double): boolean; overload;

{****************************************************************************
  Overload: direct return version for each read function.
  Returns the value read, or 0 (0.0 for floats) if reading fails.
****************************************************************************}
function API_ReadInt8(Hnd: TDataHnd): int8; overload;
function API_ReadUInt8(Hnd: TDataHnd): uint8; overload;
function API_ReadInt16(Hnd: TDataHnd): int16; overload;
function API_ReadUInt16(Hnd: TDataHnd): uint16; overload;
function API_ReadInt32(Hnd: TDataHnd): int32; overload;
function API_ReadUInt32(Hnd: TDataHnd): uint32; overload;
function API_ReadInt64(Hnd: TDataHnd): int64; overload;
function API_ReadUInt64(Hnd: TDataHnd): uint64; overload;
function API_ReadSingle(Hnd: TDataHnd): single; overload;
function API_ReadDouble(Hnd: TDataHnd): double; overload;

{****************************************************************************
  3.5k API_ReadString
  Reads a UTF‑8 encoded string terminated by a null byte (#0) from the current
  position. The read position is advanced past the terminating null.
  Parameters:
    Hnd   : data handle.
    out Value : the decoded Pascal string (empty if no data or invalid UTF‑8).
  Returns:
    True if at least one byte was read and a null terminator was found.
    False if the end of the buffer is reached without a null terminator.
  Thread safe: reads on the same handle are safe as long as no concurrent write.
  Example:
    var s: string;
    if API_ReadString(d, s) then ...
  Note: This function reads until a null byte (#0) is encountered. If the buffer
        contains no null byte within the current size, it returns False and
        Value is set to empty string. The position is moved to the byte after
        the null terminator.
****************************************************************************}
function API_ReadString(Hnd: TDataHnd; out Value: string): boolean; overload;
function API_ReadString(Hnd: TDataHnd): string; overload;

  {****************************************************************************
    3.6 API_GetPos / API_SetPos
    Gets/Sets the current read/write position (byte offset, 0‑based).
    If SetPos exceeds the current size, the buffer is extended with zero bytes.
    Thread safe: GetPos is read‑only safe; SetPos must be serialized.
  ****************************************************************************}
function API_GetPos(Hnd: TDataHnd): int64; cdecl; external libapi_hub name 'API_GetPos';
procedure API_SetPos(Hnd: TDataHnd; Pos_: int64); cdecl; external libapi_hub name 'API_SetPos';

  {****************************************************************************
    3.7 API_GetSize / API_SetSize
    Gets/Sets the total buffer size in bytes.
    If SetSize shrinks the buffer, data is truncated; if it enlarges, new
    space is uninitialized.
    Thread safe: GetSize is read‑only safe; SetSize must be serialized.
  ****************************************************************************}
function API_GetSize(Hnd: TDataHnd): int64; cdecl; external libapi_hub name 'API_GetSize';
procedure API_SetSize(Hnd: TDataHnd; Size_: int64); cdecl; external libapi_hub name 'API_SetSize';

{===============================================================================
  4. Application Handle Operations
===============================================================================}

  {****************************************************************************
    4.1 API_Create_APPHnd
    Creates an application context.
    Parameters:
      appName : application name (case‑sensitive, UTF‑8, must be unique
                across the network).
      Desc    : human‑readable description (UTF‑8, may be empty).
    Returns:
      New TAppHnd. Never returns nil under normal conditions.
    Note: must be freed with API_Free_APPHnd.
    Thread safe: Yes.
  ****************************************************************************}
function API_Create_APPHnd(appName, Desc: pansichar): TAppHnd; cdecl; external libapi_hub name 'API_Create_APPHnd';
function API_Create_APPHnd2(appName, Desc: string): TAppHnd;  // convenience overload, auto UTF‑8

  {****************************************************************************
    4.2 API_Free_APPHnd
    Destroys an application handle, freeing all registered APIs and resources.
    Parameters:
      appHnd : application handle.
    Thread safe: Yes, but ensure no other thread is using the handle.
  ****************************************************************************}
procedure API_Free_APPHnd(appHnd: TAppHnd); cdecl; external libapi_hub name 'API_Free_APPHnd';

  {****************************************************************************
    4.3 API_Reg_Call
    Registers a request‑response (Call) API within the application.
    Parameters:
      appHnd   : application handle.
      APIName  : API name (unique inside the app, case‑sensitive, UTF‑8).
      Desc     : description (UTF‑8, optional).
      Trigger  : user data that will be passed to the callback.
      OnCall   : callback function pointer (cdecl).
    Returns:
      1 on success, 0 if the API name already exists.
    Thread safe: Yes.
    Note: see TAPI_Call for callback constraints.
  ****************************************************************************}
function API_Reg_Call(appHnd: TAppHnd; APIName, Desc: pansichar; Trigger: Pointer; OnCall: TAPI_Call): integer; cdecl; external libapi_hub name 'API_Reg_Call';
function API_Reg_Call2(appHnd: TAppHnd; APIName, Desc: string; Trigger: Pointer; OnCall: TAPI_Call): integer;  // convenience overload

  {****************************************************************************
    4.4 API_Reg_Notify
    Registers a one‑way notification (Notify) API within the application.
    Parameters and return same as API_Reg_Call, but callback type is TAPI_Notify
    (no output).
    Thread safe: Yes.
  ****************************************************************************}
function API_Reg_Notify(appHnd: TAppHnd; APIName, Desc: pansichar; Trigger: Pointer; OnNotify: TAPI_Notify): integer; cdecl; external libapi_hub name 'API_Reg_Notify';
function API_Reg_Notify2(appHnd: TAppHnd; APIName, Desc: string; Trigger: Pointer; OnNotify: TAPI_Notify): integer;  // convenience overload

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
function API_UnReg(appHnd: TAppHnd; APIName: pansichar): integer; cdecl; external libapi_hub name 'API_UnReg';
function API_UnReg2(appHnd: TAppHnd; APIName: string): integer;

  {****************************************************************************
    4.5 API_Local_APP_Call
    Executes a Call API locally (within the same process), bypassing the network.
    Parameters:
      appHnd : application handle.
      Param  : input data handle (must contain API name and payload).
    Returns:
      New TDataHnd containing the result; if the API is not found or an error
      occurs, the handle size will be 0.
    Notes:
      • The returned handle must be freed by the caller.
      • The input handle is not freed by this function; the caller must free it.
    Thread safe: Yes.
  ****************************************************************************}
function API_Local_APP_Call(appHnd: TAppHnd; Param: TDataHnd): TDataHnd; cdecl; external libapi_hub name 'API_Local_APP_Call';

  {****************************************************************************
    4.6 API_Local_APP_Notify
    Sends a notification locally (no result).
    Parameters:
      appHnd : application handle.
      Param  : input data handle.
    Thread safe: Yes.
  ****************************************************************************}
procedure API_Local_APP_Notify(appHnd: TAppHnd; Param: TDataHnd); cdecl; external libapi_hub name 'API_Local_APP_Notify';

{===============================================================================
  5. Network Layer – Preparation & Communication
===============================================================================}

  {****************************************************************************
    5.1 API_Prepare_Service
    Prepares a service listener. Can be called multiple times to start
    multiple services.
    Parameters:
      ListeningAddr_ : local address to bind (UTF‑8).
                       TCP example: "0.0.0.0:9898" or "127.0.0.1"
                       IPC example: "ipc:my_service"
                       If no port is given, default 9898 is used (IPC ignores port).
      PhysicsAddr_   : public address advertised to clients (UTF‑8).
                       Must match the address provided by clients.
    Returns:
      An internal tag (informational, may be ignored).
    Note: services and clients can be prepared in any order; clients will
          wait for services to appear.
    Thread safe: Yes (usually called from the main thread).
  ****************************************************************************}
function API_Prepare_Service(ListeningAddr_, PhysicsAddr_: pansichar): integer; cdecl; external libapi_hub name 'API_Prepare_Service';
function API_Prepare_Service2(ListeningAddr_, PhysicsAddr_: string): integer;  // convenience overload

  {****************************************************************************
    5.2 API_Prepare_Client
    Prepares a client connection.
    Parameters:
      PhysicsAddr_ : remote service address (UTF‑8), must match the service's
                     public address.
      appHnd       : optional application handle. If provided, the client will
                     automatically register this app's APIs with the service
                     (exposing the app). If nil, the client acts as a pure
                     consumer.
    Returns:
      An internal tag (informational).
    Note: the client automatically reconnects if the connection is lost,
          and re‑registers the application if provided.
    Thread safe: Yes.
  ****************************************************************************}
function API_Prepare_Client(PhysicsAddr_: pansichar; appHnd: TAppHnd): integer; cdecl; external libapi_hub name 'API_Prepare_Client';
function API_Prepare_Client2(PhysicsAddr_: string; appHnd: TAppHnd): integer; overload;  // convenience overload
function API_Prepare_Client2(PhysicsAddr_: string): integer; overload;                  // convenience overload (no app)

  {****************************************************************************
    5.3 API_Reset_Prepare
    Clears all previously prepared services and clients.
    Call this before preparing a new set to avoid conflicts.
    Thread safe: Yes.
  ****************************************************************************}
procedure API_Reset_Prepare(); cdecl; external libapi_hub name 'API_Reset_Prepare';

  {****************************************************************************
    5.4 API_Prepare_Done
    Starts the C4 framework with all prepared services and clients.
    This function blocks until the framework is fully initialized and running.
    Returns:
      1 on success, 0 on failure (error details are printed to the console).
    Notes:
      • Must be called only once per preparation session (unless you reset
        with API_Exit_MainThread or API_shutdown).
      • After this call, remote calls can be made.
    Thread safe: Yes, but recommended to call from the main thread.
  ****************************************************************************}
function API_Prepare_Done: integer; cdecl; external libapi_hub name 'API_Prepare_Done';

  {****************************************************************************
    5.5 API_Exit_MainThread
    Signals the internal event loop to exit (stops network processing).
    Resources are not automatically freed; usually followed by API_shutdown.
    Recommended order: call this first, then API_shutdown.
    Thread safe: Yes.
  ****************************************************************************}
procedure API_Exit_MainThread; cdecl; external libapi_hub name 'API_Exit_MainThread';

  {****************************************************************************
    5.6 API_Call
    Performs a remote (or local) synchronous call to the target application.
    Parameters:
      appName   : target application name (case‑sensitive, UTF‑8).
      Param     : input data handle (cloned internally; caller must still free
                  the original).
      Timeout_  : timeout in milliseconds. 0 means infinite wait (use with care).
    Returns:
      New TDataHnd containing the result. The handle is never nil; if the call
      times out or fails, its size will be 0. The caller MUST free the returned
      handle (even if size is 0).
    Thread safe: Fully thread‑safe; can be called concurrently.
    Notes:
      • The function first attempts a local call if the target app is
        registered in the same process.
      • Order of concurrent calls is not guaranteed (load balancing may
        reorder them).
      • Lightweight calls achieve ~3000 per second (depending on network and
        hardware).
    Example:
      var d, res: TDataHnd;
      begin
        d := API_Create_DataHnd('add');
        API_WriteBuffer(d, @a, SizeOf(a));
        API_WriteBuffer(d, @b, SizeOf(b));
        res := API_Call('CalcApp', d, 5000);
        if API_GetSize(res) > 0 then ...
        API_Free_DataHnd(d);
        API_Free_DataHnd(res);   // always free result
      end;
  ****************************************************************************}
function API_Call(appName: pansichar; Param: TDataHnd; Timeout_: uint64): TDataHnd; cdecl; external libapi_hub name 'API_Call';
function API_Call2(appName: string; Param: TDataHnd; Timeout_: uint64): TDataHnd;  // convenience overload

  {****************************************************************************
    5.7 API_Notify
    Sends a one‑way notification (fire‑and‑forget).
    Parameters:
      appName : target application name (UTF‑8).
      Param   : input data handle (cloned internally; caller must still free).
    Thread safe: Yes.
    Note: order of notifications is not guaranteed; no response is expected.
  ****************************************************************************}
procedure API_Notify(appName: pansichar; Param: TDataHnd); cdecl; external libapi_hub name 'API_Notify';
procedure API_Notify2(appName: string; Param: TDataHnd);   // convenience overload

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
procedure API_SetOption(Option, Value: pansichar); cdecl; external libapi_hub name 'API_SetOption';
procedure API_SetOption2(Option, Value: string);

  {****************************************************************************
    5.8 API_shutdown
    Gracefully shuts down the entire framework: stops all services, disconnects
    all clients, and releases internal resources.
    After this call, the state is reset and you can re‑initialize.
    This function internally calls API_Exit_MainThread, but it is recommended
    to call that explicitly first for a clean shutdown.
    Thread safe: Yes, but usually called from the main thread.
  ****************************************************************************}
procedure API_shutdown; cdecl; external libapi_hub name 'API_shutdown';

{===============================================================================
  6. Implementation – Convenience Wrappers
  These are thin wrappers around the raw API calls; they do not change
  behaviour and only handle UTF‑8 conversion.
===============================================================================}

implementation

function API_Create_DataHnd2(APIName: string): TDataHnd;
begin
  Result := API_Create_DataHnd(pansichar(UTF8Encode(APIName)));
end;

function API_GetBuffer2(Hnd: TDataHnd; Offset: nativeint): Pointer;
var
  base: Pointer;
begin
  base := API_GetBuffer(Hnd);
  if base = nil then
    Result := nil
  else
    Result := Pointer(nativeuint(base) + Offset);
end;

{===============================================================================
  6a. Implementation of atomic write helpers
===============================================================================}
function API_WriteInt8(Hnd: TDataHnd; Value: int8): boolean;
begin
  Result := API_WriteBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_WriteUInt8(Hnd: TDataHnd; Value: uint8): boolean;
begin
  Result := API_WriteBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_WriteInt16(Hnd: TDataHnd; Value: int16): boolean;
begin
  Result := API_WriteBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_WriteUInt16(Hnd: TDataHnd; Value: uint16): boolean;
begin
  Result := API_WriteBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_WriteInt32(Hnd: TDataHnd; Value: int32): boolean;
begin
  Result := API_WriteBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_WriteUInt32(Hnd: TDataHnd; Value: uint32): boolean;
begin
  Result := API_WriteBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_WriteInt64(Hnd: TDataHnd; Value: int64): boolean;
begin
  Result := API_WriteBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_WriteUInt64(Hnd: TDataHnd; Value: uint64): boolean;
begin
  Result := API_WriteBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_WriteSingle(Hnd: TDataHnd; Value: single): boolean;
begin
  Result := API_WriteBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_WriteDouble(Hnd: TDataHnd; Value: double): boolean;
begin
  Result := API_WriteBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_WriteString(Hnd: TDataHnd; const Value: string): boolean;
var
  utf8: TBytes;
  len: Integer;
  written: Int64;
begin
  // Empty string: write only a null terminator.
  if Value = '' then
  begin
    Result := API_WriteUInt8(Hnd, 0);
    Exit;
  end;

  utf8 := TEncoding.UTF8.GetBytes(Value);
  len := Length(utf8);
  written := API_WriteBuffer(Hnd, @utf8[0], len);
  if written <> len then
  begin
    Result := False;
    Exit;
  end;
  // Write the null terminator and ensure it succeeds.
  Result := API_WriteUInt8(Hnd, 0);
end;

{===============================================================================
  6b. Implementation of atomic read helpers
===============================================================================}
function API_ReadInt8(Hnd: TDataHnd; out Value: int8): boolean;
begin
  Result := API_ReadBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_ReadUInt8(Hnd: TDataHnd; out Value: uint8): boolean;
begin
  Result := API_ReadBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_ReadInt16(Hnd: TDataHnd; out Value: int16): boolean;
begin
  Result := API_ReadBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_ReadUInt16(Hnd: TDataHnd; out Value: uint16): boolean;
begin
  Result := API_ReadBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_ReadInt32(Hnd: TDataHnd; out Value: int32): boolean;
begin
  Result := API_ReadBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_ReadUInt32(Hnd: TDataHnd; out Value: uint32): boolean;
begin
  Result := API_ReadBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_ReadInt64(Hnd: TDataHnd; out Value: int64): boolean;
begin
  Result := API_ReadBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_ReadUInt64(Hnd: TDataHnd; out Value: uint64): boolean;
begin
  Result := API_ReadBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_ReadSingle(Hnd: TDataHnd; out Value: single): boolean;
begin
  Result := API_ReadBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

function API_ReadDouble(Hnd: TDataHnd; out Value: double): boolean;
begin
  Result := API_ReadBuffer(Hnd, @Value, SizeOf(Value)) = SizeOf(Value);
end;

{===============================================================================
  6c. Direct‑return overloads for read helpers (return 0 on failure)
===============================================================================}
function API_ReadInt8(Hnd: TDataHnd): int8;
var v: int8;
begin
  if API_ReadInt8(Hnd, v) then Result := v else Result := 0;
end;

function API_ReadUInt8(Hnd: TDataHnd): uint8;
var v: uint8;
begin
  if API_ReadUInt8(Hnd, v) then Result := v else Result := 0;
end;

function API_ReadInt16(Hnd: TDataHnd): int16;
var v: int16;
begin
  if API_ReadInt16(Hnd, v) then Result := v else Result := 0;
end;

function API_ReadUInt16(Hnd: TDataHnd): uint16;
var v: uint16;
begin
  if API_ReadUInt16(Hnd, v) then Result := v else Result := 0;
end;

function API_ReadInt32(Hnd: TDataHnd): int32;
var v: int32;
begin
  if API_ReadInt32(Hnd, v) then Result := v else Result := 0;
end;

function API_ReadUInt32(Hnd: TDataHnd): uint32;
var v: uint32;
begin
  if API_ReadUInt32(Hnd, v) then Result := v else Result := 0;
end;

function API_ReadInt64(Hnd: TDataHnd): int64;
var v: int64;
begin
  if API_ReadInt64(Hnd, v) then Result := v else Result := 0;
end;

function API_ReadUInt64(Hnd: TDataHnd): uint64;
var v: uint64;
begin
  if API_ReadUInt64(Hnd, v) then Result := v else Result := 0;
end;

function API_ReadSingle(Hnd: TDataHnd): single;
var v: single;
begin
  if API_ReadSingle(Hnd, v) then Result := v else Result := 0.0;
end;

function API_ReadDouble(Hnd: TDataHnd): double;
var v: double;
begin
  if API_ReadDouble(Hnd, v) then Result := v else Result := 0.0;
end;

function API_ReadString(Hnd: TDataHnd; out Value: string): boolean;
type
  TByteArray = array [0..0] of byte;
  PByteArray = ^TByteArray;
var
  p: PByteArray;
  b, e, sz: int64;
  buff: TBytes;
begin
  p := API_GetBuffer(Hnd);
  sz := API_GetSize(Hnd);

  // Handle null or empty buffer.
  if (p = nil) or (sz = 0) then
  begin
    Value := '';
    Result := False;
    Exit;
  end;

  b := API_GetPos(Hnd);
  if b >= sz then
  begin
    Value := '';
    Result := False;
    Exit;
  end;

  e := b;
  // Search for the null terminator with correct bounds check first.
  while (e < sz) and (p^[e] <> 0) do
    Inc(e);

  // If we reached the end without finding a null, fail.
  if e = sz then
  begin
    Value := '';
    Result := False;
    Exit;
  end;

  // Copy bytes from b to e-1 (excluding the null terminator).
  SetLength(buff, e - b);
  if e > b then
    Move(p^[b], buff[0], e - b)
  else
    buff := nil;  // empty string

  // Advance position past the null terminator.
  API_SetPos(Hnd, e + 1);

  // Decode UTF-8.
  Value := TEncoding.UTF8.GetString(buff);
  Result := True;
end;

function API_ReadString(Hnd: TDataHnd): string;
begin
  // Call the out-version; on failure it returns empty string.
  API_ReadString(Hnd, Result);
end;

function API_Create_APPHnd2(appName, Desc: string): TAppHnd;
begin
  Result := API_Create_APPHnd(pansichar(UTF8Encode(appName)), pansichar(UTF8Encode(Desc)));
end;

function API_Reg_Call2(appHnd: TAppHnd; APIName, Desc: string; Trigger: Pointer; OnCall: TAPI_Call): integer;
begin
  Result := API_Reg_Call(appHnd, pansichar(UTF8Encode(APIName)), pansichar(UTF8Encode(Desc)), Trigger, OnCall);
end;

function API_Reg_Notify2(appHnd: TAppHnd; APIName, Desc: string; Trigger: Pointer; OnNotify: TAPI_Notify): integer;
begin
  Result := API_Reg_Notify(appHnd, pansichar(UTF8Encode(APIName)), pansichar(UTF8Encode(Desc)), Trigger, OnNotify);
end;

function API_UnReg2(appHnd: TAppHnd; APIName: string): integer;
begin
  Result := API_UnReg(appHnd, pansichar(UTF8Encode(APIName)));
end;

function API_Prepare_Service2(ListeningAddr_, PhysicsAddr_: string): integer;
begin
  Result := API_Prepare_Service(pansichar(UTF8Encode(ListeningAddr_)), pansichar(UTF8Encode(PhysicsAddr_)));
end;

function API_Prepare_Client2(PhysicsAddr_: string; appHnd: TAppHnd): integer;
begin
  Result := API_Prepare_Client(pansichar(UTF8Encode(PhysicsAddr_)), appHnd);
end;

function API_Prepare_Client2(PhysicsAddr_: string): integer;
begin
  Result := API_Prepare_Client2(PhysicsAddr_, nil);
end;

function API_Call2(appName: string; Param: TDataHnd; Timeout_: uint64): TDataHnd;
begin
  Result := API_Call(pansichar(UTF8Encode(appName)), Param, Timeout_);
end;

procedure API_Notify2(appName: string; Param: TDataHnd);
begin
  API_Notify(pansichar(UTF8Encode(appName)), Param);
end;

procedure API_SetOption2(Option, Value: string);
begin
  API_SetOption(pansichar(UTF8Encode(Option)), pansichar(UTF8Encode(Value)));
end;

initialization
  // Nothing to initialize

finalization
  if not IsLibrary then
    API_shutdown();   // automatic cleanup
end.
