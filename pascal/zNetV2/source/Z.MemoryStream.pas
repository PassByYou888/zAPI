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
{
  * Z.MemoryStream – High-performance memory stream with 64‑bit addressing,
  * compression, serialisation, and zero‑copy mapping.
  *
  * This unit provides two main classes:
  *   – TMS64: a TStream descendant for drop‑in compatibility.
  *   – TMem64: a standalone object with the same capabilities.
  *
  * Both support:
  *   – 64‑bit sizes and positions (streams > 2 GiB).
  *   – Delta‑based capacity growth (reduces reallocations).
  *   – Protected (read‑only) mode for safe external buffer mapping.
  *   – Built‑in LZ4 and Snappy compression.
  *   – Rich serialisation of primitive types, strings, MD5, etc.
  *
  * The design favours performance, low memory overhead, and ease of use
  * in both server and client applications.
}
unit Z.MemoryStream;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses
  SysUtils,
{$IFDEF FPC}
  zstream,
  Z.FPC.GenericList,
{$ELSE FPC}
  ZLib,
{$ENDIF FPC}
  Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.Int128;

type
  TMem64 = class; // forward declaration for mutual references

  {
    * TMS64 – A 64‑bit memory stream that inherits from TCore_Stream (TStream).
    *
    * It overcomes the 2 GiB limitation of TMemoryStream and adds advanced
    * features:
    *   – Delta‑based growth: you control how much capacity increases each time.
    *   – Protected mode: once mapped to an external buffer, the stream becomes
    *     read‑only, preventing accidental writes.
    *   – Zero‑copy mapping: you can map any memory block without copying.
    *   – Compression: LZ4 and Snappy are built in.
    *   – Serialisation helpers: write/read Boolean, Integer, String, MD5, etc.
    *
    * @Example:
    *   var ms: TMS64;
    *       s: TPascalString;
    *   begin
    *     ms := TMS64.Create;                  // delta = 256 bytes
    *     ms.WriteString('Hello, world!');     // writes length + UTF‑8
    *     ms.Position := 0;
    *     s := ms.ReadString;                  // 'Hello, world!'
    *     ms.Free;
    *   end;
    *
    * @Example (mapping an external buffer):
    *   var data: TBytes;
    *       ms: TMS64;
    *   begin
    *     data := TFile.ReadAllBytes('file.bin');
    *     ms := TMS64.Create;
    *     ms.Mapping(@data[0], Length(data));  // read‑only view
    *     // ms.WriteString('x') would raise an exception
    *     ms.Free;
    *   end;
    *
    * @Example (compression):
    *   var orig, comp: TMS64;
    *   begin
    *     orig := TMS64.Create;
    *     orig.WriteString('some data');
    *     comp := orig.LZ4;                    // compressed version
    *     // comp contains a header: [orig size][comp size][data]
    *     comp.Free;
    *     orig.Free;
    *   end;
  }
  TMS64 = class(TCore_Stream)
  private
    FDelta: NativeInt; // capacity growth increment (bytes)
    FMemory: Pointer; // pointer to allocated or mapped buffer
    FSize: NativeUInt; // current logical size
    FPosition: NativeUInt; // current read/write position
    FCapacity: NativeUInt; // total allocated bytes (>= FSize)
    FProtectedMode: Boolean; // True if read‑only (external mapping)
    FMem64: TMem64; // associated TMem64, if any
  protected
    { * Sets the internal memory pointer and size (used by Realloc). }
    procedure SetPointer(buffPtr: Pointer; const BuffSize: NativeUInt);
    { * Changes the capacity; does nothing in protected mode. }
    procedure SetCapacity(NewCapacity: NativeUInt);
    { * Reallocates the buffer to NewCapacity (delta‑aligned).
      * @param NewCapacity Requested capacity; will be rounded up.
      * @return New pointer or nil.
    }
    function Realloc(var NewCapacity: NativeUInt): Pointer; virtual;
    { * Sets FDelta with clamping to [64, 1,048,576]. }
    procedure SetDelta(const Value: NativeInt);
    { * Current allocated capacity (read‑only). }
    property Capacity: NativeUInt read FCapacity write SetCapacity;
  public
    { * Creates a stream with default delta = 256 bytes. }
    constructor Create;
    { * Creates a stream with a custom delta (growth increment).
      * @param customDelta Minimum bytes to add when growing; clamped to [64, 1 MiB].
    }
    constructor CustomCreate(const customDelta: NativeInt);
    destructor Destroy; override;

    { * Returns a TMem64 instance that maps to this stream’s data.
      * @param Mapping_Begin_As_Position_ If True, map from current position to end.
      * @return A TMem64 sharing the same buffer.
    }
    function Mem64(Mapping_Begin_As_Position_: Boolean): TMem64; overload;
    { * Returns a TMem64 mapping the entire stream. Equivalent to Mem64(False). }
    function Mem64: TMem64; overload;

    { * Creates a deep copy (clone) of the stream. }
    function NewClone: TMS64;

    { * Creates a new TMS64 that shares the same memory buffer (zero‑copy, read‑only).
      * The caller must free the returned instance.
    }
    function Create_Mapping_Instance: TMS64;
    { * Creates a TMem64 that shares the same buffer. }
    function Create_Mapping_Instance_Mem64: TMem64;

    { * Swaps internal state with a newly created TMS64, effectively moving data out.
      * Leaves the current stream empty. Useful for passing data without copying.
      * @return A new TMS64 containing the original data.
    }
    function Swap_To_New_Instance: TMS64;

    { * Discards the memory pointer without freeing – use with extreme caution. }
    procedure DiscardMemory;

    { * Frees the memory and resets size and position (not allowed in protected mode). }
    procedure Clear;

    { * Reinitialises the stream using parameters from another TMS64.
      * The current stream is cleared first.
    }
    procedure NewParam(source: TMS64); overload;
    { * Reinitialises using parameters from a TMem64. }
    procedure NewParam(source: TMem64); overload;

    { * Swaps internal state with another TMS64 (O(1) operation). }
    procedure SwapInstance(source: TMS64); overload;
    { * Swaps internal state with a TMem64. }
    procedure SwapInstance(source: TMem64); overload;

    { * Returns a copy of the stream data as a TBytes array. }
    function ToBytes: TBytes;
    { * Computes the MD5 hash of the entire stream content. }
    function ToMD5: TMD5;

    { * Compresses the stream using LZ4.
      * Output: [OriginalSize: Int64][CompressedSize: Int64][CompressedData].
      * @return A new TMS64 containing the compressed data.
    }
    function LZ4: TMS64;
    { * Decompresses LZ4 data from the stream (must be in LZ4 format). }
    function UnLZ4: TMS64;
    { * Compresses using Snappy. Same header format as LZ4. }
    function Snappy_Pas: TMS64;
    { * Decompresses Snappy data. }
    function UnSnappy_Pas: TMS64;

    { * The delta (capacity growth increment). Clamped to [64, 1,048,576]. }
    property Delta: NativeInt read FDelta write SetDelta;
    { * True if the stream is read‑only (mapped to external buffer). }
    property ProtectedMode: Boolean read FProtectedMode;

    { * Maps to an external buffer (protected mode). }
    procedure SetPointerWithProtectedMode(buffPtr: Pointer; const BuffSize: Int64);
    { * Alias for SetPointerWithProtectedMode. }
    procedure Mapping(buffPtr: Pointer; const BuffSize: Int64); overload;
    { * Maps to another TMS64 (protected mode). }
    procedure Mapping(m64: TMS64); overload;
    { * Maps to a TMem64 (protected mode). }
    procedure Mapping(m64: TMem64); overload;

    { * Returns a pointer to the data at the given offset. }
    function PositionAsPtr(const Position_: Int64): Pointer; overload;
    { * Returns a pointer to the data at the current position. }
    function PositionAsPtr: Pointer; overload;
    { * Aliases for PositionAsPtr. }
    function PosAsPtr(const Position_: Int64): Pointer; overload;
    function PosAsPtr: Pointer; overload;

    { * Replaces the stream content by reading from another stream. }
    procedure LoadFromStream(stream: TCore_Stream); virtual;
    { * Loads from a file. }
    procedure LoadFromFile(FileName: SystemString);
    { * Writes the entire stream content to another stream. }
    procedure SaveToStream(stream: TCore_Stream); virtual;
    { * Saves to a file. }
    procedure SaveToFile(FileName: SystemString);

    { * Sets the stream size; if larger, expands capacity. }
    procedure SetSize(const NewSize: Int64); overload; override;
    { * 32‑bit overload for SetSize. }
    procedure SetSize(NewSize: longint); overload; override;

    { * Writes Count bytes from buffer; expands stream if needed.
      * @return Actual bytes written (should equal Count).
    }
    function Write64(const buffer; Count: Int64): Int64; virtual;
    { * Writes from a pointer. }
    function WritePtr(const p: Pointer; Count: Int64): Int64;
    { * 32‑bit overload for TStream compatibility. }
    function write(const buffer; Count: longint): longint; overload; override;
    { * Writes a TBytes array. }
    procedure WriteBytes(const buff: TBytes);

    { * Reads up to Count bytes into buffer.
      * @return Actual bytes read (might be less than Count if EOF).
    }
    function Read64(var buffer; Count: Int64): Int64; virtual;
    { * Reads into a pointer buffer. }
    function ReadPtr(const p: Pointer; Count: Int64): Int64;
    { * 32‑bit overload for TStream compatibility. }
    function read(var buffer; Count: longint): longint; overload; override;
{$IFDEF DELPHI}
    { * Delphi‑specific overload for writing from a TBytes slice. }
    function write(const buffer: TBytes; Offset, Count: longint): longint; overload; override;
    { * Delphi‑specific overload for reading into a TBytes slice. }
    function read(buffer: TBytes; Offset, Count: longint): longint; overload; override;
{$ENDIF DELPHI}
    { * Seeks to a new position. }
    function Seek(const Offset: Int64; origin: TSeekOrigin): Int64; override;

    { * Returns a pointer to the start of the memory buffer. }
    property Memory: Pointer read FMemory;

    { * Copies data from a TMem64 into this stream.
      * Advances the source position.
      * @param Count Number of bytes to copy.
      * @return Bytes actually copied (should equal Count).
    }
    function CopyMem64(const source: TMem64; Count: Int64): Int64;
    { * Copies from any TCore_Stream. If Count < 0, copies all.
      * @return Bytes copied.
    }
    function CopyFrom(const source: TCore_Stream; Count: Int64): Int64; overload;
    { * Copies from a TMem64. }
    function CopyFrom(const source: TMem64; Count: Int64): Int64; overload;

    // --- Serialisation writers -------------------------------------------------
    { * Writes a Boolean (1 byte). }
    procedure WriteBool(const buff: Boolean);
    { * Writes a signed 8‑bit integer. }
    procedure WriteInt8(const buff: ShortInt);
    { * Writes a signed 16‑bit integer. }
    procedure WriteInt16(const buff: SmallInt);
    { * Writes a signed 32‑bit integer. }
    procedure WriteInt32(const buff: Integer);
    { * Writes a signed 64‑bit integer. }
    procedure WriteInt64(const buff: Int64);
    { * Writes a 128‑bit integer (Int128). }
    procedure WriteInt128(const buff: Int128);
    { * Writes an unsigned 8‑bit integer. }
    procedure WriteUInt8(const buff: Byte);
    { * Writes an unsigned 16‑bit integer. }
    procedure WriteUInt16(const buff: Word);
    { * Writes an unsigned 32‑bit integer. }
    procedure WriteUInt32(const buff: Cardinal);
    { * Writes an unsigned 64‑bit integer. }
    procedure WriteUInt64(const buff: UInt64);
    { * Writes an unsigned 128‑bit integer (UInt128). }
    procedure WriteUInt128(const buff: UInt128);
    { * Writes a 32‑bit floating‑point value (Single). }
    procedure WriteSingle(const buff: Single);
    { * Writes a 64‑bit floating‑point value (Double). }
    procedure WriteDouble(const buff: Double);
    { * Writes a Currency value (stored as Double). }
    procedure WriteCurrency(const buff: Currency);

    { * Writes a TPascalString as UTF‑8 with a 32‑bit length prefix.
      * Format: [Length: UInt32][UTF‑8 bytes].
    }
    procedure WriteString(const buff: TPascalString);
    { * Writes the ANSI bytes of a TPascalString (no length prefix).
      * Use when the receiver knows the expected length.
    }
    procedure WriteANSI(const buff: TPascalString); overload;
    { * Writes exactly L ANSI bytes; if buff is shorter, only L bytes are written.
      * The caller must ensure L <= Length(buff.ANSI).
    }
    procedure WriteANSI(const buff: TPascalString; const L: Integer); overload;
    { * Writes an MD5 digest (16 bytes). }
    procedure WriteMD5(const buff: TMD5);

    // --- Serialisation readers ------------------------------------------------
    { * Reads a Boolean. }
    function ReadBool: Boolean;
    { * Reads a signed 8‑bit integer. }
    function ReadInt8: ShortInt;
    { * Reads a signed 16‑bit integer. }
    function ReadInt16: SmallInt;
    { * Reads a signed 32‑bit integer. }
    function ReadInt32: Integer;
    { * Reads a signed 64‑bit integer. }
    function ReadInt64: Int64;
    { * Reads a 128‑bit integer. }
    function ReadInt128: Int128;
    { * Reads an unsigned 8‑bit integer. }
    function ReadUInt8: Byte;
    { * Reads an unsigned 16‑bit integer. }
    function ReadUInt16: Word;
    { * Reads an unsigned 32‑bit integer. }
    function ReadUInt32: Cardinal;
    { * Reads an unsigned 64‑bit integer. }
    function ReadUInt64: UInt64;
    { * Reads an unsigned 128‑bit integer. }
    function ReadUInt128: UInt128;
    { * Reads a Single. }
    function ReadSingle: Single;
    { * Reads a Double. }
    function ReadDouble: Double;
    { * Reads a Currency (stored as Double). }
    function ReadCurrency: Currency;

    { * Checks if there is enough data to read a string (4‑byte length + payload).
      * @return True if the full string can be read safely.
    }
    function PrepareReadString: Boolean;
    { * Reads a TPascalString (UTF‑8 with length prefix). Returns empty on error. }
    function ReadString: TPascalString;
    { * Reads the raw UTF‑8 bytes of a string without decoding. }
    function ReadStringAsBuff: TBytes;
    { * Skips a string in the stream. }
    procedure IgnoreReadString;
    { * Reads L bytes as ANSI and converts to TPascalString. }
    function ReadANSI(L: Integer): TPascalString;
    { * Reads an MD5 digest. }
    function ReadMD5: TMD5;
  end;

  { Type aliases for arrays and collections. }
  TMS64_Array = array of TMS64;
  TStream64_Array = TMS64_Array;
  TMemoryStream64_Array = TMS64_Array;
  TStream64 = TMS64;
  TMemoryStream64 = TMS64;

  TMemoryStream64List_Decl = TGenericsList<TMS64>;

  {
    * TMemoryStream64List – A generic list that manages TMS64 instances.
    * Provides Clean (frees all) and To_Array methods.
  }
  TMemoryStream64List = class(TMemoryStream64List_Decl)
  public
    { * Frees all contained streams and clears the list. }
    procedure Clean;
    { * Returns an array of all contained streams. }
    function To_Array: TMS64_Array;
  end;

  TStream64List = TMemoryStream64List;
  TMS64List = TMemoryStream64List;
  TMS64_Pool = TBig_Object_List<TMS64>;

  {
    * TMemoryStream64ThreadList – Thread‑safe list for TMS64.
    * Uses a TCritical for locking and can auto‑free streams on removal.
  }
  TMemoryStream64ThreadList = class(TMemoryStream64List_Decl)
  private
    FCritical: TCritical; // lock object
  public
    AutoFree_Stream: Boolean; // if True, streams are freed when removed
    constructor Create;
    destructor Destroy; override;

    { * Acquires the lock. }
    procedure Lock;
    { * Releases the lock. }
    procedure UnLock;

    { * Removes a stream; if AutoFree_Stream, frees it. }
    procedure Remove(obj: TMS64);
    { * Deletes at index; frees the stream if AutoFree_Stream. }
    procedure Delete(index: Integer);
    { * Clears the list; frees all streams if AutoFree_Stream. }
    procedure Clear;
    { * Frees all streams and clears the list (ignores AutoFree_Stream). }
    procedure Clean;
    { * Returns an array of all streams. }
    function To_Array: TMS64_Array;
  end;

  TStream64CriticalList = TMemoryStream64ThreadList;
  TMS64CriticalList = TMemoryStream64ThreadList;
  TStream64ThreadList = TMemoryStream64ThreadList;
  TMS64ThreadList = TMemoryStream64ThreadList;

  { Interface for write notification. }
  IMemoryStream64WriteTrigger = interface
    { * Called after a write operation. }
    procedure TriggerWrite64(Count: Int64);
  end;

  {
    * TMemoryStream64OfWriteTrigger – TMS64 that triggers a callback on every write.
    *
    * @Example:
    *   type TMyTrigger = class(TInterfacedObject, IMemoryStream64WriteTrigger)
    *     procedure TriggerWrite64(Count: Int64);
    *   end;
    *   ...
    *   ms := TMemoryStream64OfWriteTrigger.Create(MyTrigger);
    *   ms.WriteString('test'); // calls TriggerWrite64
  }
  TMemoryStream64OfWriteTrigger = class(TMS64)
  public
    Trigger: IMemoryStream64WriteTrigger;
    constructor Create(ATrigger: IMemoryStream64WriteTrigger);
    function Write64(const buffer; Count: Int64): Int64; override;
  end;

  { Interface for read notification. }
  IMemoryStream64ReadTrigger = interface
    procedure TriggerRead64(Count: Int64);
  end;

  { * TMS64 that triggers a callback on every read. }
  TMemoryStream64OfReadTrigger = class(TMS64)
  public
    Trigger: IMemoryStream64ReadTrigger;
    constructor Create(ATrigger: IMemoryStream64ReadTrigger);
    function Read64(var buffer; Count: Int64): Int64; override;
  end;

  { Interface for both read and write notification. }
  IMemoryStream64ReadWriteTrigger = interface
    procedure TriggerWrite64(Count: Int64);
    procedure TriggerRead64(Count: Int64);
  end;

  { * TMS64 that triggers callbacks on both read and write. }
  TMemoryStream64OfReadWriteTrigger = class(TMS64)
  public
    Trigger: IMemoryStream64ReadWriteTrigger;
    constructor Create(ATrigger: IMemoryStream64ReadWriteTrigger);
    function Read64(var buffer; Count: Int64): Int64; override;
    function Write64(const buffer; Count: Int64): Int64; override;
  end;

  {
    * TMem64 – A 64‑bit memory stream that does NOT inherit from TStream.
    *
    * It provides almost identical functionality to TMS64 but is a standalone
    * object, making it useful in contexts where TStream compatibility is not
    * required. It can be converted to a TMS64 via Stream64().
    *
    * @Example:
    *   var mem: TMem64;
    *   begin
    *     mem := TMem64.Create;
    *     mem.WriteString('Hello');
    *     mem.Position := 0;
    *     s := mem.ReadString;   // 'Hello'
    *     mem.Free;
    *   end;
  }
  TMem64 = class(TCore_Object_Intermediate)
  private
    FDelta: NativeInt;
    FMemory: Pointer;
    FSize: Int64;
    FPosition: Int64;
    FCapacity: Int64;
    FProtectedMode: Boolean;
    FStream64: TMS64;
  protected
    procedure SetPointer(buffPtr: Pointer; const BuffSize: Int64);
    procedure SetCapacity(NewCapacity: Int64);
    function Realloc(var NewCapacity: Int64): Pointer;
    property Capacity: Int64 read FCapacity write SetCapacity;
    function GetDelta: NativeInt;
    procedure SetDelta(const Value: NativeInt);
    function GetMemory_: Pointer;
    function GetPosition: Int64;
    procedure SetPosition(const Value: Int64);
    function GetSize: Int64;
    procedure SetSize(const NewSize: Int64);
  public
    constructor Create;
    constructor CustomCreate(const customDelta: NativeInt);
    destructor Destroy; override;

    { * Returns a TMS64 that maps to this TMem64’s data.
      * @param Mapping_Begin_As_Position_ If True, map from current position.
    }
    function Stream64(Mapping_Begin_As_Position_: Boolean): TMS64; overload;
    { * Returns a TMS64 mapping the entire buffer. }
    function Stream64: TMS64; overload;

    { * Creates a deep copy (clone). }
    function NewClone: TMem64;
    { * Creates a new TMem64 that shares the same memory (zero‑copy, read‑only). }
    function Create_Mapping_Instance: TMem64;
    { * Creates a TMS64 that shares the same memory. }
    function Create_Mapping_Instance_MS64: TMS64;
    { * Moves data to a new TMem64 instance by swapping. }
    function Swap_To_New_Instance: TMem64;

    { * Discards the memory pointer without freeing – use with caution. }
    procedure DiscardMemory;
    { * Clears the stream (frees memory, resets). }
    procedure Clear;
    { * Reinitialises from a TMS64. }
    procedure NewParam(source: TMS64); overload;
    { * Reinitialises from another TMem64. }
    procedure NewParam(source: TMem64); overload;
    { * Swaps state with a TMS64. }
    procedure SwapInstance(source: TMS64); overload;
    { * Swaps state with another TMem64. }
    procedure SwapInstance(source: TMem64); overload;

    { * Copies data to a TBytes array. }
    function ToBytes: TBytes;
    { * Computes MD5 of the content. }
    function ToMD5: TMD5;

    { * LZ4 compression. }
    function LZ4: TMem64;
    { * Decompresses LZ4 data. }
    function UnLZ4: TMem64;
    { * Snappy compression. }
    function Snappy_Pas: TMem64;
    { * Decompresses Snappy data. }
    function UnSnappy_Pas: TMem64;

    property Delta: NativeInt read GetDelta write SetDelta;
    property Memory: Pointer read GetMemory_;
    property Position: Int64 read GetPosition write SetPosition;
    property Size: Int64 read GetSize write SetSize;
    property ProtectedMode: Boolean read FProtectedMode;

    { * Maps an external buffer (protected mode). }
    procedure SetPointerWithProtectedMode(buffPtr: Pointer; const BuffSize: Int64);
    { * Alias for SetPointerWithProtectedMode. }
    procedure Mapping(buffPtr: Pointer; const BuffSize: Int64); overload;
    { * Maps to a TMS64 (protected). }
    procedure Mapping(m64: TMS64); overload;
    { * Maps to another TMem64 (protected). }
    procedure Mapping(m64: TMem64); overload;

    { * Returns pointer at given offset. }
    function PositionAsPtr(const Position_: Int64): Pointer; overload;
    { * Returns pointer at current position. }
    function PositionAsPtr: Pointer; overload;
    { * Aliases. }
    function PosAsPtr(const Position_: Int64): Pointer; overload;
    function PosAsPtr: Pointer; overload;

    { * Loads from another stream. }
    procedure LoadFromStream(stream: TCore_Stream);
    { * Loads from a file. }
    procedure LoadFromFile(FileName: SystemString);
    { * Saves to another stream. }
    procedure SaveToStream(stream: TCore_Stream);
    { * Saves to a file. }
    procedure SaveToFile(FileName: SystemString);

    { * Writes Count bytes from buffer. }
    function Write64(const buffer; Count: Int64): Int64;
    { * Writes from a pointer. }
    function WritePtr(const p: Pointer; Count: Int64): Int64;
    { * Alias for Write64. }
    function write(const buffer; Count: Int64): Int64;
    { * Writes a TBytes array, returns bytes written. }
    function WriteBytes(const buffer: TBytes): Int64;

    { * Reads into buffer. }
    function Read64(var buffer; Count: Int64): Int64;
    { * Reads into a pointer. }
    function ReadPtr(const p: Pointer; Count: Int64): Int64;
    { * Alias for Read64. }
    function read(var buffer; Count: Int64): Int64;

    { * Seeks to a new position. }
    function Seek(const Offset: Int64; origin: TSeekOrigin): Int64;

    { * Copies from a TCore_Stream. }
    function CopyFrom(const source: TCore_Stream; Count: Int64): Int64; overload;
    { * Copies from another TMem64. }
    function CopyFrom(const source: TMem64; Count: Int64): Int64; overload;

    // --- Serialisation writers (same as TMS64) --------------------------------
    procedure WriteBool(const buff: Boolean);
    procedure WriteInt8(const buff: ShortInt);
    procedure WriteInt16(const buff: SmallInt);
    procedure WriteInt32(const buff: Integer);
    procedure WriteInt64(const buff: Int64);
    procedure WriteInt128(const buff: Int128);
    procedure WriteUInt8(const buff: Byte);
    procedure WriteUInt16(const buff: Word);
    procedure WriteUInt32(const buff: Cardinal);
    procedure WriteUInt64(const buff: UInt64);
    procedure WriteUInt128(const buff: UInt128);
    procedure WriteSingle(const buff: Single);
    procedure WriteDouble(const buff: Double);
    procedure WriteCurrency(const buff: Currency);
    procedure WriteString(const buff: TPascalString);
    procedure WriteANSI(const buff: TPascalString); overload;
    procedure WriteANSI(const buff: TPascalString; const L: Integer); overload;
    procedure WriteMD5(const buff: TMD5);

    // --- Serialisation readers ------------------------------------------------
    function ReadBool: Boolean;
    function ReadInt8: ShortInt;
    function ReadInt16: SmallInt;
    function ReadInt32: Integer;
    function ReadInt64: Int64;
    function ReadInt128: Int128;
    function ReadUInt8: Byte;
    function ReadUInt16: Word;
    function ReadUInt32: Cardinal;
    function ReadUInt64: UInt64;
    function ReadUInt128: UInt128;
    function ReadSingle: Single;
    function ReadDouble: Double;
    function ReadCurrency: Currency;
    function PrepareReadString: Boolean;
    function ReadString: TPascalString;
    function ReadStringAsBuff: TBytes;
    procedure IgnoreReadString;
    function ReadANSI(L: Integer): TPascalString;
    function ReadMD5: TMD5;
  end;

  TMem64_Array = array of TMem64;
  TM64 = TMem64;
  TMem64List_Decl = TGenericsList<TMem64>;

  {
    * TMem64List – A generic list for TMem64 with a Clean method.
  }
  TMem64List = class(TMem64List_Decl)
  public
    { * Frees all contained TMem64 objects and clears the list. }
    procedure Clean;
  end;

  TM64List = TMem64List;
  TMem64_Pool = TBig_Object_List<TMem64>;

