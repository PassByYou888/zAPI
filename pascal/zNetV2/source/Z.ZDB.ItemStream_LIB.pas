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
  * Z.ZDB.ItemStream_LIB 每 Stream Interface for ZDB Items
  *
  * This unit provides a TStream descendant (TItemStream) that maps a ZDB Item
  * (file-like object) to a standard Pascal stream interface. It allows reading,
  * writing, seeking, and copying operations on ZDB items using familiar stream
  * methods, making it easy to integrate with existing code that expects TStream.
  *
  * Architecture:
  *   - TItemStream wraps a TObjectDataManager instance and a TItemHandle.
  *     It delegates all I/O operations to the underlying ZDB engine via the
  *     TObjectDataManager methods (ItemRead, ItemWrite, ItemSeek, etc.).
  *   - The stream can be constructed from a database path/item name, an existing
  *     item handle, or an item header position. It can optionally manage the
  *     handle's lifetime (AutoFreeHnd).
  *   - Helper methods are provided for TMS64 and TMem64 to load/save their
  *     content directly to/from a ZDB item, simplifying data exchange.
  *
  * Dependencies:
  *   - Z.ZDB (TObjectDataManager, TItemHandle)
  *   - Z.ZDB.ObjectData_LIB (low-level record types)
  *   - Z.MemoryStream (TMS64, TMem64)
  *   - Z.Core (TCore_Stream, TCore_FileStream, etc.)
  *
  * Use Cases:
  *   - Reading/writing large binary data stored as ZDB items.
  *   - Treating a ZDB item as a file for serialization/deserialization.
  *   - Streaming data between ZDB and other streams (e.g., file, memory).
  *
  * Historical Context:
  *   This unit belongs to the legacy ZDB stack, which organizes data as
  *   hierarchical fields and items. It provides a convenient stream wrapper
  *   but is based on the same linked-list block traversal as the underlying
  *   engine. For modern high-performance applications, the ZDB2 family
  *   (Z.ZDB2, Z.ZDB2.Thread, etc.) is recommended, as it offers block-oriented
  *   storage, parallel I/O, and advanced features better suited for large-scale
  *   and HPC scenarios.
  *
  * This unit is stable and remains useful for legacy systems and moderate-sized
  * data, but new projects should consider ZDB2 for future-proof performance.
  * }
unit Z.ZDB.ItemStream_LIB;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses SysUtils, Z.Core, Classes, Z.UnicodeMixedLib, Z.ZDB.ObjectData_LIB, Z.ZDB, Z.MemoryStream,
  Z.PascalStrings, Z.UPascalStrings;

