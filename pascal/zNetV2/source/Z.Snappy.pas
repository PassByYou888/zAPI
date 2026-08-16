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
{ * Z.Snappy
  * =========
  * Pascal binding for the Snappy compression library.
  *
  * Snappy is a fast compression/decompression library developed by Google.
  * It prioritises speed over compression ratio, achieving compression
  * speeds above 250 MB/s and decompression above 500 MB/s on modern hardware.
  * Typical compression ratios are 1.5‑2× for text, 2‑4× for HTML,
  * and near 1.0× for already‑compressed data (JPEG, PNG, etc.).
  *
  * This unit provides:
  *   - A thin wrapper around the native Snappy dynamic library.
  *   - TMS64 and TMem64 helper methods for easy compression/decompression
  *     on memory streams.
  *
  * The native library is loaded dynamically. Supported platforms:
  *   - Windows: snappy_x86.dll / snappy_x64.dll
  *   - Linux: libsnappy.so
  *
  * @Example (basic usage with TMS64):
  *   var
  *     src, compressed, decompressed: TMS64;
  *   begin
  *     src := TMS64.Create;
  *     src.WriteString('Hello, Snappy!');
  *
  *     compressed := TMS64.Create;
  *     src.snappy_compress_To(compressed);   // compress src -> compressed
  *
  *     decompressed := TMS64.Create;
  *     compressed.snappy_uncompress_To(decompressed); // decompress -> decompressed
  *
  *     // decompressed now contains the original string.
  *     // You can also check validity:
  *     if compressed.is_snappy_compressed then ...
  *   end;
  *
  * @Example (using TMem64):
  *   var
  *     src, out: TMem64;
  *   begin
  *     src := TMem64.Create;
  *     src.LoadFromFile('data.bin');
  *     out := TMem64.Create;
  *     src.snappy_compress_To(out);  // compress to out
  *     out.SaveToFile('data.snap');
  *   end;
  *
  * All helper methods return Boolean indicating success.
  * On failure, the target stream may be left in an undefined state.
  * The Snappy library is thread‑safe; multiple calls can be made concurrently
  * from different threads.
}
unit Z.Snappy;

{$I Z.Define.inc}

interface

uses Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib, Z.MemoryStream;

{ * Library name and function prefix for each platform.
  * These constants are used to load the correct dynamic library at runtime.
}
const
{$IF Defined(WIN32)}
  C_Snappy_Lib = 'snappy_x86.dll'; // 32‑bit Windows DLL
  C_FuncPre = ''; // no prefix
{$ELSEIF Defined(WIN64)}
  C_Snappy_Lib = 'snappy_x64.dll'; // 64‑bit Windows DLL
  C_FuncPre = '';
{$ELSEIF Defined(Linux)}
  C_Snappy_Lib = 'libsnappy.so'; // Linux shared object
  C_FuncPre = '';
{$ELSE}
{$MESSAGE Error 'Unsupported platform'}
{$ENDIF}