{$IFDEF FPC}

  { FPC compatibility wrappers for zlib streams. }
  TDecompressionStream = class(zstream.TDecompressionStream)
  public
  end;

  TCompressionStream = class(zstream.TCompressionStream)
  public
    constructor Create(stream: TCore_Stream); overload;
    constructor Create(level: Tcompressionlevel; stream: TCore_Stream); overload;
  end;
{$ELSE}

  { Delphi uses ZLib unit’s classes. }
  TDecompressionStream = ZLib.TZDecompressionStream;
  TCompressionStream = ZLib.TZCompressionStream;
{$ENDIF}
  {
    * TSelectCompressionMethod – Enumerates supported compression algorithms.
    * Used with SelectCompressStream and SelectDecompressStream.
  }
  TSelectCompressionMethod = (scmNone, scmZLIB, scmZLIB_Fast, scmZLIB_Max,
    scmDeflate, scmBRRC, scmLZ4, scmSnappy_Pas);

  // ---------- Compression and Decompression Functions ----------

  { * Compresses sour into dest using maximum ZLIB compression. }
function MaxCompressStream(sour, dest: TCore_Stream): Boolean;
{ * Compresses using fast ZLIB compression. }
function FastCompressStream(sour, dest: TCore_Stream): Boolean;
{ * Compresses using default ZLIB compression. }
function CompressStream(sour, dest: TCore_Stream): Boolean; overload;
{ * Decompresses data from a memory pointer into dest. }
function DecompressStream(DataPtr: Pointer; siz: NativeInt; dest: TCore_Stream): Boolean; overload;
{ * Decompresses data from sour into dest. }
function DecompressStream(sour: TCore_Stream; dest: TCore_Stream): Boolean; overload;
{ * Decompresses data from sour into a newly allocated pointer. }
function DecompressStreamToPtr(sour: TCore_Stream; var dest: Pointer): Boolean; overload;
{ * Compresses a file using ZLIB. }
function CompressFile(sour, dest: SystemString): Boolean;
{ * Decompresses a file using ZLIB. }
function DecompressFile(sour, dest: SystemString): Boolean;

