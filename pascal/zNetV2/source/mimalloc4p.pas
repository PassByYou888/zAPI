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
{ * mimalloc4p – Pascal binding for the mimalloc memory allocator
  * =============================================================
  *
  * This unit replaces the default memory manager (Delphi or FPC) with
  * Microsoft’s mimalloc – a fast, scalable, thread‑safe allocator.
  *
  * Key features:
  *   - 16‑byte aligned header stores the exact user‑requested size.
  *   - Thread‑safe hooks for FPC (non‑nil InitThread/DoneThread).
  *   - Safe ReallocMem: on failure, the original pointer remains valid.
  *   - Optional full heap statistics via mi_stats_merge (not enabled here).
  *
  * The native mimalloc library is loaded dynamically. Supported platforms:
  *   - Windows 32‑bit : mimalloc32.dll
  *   - Windows 64‑bit : mimalloc64.dll
  *   - Linux          : libmimalloc.so
  *   - macOS          : libmimalloc.dylib
  *
  * @Example (basic usage – automatic):
  *   // Simply add Z.mimalloc4p to your uses clause.
  *   // All memory allocations (GetMem, FreeMem, ReallocMem, New, Dispose, etc.)
  *   // will now use mimalloc instead of the default manager.
  *   var
  *     P: Pointer;
  *   begin
  *     GetMem(P, 1024);   // allocated by mi_malloc with 16‑byte header
  *     FillChar(P^, 1024, 0);
  *     FreeMem(P);        // mi_free is called
  *   end;
  *
  * @Example (manual use of low‑level functions):
  *   var
  *     Raw, P: Pointer;
  *   begin
  *     Raw := mi_malloc(100 + HEADER_SIZE); // allocate raw with header
  *     if Raw <> nil then
  *     begin
  *       SetStoredSize(Raw, 100);           // store user size
  *       P := Raw + HEADER_SIZE;            // user pointer
  *       // ... use P ...
  *       mi_free(Raw);                      // free raw pointer
  *     end;
  *   end;
  *
  * This unit is part of the Z‑framework and is maintained at:
  *   https://github.com/PassByYou888/mimalloc4p
}
unit mimalloc4p;

{$I Z.Define.inc}
{$POINTERMATH ON}   // Allow pointer arithmetic (e.g. P + HEADER_SIZE)
{$INLINE ON}        // Inline small helper functions

interface

implementation

const
  { * Name of the native mimalloc library, selected by platform.
    * These constants are used in the external declarations below.
  }
{$IF Defined(WIN32)}
  mimalloc_Lib = 'mimalloc32.dll'; // 32‑bit Windows
{$ELSEIF Defined(WIN64)}
  mimalloc_Lib = 'mimalloc64.dll'; // 64‑bit Windows
{$ELSEIF Defined(LINUX)}
  mimalloc_Lib = 'libmimalloc.so'; // Linux shared object
{$ELSEIF Defined(DARWIN)}
  mimalloc_Lib = 'libmimalloc.dylib'; // macOS dynamic library
{$ELSE}
{$MESSAGE FATAL 'Unsupported platform'}
{$IFEND}
  { * HEADER_SIZE: bytes reserved before each user pointer.
    * mimalloc internally uses 16‑byte alignment; we store the exact
    * user‑requested size in the first PtrUInt field of this header.
    * This allows MemSize to return the correct size without relying on
    * internal allocator metadata.
  }
  HEADER_SIZE = 16;

  { --- Core mimalloc functions (cdecl calling convention) --- }

  { * mi_malloc: Allocates a block of memory of given size from the mimalloc heap.
    * @param Size  Number of bytes to allocate.
    * @return      Pointer to the allocated memory, or nil on failure.
  }
function mi_malloc(Size: NativeUInt): Pointer; cdecl; external mimalloc_Lib name 'mi_malloc';

{ * mi_free: Frees a block previously allocated by mi_malloc, mi_calloc, or mi_realloc.
  * @param P  Pointer to the block to free. If nil, does nothing.
}
procedure mi_free(P: Pointer); cdecl; external mimalloc_Lib name 'mi_free';

