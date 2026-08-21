{
  * --------------------------------------------------------------------------
  * Z.API_HubTool – Core RPC framework for defining, registering, and invoking
  *               language‑neutral APIs locally or over a distributed network.
  *
  * This unit is the backbone of the API Hub system. It provides the data
  * structures and logic that allow an application (TAPI_APP) to expose
  * callable functions (APIs) and one‑way notifications. These APIs can be
  * executed directly inside the same process or routed over a network using
  * the companion C4 transport layer.
  *
  * The design is built around three primary concepts:
  *
  *   – TAPI_APP : A named container that groups a set of related APIs.
  *                Each app has a unique name (used for routing) and contains
  *                a TAPI_Tool instance that manages its API registry.
  *
  *   – TAPI_Tool: The engine that holds the registry of all APIs for a given
  *                app. It provides methods to register new APIs (Reg_Call,
  *                Reg_Notify) and to execute them locally (Execute_Call,
  *                Execute_Notify). It uses a thread‑safe hash pool to store
  *                API metadata (TAPI_Info).
  *
  *   – TMemory_Param_Tool: A helper that packs an API name and a binary
  *                payload into a single TMem64 block. This block can be sent
  *                over the network or passed between threads. The format is:
  *                [API name as a Pascal string] + [4‑byte payload size] +
  *                [payload bytes]. This is the standard wire format used by
  *                the API Hub system.
  *
  * The unit also defines an opaque handle (TDataHnd) and an application
  * handle (TAppHnd) that are used by the C ABI export layer (in the separate
  * unit API_HubTool_Export). This allows the framework to be called from
  * other languages (C, C++, Python, etc.) via a cdecl interface.
  *
  * All public classes and methods are designed to be thread‑safe, except for
  * the TMemory_Param_Tool which is not thread‑safe when shared between
  * threads. Use separate instances per thread or synchronise access.
  *
  * The unit depends on:
  *   – Z.Core                 (foundation: threads, containers, memory)
  *   – Z.PascalStrings        (TPascalString handling)
  *   – Z.UPascalStrings       (Unicode string handling)
  *   – Z.Status               (global logging)
  *   – Z.UnicodeMixedLib      (utility functions)
  *   – Z.HashList.Templet     (generic hash pool)
  *   – Z.MemoryStream         (TMem64 stream)
  *   – Z.Parsing              (text parsing, not heavily used here)
  *   – API_HubTool_Export     (C ABI types)
  *   – Z.Int128               (not directly used, but included for completeness)
  *
  * @Example (registering and calling a simple API locally):
  *   var
  *     App: TAPI_APP;
  *     Tool: TAPI_Tool;
  *     Param, Result: TMem64;
  *   begin
  *     App := TAPI_APP.Create;
  *     App.Name := 'MyApp';
  *
  *     // Register a Call API named 'echo' that copies input to output.
  *     App.API.Reg_Call('echo', 'Echo service', nil,
  *       procedure(Trigger: Pointer; Input, Output: PAPI_Data)
  *       begin
  *         // Copy the entire input buffer to output.
  *         Output.Data_Result.CopyFrom(Input.Data_Param.Param, -1);
  *       end
  *     );
  *
  *     // Prepare a parameter block for the API.
  *     Param := TMem64.Create;
  *     Param.WriteString('Hello world');
  *
  *     // Execute the call locally.
  *     Result := App.API.Execute_Call(TMemory_Param_Tool.Encode('echo', Param));
  *     // Result now contains the echoed data.
  *     DisposeObject(Result);
  *     DisposeObject(Param);
  *     DisposeObject(App);
  *   end;
  *
  * @Example (sending a notification):
  *   // Register a Notify API.
  *   App.API.Reg_Notify('log', 'Logging', nil,
  *     procedure(Trigger: Pointer; Input: PAPI_Data)
  *     begin
  *       // Read the message from the input and log it.
  *       var Msg := Input.Data_Param.Param.ReadString;
  *       DoStatus('Log: ' + Msg);
  *     end
  *   );
  *
  *   // Send a notification.
  *   var NotifyParam := TMem64.Create;
  *   NotifyParam.WriteString('Hello from notify');
  *   App.API.Execute_Notify(TMemory_Param_Tool.Encode('log', NotifyParam));
  *   DisposeObject(NotifyParam);
  *
  * For remote execution over the network, refer to the companion units
  * Z.Net.C4.API_Hub and API_HubTool_Export.
  * --------------------------------------------------------------------------
}
unit Z.API_HubTool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\pascal\zNetV2\source\Z.Define.inc}