{ * Compresses using a selected method; writes method identifier first. }
function SelectCompressStream(const scm: TSelectCompressionMethod; const sour, dest: TCore_Stream): Boolean;
{ * Decompresses automatically detecting the method from the data. }
function SelectDecompressStream(const sour, dest: TCore_Stream): Boolean; overload;
{ * Decompresses and returns the detected method. }
function SelectDecompressStream(const sour, dest: TCore_Stream; var scm: TSelectCompressionMethod): Boolean; overload;

{ * Parallel compression using multiple threads. }
procedure ParallelCompressMemory(const ThNum: Integer; const scm: TSelectCompressionMethod; const StripNum_: Integer; const sour: TMS64; const dest: TCore_Stream); overload;
procedure ParallelCompressMemory(const scm: TSelectCompressionMethod; const StripNum_: Integer; const sour: TMS64; const dest: TCore_Stream); overload;
procedure ParallelCompressMemory(const scm: TSelectCompressionMethod; const sour: TMS64; const dest: TCore_Stream); overload;
procedure ParallelCompressMemory(const sour: TMS64; const dest: TCore_Stream); overload;

{ * Parallel decompression using multiple threads. }
procedure ParallelDecompressStream(const ThNum: Integer; const sour_, dest_: TCore_Stream); overload;
procedure ParallelDecompressStream(const sour_, dest_: TCore_Stream); overload;

{ * Parallel file compression/decompression. }
procedure ParallelCompressFile(const sour, dest: SystemString);
procedure ParallelDecompressFile(const sour, dest: SystemString);

{ * Compresses UTF‑8 data with a small header (FF FF + original size). }
function CompressUTF8(const sour_: TBytes): TBytes;
{ * Decompresses UTF‑8 data produced by CompressUTF8. }
function DecompressUTF8(const sour_: TBytes): TBytes;

// ---------- Stream Serialisation Functions (standalone) ----------
procedure StreamWriteBool(const stream: TCore_Stream; const buff: Boolean); // Writes a Boolean to a stream.
procedure StreamWriteInt8(const stream: TCore_Stream; const buff: ShortInt); // Writes an Int8.
procedure StreamWriteInt16(const stream: TCore_Stream; const buff: SmallInt); // Writes an Int16.
procedure StreamWriteInt32(const stream: TCore_Stream; const buff: Integer); // Writes an Int32.
procedure StreamWriteInt64(const stream: TCore_Stream; const buff: Int64); // Writes an Int64.
procedure StreamWriteInt128(const stream: TCore_Stream; const buff: Int128); // Writes an Int128.
procedure StreamWriteUInt8(const stream: TCore_Stream; const buff: Byte); // Writes a UInt8.
procedure StreamWriteUInt16(const stream: TCore_Stream; const buff: Word); // Writes a UInt16.
procedure StreamWriteUInt32(const stream: TCore_Stream; const buff: Cardinal); // Writes a UInt32.
procedure StreamWriteUInt64(const stream: TCore_Stream; const buff: UInt64); // Writes a UInt64.
procedure StreamWriteUInt128(const stream: TCore_Stream; const buff: UInt128); // Writes a UInt128.
procedure StreamWriteSingle(const stream: TCore_Stream; const buff: Single); // Writes a Single.
procedure StreamWriteDouble(const stream: TCore_Stream; const buff: Double); // Writes a Double.
procedure StreamWriteCurrency(const stream: TCore_Stream; const buff: Currency); // Writes a Currency.
procedure StreamWriteString(const stream: TCore_Stream; const buff: TPascalString); // Writes a TPascalString as UTF‑8 with length prefix.
function ComputeStreamWriteStringSize(buff: TPascalString): Integer; // Returns the total byte size needed to write a string (4 + UTF‑8 length).
procedure StreamWriteMD5(const stream: TCore_Stream; const buff: TMD5); // Writes an MD5 digest.

function StreamReadBool(const stream: TCore_Stream): Boolean; // Reads a Boolean.
function StreamReadInt8(const stream: TCore_Stream): ShortInt; // Reads an Int8.
function StreamReadInt16(const stream: TCore_Stream): SmallInt; // Reads an Int16.
function StreamReadInt32(const stream: TCore_Stream): Integer; // Reads an Int32.
function StreamReadInt64(const stream: TCore_Stream): Int64; // Reads an Int64.
function StreamReadInt128(const stream: TCore_Stream): Int128; // Reads an Int128.
function StreamReadUInt8(const stream: TCore_Stream): Byte; // Reads a UInt8.
function StreamReadUInt16(const stream: TCore_Stream): Word; // Reads a UInt16.
function StreamReadUInt32(const stream: TCore_Stream): Cardinal; // Reads a UInt32.
function StreamReadUInt64(const stream: TCore_Stream): UInt64; // Reads a UInt64.
function StreamReadUInt128(const stream: TCore_Stream): UInt128; // Reads a UInt128.
function StreamReadSingle(const stream: TCore_Stream): Single; // Reads a Single.
function StreamReadDouble(const stream: TCore_Stream): Double; // Reads a Double.
function StreamReadCurrency(const stream: TCore_Stream): Currency; // Reads a Currency.
function StreamReadString(const stream: TCore_Stream): TPascalString; // Reads a TPascalString (UTF‑8 with length prefix).
function StreamReadStringAsBuff(const stream: TCore_Stream): TBytes; // Reads a string as raw bytes (UTF‑8 without decoding).
procedure StreamIgnoreReadString(const stream: TCore_Stream); // Skips a string in the stream.
function StreamReadMD5(const stream: TCore_Stream): TMD5; // Reads an MD5 digest.{ * Debug: prints the content of a TMS64 to the status console. }

procedure DoStatus(const v: TMS64); overload;
{ * Debug: prints the content of a TMem64 to the status console. }
procedure DoStatus(const v: TMem64); overload;

implementation

uses Z.UnicodeMixedLib, Z.Status, Z.Compress, Z.Instance.Tool, Z.LZ4_Pas, Z.Snappy_Pas;

{ *************** TMS64 implementation *************** }

procedure TMS64.SetPointer(buffPtr: Pointer; const BuffSize: NativeUInt);
{ * Simply stores the buffer pointer and size. Used internally after allocation. }
begin
  FMemory := buffPtr;
  FSize := BuffSize;
end;

procedure TMS64.SetCapacity(NewCapacity: NativeUInt);
{ * Changes the allocated capacity. No effect if in protected mode. }
begin
  if FProtectedMode then
      Exit;
  SetPointer(Realloc(NewCapacity), FSize);
  FCapacity := NewCapacity;
end;

function TMS64.Realloc(var NewCapacity: NativeUInt): Pointer;
{ *
  * Reallocates memory to NewCapacity, aligning it to the delta boundary.
  * If NewCapacity = 0, frees the old memory.
  * Returns the new pointer (nil if allocation fails).
}
begin
  if FProtectedMode then
      Exit(nil);
  if (NewCapacity > 0) and (NewCapacity <> FSize) then
      NewCapacity := DeltaStep(NewCapacity, FDelta);
  Result := Memory;
  if NewCapacity <> FCapacity then
    begin
      if NewCapacity = 0 then
        begin
          System.FreeMemory(Memory);
          Result := nil;
        end
      else
        begin
          if Capacity = 0 then
              Result := System.GetMemory(NewCapacity)
          else
              Result := System.ReallocMemory(Result, NewCapacity);
          if Result = nil then
              RaiseInfo('%s Out of memory while expanding memory stream', [umlSizeToStr(NewCapacity).Text]);
        end;
    end;
end;

procedure TMS64.SetDelta(const Value: NativeInt);
{ * Clamps the delta to [64, 1,048,576] bytes. }
begin
  FDelta := umlClamp(Value, 64, 1024 * 1024);
end;

constructor TMS64.Create;
{ * Default delta = 256 bytes. }
begin
  CustomCreate(256);
end;

constructor TMS64.CustomCreate(const customDelta: NativeInt);
{ * Initialises with custom delta; all pointers and sizes zero. }
begin
  inherited Create;
  Delta := customDelta;
  FMemory := nil;
  FSize := 0;
  FPosition := 0;
  FCapacity := 0;
  FProtectedMode := False;
  FMem64 := nil;
end;

destructor TMS64.Destroy;
{ * Frees the associated TMem64 (if any) and clears the buffer. }
begin
  if FMem64 <> nil then
      DisposeObject(FMem64);
  Clear;
  inherited Destroy;
end;

function TMS64.Mem64(Mapping_Begin_As_Position_: Boolean): TMem64;
{ * Lazily creates a TMem64 that shares our buffer.
  * If Mapping_Begin_As_Position_ is True, the view starts at current position.
}
begin
  if FMem64 = nil then
      FMem64 := TMem64.Create;
  if Mapping_Begin_As_Position_ then
      FMem64.Mapping(PosAsPtr, Size - Position)
  else
      FMem64.Mapping(self);
  Result := FMem64;
end;

function TMS64.Mem64: TMem64;
begin
  Result := Mem64(False);
end;

function TMS64.NewClone: TMS64;
{ * Performs a deep copy: allocates a new stream and copies all data.
  * The position of the clone is set to the same as the original.
}
begin
  Result := TMS64.CustomCreate(FDelta);
  Result.Size := Size;
  CopyPtr(Memory, Result.Memory, Size);
  Result.Position := Position;
end;

function TMS64.Create_Mapping_Instance: TMS64;
{ * Creates a read‑only view that points to the same buffer.
  * The caller must free the returned instance separately.
}
begin
  Result := TMS64.Create;
  Result.Mapping(self);
end;

function TMS64.Create_Mapping_Instance_Mem64: TMem64;
begin
  Result := TMem64.Create;
  Result.Mapping(self);
end;

function TMS64.Swap_To_New_Instance: TMS64;
{ * Swaps our entire state into a new TMS64, leaving us empty.
  * This is an O(1) operation.
}
begin
  Result := TMS64.Create;
  SwapInstance(Result);
end;

procedure TMS64.DiscardMemory;
{ * Releases the buffer pointer without freeing memory.
  * Only valid for non‑protected streams.
}
begin
  if FProtectedMode then
      Exit;
  FMemory := nil;
  FSize := 0;
  FPosition := 0;
  FCapacity := 0;
end;

procedure TMS64.Clear;
{ * Frees memory and resets size/position. Does nothing in protected mode. }
begin
  if FProtectedMode then
      Exit;
  SetCapacity(0);
  FSize := 0;
  FPosition := 0;
end;

procedure TMS64.NewParam(source: TMS64);
{ * Copies all parameters from source, but does NOT share memory.
  * The current stream is cleared first.
}
begin
  Clear;
  FDelta := source.FDelta;
  FMemory := source.FMemory;
  FSize := source.FSize;
  FPosition := source.FPosition;
  FCapacity := source.FCapacity;
  FProtectedMode := source.FProtectedMode;
end;

procedure TMS64.NewParam(source: TMem64);
begin
  Clear;
  FDelta := source.FDelta;
  FMemory := source.FMemory;
  FSize := source.FSize;
  FPosition := source.FPosition;
  FCapacity := source.FCapacity;
  FProtectedMode := source.FProtectedMode;
end;

procedure TMS64.SwapInstance(source: TMS64);
{ * Swaps all fields with another TMS64 instance. }
var
  FDelta_: NativeInt;
  FMemory_: Pointer;
  FSize_: NativeUInt;
  FPosition_: NativeUInt;
  FCapacity_: NativeUInt;
  FProtectedMode_: Boolean;
begin
  FDelta_ := FDelta;
  FMemory_ := FMemory;
  FSize_ := FSize;
  FPosition_ := FPosition;
  FCapacity_ := FCapacity;
  FProtectedMode_ := FProtectedMode;

  FDelta := source.FDelta;
  FMemory := source.FMemory;
  FSize := source.FSize;
  FPosition := source.FPosition;
  FCapacity := source.FCapacity;
  FProtectedMode := source.FProtectedMode;

  source.FDelta := FDelta_;
  source.FMemory := FMemory_;
  source.FSize := FSize_;
  source.FPosition := FPosition_;
  source.FCapacity := FCapacity_;
  source.FProtectedMode := FProtectedMode_;
end;

procedure TMS64.SwapInstance(source: TMem64);
{ * Swaps with a TMem64; the fields are compatible. }
var
  FDelta_: NativeInt;
  FMemory_: Pointer;
  FSize_: NativeUInt;
  FPosition_: NativeUInt;
  FCapacity_: NativeUInt;
  FProtectedMode_: Boolean;
begin
  FDelta_ := FDelta;
  FMemory_ := FMemory;
  FSize_ := FSize;
  FPosition_ := FPosition;
  FCapacity_ := FCapacity;
  FProtectedMode_ := FProtectedMode;

  FDelta := source.FDelta;
  FMemory := source.FMemory;
  FSize := source.FSize;
  FPosition := source.FPosition;
  FCapacity := source.FCapacity;
  FProtectedMode := source.FProtectedMode;

  source.FDelta := FDelta_;
  source.FMemory := FMemory_;
  source.FSize := FSize_;
  source.FPosition := FPosition_;
  source.FCapacity := FCapacity_;
  source.FProtectedMode := FProtectedMode_;
