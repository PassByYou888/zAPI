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
{ ******************************************************************************
  * Z.MD5 – Fast MD5 Message‑Digest Implementation
  *
  * This unit provides a high‑performance MD5 hash function, optimized for
  * Windows/Delphi using hand‑written assembly (32‑bit and 64‑bit). On other
  * platforms, it falls back to a pure Pascal implementation from the
  * Z.UnicodeMixedLib unit. The API is simple: compute the MD5 digest of a
  * memory buffer or a stream (or a sub‑range of a stream).
  *
  * The MD5 algorithm produces a 128‑bit (16‑byte) hash, commonly represented
  * as a 32‑character hexadecimal string. This unit returns the digest as a
  * TMD5 record (an array of 16 bytes).
  *
  * The assembly versions are based on the work of Peter Sawatzki (32‑bit) and
  * Maxim Masiutin (64‑bit), and provide a significant speed boost over pure
  * Pascal on supported platforms.
  *
  * @Example (computing MD5 of a string):
  *   var
  *     s: RawByteString;
  *     digest: TMD5;
  *   begin
  *     s := 'Hello, world!';
  *     digest := FastMD5(@s[1], Length(s));   // Compute hash of the bytes
  *     // 'digest' now contains the 16‑byte MD5 checksum
  *   end;
  *
  * @Example (computing MD5 of a file stream):
  *   var
  *     fs: TFileStream;
  *     digest: TMD5;
  *   begin
  *     fs := TFileStream.Create('myfile.dat', fmOpenRead);
  *     try
  *       digest := FastMD5(fs, 0, fs.Size);  // Hash the entire file
  *     finally
  *       fs.Free;
  *     end;
  *   end;
  ****************************************************************************** }
unit Z.MD5;

{$I Z.Define.inc}

interface

uses Z.Core, Z.UnicodeMixedLib;

{
  * MD5_Transform – internal low‑level function that processes a single 64‑byte
  * chunk of data. It is implemented in assembly (on Windows/Delphi) or may be
  * unused elsewhere. You normally do not call this directly; use FastMD5 instead.
}
{$IF Defined(MSWINDOWS) and Defined(Delphi)}
procedure MD5_Transform(var Accu; const Buf);
{$ENDIF Defined(MSWINDOWS) and Defined(Delphi)}

{
  * FastMD5 – computes the MD5 digest of a memory buffer.
  * @Param buffPtr: pointer to the first byte of the buffer (PByte).
  * @Param bufSiz: size of the buffer in bytes (nativeUInt, typically 32‑bit or 64‑bit).
  * @Returns: a TMD5 record containing the 16‑byte digest.
  * @Example: see unit header.
}
function FastMD5(const buffPtr: PByte; bufSiz: nativeUInt): TMD5; overload;

{
  * FastMD5 – computes the MD5 digest of a portion of a stream.
  * @Param stream: a TCore_Stream (or descendant) to read from.
  * @Param StartPos: starting position (byte offset) in the stream; if greater than
  *        EndPos, the two values are swapped automatically.
  * @Param EndPos: ending position (exclusive) in the stream; the hash is computed
  *        over the range [StartPos, EndPos). Clamped to the stream size.
  * @Returns: a TMD5 record containing the 16‑byte digest for the specified range.
  * @Example: see unit header.
  *
  * If the stream is a TCore_MemoryStream or TMS64, and the conditional define
  * 'OptimizationMemoryStreamMD5' is set, the function reads the data directly
  * from memory without intermediate buffering, for extra speed.
}
function FastMD5(stream: TCore_Stream; StartPos, EndPos: Int64): TMD5; overload;

implementation

{$IF Defined(MSWINDOWS) and Defined(Delphi)}


uses Z.MemoryStream;

{ *************** Assembly‑linked MD5 core (Windows/Delphi only) *************** }
(*
  fastMD5 algorithm by Maxim Masiutin
  https://github.com/maximmasiutin/MD5_Transform-x64

  Delphi imp by 600585@qq.com
  https://github.com/PassByYou888/FastMD5

  For 32‑bit Windows, the external object file Z.MD5_32.obj contains the
  386‑optimized MD5_Transform routine by Peter Sawatzki.
  For 64‑bit Windows, Z.MD5_64.obj contains the x64 version by Maxim Masiutin.
*)

