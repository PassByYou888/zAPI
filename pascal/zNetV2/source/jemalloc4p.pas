{ * jemalloc4p – Pascal binding for the jemalloc memory allocator
  * ===============================================================
  *
  * This unit replaces the default memory manager (Delphi or FPC) with
  * jemalloc – a general‑purpose, concurrent, scalable allocator
  * originally developed by Jason Evans for FreeBSD and now widely used
  * in production (e.g., Firefox, Redis, Rust).
  *
  * Key features of jemalloc:
  *   - Scalable multi‑threaded allocation with low fragmentation.
  *   - Per‑CPU arenas to reduce contention.
  *   - Optional profiling and heap statistics (not used here).
  *
  * This binding loads the native jemalloc library dynamically and provides
  * full memory manager hooks. Behaviour differs slightly between FPC and
  * Delphi:
  *   - On FPC, each allocation stores the user‑requested size in a header
  *     preceding the returned pointer, so MemSize always returns the
  *     exact size. This header is *not* used on Delphi because Delphi’s
  *     memory manager does not require a separate stored size.
  *   - On all platforms, GetMem/FreeMem/ReallocMem/AllocMem are redirected.
  *
  * The native library is selected by platform:
  *   - Windows 32‑bit : jemalloc_IA32.dll
  *   - Windows 64‑bit : jemalloc_X64.dll
  *   - Linux          : libjemalloc.so
  *   - macOS          : libjemalloc.dylib
  *   - iOS            : libjemalloc.a   (static – but loaded at runtime)
  *   - Android        : libjemalloc.so
  *
  * @Example (automatic usage):
  *   // Just add jemalloc4p to your uses clause; the memory manager is
  *   // replaced at unit initialization and restored at finalization.
  *   program MyApp;
  *   uses
  *     jemalloc4p,  // all subsequent allocations use jemalloc
  *     SysUtils;
  *   var
  *     P: Pointer;
  *   begin
  *     GetMem(P, 1024);        // allocated by je_malloc
  *     FillChar(P^, 1024, 0);
  *     WriteLn(MemSize(P));    // returns 1024 (FPC) or actual block size (Delphi)
  *     FreeMem(P);
  *   end.
  *
  * This unit is part of the Z‑framework and is maintained at:
  *   https://github.com/PassByYou888/jemalloc4p
}
unit jemalloc4p;

{$IFDEF FPC}
  {$MODE objfpc}
  {$NOTES OFF}
  {$STACKFRAMES OFF}
  {$COPERATORS OFF}
  {$GOTO OFF}
  {$INLINE ON}
  {$MACRO ON}
  {$HINTS ON}
  {$IEEEERRORS ON}
{$ENDIF FPC}

{$R-}
{$I-}
{$S-}
{$D-}
{$OPTIMIZATION ON}

interface

implementation

const
  { * Name of the native jemalloc library and function prefix, per platform.
    * These are used in the external declarations below.
  }
{$IF Defined(WIN32)}
  jemalloc4p_Lib = 'jemalloc_IA32.dll'; // 32‑bit Windows
  C_FuncPre = 'je_'; // jemalloc exports prefixed with 'je_'
{$ELSEIF Defined(WIN64)}
  jemalloc4p_Lib = 'jemalloc_X64.dll'; // 64‑bit Windows
  C_FuncPre = 'je_';
{$ELSEIF Defined(OSX)}
  jemalloc4p_Lib = 'libjemalloc.dylib'; // macOS dynamic library
  C_FuncPre = '_je_'; // macOS uses an underscore prefix
{$ELSEIF Defined(IOS)}
  jemalloc4p_Lib = 'libjemalloc.a'; // iOS static library (but still `external`)
  C_FuncPre = '_je_'; // also prefixed
{$ELSEIF Defined(ANDROID)}
  jemalloc4p_Lib = 'libjemalloc.so'; // Android shared object
  C_FuncPre = 'je_';
{$ELSEIF Defined(Linux)}
  jemalloc4p_Lib = 'libjemalloc.so'; // Linux shared object
  C_FuncPre = ''; // Linux exports plain `malloc` etc.
{$ELSE}
{$MESSAGE FATAL 'unknow system.'}
{$IFEND}

  { * je_malloc: Direct call to jemalloc’s malloc.
    * @param Size  Number of bytes to allocate.
    * @return      Pointer to allocated memory, or nil on failure.
  }
function je_malloc(Size: NativeUInt): Pointer; cdecl; external jemalloc4p_Lib Name C_FuncPre + 'malloc';

{ * je_free: Direct call to jemalloc’s free.
  * @param P  Pointer to memory previously returned by je_malloc/je_realloc.
  *           If nil, does nothing.
}
procedure je_free(P: Pointer); cdecl; external jemalloc4p_Lib Name C_FuncPre + 'free';