{ * mi_realloc: Resizes a previously allocated block to a new size.
  * If P is nil, behaves like mi_malloc. If Size is 0, frees the block and returns nil.
  * @param P     Original pointer (may be nil).
  * @param Size  New requested size in bytes.
  * @return      New pointer to the resized block, or nil on failure.
  *              On failure, the original block remains valid.
}
function mi_realloc(P: Pointer; Size: NativeUInt): Pointer; cdecl; external mimalloc_Lib name 'mi_realloc';

{ * mi_calloc: Allocates memory for an array of Count elements, each of Size bytes,
  * and initialises all bytes to zero.
  * @param Count  Number of elements.
  * @param Size   Size of each element.
  * @return       Pointer to the zero‑initialised block, or nil on failure.
}
function mi_calloc(Count: NativeUInt; Size: NativeUInt): Pointer; cdecl; external mimalloc_Lib name 'mi_calloc';

{ ---------------------------------------------------------------------------- }
{ Header helpers: store / retrieve the exact user‑requested size }
{ ---------------------------------------------------------------------------- }

type
  { * TSize__: The type used to store the user size in the header.
    * On FPC, PtrUInt is an alias for NativeUInt; on Delphi we use NativeUInt directly.
    * We define it to keep the code consistent.
  }
{$IFDEF FPC}
  TSize__ = PtrUInt;
{$ELSE FPC}
  TSize__ = NativeUInt;
{$ENDIF FPC}
  PSize__ = ^TSize__; // Pointer to the stored size

  { * GetStoredSize: Reads the user‑requested size from the 16‑byte header.
    * @param RawPtr  Pointer to the raw block (the start of the header).
    * @return        The stored size in bytes.
  }
function GetStoredSize(RawPtr: Pointer): TSize__; inline;
begin
  Result := PSize__(RawPtr)^; // cast to PSize__ and dereference
end;

{ * SetStoredSize: Writes the user‑requested size into the 16‑byte header.
  * @param RawPtr  Pointer to the raw block (the start of the header).
  * @param Size    The size to store.
}
procedure SetStoredSize(RawPtr: Pointer; Size: TSize__); inline;
begin
  PSize__(RawPtr)^ := Size;
end;

{ ---------------------------------------------------------------------------- }
{ Memory manager hooks }
{ ---------------------------------------------------------------------------- }

{$IFDEF FPC}

{ * For FPC, we must implement the TMemoryManager record.
  * It requires several callback functions; we provide all of them.
  * The manager is installed via SetMemoryManager.
}
var
  OriginMM: TMemoryManager; // original manager, saved to restore later
  HookMM: TMemoryManager; // our custom manager

  { * do_GetMem: Allocates memory using mimalloc with a 16‑byte header.
    * @param Size  User‑requested size.
    * @return      User pointer (raw + HEADER_SIZE), or nil on failure.
  }
function do_GetMem(Size: PtrUInt): Pointer;
var
  RawPtr: Pointer;
begin
  RawPtr := mi_malloc(Size + HEADER_SIZE); // allocate raw block with extra space
  if RawPtr <> nil then
    begin
      SetStoredSize(RawPtr, Size); // store exact user size in header
      Result := RawPtr + HEADER_SIZE; // return user pointer (past header)
    end
  else
      Result := nil;
end;

{ * do_FreeMem: Frees memory previously allocated by do_GetMem or do_AllocMem.
  * @param P  User pointer (must not be nil).
  * @return   0 (always success, as FreeMem is expected to return 0).
}
function do_FreeMem(P: Pointer): PtrUInt;
var
  RawPtr: Pointer;
begin
  if P <> nil then
    begin
      RawPtr := P - HEADER_SIZE; // get raw block pointer
      mi_free(RawPtr); // free raw block
    end;
  Result := 0; // standard return code
end;