type
  { * TMS64_Snappy_Helper_
    * Class helper for TMS64 that adds Snappy compression/decompression methods.
    *
    * These methods operate on the memory stream itself as the source or target.
    * All methods return True on success, False on failure.
    *
    * @Example:
    *   var src, dest: TMS64;
    *   begin
    *     src := TMS64.Create;
    *     src.WriteString('data');
    *     dest := TMS64.Create;
    *     if src.snappy_compress_To(dest) then
    *       // dest now contains compressed data.
    *   end;
  }
  TMS64_Snappy_Helper_ = class helper for TMS64
  public
    { * Compresses the content of this stream and stores the result in another TMS64.
      * @param inst  Target stream that will receive compressed data.
      * @return True if compression succeeded, False otherwise.
      * @Example:
      *   var src, out: TMS64;
      *   begin
      *     src := TMS64.Create; src.WriteString('...');
      *     out := TMS64.Create;
      *     src.snappy_compress_To(out);
      *   end;
    }
    function snappy_compress_To(inst: TMS64): Boolean; overload;

    { * Compresses the content of this stream and stores the result in a TMem64.
      * @param inst  Target TMem64 stream.
      * @return True on success, False otherwise.
    }
    function snappy_compress_To(inst: TMem64): Boolean; overload;

    { * Compresses the content of another TMS64 and stores it into this stream.
      * Equivalent to `inst.snappy_compress_To(Self)`.
      * @param inst  Source stream to be compressed.
      * @return True on success, False otherwise.
    }
    function snappy_compress_From(inst: TMS64): Boolean; overload;

    { * Compresses the content of a TMem64 and stores it into this stream.
      * @param inst  Source TMem64 stream.
      * @return True on success, False otherwise.
    }
    function snappy_compress_From(inst: TMem64): Boolean; overload;

    { * Decompresses the content of another TMS64 and stores the result into this stream.
      * The source data must be a valid Snappy compressed block.
      * @param inst  Source compressed stream.
      * @return True on success, False if the data is invalid or decompression fails.
    }
    function snappy_uncompress_From(inst: TMS64): Boolean; overload;

    { * Decompresses the content of a TMem64 and stores the result into this stream.
      * @param inst  Source compressed TMem64.
      * @return True on success, False otherwise.
    }
    function snappy_uncompress_From(inst: TMem64): Boolean; overload;

    { * Decompresses the content of this stream and stores the result in another TMS64.
      * Equivalent to `inst.snappy_uncompress_From(Self)`.
      * @param inst  Target stream for decompressed data.
      * @return True on success, False otherwise.
    }
    function snappy_uncompress_To(inst: TMS64): Boolean; overload;

    { * Decompresses the content of this stream and stores the result in a TMem64.
      * @param inst  Target TMem64.
      * @return True on success, False otherwise.
    }
    function snappy_uncompress_To(inst: TMem64): Boolean; overload;

    { * Checks whether the content of this stream appears to be a valid
      * Snappy compressed block. This is a fast validation that does not
      * perform full decompression.
      * @return True if the buffer is a valid Snappy compressed block.
    }
    function is_snappy_compressed: Boolean;
  end;

  { * TMem64_Snappy_Helper_
    * Class helper for TMem64, identical to TMS64_Snappy_Helper_ but for TMem64.
    * All methods have the same semantics.
    *
    * @Example:
    *   var src, compressed: TMem64;
    *   begin
    *     src := TMem64.Create; src.LoadFromFile('input.dat');
    *     compressed := TMem64.Create;
    *     src.snappy_compress_To(compressed);
    *   end;
  }
  TMem64_Snappy_Helper_ = class helper for TMem64
  public
    function snappy_compress_To(inst: TMS64): Boolean; overload;
    function snappy_compress_To(inst: TMem64): Boolean; overload;
    function snappy_compress_From(inst: TMS64): Boolean; overload;
    function snappy_compress_From(inst: TMem64): Boolean; overload;
    function snappy_uncompress_From(inst: TMS64): Boolean; overload;
    function snappy_uncompress_From(inst: TMem64): Boolean; overload;
    function snappy_uncompress_To(inst: TMS64): Boolean; overload;
    function snappy_uncompress_To(inst: TMem64): Boolean; overload;
    function is_snappy_compressed: Boolean;
  end;

  { * TSnappy_Status
    * Return codes for the native Snappy functions.
    * - SNAPPY_OK: operation completed successfully.
    * - SNAPPY_INVALID_INPUT: input data is corrupted or malformed.
    * - SNAPPY_BUFFER_TOO_SMALL: the output buffer is not large enough.
  }
  TSnappy_Status = (
    SNAPPY_OK = 0,
    SNAPPY_INVALID_INPUT = 1,
    SNAPPY_BUFFER_TOO_SMALL = 2
    );

  { * Native Snappy API functions, imported from the dynamic library.
    * They are declared cdecl and use NativeUInt for sizes.
    * All functions return a TSnappy_Status.
    *
    * snappy_compress:
    *   Compresses `input_length` bytes from `input` into `compressed`.
    *   On entry, `compressed_length` must contain the size of the output buffer.
    *   On success, it is updated to the actual compressed size.
    *   It is safe to call with compressed_length = snappy_max_compressed_length(input_length).
    *
    * snappy_uncompress:
    *   Decompresses `compressed_length` bytes from `compressed` into `uncompressed`.
    *   The caller must provide a buffer large enough; the required size can be
    *   obtained via snappy_uncompressed_length.
    *
    * snappy_max_compressed_length:
    *   Returns the maximum possible compressed size for a given input length.
    *   This is an upper bound, not the actual size.
    *
    * snappy_uncompressed_length:
    *   Retrieves the exact uncompressed size of a compressed block.
    *   Useful for allocating the output buffer before decompression.
    *
    * snappy_validate_compressed_buffer:
    *   Checks if a buffer appears to be a valid Snappy compressed block.
    *   Returns SNAPPY_OK if valid, SNAPPY_INVALID_INPUT otherwise.
  }
