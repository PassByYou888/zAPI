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
unit Z.FP.Net.BSD.kqueue;

{ *
  * BSD.kqueue – Pascal translation of the BSD kqueue system calls.
  *
  * This unit defines the kqueue(), kevent() functions, the kevent structure,
  * and the event flags (EVFILT_READ, EVFILT_WRITE, EV_ADD, EV_DELETE, etc.)
  * used on BSD systems (including macOS, iOS, FreeBSD, etc.).
  *
  * The unit provides a helper procedure EV_SET to initialise a kevent record.
  *
  * Example:
  *   var
  *     kq: Integer;
  *     ev: TKEvent;
  *   begin
  *     kq := kqueue;
  *     EV_SET(@ev, fd, EVFILT_READ, EV_ADD or EV_ONESHOT, 0, 0, nil);
  *     kevent(kq, @ev, 1, nil, 0, nil);
  *   end;
}

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

{$IF defined(BSD) or defined(MACOS) or defined(IOS)}


uses
{$IFDEF FPC}
  BaseUnix,
  Unix,
  Sockets,
  netdb,
  termio,
  BSD;
{$ELSE FPC}
  Posix.Base, Posix.Time;
{$ENDIF FPC}

{$IFDEF DELPHI}

const
  EVFILT_READ = -1;
  EVFILT_WRITE = -2;
  EVFILT_AIO = -3; { attached to aio requests }
  EVFILT_VNODE = -4; { attached to vnodes }
  EVFILT_PROC = -5; { attached to struct proc }
  EVFILT_SIGNAL = -6; { attached to struct proc }
  EVFILT_TIMER = -7; { timers }
  EVFILT_NETDEV = -8; { network devices }
  EVFILT_FS = -9; { filesystem events }

  EVFILT_SYSCOUNT = 9;

  EV_ADD = $0001; { add event to kq }
  EV_DELETE = $0002; { delete event from kq }
  EV_ENABLE = $0004; { enable event }
  EV_DISABLE = $0008; { disable event (not reported) }

  { flags }
  EV_ONESHOT = $0010; { only report one occurrence }
  EV_CLEAR = $0020; { clear event state after reporting }
  EV_RECEIPT = $0040; { force EV_ERROR on success, data=0 }
  EV_DISPATCH = $0080; { disable event after reporting }
  EV_SYSFLAGS = $F000; { reserved by system }
  EV_FLAG1 = $2000; { filter-specific flag }

  { returned values }
  EV_EOF = $8000; { EOF detected }
  EV_ERROR = $4000; { error, data contains errno }

  { data/hint flags for EVFILT_READ|WRITE, shared with userspace }
  NOTE_LOWAT = $0001; { low water mark }

  { data/hint flags for EVFILT_VNODE, shared with userspace }
  NOTE_DELETE = $0001; { vnode was removed }
  NOTE_WRITE = $0002; { data contents changed }
  NOTE_EXTEND = $0004; { size increased }
  NOTE_ATTRIB = $0008; { attributes changed }
  NOTE_LINK = $0010; { link count changed }
  NOTE_RENAME = $0020; { vnode was renamed }
  NOTE_REVOKE = $0040; { vnode access was revoked }

  { data/hint flags for EVFILT_PROC, shared with userspace }
  NOTE_EXIT = $80000000; { process exited }
  NOTE_FORK = $40000000; { process forked }
  NOTE_EXEC = $20000000; { process exec'd }
  NOTE_PCTRLMASK = $F0000000; { mask for hint bits }
  NOTE_PDATAMASK = $000FFFFF; { mask for pid }

  { additional flags for EVFILT_PROC }
  NOTE_TRACK = $00000001; { follow across forks }
  NOTE_TRACKERR = $00000002; { could not track child }
  NOTE_CHILD = $00000004; { am a child process }

  { data/hint flags for EVFILT_NETDEV, shared with userspace }
  NOTE_LINKUP = $0001; { link is up }
  NOTE_LINKDOWN = $0002; { link is down }
  NOTE_LINKINV = $0004; { link state is invalid }

type
  PKEvent = ^TKEvent;

  TKEvent = record
    Ident: UIntPtr;
    Filter: SmallInt;
    Flags: Word;
    FFlags: Cardinal;
    Data: IntPtr;
    uData: Pointer;
  end;

function kqueue: Integer; cdecl; external libc name _PU + 'kqueue';
function kevent(kq: Integer; ChangeList: PKEvent; nChanged: Integer;
  EventList: PKEvent; nEvents: Integer; Timeout: PTimeSpec): Integer; cdecl;
  external libc name _PU + 'kevent';

{$ENDIF DELPHI}

procedure EV_SET(kevp: PKEvent; const aIdent: UIntPtr; const aFilter: SmallInt;
  const aFlags: Word; const aFFlags: Cardinal; const aData: IntPtr;
  const auData: Pointer);

{$ENDIF}

implementation

{$IF defined(BSD) or defined(MACOS) or defined(IOS)}


procedure EV_SET(kevp: PKEvent; const aIdent: UIntPtr; const aFilter: SmallInt;
  const aFlags: Word; const aFFlags: Cardinal; const aData: IntPtr;
  const auData: Pointer);
begin
  kevp^.Ident := aIdent;
  kevp^.Filter := aFilter;
  kevp^.Flags := aFlags;
  kevp^.FFlags := aFFlags;
  kevp^.Data := aData;
  kevp^.uData := auData;
end;

{$ENDIF}

end.
 