interface

uses
  Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.Status, Z.UnicodeMixedLib,
  Z.HashList.Templet, Z.MemoryStream, Z.Parsing,
  Z.API_HubTool_Export, Z.Int128;

type
  { * TAPI_String: A Unicode string type used throughout the API Hub for all
    * textual identifiers and descriptions. It is an alias for TUPascalString,
    * which provides high-performance Unicode handling.
    * @Note This type is used for all API names, descriptions, and any other
    *       text data exchanged by the framework.
  }
  TAPI_String = TUPascalString;

  { * TAPI_Mode: Classification of an API operation.
    *   - amUnknow : Unspecified, used as a placeholder or error state.
    *   - amCall   : Request-response style. The caller expects a result.
    *                The callback receives both Input and Output handles.
    *   - amNotify : One-way message. The caller does not wait for a response.
    *                The callback receives only an Input handle.
    * @Note This enumeration is stored in TAPI_Info to indicate the callback type.
  }
  TAPI_Mode = (
    amUnknow = 0,
    amCall = 1,
    amNotify = 2
    );

  { * TMemory_Param_Tool: A helper class that packs an API name and its binary
    * parameter data into a single TMem64 block for transmission or storage.
    * The packed format is: [API name as a Pascal string] + [4-byte payload size]
    * + [payload bytes]. This format is used by both local and remote calls.
    * The class provides methods to pack (EncryptToMem) and unpack
    * (DecryptFromMem) the data. It is not thread-safe; create separate
    * instances for concurrent use.
    *
    * @Example:
    *   var Tool := TMemory_Param_Tool.Create;
    *   Tool.apiName := 'echo';
    *   Tool.Param.WriteString('Hello');
    *   var M64 := TMem64.Create;
    *   Tool.EncryptToMem(M64);   // now M64 contains the packed data
    *   // To unpack later:
    *   var Tool2 := TMemory_Param_Tool.Create;
    *   Tool2.DecryptFromMem(M64);
    *   // Tool2.apiName = 'echo', Tool2.Param contains the string.
    * @Field apiName: Name of the target API.
    * @Field Param: Binary payload for the API call/notification.
    * @Constructor Create: Initializes empty fields and internal temp buffer.
    * @Destructor Destroy: Frees Param and temp buffer.
    * @Method EncryptToMem: Encodes the current apiName and Param into a TMem64.
    * @Method DecryptFromMem: Decodes a TMem64 block back into apiName and Param.
    * @ClassMethod Get_apiName: Extracts only the API name from a packed block.
  }
  TMemory_Param_Tool = class
  private
    tmp: TMem64; // Internal buffer used during decoding to avoid reallocation.
  public
    apiName: TAPI_String; // Name of the target API.
    Param: TMem64; // Binary payload for the API call/notification.

    constructor Create;
    destructor Destroy; override;

    procedure EncryptToMem(m64: TMem64);
    procedure DecryptFromMem(m64: TMem64);
    class function Get_apiName(m64: TMem64): TAPI_String;
  end;

  { * TAPI_Info: Metadata record for a single registered API.
    * It stores the API's name, description, mode (Call/Notify), a user-supplied
    * trigger pointer, and the appropriate callback function.
    * Instances of this class are stored in a TAPI_Info_Pool.
    * @Field Name: Unique identifier of the API (case‑sensitive).
    * @Field Desc: Human‑readable description.
    * @Field Mode: Whether this is a Call or Notify API.
    * @Field Trigger: User‑defined data passed back to the callback.
    * @Field On_Call: Callback for Call‑mode APIs (cdecl).
    * @Field On_Notify: Callback for Notify‑mode APIs (cdecl).
  }
  TAPI_Info = class
  public
    Name: TAPI_String;
    Desc: TAPI_String;
    Mode: TAPI_Mode;
    Trigger: Pointer;
    On_Call: TAPI_Call;
    On_Notify: TAPI_Notify;

    constructor Create;
    destructor Destroy; override;
  end;

  { * TAPI_Info_Pool: A thread-safe hash map that stores TAPI_Info objects
    * keyed by API name (as SystemString). It is used by TAPI_Tool to manage
    * the registry of APIs for an application.
    * The pool automatically frees TAPI_Info objects when entries are removed.
    * @InheritsFrom TString_Big_Hash_Pair_Pool<TAPI_Info>
    * @Method DoFree: Called when an entry is removed, frees the TAPI_Info object.
  }
  TAPI_Info_Pool = class(TString_Big_Hash_Pair_Pool<TAPI_Info>)
  public
    procedure DoFree(var Key: SystemString; var Value: TAPI_Info); override;
  end;

  { * PAPI_Data: A pointer to a TAPI_Data record. This is used as the opaque
    * TDataHnd handle in the C export layer. External code should never
    * dereference this pointer; it must only be passed to the API functions.
  }
  PAPI_Data = ^TAPI_Data;

  { * TAPI_Data: Represents either a parameter or a result for an API invocation.
    * It is a discriminated union: either Data_Param (input) or Data_Result (output)
    * will be non‑nil, never both.
    * This record is intended for internal use, but is exposed for the export layer.
    * The static factory methods simplify creation and destruction.
    * @Field Data_Param: Non‑nil if this is an input parameter (TMemory_Param_Tool).
    * @Field Data_Result: Non‑nil if this is an output result (TMem64).
    * @Method Init: Initialises the record to nil pointers.
    * @ClassMethod New_Param: Creates a new input parameter record with given API name.
    * @ClassMethod New_Param_From: Creates a new input parameter by unpacking a packed TMem64.
    * @ClassMethod New_Result: Creates a new empty output result record.
    * @ClassMethod New_Result_From: Creates a new output result taking ownership of a TMem64.
    * @ClassMethod Free_Data: Frees a TAPI_Data record and all its owned objects.
    * @Method GetBuffer: Returns a pointer to the raw data buffer (read‑only).
    * @Method WriteBuff: Writes data to the buffer at the current position.
    * @Method ReadBuff: Reads data from the buffer at the current position.
    * @Method Get_Pos: Returns the current read/write position.
    * @Method Set_Pos: Sets the current read/write position.
    * @Method Get_Size: Returns the total size of the data buffer.
    * @Method Set_Size: Resizes the data buffer.
  }
  TAPI_Data = record
  public
    Data_Param: TMemory_Param_Tool;
    Data_Result: TMem64;

    procedure Init;

    class function New_Param(apiName: TAPI_String): PAPI_Data; static;
    class function New_Param_From(Data_: TMem64): PAPI_Data; static;
    class function New_Result: PAPI_Data; static;
    class function New_Result_From(Data_: TMem64): PAPI_Data; static;
    class procedure Free_Data(hnd: PAPI_Data); static;

    function GetBuffer: Pointer;
    function WriteBuff(Buff: Pointer; Size: Int64): Int64;
    function ReadBuff(Buff: Pointer; Size: Int64): Int64;
    function Get_Pos: Int64;
    procedure Set_Pos(Pos_: Int64);
    function Get_Size: Int64;
    procedure Set_Size(Size_: Int64);
  end;

  { * TAPI_APP: Forward declaration for the application class (used below). }
  TAPI_APP = class;

  { * TAPI_Tool: The core API registry and execution engine for an application.
    * It maintains a pool of registered APIs and provides methods to invoke them
    * locally. It also holds a back‑reference to its owner TAPI_APP.
    * All registration and execution methods are thread‑safe.
    *
    * @Example:
    *   var Tool := TAPI_Tool.Create;
    *   Tool.Reg_Call('add', 'Adds two integers', nil,
    *     procedure(Trigger: Pointer; Input, Output: PAPI_Data)
    *     var
    *       a, b, Sum: Integer;
    *     begin
    *       Input.Data_Param.Param.ReadBuffer(@a, SizeOf(a));
    *       Input.Data_Param.Param.ReadBuffer(@b, SizeOf(b));
    *       Sum := a + b;
    *       Output.Data_Result.WriteBuffer(@Sum, SizeOf(Sum));
    *     end
    *   );
    *   // Execute the call.
    *   var Param := TMem64.Create;
    *   Param.WriteInt32(5);
    *   Param.WriteInt32(7);
    *   var Result := Tool.Execute_Call(Param); // Result is a TMem64 with Sum.
    *   DisposeObject(Result);
    *   DisposeObject(Param);
    *   DisposeObject(Tool);
    *
    * @Field API_Pool: Thread‑safe hash pool of registered APIs.
    * @Field APP: Back‑reference to the owning application.
    * @Constructor Create: Initializes the API pool.
    * @Destructor Destroy: Frees the API pool.
    * @Method Reg_Call: Registers a new Call API.
    * @Method Reg_Notify: Registers a new Notify API.
    * @Method UnReg: Unregisters an API by name.
    * @Method Execute_Call: Executes a Call API synchronously.
    * @Method Execute_Notify: Executes a Notify API asynchronously.
  }
  TAPI_Tool = class
  public
    API_Pool: TAPI_Info_Pool;
    APP: TAPI_APP;

    constructor Create;
    destructor Destroy; override;

    function Reg_Call(apiName, Desc: TAPI_String; Trigger: Pointer; On_Call: TAPI_Call): Boolean;
    function Reg_Notify(apiName, Desc: TAPI_String; Trigger: Pointer; On_Notify: TAPI_Notify): Boolean;
    function UnReg(apiName: TAPI_String): Boolean;

    function Execute_Call(Memory_Param: TMem64): TMem64;
    procedure Execute_Notify(Memory_Param: TMem64);
  end;

  { * TOn_API_Update: Callback signature for application update events.
    * This is triggered when the application's API list changes (registration,
    * unregistration). The event is fired in the main thread via a timer.
    * @Param Sender: The TAPI_APP instance that changed.
  }
  TOn_API_Update = procedure(Sender: TAPI_APP) of object;

  { * TAPIUpdate_Event_Pool: Thread‑safe hash map that stores event callbacks
    * keyed by a binding object (typically the subscriber). Used by TAPI_APP to
    * notify subscribers when the app's API list changes.
    * @InheritsFrom TCritical_Big_Hash_Pair_Pool<TCore_Object, TOn_API_Update>
  }
  TAPIUpdate_Event_Pool = class(TCritical_Big_Hash_Pair_Pool<TCore_Object, TOn_API_Update>)
  end;

  { * TAPI_APP: Represents a logical application that exposes a set of APIs.
    * Each app has a unique Name (used for network routing) and a Description.
    * It contains a TAPI_Tool instance that holds the actual API registry.
    * The app can notify subscribers (via Subscribe_Update) when its API list
    * changes (e.g., after registration or unregistration).
    *
    * @Example:
    *   var App := TAPI_APP.Create;
    *   App.Name := 'MyService';
    *   App.Desc := 'My service description';
    *   App.API.Reg_Call('ping', 'Ping', nil, MyPingCallback);
    *   // Subscribe to changes.
    *   App.Subscribe_Update(MyObject, MyUpdateHandler);
    *   // ... later, when the app changes, MyUpdateHandler will be called.
    *
    * @Field Name: Unique identifier for this application (case‑sensitive).
    * @Field Desc: Human‑readable description.
    * @Field API: The registry and execution engine (TAPI_Tool).
    * @Constructor Create: Initializes the API tool and event pool.
    * @Destructor Destroy: Frees the API tool and event pool.
    * @Method DoChange: Marks the app as changed and schedules a broadcast.
    * @Method Subscribe_Update: Subscribes a listener to update events.
    * @Method Remove_Update: Unsubscribes a previously subscribed object.
  }
  TAPI_APP = class
  private
    FAPIUpdate_Event_Pool: TAPIUpdate_Event_Pool;
    FUpdated: Boolean;
    procedure Do_APIReg_Event__;
    procedure DoTimer();
  public
    Name: TAPI_String;
    Desc: TAPI_String;
    API: TAPI_Tool;

    constructor Create;
    destructor Destroy; override;

    procedure DoChange();
    procedure Subscribe_Update(Bind: TCore_Object; OnUpdate: TOn_API_Update);
    procedure Remove_Update(Bind: TCore_Object);
  end;

