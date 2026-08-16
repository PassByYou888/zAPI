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
{ *
  * ZDB2 Pair MD5-Stream for HPC
  *
  * This unit provides a high-performance, thread-safe MD5-keyed fragment
  * storage system built on top of the ZDB2 thread engine (Z.ZDB2.Thread).
  * It is designed for applications that need to store and retrieve arbitrary
  * binary data blobs (fragments) indexed by their MD5 hash, such as
  * content-addressable storage, deduplication caches, or distributed file
  * system metadata.
  *
  * Architecture:
  *   - TZDB2_Pair_MD5_Stream_Tool is the main entry point. It owns a
  *     TZDB2_Th_Engine_Marshal (which manages a pool of database engines)
  *     and an MD5-to-data hash pool (TZDB2_Pair_MD5_Stream_Pool).
  *   - TZDB2_Pair_MD5_Stream_Data represents a single stored fragment.
  *     It inherits from TZDB2_Th_Engine_Data and links the actual database
  *     entry to the MD5 pool.
  *   - The MD5 pool provides O(1) lookup by MD5 key, while the underlying
  *     ZDB2 engine handles persistent storage, caching, and I/O.
  *
  * Core Features:
  *   - MD5-based key-value storage: store any binary data and retrieve it
  *     by its MD5 hash.
  *   - Thread-safe operations with asynchronous read/write support.
  *   - Automatic deduplication: setting a fragment with an existing MD5
  *     only updates the access time (moves to last) without duplicating data.
  *   - Parallel extraction: rebuild the MD5 pool from the database using
  *     multiple threads (Extract_MD5_Pool).
  *   - Backup and flush support inherited from TZDB2_Th_Engine_Marshal.
  *   - Configurable hash pool size for optimal lookup performance.
  *
  * Dependencies:
  *   - Z.ZDB2.Thread (TZDB2_Th_Engine_Marshal, TZDB2_Th_Engine_Data)
  *   - Z.ZDB2.Thread.Queue (TZDB2_Th_CMD_Stream_And_State, etc.)
  *   - Z.HashList.Templet (TCritical_MD5_Big_Hash_Pair_Pool)
  *   - Z.UnicodeMixedLib (TMD5 operations)
  *   - Z.MemoryStream (TMS64, TMem64)
  *
  * Use Cases:
  *   - Content-addressable storage (CAS) for file chunks.
  *   - Deduplication cache for backup systems.
  *   - Fast lookup of previously computed results (e.g., cryptographic
  *     hashes, rendering outputs).
  *   - Distributed storage metadata indexing.
  *
  * This unit leverages the full power of the ZDB2 thread engine and is
  * suitable for high-concurrency, large-scale fragment storage scenarios.
  * }
unit Z.ZDB2.Thread.Pair_MD5_Stream;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses Z.Core,
{$IFDEF FPC}
  Z.FPC.GenericList,
{$ENDIF FPC}
  Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib,
  Z.MemoryStream, Z.HashList.Templet,
  Z.Status, Z.Cipher, Z.ZDB2, Z.ListEngine, Z.TextDataEngine, Z.Notify, Z.IOThread,
  Z.ZDB2.Thread.Queue, Z.ZDB2.Thread;