{ * do_FreememSize: Frees a block with known size (size is ignored here).
  * In FPC, this is a separate callback. We simply call do_FreeMem.
  * @param P     User pointer.
  * @param Size  Ignored (mimalloc knows the block size internally).
  * @return      0.
}
function do_FreememSize(P: Pointer; Size: PtrUInt): PtrUInt;
begin
  Result := do_FreeMem(P);
end;

{ * do_AllocMem: Allocates zero‑initialised memory.
  * Uses mi_calloc to get zeroed memory.
  * @param Size  User‑requested size.
  * @return      User pointer, or nil on failure.
}
function do_AllocMem(Size: PtrUInt): Pointer;
var
  RawPtr: Pointer;
begin
  RawPtr := mi_calloc(1, Size + HEADER_SIZE); // allocate and zero
  if RawPtr <> nil then
    begin
      SetStoredSize(RawPtr, Size);
      Result := RawPtr + HEADER_SIZE;
    end
  else
      Result := nil;
end;

{ * do_ReallocMem: Resizes a block, preserving existing data.
  * If Size = 0, it frees the block and sets P to nil.
  * If P = nil, it allocates a new block.
  * On failure, P remains unchanged (safe behaviour).
  * @param P     Pointer to the block (may be nil).
  * @param Size  New size in bytes.
  * @return      New user pointer, or nil on failure.
}
function do_ReallocMem(var P: Pointer; Size: PtrUInt): Pointer;
var
  RawPtr, NewRawPtr: Pointer;
begin
  if Size = 0 then
    begin
      if P <> nil then
        begin
          RawPtr := P - HEADER_SIZE;
          mi_free(RawPtr);
          P := nil;
        end;
      Exit(nil);
    end;

  if P = nil then
    begin
      RawPtr := mi_malloc(Size + HEADER_SIZE);
      if RawPtr <> nil then
        begin
          SetStoredSize(RawPtr, Size);
          P := RawPtr + HEADER_SIZE;
        end;
      Exit(P);
    end;

  RawPtr := P - HEADER_SIZE;
  NewRawPtr := mi_realloc(RawPtr, Size + HEADER_SIZE);
  if NewRawPtr <> nil then
    begin
      SetStoredSize(NewRawPtr, Size);
      P := NewRawPtr + HEADER_SIZE;
    end;
  // On failure, P is unchanged (mi_realloc guarantees old block is still valid).
  Result := P;
end;

{ * do_MemSize: Returns the exact user‑requested size stored in the header.
  * This avoids relying on internal allocator metadata.
  * @param P  User pointer.
  * @return   The size originally requested when the block was allocated.
}
function do_MemSize(P: Pointer): PtrUInt;
begin
  if P = nil then
      Exit(0);
  Result := GetStoredSize(P - HEADER_SIZE);
end;

{ * do_GetHeapStatus: Returns a THeapStatus record (not used by mimalloc).
  * We fill it with zeros to satisfy the interface.
}
function do_GetHeapStatus: THeapStatus;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

{ * do_GetFPCHeapStatus: Returns TFPCHeapStatus (not used). Filled with zeros.
}
function do_GetFPCHeapStatus: TFPCHeapStatus;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

{ * DummyInitThread / DummyDoneThread: FPC requires non‑nil thread callbacks
  * for TLS (thread‑local storage) initialisation, otherwise multi‑threading
  * crashes. These do nothing but must exist and be non‑nil.
}
procedure DummyInitThread;
begin
end;

procedure DummyDoneThread;
begin
end;

{ * InstallMemoryHook: Replaces the default memory manager with our hooks.
  * Saves the original manager in OriginMM, then sets HookMM.
}
procedure InstallMemoryHook;
const
  C_: TMemoryManager = (
    NeedLock: False;
    GetMem: @do_GetMem;
    FreeMem: @do_FreeMem;
    FreeMemSize: @do_FreememSize;
    AllocMem: @do_AllocMem;
    ReallocMem: @do_ReallocMem;
    MemSize: @do_MemSize;
    InitThread: @DummyInitThread; // non‑nil to satisfy FPC
    DoneThread: @DummyDoneThread; // non‑nil to satisfy FPC
    RelocateHeap: nil;
    GetHeapStatus: @do_GetHeapStatus;
    GetFPCHeapStatus: @do_GetFPCHeapStatus;
  );