end;

function TMS64.ToBytes: TBytes;
{ * Copies the entire stream data into a newly allocated TBytes array. }
begin
  SetLength(Result, Size);
  if Size > 0 then
      CopyPtr(Memory, @Result[0], Size);
end;

function TMS64.ToMD5: TMD5;
{ * Computes MD5 of the entire stream data. }
begin
  Result := umlMD5(Memory, Size);
end;

function TMS64.LZ4: TMS64;
{ * LZ4 compression.
  * Allocates a new stream, writes original size and compressed size,
  * then the compressed data.
}
var
  comp_size: Int64;
begin
  Result := TMS64.Create;
  Result.Size := LZ4_compressBound64(Size) + 16; // room for headers + max compressed
  PInt64(Result.PosAsPtr(0))^ := Size; // original size
  comp_size := LZ4_compress_default64(Memory^, Size, Result.PosAsPtr(16)^, LZ4_compressBound64(Size));
  PInt64(Result.PosAsPtr(8))^ := comp_size; // compressed size
  Result.Size := comp_size + 16; // trim to actual size
end;

function TMS64.UnLZ4: TMS64;
{ * Decompresses LZ4 data.
  * Reads original size and compressed size from the headers,
  * then decompresses into a new stream.
}
var
  comp_size: Int64;
begin
  Result := TMS64.Create;
  Result.Size := PInt64(PosAsPtr(0))^; // original size
  comp_size := PInt64(PosAsPtr(8))^; // compressed size
  LZ4_decompress_safe64(PosAsPtr(16)^, comp_size, Result.Memory^, Result.Size);
end;

function TMS64.Snappy_Pas: TMS64;
{ * Snappy compression, same header format as LZ4. }
var
  comp_size: Int64;
begin
  Result := TMS64.Create;
  Result.Size := SnappyMaxCompressedLength64(Size) + 16;
  PInt64(Result.PosAsPtr(0))^ := Size;
  comp_size := Result.Size;
  SnappyCompress(Memory, Size, Result.PosAsPtr(16), comp_size);
  PInt64(Result.PosAsPtr(8))^ := comp_size;
  Result.Size := comp_size + 16;
end;

function TMS64.UnSnappy_Pas: TMS64;
{ * Decompresses Snappy data. }
var
  OutputSize: Int64;
  comp_size: Int64;
begin
  Result := TMS64.Create;
  Result.Size := PInt64(PosAsPtr(0))^;
  OutputSize := Result.Size;
  comp_size := PInt64(PosAsPtr(8))^;
  SnappyDecompress(PosAsPtr(16), comp_size, Result.Memory, OutputSize);
end;

procedure TMS64.SetPointerWithProtectedMode(buffPtr: Pointer; const BuffSize: Int64);
{ * Sets the stream to protected mode using an external buffer. }
begin
  Mapping(buffPtr, BuffSize);
end;

procedure TMS64.Mapping(buffPtr: Pointer; const BuffSize: Int64);
{ * Maps an external buffer; the stream becomes read‑only. }
begin
  Clear;
  FMemory := buffPtr;
  FSize := BuffSize;
  FPosition := 0;
  FProtectedMode := True;
end;

procedure TMS64.Mapping(m64: TMS64);
begin
  Mapping(m64.Memory, m64.Size);
end;

procedure TMS64.Mapping(m64: TMem64);
begin
  Mapping(m64.Memory, m64.Size);
end;

function TMS64.PositionAsPtr(const Position_: Int64): Pointer;
{ * Returns a pointer to the given offset (0‑based). }
begin
  Result := GetOffset(FMemory, Position_);
end;

function TMS64.PositionAsPtr: Pointer;
begin
  Result := GetOffset(FMemory, FPosition);
end;

function TMS64.PosAsPtr(const Position_: Int64): Pointer;
begin
  Result := PositionAsPtr(Position_);
end;

function TMS64.PosAsPtr: Pointer;
begin
  Result := PositionAsPtr();
end;

procedure TMS64.LoadFromStream(stream: TCore_Stream);
{ * Replaces content with data from another stream. }
begin
  if FProtectedMode then
      Exit;
  Clear;
  stream.Position := 0;
  if CopyFrom(stream, stream.Size) <> stream.Size then
      RaiseInfo('load stream error.');
  Position := 0;
end;

procedure TMS64.LoadFromFile(FileName: SystemString);
{ * Reads entire file into the stream. }
var
  stream: TCore_Stream;
begin
  stream := TCore_FileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
      LoadFromStream(stream);
  finally
      DisposeObject(stream);
  end;
end;

procedure TMS64.SaveToStream(stream: TCore_Stream);
{ * Writes the entire stream to another stream, using chunked I/O
  * to avoid large memory copies.
}
const
  ChunkSize = 64 * 1024 * 1024; // 64 MiB
var
  p: Pointer;
  j: NativeInt;
  Num: NativeInt;
  Rest: NativeInt;
begin
  if stream is TMS64 then
    begin
      TMS64(stream).Clear;
      if Size > 0 then
          TMS64(stream).WritePtr(Memory, Size);
      TMS64(stream).Position := 0;
      Exit;
    end;
  if Size > 0 then
    begin
      p := FMemory;
      if Size > ChunkSize then
        begin
          Num := Size div ChunkSize;
          Rest := Size mod ChunkSize;
          for j := 0 to Num - 1 do
            begin
              stream.WriteBuffer(p^, ChunkSize);
              p := GetOffset(p, ChunkSize);
            end;
          if Rest > 0 then
            begin
              stream.WriteBuffer(p^, Rest);
              p := GetOffset(p, Rest);
            end;
        end
      else
          stream.WriteBuffer(p^, Size);
    end;
end;

procedure TMS64.SaveToFile(FileName: SystemString);
var
  stream: TCore_Stream;
begin
  stream := TCore_FileStream.Create(FileName, fmCreate);
  try
      SaveToStream(stream);
  finally
      DisposeObject(stream);
  end;
end;

procedure TMS64.SetSize(const NewSize: Int64);
{ * Changes the stream size; if larger, expands capacity.
  * If position > new size, seeks to end.
}
var
  OldPosition: Int64;
begin
  if FProtectedMode then
      Exit;
  OldPosition := FPosition;
  SetCapacity(NewSize);
  FSize := NewSize;
  if OldPosition > NewSize then
      Seek(0, TSeekOrigin.soEnd);
end;

procedure TMS64.SetSize(NewSize: longint);
begin
  SetSize(Int64(NewSize));
end;

function TMS64.Write64(const buffer; Count: Int64): Int64;
{ * Core write routine: copies from buffer into internal memory,
  * expanding the stream if necessary.
}
var
  p: Int64;
begin
  if (Count > 0) then
    begin
      p := FPosition;
      p := p + Count;
      if p > 0 then
        begin
          if p > FSize then
            begin
              if FProtectedMode then
                begin
                  Result := 0;
                  Exit;
                end;
              if p > FCapacity then
                  SetCapacity(p);
              FSize := p;
            end;
          CopyPtr(@buffer, GetOffset(FMemory, FPosition), Count);
          FPosition := p;
          Result := Count;
          Exit;
        end;
    end;
  Result := 0;
end;

function TMS64.WritePtr(const p: Pointer; Count: Int64): Int64;
begin
  Result := Write64(p^, Count);
end;

function TMS64.write(const buffer; Count: longint): longint;
begin
  Result := Write64(buffer, Count);
end;

procedure TMS64.WriteBytes(const buff: TBytes);
begin
  if Length(buff) > 0 then
      WritePtr(@buff[0], Length(buff));
end;

function TMS64.Read64(var buffer; Count: Int64): Int64;
{ * Core read routine: copies from internal memory to buffer,
  * reading at most available bytes.
}
begin
  if Count > 0 then
    begin
      Result := FSize - FPosition;
      if Result > 0 then
        begin
          if Result > Count then
              Result := Count;
          CopyPtr(GetOffset(FMemory, FPosition), @buffer, Result);
          inc(FPosition, Result);
          Exit;
        end;
    end;
  Result := 0;
end;

function TMS64.ReadPtr(const p: Pointer; Count: Int64): Int64;
begin
  Result := Read64(p^, Count);
end;

function TMS64.read(var buffer; Count: longint): longint;
begin
  Result := Read64(buffer, Count);
end;

{$IFDEF DELPHI}

function TMS64.write(const buffer: TBytes; Offset, Count: longint): longint;
{ * Delphi‑specific overload for writing from a TBytes slice.
  * Behaves like Write64 but with offset into the byte array.
}
var
  p: Int64;
begin
  if Count > 0 then
    begin
      p := FPosition;
      p := p + Count;
      if p > 0 then
        begin
          if p > FSize then
            begin
              if FProtectedMode then
                begin
                  Result := 0;
                  Exit;
                end;
              if p > FCapacity then
                  SetCapacity(p);
              FSize := p;
            end;
          CopyPtr(@buffer[Offset], GetOffset(FMemory, FPosition), Count);
          FPosition := p;
          Result := Count;
          Exit;
        end;
    end;
  Result := 0;
end;

function TMS64.read(buffer: TBytes; Offset, Count: longint): longint;
{ * Delphi‑specific overload for reading into a TBytes slice. }
var
  p: Int64;
begin
  if Count > 0 then
    begin
      p := FSize - FPosition;
      if p > 0 then
        begin
          if p > Count then
              p := Count;
          CopyPtr(GetOffset(FMemory, FPosition), @buffer[Offset], p);
          inc(FPosition, p);
          Result := p;
          Exit;
        end;
    end;
  Result := 0;
end;
{$ENDIF DELPHI}


function TMS64.Seek(const Offset: Int64; origin: TSeekOrigin): Int64;
{ * Moves the position according to the origin. }
begin
  case origin of
    TSeekOrigin.soBeginning: FPosition := Offset;
    TSeekOrigin.soCurrent: inc(FPosition, Offset);
    TSeekOrigin.soEnd: FPosition := FSize + Offset;
  end;
  Result := FPosition;
end;

function TMS64.CopyMem64(const source: TMem64; Count: Int64): Int64;
{ * Copies data from a TMem64 at its current position.
  * Advances the source position.
}
begin
  if FProtectedMode then
      RaiseInfo('protected mode');
  WritePtr(source.PositionAsPtr, Count);
  source.Position := source.FPosition + Count;
  Result := Count;
end;

function TMS64.CopyFrom(const source: TCore_Stream; Count: Int64): Int64;
{ * Copies from any TCore_Stream. If Count < 0, copies all remaining.
  * Uses chunked reading to handle large streams efficiently.
}
const
  MaxBufSize = $F000; // ~60 KB
var
  BufSize, n, p: Int64;
begin
  if FProtectedMode then
      RaiseInfo('protected mode');
  if Count = 0 then
      Exit(0);
  if Count < 0 then
    begin
      source.Position := 0;
      Count := source.Size;
    end;
  if source is TMS64 then
    begin
      WritePtr(TMS64(source).PositionAsPtr, Count);
      TMS64(source).Position := TMS64(source).FPosition + Count;
      Result := Count;
      Exit;
    end;
  Result := Count;
  if Count > MaxBufSize then
      BufSize := MaxBufSize
  else
      BufSize := Count;
  p := Position;
  if p + Count > Size then
      Size := p + Count;
  while Count <> 0 do
    begin
      if Count > BufSize then
          n := BufSize
      else
          n := Count;
      if source.read(PosAsPtr(p)^, n) <> n then
          RaiseInfo('stream read error.');
      inc(p, n);
      dec(Count, n);
    end;
  Position := p;
end;

function TMS64.CopyFrom(const source: TMem64; Count: Int64): Int64;
begin
  if FProtectedMode then
      RaiseInfo('protected mode');
  WritePtr(source.PositionAsPtr, Count);
  source.Position := source.FPosition + Count;
  Result := Count;
end;

{ ----- Serialisation writers -------------------------------------------------- }
procedure TMS64.WriteBool(const buff: Boolean);
begin
  WritePtr(@buff, 1);
end;

procedure TMS64.WriteInt8(const buff: ShortInt);
begin
  WritePtr(@buff, 1);
end;

procedure TMS64.WriteInt16(const buff: SmallInt);
begin
  WritePtr(@buff, 2);
end;

procedure TMS64.WriteInt32(const buff: Integer);
begin
  WritePtr(@buff, 4);
end;

procedure TMS64.WriteInt64(const buff: Int64);
begin
  WritePtr(@buff, 8);
end;

procedure TMS64.WriteInt128(const buff: Int128);
begin
  WritePtr(@buff.b[0], 16);
end;

procedure TMS64.WriteUInt8(const buff: Byte);
begin
  WritePtr(@buff, 1);
end;

procedure TMS64.WriteUInt16(const buff: Word);
begin
  WritePtr(@buff, 2);
end;

procedure TMS64.WriteUInt32(const buff: Cardinal);
begin
  WritePtr(@buff, 4);
end;

procedure TMS64.WriteUInt64(const buff: UInt64);
begin
  WritePtr(@buff, 8);
end;

procedure TMS64.WriteUInt128(const buff: UInt128);
begin
  WritePtr(@buff.b[0], 16);
end;

procedure TMS64.WriteSingle(const buff: Single);
begin
  WritePtr(@buff, 4);
end;

procedure TMS64.WriteDouble(const buff: Double);
begin
  WritePtr(@buff, 8);
end;

procedure TMS64.WriteCurrency(const buff: Currency);
begin
  WriteDouble(buff);
end;

procedure TMS64.WriteString(const buff: TPascalString);
{ * Writes a TPascalString as UTF‑8 with a 32‑bit length prefix.
  * Length is the number of UTF‑8 bytes, not characters.
}
var
  b: TBytes;