type
  TZDB2_Pair_MD5_Stream_Tool = class;
  TZDB2_Pair_MD5_Stream_Data = class;

  // Critical-section protected MD5 hash pool mapping MD5 keys to TZDB2_Pair_MD5_Stream_Data instances.
  TZDB2_Pair_MD5_Stream_Pool__ = TCritical_MD5_Big_Hash_Pair_Pool<TZDB2_Pair_MD5_Stream_Data>;

  // Extended MD5 hash pool with custom free and comparison methods.
  TZDB2_Pair_MD5_Stream_Pool = class(TZDB2_Pair_MD5_Stream_Pool__)
  public
    procedure DoFree(var Key: TMD5; var Value: TZDB2_Pair_MD5_Stream_Data); override; // Frees the value and removes it from the engine.
    function Compare_Key(const Key_1, Key_2: TMD5): Boolean; override; // Compares two MD5 keys for equality.
    function Compare_Value(const Value_1, Value_2: TZDB2_Pair_MD5_Stream_Data): Boolean; override; // Compares two data instances by reference.
  end;

  // Data item representing a single MD5-keyed fragment stored in the ZDB2 engine.
  TZDB2_Pair_MD5_Stream_Data = class(TZDB2_Th_Engine_Data)
  public
    Owner_MD5_Fragment_Tool: TZDB2_Pair_MD5_Stream_Tool; // Back-reference to the owning tool 每 set by Extract_MD5_Pool or Set_MD5_Fragment.
    MD5_Fragment_Pool_Ptr: TZDB2_Pair_MD5_Stream_Pool__.PPair_Pool_Value__; // Pointer to this item's entry in the MD5 pool 每 set by Do_Th_Data_Loaded or Set_MD5_Fragment.
    constructor Create(); override;
    destructor Destroy; override; // Removes itself from the MD5 pool on destruction.
  end;

  // Main tool class for MD5-keyed fragment storage.
  TZDB2_Pair_MD5_Stream_Tool = class(TCore_Object_Intermediate)
  private
    procedure Do_Th_Data_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMS64); // Internal callback for parallel extraction 每 links each loaded data to the MD5 pool.
  public
    ZDB2_Marshal: TZDB2_Th_Engine_Marshal; // Underlying thread engine marshal 每 created by constructor.
    MD5_Pool: TZDB2_Pair_MD5_Stream_Pool; // Thread-safe MD5-to-data hash pool 每 created by constructor.

    constructor Create(hash_size_: Integer); // Creates the tool with a given hash pool size.
    destructor Destroy; override;

    // Build an in-memory database engine (no persistence).
    function BuildMemory(): TZDB2_Th_Engine;
    // Build or open a file-based database. If Encrypt_ is True, uses Rijndael cipher with default password 'DTC40@ZSERVER'.
    function BuildOrOpen(FileName_: U_String; OnlyRead_, Encrypt_: Boolean): TZDB2_Th_Engine; overload;
    // Build or open with custom configuration.
    function BuildOrOpen(FileName_: U_String; OnlyRead_, Encrypt_: Boolean; cfg: THashStringList): TZDB2_Th_Engine; overload;

    // Hooks for custom build process.
    function Begin_Custom_Build: TZDB2_Th_Engine;
    function End_Custom_Build(Eng_: TZDB2_Th_Engine): Boolean;

    // Extract all fragments from the database into the MD5 pool using parallel threads.
    procedure Extract_MD5_Pool(ThNum_: Integer);

    // Clear all fragments from the pool and optionally delete them from the database.
    procedure Clear(Delete_Data_: Boolean);

    // Delete a specific fragment by its MD5 key, optionally deleting the underlying data.
    procedure Delete(Key_: TMD5; Delete_Data_: Boolean);

    // Check if a fragment with the given MD5 exists.
    function Exists_MD5_Fragment(Key_: TMD5): Boolean;

    // Asynchronous read operations (C, M, P callbacks) 每 read fragment into a stream or memory buffer.
    procedure Async_Get_String_Fragment_C(Key_: TMD5; Source: TMS64; OnResult: TOn_Stream_And_State_Event_C); overload;
    procedure Async_Get_String_Fragment_M(Key_: TMD5; Source: TMS64; OnResult: TOn_Stream_And_State_Event_M); overload;
    procedure Async_Get_String_Fragment_P(Key_: TMD5; Source: TMS64; OnResult: TOn_Stream_And_State_Event_P); overload;
    procedure Async_Get_String_Fragment_C(Key_: TMD5; Source: TMem64; OnResult: TOn_Mem64_And_State_Event_C); overload;
    procedure Async_Get_String_Fragment_M(Key_: TMD5; Source: TMem64; OnResult: TOn_Mem64_And_State_Event_M); overload;
    procedure Async_Get_String_Fragment_P(Key_: TMD5; Source: TMem64; OnResult: TOn_Mem64_And_State_Event_P); overload;

    // Synchronous read: loads the fragment into the provided stream, returns True on success.
    function Get_MD5_Fragment(Key_: TMD5; IO_: TMS64): Boolean;

    // Store a fragment. The MD5 is automatically computed from the data.
    procedure Set_MD5_Fragment(buff: Pointer; buff_size: Int64); overload;
    // Store a fragment from a stream; the MD5 is computed from the stream content.
    procedure Set_MD5_Fragment(IO_: TMS64; Done_Free_IO_: Boolean); overload;
    // Store a fragment with an explicit MD5 key (useful when the key is known in advance).
    procedure Set_MD5_Fragment(Key_: TMD5; IO_: TMS64; Done_Free_IO_: Boolean); overload;

    // Check and clean recycle pools (frees unreferenced data instances).
    procedure Check_Recycle_Pool;
    // Progress maintenance 每 returns True if any engine progressed.
    function Progress: Boolean;

    // Backup all engines, keeping Reserve_ copies.
    procedure Backup(Reserve_: Word);
    // Create a backup only if no backup exists.
    procedure Backup_If_No_Exists();

    // Flush all pending writes to disk.
    procedure Flush; overload;
    procedure Flush(WaitQueue_: Boolean); overload;
    function Flush_Is_Busy: Boolean;

    // Number of fragments currently in memory.
    function Num: NativeInt;
    // Total number of fragments (including those not in memory).
    function Total: NativeInt;

    // Database space statistics.
    function Database_Size: Int64;
    function Database_Physics_Size: Int64;

    // RemoveDatabaseOnDestroy property (deletes database file when tool is destroyed).
    function GetRemoveDatabaseOnDestroy: Boolean;
    procedure SetRemoveDatabaseOnDestroy(const Value: Boolean);
    property RemoveDatabaseOnDestroy: Boolean read GetRemoveDatabaseOnDestroy write SetRemoveDatabaseOnDestroy;

    // Wait for all background tasks to complete.
    procedure Wait();

    // Test procedure.
    class procedure Test();
  end;