implementation

{ ----------------------------------------------------------------------------
  TMemory_Param_Tool Implementation
  ---------------------------------------------------------------------------- }

{ * Constructor: Initializes the tool with empty apiName and Param, and creates
  * a temporary internal buffer (tmp) used during decoding to avoid reallocations.
  * @Note Param is a TMem64 object that will hold the payload.
}
constructor TMemory_Param_Tool.Create;
begin
  inherited Create;
  tmp := TMem64.Create;
  apiName := '';
  Param := TMem64.Create;
end;

{ * Destructor: Frees the Param payload and the temporary internal buffer.
  * @Note The object is disposed with DisposeObject (from Z.Core) which handles
  *       nil checking and exception safety.
}
destructor TMemory_Param_Tool.Destroy;
begin
  DisposeObject(Param);
  DisposeObject(tmp);
  inherited Destroy;
end;

{ * EncryptToMem: Encodes the current apiName and Param into the provided TMem64.
  * The encoded format is:
  *   - Pascal-style string (length prefix) for apiName.
  *   - 32-bit integer for the payload size.
  *   - raw payload bytes.
  * @Param m64: Destination TMem64. It is cleared before writing.
  * @Note The resulting m64 can be sent over the network or stored.
}
procedure TMemory_Param_Tool.EncryptToMem(m64: TMem64);
begin
  m64.Clear;
  m64.WriteString(apiName.Text);
  m64.WriteInt32(Param.Size);
  m64.WritePtr(Param.Memory, Param.Size);