function snappy_compress(input: Pointer; input_length: NativeUInt; compressed: Pointer; var compressed_length: NativeUInt): TSnappy_Status; cdecl;
  external C_Snappy_Lib name C_FuncPre + 'snappy_compress' {$IFDEF DELPHI}delayed {$ENDIF DELPHI};

function snappy_uncompress(compressed: Pointer; compressed_length: NativeUInt; uncompressed: Pointer; var uncompressed_length: NativeUInt): TSnappy_Status; cdecl;
  external C_Snappy_Lib name C_FuncPre + 'snappy_uncompress' {$IFDEF DELPHI}delayed {$ENDIF DELPHI};

function snappy_max_compressed_length(source_length: NativeUInt): NativeUInt; cdecl;
  external C_Snappy_Lib name C_FuncPre + 'snappy_max_compressed_length' {$IFDEF DELPHI}delayed {$ENDIF DELPHI};

function snappy_uncompressed_length(compressed: Pointer; compressed_length: NativeUInt; var result_: NativeUInt): TSnappy_Status; cdecl;
  external C_Snappy_Lib name C_FuncPre + 'snappy_uncompressed_length' {$IFDEF DELPHI}delayed {$ENDIF DELPHI};

function snappy_validate_compressed_buffer(compressed: Pointer; compressed_length: NativeUInt): TSnappy_Status; cdecl;
  external C_Snappy_Lib name C_FuncPre + 'snappy_validate_compressed_buffer' {$IFDEF DELPHI}delayed {$ENDIF DELPHI};

implementation

{ * TMS64_Snappy_Helper_.snappy_compress_To (TMS64 overload) }
function TMS64_Snappy_Helper_.snappy_compress_To(inst: TMS64): Boolean;
var
  L: NativeUInt; // maximum possible compressed size
begin
  L := snappy_max_compressed_length(size); // compute upper bound
  inst.size := L; // allocate output buffer
  Result := snappy_compress(memory, size, inst.memory, L) = TSnappy_Status.SNAPPY_OK;
  inst.size := L; // set final size (actual compressed length)
end;

{ * TMS64_Snappy_Helper_.snappy_compress_To (TMem64 overload) }
function TMS64_Snappy_Helper_.snappy_compress_To(inst: TMem64): Boolean;
var
  L: NativeUInt;
begin
  L := snappy_max_compressed_length(size);
  inst.size := L;
  Result := snappy_compress(memory, size, inst.memory, L) = TSnappy_Status.SNAPPY_OK;
  inst.size := L;
end;

{ * TMS64_Snappy_Helper_.snappy_compress_From (TMS64) }
function TMS64_Snappy_Helper_.snappy_compress_From(inst: TMS64): Boolean;
begin
  Result := inst.snappy_compress_To(self); // delegate to the source's To method
end;

{ * TMS64_Snappy_Helper_.snappy_compress_From (TMem64) }
function TMS64_Snappy_Helper_.snappy_compress_From(inst: TMem64): Boolean;
begin
  Result := inst.snappy_compress_To(self);
end;

{ * TMS64_Snappy_Helper_.snappy_uncompress_From (TMS64) }
function TMS64_Snappy_Helper_.snappy_uncompress_From(inst: TMS64): Boolean;
var
  L: NativeUInt; // uncompressed size
begin
  Result := False;
  // First, get the required output size.
  if snappy_uncompressed_length(inst.memory, inst.size, L) = TSnappy_Status.SNAPPY_OK then
    begin
      size := L; // allocate output buffer
      Result := snappy_uncompress(inst.memory, inst.size, memory, L) = TSnappy_Status.SNAPPY_OK;
      if Result then
          size := L; // on success, set final size
    end;