type
  // TItemStream 每 a stream class that maps a ZDB item (file) to a TCore_Stream.
  // It allows reading, writing, and seeking on the item's data using standard stream methods.
  TItemStream = class(TCore_Stream)
  private
    DB_Engine: TObjectDataManager; // Owning database manager 每 set by constructor.
    ItemHnd_Ptr: PItemHandle; // Pointer to the item handle (owned or external) 每 set by constructor.
    AutoFreeHnd: Boolean; // If True, frees the handle when stream is destroyed 每 set by constructor.
  protected
    function GetSize: Int64; override; // Returns the total size of the item's data 每 delegates to DB_Engine.ItemGetSize.
  public
    // Constructor: opens or creates an item at the given DBPath/DBItem, stores the handle internally.
    constructor Create(eng_: TObjectDataManager; DBPath, DBItem: SystemString); overload;
    // Constructor: uses an existing item handle (caller manages lifetime unless AutoFreeHnd set).
    constructor Create(eng_: TObjectDataManager; var ItemHnd: TItemHandle); overload;
    // Constructor: opens an item by its header position (fast open).
    constructor Create(eng_: TObjectDataManager; const ItemHeaderPos: Int64); overload;
    destructor Destroy; override;

    // Save the entire stream content to a file.
    procedure SaveToFile(fn: SystemString);
    // Load the stream content from a file (overwrites existing data).
    procedure LoadFromFile(fn: SystemString);

    // Read up to Count bytes into buffer, returns actual bytes read (64-bit version).
    function Read64(var buffer; Count: Int64): Int64;
    // Read method override (32-bit version).
    function Read(var buffer; Count: longint): longint; override;

    // Write Count bytes from buffer, returns actual bytes written (64-bit).
    function Write64(const buffer; Count: Int64): Int64;
    // Write method override (32-bit).
    function Write(const buffer; Count: longint): longint; override;

    // Seek to a position (32-bit offset, legacy).
    function Seek(Offset: longint; origin: Word): longint; overload; override;
    // Seek to a position (64-bit offset, new style).
    function Seek(const Offset: Int64; origin: TSeekOrigin): Int64; overload; override;

    // Copy from Source stream to this stream (64-bit count, optimized).
    function CopyFrom64(const Source: TCore_Stream; Count: Int64): Int64;

    // Shortcuts: seek to beginning or end.
    procedure SeekStart;
    procedure SeekLast;

    // Update the item's metadata (e.g., modification time) to reflect changes.
    function UpdateHandle: Boolean;
    // Close the item handle (releases resources).
    function CloseHandle: Boolean;

    // Read-only access to the item handle pointer.
    property Hnd: PItemHandle read ItemHnd_Ptr;
  end;

  // Helper for TMS64 (memory stream) to load/save directly from/to a ZDB item.
  TMS64_Helper__ = class helper for TMS64
  public
    // Loads the content of a ZDB item (specified by path) into this memory stream.
    procedure LoadFrom_ZDB_File(eng_: TObjectDataManager; FileName: SystemString);
    // Saves the content of this memory stream to a ZDB item (creates or overwrites).
    procedure SaveTo_ZDB_File(eng_: TObjectDataManager; FileName: SystemString);
  end;

  // Helper for TMem64 (memory buffer) to load/save directly from/to a ZDB item.
  TMem64_Helper__ = class helper for TMem64
  public
    // Loads the content of a ZDB item into this memory buffer.
    procedure LoadFrom_ZDB_File(eng_: TObjectDataManager; FileName: SystemString);
    // Saves the content of this memory buffer to a ZDB item.
    procedure SaveTo_ZDB_File(eng_: TObjectDataManager; FileName: SystemString);
  end;

  // Helper for TCore_Stream that adds a 64-bit CopyFrom method.
  TCore_Stream_Helper__ = class helper for TCore_Stream
  public
    // Copies Count bytes from Source to this stream, handling large sizes (64-bit).
    function Helper_CopyFrom64__(const Source: TCore_Stream; Count: Int64): Int64;
  end;

implementation

function TItemStream.GetSize: Int64;
begin
  Result := DB_Engine.ItemGetSize(ItemHnd_Ptr^);
end;

constructor TItemStream.Create(eng_: TObjectDataManager; DBPath, DBItem: SystemString);
begin
  inherited Create;
  DB_Engine := eng_;
  New(ItemHnd_Ptr);
  eng_.ItemAutoOpenOrCreate(DBPath, DBItem, DBItem, ItemHnd_Ptr^);
  AutoFreeHnd := True;
end;

constructor TItemStream.Create(eng_: TObjectDataManager; var ItemHnd: TItemHandle);
begin
  inherited Create;
  DB_Engine := eng_;
  ItemHnd_Ptr := @ItemHnd;
  AutoFreeHnd := False;
end;

constructor TItemStream.Create(eng_: TObjectDataManager; const ItemHeaderPos: Int64);
begin
  inherited Create;
  DB_Engine := eng_;
  New(ItemHnd_Ptr);
  eng_.ItemFastOpen(ItemHeaderPos, ItemHnd_Ptr^);
  AutoFreeHnd := True;
end;

destructor TItemStream.Destroy;
begin
  UpdateHandle();
  if AutoFreeHnd then
    begin
      Dispose(ItemHnd_Ptr);
      ItemHnd_Ptr := nil;
    end;
  inherited Destroy;
end;