end;

{ * DecryptFromMem: Decodes a TMem64 block that was previously packed by
  * EncryptToMem, restoring apiName and Param.
  * @Param m64: Source TMem64 containing the packed data.
  * @Note If m64 is in protected mode (read‑only), we read directly from it.
  *       Otherwise, we swap its content into tmp to avoid modifying the original.
  *       The resulting Param is a fresh mapping of the payload.
}
procedure TMemory_Param_Tool.DecryptFromMem(m64: TMem64);
var
  i32: Integer;
begin
  if m64.ProtectedMode then
    begin
      m64.Position := 0;
      apiName := m64.ReadString;
      Param.Size := m64.ReadInt32;
      m64.ReadPtr(Param.Memory, Param.Size);
      Param.Position := 0;
    end
  else
    begin
      tmp.SwapInstance(m64);
      tmp.Position := 0;
      apiName := tmp.ReadString;
      i32 := tmp.ReadInt32;
      Param.Mapping(tmp.PosAsPtr, i32);
      Param.Position := 0;
    end;
end;

{ * Get_apiName: Extracts just the API name from a packed TMem64 without full decoding.
  * This is a lightweight operation that only reads the name prefix.
  * @Param m64: The packed TMem64.
  * @Returns: The API name as a TAPI_String.
  * @Note The current position of m64 is preserved.
}
class function TMemory_Param_Tool.Get_apiName(m64: TMem64): TAPI_String;
var
  bak_: Int64;