begin
  b := buff.Bytes;
  WriteUInt32(Length(b));
  if Length(b) > 0 then
    begin
      WritePtr(@b[0], Length(b));
      SetLength(b, 0);
    end;
end;

procedure TMS64.WriteANSI(const buff: TPascalString);
{ * Writes the ANSI bytes of the string without a length prefix.
  * The receiver must know the length in advance.
}
var
  b: TBytes;
begin
  b := buff.ANSI;
  if Length(b) > 0 then
    begin
      WritePtr(@b[0], Length(b));
      SetLength(b, 0);
    end;
end;

procedure TMS64.WriteANSI(const buff: TPascalString; const L: Integer);
{ * Writes exactly L bytes of ANSI data.
  * If buff is shorter than L, only buff length bytes are written.
  * Caller must ensure L <= Length(buff.ANSI) for correct operation.
}
var
  b: TBytes;
begin
  b := buff.ANSI;
  if L > 0 then
    begin
      WritePtr(@b[0], L);
      SetLength(b, 0);
    end;
end;

procedure TMS64.WriteMD5(const buff: TMD5);
begin
  WritePtr(@buff, 16);
end;

{ ----- Serialisation readers -------------------------------------------------- }
function TMS64.ReadBool: Boolean;
begin
  ReadPtr(@Result, 1);
end;

function TMS64.ReadInt8: ShortInt;
begin
  ReadPtr(@Result, 1);
end;

function TMS64.ReadInt16: SmallInt;
begin
  ReadPtr(@Result, 2);
end;

function TMS64.ReadInt32: Integer;
begin
  ReadPtr(@Result, 4);
end;

function TMS64.ReadInt64: Int64;
begin
  ReadPtr(@Result, 8);
end;

function TMS64.ReadInt128: Int128;
begin
  ReadPtr(@Result.b[0], 16);
end;

function TMS64.ReadUInt8: Byte;
begin
  ReadPtr(@Result, 1);
end;

function TMS64.ReadUInt16: Word;
begin
  ReadPtr(@Result, 2);
end;

function TMS64.ReadUInt32: Cardinal;
begin
  ReadPtr(@Result, 4);
end;

function TMS64.ReadUInt64: UInt64;
begin
  ReadPtr(@Result, 8);
end;

function TMS64.ReadUInt128: UInt128;
begin
  ReadPtr(@Result.b[0], 16);
end;

function TMS64.ReadSingle: Single;
begin
  ReadPtr(@Result, 4);
end;

function TMS64.ReadDouble: Double;
begin
  ReadPtr(@Result, 8);
end;

function TMS64.ReadCurrency: Currency;
begin
  Result := ReadDouble();
end;

function TMS64.PrepareReadString: Boolean;
{ * Checks if the stream contains a complete string (length + data). }
begin
  Result := (Position + 4 <= Size) and (Position + 4 + PCardinal(PositionAsPtr())^ <= Size);
end;

function TMS64.ReadString: TPascalString;
{ * Reads a UTF‑8 string with a 32‑bit length prefix.
  * Returns empty string on error.
}
var
  L: Cardinal;
  b: TBytes;
begin
  try
    L := ReadUInt32;
    if L > 0 then
      begin
        SetLength(b, L);
        ReadPtr(@b[0], L);
        Result.Bytes := b;
        SetLength(b, 0);
      end;
  except
      Result := '';
  end;
end;

function TMS64.ReadStringAsBuff: TBytes;
{ * Reads the raw UTF‑8 bytes of a string without decoding. }
var
  L: Cardinal;
begin
  try
    L := ReadUInt32;
    if L > 0 then
      begin
        SetLength(Result, L);
        ReadPtr(@Result[0], L);
      end
    else
        SetLength(Result, 0);
  except
      SetLength(Result, 0);
  end;
end;

procedure TMS64.IgnoreReadString;
{ * Skips a string by reading and discarding its data. }
var
  L: Cardinal;
  b: TBytes;
begin
  try
    L := ReadUInt32;
    if L > 0 then
      begin
        SetLength(b, L);
        ReadPtr(@b[0], L);
        SetLength(b, 0);
      end;
  except
  end;
end;

function TMS64.ReadANSI(L: Integer): TPascalString;
{ * Reads L bytes as ANSI and converts to TPascalString. }
var
  b: TBytes;
begin
  if L > 0 then
    begin
      SetLength(b, L);
      ReadPtr(@b[0], L);
      Result.ANSI := b;
      SetLength(b, 0);
    end;
end;

function TMS64.ReadMD5: TMD5;
begin
  ReadPtr(@Result, 16);
end;

{ *************** TMemoryStream64List *************** }

procedure TMemoryStream64List.Clean;
{ * Frees all streams in the list and clears the list. }
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
      DisposeObject(Items[i]);
  Clear;
end;

function TMemoryStream64List.To_Array: TMS64_Array;
var
  i: Integer;
begin
  SetLength(Result, Count);
  for i := 0 to Count - 1 do
      Result[i] := Items[i];
end;

{ *************** TMemoryStream64ThreadList *************** }

constructor TMemoryStream64ThreadList.Create;
begin
  inherited Create;
  FCritical := TCritical.Create;
  AutoFree_Stream := False;
end;

destructor TMemoryStream64ThreadList.Destroy;
begin
  DisposeObject(FCritical);
  Clear;
  inherited Destroy;
end;

procedure TMemoryStream64ThreadList.Lock;
begin
  FCritical.Lock;
end;

procedure TMemoryStream64ThreadList.UnLock;
begin
  FCritical.UnLock;
end;

procedure TMemoryStream64ThreadList.Remove(obj: TMS64);
begin
  if AutoFree_Stream then
      DisposeObject(obj);
  inherited Remove(obj);
end;

procedure TMemoryStream64ThreadList.Delete(index: Integer);
begin
  if (index >= 0) and (index < Count) then
    begin
      if AutoFree_Stream then
          DisposeObject(Items[index]);
      inherited Delete(index);
    end;
end;

procedure TMemoryStream64ThreadList.Clear;
var
  i: Integer;
begin
  if AutoFree_Stream then
    for i := 0 to Count - 1 do
        DisposeObject(Items[i]);
  inherited Clear;
end;

procedure TMemoryStream64ThreadList.Clean;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
      DisposeObject(Items[i]);
  inherited Clear;
end;

function TMemoryStream64ThreadList.To_Array: TMS64_Array;
var
  i: Integer;
begin
  SetLength(Result, Count);
  for i := 0 to Count - 1 do
      Result[i] := Items[i];
end;

{ *************** Triggered streams *************** }

constructor TMemoryStream64OfWriteTrigger.Create(ATrigger: IMemoryStream64WriteTrigger);
begin
  inherited Create;
  Trigger := ATrigger;
end;

function TMemoryStream64OfWriteTrigger.Write64(const buffer; Count: Int64): Int64;
begin
  Result := inherited Write64(buffer, Count);
  if Assigned(Trigger) then
      Trigger.TriggerWrite64(Count);
end;

constructor TMemoryStream64OfReadTrigger.Create(ATrigger: IMemoryStream64ReadTrigger);
begin
  inherited Create;
  Trigger := ATrigger;
end;

function TMemoryStream64OfReadTrigger.Read64(var buffer; Count: Int64): Int64;
begin
  Result := inherited Read64(buffer, Count);
  if Assigned(Trigger) then
      Trigger.TriggerRead64(Count);
end;

constructor TMemoryStream64OfReadWriteTrigger.Create(ATrigger: IMemoryStream64ReadWriteTrigger);
begin
  inherited Create;
  Trigger := ATrigger;
end;

function TMemoryStream64OfReadWriteTrigger.Read64(var buffer; Count: Int64): Int64;
begin
  Result := inherited Read64(buffer, Count);
  if Assigned(Trigger) then
      Trigger.TriggerRead64(Count);
end;

function TMemoryStream64OfReadWriteTrigger.Write64(const buffer; Count: Int64): Int64;
begin
  Result := inherited Write64(buffer, Count);
  if Assigned(Trigger) then
      Trigger.TriggerWrite64(Count);
end;

{ *************** TMem64 implementation *************** }

procedure TMem64.SetPointer(buffPtr: Pointer; const BuffSize: Int64);
begin
  FMemory := buffPtr;
  FSize := BuffSize;
end;

procedure TMem64.SetCapacity(NewCapacity: Int64);
begin
  if FProtectedMode then
      Exit;
  SetPointer(Realloc(NewCapacity), FSize);
  FCapacity := NewCapacity;
end;

function TMem64.Realloc(var NewCapacity: Int64): Pointer;
begin
  if FProtectedMode then
      Exit(nil);
  if (NewCapacity > 0) and (NewCapacity <> FSize) then
      NewCapacity := DeltaStep(NewCapacity, FDelta);
  Result := Memory;
  if NewCapacity <> FCapacity then
    begin
      if NewCapacity = 0 then
        begin
          System.FreeMemory(Memory);
          Result := nil;
        end
      else
        begin
          if Capacity = 0 then
              Result := System.GetMemory(NewCapacity)
          else
              Result := System.ReallocMemory(Result, NewCapacity);
          if Result = nil then
              RaiseInfo('%s Out of memory while expanding memory stream', [umlSizeToStr(NewCapacity).Text]);
        end;
    end;
end;

function TMem64.GetDelta: NativeInt;
begin
  Result := FDelta;
end;

procedure TMem64.SetDelta(const Value: NativeInt);
begin
  FDelta := umlClamp(Value, 64, 1024 * 1024);
end;

function TMem64.GetMemory_: Pointer;
begin
  Result := FMemory;
end;

function TMem64.GetPosition: Int64;
begin
  Result := Seek(0, TSeekOrigin.soCurrent);
end;

procedure TMem64.SetPosition(const Value: Int64);
begin
  Seek(Value, TSeekOrigin.soBeginning);
end;

function TMem64.GetSize: Int64;
var
  Pos_: Int64;
begin
  Pos_ := Seek(0, TSeekOrigin.soCurrent);
  Result := Seek(0, TSeekOrigin.soEnd);
  Seek(Pos_, TSeekOrigin.soBeginning);
end;

procedure TMem64.SetSize(const NewSize: Int64);
var
  OldPosition: Int64;
begin
  if FProtectedMode then
      Exit;
  OldPosition := FPosition;
  SetCapacity(NewSize);
  FSize := NewSize;
  if OldPosition > NewSize then
      Seek(0, TSeekOrigin.soEnd);
end;

constructor TMem64.Create;
begin
  CustomCreate(256);
end;

constructor TMem64.CustomCreate(const customDelta: NativeInt);
begin
  inherited Create;
  Delta := customDelta;
  FMemory := nil;
  FSize := 0;
  FPosition := 0;
  FCapacity := 0;
  FProtectedMode := False;
  FStream64 := nil;
end;

destructor TMem64.Destroy;
begin
  if FStream64 <> nil then
      DisposeObject(FStream64);
  Clear;
  inherited Destroy;
end;

function TMem64.Stream64(Mapping_Begin_As_Position_: Boolean): TMS64;
begin
  if FStream64 = nil then
      FStream64 := TMS64.Create;
  if Mapping_Begin_As_Position_ then
      FStream64.Mapping(PosAsPtr, Size - Position)
  else
      FStream64.Mapping(self);
  Result := FStream64;
end;

function TMem64.Stream64: TMS64;
begin
  Result := Stream64(False);
end;

function TMem64.NewClone: TMem64;
begin
  Result := TMem64.CustomCreate(FDelta);
  Result.Size := Size;
  CopyPtr(Memory, Result.Memory, Size);
  Result.Position := Position;
end;

function TMem64.Create_Mapping_Instance: TMem64;
begin
  Result := TMem64.Create;
  Result.Mapping(self);
end;

function TMem64.Create_Mapping_Instance_MS64: TMS64;
begin
  Result := TMS64.Create;
  Result.Mapping(self);
end;

function TMem64.Swap_To_New_Instance: TMem64;
begin
  Result := TMem64.Create;
  SwapInstance(Result);
end;

procedure TMem64.DiscardMemory;
begin
  if FProtectedMode then
      Exit;
  FMemory := nil;
  FSize := 0;
  FPosition := 0;
  FCapacity := 0;
end;

procedure TMem64.Clear;
begin
  if FProtectedMode then
      Exit;
  SetCapacity(0);
  FSize := 0;
  FPosition := 0;
end;

procedure TMem64.NewParam(source: TMS64);
begin
  Clear;
  FDelta := source.FDelta;
  FMemory := source.FMemory;
  FSize := source.FSize;
  FPosition := source.FPosition;
  FCapacity := source.FCapacity;
  FProtectedMode := source.FProtectedMode;
end;

procedure TMem64.NewParam(source: TMem64);
begin
  Clear;
  FDelta := source.FDelta;
  FMemory := source.FMemory;
  FSize := source.FSize;
  FPosition := source.FPosition;
  FCapacity := source.FCapacity;
  FProtectedMode := source.FProtectedMode;
end;

procedure TMem64.SwapInstance(source: TMS64);
var
  FDelta_: NativeInt;
  FMemory_: Pointer;
  FSize_: Int64;
  FPosition_: Int64;
  FCapacity_: Int64;
  FProtectedMode_: Boolean;
begin
  FDelta_ := FDelta;
  FMemory_ := FMemory;
  FSize_ := FSize;
  FPosition_ := FPosition;
  FCapacity_ := FCapacity;
  FProtectedMode_ := FProtectedMode;

  FDelta := source.FDelta;
  FMemory := source.FMemory;
  FSize := source.FSize;
  FPosition := source.FPosition;
  FCapacity := source.FCapacity;
  FProtectedMode := source.FProtectedMode;

  source.FDelta := FDelta_;
  source.FMemory := FMemory_;
  source.FSize := FSize_;
  source.FPosition := FPosition_;
  source.FCapacity := FCapacity_;
  source.FProtectedMode := FProtectedMode_;