procedure TItemStream.SaveToFile(fn: SystemString);
var
  stream: TCore_Stream;
begin
  stream := TCore_FileStream.Create(fn, fmCreate);
  try
      stream.CopyFrom(Self, Size);
  finally
      DisposeObject(stream);
  end;
end;

procedure TItemStream.LoadFromFile(fn: SystemString);
var
  stream: TCore_Stream;
begin
  stream := TCore_FileStream.Create(fn, fmOpenRead or fmShareDenyNone);
  try
      CopyFrom(stream, stream.Size);
  finally
      DisposeObject(stream);
  end;
end;

function TItemStream.Read64(var buffer; Count: Int64): Int64;
var
  Pos_: Int64;
  Size_: Int64;
begin
  Result := 0;
  if (Count > 0) then
    begin
      Pos_ := DB_Engine.ItemGetPos(ItemHnd_Ptr^);
      Size_ := DB_Engine.ItemGetSize(ItemHnd_Ptr^);
      if Pos_ + Count <= Size_ then
        begin
          if DB_Engine.ItemRead(ItemHnd_Ptr^, Count, PByte(@buffer)^) then
              Result := Count;
        end
      else if DB_Engine.ItemRead(ItemHnd_Ptr^, Size_ - Pos_, PByte(@buffer)^) then
          Result := Size_ - Pos_;
    end;
end;

function TItemStream.Read(var buffer; Count: longint): longint;
begin
  Result := Read64(buffer, Count);
end;

function TItemStream.Write64(const buffer; Count: Int64): Int64;
begin
  Result := Count;
  if (Count > 0) then
    if not DB_Engine.ItemWrite(ItemHnd_Ptr^, Count, PByte(@buffer)^) then
      begin
        Result := 0;
      end;
end;

function TItemStream.Write(const buffer; Count: longint): longint;
begin
  Result := Write64(buffer, Count);
end;

function TItemStream.Seek(Offset: longint; origin: Word): longint;
begin
  case origin of
    soFromBeginning:
      begin
        DB_Engine.ItemSeek(ItemHnd_Ptr^, Offset);
      end;
    soFromCurrent:
      begin
        if Offset <> 0 then
            DB_Engine.ItemSeek(ItemHnd_Ptr^, DB_Engine.ItemGetPos(ItemHnd_Ptr^) + Offset);
      end;
    soFromEnd:
      begin
        DB_Engine.ItemSeek(ItemHnd_Ptr^, DB_Engine.ItemGetSize(ItemHnd_Ptr^) + Offset);
      end;
  end;
  Result := DB_Engine.ItemGetPos(ItemHnd_Ptr^);
end;

function TItemStream.Seek(const Offset: Int64; origin: TSeekOrigin): Int64;
begin
  case origin of
    TSeekOrigin.soBeginning:
      begin
        DB_Engine.ItemSeek(ItemHnd_Ptr^, Offset);
      end;
    TSeekOrigin.soCurrent:
      begin
        if Offset <> 0 then
            DB_Engine.ItemSeek(ItemHnd_Ptr^, DB_Engine.ItemGetPos(ItemHnd_Ptr^) + Offset);
      end;
    TSeekOrigin.soEnd:
      begin
        DB_Engine.ItemSeek(ItemHnd_Ptr^, DB_Engine.ItemGetSize(ItemHnd_Ptr^) + Offset);
      end;
  end;
  Result := DB_Engine.ItemGetPos(ItemHnd_Ptr^);
end;

function TItemStream.CopyFrom64(const Source: TCore_Stream; Count: Int64): Int64;
const
  MaxBufSize = $F000;
var
  BufSize, N: Int64;
  buffer: Pointer;
