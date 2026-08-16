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
unit Z.FP.Net.CrossSocket;

{ *
  * CrossSocket – platform‑specific factory unit.
  * This unit selects the appropriate implementation (IOCP, epoll, or kqueue)
  * based on the target operating system, and exposes the concrete types.
  *
  * Usage:
  *   In your code, you can use the TCrossSocket type directly, which will be
  *   an alias for the correct platform class. Similarly, TCrossListen and
  *   TCrossConnection are aliases to the platform‑specific versions.
  *
  * Example:
  *   var
  *     server: TCrossSocket;
  *   begin
  *     server := TCrossSocket.Create(4);
  *     server.Listen('0.0.0.0', 8080);
  *   end;
}

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses
  Z.FP.Net.CrossSocket.Base,
  {$IF defined(MSWINDOWS)}
  Z.FP.Net.CrossSocket.Iocp
  {$ELSEIF defined(LINUX) or defined(ANDROID)}
  Z.FP.Net.CrossSocket.Epoll
  {$ELSEIF defined(BSD) or defined(MACOS) or defined(IOS)}
  Z.FP.Net.CrossSocket.Kqueue
  {$ENDIF};

type
  TCrossListen =
    {$IF defined(MSWINDOWS)}
    TIocpListen
    {$ELSEIF defined(LINUX) or defined(ANDROID)}
    TEpollListen
    {$ELSEIF defined(BSD) or defined(MACOS) or defined(IOS)}
    TKqueueListen
    {$ENDIF};

  TCrossConnection =
    {$IF defined(MSWINDOWS)}
    TIocpConnection
    {$ELSEIF defined(LINUX) or defined(ANDROID)}
    TEpollConnection
    {$ELSEIF defined(BSD) or defined(MACOS) or defined(IOS)}
    TKqueueConnection
    {$ENDIF};

  TCrossSocket =
    {$IF defined(MSWINDOWS)}
    TIocpCrossSocket
    {$ELSEIF defined(LINUX) or defined(ANDROID)}
    TEpollCrossSocket
    {$ELSEIF defined(BSD) or defined(MACOS) or defined(IOS)}
    TKqueueCrossSocket
    {$ENDIF};

implementation

end.
 
