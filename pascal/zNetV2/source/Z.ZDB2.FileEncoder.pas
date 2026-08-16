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
  *  ZDB2 File Encoder/Decoder – Archive and Packaging Layer
  *
  *  This unit provides a high‑performance file archiving and compression solution
  *  built on top of the ZDB2 core storage engine. It is designed for packaging
  *  large numbers of files (e.g., application installers, asset bundles, data
  *  distribution packages) into a single, compact, and optionally encrypted
  *  ZDB2 container, with parallel compression and decompression for maximum
  *  throughput.
  *
  *  Architecture Overview
  *  ---------------------
  *  – TZDB2_File_Encoder   : Takes input streams, files, or entire directories,
  *    compresses each file (or chunks thereof) using a selectable compression
  *    method (ZLib, ZLib_Max, etc.) and writes the compressed blocks into a
  *    TZDB2_Core_Space. Metadata (file name, MD5, timestamp, size, compressed
  *    size, and block handle list) is stored in a TZDB2_FI object, and the
  *    collection of all FI objects is serialized (via DFE) into a dedicated
  *    ZDB2 block, whose ID is stored in the custom header at offset $F0.
  *
  *  – TZDB2_File_Decoder   : Reads the metadata block from the ZDB2 container,
  *    reconstructs the list of TZDB2_FI objects, and provides methods to
  *    decompress any file to a stream or to disk, restoring original timestamps
  *    and verifying MD5 checksums.
  *
  *  Key Features
  *  ------------
  *  – Parallel compression/decompression using TIO_Thread pools.
  *  – Flexible input: stream, file, or recursive directory traversal.
  *  – Supports arbitrary chunk sizes for streaming large files without loading
  *    the entire file into memory.
  *  – Metadata stored in a compact DFE‑encoded block, allowing fast listing and
  *    random access without scanning the whole archive.
  *  – Built‑in MD5 verification for data integrity.
  *  – Progress callbacks for both encoding and decoding operations.
  *  – Optional encryption via IZDB2_Cipher.
  *
  *  Workflow
  *  --------
  *  1. Create a TZDB2_File_Encoder, optionally with a cipher and thread count.
  *  2. Encode files using EncodeFromStream, EncodeFromFile, or
  *     EncodeFromDirectory (recursive). Each call returns a TZDB2_FI object
  *     (added to the internal pool) and writes compressed data to the ZDB2 space.
  *  3. Call Flush to finalise the archive: this serialises all FI metadata into
  *     a single block, stores its ID in the custom header, and flushes the core.
  *  4. To decode, create a TZDB2_File_Decoder from the same stream/file.
  *  5. Access the Files property (TZDB2_FI_Pool) to enumerate, or use
  *     DecodeToStream / DecodeToDirectory to extract files.
  *  6. Progress and abort controls are available for both encoder and decoder.
  *
  *  This unit is the preferred packaging technology for large‑data installation
  *  programs, game asset bundles, and any scenario requiring high‑speed,
  *  compressed, and verifiable file archives.
*)
unit Z.ZDB2.FileEncoder;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses Z.Core,
{$IFDEF FPC}
  Z.FPC.GenericList,
{$ENDIF FPC}
  Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib, Z.Status, Z.MemoryStream, Z.ListEngine,
  Z.ZDB.ObjectData_LIB, Z.ZDB, Z.ZDB.ItemStream_LIB,
  Z.HashList.Templet, Z.DFE, Z.ZDB2, Z.IOThread, Z.Cipher;