{$IF Defined(WIN32)}
{$L Z.MD5_32.obj} // Link 32‑bit assembly object
{$ELSEIF Defined(WIN64)}
{$L Z.MD5_64.obj} // Link 64‑bit assembly object
{$ENDIF}

{
  * MD5_Transform – externally implemented in assembly.
  * This procedure updates the MD5 accumulator (Accu) by hashing one 64‑byte block
  * (Buf). It is called repeatedly by FastMD5 for each full block of the input.
}
procedure MD5_Transform(var Accu; const Buf); register; external;

{
  * FastMD5 – buffer version (Windows/Delphi assembly accelerated).
  *
  * The algorithm follows the standard MD5 padding and processing:
  *   - Initialize the four 32‑bit state variables with the MD5 constants.
  *   - Process the input in 64‑byte chunks using MD5_Transform.
  *   - After all full blocks, pad the remaining data with a single '1' bit,
  *     then zeros, then the 64‑bit length in bits (low word first).
  *   - Process the final padded block(s) if needed.
}
function FastMD5(const buffPtr: PByte; bufSiz: nativeUInt): TMD5;
var
  Digest: TMD5;
  Lo, Hi: Cardinal;
  p: PByte;
  ChunkIndex: Byte;
  ChunkBuff: array [0 .. 63] of Byte;
begin
  // Initialize MD5 state (magic constants)
  PCardinal(@Digest[0])^ := $67452301;
  PCardinal(@Digest[4])^ := $EFCDAB89;
  PCardinal(@Digest[8])^ := $98BADCFE;
  PCardinal(@Digest[12])^ := $10325476;

  // Compute length in bits: low 32 bits, high 32 bits (bits shifted by 29)
  Lo := bufSiz shl 3; // lower 32 bits of bit length
  Hi := bufSiz shr 29; // upper 32 bits (since 2^29 = 512 MB)

  p := buffPtr;

  // Process full 64‑byte chunks
  while bufSiz >= $40 do
    begin
      MD5_Transform(Digest, p^);
      inc(p, $40);
      dec(bufSiz, $40);
    end;

  // Copy any remaining bytes into the chunk buffer
  if bufSiz > 0 then
      CopyPtr(p, @ChunkBuff[0], bufSiz);

  // Copy the current accumulator to Result (will be finalized)
  Result := PMD5(@Digest[0])^;

  // Padding: append a single '1' bit (0x80) after the data
  ChunkBuff[bufSiz] := $80;
  ChunkIndex := bufSiz + 1;

  // If the padding exceeds the 56‑byte mark (0x38), we need to process this
  // chunk and create a new one for the length.
  if ChunkIndex > $38 then
    begin
      if ChunkIndex < $40 then
          FillPtrByte(@ChunkBuff[ChunkIndex], $40 - ChunkIndex, 0); // zero fill the rest
      MD5_Transform(Result, ChunkBuff); // process this chunk
      ChunkIndex := 0;
    end;

  // Fill the rest of the buffer (up to position 0x38) with zeros
  FillPtrByte(@ChunkBuff[ChunkIndex], $38 - ChunkIndex, 0);

  // Append the 64‑bit bit length (little‑endian)
  PCardinal(@ChunkBuff[$38])^ := Lo;
  PCardinal(@ChunkBuff[$3C])^ := Hi;

  // Final transformation
  MD5_Transform(Result, ChunkBuff);
end;

{
  * FastMD5 – stream version (Windows/Delphi assembly accelerated).
  *
  * This version reads the stream in chunks (default chunk size = 64 * 0xFFFF bytes)
  * to avoid allocating a huge buffer. It uses a temporary block buffer (DeltaBuf)
  * for reading. If the stream is a memory‑based stream, and the define
  * OptimizationMemoryStreamMD5 is active, it reads directly from memory.
  *
  * The hash computation is otherwise identical to the buffer version.
}
function FastMD5(stream: TCore_Stream; StartPos, EndPos: Int64): TMD5;
const
  deltaSize: Cardinal = $40 * $FFFF; // 64 * 65535 = 4,194,240 bytes per read

var
  Digest: TMD5;
  Lo, Hi: Cardinal;
  DeltaBuf: Pointer;
  bufSiz: Int64;
  Rest: Cardinal;
  p: PByte;
  ChunkIndex: Byte;
  ChunkBuff: array [0 .. 63] of Byte;