end;

procedure TMem64.SwapInstance(source: TMem64);
var
  FDelta_: NativeInt;
  FMemory_: Pointer;
  FSize_: Int64;
  FPosition_: Int64;
  FCapacity_: Int64;
  FProtectedMode_: Boolean;
begin
  FDelta_ := FDelta;
  FMemory_ := FMemory;
  FSize_ := FSize;
  FPosition_ := FPosition;
  FCapacity_ := FCapacity;
  FProtectedMode_ := FProtectedMode;

  FDelta := source.FDelta;
  FMemory := source.FMemory;
  FSize := source.FSize;
  FPosition := source.FPosition;
  FCapacity := source.FCapacity;
  FProtectedMode := source.FProtectedMode;

  source.FDelta := FDelta_;
  source.FMemory := FMemory_;
  source.FSize := FSize_;
  source.FPosition := FPosition_;
  source.FCapacity := FCapacity_;
  source.FProtectedMode := FProtectedMode_;
end;

function TMem64.ToBytes: TBytes;
begin
  SetLength(Result, Size);
  if Size > 0 then
      CopyPtr(Memory, @Result[0], Size);
end;

function TMem64.ToMD5: TMD5;
begin
  Result := umlMD5(Memory, Size);
end;

function TMem64.LZ4: TMem64;
var
  comp_size: Int64;
begin
  Result := TMem64.Create;
  Result.Size := LZ4_compressBound64(Size) + 16;
  PInt64(Result.PosAsPtr(0))^ := Size;
  comp_size := LZ4_compress_default64(Memory^, Size, Result.PosAsPtr(16)^, LZ4_compressBound64(Size));
  PInt64(Result.PosAsPtr(8))^ := comp_size;
  Result.Size := comp_size + 16;
end;

function TMem64.UnLZ4: TMem64;
var
  comp_size: Int64;
begin
  Result := TMem64.Create;
  Result.Size := PInt64(PosAsPtr(0))^;
  comp_size := PInt64(PosAsPtr(8))^;
  LZ4_decompress_safe64(PosAsPtr(16)^, comp_size, Result.Memory^, Result.Size);
end;

function TMem64.Snappy_Pas: TMem64;
var
  comp_size: Int64;
begin
  Result := TMem64.Create;
  Result.Size := SnappyMaxCompressedLength64(Size) + 16;
  comp_size := Result.Size;
  PInt64(Result.PosAsPtr(0))^ := Size;
  SnappyCompress(Memory, Size, Result.PosAsPtr(16), comp_size);
  PInt64(Result.PosAsPtr(8))^ := comp_size;
  Result.Size := comp_size + 16;
end;

function TMem64.UnSnappy_Pas: TMem64;
var
  OutputSize: Int64;
  comp_size: Int64;
begin
  Result := TMem64.Create;
  Result.Size := PInt64(PosAsPtr(0))^;
  OutputSize := Result.Size;
  comp_size := PInt64(PosAsPtr(8))^;
  SnappyDecompress(PosAsPtr(16), comp_size, Result.Memory, OutputSize);
end;

procedure TMem64.SetPointerWithProtectedMode(buffPtr: Pointer; const BuffSize: Int64);
begin
  Mapping(buffPtr, BuffSize);
end;

procedure TMem64.Mapping(buffPtr: Pointer; const BuffSize: Int64);
begin
  Clear;
  FMemory := buffPtr;
  FSize := BuffSize;
  FPosition := 0;
  FProtectedMode := True;
end;

procedure TMem64.Mapping(m64: TMS64);
begin
  Mapping(m64.Memory, m64.Size);
end;

procedure TMem64.Mapping(m64: TMem64);
begin
  Mapping(m64.Memory, m64.Size);
end;

function TMem64.PositionAsPtr(const Position_: Int64): Pointer;
begin
  Result := GetOffset(FMemory, Position_);
end;

function TMem64.PositionAsPtr: Pointer;
begin
  Result := GetOffset(FMemory, FPosition);
end;

function TMem64.PosAsPtr(const Position_: Int64): Pointer;
begin
  Result := PositionAsPtr(Position_);
end;

function TMem64.PosAsPtr: Pointer;
begin
  Result := PositionAsPtr();
end;

procedure TMem64.LoadFromStream(stream: TCore_Stream);
begin
  if FProtectedMode then
      Exit;
  Clear;
  stream.Position := 0;
  if CopyFrom(stream, stream.Size) <> stream.Size then
      RaiseInfo('load stream error.');
  Position := 0;
end;

procedure TMem64.LoadFromFile(FileName: SystemString);
var
  stream: TCore_Stream;
begin
  stream := TCore_FileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
      LoadFromStream(stream);
  finally
      DisposeObject(stream);
  end;
end;

procedure TMem64.SaveToStream(stream: TCore_Stream);
const
  ChunkSize = 64 * 1024 * 1024;
var
  p: Pointer;
  j: NativeInt;
  Num: NativeInt;
  Rest: NativeInt;
begin
  if Size > 0 then
    begin
      p := FMemory;
      if Size > ChunkSize then
        begin
          Num := Size div ChunkSize;
          Rest := Size mod ChunkSize;
          for j := 0 to Num - 1 do
            begin
              stream.WriteBuffer(p^, ChunkSize);
              p := GetOffset(p, ChunkSize);
            end;
          if Rest > 0 then
            begin
              stream.WriteBuffer(p^, Rest);
              p := GetOffset(p, Rest);
            end;
        end
      else
          stream.WriteBuffer(p^, Size);
    end;
end;

procedure TMem64.SaveToFile(FileName: SystemString);
var
  stream: TCore_Stream;
begin
  stream := TCore_FileStream.Create(FileName, fmCreate);
  try
      SaveToStream(stream);
  finally
      DisposeObject(stream);
  end;
end;

function TMem64.Write64(const buffer; Count: Int64): Int64;
var
  p: Int64;
begin
  if (Count > 0) then
    begin
      p := FPosition;
      p := p + Count;
      if p > 0 then
        begin
          if p > FSize then
            begin
              if FProtectedMode then
                begin
                  Result := 0;
                  Exit;
                end;
              if p > FCapacity then
                  SetCapacity(p);
              FSize := p;
            end;
          CopyPtr(@buffer, GetOffset(FMemory, FPosition), Count);
          FPosition := p;
          Result := Count;
          Exit;
        end;
    end;
  Result := 0;
end;

function TMem64.WritePtr(const p: Pointer; Count: Int64): Int64;
begin
  Result := Write64(p^, Count);
end;

function TMem64.write(const buffer; Count: Int64): Int64;
begin
  Result := Write64(buffer, Count);
end;

function TMem64.WriteBytes(const buffer: TBytes): Int64;
begin
  if Length(buffer) > 0 then
      Result := WritePtr(@buffer[0], Length(buffer))
  else
      Result := 0;
end;

function TMem64.Read64(var buffer; Count: Int64): Int64;
begin
  if Count > 0 then
    begin
      Result := FSize - FPosition;
      if Result > 0 then
        begin
          if Result > Count then
              Result := Count;
          CopyPtr(GetOffset(FMemory, FPosition), @buffer, Result);
          inc(FPosition, Result);
          Exit;
        end;
    end;
  Result := 0;
end;

function TMem64.ReadPtr(const p: Pointer; Count: Int64): Int64;
begin
  Result := Read64(p^, Count);
end;

function TMem64.read(var buffer; Count: Int64): Int64;
begin
  Result := Read64(buffer, Count);
end;

function TMem64.Seek(const Offset: Int64; origin: TSeekOrigin): Int64;
begin
  case origin of
    TSeekOrigin.soBeginning: FPosition := Offset;
    TSeekOrigin.soCurrent: inc(FPosition, Offset);
    TSeekOrigin.soEnd: FPosition := FSize + Offset;
  end;
  Result := FPosition;
end;

function TMem64.CopyFrom(const source: TCore_Stream; Count: Int64): Int64;
const
  MaxBufSize = $F000;
var
  BufSize, n, p: Int64;
begin
  if FProtectedMode then
      RaiseInfo('protected mode');
  if Count = 0 then
      Exit(0);
  if Count < 0 then
    begin
      source.Position := 0;
      Count := source.Size;
    end;
  if source is TMS64 then
    begin
      WritePtr(TMS64(source).PositionAsPtr, Count);
      TMS64(source).Position := TMS64(source).FPosition + Count;
      Result := Count;
      Exit;
    end;
  Result := Count;
  if Count > MaxBufSize then
      BufSize := MaxBufSize
  else
      BufSize := Count;
  p := Position;
  if p + Count > Size then
      Size := p + Count;
  while Count <> 0 do
    begin
      if Count > BufSize then
          n := BufSize
      else
          n := Count;
      if source.read(PosAsPtr(p)^, n) <> n then
          RaiseInfo('stream read error.');
      inc(p, n);
      dec(Count, n);
    end;
  Position := p;
end;

function TMem64.CopyFrom(const source: TMem64; Count: Int64): Int64;
begin
  if FProtectedMode then
      RaiseInfo('protected mode');
  WritePtr(source.PositionAsPtr, Count);
  source.Position := source.FPosition + Count;
  Result := Count;
end;

{ ----- Serialisation writers for TMem64 (identical to TMS64) ----------------- }
procedure TMem64.WriteBool(const buff: Boolean);
begin
  WritePtr(@buff, 1);
end;

procedure TMem64.WriteInt8(const buff: ShortInt);
begin
  WritePtr(@buff, 1);
end;

procedure TMem64.WriteInt16(const buff: SmallInt);
begin
  WritePtr(@buff, 2);
end;

procedure TMem64.WriteInt32(const buff: Integer);
begin
  WritePtr(@buff, 4);
end;

procedure TMem64.WriteInt64(const buff: Int64);
begin
  WritePtr(@buff, 8);
end;

procedure TMem64.WriteInt128(const buff: Int128);
begin
  WritePtr(@buff.b[0], 16);
end;

procedure TMem64.WriteUInt8(const buff: Byte);
begin
  WritePtr(@buff, 1);
end;

procedure TMem64.WriteUInt16(const buff: Word);
begin
  WritePtr(@buff, 2);
end;

procedure TMem64.WriteUInt32(const buff: Cardinal);
begin
  WritePtr(@buff, 4);
end;

procedure TMem64.WriteUInt64(const buff: UInt64);
begin
  WritePtr(@buff, 8);
end;

procedure TMem64.WriteUInt128(const buff: UInt128);
begin
  WritePtr(@buff.b[0], 16);
end;

procedure TMem64.WriteSingle(const buff: Single);
begin
  WritePtr(@buff, 4);
end;

procedure TMem64.WriteDouble(const buff: Double);
begin
  WritePtr(@buff, 8);
end;

procedure TMem64.WriteCurrency(const buff: Currency);
begin
  WriteDouble(buff);
end;

procedure TMem64.WriteString(const buff: TPascalString);
var
  b: TBytes;
begin
  b := buff.Bytes;
  WriteUInt32(Length(b));
  if Length(b) > 0 then
    begin
      WritePtr(@b[0], Length(b));
      SetLength(b, 0);
    end;
end;

procedure TMem64.WriteANSI(const buff: TPascalString);
var
  b: TBytes;
begin
  b := buff.ANSI;
  if Length(b) > 0 then
    begin
      WritePtr(@b[0], Length(b));
      SetLength(b, 0);
    end;
end;

procedure TMem64.WriteANSI(const buff: TPascalString; const L: Integer);
var
  b: TBytes;
begin
  b := buff.ANSI;
  if L > 0 then
    begin
      WritePtr(@b[0], L);
      SetLength(b, 0);
    end;
end;

procedure TMem64.WriteMD5(const buff: TMD5);
begin
  WritePtr(@buff, 16);
end;

{ ----- Serialisation readers for TMem64 -------------------------------------- }
function TMem64.ReadBool: Boolean;
begin
  ReadPtr(@Result, 1);
end;

function TMem64.ReadInt8: ShortInt;
begin
  ReadPtr(@Result, 1);
end;

function TMem64.ReadInt16: SmallInt;
begin
  ReadPtr(@Result, 2);
end;

function TMem64.ReadInt32: Integer;
begin
  ReadPtr(@Result, 4);
end;

function TMem64.ReadInt64: Int64;
begin
  ReadPtr(@Result, 8);
end;

function TMem64.ReadInt128: Int128;
begin
  ReadPtr(@Result.b[0], 16);
end;

function TMem64.ReadUInt8: Byte;
begin
  ReadPtr(@Result, 1);
end;

function TMem64.ReadUInt16: Word;
begin
  ReadPtr(@Result, 2);
end;

function TMem64.ReadUInt32: Cardinal;
begin
  ReadPtr(@Result, 4);
end;

function TMem64.ReadUInt64: UInt64;
begin
  ReadPtr(@Result, 8);
end;

function TMem64.ReadUInt128: UInt128;
begin
  ReadPtr(@Result.b[0], 16);
end;

function TMem64.ReadSingle: Single;
begin
  ReadPtr(@Result, 4);
end;

function TMem64.ReadDouble: Double;
begin
  ReadPtr(@Result, 8);
end;

function TMem64.ReadCurrency: Currency;
begin
  Result := ReadDouble();
end;

function TMem64.PrepareReadString: Boolean;
begin
  Result := (Position + 4 <= Size) and (Position + 4 + PCardinal(PositionAsPtr())^ <= Size);
end;

function TMem64.ReadString: TPascalString;
var
  L: Cardinal;
  b: TBytes;
begin
  L := ReadUInt32;
  if L > 0 then
    begin
      try
        SetLength(b, L);
        ReadPtr(@b[0], L);
        Result.Bytes := b;
        SetLength(b, 0);
      except
          Result := '';
      end;
    end;
end;

function TMem64.ReadStringAsBuff: TBytes;
var
  L: Cardinal;