implementation

procedure TZDB2_Pair_MD5_Stream_Pool.DoFree(var Key: TMD5; var Value: TZDB2_Pair_MD5_Stream_Data);
begin
  if Value <> nil then
    begin
      Value.Owner_MD5_Fragment_Tool := nil;
      Value.MD5_Fragment_Pool_Ptr := nil;
      Value.Remove(False);
      Value := nil;
    end;
end;

function TZDB2_Pair_MD5_Stream_Pool.Compare_Key(const Key_1, Key_2: TMD5): Boolean;
begin
  Result := umlMD5Compare(Key_1, Key_2);
end;

function TZDB2_Pair_MD5_Stream_Pool.Compare_Value(const Value_1, Value_2: TZDB2_Pair_MD5_Stream_Data): Boolean;
begin
  Result := Value_1 = Value_2;
end;

constructor TZDB2_Pair_MD5_Stream_Data.Create;
begin
  inherited Create;
  Owner_MD5_Fragment_Tool := nil;
  MD5_Fragment_Pool_Ptr := nil;
end;

destructor TZDB2_Pair_MD5_Stream_Data.Destroy;
begin
  if (Owner_MD5_Fragment_Tool <> nil) and (MD5_Fragment_Pool_Ptr <> nil) then
    begin
      MD5_Fragment_Pool_Ptr^.Data.Second := nil;
      TZDB2_Pair_MD5_Stream_Pool__(Owner_MD5_Fragment_Tool.MD5_Pool).Remove(MD5_Fragment_Pool_Ptr);
    end;
  inherited Destroy;
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Do_Th_Data_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMS64);
var
  Key_: TMD5;
  obj_: TZDB2_Pair_MD5_Stream_Data;
begin
  Key_ := IO_.ToMD5;
  obj_ := Sender as TZDB2_Pair_MD5_Stream_Data;
  obj_.Owner_MD5_Fragment_Tool := self;
  obj_.MD5_Fragment_Pool_Ptr := MD5_Pool.Add(Key_, obj_, False);
end;

constructor TZDB2_Pair_MD5_Stream_Tool.Create(hash_size_: Integer);
begin
  inherited Create;
  ZDB2_Marshal := TZDB2_Th_Engine_Marshal.Create(self);
  ZDB2_Marshal.Current_Data_Class := TZDB2_Pair_MD5_Stream_Data;
  MD5_Pool := TZDB2_Pair_MD5_Stream_Pool.Create(hash_size_, nil);
end;

destructor TZDB2_Pair_MD5_Stream_Tool.Destroy;
begin
  DisposeObject(ZDB2_Marshal);
  DisposeObject(MD5_Pool);
  inherited Destroy;
end;