type
  TZDB2_File_HndList = class(TGenericsList<Integer>); // List of ZDB2 block IDs that constitute a compressed file – used internally by TZDB2_FI.

  TZDB2_FI = class(TCore_Object_Intermediate) // File information entry: metadata for a single archived file.
  public
    FileName: U_String; // Original file name – set by encoder from source file name.
    FileMD5: TMD5; // MD5 checksum of the uncompressed file – computed from source stream.
    FimeTime: TDateTime; // Last modification time of the original file – set from file timestamp, or current time for streams.
    Size: Int64; // Uncompressed size in bytes – set from source stream.
    Compressed: Int64; // Total compressed size (sum of all block payloads) – accumulated during encoding.
    OwnerPath: U_String; // Logical path within the archive (e.g., directory structure) – set by user or derived from source path.
    HandleArray: TZDB2_File_HndList; // List of block IDs that store the compressed data – populated by WriteStream during encoding.

    constructor Create();
    destructor Destroy; override;
    procedure SaveToStream(stream: TMS64); // Serialise this FI object to a TMS64 using DFE.
    procedure LoadFromStream(stream: TMS64); // Deserialise from a TMS64.
  end;

  TZDB2_FI_Pool_Decl = class(TBigList<TZDB2_FI>); // BigList of FI objects (managed pool).
  TZDB2_FI_Hash_Decl = class(TPascalString_Big_Hash_Pair_Pool<TZDB2_FI>); // Hash pool mapping string keys to FI (for fast lookup).

  TZDB2_FI_Hash = class(TZDB2_FI_Hash_Decl) // Specialised hash pool with automatic memory management.
  public
    constructor Create;
    function Compare_Value(const Value_1, Value_2: TZDB2_FI): Boolean; override; // Compares two FI references for equality.
    procedure DoFree(var Key: TPascalString; var Value: TZDB2_FI); override; // Frees the FI when removed from hash.
  end;

  TZDB2_FI_Pool = class(TZDB2_FI_Pool_Decl) // Pool of FI objects, supports search and hash building.
  public
    AutoFree: Boolean; // If True, automatically frees FI objects when removed – set by user (default True).
    constructor Create;
    procedure DoFree(var Data: TZDB2_FI); override; // Frees the FI if AutoFree is True.
    function CompareData(const Data_1, Data_2: TZDB2_FI): Boolean; override; // Compares two FI references.
    function FindFile(FileName: U_String): TZDB2_FI; // Finds an FI by exact file name (case‑sensitive? uses Same).
    function SearchFile(FileName, OwnerPath: U_String): TZDB2_FI_Pool; // Returns a new pool of FI matching wildcard pattern for both file name and path.
    function Build_Hash_Pool(OwnerPath_: Boolean): TZDB2_FI_Hash; // Builds a hash pool keyed by full path (if OwnerPath_=True) or file name only.
  end;

  TZDB2_FE_IO = class(TIO_Thread_Data) // IO worker data for encoding: compresses a data chunk.
  public
    Source: TMS64; // Uncompressed chunk – set by encoder thread.
    Dest: TMS64; // Compressed chunk – filled by Process.
    CM: TSelectCompressionMethod; // Compression method to use – set by encoder.
    constructor Create; override;
    destructor Destroy; override;
    procedure Process; override; // Compresses Source into Dest.
  end;

  TOn_ZDB2_File_OnProgress = procedure(State_: SystemString; Total, Current1, Current2: Int64) of object; // Progress callback: State string, total bytes, current step1, current step2.

  TZDB2_File_Encoder = class(TCore_Object_Intermediate) // Main class for creating a compressed archive.
  private
    FCore: TZDB2_Core_Space; // Underlying ZDB2 core space – created by constructor.
    FPlace: TZDB2_Space_Planner; // Planner for allocating blocks – created by constructor.
    FIO_Thread: TIO_Thread_Base; // Thread pool for parallel compression – created by constructor.
    FEncoderFiles: TZDB2_FI_Pool; // Pool of all FI objects built during encoding – created by constructor.
    FMaxQueue: Integer; // Maximum number of pending IO jobs – set by user (default = ThNum_*5).
    FProgressInfo: SystemString; // Current progress context string – set by EncodeFromFile/EncodeFromDirectory.
    FOnProgress: TOn_ZDB2_File_OnProgress; // User progress callback – assigned by user.
    FAborted: Boolean; // Abort flag – can be set by user to cancel encoding.
    FFlushed: Boolean; // True after Flush has been called – set by Flush.
  public
    constructor Create(Cipher_: IZDB2_Cipher; ZDB2_Stream: TCore_Stream; ThNum_: Integer); overload; // Creates encoder with cipher, stream, and thread count.
    constructor CreateFile(Cipher_: IZDB2_Cipher; ZDB2_FileName: U_String; ThNum_: Integer); overload; // Creates encoder with cipher, file name, and thread count.
    constructor Create(ZDB2_Stream: TCore_Stream; ThNum_: Integer); overload; // Creates encoder without cipher.
    constructor CreateFile(ZDB2_FileName: U_String; ThNum_: Integer); overload; // Creates encoder without cipher, using a file.
    destructor Destroy; override;
    function EncodeFromStream(stream: TCore_Stream; chunkSize_: Int64; CM: TSelectCompressionMethod; BlockSize_: Word): TZDB2_FI; // Encodes a stream into the archive; returns FI metadata.
    function EncodeFromFile(FileName, OwnerPath: U_String; chunkSize_: Int64; CM: TSelectCompressionMethod; BlockSize_: Word): TZDB2_FI; // Encodes a file; OwnerPath is logical directory.
    procedure EncodeFromDirectory(Directory_: U_String; IncludeSub: Boolean; OwnerPath_: U_String; chunkSize_: Int64; CM: TSelectCompressionMethod; BlockSize_: Word); // Recursively encodes all files in a directory.
    function Flush: Int64; // Finalises archive: writes metadata block, returns total uncompressed size.
    property MaxQueue: Integer read FMaxQueue write FMaxQueue; // Max pending IO jobs.
    property OnProgress: TOn_ZDB2_File_OnProgress read FOnProgress write FOnProgress;
    property Aborted: Boolean read FAborted write FAborted;
    property Core: TZDB2_Core_Space read FCore;

    class procedure Test;
  end;

  TZDB2_FD_IO = class(TIO_Thread_Data) // IO worker data for decoding: decompresses a chunk.
  public
    Source: TMS64; // Compressed chunk – read from ZDB2.
    Dest: TMS64; // Decompressed chunk – filled by Process.
    constructor Create; override;
    destructor Destroy; override;
    procedure Process; override; // Decompresses Source into Dest.
  end;

  TZDB2_File_Decoder = class(TCore_Object_Intermediate) // Main class for extracting files from an archive.
  private
    FCore: TZDB2_Core_Space; // Underlying ZDB2 core space – opened from archive.
    FIO_Thread: TIO_Thread_Base; // Thread pool for parallel decompression – created by constructor.
    FDecoderFiles: TZDB2_FI_Pool; // Pool of FI objects read from metadata – populated by constructor.
    FDecoderFile_Hash: TZDB2_FI_Hash; // Hash pool keyed by file name – built by constructor.
    FDecoderPath_Hash: TZDB2_FI_Hash; // Hash pool keyed by full path (OwnerPath+FileName) – built by constructor.
    FMaxQueue: Integer; // Max pending IO jobs – set by user (default = ThNum_*10).
    FFileLog: TPascalStringList; // List of extracted file paths (for logging) – populated by DecodeToDirectory.
    FProgressInfo: SystemString; // Current progress context – set by DecodeToDirectory.
    FOnProgress: TOn_ZDB2_File_OnProgress; // User progress callback – assigned by user.
    FAborted: Boolean; // Abort flag – can be set by user to cancel decoding.
  public
    class function Check(Cipher_: IZDB2_Cipher; ZDB2_Stream: TCore_Stream): Boolean; overload; // Checks if a stream is a valid archive.
    class function CheckFile(Cipher_: IZDB2_Cipher; ZDB2_FileName: U_String): Boolean; overload; // Checks if a file is a valid archive.
    class function Check(ZDB2_Stream: TCore_Stream): Boolean; overload; // Without cipher.
    class function CheckFile(ZDB2_FileName: U_String): Boolean; overload; // Without cipher.
    constructor Create(Cipher_: IZDB2_Cipher; ZDB2_Stream: TCore_Stream; ThNum_: Integer); overload; // Creates decoder from stream, with optional cipher.
    constructor CreateFile(Cipher_: IZDB2_Cipher; ZDB2_FileName: U_String; ThNum_: Integer); overload; // Creates decoder from file.
    constructor Create(ZDB2_Stream: TCore_Stream; ThNum_: Integer); overload; // Without cipher.
    constructor CreateFile(ZDB2_FileName: U_String; ThNum_: Integer); overload; // Without cipher.
    destructor Destroy; override;
    function CheckFileInfo(FileInfo_: TZDB2_FI): Boolean; // Verifies that all block IDs for a file exist and are valid.
    function DecodeToStream(source_: TZDB2_FI; Dest_: TCore_Stream): Boolean; // Decompresses a file into a stream.
    function DecodeToDirectory(source_: TZDB2_FI; DestDirectory_: U_String; var dest_file: U_String): Boolean; overload; // Decompresses to a specific file path.
    function DecodeToDirectory(source_: TZDB2_FI; DestDirectory_: U_String): Boolean; overload; // Decompresses to directory, using stored file name.
    property Files: TZDB2_FI_Pool read FDecoderFiles; // All file entries in the archive.
    property FileHash: TZDB2_FI_Hash read FDecoderFile_Hash; // Hash by file name.
    property PathHash: TZDB2_FI_Hash read FDecoderPath_Hash; // Hash by full path.
    property MaxQueue: Integer read FMaxQueue write FMaxQueue;
    property FileLog: TPascalStringList read FFileLog;
    property OnProgress: TOn_ZDB2_File_OnProgress read FOnProgress write FOnProgress;
    property Aborted: Boolean read FAborted write FAborted;
    property Core: TZDB2_Core_Space read FCore;

    class procedure Test;
  end;

