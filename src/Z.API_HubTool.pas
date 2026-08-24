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
  * The unit also defines an opaque handle (TDataHnd___) and an application
  * handle (TAppHnd) that are used by the C ABI export layer (in the separate
  * unit API_HubTool_Export). This allows the framework to be called from
  * other languages (C, C++, Python, etc.) via a cdecl interface.
  *
  * All public classes and methods are designed to be thread‑safe, except for
  * the TMemory_Param_Tool which is not thread‑safe when shared between
  * threads. Use separate instances per thread or synchronise access.
  *
  * Dependencies:
  *   – Z.Core                 (foundation: threads, containers, memory)
  *   – Z.PascalStrings        (Pascal string handling)
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
  *     Param, Result: TMem64;
  *     Tool: TMemory_Param_Tool;
  *   begin
  *     App := TAPI_APP.Create;                 // create an app instance
  *     App.Name := 'MyApp';                    // set its name
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
  *     Tool := TMemory_Param_Tool.Create;
  *     Tool.apiName := 'echo';                  // set the API name
  *     Tool.Param.WriteString('Hello world');   // write payload
  *
  *     // Pack the parameter into a TMem64.
  *     Param := TMem64.Create;
  *     Tool.EncryptToMem(Param);                // encode apiName and payload
  *     Tool.Free;                               // free the helper
  *
  *     // Execute the call locally.
  *     Result := App.API.Execute_Call(Param);   // synchronous call, returns result
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
  *   var Tool := TMemory_Param_Tool.Create;
  *   Tool.apiName := 'log';
  *   Tool.Param.WriteString('Hello from notify');
  *   var NotifyParam := TMem64.Create;
  *   Tool.EncryptToMem(NotifyParam);
  *   Tool.Free;
  *   App.API.Execute_Notify(NotifyParam);      // asynchronous, no result
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
  { * TAPI_String: Unicode string type used for all textual identifiers and descriptions.
    * Alias for TUPascalString, providing high‑performance Unicode handling.
    * Used for API names, descriptions, and all text data exchanged by the framework. }
  TAPI_String = TUPascalString;

  { * TAPI_Mode: Classification of an API operation.
    * - amUnknow : Unspecified, placeholder or error state.
    * - amCall   : Request‑response style. Caller expects a result.
    *              Callback receives Input and Output handles.
    * - amNotify : One‑way message. Caller does not wait for response.
    *              Callback receives only an Input handle. }
  TAPI_Mode = (
    amUnknow = 0,
    amCall = 1,
    amNotify = 2
    );

  { * TMemory_Param_Tool: Packs an API name and binary parameter into a TMem64.
    * Packed format: [API name as Pascal string] + [4‑byte payload size] + [payload bytes].
    * Used for both local and remote calls.
    * Not thread‑safe; create separate instances per thread or synchronise access.
    *
    * @Field apiName: Name of the target API.
    * @Field Param: Binary payload for the API call/notification.
    * @Constructor Create: Initializes empty fields and internal temp buffer.
    * @Destructor Destroy: Frees Param and temp buffer.
    * @Method EncryptToMem: Encodes current apiName and Param into a TMem64.
    * @Method DecryptFromMem: Decodes a TMem64 block back into apiName and Param.
    * @ClassMethod Get_apiName: Extracts only the API name from a packed block. }
  TMemory_Param_Tool = class
  private
    tmp: TMem64; // internal buffer used during decoding to avoid reallocation
  public
    apiName: TAPI_String; // name of the target API
    Param: TMem64; // binary payload for the API call/notification

    constructor Create;
    destructor Destroy; override;

    { * Encodes the current apiName and Param into the provided TMem64.
      * The format is: Pascal‑string for apiName, then 32‑bit size, then raw bytes.
      * @Param m64: Destination TMem64. It is cleared before writing.
      * @Example:
      *   var Tool := TMemory_Param_Tool.Create;
      *   Tool.apiName := 'echo';
      *   Tool.Param.WriteString('Hello');
      *   var m64 := TMem64.Create;
      *   Tool.EncryptToMem(m64);   // m64 now contains packed data
      *   Tool.Free;
      *   // m64 can be sent over network or passed to Execute_Call.
      *   DisposeObject(m64); }
    procedure EncryptToMem(m64: TMem64);

    { * Decodes a TMem64 block that was previously packed by EncryptToMem.
      * Restores apiName and Param.
      * @Param m64: Source TMem64 containing the packed data.
      * @Note If m64 is in protected mode (read‑only), we read directly from it.
      *       Otherwise, we swap its content into tmp to avoid modifying the original.
      *       The resulting Param is a fresh mapping of the payload.
      * @Example:
      *   var Tool := TMemory_Param_Tool.Create;
      *   Tool.DecryptFromMem(packedM64);   // restores apiName and Param
      *   // Now Tool.apiName and Tool.Param contain the decoded data. }
    procedure DecryptFromMem(m64: TMem64);

    { * Extracts just the API name from a packed TMem64 without full decoding.
      * Lightweight operation; does not modify m64's position.
      * @Param m64: The packed TMem64.
      * @Returns: The API name as a TAPI_String.
      * @Example:
      *   var name := TMemory_Param_Tool.Get_apiName(packedM64);
      *   // name is the API name without decoding the whole payload. }
    class function Get_apiName(m64: TMem64): TAPI_String;
  end;

  { * TAPI_Info: Metadata record for a single registered API.
    * Stores name, description, mode (Call/Notify), user‑supplied trigger,
    * and the appropriate cdecl callback.
    * Stored in TAPI_Info_Pool. }
  TAPI_Info = class
  public
    Name: TAPI_String; // Unique identifier of the API (case‑sensitive)
    Desc: TAPI_String; // Human‑readable description
    Mode: TAPI_Mode; // Whether this is a Call or Notify API
    Trigger: Pointer; // User‑defined data passed back to the callback
    On_Call: TAPI_Call; // Callback for Call‑mode APIs (cdecl)
    On_Notify: TAPI_Notify; // Callback for Notify‑mode APIs (cdecl)

    constructor Create;
    destructor Destroy; override;
  end;

  { * TAPI_Info_Pool: Thread‑safe hash map storing TAPI_Info objects keyed by API name.
    * Used by TAPI_Tool to manage API registry.
    * Automatically frees TAPI_Info objects when entries are removed.
    * @InheritsFrom TString_Big_Hash_Pair_Pool<TAPI_Info>
    * @Method DoFree: Frees the TAPI_Info object on removal. }
  TAPI_Info_Pool = class(TString_Big_Hash_Pair_Pool<TAPI_Info>)
  public
    procedure DoFree(var Key: SystemString; var Value: TAPI_Info); override;
  end;

  { * PAPI_Data: Pointer to a TAPI_Data record. Used as opaque TDataHnd___ in C export layer.
    * External code must never dereference; only pass to API functions. }
  PAPI_Data = ^TAPI_Data;

  TAPI_Data_Order = class(TOrderStruct<PAPI_Data>)
  end;

  { * TAPI_Data_Pool: Global pool that tracks all active TAPI_Data handles.
    * It stores each handle with a timestamp of its last usage.
    * Periodically (every 5 seconds) it scans and automatically frees handles
    * that have been idle for more than 5 minutes. This acts as a garbage collector
    * for handles that were not explicitly freed.
    *
    * @Field Update_Time__: Last time the Progress method ran (used for throttling).
    * @Method CreateAfter: Initializes Update_Time__.
    * @Method Progress: Scans the pool and frees idle handles.
    * @Method Free_All_Hnd: Frees all handles in the pool.
    * @Method Update_Hnd_For_Usage: Updates the timestamp for a given handle. }
  TAPI_Data_Pool = class(TBig_Hash_Pair_Pool<PAPI_Data, TTimeTick>)
  private
    Update_Time__: TTimeTick; // last time Progress() was executed (for throttling)
  public
    procedure CreateAfter; override;
    procedure Progress;
    procedure Free_All_Hnd;
    procedure Update_Hnd_For_Usage(hnd: PAPI_Data);
  end;

  { * TAPI_Data: Represents either a parameter or a result for an API invocation.
    * Discriminated union: either Data_Param (input) or Data_Result (output) is non‑nil.
    * Static factory methods simplify creation and destruction.
    *
    * @Field Data_Param: Non‑nil if input parameter (TMemory_Param_Tool).
    * @Field Data_Result: Non‑nil if output result (TMem64).
    * @Field Data_Info: Debug info string (used for logging).
    * @Method Init: Initialises record to nil pointers.
    * @ClassMethod New_Param: Creates input parameter record with given API name.
    * @ClassMethod New_Param_From: Creates input parameter by unpacking a packed TMem64.
    * @ClassMethod New_Result: Creates empty output result record.
    * @ClassMethod New_Result_From: Creates output result taking ownership of a TMem64.
    * @ClassMethod Free_Data: Frees TAPI_Data record and all owned objects.
    * @Method GetBuffer: Returns raw data buffer pointer (read‑only).
    * @Method WriteBuff: Writes data to buffer at current position.
    * @Method ReadBuff: Reads data from buffer at current position.
    * @Method Get_Pos: Returns current read/write position.
    * @Method Set_Pos: Sets current read/write position.
    * @Method Get_Size: Returns total size of data buffer.
    * @Method Set_Size: Resizes data buffer. }
  TAPI_Data = record
  public
    Data_Param: TMemory_Param_Tool;
    Data_Result: TMem64;
    Data_Info: TAPI_String;

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

  { * Forward declaration for TAPI_APP (used below). }
  TAPI_APP = class;

  { * TAPI_Tool: Core API registry and execution engine for an application.
    * Maintains a pool of registered APIs and provides methods to invoke them locally.
    * All registration and execution methods are thread‑safe.
    *
    * @Field API_Pool: Thread‑safe hash pool of registered APIs.
    * @Field APP: Back‑reference to the owning application.
    * @Constructor Create: Initializes the API pool.
    * @Destructor Destroy: Frees the API pool.
    * @Method Reg_Call: Registers a new Call API.
    * @Method Reg_Notify: Registers a new Notify API.
    * @Method UnReg: Unregisters an API by name.
    * @Method Execute_Call: Executes a Call API synchronously.
    * @Method Execute_Notify: Executes a Notify API synchronously (callback runs in caller's thread).
    *
    * @Example (registering a call API):
    *   var Tool := TAPI_Tool.Create;
    *   Tool.Reg_Call('add', 'Adds two integers', nil,
    *     procedure(Trigger: Pointer; Input, Output: PAPI_Data)
    *     var
    *       a, b, Sum: Integer;
    *     begin
    *       // read two integers from input
    *       Input.Data_Param.Param.ReadBuffer(@a, SizeOf(a));
    *       Input.Data_Param.Param.ReadBuffer(@b, SizeOf(b));
    *       Sum := a + b;
    *       // write result to output
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
    *   DisposeObject(Tool); }
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
    * Triggered when the application's API list changes (registration/unregistration).
    * Fired on the main thread via a timer.
    * @Param Sender: The TAPI_APP instance that changed. }
  TOn_API_Update = procedure(Sender: TAPI_APP) of object;

  { * TAPIUpdate_Event_Pool: Thread‑safe hash map storing event callbacks keyed by binding object.
    * Used by TAPI_APP to notify subscribers of API list changes.
    * @InheritsFrom TCritical_Big_Hash_Pair_Pool<TCore_Object, TOn_API_Update> }
  TAPIUpdate_Event_Pool = class(TCritical_Big_Hash_Pair_Pool<TCore_Object, TOn_API_Update>)
  end;

  { * TAPI_APP: Logical application exposing a set of APIs.
    * Each app has a unique Name (used for network routing) and Description.
    * Contains a TAPI_Tool instance holding the actual API registry.
    * Notifies subscribers via Subscribe_Update when its API list changes.
    *
    * @Field Name: Unique identifier (case‑sensitive).
    * @Field Desc: Human‑readable description.
    * @Field API: The registry and execution engine (TAPI_Tool).
    * @Constructor Create: Initializes the API tool and event pool, starts a 1‑second timer for coalescing updates.
    * @Destructor Destroy: Frees the API tool and event pool.
    * @Method DoChange: Marks the app as changed and schedules a broadcast.
    * @Method Subscribe_Update: Subscribes a listener to update events.
    * @Method Remove_Update: Unsubscribes a previously subscribed object.
    *
    * @Example:
    *   var App := TAPI_APP.Create;
    *   App.Name := 'MyService';
    *   App.Desc := 'My service description';
    *   App.API.Reg_Call('ping', 'Ping', nil, MyPingCallback);
    *   // Subscribe to changes.
    *   App.Subscribe_Update(MyObject, MyUpdateHandler);
    *   // ... later, when the app changes, MyUpdateHandler will be called. }
  TAPI_APP = class
  private
    FAPIUpdate_Event_Pool: TAPIUpdate_Event_Pool; // stores subscribers and their callbacks
    FUpdated: Boolean; // flag to indicate a change has occurred; reset after broadcast
    procedure Do_APIReg_Event__; // internal broadcast of update events
    procedure DoTimer(); // timer callback that triggers broadcast if changed
  public
    Name: TAPI_String; // unique application identifier
    Desc: TAPI_String; // human‑readable description
    API: TAPI_Tool; // the API registry and execution engine

    constructor Create;
    destructor Destroy; override;

    procedure DoChange(); // marks app as changed, schedules broadcast
    procedure Subscribe_Update(Bind: TCore_Object; OnUpdate: TOn_API_Update);
    procedure Remove_Update(Bind: TCore_Object);
  end;

var
  API_Data_Pool: TAPI_Data_Pool; // global pool for automatic handle recycling
  Running_API_Num: TAtomInt; // global atomic counter of currently executing API calls

implementation

{ ----------------------------------------------------------------------------
  TMemory_Param_Tool Implementation
  ---------------------------------------------------------------------------- }

constructor TMemory_Param_Tool.Create;
{ * Initializes the tool with empty apiName and Param, and creates a temporary
  * internal buffer (tmp) used during decoding to avoid reallocations. }
begin
  inherited Create;
  tmp := TMem64.Create;
  apiName := '';
  Param := TMem64.Create;
end;

destructor TMemory_Param_Tool.Destroy;
{ * Frees the Param payload and the temporary internal buffer. }
begin
  DisposeObject(Param);
  DisposeObject(tmp);
  inherited Destroy;
end;

procedure TMemory_Param_Tool.EncryptToMem(m64: TMem64);
{ * Encodes the current apiName and Param into the provided TMem64.
  * The encoded format is:
  *   - Pascal‑style string (length prefix) for apiName.
  *   - 32‑bit integer for the payload size.
  *   - raw payload bytes.
  * @Param m64: Destination TMem64. It is cleared before writing. }
begin
  m64.Clear;
  m64.WriteString(apiName.Text);
  m64.WriteInt32(Param.Size);
  m64.WritePtr(Param.Memory, Param.Size);
end;

procedure TMemory_Param_Tool.DecryptFromMem(m64: TMem64);
{ * Decodes a TMem64 block that was previously packed by EncryptToMem,
  * restoring apiName and Param.
  * @Param m64: Source TMem64 containing the packed data.
  * @Note If m64 is in protected mode (read‑only), we read directly from it.
  *       Otherwise, we swap its content into tmp to avoid modifying the original.
  *       The resulting Param is a fresh mapping of the payload. }
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

class function TMemory_Param_Tool.Get_apiName(m64: TMem64): TAPI_String;
{ * Extracts just the API name from a packed TMem64 without full decoding.
  * This is a lightweight operation that only reads the name prefix.
  * @Param m64: The packed TMem64.
  * @Returns: The API name as a TAPI_String.
  * @Note The current position of m64 is preserved. }
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

constructor TAPI_Info.Create;
{ * Initializes all fields to default empty values. Mode is set to amUnknow. }
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

procedure TAPI_Info_Pool.DoFree(var Key: SystemString; var Value: TAPI_Info);
{ * Called when an entry is removed from the pool. Frees the TAPI_Info object. }
begin
  DisposeObjectAndNil(Value);
  inherited;
end;

{ ----------------------------------------------------------------------------
  TAPI_Data_Pool Implementation
  ---------------------------------------------------------------------------- }

procedure TAPI_Data_Pool.CreateAfter;
{ * Initializes the Update_Time__ field to the current tick. }
begin
  inherited CreateAfter;
  Update_Time__ := GetTimeTick;
end;

procedure TAPI_Data_Pool.Progress;
{ * Scans the pool and automatically frees handles that have been idle
  * for more than 5 minutes. This runs at most once every 5 seconds.
  * @Note It collects handles to free in a temporary list, then frees them
  *       outside the lock to minimize contention. }
var
  tk: TTimeTick;
  L: TAPI_Data_Order;
begin
  tk := GetTimeTick();
  if tk - Update_Time__ < 5000 then exit; // throttle: run at most every 5s
  Update_Time__ := tk;
  L := TAPI_Data_Order.Create;

  Lock; // acquire the hash map lock
  try
    if Num > 0 then
      with repeat_ do
        repeat
          // Check if the handle's last usage time is older than 5 minutes
          if tk - queue^.Data^.Data.Second > Z.Core.C_Tick_Second * 60 * 5 then
            begin
              L.Push(queue^.Data^.Data.Primary); // collect handle
              Push_To_Recycle_Pool2(queue); // mark entry for removal
            end;
        until not Next;
    Free_Recycle_Pool; // physically remove all marked entries
  finally
    UnLock;
  end;

  // Free the collected handles outside the lock to reduce contention
  if L.Num > 0 then
    begin
      DoStatus('hint: Data handle pool "%d" handles were idle for more than 5 minutes and have been automatically freed.', [L.Num]);
      if L.Num > 5 then
        DoStatus('...');
      repeat
        if L.Num < 5 then
          DoStatus('hint: automatically free handles ' + L.First^.Data^.Data_Info.Text);
        TAPI_Data.Free_Data(L.First^.Data); // actually free the handle
        L.Next;
      until L.Num <= 0;
    end;

  DisposeObject(L);
end;

procedure TAPI_Data_Pool.Free_All_Hnd;
{ * Frees all handles currently in the pool. Used during finalization. }
var
  L: TAPI_Data_Order;
begin
  L := TAPI_Data_Order.Create;

  Lock;
  try
    if Num > 0 then
      with repeat_ do
        repeat
          L.Push(queue^.Data^.Data.Primary);
        until not Next;
    Clear; // clears the hash map without freeing the handles themselves
  finally
    UnLock;
  end;

  // Free all collected handles outside the lock
  if L.Num > 0 then
    begin
      if L.Num > 5 then
        begin
          DoStatus('hint: Data handle pool "%d" do automatically freed.', [L.Num]);
          DoStatus('...');
        end;
      repeat
        if L.Num < 5 then
          DoStatus('hint: automatically free handles ' + L.First^.Data^.Data_Info.Text);
        TAPI_Data.Free_Data(L.First^.Data);
        L.Next;
      until L.Num <= 0;
    end;

  DisposeObject(L);
end;

procedure TAPI_Data_Pool.Update_Hnd_For_Usage(hnd: PAPI_Data);
{ * Updates the timestamp for the given handle to the current time,
  * effectively resetting its idle timer.
  * @Param hnd: The handle to update.
  * @Note This is called on every read/write operation on a handle. }
var
  p: PValue_;
begin
  Lock;
  try
    p := Get_Value_Ptr(hnd);
    if p <> nil then
      p^ := GetTimeTick;
  finally
    UnLock;
  end;
end;

{ ----------------------------------------------------------------------------
  TAPI_Data Implementation
  ---------------------------------------------------------------------------- }

procedure TAPI_Data.Init;
{ * Sets both Data_Param and Data_Result to nil. Used before allocation. }
begin
  Data_Param := nil;
  Data_Result := nil;
  Data_Info := '';
end;

class function TAPI_Data.New_Param(apiName: TAPI_String): PAPI_Data;
{ * Creates a new TAPI_Data record as an input parameter.
  * @Param apiName: The name of the API to call.
  * @Returns: A pointer to a newly allocated TAPI_Data record.
  *          The caller must free it with Free_Data. }
var
  p: PAPI_Data;
begin
  New(p);
  p^.Init;
  p^.Data_Param := TMemory_Param_Tool.Create;
  p^.Data_Param.apiName := apiName;
  p^.Data_Info := PFormat('api "%s" parameter.', [apiName.Text]);

  API_Data_Pool.Lock;
  API_Data_Pool.Add(p, GetTimeTick(), False);
  API_Data_Pool.UnLock;

  Result := p;
end;

class function TAPI_Data.New_Param_From(Data_: TMem64): PAPI_Data;
{ * Creates a new TAPI_Data record as an input parameter by unpacking a packed TMem64 block.
  * @Param Data_: The packed TMem64.
  * @Returns: A pointer to a new TAPI_Data record. }
var
  p: PAPI_Data;
begin
  New(p);
  p^.Init;
  p^.Data_Param := TMemory_Param_Tool.Create;
  p^.Data_Param.DecryptFromMem(Data_);

  API_Data_Pool.Lock;
  API_Data_Pool.Add(p, GetTimeTick(), False);
  API_Data_Pool.UnLock;

  Result := p;
end;

class function TAPI_Data.New_Result: PAPI_Data;
{ * Creates a new empty output result TAPI_Data.
  * @Returns: A pointer to a new record with a fresh TMem64 for the result. }
var
  p: PAPI_Data;
begin
  New(p);
  p^.Init;
  p^.Data_Result := TMem64.Create;

  API_Data_Pool.Lock;
  API_Data_Pool.Add(p, GetTimeTick(), False);
  API_Data_Pool.UnLock;

  Result := p;
end;

class function TAPI_Data.New_Result_From(Data_: TMem64): PAPI_Data;
{ * Creates a new output result TAPI_Data, taking ownership of the provided TMem64.
  * @Param Data_: The TMem64 that holds the result data.
  * @Returns: A pointer to a new record. }
var
  p: PAPI_Data;
begin
  New(p);
  p^.Init;
  p^.Data_Result := Data_;
  p^.Data_Result.Position := 0;

  API_Data_Pool.Lock;
  API_Data_Pool.Add(p, GetTimeTick(), False);
  API_Data_Pool.UnLock;

  Result := p;
end;

class procedure TAPI_Data.Free_Data(hnd: PAPI_Data);
{ * Frees a TAPI_Data record and all its owned objects.
  * @Param hnd: The pointer returned by one of the New_* methods.
  * @Note This will free Data_Param (if any) and Data_Result (if any), then dispose the record itself.
  *       It also removes the handle from the global pool. }
begin
  if hnd = nil then exit;

  API_Data_Pool.Lock;
  API_Data_Pool.Delete(hnd);
  API_Data_Pool.UnLock;

  hnd^.Data_Info := '';
  DisposeObjectAndNil(hnd^.Data_Param);
  DisposeObjectAndNil(hnd^.Data_Result);
  Dispose(hnd);
end;

function TAPI_Data.GetBuffer: Pointer;
{ * Returns a pointer to the raw data buffer. Read‑only; do not free the pointer.
  * @Returns: Pointer to the internal buffer, or nil if neither field is set. }
begin
  Result := nil;
  if Data_Param <> nil then
    Result := Data_Param.Param.Memory
  else if Data_Result <> nil then
    Result := Data_Result.Memory;
end;

function TAPI_Data.WriteBuff(Buff: Pointer; Size: Int64): Int64;
{ * Writes data to the buffer at the current position. The buffer automatically enlarges if needed.
  * @Param Buff: Source data pointer.
  * @Param Size: Number of bytes to write.
  * @Returns: Number of bytes actually written. }
begin
  Result := 0;
  if Data_Param <> nil then
    Result := Data_Param.Param.WritePtr(Buff, Size)
  else if Data_Result <> nil then
    Result := Data_Result.WritePtr(Buff, Size);
end;

function TAPI_Data.ReadBuff(Buff: Pointer; Size: Int64): Int64;
{ * Reads data from the buffer at the current position. The position advances by the number of bytes read.
  * @Param Buff: Destination buffer pointer.
  * @Param Size: Maximum bytes to read.
  * @Returns: Number of bytes actually read. }
begin
  Result := 0;
  if Data_Param <> nil then
    Result := Data_Param.Param.ReadPtr(Buff, Size)
  else if Data_Result <> nil then
    Result := Data_Result.ReadPtr(Buff, Size);
end;

function TAPI_Data.Get_Pos: Int64;
{ * Returns the current read/write position in bytes. }
begin
  Result := 0;
  if Data_Param <> nil then
    Result := Data_Param.Param.Position
  else if Data_Result <> nil then
    Result := Data_Result.Position;
end;

procedure TAPI_Data.Set_Pos(Pos_: Int64);
{ * Sets the current read/write position. If the position exceeds the current size, the buffer is extended with zeros.
  * @Param Pos_: New position (must be >= 0). }
begin
  if Data_Param <> nil then
    Data_Param.Param.Position := Pos_
  else if Data_Result <> nil then
    Data_Result.Position := Pos_;
end;

function TAPI_Data.Get_Size: Int64;
{ * Returns the total size of the data buffer in bytes. }
begin
  Result := 0;
  if Data_Param <> nil then
    Result := Data_Param.Param.Size
  else if Data_Result <> nil then
    Result := Data_Result.Size;
end;

procedure TAPI_Data.Set_Size(Size_: Int64);
{ * Resizes the data buffer. If larger, the added space is uninitialized; if smaller, data beyond the new size is discarded.
  * @Param Size_: New size. }
begin
  if Data_Param <> nil then
    Data_Param.Param.Size := Size_
  else if Data_Result <> nil then
    Data_Result.Size := Size_;
end;

{ ----------------------------------------------------------------------------
  TAPI_Tool Implementation
  ---------------------------------------------------------------------------- }

constructor TAPI_Tool.Create;
{ * Creates the API pool with 255 hash buckets. The pool is thread‑safe. }
begin
  inherited Create;
  API_Pool := TAPI_Info_Pool.Create($FF, nil);
end;

destructor TAPI_Tool.Destroy;
{ * Frees the API pool and all registered API metadata. }
begin
  DisposeObject(API_Pool);
  inherited Destroy;
end;

function TAPI_Tool.Reg_Call(apiName, Desc: TAPI_String; Trigger: Pointer; On_Call: TAPI_Call): Boolean;
{ * Registers a new Call API in the pool.
  * @Param apiName: Unique name (case‑sensitive).
  * @Param Desc: Optional description.
  * @Param Trigger: User data passed to the callback.
  * @Param On_Call: The callback function (cdecl).
  * @Returns: True if registration succeeded, False if the name already exists.
  * @Note Also triggers an update event via APP.DoChange(). }
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

function TAPI_Tool.Reg_Notify(apiName, Desc: TAPI_String; Trigger: Pointer; On_Notify: TAPI_Notify): Boolean;
{ * Registers a new Notify API.
  * @Param apiName: Unique name.
  * @Param Desc: Description.
  * @Param Trigger: User data.
  * @Param On_Notify: The callback function (cdecl).
  * @Returns: True on success, False if name already exists.
  * @Note Triggers an update event via APP.DoChange(). }
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

function TAPI_Tool.UnReg(apiName: TAPI_String): Boolean;
{ * Unregisters an API by name.
  * @Param apiName: The name of the API to remove.
  * @Returns: True if the API was found and removed, False otherwise.
  * @Note Triggers an update event via APP.DoChange(). }
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

function TAPI_Tool.Execute_Call(Memory_Param: TMem64): TMem64;
{ * Executes a Call API synchronously.
  * @Param Memory_Param: A packed TMem64 (should be created with TMemory_Param_Tool).
  * @Returns: A new TMem64 containing the result. The caller must free it.
  *          If the API is not found or an error occurs, an empty TMem64 is returned.
  * @Note The function unpacks the input, looks up the API by name, invokes the
  *       callback, and transfers the output result to the returned TMem64.
  *       The input and output TAPI_Data records are freed internally. }
var
  api_: TAPI_Info;
  input_, output_: PAPI_Data;
  bak_input_, bak_output_: TAPI_Data;
begin
  Running_API_Num.UnLock(Running_API_Num.LockP^ + 1); // increment active call counter
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

    bak_input_ := input_^;
    bak_output_ := output_^;

    case api_.Mode of
      amCall:
        begin
          try
            if Assigned(api_.On_Call) then
              begin
                api_.On_Call(api_.Trigger, input_, output_);
                input_^ := bak_input_;
                output_^ := bak_output_;
              end;
          except
            DoStatus('execute call-mode api "%s" (stdcall) execpet!', [input_.Data_Param.apiName.Text]);
            input_^ := bak_input_;
            output_^ := bak_output_;
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
    Running_API_Num.UnLock(Running_API_Num.LockP^ - 1); // decrement active call counter
  end;
end;

procedure TAPI_Tool.Execute_Notify(Memory_Param: TMem64);
{ * Executes a Notify API synchronously (the callback runs in the calling thread).
  * @Param Memory_Param: A packed TMem64.
  * @Note The input is unpacked, the callback is invoked, and the input record
  *       is freed. No result is produced. }
var
  api_: TAPI_Info;
  input_: PAPI_Data;
  bak_input_: TAPI_Data;
begin
  Running_API_Num.UnLock(Running_API_Num.LockP^ + 1);
  input_ := TAPI_Data.New_Param_From(Memory_Param);
  try
    api_ := API_Pool.Get_Default_Value(input_.Data_Param.apiName, nil);
    if api_ = nil then
      begin
        DoStatus('no found api "%s"', [input_.Data_Param.apiName.Text]);
        exit;
      end;

    bak_input_ := input_^;

    case api_.Mode of
      amNotify:
        begin
          try
            if Assigned(api_.On_Notify) then
              begin
                api_.On_Notify(api_.Trigger, input_);
                input_^ := bak_input_;
              end;
          except
            DoStatus('execute notify-mode api "%s" (stdcall) execpet!', [input_.Data_Param.apiName.Text]);
            input_^ := bak_input_;
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
    Running_API_Num.UnLock(Running_API_Num.LockP^ - 1);
  end;
end;

{ ----------------------------------------------------------------------------
  TAPI_APP Implementation
  ---------------------------------------------------------------------------- }

procedure TAPI_APP.Do_APIReg_Event__;
{ * Internal method that broadcasts update events to all subscribers.
  * Locks the event pool, iterates over all registered callbacks,
  * and invokes each one, catching exceptions.
  * This is called on the main thread via a timer. }
begin
  FAPIUpdate_Event_Pool.Lock;
  if FAPIUpdate_Event_Pool.Num > 0 then
    with FAPIUpdate_Event_Pool.repeat_ do
      repeat
        try
          if Assigned(queue^.Data^.Data.Second) then
            queue^.Data^.Data.Second(Self);
        except
        end;
      until not Next;
  FAPIUpdate_Event_Pool.UnLock;
end;

procedure TAPI_APP.DoTimer;
{ * Timer callback that checks if a change occurred. If FUpdated is True,
  * it posts Do_APIReg_Event__ to the main thread (via MainThreadPost) and resets
  * the flag. This ensures that multiple changes within a short period are coalesced. }
begin
  if FUpdated then
    begin
      MainThreadPost.PostM_NP(Do_APIReg_Event__);
      FUpdated := False;
    end;
end;

constructor TAPI_APP.Create;
{ * Initializes the application with empty Name and Desc, creates the API tool,
  * and starts a 1‑second timer to handle update coalescing.
  * @Note The timer is managed by the Z.Core timer system (Subscribe_Timer_M). }
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

destructor TAPI_APP.Destroy;
{ * Stops the timer, frees the API tool and event pool.
  * @Note The timer is removed automatically by Remove_Timer. }
begin
  Remove_Timer(Self);
  DisposeObject(API);
  DisposeObject(FAPIUpdate_Event_Pool);
  inherited Destroy;
end;

procedure TAPI_APP.DoChange();
{ * Marks the application as changed and resets the timer so that
  * the update event will be broadcast shortly. This is called whenever the
  * API list changes (Reg_*, UnReg). }
begin
  FUpdated := True;
  Reset_Timer(Self);
end;

procedure TAPI_APP.Subscribe_Update(Bind: TCore_Object; OnUpdate: TOn_API_Update);
{ * Subscribes a listener to update events.
  * @Param Bind: An object that uniquely identifies the subscriber (used for removal).
  * @Param OnUpdate: The callback to invoke when the app changes.
  * @Note If Bind already exists, the callback is overwritten. }
begin
  FAPIUpdate_Event_Pool.Add(Bind, OnUpdate, True);
end;

procedure TAPI_APP.Remove_Update(Bind: TCore_Object);
{ * Unsubscribes a previously subscribed object.
  * @Param Bind: The same object used in Subscribe_Update. }
begin
  FAPIUpdate_Event_Pool.Delete(Bind);
end;

initialization

API_Data_Pool := TAPI_Data_Pool.Create($FFFF, 0);
Running_API_Num := TAtomInt.Create(0);

finalization

DisposeObjectAndNil(Running_API_Num);
DisposeObjectAndNil(API_Data_Pool);

end.