begin
  bak_ := m64.Position;
  m64.Position := 0;
  Result := m64.ReadString;
  m64.Position := bak_;
end;

{ ----------------------------------------------------------------------------
  TAPI_Info Implementation
  ---------------------------------------------------------------------------- }

{ * Constructor: Initializes all fields to default empty values.
  * @Note Mode is set to amUnknow, callbacks are nil.
}
constructor TAPI_Info.Create;
begin
  inherited Create;
  Name := '';
  Desc := '';
  Mode := TAPI_Mode.amUnknow;
  Trigger := nil;
  On_Call := nil;
  On_Notify := nil;
end;

destructor TAPI_Info.Destroy;
begin
  inherited Destroy;
end;

{ ----------------------------------------------------------------------------
  TAPI_Info_Pool Implementation
  ---------------------------------------------------------------------------- }

{ * DoFree: Called when an entry is removed from the pool. Frees the TAPI_Info
  * object stored as Value.
  * @Param Key: The API name (unused).
  * @Param Value: The TAPI_Info object to be freed.
}
procedure TAPI_Info_Pool.DoFree(var Key: SystemString; var Value: TAPI_Info);
begin
  DisposeObjectAndNil(Value);
  inherited;
end;

{ ----------------------------------------------------------------------------
  TAPI_Data Implementation
  ---------------------------------------------------------------------------- }

{ * Init: Sets both Data_Param and Data_Result to nil.
  * @Note Used before allocation to ensure clean state.
}
procedure TAPI_Data.Init;
begin
  Data_Param := nil;
  Data_Result := nil;
end;

{ * New_Param: Creates a new TAPI_Data record as an input parameter.
  * @Param apiName: The name of the API to call.
  * @Returns: A pointer to a newly allocated TAPI_Data record.
  *          The caller must free it with Free_Data.
}
class function TAPI_Data.New_Param(apiName: TAPI_String): PAPI_Data;
var
  p: PAPI_Data;
begin
  New(p);
  p^.Init;
  p^.Data_Param := TMemory_Param_Tool.Create;
  p^.Data_Param.apiName := apiName;
  Result := p;
end;

{ * New_Param_From: Creates a new TAPI_Data record as an input parameter by
  * unpacking a packed TMem64 block.
  * @Param Data_: The packed TMem64.
  * @Returns: A pointer to a new TAPI_Data record.
}
class function TAPI_Data.New_Param_From(Data_: TMem64): PAPI_Data;
var
  p: PAPI_Data;
begin
  New(p);
  p^.Init;
  p^.Data_Param := TMemory_Param_Tool.Create;
  p^.Data_Param.DecryptFromMem(Data_);
  Result := p;
end;

{ * New_Result: Creates a new empty output result TAPI_Data.
  * @Returns: A pointer to a new record with a fresh TMem64 for the result.
}
class function TAPI_Data.New_Result: PAPI_Data;
var
  p: PAPI_Data;