begin
  GetMemoryManager(OriginMM); // save current manager
  HookMM := C_;
  SetMemoryManager(HookMM); // install ours
end;

{ * UnInstallMemoryHook: Restores the original memory manager.
}
procedure UnInstallMemoryHook;
begin
  SetMemoryManager(OriginMM);
end;

{$ELSE}  // Delphi

{ * For Delphi, we implement the TMemoryManagerEx record.
  * It has fewer callbacks and uses NativeInt for sizes.
}
var
  OriginMM: TMemoryManagerEx;
  HookMM: TMemoryManagerEx;

  { * do_GetMem: Allocates memory with a header.
    * @param Size  User‑requested size (NativeInt).
    * @return      User pointer or nil.
  }
function do_GetMem(Size: NativeInt): Pointer;
var
  RawPtr: Pointer;
begin
  RawPtr := mi_malloc(Size + HEADER_SIZE);
  if RawPtr <> nil then
    begin
      SetStoredSize(RawPtr, Size);
      Result := Pointer(NativeUInt(RawPtr) + HEADER_SIZE);
    end
  else
      Result := nil;
end;

{ * do_FreeMem: Frees a block.
  * @param P  User pointer.
  * @return   0 on success.
}
function do_FreeMem(P: Pointer): Integer;
var
  RawPtr: Pointer;
begin
  if P <> nil then
    begin
      RawPtr := Pointer(NativeUInt(P) - HEADER_SIZE);
      mi_free(RawPtr);
    end;
  Result := 0;
end;

{ * do_ReallocMem: Resizes a block.
  * @param P     Pointer (may be nil).
  * @param Size  New size.
  * @return      New pointer, or nil on failure (old block remains valid).
}
function do_ReallocMem(P: Pointer; Size: NativeInt): Pointer;
var
  RawPtr, NewRawPtr: Pointer;
begin
  if Size = 0 then
    begin
      if P <> nil then
        begin
          RawPtr := Pointer(NativeUInt(P) - HEADER_SIZE);
          mi_free(RawPtr);
        end;
      Exit(nil);
    end;

  if P = nil then
    begin
      RawPtr := mi_malloc(Size + HEADER_SIZE);
      if RawPtr <> nil then
        begin
          SetStoredSize(RawPtr, Size);
          Result := Pointer(NativeUInt(RawPtr) + HEADER_SIZE);
        end
      else
          Result := nil;
      Exit;
    end;

  RawPtr := Pointer(NativeUInt(P) - HEADER_SIZE);
  NewRawPtr := mi_realloc(RawPtr, Size + HEADER_SIZE);
  if NewRawPtr <> nil then
    begin
      SetStoredSize(NewRawPtr, Size);
      Result := Pointer(NativeUInt(NewRawPtr) + HEADER_SIZE);
    end
  else
      Result := nil; // old block is still valid, but we signal failure
end;

{ * do_AllocMem: Allocates zero‑initialised memory.
  * @param Size  Size in bytes.
  * @return      User pointer or nil.
}
function do_AllocMem(Size: NativeInt): Pointer;
var
  RawPtr: Pointer;
begin
  RawPtr := mi_calloc(1, Size + HEADER_SIZE);
  if RawPtr <> nil then
    begin
      SetStoredSize(RawPtr, Size);
      Result := Pointer(NativeUInt(RawPtr) + HEADER_SIZE);
    end
  else
      Result := nil;
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

{ * InstallMemoryHook: Replaces the default memory manager with our hooks.
}
procedure InstallMemoryHook;
const
  C_: TMemoryManagerEx = (
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

{$ENDIF}

initialization

InstallMemoryHook; // replace default memory manager on unit load

finalization

UnInstallMemoryHook; // restore original manager on unit unload

end.
 