implementation

constructor TZDB2_FI.Create;
begin
  inherited Create;
  FileName := '';
  FileMD5 := NullMD5;
  FimeTime := umlNow();
  OwnerPath := '';
  Size := 0;
  Compressed := 0;
  HandleArray := TZDB2_File_HndList.Create;
end;

destructor TZDB2_FI.Destroy;
begin
  FileName := '';
  OwnerPath := '';
  DisposeObject(HandleArray);
  inherited Destroy;
end;

procedure TZDB2_FI.SaveToStream(stream: TMS64);
var
  d: TDFE;
  i: Integer;
begin
  d := TDFE.Create;
  d.WriteString(FileName);
  d.WriteMD5(FileMD5);
  d.WriteDouble(FimeTime);
  d.WriteInt64(Size);
  d.WriteInt64(Compressed);
  d.WriteString(OwnerPath);
  with d.WriteArrayInteger do
    for i := 0 to HandleArray.Count - 1 do
        Add(HandleArray[i]);
  d.EncodeTo(stream, True, False);
  DisposeObject(d);
end;

procedure TZDB2_FI.LoadFromStream(stream: TMS64);
var
  d: TDFE;
  i: Integer;
begin
  d := TDFE.Create;
  d.DecodeFrom(stream, True);
  FileName := d.Reader.ReadString;
  FileMD5 := d.Reader.ReadMD5;
  FimeTime := d.Reader.ReadDouble;
  Size := d.Reader.ReadInt64;
  Compressed := d.Reader.ReadInt64;
  OwnerPath := d.Reader.ReadString;
  with d.Reader.ReadArrayInteger do
    for i := 0 to Count - 1 do
        HandleArray.Add(Buffer[i]);
  DisposeObject(d);
end;

constructor TZDB2_FI_Hash.Create;
begin
  inherited Create($FFFF, nil);
end;

function TZDB2_FI_Hash.Compare_Value(const Value_1, Value_2: TZDB2_FI): Boolean;
begin
  Result := Value_1 = Value_2;
end;