end;

{ * TMS64_Snappy_Helper_.snappy_uncompress_From (TMem64) }
function TMS64_Snappy_Helper_.snappy_uncompress_From(inst: TMem64): Boolean;
var
  L: NativeUInt;
begin
  Result := False;
  if snappy_uncompressed_length(inst.memory, inst.size, L) = TSnappy_Status.SNAPPY_OK then
    begin
      size := L;
      Result := snappy_uncompress(inst.memory, inst.size, memory, L) = TSnappy_Status.SNAPPY_OK;
      if Result then
          size := L;
    end;
end;

{ * TMS64_Snappy_Helper_.snappy_uncompress_To (TMS64) }
function TMS64_Snappy_Helper_.snappy_uncompress_To(inst: TMS64): Boolean;
begin
  Result := inst.snappy_uncompress_From(self); // delegate to target's From
end;

{ * TMS64_Snappy_Helper_.snappy_uncompress_To (TMem64) }
function TMS64_Snappy_Helper_.snappy_uncompress_To(inst: TMem64): Boolean;
begin
  Result := inst.snappy_uncompress_From(self);
end;

{ * TMS64_Snappy_Helper_.is_snappy_compressed }
function TMS64_Snappy_Helper_.is_snappy_compressed: Boolean;
begin
  Result := snappy_validate_compressed_buffer(memory, size) = TSnappy_Status.SNAPPY_OK;
end;

{ * TMem64_Snappy_Helper_ methods – identical to TMS64 counterparts. }
function TMem64_Snappy_Helper_.snappy_compress_To(inst: TMS64): Boolean;
var
  L: NativeUInt;
begin
  L := snappy_max_compressed_length(size);
  inst.size := L;
  Result := snappy_compress(memory, size, inst.memory, L) = TSnappy_Status.SNAPPY_OK;
  inst.size := L;
end;

function TMem64_Snappy_Helper_.snappy_compress_To(inst: TMem64): Boolean;
var
  L: NativeUInt;
begin
  L := snappy_max_compressed_length(size);
  inst.size := L;
  Result := snappy_compress(memory, size, inst.memory, L) = TSnappy_Status.SNAPPY_OK;
  inst.size := L;
end;

function TMem64_Snappy_Helper_.snappy_compress_From(inst: TMS64): Boolean;
begin
  Result := inst.snappy_compress_To(self);
end;

function TMem64_Snappy_Helper_.snappy_compress_From(inst: TMem64): Boolean;
begin
  Result := inst.snappy_compress_To(self);
end;

function TMem64_Snappy_Helper_.snappy_uncompress_From(inst: TMS64): Boolean;
var
  L: NativeUInt;
begin
  Result := False;
  if snappy_uncompressed_length(inst.memory, inst.size, L) = TSnappy_Status.SNAPPY_OK then
    begin
      size := L;
      Result := snappy_uncompress(inst.memory, inst.size, memory, L) = TSnappy_Status.SNAPPY_OK;
      if Result then
          size := L;
    end;
end;

function TMem64_Snappy_Helper_.snappy_uncompress_From(inst: TMem64): Boolean;
var
  L: NativeUInt;
begin
  Result := False;
  if snappy_uncompressed_length(inst.memory, inst.size, L) = TSnappy_Status.SNAPPY_OK then
    begin
      size := L;
      Result := snappy_uncompress(inst.memory, inst.size, memory, L) = TSnappy_Status.SNAPPY_OK;
      if Result then
          size := L;
    end;
end;

function TMem64_Snappy_Helper_.snappy_uncompress_To(inst: TMS64): Boolean;
begin
  Result := inst.snappy_uncompress_From(self);
end;

function TMem64_Snappy_Helper_.snappy_uncompress_To(inst: TMem64): Boolean;
begin
  Result := inst.snappy_uncompress_From(self);
end;

function TMem64_Snappy_Helper_.is_snappy_compressed: Boolean;
begin
  Result := snappy_validate_compressed_buffer(memory, size) = TSnappy_Status.SNAPPY_OK;
end;

end.
 