begin
  New(p);
  p^.Init;
  p^.Data_Result := TMem64.Create;
  Result := p;
end;

{ * New_Result_From: Creates a new output result TAPI_Data, taking ownership
  * of the provided TMem64.
  * @Param Data_: The TMem64 that holds the result data.
  * @Returns: A pointer to a new record.
}
class function TAPI_Data.New_Result_From(Data_: TMem64): PAPI_Data;
var
  p: PAPI_Data;
begin
  New(p);
  p^.Init;
  p^.Data_Result := Data_;
  p^.Data_Result.Position := 0;
  Result := p;
end;

{ * Free_Data: Frees a TAPI_Data record and all its owned objects.
  * @Param hnd: The pointer returned by one of the New_* methods.
  * @Note This will free Data_Param (if any) and Data_Result (if any), then
  *       dispose the record itself.
}
class procedure TAPI_Data.Free_Data(hnd: PAPI_Data);
begin
  DisposeObjectAndNil(hnd^.Data_Param);
  DisposeObjectAndNil(hnd^.Data_Result);
  Dispose(hnd);
end;

{ * GetBuffer: Returns a pointer to the raw data buffer.
  * @Returns: Pointer to the internal buffer, or nil if neither field is set.
  * @Note Read‑only access; do not free the pointer.
}
function TAPI_Data.GetBuffer: Pointer;
begin
  Result := nil;
  if Data_Param <> nil then
      Result := Data_Param.Param.Memory
  else if Data_Result <> nil then
      Result := Data_Result.Memory;
end;

{ * WriteBuff: Writes data to the buffer at the current position.
  * @Param Buff: Source data pointer.
  * @Param Size: Number of bytes to write.
  * @Returns: Number of bytes actually written.
  * @Note The buffer automatically enlarges if needed.
}
function TAPI_Data.WriteBuff(Buff: Pointer; Size: Int64): Int64;
begin
  Result := 0;
  if Data_Param <> nil then
      Result := Data_Param.Param.WritePtr(Buff, Size)
  else if Data_Result <> nil then
      Result := Data_Result.WritePtr(Buff, Size);
end;

{ * ReadBuff: Reads data from the buffer at the current position.
  * @Param Buff: Destination buffer pointer.
  * @Param Size: Maximum bytes to read.
  * @Returns: Number of bytes actually read.
  * @Note The position advances by the number of bytes read.
}
function TAPI_Data.ReadBuff(Buff: Pointer; Size: Int64): Int64;
begin
  Result := 0;
  if Data_Param <> nil then
      Result := Data_Param.Param.ReadPtr(Buff, Size)
  else if Data_Result <> nil then
      Result := Data_Result.ReadPtr(Buff, Size);
end;

{ * Get_Pos: Returns the current read/write position.
  * @Returns: The position in bytes.
}
function TAPI_Data.Get_Pos: Int64;
begin
  Result := 0;
  if Data_Param <> nil then
      Result := Data_Param.Param.Position
  else if Data_Result <> nil then
      Result := Data_Result.Position;
end;

{ * Set_Pos: Sets the current read/write position.
  * @Param Pos_: New position (must be >= 0).
  * @Note If the position exceeds the current size, the buffer is extended with zeros.
}
procedure TAPI_Data.Set_Pos(Pos_: Int64);
begin
  if Data_Param <> nil then
      Data_Param.Param.Position := Pos_
  else if Data_Result <> nil then
      Data_Result.Position := Pos_;
end;

{ * Get_Size: Returns the total size of the data buffer.
  * @Returns: The size in bytes.
}
function TAPI_Data.Get_Size: Int64;
begin
  Result := 0;
  if Data_Param <> nil then
      Result := Data_Param.Param.Size
  else if Data_Result <> nil then
      Result := Data_Result.Size;
end;

{ * Set_Size: Resizes the data buffer.
  * @Param Size_: New size. If larger, the added space is uninitialized.
  *               If smaller, data beyond the new size is discarded.
}
procedure TAPI_Data.Set_Size(Size_: Int64);
begin
  if Data_Param <> nil then
      Data_Param.Param.Size := Size_
  else if Data_Result <> nil then
      Data_Result.Size := Size_;
end;

{ ----------------------------------------------------------------------------
  TAPI_Tool Implementation
  ---------------------------------------------------------------------------- }

{ * Constructor: Creates the API pool with 255 hash buckets.
  * @Note The pool is thread‑safe (uses TString_Big_Hash_Pair_Pool).
}
constructor TAPI_Tool.Create;
begin
  inherited Create;
  API_Pool := TAPI_Info_Pool.Create($FF, nil);