function TZDB2_Pair_MD5_Stream_Tool.BuildMemory(): TZDB2_Th_Engine;
begin
  Result := TZDB2_Th_Engine.Create(ZDB2_Marshal);
  Result.Cache_Mode := smBigData;
  Result.Database_File := '';
  Result.OnlyRead := False;
  Result.Cipher_Security := TCipherSecurity.csNone;
  Result.Build(ZDB2_Marshal.Current_Data_Class);
end;

function TZDB2_Pair_MD5_Stream_Tool.BuildOrOpen(FileName_: U_String; OnlyRead_, Encrypt_: Boolean): TZDB2_Th_Engine;
begin
  Result := TZDB2_Th_Engine.Create(ZDB2_Marshal);
  Result.Cache_Mode := smNormal;
  Result.Database_File := FileName_;
  Result.OnlyRead := OnlyRead_;

  if Encrypt_ then
      Result.Cipher_Security := TCipherSecurity.csRijndael
  else
      Result.Cipher_Security := TCipherSecurity.csNone;

  Result.Build(ZDB2_Marshal.Current_Data_Class);
  if not Result.Ready then
    begin
      DisposeObjectAndNil(Result);
      Result := BuildMemory();
    end;
end;

function TZDB2_Pair_MD5_Stream_Tool.BuildOrOpen(FileName_: U_String; OnlyRead_, Encrypt_: Boolean; cfg: THashStringList): TZDB2_Th_Engine;
begin
  Result := TZDB2_Th_Engine.Create(ZDB2_Marshal);
  Result.Cache_Mode := smNormal;
  Result.Database_File := FileName_;
  Result.OnlyRead := OnlyRead_;
  if cfg <> nil then
      Result.ReadConfig(FileName_, cfg);

  if Encrypt_ then
      Result.Cipher_Security := TCipherSecurity.csRijndael
  else
      Result.Cipher_Security := TCipherSecurity.csNone;

  Result.Build(ZDB2_Marshal.Current_Data_Class);
  if not Result.Ready then
    begin
      DisposeObjectAndNil(Result);
      Result := BuildMemory();
    end;
end;

function TZDB2_Pair_MD5_Stream_Tool.Begin_Custom_Build: TZDB2_Th_Engine;
begin
  Result := TZDB2_Th_Engine.Create(ZDB2_Marshal);
end;

function TZDB2_Pair_MD5_Stream_Tool.End_Custom_Build(Eng_: TZDB2_Th_Engine): Boolean;
begin
  Eng_.Build(ZDB2_Marshal.Current_Data_Class);
  Result := Eng_.Ready;
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Extract_MD5_Pool(ThNum_: Integer);
begin
  MD5_Pool.Clear;
  ZDB2_Marshal.Parallel_Load_M(ThNum_, Do_Th_Data_Loaded, nil);
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Clear(Delete_Data_: Boolean);
begin
  MD5_Pool.Clear;
  if ZDB2_Marshal.Data_Marshal.Num <= 0 then
      exit;

  if Delete_Data_ then
    begin
      ZDB2_Marshal.Wait_Busy_Task();
      with ZDB2_Marshal.Data_Marshal.Repeat_ do
        repeat
            Queue^.Data.Remove(True);
        until not Next;
      ZDB2_Marshal.Wait_Busy_Task();
    end
  else
    begin
      ZDB2_Marshal.Clear;
    end;
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Delete(Key_: TMD5; Delete_Data_: Boolean);
var
  data_: TZDB2_Pair_MD5_Stream_Data;
begin
  data_ := MD5_Pool[Key_];
  if data_ <> nil then
      data_.Remove(Delete_Data_);
end;

function TZDB2_Pair_MD5_Stream_Tool.Exists_MD5_Fragment(Key_: TMD5): Boolean;
begin
  Result := MD5_Pool.Exists_Key(Key_);
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Async_Get_String_Fragment_C(Key_: TMD5; Source: TMS64; OnResult: TOn_Stream_And_State_Event_C);
var
  data_: TZDB2_Pair_MD5_Stream_Data;
  tmp: TZDB2_Th_CMD_Stream_And_State;
begin
  data_ := MD5_Pool[Key_];
  if data_ = nil then
    begin
      tmp.Stream := Source;
      tmp.State := TCMD_State.csError;
      OnResult(tmp);
      exit;
    end;
  data_.Async_Load_Data_C(Source, OnResult);
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Async_Get_String_Fragment_M(Key_: TMD5; Source: TMS64; OnResult: TOn_Stream_And_State_Event_M);
var
  data_: TZDB2_Pair_MD5_Stream_Data;
  tmp: TZDB2_Th_CMD_Stream_And_State;