procedure TZDB2_FI_Hash.DoFree(var Key: TPascalString; var Value: TZDB2_FI);
begin
  Value := nil;
  inherited DoFree(Key, Value);
end;

constructor TZDB2_FI_Pool.Create;
begin
  inherited Create;
  AutoFree := True;
end;

procedure TZDB2_FI_Pool.DoFree(var Data: TZDB2_FI);
begin
  if AutoFree then
      DisposeObjectAndNil(Data)
  else
      Data := nil;
end;

function TZDB2_FI_Pool.CompareData(const Data_1, Data_2: TZDB2_FI): Boolean;
begin
  Result := Data_1 = Data_2;
end;

function TZDB2_FI_Pool.FindFile(FileName: U_String): TZDB2_FI;
var
  r_: TZDB2_FI_Pool_Decl.TInvert_Repeat___;
begin
  Result := nil;
  if num <= 0 then
      exit;
  r_ := Invert_Repeat_;
  repeat
    if FileName.Same(r_.Queue^.Data.FileName) then
        exit(r_.Queue^.Data);
  until not r_.Prev;
end;

function TZDB2_FI_Pool.SearchFile(FileName, OwnerPath: U_String): TZDB2_FI_Pool;
var
  r_: TZDB2_FI_Pool_Decl.TInvert_Repeat___;
begin
  Result := TZDB2_FI_Pool.Create;
  Result.AutoFree := False;
  if num <= 0 then
      exit;
  r_ := Invert_Repeat_;
  repeat
    if umlSearchMatch(FileName, r_.Queue^.Data.FileName) and umlSearchMatch(OwnerPath, r_.Queue^.Data.OwnerPath) then
        Result.Add(r_.Queue^.Data);
  until not r_.Prev;
end;

function TZDB2_FI_Pool.Build_Hash_Pool(OwnerPath_: Boolean): TZDB2_FI_Hash;
var
  r_: TZDB2_FI_Pool_Decl.TInvert_Repeat___;
begin
  Result := TZDB2_FI_Hash.Create;
  if num <= 0 then
      exit;
  r_ := Invert_Repeat_;
  repeat
    if OwnerPath_ then
        Result.Add(umlCombineUnixFileName(r_.Queue^.Data.OwnerPath, r_.Queue^.Data.FileName), r_.Queue^.Data, True)
    else
        Result.Add(r_.Queue^.Data.FileName, r_.Queue^.Data, True);
  until not r_.Prev;
end;

constructor TZDB2_FE_IO.Create;
begin
  inherited Create;
  Source := TMS64.Create;
  Dest := TMS64.Create;
  CM := TSelectCompressionMethod.scmZLIB;
end;

destructor TZDB2_FE_IO.Destroy;
begin
  DisposeObject(Source);
  DisposeObject(Dest);
  inherited Destroy;
end;

procedure TZDB2_FE_IO.Process;
begin
  Source.Position := 0;
  Dest.Clear;
  if Source.Size < 128 then
      CM := TSelectCompressionMethod.scmNone;
  SelectCompressStream(CM, Source, Dest);
end;

constructor TZDB2_File_Encoder.Create(Cipher_: IZDB2_Cipher; ZDB2_Stream: TCore_Stream; ThNum_: Integer);
var
  P: PIOHnd;
begin
  inherited Create;
  new(P);
  InitIOHnd(P^);
  if not umlFileCreateAsStream(ZDB2_Stream, P^) then
      RaiseInfo('create stream error.');
  FCore := TZDB2_Core_Space.Create(P);
  FCore.Cipher := Cipher_;
  FCore.AutoCloseIOHnd := True;
  FCore.AutoFreeIOHnd := True;
  FPlace := TZDB2_Space_Planner.Create(FCore);

  if ThNum_ > 0 then
      FIO_Thread := TIO_Thread.Create(ThNum_)
  else
      FIO_Thread := TIO_Direct.Create;
  FEncoderFiles := TZDB2_FI_Pool.Create;
  FMaxQueue := umlMax(1, ThNum_) * 5;
  FProgressInfo := '';
  FOnProgress := nil;
  FAborted := False;
  FFlushed := False;
end;

constructor TZDB2_File_Encoder.CreateFile(Cipher_: IZDB2_Cipher; ZDB2_FileName: U_String; ThNum_: Integer);
var
  fs: TCore_FileStream;
begin
  fs := TCore_FileStream.Create(ZDB2_FileName, fmCreate);
  Create(Cipher_, fs, ThNum_);
  FCore.Space_IOHnd^.AutoFree := True;
end;

constructor TZDB2_File_Encoder.Create(ZDB2_Stream: TCore_Stream; ThNum_: Integer);
begin
  Create(nil, ZDB2_Stream, ThNum_);
end;

constructor TZDB2_File_Encoder.CreateFile(ZDB2_FileName: U_String; ThNum_: Integer);
begin
  CreateFile(nil, ZDB2_FileName, ThNum_);
end;

destructor TZDB2_File_Encoder.Destroy;
begin
  if not FFlushed then
      Flush;
  DisposeObject(FIO_Thread);
  DisposeObject(FEncoderFiles);
  DisposeObject(FPlace);
  DisposeObject(FCore);
  inherited Destroy;
end;