{ * je_realloc: Direct call to jemalloc’s realloc.
  * Resizes a previously allocated block. If P is nil, behaves like malloc.
  * If Size is 0, frees the block and returns nil.
  * @param P     Original pointer (may be nil).
  * @param Size  New size in bytes.
  * @return      New pointer, or nil on failure. On failure, the original
  *              block remains valid.
}
function je_realloc(P: Pointer; Size: NativeUInt): Pointer; cdecl; external jemalloc4p_Lib Name C_FuncPre + 'realloc';

{ * Fast_FillByte: Optimised memory fill using 64‑bit writes.
  * This is faster than a simple loop for large blocks.
  * @param dest  Start address to fill.
  * @param Count Number of bytes to fill.
  * @param Value Byte value to write repeatedly.
}
procedure Fast_FillByte(const dest: Pointer; Count: NativeUInt; const Value: byte); inline;
var
  d: PByte;
  v: UInt64;
begin
  if Count <= 0 then
      Exit;
  v := Value or (Value shl 8) or (Value shl 16) or (Value shl 24); // repeat into 32 bits
  v := v or (v shl 32); // repeat into 64 bits
  d := dest;
  while Count >= 8 do
    begin
      PUInt64(d)^ := v; // write 8 bytes at once
      Dec(Count, 8);
      Inc(d, 8);
    end;
  if Count >= 4 then
    begin
      PCardinal(d)^ := PCardinal(@v)^; // write 4 bytes
      Dec(Count, 4);
      Inc(d, 4);
    end;
  if Count >= 2 then
    begin
      PWORD(d)^ := PWORD(@v)^; // write 2 bytes
      Dec(Count, 2);
      Inc(d, 2);
    end;
  if Count > 0 then
      d^ := Value; // write last single byte
end;

{$IFDEF FPC}

(*
  Pointer math is simply treating any given typed pointer in some narrow,
  instances as a scaled ordinal where you can perform simple arithmetic operations directly on the pointer variable.
*)
{$POINTERMATH ON}   // Enable pointer arithmetic (P + offset) for FPC

{ * For FPC, we store the user‑requested size in a header right before the
  * returned pointer. This allows MemSize to return the exact original size.
  * The header is one PtrUInt (SizeOf(PtrUInt) bytes).
}
var
  OriginMM: TMemoryManager; // original memory manager, saved for restoration
  HookMM: TMemoryManager; // our custom manager

  { * do_GetMem: Allocates memory with a header containing the size.
    * @param Size  User‑requested size.
    * @return      User pointer (header + data), or nil on failure.
  }
function do_GetMem(Size: PtrUInt): Pointer;
begin
  Result := je_malloc(Size + SizeOf(PtrUInt)); // allocate extra space for header

  if (Result <> nil) then
    begin
      PPtrUInt(Result)^ := Size; // store size in header
      Inc(Result, SizeOf(PtrUInt)); // move pointer past header to user area
    end;
end;

{ * do_FreeMem: Frees memory allocated by do_GetMem or do_AllocMem.
  * @param P  User pointer (must not be nil).
  * @return   0 (always success, as expected by FPC).
}
function do_FreeMem(P: Pointer): PtrUInt;
begin
  if (P <> nil) then
      Dec(P, SizeOf(PtrUInt)); // move back to header start

  je_free(P);
  Result := 0;
end;

{ * do_FreememSize: Frees a block with known size (size is ignored here).
  * @param P     User pointer.
  * @param Size  Ignored.
  * @return      0.
}
function do_FreememSize(P: Pointer; Size: PtrUInt): PtrUInt;
begin
  Result := 0;
  if Size = 0 then
      Exit;

  if P <> nil then
    begin
      Dec(P, SizeOf(PtrUInt));
      je_free(P);
    end;
end;

{ * do_AllocMem: Allocates zero‑initialised memory.
  * Uses je_malloc and then Fast_FillByte to zero the entire block.
  * @param Size  User‑requested size.
  * @return      User pointer, or nil.
}
function do_AllocMem(Size: PtrUInt): Pointer;
var
  TotalSize: PtrUInt;
begin
  TotalSize := Size + SizeOf(PtrUInt);

  Result := je_malloc(TotalSize);

  if Result <> nil then
    begin
      Fast_FillByte(Result, TotalSize, 0); // zero both header and user area
      PPtrUInt(Result)^ := Size; // store size in header
      Inc(Result, SizeOf(PtrUInt));
    end;
end;

{ * do_ReallocMem: Resizes a block, preserving existing data.
  * Handles Size=0 and P=nil cases correctly.
  * @param P     Pointer to the block (may be nil).
  * @param Size  New size in bytes.
  * @return      New user pointer, or nil on failure. On failure, P is unchanged.
}
function do_ReallocMem(var P: Pointer; Size: PtrUInt): Pointer;
begin
  if Size = 0 then
    begin
      if P <> nil then
        begin
          Dec(P, SizeOf(PtrUInt)); // go to header
          je_free(P);
          P := nil;
        end;
    end
  else
    begin
      Inc(Size, SizeOf(PtrUInt)); // total needed
      if P = nil then
          P := je_malloc(Size) // allocate new block
      else
        begin
          Dec(P, SizeOf(PtrUInt)); // move to header
          P := je_realloc(P, Size); // realloc raw block
        end;

      if P <> nil then
        begin
          PPtrUInt(P)^ := Size - SizeOf(PtrUInt); // store new user size
          Inc(P, SizeOf(PtrUInt)); // return user pointer
        end;
    end;

  Result := P; // return updated pointer