begin
  data_ := MD5_Pool[Key_];
  if data_ = nil then
    begin
      tmp.Stream := Source;
      tmp.State := TCMD_State.csError;
      OnResult(tmp);
      exit;
    end;
  data_.Async_Load_Data_M(Source, OnResult);
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Async_Get_String_Fragment_P(Key_: TMD5; Source: TMS64; OnResult: TOn_Stream_And_State_Event_P);
var
  data_: TZDB2_Pair_MD5_Stream_Data;
  tmp: TZDB2_Th_CMD_Stream_And_State;
begin
  data_ := MD5_Pool[Key_];
  if data_ = nil then
    begin
      tmp.Stream := Source;
      tmp.State := TCMD_State.csError;
      OnResult(tmp);
      exit;
    end;
  data_.Async_Load_Data_P(Source, OnResult);
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Async_Get_String_Fragment_C(Key_: TMD5; Source: TMem64; OnResult: TOn_Mem64_And_State_Event_C);
var
  data_: TZDB2_Pair_MD5_Stream_Data;
  tmp: TZDB2_Th_CMD_Mem64_And_State;
begin
  data_ := MD5_Pool[Key_];
  if data_ = nil then
    begin
      tmp.Mem64 := Source;
      tmp.State := TCMD_State.csError;
      OnResult(tmp);
      exit;
    end;
  data_.Async_Load_Data_C(Source, OnResult);
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Async_Get_String_Fragment_M(Key_: TMD5; Source: TMem64; OnResult: TOn_Mem64_And_State_Event_M);
var
  data_: TZDB2_Pair_MD5_Stream_Data;
  tmp: TZDB2_Th_CMD_Mem64_And_State;
begin
  data_ := MD5_Pool[Key_];
  if data_ = nil then
    begin
      tmp.Mem64 := Source;
      tmp.State := TCMD_State.csError;
      OnResult(tmp);
      exit;
    end;
  data_.Async_Load_Data_M(Source, OnResult);
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Async_Get_String_Fragment_P(Key_: TMD5; Source: TMem64; OnResult: TOn_Mem64_And_State_Event_P);
var
  data_: TZDB2_Pair_MD5_Stream_Data;
  tmp: TZDB2_Th_CMD_Mem64_And_State;
begin
  data_ := MD5_Pool[Key_];
  if data_ = nil then
    begin
      tmp.Mem64 := Source;
      tmp.State := TCMD_State.csError;
      OnResult(tmp);
      exit;
    end;
  data_.Async_Load_Data_P(Source, OnResult);
end;

function TZDB2_Pair_MD5_Stream_Tool.Get_MD5_Fragment(Key_: TMD5; IO_: TMS64): Boolean;
var
  obj_: TZDB2_Pair_MD5_Stream_Data;
begin
  obj_ := MD5_Pool.Get_Key_Value(Key_);
  Result := obj_ <> nil;
  if Result then
      Result := obj_.Load_Data(IO_);
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Set_MD5_Fragment(buff: Pointer; buff_size: Int64);
var
  m64: TMS64;
begin
  m64 := TMS64.Create;
  m64.WritePtr(buff, buff_size);
  Set_MD5_Fragment(m64, True);
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Set_MD5_Fragment(IO_: TMS64; Done_Free_IO_: Boolean);
begin
  Set_MD5_Fragment(IO_.ToMD5, IO_, Done_Free_IO_);
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Set_MD5_Fragment(Key_: TMD5; IO_: TMS64; Done_Free_IO_: Boolean);
var
  obj_: TZDB2_Pair_MD5_Stream_Data;
begin
  if MD5_Pool.Exists_Key(Key_) then
    begin
      if Done_Free_IO_ then
          DisposeObject(IO_);
      MD5_Pool.Key_Value[Key_].MoveToLast;
      exit;
    end;

  obj_ := ZDB2_Marshal.Add_Data_To_Minimize_Size_Engine as TZDB2_Pair_MD5_Stream_Data;
  obj_.Owner_MD5_Fragment_Tool := self;
  obj_.MD5_Fragment_Pool_Ptr := MD5_Pool.Add(Key_, obj_, True);
  if Done_Free_IO_ then
      obj_.Async_Save_And_Free_Data(IO_)
  else
      obj_.Async_Save_And_Free_Data(IO_.NewClone);
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Check_Recycle_Pool;
begin
  ZDB2_Marshal.Check_Recycle_Pool;