end;

{ * Destructor: Frees the API pool and all registered API metadata.
}
destructor TAPI_Tool.Destroy;
begin
  DisposeObject(API_Pool);
  inherited Destroy;
end;

{ * Reg_Call: Registers a new Call API in the pool.
  * @Param apiName: Unique name (case‑sensitive).
  * @Param Desc: Optional description.
  * @Param Trigger: User data passed to the callback.
  * @Param On_Call: The callback function (cdecl).
  * @Returns: True if registration succeeded, False if the name already exists.
  * @Note Also triggers an update event via APP.DoChange().
}
function TAPI_Tool.Reg_Call(apiName, Desc: TAPI_String; Trigger: Pointer; On_Call: TAPI_Call): Boolean;
var
  api_: TAPI_Info;
begin
  Result := False;
  if API_Pool.Exists_Key(apiName) then
      exit;
  api_ := TAPI_Info.Create;
  api_.Name := apiName;
  api_.Desc := Desc;
  api_.Mode := TAPI_Mode.amCall;
  api_.Trigger := Trigger;
  api_.On_Call := On_Call;
  API_Pool.Add(apiName, api_, False);
  APP.DoChange();
  Result := True;
end;

{ * Reg_Notify: Registers a new Notify API.
  * @Param apiName: Unique name.
  * @Param Desc: Description.
  * @Param Trigger: User data.
  * @Param On_Notify: The callback function (cdecl).
  * @Returns: True on success, False if name already exists.
  * @Note Triggers an update event via APP.DoChange().
}
function TAPI_Tool.Reg_Notify(apiName, Desc: TAPI_String; Trigger: Pointer; On_Notify: TAPI_Notify): Boolean;
var
  api_: TAPI_Info;
begin
  Result := False;
  if API_Pool.Exists_Key(apiName) then
      exit;
  api_ := TAPI_Info.Create;
  api_.Name := apiName;
  api_.Desc := Desc;
  api_.Mode := TAPI_Mode.amNotify;
  api_.Trigger := Trigger;
  api_.On_Notify := On_Notify;
  API_Pool.Add(apiName, api_, False);
  APP.DoChange();
  Result := True;
end;

{ * UnReg: Unregisters an API by name.
  * @Param apiName: The name of the API to remove.
  * @Returns: True if the API was found and removed, False otherwise.
  * @Note Triggers an update event via APP.DoChange().
}
function TAPI_Tool.UnReg(apiName: TAPI_String): Boolean;
var
  api_: TAPI_Info;
begin
  Result := False;
  if not API_Pool.Exists_Key(apiName) then
      exit;
  API_Pool.Delete(apiName);
  APP.DoChange();
  Result := True;
end;

{ * Execute_Call: Executes a Call API synchronously.
  * @Param Memory_Param: A packed TMem64 (should be created with TMemory_Param_Tool).
  * @Returns: A new TMem64 containing the result. The caller must free it.
  *          If the API is not found or an error occurs, an empty TMem64 is returned.
  * @Note The function unpacks the input, looks up the API by name, invokes the
  *       callback, and transfers the output result to the returned TMem64.
  *       The input and output TAPI_Data records are freed internally.
}
function TAPI_Tool.Execute_Call(Memory_Param: TMem64): TMem64;
var
  api_: TAPI_Info;
  input_, output_: PAPI_Data;
begin
  input_ := TAPI_Data.New_Param_From(Memory_Param);
  output_ := TAPI_Data.New_Result;
  Result := TMem64.Create;
  try
    api_ := API_Pool.Get_Default_Value(input_.Data_Param.apiName, nil);
    if api_ = nil then
      begin
        DoStatus('no found api "%s"', [input_.Data_Param.apiName.Text]);
        exit;
      end;

    case api_.Mode of
      amCall:
        begin
          try
            if Assigned(api_.On_Call) then
                api_.On_Call(api_.Trigger, input_, output_);
          except
              DoStatus('execute call-mode api "%s" (stdcall) execpet!', [input_.Data_Param.apiName.Text]);
          end;
        end;
      else
        begin
          DoStatus('Illegal api "%s"', [input_.Data_Param.apiName.Text]);
          exit;
        end;
    end;

  finally
    Result.SwapInstance(output_.Data_Result);
    TAPI_Data.Free_Data(input_);
    TAPI_Data.Free_Data(output_);
  end;
end;

