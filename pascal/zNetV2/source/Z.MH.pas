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
{ ****************************************************************************** }
{ * Low MemoryHook                                                             * }
{ ****************************************************************************** }
unit Z.MH;

{$I Z.Define.inc}

interface

uses Z.Core, SyncObjs, Z.ListEngine;

procedure BeginMemoryHook_1;
procedure EndMemoryHook_1;
function GetHookMemorySize_1: nativeUInt;
function GetHookPtrList_1: TPointerHashNativeUIntList;

procedure BeginMemoryHook_2;
procedure EndMemoryHook_2;
function GetHookMemorySize_2: nativeUInt;
function GetHookPtrList_2: TPointerHashNativeUIntList;

procedure BeginMemoryHook_3;
procedure EndMemoryHook_3;
function GetHookMemorySize_3: nativeUInt;
function GetHookPtrList_3: TPointerHashNativeUIntList;

implementation

uses Z.MH_ZDB, Z.MH1, Z.MH2, Z.MH3, Z.Status, Z.PascalStrings, Z.UPascalStrings;

procedure BeginMemoryHook_1;
begin
  Z.MH1.BeginMemoryHook($FFFF);
end;

procedure EndMemoryHook_1;
begin
  Z.MH1.EndMemoryHook;
end;

function GetHookMemorySize_1: nativeUInt;
begin
  Result := Z.MH1.GetHookMemorySize;
end;

function GetHookPtrList_1: TPointerHashNativeUIntList;
begin
  Result := Z.MH1.GetHookPtrList;
end;

procedure BeginMemoryHook_2;
begin
  Z.MH2.BeginMemoryHook($FFFF);
end;

procedure EndMemoryHook_2;
begin
  Z.MH2.EndMemoryHook;
end;

function GetHookMemorySize_2: nativeUInt;
begin
  Result := Z.MH2.GetHookMemorySize;
end;

function GetHookPtrList_2: TPointerHashNativeUIntList;
begin
  Result := Z.MH2.GetHookPtrList;
end;

procedure BeginMemoryHook_3;
begin
  Z.MH3.BeginMemoryHook($FFFF);
end;

procedure EndMemoryHook_3;
begin
  Z.MH3.EndMemoryHook;
end;

function GetHookMemorySize_3: nativeUInt;
begin
  Result := Z.MH3.GetHookMemorySize;
end;

function GetHookPtrList_3: TPointerHashNativeUIntList;
begin
  Result := Z.MH3.GetHookPtrList;
end;

var
  MHStatusCritical: TCriticalSection;
  OriginDoStatusHook: TDoStatus_C;

procedure InternalDoStatus(Text: SystemString; const ID: Integer);
var
  hook_state_bak: Boolean;
begin
  hook_state_bak := GlobalMemoryHook.V;
  GlobalMemoryHook.V := False;
  MHStatusCritical.Acquire;
  try
      OriginDoStatusHook(Text, ID);
  finally
    MHStatusCritical.Release;
    GlobalMemoryHook.V := hook_state_bak;
  end;
end;

initialization

MHStatusCritical := TCriticalSection.Create;
OriginDoStatusHook := OnDoStatusHook;
OnDoStatusHook := {$IFDEF FPC}@{$ENDIF FPC}InternalDoStatus;

finalization

DisposeObject(MHStatusCritical);
OnDoStatusHook := OriginDoStatusHook;

end.
 