function TZDB2_File_Encoder.EncodeFromStream(stream: TCore_Stream; chunkSize_: Int64; CM: TSelectCompressionMethod; BlockSize_: Word): TZDB2_FI;
var
  Activted: TAtomBool;

{$IFDEF FPC}
  procedure FPC_ThRun_;
  var
    Total_: Int64;
    thIOData_: TZDB2_FE_IO;
  begin
    Total_ := stream.Size;
    stream.Position := 0;

    while (Total_ > 0) and (not FAborted) do
      begin
        thIOData_ := TZDB2_FE_IO.Create;
        thIOData_.CM := CM;
        if Total_ > chunkSize_ then
          begin
            thIOData_.Source.Size := chunkSize_;
            dec(Total_, chunkSize_);
          end
        else
          begin
            thIOData_.Source.Size := Total_;
            Total_ := 0;
          end;
        if stream.Read(thIOData_.Source.Memory^, thIOData_.Source.Size) <> thIOData_.Source.Size then
            break;
        FIO_Thread.Enqueue(thIOData_);
        while FIO_Thread.Count > FMaxQueue do
            TCompute.Sleep(1);
      end;

    FIO_Thread.Wait();
    Activted.V := False;
  end;
{$ENDIF FPC}


var
  FileInfo: TZDB2_FI;
  ioData: TZDB2_FE_IO;
  id: Integer;
  CompleteSize_: Int64;
begin
  if FFlushed then
      RaiseInfo('only work before flash');

  FileInfo := TZDB2_FI.Create;
  FileInfo.Size := stream.Size;
  FileInfo.Compressed := 0;
  FileInfo.FileMD5 := umlStreamMD5(stream);

  if FileInfo.Size = 0 then
    begin
      FEncoderFiles.Add(FileInfo);
      Result := FileInfo;
      exit;
    end;

  Activted := TAtomBool.Create(True);
  CompleteSize_ := 0;

{$IFDEF FPC}
  TCompute.RunP_NP(FPC_ThRun_);
{$ELSE FPC}
  TCompute.RunP_NP(procedure
    var
      Total_: Int64;
      thIOData_: TZDB2_FE_IO;
    begin
      Total_ := stream.Size;
      stream.Position := 0;

      while (Total_ > 0) and (not FAborted) do
        begin
          thIOData_ := TZDB2_FE_IO.Create;
          thIOData_.CM := CM;
          if Total_ > chunkSize_ then
            begin
              thIOData_.Source.Size := chunkSize_;
              dec(Total_, chunkSize_);
            end
          else
            begin
              thIOData_.Source.Size := Total_;
              Total_ := 0;
            end;
          if stream.Read(thIOData_.Source.Memory^, thIOData_.Source.Size) <> thIOData_.Source.Size then
              break;
          FIO_Thread.Enqueue(thIOData_);
          while FIO_Thread.Count > FMaxQueue do
              TCompute.Sleep(1);
        end;

      FIO_Thread.Wait();
      Activted.V := False;
    end);
{$ENDIF FPC}
  CompleteSize_ := 0;
  while Activted.V do
    begin
      ioData := TZDB2_FE_IO(FIO_Thread.Dequeue);
      if ioData <> nil then
        begin
          inc(CompleteSize_, ioData.Source.Size);
          inc(FileInfo.Compressed, ioData.Dest.Size);
          if FPlace.WriteStream(ioData.Dest, BlockSize_, id) then
              FileInfo.HandleArray.Add(id)
          else
              DoStatus('TZDB2_File_Encoder error.');
          DisposeObject(ioData);
          if Assigned(FOnProgress) then
              FOnProgress(FProgressInfo + PFormat('(%s/%s compress:%s)',
              [umlSizeToStr(FileInfo.Size).Text, umlSizeToStr(CompleteSize_).Text, umlSizeToStr(FileInfo.Compressed).Text]),
              FileInfo.Size, CompleteSize_, FileInfo.Compressed);
        end
      else
          TCompute.Sleep(1);
    end;

  DisposeObject(Activted);
  FileInfo.FileName := umlMD5ToStr(FileInfo.FileMD5);
  FileInfo.FimeTime := umlNow();
  FileInfo.OwnerPath := '/';
  FEncoderFiles.Add(FileInfo);
  Result := FileInfo;
end;

function TZDB2_File_Encoder.EncodeFromFile(FileName, OwnerPath: U_String; chunkSize_: Int64; CM: TSelectCompressionMethod; BlockSize_: Word): TZDB2_FI;
var
  fs: TCore_FileStream;
  prefix: SystemString;
begin
  Result := nil;
  if not umlFileExists(FileName) then
      exit;
  FProgressInfo := umlCombineFileName(OwnerPath, umlGetFileName(FileName));
  fs := TCore_FileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  Result := EncodeFromStream(fs, chunkSize_, CM, BlockSize_);
  DisposeObject(fs);
  Result.FileName := umlGetFileName(FileName);
  Result.OwnerPath := OwnerPath;
  Result.FimeTime := umlGetFileTime(FileName);

  if (FCore.Space_IOHnd^.Handle is TCore_FileStream) then
      prefix := umlGetFileName(TCore_FileStream(FCore.Space_IOHnd^.Handle).FileName)
  else if (FCore.Space_IOHnd^.Handle is TReliableFileStream) then
      prefix := umlGetFileName(TReliableFileStream(FCore.Space_IOHnd^.Handle).FileName)
  else
      prefix := 'encode';

  DoStatus('%s %s %s->%s ratio:%d%%',
    [
    prefix,
    FProgressInfo,
    umlSizeToStr(Result.Size).Text,
    umlSizeToStr(Result.Compressed).Text,
    100 - umlPercentageToInt64(Result.Size, Result.Compressed)]);