begin
  if Count <= 0 then
    begin
      Source.Position := 0;
      Count := Source.Size;
    end;

  if Source is TMS64 then
    begin
      Result := Write64(TMS64(Source).Memory^, Count);
      exit;
    end;

  Result := Count;
  if Count > MaxBufSize then
      BufSize := MaxBufSize
  else
      BufSize := Count;
  buffer := System.GetMemory(BufSize);
  try
    while Count <> 0 do
      begin
        if Count > BufSize then
            N := BufSize
        else
            N := Count;
        if Source.Read(buffer^, N) <> N then
            RaiseInfo('item read error.');
        if Write64(buffer^, N) <> N then
            RaiseInfo('item write error.');
        Dec(Count, N);
      end;
  finally
      System.FreeMemory(buffer);
  end;
end;

procedure TItemStream.SeekStart;
begin
  DB_Engine.ItemSeekStart(ItemHnd_Ptr^);
end;

procedure TItemStream.SeekLast;
begin
  DB_Engine.ItemSeekLast(ItemHnd_Ptr^);
end;

function TItemStream.UpdateHandle: Boolean;
begin
  if DB_Engine.IsOnlyRead then
      Result := False
  else
      Result := DB_Engine.ItemUpdate(ItemHnd_Ptr^);
end;

function TItemStream.CloseHandle: Boolean;
begin
  Result := DB_Engine.ItemClose(ItemHnd_Ptr^);
end;

procedure TMS64_Helper__.LoadFrom_ZDB_File(eng_: TObjectDataManager; FileName: SystemString);
var
  field_path_, item_name_: U_String;
  Hnd: TItemHandle;
begin
  clear;
  field_path_ := umlGetUnixFilePath(FileName);
  item_name_ := umlGetUnixFileName(FileName);

  if eng_.ItemOpen(field_path_, item_name_, Hnd) then
    begin
      eng_.ItemReadToStream(Hnd, Self);
      eng_.ItemClose(Hnd);
    end
  else
      RaiseInfo('no found %s', [FileName]);
end;

procedure TMS64_Helper__.SaveTo_ZDB_File(eng_: TObjectDataManager; FileName: SystemString);
var
  field_path_, item_name_: U_String;
begin
  field_path_ := umlGetUnixFilePath(FileName);
  item_name_ := umlGetUnixFileName(FileName);
  eng_.ItemWriteFromStream(field_path_, item_name_, Self);
end;

procedure TMem64_Helper__.LoadFrom_ZDB_File(eng_: TObjectDataManager; FileName: SystemString);
var
  field_path_, item_name_: U_String;
  Hnd: TItemHandle;
begin
  field_path_ := umlGetUnixFilePath(FileName);
  item_name_ := umlGetUnixFileName(FileName);

  if eng_.ItemOpen(field_path_, item_name_, Hnd) then
    begin
      Size := Hnd.Item.Size;
      eng_.ItemRead(Hnd, Size, Memory^);
      eng_.ItemClose(Hnd);
    end
  else
      RaiseInfo('no found %s', [FileName]);
end;

procedure TMem64_Helper__.SaveTo_ZDB_File(eng_: TObjectDataManager; FileName: SystemString);
var
  field_path_, item_name_: U_String;
  Hnd: TItemHandle;
begin
  field_path_ := umlGetUnixFilePath(FileName);
  item_name_ := umlGetUnixFileName(FileName);
  eng_.ItemWriteFromStream(field_path_, item_name_, Self.Stream64);
end;

function TCore_Stream_Helper__.Helper_CopyFrom64__(const Source: TCore_Stream; Count: Int64): Int64;
const
  MaxBufSize = $F000;
var
  BufSize, N: Int64;
  buffer: Pointer;
begin
  if Count <= 0 then
    begin
      Source.Position := 0;
      Count := Source.Size;
    end;

  Result := Count;
  if Count > MaxBufSize then
      BufSize := MaxBufSize
  else
      BufSize := Count;
  buffer := System.GetMemory(BufSize);
  try
    while Count <> 0 do
      begin
        if Count > BufSize then
            N := BufSize
        else
            N := Count;
        if Source.Read(buffer^, N) <> N then
            RaiseInfo('item read error.');
        if Write(buffer^, N) <> N then
            RaiseInfo('item write error.');
        Dec(Count, N);
      end;
  finally
      System.FreeMemory(buffer);
  end;
end;

end.
 
