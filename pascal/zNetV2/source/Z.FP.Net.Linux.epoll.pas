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
unit Z.FP.Net.Linux.epoll;

{ *
  * Linux.epoll – Pascal translation of the Linux epoll system calls.
  *
  * This unit provides constants and function prototypes for epoll_create,
  * epoll_ctl, and epoll_wait, as well as the eventfd function for waking
  * up epoll_wait. It is used by the epoll CrossSocket implementation.
  *
  * The definitions are based on the Linux man pages and the C header files.
  * For Delphi (non‑FPC) on Linux, the functions are linked directly.
}

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

{$IFDEF LINUX}
{$IFDEF DELPHI}

uses
  Posix.Base,
  Posix.StdDef,
  Posix.SysTypes,
  Posix.Signal;

const
  EPOLLIN  = $01; { The associated file is available for read(2) operations. }
  EPOLLPRI = $02; { There is urgent data available for read(2) operations. }
  EPOLLOUT = $04; { The associated file is available for write(2) operations. }
  EPOLLERR = $08; { Error condition happened on the associated file descriptor. }
  EPOLLHUP = $10; { Hang up happened on the associated file descriptor. }
  EPOLLONESHOT = $40000000; { Sets the One-Shot behaviour for the associated file descriptor. }
  EPOLLET  = $80000000; { Sets the Edge Triggered behaviour for the associated file descriptor. }

  { Valid opcodes ( "op" parameter ) to issue to epoll_ctl }
  EPOLL_CTL_ADD = 1;
  EPOLL_CTL_DEL = 2;
  EPOLL_CTL_MOD = 3;

type
  EPoll_Data = packed record
    case integer of
      0: (ptr: pointer);
      1: (fd: Integer);
      2: (u32: Cardinal);
      3: (u64: UInt64);
  end;
  TEPoll_Data =  Epoll_Data;
  PEPoll_Data = ^Epoll_Data;

  EPoll_Event = record
    Events: Cardinal;
    Data  : TEpoll_Data;
  end;

  TEPoll_Event =  Epoll_Event;
  PEpoll_Event = ^Epoll_Event;

{ open an epoll file descriptor }
function epoll_create(size: Integer): Integer; cdecl;
  external libc name 'epoll_create'

{ control interface for an epoll descriptor }
function epoll_ctl(epfd, op, fd: Integer; event: pepoll_event): Integer; cdecl;
  external libc name 'epoll_ctl'

{ wait for an I/O event on an epoll file descriptor }
function epoll_wait(epfd: Integer; events: pepoll_event; maxevents, timeout: Integer): Integer; cdecl;
  external libc name 'epoll_wait'

function eventfd(initval: Cardinal; flags: Integer): Integer; cdecl;
  external libc name 'eventfd'

{$ENDIF DELPHI}
{$ENDIF LINUX}

implementation

end.
 