end;

procedure TZDB2_File_Encoder.EncodeFromDirectory(Directory_: U_String; IncludeSub: Boolean; OwnerPath_: U_String; chunkSize_: Int64; CM: TSelectCompressionMethod; BlockSize_: Word);
var
  fAry: U_StringArray;
  n: SystemString;
begin
  fAry := umlGet_File_Full_Array(Directory_);
  for n in fAry do
    if not FAborted then
        EncodeFromFile(n, OwnerPath_, chunkSize_, CM, BlockSize_)
    else
        exit;

  if IncludeSub then
    begin
      fAry := umlGet_Path_Full_Array(Directory_);
      for n in fAry do
        if not FAborted then
            EncodeFromDirectory(n, IncludeSub, umlCombineWinPath(OwnerPath_, umlGetLastStr(n, '\/')), chunkSize_, CM, BlockSize_)
        else
            exit;
    end;
end;

function TZDB2_File_Encoder.Flush: Int64;
var
  d: TDFE;
  m64: TMS64;
  FileInfo_ID: Integer;
begin
  if FFlushed then
      RaiseInfo('repeat flash');

  Result := 0;
  d := TDFE.Create;
  if FEncoderFiles.num > 0 then
    with FEncoderFiles.repeat_ do
      repeat
        m64 := TMS64.Create;
        Queue^.Data.SaveToStream(m64);
        inc(Result, Queue^.Data.Size);
        d.WriteStream(m64);
        DisposeObject(m64);
      until not Next;
  m64 := TMS64.Create;
  d.EncodeAsZLib(m64, False);
  if not FPlace.WriteStream(m64, 1024, FileInfo_ID) then
      RaiseInfo('flush error.');
  DisposeObject(m64);
  DisposeObject(d);
  FPlace.Flush;
  PInteger(@FCore.UserCustomHeader^[$F0])^ := FileInfo_ID;
  FCore.Flush;
  FEncoderFiles.Clear;
  FFlushed := True;
end;

class procedure TZDB2_File_Encoder.Test;
var
  zdb_stream: TMS64;
  en: TZDB2_File_Encoder;
  tmp: TMS64;
  i: Integer;
begin
  zdb_stream := TMS64.CustomCreate(1024 * 1024 * 2);
  en := TZDB2_File_Encoder.Create(zdb_stream, 8);

  for i := 0 to 10 do
    begin
      tmp := TMS64.Create;
      tmp.Size := umlRandomRange(16 * 1024 * 1024, 4 * 1024 * 1024);
      MT19937Rand32(MaxInt, tmp.Memory, tmp.Size div 4);
      en.EncodeFromStream(tmp, 512 * 1024, TSelectCompressionMethod.scmZLIB, 8192);
      DisposeObject(tmp);
    end;
  en.Flush;

  DisposeObject(en);
  DisposeObject(zdb_stream);
end;

constructor TZDB2_FD_IO.Create;
begin
  inherited Create;
  Source := TMS64.Create;
  Dest := TMS64.Create;
end;

destructor TZDB2_FD_IO.Destroy;
begin
  DisposeObject(Source);
  DisposeObject(Dest);
  inherited Destroy;
end;

procedure TZDB2_FD_IO.Process;
begin
  SelectDecompressStream(Source, Dest);
end;

class function TZDB2_File_Decoder.Check(Cipher_: IZDB2_Cipher; ZDB2_Stream: TCore_Stream): Boolean;
var
  ioHnd: TIOHnd;
  tmp: TZDB2_Core_Space;
  id: Integer;
  mem: TZDB2_Mem;
  d: TDFE;
begin
  Result := False;
  InitIOHnd(ioHnd);
  if umlFileOpenAsStream('', ZDB2_Stream, ioHnd, True) then
    begin
      tmp := TZDB2_Core_Space.Create(@ioHnd);
      tmp.Cipher := Cipher_;
      if tmp.Open then
        begin
          id := PInteger(@tmp.UserCustomHeader^[$F0])^;
          if tmp.Check(id) then
            begin
              mem := TZDB2_Mem.Create.Create;
              if tmp.ReadData(mem, id) then
                begin
                  d := TDFE.Create;
                  try
                    d.LoadFromStream(mem.Stream64);
                    Result := d.Count >= 0;
                  except
                      Result := False;
                  end;
                  DisposeObject(d);
                end;
              DisposeObject(mem);
            end;
        end;
      DisposeObject(tmp);
    end;
end;

class function TZDB2_File_Decoder.CheckFile(Cipher_: IZDB2_Cipher; ZDB2_FileName: U_String): Boolean;
var
  fs: TCore_FileStream;
begin
  fs := TCore_FileStream.Create(ZDB2_FileName, fmOpenRead or fmShareDenyNone);
  try
      Result := Check(Cipher_, fs);
  finally
      DisposeObject(fs);
  end;
end;