end;

{ * do_MemSize: Returns the exact user‑requested size stored in the header.
  * @param P  User pointer.
  * @return   Original allocation size.
}
function do_MemSize(P: Pointer): PtrUInt;
begin
  Result := PPtrUInt(P - SizeOf(PtrUInt))^;
end;

{ * do_GetHeapStatus: Returns a THeapStatus record (not used by jemalloc).
  * We fill it with zeros to satisfy the interface.
}
function do_GetHeapStatus: THeapStatus;
begin
  Fast_FillByte(@Result, SizeOf(Result), 0);
end;

{ * do_GetFPCHeapStatus: Returns TFPCHeapStatus (not used). Filled with zeros.
}
function do_GetFPCHeapStatus: TFPCHeapStatus;
begin
  Fast_FillByte(@Result, SizeOf(Result), 0);
end;

{ * InstallMemoryHook: Replaces the default memory manager with our hooks.
  * Saves the original in OriginMM.
}
procedure InstallMemoryHook;
const
  C_: TMemoryManager =
    (
    NeedLock: False; // we don't need locking; jemalloc handles it
    GetMem: @do_GetMem;
    FreeMem: @do_FreeMem;
    FreeMemSize: @do_FreememSize;
    AllocMem: @do_AllocMem;
    ReallocMem: @do_ReallocMem;
    MemSize: @do_MemSize;
    InitThread: nil; // FPC requires these, but jemalloc doesn't need them
    DoneThread: nil;
    RelocateHeap: nil;
    GetHeapStatus: @do_GetHeapStatus;
    GetFPCHeapStatus: @do_GetFPCHeapStatus;
  );
begin
  GetMemoryManager(OriginMM);
  HookMM := C_;
  SetMemoryManager(HookMM);
end;

{ * UnInstallMemoryHook: Restores the original memory manager.
}
procedure UnInstallMemoryHook;
begin
  SetMemoryManager(OriginMM);
end;

{$ELSE FPC}   // Delphi

{ * For Delphi, we use the TMemoryManagerEx interface.
  * Delphi does not require storing the size in a header because the RTL
  * already tracks block sizes internally. We simply forward calls directly.
}
var
  OriginMM: TMemoryManagerEx;
  HookMM: TMemoryManagerEx;

  { * do_GetMem: Allocates memory using je_malloc.
    * @param Size  Size in bytes.
    * @return      Pointer, or nil.
  }
function do_GetMem(Size: NativeInt): Pointer;
begin
  Result := je_malloc(Size);
end;

{ * do_FreeMem: Frees memory using je_free.
  * @param P  Pointer to free.
  * @return   0 (success).
}
function do_FreeMem(P: Pointer): integer;
begin
  je_free(P);
  Result := 0;
end;

{ * do_ReallocMem: Resizes a block using je_realloc.
  * @param P     Original pointer (may be nil).
  * @param Size  New size.
  * @return      New pointer, or nil on failure.
}
function do_ReallocMem(P: Pointer; Size: NativeInt): Pointer;
begin
  Result := je_realloc(P, Size);
end;

{ * do_AllocMem: Allocates zero‑initialised memory using je_malloc
  * and Fast_FillByte to zero.
  * @param Size  Size in bytes.
  * @return      Pointer to zeroed block.
}
function do_AllocMem(Size: NativeInt): Pointer;
begin
  Result := je_malloc(Size);
  Fast_FillByte(Result, Size, 0);
end;

{ * do_RegisterExpectedMemoryLeak / do_UnregisterExpectedMemoryLeak:
  * These are used by Delphi's memory leak detection. We don't implement them,
  * so we simply return False.
}
function do_RegisterExpectedMemoryLeak(P: Pointer): Boolean;
begin
  Result := False;
end;

function do_UnregisterExpectedMemoryLeak(P: Pointer): Boolean;
begin
  Result := False;
end;

{ * InstallMemoryHook: Replaces the default memory manager.
}
procedure InstallMemoryHook;
const
  C_: TMemoryManagerEx =
    (
    GetMem: do_GetMem;
    FreeMem: do_FreeMem;
    ReallocMem: do_ReallocMem;
    AllocMem: do_AllocMem;
    RegisterExpectedMemoryLeak: do_RegisterExpectedMemoryLeak;
    UnregisterExpectedMemoryLeak: do_UnregisterExpectedMemoryLeak;
  );
begin
  GetMemoryManager(OriginMM);
  HookMM := C_;
  SetMemoryManager(HookMM);
end;

{ * UnInstallMemoryHook: Restores the original manager.
}
procedure UnInstallMemoryHook;
begin
  SetMemoryManager(OriginMM);
end;

{$ENDIF FPC}

initialization

InstallMemoryHook; // install hooks when unit loads

finalization

UnInstallMemoryHook; // restore original when unit unloads

end.