begin
  // Ensure StartPos <= EndPos, swap if needed
  if StartPos > EndPos then
      TSwap<Int64>.Do_(StartPos, EndPos);

  // Clamp to valid stream range
  StartPos := umlClamp(StartPos, 0, stream.Size);
  EndPos := umlClamp(EndPos, 0, stream.Size);

  // If the range is empty, return hash of empty input
  if EndPos - StartPos <= 0 then
    begin
      Result := FastMD5(nil, 0);
      exit;
    end;

  // Optimization for memory streams: direct pointer access avoids reading
{$IFDEF OptimizationMemoryStreamMD5}
  if stream is TCore_MemoryStream then
    begin
      Result := FastMD5(Pointer(nativeUInt(TCore_MemoryStream(stream).Memory) + StartPos), EndPos - StartPos);
      exit;
    end;
  if stream is TMS64 then
    begin
      Result := FastMD5(TMS64(stream).PositionAsPtr(StartPos), EndPos - StartPos);
      exit;
    end;
{$ENDIF}
  // Initialize MD5 state
  PCardinal(@Digest[0])^ := $67452301;
  PCardinal(@Digest[4])^ := $EFCDAB89;
  PCardinal(@Digest[8])^ := $98BADCFE;
  PCardinal(@Digest[12])^ := $10325476;

  bufSiz := EndPos - StartPos;
  Rest := 0;
  Lo := bufSiz shl 3; // lower 32 bits of bit length
  Hi := bufSiz shr 29; // upper 32 bits

  // Allocate a buffer for reading chunks from the stream
  DeltaBuf := GetMemory(deltaSize);
  stream.Position := StartPos;

  // If the total size is less than one block, just read it directly
  if bufSiz < $40 then
    begin
      stream.read(DeltaBuf^, bufSiz);
      p := DeltaBuf;
    end
  else
    // Otherwise, process in blocks: fill DeltaBuf as needed
    while bufSiz >= $40 do
      begin
        if Rest = 0 then
          begin
            // Determine how much to read next: either deltaSize or remaining
            if bufSiz >= deltaSize then
                Rest := deltaSize
            else
                Rest := bufSiz;
            stream.ReadBuffer(DeltaBuf^, Rest);
            p := DeltaBuf;
          end;

        // Process one 64‑byte block
        MD5_Transform(Digest, p^);
        inc(p, $40);
        dec(bufSiz, $40);
        dec(Rest, $40);
      end;

  // Copy any remaining bytes into the chunk buffer
  if bufSiz > 0 then
      CopyPtr(p, @ChunkBuff[0], bufSiz);

  FreeMemory(DeltaBuf); // release temporary read buffer

  // Finalize hash (same as buffer version)
  Result := PMD5(@Digest[0])^;
  ChunkBuff[bufSiz] := $80;
  ChunkIndex := bufSiz + 1;
  if ChunkIndex > $38 then
    begin
      if ChunkIndex < $40 then
          FillPtrByte(@ChunkBuff[ChunkIndex], $40 - ChunkIndex, 0);
      MD5_Transform(Result, ChunkBuff);
      ChunkIndex := 0;
    end;
  FillPtrByte(@ChunkBuff[ChunkIndex], $38 - ChunkIndex, 0);
  PCardinal(@ChunkBuff[$38])^ := Lo;
  PCardinal(@ChunkBuff[$3C])^ := Hi;
  MD5_Transform(Result, ChunkBuff);
end;

{$ELSE} // Not (Windows and Delphi): fallback to pure Pascal implementation

{
  * FastMD5 – buffer version (non‑Windows or non‑Delphi).
  * Uses the pure Pascal MD5 implementation from Z.UnicodeMixedLib.umlMD5.
}
function FastMD5(const buffPtr: PByte; bufSiz: nativeUInt): TMD5;
begin
  Result := umlMD5(buffPtr, bufSiz);
end;

{
  * FastMD5 – stream version (non‑Windows or non‑Delphi).
  * Uses the pure Pascal stream MD5 from Z.UnicodeMixedLib.umlStreamMD5.
}
function FastMD5(stream: TCore_Stream; StartPos, EndPos: Int64): TMD5;
begin
  Result := umlStreamMD5(stream, StartPos, EndPos);
end;

{$ENDIF Defined(MSWINDOWS) and Defined(Delphi)}

end.
 