begin
  try
    L := ReadUInt32;
    if L > 0 then
      begin
        SetLength(Result, L);
        ReadPtr(@Result[0], L);
      end
    else
        SetLength(Result, 0);
  except
      SetLength(Result, 0);
  end;
end;

procedure TMem64.IgnoreReadString;
var
  L: Cardinal;
  b: TBytes;
begin
  L := ReadUInt32;
  if L > 0 then
    begin
      try
        SetLength(b, L);
        ReadPtr(@b[0], L);
        SetLength(b, 0);
      except
      end;
    end;
end;

function TMem64.ReadANSI(L: Integer): TPascalString;
var
  b: TBytes;
begin
  if L > 0 then
    begin
      SetLength(b, L);
      ReadPtr(@b[0], L);
      Result.ANSI := b;
      SetLength(b, 0);
    end;
end;

function TMem64.ReadMD5: TMD5;
begin
  ReadPtr(@Result, 16);
end;

{ *************** TMem64List *************** }

procedure TMem64List.Clean;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
      DisposeObject(Items[i]);
  Clear;
end;

{ *************** ZLIB wrappers (FPC) *************** }

{$IFDEF FPC}

constructor TCompressionStream.Create(stream: TCore_Stream);
begin
  inherited Create(clFastest, stream);
end;

constructor TCompressionStream.Create(level: Tcompressionlevel; stream: TCore_Stream);
begin
  inherited Create(level, stream);
end;
{$ENDIF}

{ *************** Compression and Decompression Functions *************** }

function MaxCompressStream(sour, dest: TCore_Stream): Boolean;
{ *
  * Compresses using maximum ZLIB compression (clMax).
  * Writes original size (8 bytes) first.
}
var
  cStream: TCompressionStream;
  siz_: Int64;
begin
  Result := False;
  try
    siz_ := sour.Size;
    dest.WriteBuffer(siz_, 8);
    if sour.Size > 0 then
      begin
        sour.Position := 0;
        cStream := TCompressionStream.Create(clMax, dest);
        Result := cStream.CopyFrom(sour, siz_) = siz_;
        DisposeObject(cStream);
      end;
  except
  end;
end;

function FastCompressStream(sour, dest: TCore_Stream): Boolean;
{ *
  * Fast ZLIB compression (clFastest).
}
var
  cStream: TCompressionStream;
  siz_: Int64;
begin
  Result := False;
  try
    siz_ := sour.Size;
    dest.WriteBuffer(siz_, 8);
    if sour.Size > 0 then
      begin
        sour.Position := 0;
        cStream := TCompressionStream.Create(clFastest, dest);
        Result := cStream.CopyFrom(sour, siz_) = siz_;
        DisposeObject(cStream);
      end;
  except
  end;
end;

function CompressStream(sour, dest: TCore_Stream): Boolean;
{ *
  * Standard ZLIB compression (clDefault).
}
var
  cStream: TCompressionStream;
  siz_: Int64;
begin
  Result := False;
  try
    siz_ := sour.Size;
    dest.WriteBuffer(siz_, 8);
    if sour.Size > 0 then
      begin
        sour.Position := 0;
        cStream := TCompressionStream.Create(clDefault, dest);
        Result := cStream.CopyFrom(sour, siz_) = siz_;
        DisposeObject(cStream);
      end;
  except
  end;
end;

function DecompressStream(DataPtr: Pointer; siz: NativeInt; dest: TCore_Stream): Boolean;
{ *
  * Decompresses data from a memory pointer by wrapping it in a TMS64.
}
var
  m64: TMS64;
begin
  m64 := TMS64.Create;
  m64.SetPointer(DataPtr, siz);
  Result := DecompressStream(m64, dest);
  DisposeObject(m64);
end;

function DecompressStream(sour: TCore_Stream; dest: TCore_Stream): Boolean;
{ *
  * Decompresses ZLIB data. Reads original size, then decompresses into dest.
}
var
  dcStream: TDecompressionStream;
  dSiz: Int64;
  iPos: Int64;
begin
  Result := False;
  sour.ReadBuffer(dSiz, 8);
  if dSiz > 0 then
    begin
      iPos := dest.Position;
      dest.Size := iPos + dSiz;
      dest.Position := iPos;
      try
        dcStream := TDecompressionStream.Create(sour);
        Result := dest.CopyFrom(dcStream, dSiz) = dSiz;
        DisposeObject(dcStream);
      except
      end;
    end;
end;

function DecompressStreamToPtr(sour: TCore_Stream; var dest: Pointer): Boolean;
{ *
  * Decompresses data into a newly allocated memory block.
  * The caller must free the returned pointer.
}
var
  dcStream: TDecompressionStream;
  dSiz: Int64;
begin
  Result := False;
  try
    sour.ReadBuffer(dSiz, 8);
    if dSiz > 0 then
      begin
        dcStream := TDecompressionStream.Create(sour);
        dest := System.GetMemory(dSiz);
        Result := dcStream.read(dest^, dSiz) = dSiz;
        DisposeObject(dcStream);
      end;
  except
  end;
end;

function CompressFile(sour, dest: SystemString): Boolean;
{ *
  * Compresses a file using standard ZLIB.
}
var
  s_fs, d_fs: TCore_FileStream;
begin
  s_fs := TCore_FileStream.Create(sour, fmOpenRead or fmShareDenyNone);
  d_fs := TCore_FileStream.Create(dest, fmCreate);
  Result := CompressStream(s_fs, d_fs);
  DisposeObject(s_fs);
  DisposeObject(d_fs);
end;

function DecompressFile(sour, dest: SystemString): Boolean;
var
  s_fs, d_fs: TCore_FileStream;
begin
  s_fs := TCore_FileStream.Create(sour, fmOpenRead or fmShareDenyNone);
  d_fs := TCore_FileStream.Create(dest, fmCreate);
  Result := DecompressStream(s_fs, d_fs);
  DisposeObject(s_fs);
  DisposeObject(d_fs);
end;

function SelectCompressStream(const scm: TSelectCompressionMethod; const sour, dest: TCore_Stream): Boolean;
{ *
  * Compresses using a selected method. Writes a single‑byte method identifier
  * before the compressed data. For LZ4 and Snappy, uses the built‑in TMS64 methods.
}
var
  scm_b: Byte;
  siz_: Int64;
  tmpSour, tmpDest: TMS64;
begin
  Result := False;
  scm_b := Byte(scm);
  if dest.write(scm_b, 1) <> 1 then
      Exit;
  sour.Position := 0;
  try
    case scm of
      scmNone:
        begin
          siz_ := sour.Size;
          dest.write(siz_, 8);
          Result := dest.CopyFrom(sour, siz_) = siz_;
        end;
      scmZLIB: Result := CompressStream(sour, dest);
      scmZLIB_Fast: Result := FastCompressStream(sour, dest);
      scmZLIB_Max: Result := MaxCompressStream(sour, dest);
      scmDeflate: Result := DeflateCompressStream(sour, dest);
      scmBRRC: Result := BRRCCompressStream(sour, dest);
      scmLZ4:
        begin
          tmpSour := TMS64.Create;
          if sour is TMS64 then
              tmpSour.Mapping(TMS64(sour))
          else
              tmpSour.LoadFromStream(sour);
          tmpDest := tmpSour.LZ4;
          DisposeObject(tmpSour);
          dest.write(tmpDest.Memory^, tmpDest.Size);
          DisposeObject(tmpDest);
          Result := True;
        end;
      scmSnappy_Pas:
        begin
          tmpSour := TMS64.Create;
          if sour is TMS64 then
              tmpSour.Mapping(TMS64(sour))
          else
              tmpSour.LoadFromStream(sour);
          tmpDest := tmpSour.Snappy_Pas;
          DisposeObject(tmpSour);
          dest.write(tmpDest.Memory^, tmpDest.Size);
          DisposeObject(tmpDest);
          Result := True;
        end;
    end;
  except
  end;
end;

function SelectDecompressStream(const sour, dest: TCore_Stream): Boolean;
var
  scm: TSelectCompressionMethod;
begin
  Result := SelectDecompressStream(sour, dest, scm);
end;

function SelectDecompressStream(const sour, dest: TCore_Stream; var scm: TSelectCompressionMethod): Boolean;
{ *
  * Auto‑detects compression method from the first byte and decompresses.
  * For LZ4 and Snappy, uses TMS64 methods.
}
var
  scm_: Byte;
  siz_: Int64;
  tmpSour, tmpDest: TMS64;
begin
  Result := False;
  if sour.read(scm_, 1) <> 1 then
      Exit;
  scm := TSelectCompressionMethod(scm_);
  try
    case scm of
      scmNone:
        begin
          if sour.read(siz_, 8) <> 8 then
              Exit;
          Result := dest.CopyFrom(sour, siz_) = siz_;
        end;
      scmZLIB, scmZLIB_Fast, scmZLIB_Max: Result := DecompressStream(sour, dest);
      scmDeflate: Result := DeflateDecompressStream(sour, dest);
      scmBRRC: Result := BRRCDecompressStream(sour, dest);
      scmLZ4:
        begin
          tmpSour := TMS64.Create;
          if sour is TMS64 then
              tmpSour.Mapping(TMS64(sour).PosAsPtr, TMS64(sour).Size - TMS64(sour).Position)
          else
              tmpSour.CopyFrom(sour, sour.Size - sour.Position);
          tmpDest := tmpSour.UnLZ4;
          DisposeObject(tmpSour);
          if dest is TMS64 then
              TMS64(dest).SwapInstance(tmpDest)
          else
              tmpDest.SaveToStream(dest);
          DisposeObject(tmpDest);
          Result := True;
        end;
      scmSnappy_Pas:
        begin
          tmpSour := TMS64.Create;
          if sour is TMS64 then
              tmpSour.Mapping(TMS64(sour).PosAsPtr, TMS64(sour).Size - TMS64(sour).Position)
          else
              tmpSour.CopyFrom(sour, sour.Size - sour.Position);
          tmpDest := tmpSour.UnSnappy_Pas;
          DisposeObject(tmpSour);
          if dest is TMS64 then
              TMS64(dest).SwapInstance(tmpDest)
          else
              tmpDest.SaveToStream(dest);
          DisposeObject(tmpDest);
          Result := True;
        end;
    end;
  except
  end;
end;

{ *************** Parallel Compression/Decompression *************** }

procedure ParallelCompressMemory(const ThNum: Integer; const scm: TSelectCompressionMethod; const StripNum_: Integer; const sour: TMS64; const dest: TCore_Stream);
{ *
  * Splits the source stream into strips, compresses each in parallel,
  * and writes them to dest with a header:
  *   [StripCount: Int32] [StripSize: Int64] [Data].
}
var
  StripNum: Integer;
  sourStrips: TStream64List;
  StripArry: array of TMS64;
{$IFDEF Parallel}
{$IFDEF FPC}
  procedure Nested_ParallelFor(pass: Integer);
  begin
    SelectCompressStream(scm, sourStrips[pass], StripArry[pass]);
  end;
{$ENDIF FPC}
{$ENDIF Parallel}
  procedure DoFor;
  var
    pass: Integer;
  begin
    for pass := 0 to Length(StripArry) - 1 do
        SelectCompressStream(scm, sourStrips[pass], StripArry[pass]);
  end;
  procedure BuildBuff;
  var
    strip_siz, strip_m: Int64;
    p: Int64;
    m64: TMS64;
    i: Integer;
  begin
    sourStrips := TStream64List.Create;
    strip_siz := sour.Size div StripNum;
    p := 0;
    while True do
      begin
        if p + strip_siz < sour.Size then
          begin
            m64 := TMS64.Create;
            m64.SetPointerWithProtectedMode(sour.PositionAsPtr(p), strip_siz);
            sourStrips.Add(m64);
            inc(p, strip_siz);
          end
        else
          begin
            if sour.Size - p > 0 then
              begin
                m64 := TMS64.Create;
                m64.SetPointerWithProtectedMode(sour.PositionAsPtr(p), sour.Size - p);
                sourStrips.Add(m64);
              end;
            break;
          end;
      end;
    SetLength(StripArry, sourStrips.Count);
    for i := 0 to sourStrips.Count - 1 do
        StripArry[i] := TMS64.CustomCreate(1024);
  end;
  procedure BuildOutput;
  var
    L: Integer;
    siz_: Int64;
    i: Integer;
  begin
    L := Length(StripArry);
    dest.write(L, 4);
    for i := 0 to L - 1 do
      begin
        siz_ := StripArry[i].Size;
        dest.write(siz_, 8);
        dest.write(StripArry[i].Memory^, StripArry[i].Size);
        DisposeObject(sourStrips[i]);
        DisposeObject(StripArry[i]);
      end;
  end;
  procedure FreeBuff;
  begin
    DisposeObject(sourStrips);
    SetLength(StripArry, 0);
  end;

begin
  if StripNum_ <= 0 then
      StripNum := 1
  else
      StripNum := StripNum_;
  BuildBuff;
  if Length(StripArry) < ThNum then
    begin
      DoFor;
    end
  else
    begin
{$IFDEF Parallel}
{$IFDEF FPC}
      FPCParallelFor(ThNum, True, 0, Length(StripArry) - 1, Nested_ParallelFor);
{$ELSE FPC}
      DelphiParallelFor(ThNum, True, 0, Length(StripArry) - 1,
          procedure(pass: Integer)
        begin
          SelectCompressStream(scm, sourStrips[pass], StripArry[pass]);
        end);
{$ENDIF FPC}
{$ELSE Parallel}
      DoFor;
{$ENDIF Parallel}
    end;
  BuildOutput;
  FreeBuff;
end;

procedure ParallelCompressMemory(const scm: TSelectCompressionMethod; const StripNum_: Integer; const sour: TMS64; const dest: TCore_Stream);
begin
  ParallelCompressMemory(umlMin(4, Get_Parallel_Granularity), scm, StripNum_, sour, dest);
end;

procedure ParallelCompressMemory(const scm: TSelectCompressionMethod; const sour: TMS64; const dest: TCore_Stream);
begin
  ParallelCompressMemory(scm, sour.Size div (16 * 1024), sour, dest);