end;

function TZDB2_Pair_MD5_Stream_Tool.Progress: Boolean;
begin
  Result := ZDB2_Marshal.Progress;
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Backup(Reserve_: Word);
begin
  ZDB2_Marshal.Backup(Reserve_);
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Backup_If_No_Exists;
begin
  ZDB2_Marshal.Backup_If_No_Exists();
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Flush;
begin
  ZDB2_Marshal.Flush;
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Flush(WaitQueue_: Boolean);
begin
  ZDB2_Marshal.Flush(WaitQueue_);
end;

function TZDB2_Pair_MD5_Stream_Tool.Flush_Is_Busy: Boolean;
begin
  Result := ZDB2_Marshal.Flush_Is_Busy;
end;

function TZDB2_Pair_MD5_Stream_Tool.Num: NativeInt;
begin
  Result := ZDB2_Marshal.Data_Marshal.Num;
end;

function TZDB2_Pair_MD5_Stream_Tool.Total: NativeInt;
begin
  Result := ZDB2_Marshal.Total;
end;

function TZDB2_Pair_MD5_Stream_Tool.Database_Size: Int64;
begin
  Result := ZDB2_Marshal.Database_Size;
end;

function TZDB2_Pair_MD5_Stream_Tool.Database_Physics_Size: Int64;
begin
  Result := ZDB2_Marshal.Database_Physics_Size;
end;

function TZDB2_Pair_MD5_Stream_Tool.GetRemoveDatabaseOnDestroy: Boolean;
begin
  Result := ZDB2_Marshal.RemoveDatabaseOnDestroy;
end;

procedure TZDB2_Pair_MD5_Stream_Tool.SetRemoveDatabaseOnDestroy(const Value: Boolean);
begin
  ZDB2_Marshal.RemoveDatabaseOnDestroy := Value;
end;

procedure TZDB2_Pair_MD5_Stream_Tool.Wait;
begin
  ZDB2_Marshal.Wait_Busy_Task;
end;

class procedure TZDB2_Pair_MD5_Stream_Tool.Test;
var
  inst_: TZDB2_Pair_MD5_Stream_Tool;
  data_List: TMD5_Big_Pool;
  i: Integer;
  tmp: TMS64;
begin
  inst_ := TZDB2_Pair_MD5_Stream_Tool.Create($FF);
  // inst_.BuildOrOpen('c:\temp\1.ox2', False, False);
  inst_.BuildOrOpen('', False, False);
  inst_.Extract_MD5_Pool(4);
  data_List := TMD5_Big_Pool.Create;

  if inst_.ZDB2_Marshal.Data_Marshal.Num > 0 then
    with inst_.ZDB2_Marshal.Data_Marshal.Repeat_ do
      repeat
          data_List.Add(TZDB2_Pair_MD5_Stream_Data(Queue^.Data).MD5_Fragment_Pool_Ptr^.Data.Primary);
      until not Next;

  for i := 0 to 100 do
    begin
      tmp := TMS64.Create;
      tmp.Size := umlRandomRange(16384, 1024 * 1024 * 2);
      TMT19937.Rand32(MaxInt, tmp.Memory, tmp.Size div 4);
      inst_.Set_MD5_Fragment(tmp, True);
      data_List.Add(inst_.MD5_Pool.Queue_Pool.Last^.Data^.Data.Primary);
    end;
  inst_.ZDB2_Marshal.Wait_Busy_Task;

  if False then
    while data_List.Num > 0 do
      begin
        inst_.Delete(data_List.First^.Data, True);
        data_List.Next;
      end;

  if data_List.Num > 0 then
    with data_List.Repeat_ do
      repeat
        if i__ mod 2 = 0 then
            inst_.Delete(Queue^.Data, True);
      until not Next;

  inst_.ZDB2_Marshal.Wait_Busy_Task;
  inst_.ZDB2_Marshal.Flush;

  DisposeObject(data_List);
  DisposeObject(inst_);
end;

end.
 