class function TZDB2_File_Decoder.Check(ZDB2_Stream: TCore_Stream): Boolean;
begin
  Result := TZDB2_File_Decoder.Check(nil, ZDB2_Stream);
end;

class function TZDB2_File_Decoder.CheckFile(ZDB2_FileName: U_String): Boolean;
begin
  Result := TZDB2_File_Decoder.CheckFile(nil, ZDB2_FileName);
end;

constructor TZDB2_File_Decoder.Create(Cipher_: IZDB2_Cipher; ZDB2_Stream: TCore_Stream; ThNum_: Integer);
var
  P: PIOHnd;
  mem: TZDB2_Mem;
  d: TDFE;
  i: Integer;
  m64: TMS64;
  fi: TZDB2_FI;
begin
  inherited Create;
  new(P);
  InitIOHnd(P^);
  if not umlFileOpenAsStream('', ZDB2_Stream, P^, True) then
      RaiseInfo('create stream error.');
  FCore := TZDB2_Core_Space.Create(P);
  FCore.Cipher := Cipher_;
  FCore.AutoCloseIOHnd := True;
  FCore.AutoFreeIOHnd := True;
  FCore.Open;

  if ThNum_ > 0 then
      FIO_Thread := TIO_Thread.Create(ThNum_)
  else
      FIO_Thread := TIO_Direct.Create;

  FMaxQueue := umlMax(1, ThNum_) * 10;
  FDecoderFiles := TZDB2_FI_Pool.Create;

  mem := TZDB2_Mem.Create.Create;
  if FCore.ReadData(mem, PInteger(@FCore.UserCustomHeader^[$F0])^) then
    begin
      d := TDFE.Create;
      d.LoadFromStream(mem.Stream64);
      while d.Reader.NotEnd do
        begin
          m64 := TMS64.Create;
          d.Reader.ReadStream(m64);
          m64.Position := 0;
          fi := TZDB2_FI.Create;
          fi.LoadFromStream(m64);
          FDecoderFiles.Add(fi);
          DisposeObject(m64);
        end;
      DisposeObject(d);
    end;
  DisposeObject(mem);

  FDecoderFile_Hash := FDecoderFiles.Build_Hash_Pool(False);
  FDecoderPath_Hash := FDecoderFiles.Build_Hash_Pool(True);

  FFileLog := TPascalStringList.Create;
  FProgressInfo := '';
  FOnProgress := nil;
  FAborted := False;
end;

constructor TZDB2_File_Decoder.CreateFile(Cipher_: IZDB2_Cipher; ZDB2_FileName: U_String; ThNum_: Integer);
var
  fs: TCore_FileStream;
begin
  fs := TCore_FileStream.Create(ZDB2_FileName, fmOpenRead or fmShareDenyNone);
  Create(Cipher_, fs, ThNum_);
  FCore.Space_IOHnd^.AutoFree := True;
end;

constructor TZDB2_File_Decoder.Create(ZDB2_Stream: TCore_Stream; ThNum_: Integer);
begin
  Create(nil, ZDB2_Stream, ThNum_);
end;

constructor TZDB2_File_Decoder.CreateFile(ZDB2_FileName: U_String; ThNum_: Integer);
begin
  CreateFile(nil, ZDB2_FileName, ThNum_);
end;

destructor TZDB2_File_Decoder.Destroy;
begin
  DisposeObject(FIO_Thread);
  DisposeObject(FDecoderFile_Hash);
  DisposeObject(FDecoderPath_Hash);
  DisposeObject(FDecoderFiles);
  DisposeObject(FFileLog);
  DisposeObject(FCore);
  inherited Destroy;
end;

function TZDB2_File_Decoder.CheckFileInfo(FileInfo_: TZDB2_FI): Boolean;
var
  i: Integer;
begin
  Result := True;
  for i := 0 to FileInfo_.HandleArray.Count - 1 do
      Result := Result and FCore.Check(FileInfo_.HandleArray[i]);
end;

function TZDB2_File_Decoder.DecodeToStream(source_: TZDB2_FI; Dest_: TCore_Stream): Boolean;
var
  Activted: TAtomBool;

{$IFDEF FPC}
  procedure FPC_ThRun_;
  var
    i: Integer;
    thIOData_: TZDB2_FD_IO;
  begin
    for i := 0 to source_.HandleArray.Count - 1 do
      begin
        thIOData_ := TZDB2_FD_IO.Create;
        FCore.ReadStream(thIOData_.Source, source_.HandleArray[i]);
        thIOData_.Source.Position := 0;
        FIO_Thread.Enqueue(thIOData_);
        while FIO_Thread.Count > FMaxQueue do
            TCompute.Sleep(1);
        if FAborted then
            break;
      end;

    FIO_Thread.Wait();
    Activted.V := False;
  end;
{$ENDIF FPC}


var
  compSiz_: Int64;
  ioData: TZDB2_FD_IO;
begin
  Result := False;
  if source_ = nil then
      exit;
  Activted := TAtomBool.Create(True);