end;

procedure ParallelCompressMemory(const sour: TMS64; const dest: TCore_Stream);
begin
  ParallelCompressMemory(scmZLIB, sour, dest);
end;

procedure ParallelDecompressStream(const ThNum: Integer; const sour_, dest_: TCore_Stream);
{ *
  * Parallel decompression: reads strip headers, decompresses each strip in parallel,
  * and writes the results sequentially.
}
type
  TPara_strip_ = record
    sour, dest: TMS64;
  end;

  PPara_strip_ = ^TPara_strip_;
var
  StripArry: array of TPara_strip_;
{$IFDEF Parallel}
{$IFDEF FPC}
  procedure Nested_ParallelFor(pass: Integer);
  begin
    SelectDecompressStream(StripArry[pass].sour, StripArry[pass].dest);
  end;
{$ENDIF FPC}
{$ELSE Parallel}
{$ENDIF Parallel}
  procedure DoFor;
  var
    pass: Integer;
  begin
    for pass := 0 to Length(StripArry) - 1 do
        SelectDecompressStream(StripArry[pass].sour, StripArry[pass].dest);
  end;
  function BuildBuff_Stream64(stream: TMS64): Boolean;
  var
    strip_num: Integer;
    i: Integer;
    p, siz_, ss: Int64;
  begin
    Result := False;
    ss := stream.Size;
    p := stream.Position;
    if p + 4 > ss then
        Exit;
    strip_num := PInteger(stream.PositionAsPtr(p))^;
    inc(p, 4);
    SetLength(StripArry, strip_num);
    for i := 0 to strip_num - 1 do
      begin
        StripArry[i].sour := TMS64.Create;
        if p + 4 > ss then
            Exit;
        siz_ := PInt64(stream.PositionAsPtr(p))^;
        inc(p, 8);
        if p + siz_ > ss then
            Exit;
        StripArry[i].sour.SetPointerWithProtectedMode(stream.PositionAsPtr(p), siz_);
        inc(p, siz_);
        StripArry[i].sour.Position := 0;
        StripArry[i].dest := TMS64.CustomCreate(1024);
      end;
    stream.Position := p;
    Result := True;
  end;
  function BuildBuff_Stream(stream: TCore_Stream): Boolean;
  var
    strip_num: Integer;
    i: Integer;
    siz_: Int64;
  begin
    Result := False;
    if stream.read(strip_num, 4) <> 4 then
        Exit;
    SetLength(StripArry, strip_num);
    for i := 0 to strip_num - 1 do
      begin
        StripArry[i].sour := TMS64.CustomCreate(1024);
        StripArry[i].dest := TMS64.CustomCreate(1024);
      end;
    for i := 0 to strip_num - 1 do
      begin
        if stream.read(siz_, 8) <> 8 then
            Exit;
        if StripArry[i].sour.CopyFrom(stream, siz_) <> siz_ then
            Exit;
        StripArry[i].sour.Position := 0;
      end;
    Result := True;
  end;
  procedure BuildOutput;
  var
    i: Integer;
  begin
    for i := 0 to Length(StripArry) - 1 do
      begin
        dest_.write(StripArry[i].dest.Memory^, StripArry[i].dest.Size);
        DisposeObject(StripArry[i].sour);
        DisposeObject(StripArry[i].dest);
      end;
  end;
  procedure FreeBuff;
  begin
    SetLength(StripArry, 0);
  end;

var
  preDone: Boolean;
begin
  if sour_ is TMS64 then
      preDone := BuildBuff_Stream64(TMS64(sour_))
  else
      preDone := BuildBuff_Stream(sour_);
  if not preDone then
    begin
      FreeBuff;
      Exit;
    end;
  if Length(StripArry) < ThNum then
    begin
      DoFor;
    end
  else
    begin
{$IFDEF Parallel}
{$IFDEF FPC}
      FPCParallelFor(ThNum, True, 0, Length(StripArry) - 1, Nested_ParallelFor);
{$ELSE FPC}
      DelphiParallelFor(ThNum, True, 0, Length(StripArry) - 1,
        procedure(pass: Integer)
        begin
          SelectDecompressStream(StripArry[pass].sour, StripArry[pass].dest);
        end);
{$ENDIF FPC}
{$ELSE Parallel}
      DoFor;
{$ENDIF Parallel}
    end;
  BuildOutput;
  FreeBuff;
end;

procedure ParallelDecompressStream(const sour_, dest_: TCore_Stream);
begin
  ParallelDecompressStream(umlMin(4, Get_Parallel_Granularity), sour_, dest_);
end;

procedure ParallelCompressFile(const sour, dest: SystemString);
var
  s_fs: TMS64;
  d_fs: TCore_FileStream;
begin
  s_fs := TMS64.Create;
  s_fs.LoadFromFile(sour);
  d_fs := TCore_FileStream.Create(dest, fmCreate);
  ParallelCompressMemory(s_fs, d_fs);
  DisposeObject(s_fs);
  DisposeObject(d_fs);
end;

procedure ParallelDecompressFile(const sour, dest: SystemString);
var
  s_fs: TMS64;
  d_fs: TCore_FileStream;
begin
  s_fs := TMS64.Create;
  s_fs.LoadFromFile(sour);
  d_fs := TCore_FileStream.Create(dest, fmCreate);
  ParallelDecompressStream(s_fs, d_fs);
  DisposeObject(s_fs);
  DisposeObject(d_fs);
end;

function CompressUTF8(const sour_: TBytes): TBytes;
{ *
  * Compresses a UTF‑8 byte array. If compression saves space, adds a header
  * [FF FF][OriginalSize: Int32][CompressedData]; otherwise returns original data.
}
var
  cStream: TCompressionStream;
  dest: TMS64;
begin
  if Length(sour_) > 10 then
    begin
      dest := TMS64.Create;
      cStream := TCompressionStream.Create(clMax, dest);
      cStream.write(sour_[0], Length(sour_));
      DisposeObject(cStream);
      if dest.Size + 6 < Length(sour_) then
        begin
          SetLength(Result, dest.Size + 6);
          Result[0] := $FF;
          Result[1] := $FF;
          PInteger(@Result[2])^ := Length(sour_);
          CopyPtr(dest.Memory, @Result[6], dest.Size);
        end
      else
          Result := sour_;
      DisposeObject(dest);
    end
  else
      Result := sour_;
end;

function DecompressUTF8(const sour_: TBytes): TBytes;
{ *
  * Decompresses data created by CompressUTF8. Checks for header [FF FF],
  * reads original size, and decompresses.
}
var
  dcStream: TDecompressionStream;
  sour: TMS64;
  siz: Integer;
begin
  if Length(sour_) > 6 then
    begin
      if (sour_[0] = $FF) and (sour_[1] = $FF) then
        begin
          siz := PInteger(@sour_[2])^;
          sour := TMS64.Create();
          sour.SetPointer(@sour_[6], Length(sour_) - 6);
          dcStream := TDecompressionStream.Create(sour);
          SetLength(Result, siz);
          dcStream.read(Result[0], siz);
          DisposeObject(sour);
          DisposeObject(dcStream);
        end
      else
          Result := sour_;
    end
  else
      Result := sour_;
end;

{ *************** Global Serialisation Functions *************** }

procedure StreamWriteBool(const stream: TCore_Stream; const buff: Boolean);
begin
  stream.write(buff, 1);
end;

procedure StreamWriteInt8(const stream: TCore_Stream; const buff: ShortInt);
begin
  stream.write(buff, 1);
end;

procedure StreamWriteInt16(const stream: TCore_Stream; const buff: SmallInt);
begin
  stream.write(buff, 2);
end;

procedure StreamWriteInt32(const stream: TCore_Stream; const buff: Integer);
begin
  stream.write(buff, 4);
end;

procedure StreamWriteInt64(const stream: TCore_Stream; const buff: Int64);
begin
  stream.write(buff, 8);
end;

procedure StreamWriteInt128(const stream: TCore_Stream; const buff: Int128);
begin
  stream.write(buff.b[0], 16);
end;

procedure StreamWriteUInt8(const stream: TCore_Stream; const buff: Byte);
begin
  stream.write(buff, 1);
end;

procedure StreamWriteUInt16(const stream: TCore_Stream; const buff: Word);
begin
  stream.write(buff, 2);
end;

procedure StreamWriteUInt32(const stream: TCore_Stream; const buff: Cardinal);
begin
  stream.write(buff, 4);
end;

procedure StreamWriteUInt64(const stream: TCore_Stream; const buff: UInt64);
begin
  stream.write(buff, 8);
end;

procedure StreamWriteUInt128(const stream: TCore_Stream; const buff: UInt128);
begin
  stream.write(buff.b[0], 16);
end;

procedure StreamWriteSingle(const stream: TCore_Stream; const buff: Single);
begin
  stream.write(buff, 4);
end;

procedure StreamWriteDouble(const stream: TCore_Stream; const buff: Double);
begin
  stream.write(buff, 8);
end;

procedure StreamWriteCurrency(const stream: TCore_Stream; const buff: Currency);
begin
  StreamWriteDouble(stream, buff);
end;

procedure StreamWriteString(const stream: TCore_Stream; const buff: TPascalString);
{ * Writes a string with length prefix (UInt32) and UTF‑8 bytes. }
var
  b: TBytes;
begin
  b := buff.Bytes;
  StreamWriteUInt32(stream, Length(b));
  if Length(b) > 0 then
    begin
      stream.write(b[0], Length(b));
      SetLength(b, 0);
    end;
end;

function ComputeStreamWriteStringSize(buff: TPascalString): Integer;
{ * Returns the total byte size needed to write the string (4 + UTF‑8 length). }
var
  b: TBytes;
begin
  b := buff.Bytes;
  Result := 4 + Length(b);
  SetLength(b, 0);
end;

procedure StreamWriteMD5(const stream: TCore_Stream; const buff: TMD5);
begin
  stream.write(buff, 16);
end;

function StreamReadBool(const stream: TCore_Stream): Boolean;
begin
  stream.read(Result, 1);
end;

function StreamReadInt8(const stream: TCore_Stream): ShortInt;
begin
  stream.read(Result, 1);
end;

function StreamReadInt16(const stream: TCore_Stream): SmallInt;
begin
  stream.read(Result, 2);
end;

function StreamReadInt32(const stream: TCore_Stream): Integer;
begin
  stream.read(Result, 4);
end;

function StreamReadInt64(const stream: TCore_Stream): Int64;
begin
  stream.read(Result, 8);
end;

function StreamReadInt128(const stream: TCore_Stream): Int128;
begin
  stream.read(Result.b[0], 16);
end;

function StreamReadUInt8(const stream: TCore_Stream): Byte;
begin
  stream.read(Result, 1);
end;

function StreamReadUInt16(const stream: TCore_Stream): Word;
begin
  stream.read(Result, 2);
end;

function StreamReadUInt32(const stream: TCore_Stream): Cardinal;
begin
  stream.read(Result, 4);
end;

function StreamReadUInt64(const stream: TCore_Stream): UInt64;
begin
  stream.read(Result, 8);
end;

function StreamReadUInt128(const stream: TCore_Stream): UInt128;
begin
  stream.read(Result.b[0], 16);
end;

function StreamReadSingle(const stream: TCore_Stream): Single;
begin
  stream.read(Result, 4);
end;

function StreamReadDouble(const stream: TCore_Stream): Double;
begin
  stream.read(Result, 8);
end;

function StreamReadCurrency(const stream: TCore_Stream): Currency;
begin
  Result := StreamReadDouble(stream);
end;

function StreamReadString(const stream: TCore_Stream): TPascalString;
var
  L: Cardinal;
  b: TBytes;
begin
  try
    L := StreamReadUInt32(stream);
    if L > 0 then
      begin
        SetLength(b, L);
        stream.read(b[0], L);
        Result.Bytes := b;
        SetLength(b, 0);
      end;
  except
      Result := '';
  end;
end;

function StreamReadStringAsBuff(const stream: TCore_Stream): TBytes;
var
  L: Cardinal;
begin
  try
    L := StreamReadUInt32(stream);
    if L > 0 then
      begin
        SetLength(Result, L);
        stream.read(Result[0], L);
      end
    else
        SetLength(Result, 0);
  except
      SetLength(Result, 0);
  end;
end;

procedure StreamIgnoreReadString(const stream: TCore_Stream);
var
  L: Cardinal;
  b: TBytes;
begin
  try
    L := StreamReadUInt32(stream);
    if L > 0 then
      begin
        SetLength(b, L);
        stream.read(b[0], L);
        SetLength(b, 0);
      end;
  except
  end;
end;

function StreamReadMD5(const stream: TCore_Stream): TMD5;
begin
  stream.read(Result, 16);
end;

{ *************** Debug Helpers *************** }

procedure DoStatus(const v: TMS64);
{ * Prints the content of a TMS64 as comma‑separated decimal values. }
var
  p: PByte;
  i: Integer;
  n: SystemString;
begin
  p := v.Memory;
  for i := 0 to v.Size - 1 do
    begin
      if n <> '' then
          n := n + ',' + IntToStr(p^)
      else
          n := IntToStr(p^);
      inc(p);
    end;
  DoStatus(IntToHex(NativeInt(v), SizeOf(Pointer)) + ':' + n);
end;

procedure DoStatus(const v: TMem64);
{ * Prints the content of a TMem64 as comma‑separated decimal values. }
var
  p: PByte;
  i: Integer;
  n: SystemString;
begin
  p := v.Memory;
  for i := 0 to v.Size - 1 do
    begin
      if n <> '' then
          n := n + ',' + IntToStr(p^)
      else
          n := IntToStr(p^);
      inc(p);
    end;
  DoStatus(IntToHex(NativeInt(v), SizeOf(Pointer)) + ':' + n);
end;

initialization

{ * No special initialisation required. * }
end.
 