{ * Execute_Notify: Executes a Notify API synchronously (the callback runs in
  * the calling thread).
  * @Param Memory_Param: A packed TMem64.
  * @Note The input is unpacked, the callback is invoked, and the input record
  *       is freed. No result is produced.
}
procedure TAPI_Tool.Execute_Notify(Memory_Param: TMem64);
var
  api_: TAPI_Info;
  input_: PAPI_Data;
begin
  input_ := TAPI_Data.New_Param_From(Memory_Param);
  try
    api_ := API_Pool.Get_Default_Value(input_.Data_Param.apiName, nil);
    if api_ = nil then
      begin
        DoStatus('no found api "%s"', [input_.Data_Param.apiName.Text]);
        exit;
      end;

    case api_.Mode of
      amNotify:
        begin
          try
            if Assigned(api_.On_Notify) then
                api_.On_Notify(api_.Trigger, input_);
          except
              DoStatus('execute notify-mode api "%s" (stdcall) execpet!', [input_.Data_Param.apiName.Text]);
          end;
        end;
      else
        begin
          DoStatus('Illegal api "%s"', [input_.Data_Param.apiName.Text]);
          exit;
        end;
    end;

  finally
      TAPI_Data.Free_Data(input_);
  end;
end;

{ ----------------------------------------------------------------------------
  TAPI_APP Implementation
  ---------------------------------------------------------------------------- }

{ * Do_APIReg_Event__: Internal method that broadcasts update events to all
  * subscribers. It locks the event pool, iterates over all registered callbacks,
  * and invokes each one, catching exceptions.
  * This is called on the main thread via a timer.
}
procedure TAPI_APP.Do_APIReg_Event__;
begin
  FAPIUpdate_Event_Pool.Lock;
  if FAPIUpdate_Event_Pool.Num > 0 then
    with FAPIUpdate_Event_Pool.Repeat_ do
      repeat
        try
          if Assigned(Queue^.Data^.Data.Second) then
              Queue^.Data^.Data.Second(Self);
        except
        end;
      until not next;
  FAPIUpdate_Event_Pool.UnLock;
end;

{ * DoTimer: Timer callback that checks if a change occurred. If FUpdated is True,
  * it posts Do_APIReg_Event__ to the main thread (via MainThreadPost) and resets
  * the flag. This ensures that multiple changes within a short period are coalesced.
}
procedure TAPI_APP.DoTimer;
begin
  if FUpdated then
    begin
      MainThreadPost.PostM_NP(Do_APIReg_Event__);
      FUpdated := False;
    end;
end;

{ * Constructor: Initializes the application with empty Name and Desc, creates
  * the API tool, and starts a 1‑second timer to handle update coalescing.
  * @Note The timer is managed by the Z.Core timer system (Subscribe_Timer_M).
}
constructor TAPI_APP.Create;
begin
  inherited Create;
  Name := '';
  Desc := '';
  API := TAPI_Tool.Create;
  API.APP := Self;
  FAPIUpdate_Event_Pool := TAPIUpdate_Event_Pool.Create($FF, nil);
  FUpdated := False;
  Subscribe_Timer_M(Self, 1000, DoTimer);
end;

{ * Destructor: Stops the timer, frees the API tool and event pool.
  * @Note The timer is removed automatically by Remove_Timer.
}
destructor TAPI_APP.Destroy;
begin
  Remove_Timer(Self);
  DisposeObject(API);
  DisposeObject(FAPIUpdate_Event_Pool);
  inherited Destroy;
end;

{ * DoChange: Marks the application as changed and resets the timer so that
  * the update event will be broadcast shortly. This is called whenever the
  * API list changes (Reg_*, UnReg).
}
procedure TAPI_APP.DoChange();
begin
  FUpdated := True;
  Reset_Timer(Self);
end;

{ * Subscribe_Update: Subscribes a listener to update events.
  * @Param Bind: An object that uniquely identifies the subscriber (used for removal).
  * @Param OnUpdate: The callback to invoke when the app changes.
  * @Note If Bind already exists, the callback is overwritten.
}
procedure TAPI_APP.Subscribe_Update(Bind: TCore_Object; OnUpdate: TOn_API_Update);
begin
  FAPIUpdate_Event_Pool.Add(Bind, OnUpdate, True);
end;

{ * Remove_Update: Unsubscribes a previously subscribed object.
  * @Param Bind: The same object used in Subscribe_Update.
}
procedure TAPI_APP.Remove_Update(Bind: TCore_Object);
begin
  FAPIUpdate_Event_Pool.Delete(Bind);
end;

end.