{$IFDEF FPC}
  TCompute.RunP_NP(FPC_ThRun_);
{$ELSE FPC}
  TCompute.RunP_NP(procedure
    var
      i: Integer;
      thIOData_: TZDB2_FD_IO;
    begin
      for i := 0 to source_.HandleArray.Count - 1 do
        begin
          thIOData_ := TZDB2_FD_IO.Create;
          FCore.ReadStream(thIOData_.Source, source_.HandleArray[i]);
          thIOData_.Source.Position := 0;
          FIO_Thread.Enqueue(thIOData_);
          while FIO_Thread.Count > FMaxQueue do
              TCompute.Sleep(1);
          if FAborted then
              break;
        end;

      FIO_Thread.Wait();
      Activted.V := False;
    end);
{$ENDIF FPC}
  compSiz_ := 0;
  while Activted.V do
    begin
      ioData := TZDB2_FD_IO(FIO_Thread.Dequeue);
      if ioData <> nil then
        begin
          inc(compSiz_, ioData.Source.Size);
          Dest_.Write(ioData.Dest.Memory^, ioData.Dest.Size);
          DisposeObject(ioData);

          if Assigned(FOnProgress) then
              FOnProgress(FProgressInfo + PFormat(' %s -> %s',
              [umlSizeToStr(Dest_.Size).Text, umlSizeToStr(source_.Size).Text]), source_.Size, Dest_.Size, compSiz_);
        end
      else
          TCompute.Sleep(1);
    end;

  DisposeObject(Activted);
  Result := True;
end;

function TZDB2_File_Decoder.DecodeToDirectory(source_: TZDB2_FI; DestDirectory_: U_String): Boolean;
var
  dest_file: U_String;
begin
  Result := DecodeToDirectory(source_, DestDirectory_, dest_file);
end;

function TZDB2_File_Decoder.DecodeToDirectory(source_: TZDB2_FI; DestDirectory_: U_String; var dest_file: U_String): Boolean;
var
  path_, fn: U_String;
  fs: TCore_FileStream;
begin
  Result := False;
  dest_file := '';
  if source_ = nil then
      exit;
  if source_.FileName.L = 0 then
      exit;
  if not CheckFileInfo(source_) then
    begin
      DoStatus('ZDB2 data error: %s', [source_.FileName.Text]);
      exit;
    end;
  path_ := umlCombinePath(DestDirectory_, source_.OwnerPath);
  if not umlDirectoryExists(path_) then
    begin
      umlCreateDirectory(path_);
      if not umlDirectoryExists(path_) then
        begin
          DoStatus('illegal directory %s', [path_.Text]);
          exit;
        end;
    end;
  fn := umlCombineFileName(path_, source_.FileName);

  try
    fs := TCore_FileStream.Create(fn, fmCreate);
    try
      FProgressInfo := umlGetFileName(fn);
      Result := DecodeToStream(source_, fs);
    finally
      DisposeObject(fs);
      umlSetFileTime(fn, source_.FimeTime);
      DoStatus('decode %s %s -> %s ratio:%d%%',
        [FProgressInfo, umlSizeToStr(source_.Compressed).Text, umlSizeToStr(source_.Size).Text, 100 - umlPercentageToInt64(source_.Size, source_.Compressed)]);
      FFileLog.Add(fn);
      dest_file := fn;
    end;
  except
    DoStatus('illegal file %s', [fn.Text]);
    exit;
  end;
end;

class procedure TZDB2_File_Decoder.Test;
var
  Cipher_: TZDB2_Cipher;
  zdb_stream: TMS64;
  en: TZDB2_File_Encoder;
  de: TZDB2_File_Decoder;
  tmp: TMS64;
  i: Integer;
  fi: TZDB2_FI;
begin
  Cipher_ := TZDB2_Cipher.Create(TCipherSecurity.csRC6, 'hello world.', 1, False, True);
  zdb_stream := TMS64.CustomCreate(1024 * 1024 * 8);

  en := TZDB2_File_Encoder.Create(Cipher_, zdb_stream, 4);
  for i := 0 to 10 do
    begin
      tmp := TMS64.Create;
      tmp.Size := umlRandomRange(16 * 1024, 64 * 1024);
      MT19937Rand32(MaxInt, tmp.Memory, tmp.Size div 4);
      fi := en.EncodeFromStream(tmp, 8192, TSelectCompressionMethod.scmZLIB_Max, 1024);
      fi.FileName := umlIntToStr(i);
      fi.OwnerPath := umlIntToStr(i * i);
      DisposeObject(tmp);
    end;
  en.Flush;
  DisposeObject(en);

  if TZDB2_File_Decoder.Check(Cipher_, zdb_stream) then
      DoStatus('TZDB2_File_Decoder check ok.')
  else
      DoStatus('TZDB2_File_Decoder check error.');

  de := TZDB2_File_Decoder.Create(Cipher_, zdb_stream, 4);
  if de.Files.num > 0 then
    with de.Files.repeat_ do
      repeat
        tmp := TMS64.Create;
        fi := Queue^.Data;
        if de.DecodeToStream(fi, tmp) then
          begin
            if umlCompareMD5(umlStreamMD5(tmp), fi.FileMD5) then
                DoStatus('TZDB2_File_Decoder md5 ok.')
            else
                DoStatus('TZDB2_File_Decoder md5 error.');
          end
        else
            DoStatus('TZDB2_File_Decoder error.');
        DisposeObject(tmp);
      until not Next;
  DisposeObject(de);

  DisposeObject(zdb_stream);
  DisposeObject(Cipher_);
end;

initialization

finalization

end.
 
