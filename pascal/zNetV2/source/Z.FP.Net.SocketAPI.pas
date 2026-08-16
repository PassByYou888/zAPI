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
unit Z.FP.Net.SocketAPI;

{ *
  * SocketAPI – A unified, cross‑platform wrapper for socket system calls.
  *
  * This unit abstracts the differences between Windows Winsock2 and POSIX
  * sockets (Linux, macOS, BSD, etc.). It provides a class TSocketAPI with
  * static methods for common operations: socket creation, binding, connect,
  * send/recv, setsockopt, and address resolution (getaddrinfo).
  *
  * It also includes utilities for address formatting, non‑blocking mode,
  * keep‑alive, TCP_NODELAY, and more.
  *
  * The goal is to allow the rest of the framework to use a single API
  * without conditional compilation for every socket call.
  *
  * Example (create a TCP server socket, bind, listen):
  *   var
  *     s: TSocket;
  *   begin
  *     s := TSocketAPI.NewTcp;
  *     TSocketAPI.SetReUseAddr(s, True);
  *     TSocketAPI.Bind(s, addr, addrlen);
  *     TSocketAPI.Listen(s);
  *     // accept connections...
  *   end;
  *
  * Example (non‑blocking connect):
  *   var
  *     s: TSocket;
  *   begin
  *     s := TSocketAPI.NewTcp;
  *     TSocketAPI.SetNonBlock(s, True);
  *     if TSocketAPI.Connect(s, addr, addrlen) = 0 then
  *       // connected immediately
  *     else if GetLastError = EINPROGRESS then
  *       // waiting for connection completion
  *   end;
}

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses
  SysUtils, Z.Core, Z.PascalStrings, Z.UPascalStrings

  {$IFDEF MSWINDOWS}
  ,Windows
  ,Z.FP.Net.Winsock2
  ,Z.FP.Net.Wship6
  {$ENDIF MSWINDOWS}

  {$IFDEF DELPHI}
    {$IFDEF POSIX}
      ,Posix.Base
      ,Posix.UniStd
      ,Posix.SysSocket
      ,Posix.ArpaInet
      ,Posix.NetinetIn
      ,Posix.NetDB
      ,Posix.NetinetTCP
      ,Posix.Fcntl
      ,Posix.SysSelect
      ,Posix.StrOpts
      ,Posix.SysTime
      ,Posix.Errno
      {$IFDEF LINUX}
        {$IFNDEF ANDROID}
          ,Linuxapi.KernelIoctl
        {$ENDIF ANDROID}
      {$ENDIF LINUX}
    {$ENDIF POSIX}
  {$ELSE}

  {$IFDEF POSIX}
    ,BaseUnix
    ,netdb
    ,cNetDB
    ,Sockets
    ,termio
    {$IFDEF LINUX}
      ,Linux
    {$ENDIF LINUX}
  {$ENDIF POSIX}

  {$ENDIF DELPHI}
  ;

type
  TSocket = {$IFDEF MSWINDOWS}Z.FP.Net.Winsock2.TSocket{$ELSE}Integer{$ENDIF}; // Socket handle type (platform‑specific)

const
  SOCKET_ERROR         = -1;            // Return value indicating an error
  INVALID_SOCKET       = TSocket(-1);   // Invalid socket handle

  {$IF DEFINED(FPC) AND NOT DEFINED(MSWINDOWS)}
  NI_MAXHOST = 1025;  // Maximum length of a host name for getnameinfo
  NI_MAXSERV = 32;    // Maximum length of a service name

  {$IF DEFINED(FREEBSD)}
  NI_NOFQDN       = $00000001;
  NI_NUMERICHOST  = $00000002;
  NI_NAMEREQD     = $00000004;
  NI_NUMERICSERV  = $00000008;
  NI_DGRAM        = $00000010;
  NI_NUMERICSCOPE = $00000020;
  {$ELSE}
  NI_NUMERICHOST = 1;
  NI_NUMERICSERV = 2;
  NI_NOFQDN      = 4;
  NI_NAMEREQD    = 8;
  NI_DGRAM       = 16;
  {$ENDIF}

  {$IF DEFINED(BSD) OR DEFINED(FREEBSD) OR DEFINED(DRAGONFLY)}
  O_SHLOCK    =   $10;        { Open with shared file lock }
  O_EXLOCK    =   $20;        { Open with exclusive file lock }
  O_ASYNC     =   $40;        { Signal pgrp when data ready }
  O_FSYNC     =   $80;        { Synchronous writes }
  O_SYNC      =   $80;        { POSIX synonym for O_FSYNC }
  O_NOFOLLOW  =  $100;        { Don't follow symlinks }
  O_DIRECT    =$10000;        { Attempt to bypass buffer cache }
  {$ENDIF}

  {$IF DEFINED(LINUX) OR DEFINED(ANDROID)}
  {$IF DEFINED(CPUSPARC) OR DEFINED(CPUSPARC64)}
  O_APPEND  =          8;
  O_CREAT   =       $200;
  O_TRUNC   =       $400;
  O_EXCL    =       $800;
  O_SYNC    =      $2000;
  O_NONBLOCK =     $4000;
  O_NDELAY  =      O_NONBLOCK OR 4;
  O_NOCTTY  =      $8000;
  O_DIRECTORY =   $10000;
  O_NOFOLLOW =    $20000;
  O_DIRECT  =    $100000;
  {$ELSE : NOT (CPUSPARC OR CPUSPARC64)}
  {$IFDEF CPUMIPS}
  O_CREAT   =       $100;
  O_EXCL    =       $400;
  O_NOCTTY  =       $800;
  O_TRUNC   =       $200;
  O_APPEND  =         $8;
  O_NONBLOCK =       $80;
  O_NDELAY  =     O_NONBLOCK;
  O_SYNC    =        $10;
  O_DIRECT  =      $8000;
  O_DIRECTORY =   $10000;
  O_NOFOLLOW =    $20000;
  {$ELSE : NOT CPUMIPS}
  O_CREAT   =        $40;
  O_EXCL    =        $80;
  O_NOCTTY  =       $100;
  O_TRUNC   =       $200;
  O_APPEND  =       $400;
  O_NONBLOCK =      $800;
  O_NDELAY  =     O_NONBLOCK;
  O_SYNC    =      $1000;
  O_DIRECT  =      $4000;
  O_DIRECTORY =   $10000;
  O_NOFOLLOW =    $20000;
  {$ENDIF NOT CPUMIPS}
  {$ENDIF NOT (CPUSPARC OR CPUSPARC64)}
  {$ENDIF LINUX}

  {$ENDIF}

  {$IFDEF LINUX}
  SO_REUSEPORT = 15;   // Socket option for port reuse (Linux specific)
  {$ENDIF}

type
  {$IF DEFINED(FPC) and DEFINED(LINUX)}
  PAddrInfo = cNetDB.PAddrInfo;
  TAddrInfo = cNetDB.TAddrInfo;
  PPAddrInfo = cNetDB.PPAddrInfo;
  {$ENDIF}

  TRawSockAddrIn = packed record
    AddrLen: Integer;
    case Integer of
      0: (Addr: sockaddr_in);    // IPv4 address
      1: (Addr6: sockaddr_in6);  // IPv6 address
  end;

  {$IFDEF POSIX}
  {$IF DEFINED(FPC)}
  TRawAddrInfo = cNetDB.addrinfo;
  {$ELSE}
  TRawAddrInfo = addrinfo;
  {$ENDIF}
  {$ELSE}
  TRawAddrInfo = Z.FP.Net.Winsock2.{$IFDEF UNICODE}TAddrInfoW{$ELSE}TAddrInfo{$ENDIF};
  {$ENDIF}
  PRawAddrInfo = ^TRawAddrInfo;

  { *
    * TSocketAPI – Unified socket API class.
    * All methods are static and can be used without instantiation.
    * They handle platform differences internally.
  }
  TSocketAPI = class
  public
    /// <summary>
    ///   Create a new socket.
    /// </summary>
    class function NewSocket(const ADomain, AType, AProtocol: Integer): TSocket; static;

    /// <summary>
    ///   Create a TCP socket (AF_INET, SOCK_STREAM, IPPROTO_TCP).
    /// </summary>
    class function NewTcp: TSocket; static;

    /// <summary>
    ///   Create a UDP socket (AF_INET, SOCK_DGRAM, IPPROTO_UDP).
    /// </summary>
    class function NewUdp: TSocket; static;

    /// <summary>
    ///   Close a socket.
    /// </summary>
    class function CloseSocket(const ASocket: TSocket): Integer; static;

    /// <summary>
    ///   Shutdown socket operations (SD_RECEIVE=0, SD_SEND=1, SD_BOTH=2).
    /// </summary>
    class function Shutdown(const ASocket: TSocket; const AHow: Integer = 2): Integer; static;

    /// <summary>
    ///   Accept an incoming connection and allocate a new socket.
    /// </summary>
    class function Accept(const ASocket: TSocket; const Addr: PSockAddr; const AddrLen: PInteger): TSocket; static;

    /// <summary>
    ///   Bind a socket to a local address and port (supports IPv6).
    /// </summary>
    class function Bind(const ASocket: TSocket; const Addr: PSockAddr; const AddrLen: Integer): Integer; static;

    /// <summary>
    ///   Connect to a remote host (supports IPv6).
    /// </summary>
    class function Connect(const ASocket: TSocket; const Addr: PSockAddr; const AddrLen: Integer): Integer; static;

    /// <summary>
    ///   Start listening for incoming connections.
    /// </summary>
    class function Listen(const ASocket: TSocket; const backlog: Integer = SOMAXCONN): Integer; overload; static;

    /// <summary>
    ///   Receive data from a connected socket.
    /// </summary>
    class function Recv(const ASocket: TSocket; var Buf; const len: Integer; const flags: Integer = 0): Integer; static;

    /// <summary>
    ///   Send data over a connected socket.
    /// </summary>
    class function Send(const ASocket: TSocket; const Buf; const len: Integer; const flags: Integer = 0): Integer; static;

    /// <summary>
    ///   Receive data from a specific address (UDP).
    /// </summary>
    class function RecvFrom(const ASocket: TSocket; const Addr: PSockAddr;
      var AddrLen: Integer; var Buf; const len: Integer; const flags: Integer = 0): Integer; static;

    /// <summary>
    ///   Send data to a specific address (UDP).
    /// </summary>
    class function SendTo(const ASocket: TSocket; const Addr: PSockAddr;
      const AddrLen: Integer; const Buf; const len: Integer; const flags: Integer = 0): Integer; static;

    /// <summary>
    ///   Get the remote peer address of a socket.
    /// </summary>
    class function GetPeerName(const ASocket: TSocket; const Addr: PSockAddr;
      var AddrLen: Integer): Integer; static;

    /// <summary>
    ///   Get the local address of a socket.
    /// </summary>
    class function GetSockName(const ASocket: TSocket; const Addr: PSockAddr;
      var AddrLen: Integer): Integer; static;

    /// <summary>
    ///   Get a socket option.
    /// </summary>
    class function GetSockOpt(const ASocket: TSocket; const ALevel, AOptionName: Integer;
       var AOptionValue; var AOptionLen: Integer): Integer; overload; static;

    /// <summary>
    ///   Get a socket option (generic type version).
    /// </summary>
    class function GetSockOpt<T>(const ASocket: TSocket; const ALevel, AOptionName: Integer;
       var AOptionValue: T): Integer; overload; static;

    /// <summary>
    ///   Set a socket option (pointer version).
    /// </summary>
    class function SetSockOpt(const ASocket: TSocket; const ALevel, AOptionName: Integer;
      const AOptionValue: Pointer; AOptionLen: Integer): Integer; overload; static;

    /// <summary>
    ///   Set a socket option (value version).
    /// </summary>
    class function SetSockOpt(const ASocket: TSocket; const ALevel, AOptionName: Integer;
      const AOptionValue; AOptionLen: Integer): Integer; overload; static;

    /// <summary>
    ///   Set a socket option (generic type version).
    /// </summary>
    class function SetSockOpt<T>(const ASocket: TSocket; const ALevel, AOptionName: Integer;
      const AOptionValue: T): Integer; overload; static;

    /// <summary>
    ///   Get the current socket error code (SO_ERROR).
    /// </summary>
    class function GetError(const ASocket: TSocket): Integer; static;

    /// <summary>
    ///   Set or clear non‑blocking mode on a socket.
    /// </summary>
    class function SetNonBlock(const ASocket: TSocket; const ANonBlock: Boolean = True): Integer; static;

    /// <summary>
    ///   Enable or disable address reuse (SO_REUSEADDR).
    /// </summary>
    class function SetReUseAddr(const ASocket: TSocket; const AReUseAddr: Boolean = True): Integer; static;

    /// <summary>
    ///   Enable or disable port reuse (SO_REUSEPORT) – POSIX only.
    /// </summary>
    class function SetReUsePort(const ASocket: TSocket; const AReUsePort: Boolean = True): Integer; static;

    /// <summary>
    ///   Configure TCP keep‑alive parameters (idle seconds, interval, count).
    /// </summary>
    class function SetKeepAlive(const ASocket: TSocket; const AIdleSeconds, AInterval, ACount: Integer): Integer; static;

    /// <summary>
    ///   Enable or disable TCP_NODELAY (Nagle algorithm).
    /// </summary>
    class function SetTcpNoDelay(const ASocket: TSocket; const ANoDelay: Boolean = True): Integer; static;

    /// <summary>
    ///   Set the send buffer size (SO_SNDBUF).
    /// </summary>
    class function SetSndBuf(const ASocket: TSocket; const ABufSize: Integer): Integer; static;

    /// <summary>
    ///   Set the receive buffer size (SO_RCVBUF).
    /// </summary>
    class function SetRcvBuf(const ASocket: TSocket; const ABufSize: Integer): Integer; static;

    /// <summary>
    ///   Set the linger option (time to wait for unsent data on close).
    /// </summary>
    class function SetLinger(const ASocket: TSocket; const AOnOff: Boolean; const ALinger: Integer): Integer; static;

    /// <summary>
    ///   Enable or disable SO_BROADCAST.
    /// </summary>
    class function SetBroadcast(const ASocket: TSocket; const ABroadcast: Boolean = True): Integer; static;

    /// <summary>
    ///   Set the receive timeout (SO_RCVTIMEO) in milliseconds.
    /// </summary>
    class function SetRecvTimeout(const ASocket: TSocket; const ATimeout: Cardinal): Integer; static;

    /// <summary>
    ///   Set the send timeout (SO_SNDTIMEO) in milliseconds.
    /// </summary>
    class function SetSendTimeout(const ASocket: TSocket; const ATimeout: Cardinal): Integer; static;

    /// <summary>
    ///   Check if the socket is readable (data available to receive).
    ///   ATimeout < 0 blocks indefinitely, =0 immediate return, >0 waits for timeout ms.
    /// </summary>
    class function Readable(const ASocket: TSocket; const ATimeout: Integer): Integer; static;

    /// <summary>
    ///   Check if the socket is writable (send buffer space available).
    ///   ATimeout < 0 blocks indefinitely, =0 immediate return, >0 waits for timeout ms.
    /// </summary>
    class function Writeable(const ASocket: TSocket; const ATimeout: Integer): Integer; static;

    /// <summary>
    ///   Get the number of bytes received and available to read (FIONREAD).
    /// </summary>
    class function RecvdCount(const ASocket: TSocket): Integer; static;

    /// <summary>
    ///   Strip brackets and whitespace from an address SystemString (for IPv6).
    /// </summary>
    class function PureAddr(const AHostName: SystemString): SystemString; static;

    /// <summary>
    ///   Resolve address info (getaddrinfo) for a host/service name (IPv6 capable).
    /// </summary>
    class function GetAddrInfo(const AHostName, AServiceName: SystemString;
      const AHints: TRawAddrInfo): PRawAddrInfo; overload; static;

    /// <summary>
    ///   Resolve address info with a port number (converted to service SystemString).
    /// </summary>
    class function GetAddrInfo(const AHostName: SystemString; const APort: Word;
      const AHints: TRawAddrInfo): PRawAddrInfo; overload; static;

    /// <summary>
    ///   Free the address info structure returned by GetAddrInfo.
    /// </summary>
    class procedure FreeAddrInfo(const ARawAddrInfo: PRawAddrInfo); static;

    /// <summary>
    ///   Extract IP address and port from a sockaddr structure (IPv6 capable).
    /// </summary>
    class procedure ExtractAddrInfo(const AAddr: PSockAddr; const AAddrLen: Integer;
      var AIP: SystemString; var APort: Word); static;

    /// <summary>
    ///   Resolve a host name to an IP address SystemString (IPv6 capable).
    /// </summary>
    class function GetIpAddrByHost(const AHost: SystemString): SystemString; static;

    /// <summary>
    ///   Check if a socket handle is valid (not INVALID_SOCKET).
    /// </summary>
    class function IsValidSocket(const ASocket: TSocket): Boolean; static;

    /// <summary>
    ///   Normalize a host address (add brackets to IPv6 if missing).
    /// </summary>
    class function StandardAddr(const AHost: SystemString): SystemString; static;
  end;

implementation

{$IF DEFINED(FPC) AND NOT DEFINED(MSWINDOWS)}
{$LINKLIB c}
function getaddrinfo(hostname, servname: MarshaledAString;
  hints: PAddrInfo; res: PPAddrInfo): Integer; cdecl; external;
procedure freeaddrinfo(ai: PRawAddrInfo); cdecl; external;

function getnameinfo(sa: PSockAddr; salen: TSockLen; host: PAnsiChar; hostlen: TSize;
  serv: PAnsiChar; servlen: TSize; flags: cInt): cInt; cdecl; external;
{$ENDIF}

{ *
  * NewSocket – create a socket with the given domain, type and protocol.
  * On Windows, it uses Winsock2.socket; on POSIX, it uses fpSocket (FPC) or socket (Delphi).
  * Raises an exception if creation fails (in DEBUG mode) or returns INVALID_SOCKET.
}
class function TSocketAPI.NewSocket(const ADomain, AType,
  AProtocol: Integer): TSocket;
begin
  {$IFDEF DELPHI}
  Result :=
    {$IFDEF MSWINDOWS}
    Z.FP.Net.Winsock2.
    {$ELSE}
    Posix.SysSocket.
    {$ENDIF MSWINDOWS}
    socket(ADomain, AType, AProtocol);
  {$ELSE DELPHI}
  Result :=
    {$IFDEF MSWINDOWS}
    Z.FP.Net.Winsock2.socket
    {$ELSE}
    Sockets.fpSocket
    {$ENDIF MSWINDOWS}
    (ADomain, AType, AProtocol);
  {$ENDIF DELPHI}

  {$IFDEF DEBUG}
  if not IsValidSocket(Result) then
    RaiseLastOSError;
  {$ENDIF}
end;

{ *
  * NewTcp – convenience wrapper to create a TCP socket (IPv4).
}
class function TSocketAPI.NewTcp: TSocket;
begin
  Result := TSocketAPI.NewSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
end;

{ *
  * NewUdp – convenience wrapper to create a UDP socket (IPv4).
}
class function TSocketAPI.NewUdp: TSocket;
begin
  Result := TSocketAPI.NewSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
end;

{ *
  * PureAddr – removes leading/trailing brackets and whitespace from an address.
  * This is useful for stripping the '[' and ']' from IPv6 addresses.
}
class function TSocketAPI.PureAddr(const AHostName: SystemString): SystemString;
begin
  Result := AHostName.Trim;
  Result := Result.TrimLeft(['[']);
  Result := Result.TrimRight([']']);
end;

{ *
  * Readable – uses select() to check if the socket has data available for reading.
  * Returns >0 if readable, 0 if timeout, -1 on error.
}
class function TSocketAPI.Readable(const ASocket: TSocket; const ATimeout: Integer): Integer;
var
  {$IFDEF MSWINDOWS}
  LFDSet: TFDSet;
  LTime_val: TTimeval;
  {$ELSE}
  LFDSet: {$IFDEF DELPHI}fd_set{$ELSE}TFDSet{$ENDIF};
  LTime_val: timeval;
  {$ENDIF}
  P: PTimeVal;
begin
  if (ATimeout >= 0) then
  begin
    LTime_val.tv_sec := ATimeout div 1000;
    LTime_val.tv_usec :=  1000 * (ATimeout mod 1000);
    P := @LTime_val;
  end else
    P := nil;

  {$IFDEF MSWINDOWS}
  FD_ZERO(LFDSet);
  FD_SET(ASocket, LFDSet);
  Result := Z.FP.Net.Winsock2.select(0, @LFDSet, nil, nil, P);
  {$ELSE MSWINDOWS}
  {$IFDEF DELPHI}
  FD_ZERO(LFDSet);
  _FD_SET(ASocket, LFDSet);
  Result := Posix.SysSelect.select(0, @LFDSet, nil, nil, P);
  {$ELSE DELPHI}
  fpFD_ZERO(LFDSet);
  fpFD_SET(ASocket, LFDSet);
  Result := fpSelect(0, @LFDSet, nil, nil, P);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

{ *
  * Recv – reads data from a connected socket.
}
class function TSocketAPI.Recv(const ASocket: TSocket; var Buf; const len,
  flags: Integer): Integer;
begin
  Result :=
    {$IFDEF DELPHI}
    {$IFDEF MSWINDOWS}
    Z.FP.Net.Winsock2.
    {$ELSE}
    Posix.SysSocket.
    {$ENDIF}
    recv(ASocket, Buf, len, flags);
    {$ELSE DELPHI}
    {$IFDEF MSWINDOWS}
    Z.FP.Net.Winsock2.recv(ASocket, Buf, len, flags);
    {$ELSE}
    fprecv(ASocket, @Buf, len, flags);
    {$ENDIF}
    {$ENDIF DELPHI}
end;

{ *
  * RecvdCount – uses ioctl(FIONREAD) to get the number of pending bytes.
}
class function TSocketAPI.RecvdCount(const ASocket: TSocket): Integer;
{$IF DEFINED(MSWINDOWS) OR DEFINED(FPC)}
var
  LTemp : Cardinal;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  if ioctlsocket(ASocket, FIONREAD, LTemp) = SOCKET_ERROR then
    Result := -1
  else
    Result := LTemp;
  {$ELSE}
  {$IFDEF DELPHI}
   Result := ioctl(ASocket, FIONREAD);
  {$ELSE}
  if fpioctl(ASocket, FIONREAD, @LTemp) = SOCKET_ERROR then
    Result := -1
  else
    Result := LTemp;
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

{ *
  * RecvFrom – receives data and stores the sender's address (UDP).
}
class function TSocketAPI.RecvFrom(const ASocket: TSocket; const Addr: PSockAddr;
  var AddrLen: Integer; var Buf; const len, flags: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Z.FP.Net.Winsock2.recvfrom(ASocket, Buf, len, flags, Addr, @AddrLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.recvfrom(ASocket, Buf, len, flags, Addr^, socklen_t(AddrLen));
  {$ELSE}
  Result := fprecvfrom(ASocket, @Buf, len, flags, Addr, @AddrLen);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

{ *
  * Accept – accepts a new connection, returns the new socket.
}
class function TSocketAPI.Accept(const ASocket: TSocket; const Addr: PSockAddr;
  const AddrLen: PInteger): TSocket;
begin
  {$IFDEF MSWINDOWS}
  Result := Z.FP.Net.Winsock2.accept(ASocket, Addr, AddrLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.accept(ASocket, Addr^, socklen_t(AddrLen^));
  {$ELSE}
  Result := fpaccept(ASocket, Addr, psocklen(AddrLen));
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

{ *
  * Bind – binds the socket to the given address.
}
class function TSocketAPI.Bind(const ASocket: TSocket; const Addr: PSockAddr;
  const AddrLen: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Z.FP.Net.Winsock2.bind(ASocket, Addr, AddrLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.bind(ASocket, Addr^, AddrLen);
  {$ELSE}
  Result := fpbind(ASocket, Addr, AddrLen);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

{ *
  * CloseSocket – closes the socket handle.
}
class function TSocketAPI.CloseSocket(const ASocket: TSocket): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Z.FP.Net.Winsock2.closesocket(ASocket);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.UniStd.__close(ASocket);
  {$ELSE}
  Result := Sockets.CloseSocket(ASocket);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

{ *
  * Shutdown – disables send/receive on the socket.
}
class function TSocketAPI.Shutdown(const ASocket: TSocket; const AHow: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Z.FP.Net.Winsock2.shutdown(ASocket, AHow);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.shutdown(ASocket, AHow);
  {$ELSE}
  Result := fpshutdown(ASocket, AHow);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

{ *
  * StandardAddr – ensures IPv6 addresses are enclosed in brackets.
}
class function TSocketAPI.StandardAddr(const AHost: SystemString): SystemString;
var
  LHost: SystemString;
begin
  if (AHost = '') then Exit('');

  LHost := AHost.Trim.ToLower;

  // IPv6
  if LHost.Contains(':') then
  begin
    if not LHost.StartsWith('[', True) then
      LHost := '[' + LHost;
    if not LHost.EndsWith(']', True) then
      LHost := LHost + ']';
  end;

  Result := LHost;
end;

{ *
  * Connect – initiates a connection to the remote address (non‑blocking if socket is non‑blocking).
}
class function TSocketAPI.Connect(const ASocket: TSocket; const Addr: PSockAddr;
  const AddrLen: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Z.FP.Net.Winsock2.connect(ASocket, Addr, AddrLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.connect(ASocket, Addr^, AddrLen);
  {$ELSE}
  Result := fpconnect(ASocket, Addr, AddrLen);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}

  {$IFDEF DEBUG}
//  if (Result <> 0) and (GetLastError <> EINPROGRESS) then
//    RaiseLastOSError;
  {$ENDIF}
end;

{ *
  * GetAddrInfo – resolves host/service names to address info structures.
}
class function TSocketAPI.GetAddrInfo(const AHostName, AServiceName: SystemString;
  const AHints: TRawAddrInfo): PRawAddrInfo;
var
  LHostName: SystemString;
  LHost, LService: Pointer;
  LRet: Integer;
  LAddrInfo: PRawAddrInfo;
begin
  Result := nil;

  LHostName := PureAddr(AHostName);

  {$IFDEF MSWINDOWS}
    if (LHostName <> '') then
      LHost := TPascalString(LHostName).{$IFDEF UNICODE}BuildWideChar{$ELSE}BuildAnsiChar{$ENDIF}
    else
      LHost := nil;
    if (AServiceName <> '') then
      LService := TPascalString(AServiceName).{$IFDEF UNICODE}BuildWideChar{$ELSE}BuildAnsiChar{$ENDIF}
    else
      LService := nil;
    LRet := Z.FP.Net.Wship6.getaddrinfo(LHost, LService, @AHints, @LAddrInfo);
    TPascalString.{$IFDEF UNICODE}FreeWideChar{$ELSE}FreeAnsiChar{$ENDIF}(LHost);
    TPascalString.{$IFDEF UNICODE}FreeWideChar{$ELSE}FreeAnsiChar{$ENDIF}(LService);
  {$ELSE}
    if (LHostName <> '') then
      LHost := TPascalString(LHostName).BuildAnsiChar
    else
      LHost := nil;
    if (AServiceName <> '') then
      LService := TPascalString(AServiceName).BuildAnsiChar
    else
      LService := nil;
    {$IFDEF DELPHI}
      LRet := Posix.NetDB.getaddrinfo(LHost, LService, AHints, Paddrinfo(LAddrInfo));
    {$ELSE}
      //LRet := cNetDB.getaddrinfo(LHost, LService, @AHints, @LAddrInfo);
      LRet := Z.FP.Net.SocketAPI.getaddrinfo(LHost, LService, @AHints, @LAddrInfo);
    {$ENDIF DELPHI}
    TPascalString.FreeAnsiChar(LHost);
    TPascalString.FreeAnsiChar(LService);
  {$ENDIF MSWINDOWS}


  if (LRet <> 0) then Exit;

  Result := LAddrInfo;
end;

{ *
  * GetAddrInfo – overload with port as Word.
}
class function TSocketAPI.GetAddrInfo(const AHostName: SystemString; const APort: Word;
  const AHints: TRawAddrInfo): PRawAddrInfo;
begin
  Result := GetAddrInfo(AHostName, APort.ToString, AHints);
end;

{ *
  * GetError – retrieves the SO_ERROR socket option.
}
class function TSocketAPI.GetError(const ASocket: TSocket): Integer;
var
  LRet, LErrLen: Integer;
begin
  LErrLen := SizeOf(Integer);
  LRet := TSocketAPI.GetSockOpt(ASocket, SOL_SOCKET, SO_ERROR, Result, LErrLen);
  if (LRet <> 0) then
    Result := LRet;
end;

{ *
  * FreeAddrInfo – frees memory allocated by getaddrinfo.
}
class procedure TSocketAPI.FreeAddrInfo(const ARawAddrInfo: PRawAddrInfo);
begin
  {$IFDEF MSWINDOWS}
    {$IFDEF DELPHI}
    Z.FP.Net.Wship6.freeaddrinfo(PAddrInfoW(ARawAddrInfo));
    {$ELSE DELPHI}
    Z.FP.Net.Wship6.freeaddrinfo(PAddrInfo(ARawAddrInfo));
    {$ENDIF DELPHI}
  {$ELSE}
  {$IFDEF DELPHI}
  Posix.NetDB.freeaddrinfo(ARawAddrInfo^);
  {$ELSE}
  //cNetDB.freeaddrinfo(ARawAddrInfo);
  Z.FP.Net.SocketAPI.freeaddrinfo(ARawAddrInfo);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

{ *
  * ExtractAddrInfo – extracts IP and port from a sockaddr using getnameinfo.
}
class procedure TSocketAPI.ExtractAddrInfo(const AAddr: PSockAddr;
  const AAddrLen: Integer; var AIP: SystemString; var APort: Word);
var
  LIP, LServInfo: Pointer;
begin
  {$IFDEF MSWINDOWS}
    LIP := TPascalString.{$IFDEF UNICODE}AllocWideChar{$ELSE}AllocAnsiChar{$ENDIF}(NI_MAXHOST);
    LServInfo := TPascalString.{$IFDEF UNICODE}AllocWideChar{$ELSE}AllocAnsiChar{$ENDIF}(NI_MAXSERV);

    getnameinfo(AAddr, AAddrLen, LIP, NI_MAXHOST, LServInfo, NI_MAXSERV, NI_NUMERICHOST or NI_NUMERICSERV);

    AIP := TPascalString.{$IFDEF UNICODE}ReadWideCharTo{$ELSE}ReadAnsiCharTo{$ENDIF}(LIP);
    APort := StrToInt(TPascalString.{$IFDEF UNICODE}ReadWideCharTo{$ELSE}ReadAnsiCharTo{$ENDIF}(LServInfo));
    TPascalString.FreeWideChar(LIP);
    TPascalString.FreeWideChar(LServInfo);
  {$ELSE}
    LIP := TPascalString.AllocAnsiChar(NI_MAXHOST);
    LServInfo := TPascalString.AllocAnsiChar(NI_MAXSERV);

    {$IFDEF DELPHI}
      getnameinfo(AAddr^, AAddrLen, LIP, NI_MAXHOST, LServInfo, NI_MAXSERV, NI_NUMERICHOST or NI_NUMERICSERV);
    {$ELSE}
      getnameinfo(AAddr, AAddrLen, LIP, NI_MAXHOST, LServInfo, NI_MAXSERV, NI_NUMERICHOST or NI_NUMERICSERV);
    {$ENDIF DELPHI}

    AIP := TPascalString.ReadAnsiCharTo(LIP);
    APort := StrToInt(TPascalString.ReadAnsiCharTo(LServInfo));
    TPascalString.FreeAnsiChar(LIP);
    TPascalString.FreeAnsiChar(LServInfo);
  {$ENDIF MSWINDOWS}
end;

{ *
  * GetIpAddrByHost – resolves a hostname to its IP address SystemString (first returned).
}
class function TSocketAPI.GetIpAddrByHost(const AHost: SystemString): SystemString;
var
  LHints: TRawAddrInfo;
  LAddrInfo: PRawAddrInfo;
  LPort: Word;
begin
  FillChar(LHints, SizeOf(TRawAddrInfo), 0);
  LAddrInfo := GetAddrInfo(AHost, '', LHints);
  if (LAddrInfo = nil) then Exit('');
  ExtractAddrInfo(LAddrInfo.ai_addr, LAddrInfo.ai_addrlen, Result, LPort);
  FreeAddrInfo(LAddrInfo);
end;

{ *
  * GetPeerName – gets the remote address of the socket.
}
class function TSocketAPI.GetPeerName(const ASocket: TSocket; const Addr: PSockAddr;
  var AddrLen: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Z.FP.Net.Winsock2.getpeername(ASocket, Addr, AddrLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.getpeername(ASocket, Addr^, socklen_t(AddrLen));
  {$ELSE}
  Result := fpgetpeername(ASocket, Addr, @AddrLen);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

{ *
  * GetSockName – gets the local address of the socket.
}
class function TSocketAPI.GetSockName(const ASocket: TSocket; const Addr: PSockAddr;
  var AddrLen: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Z.FP.Net.Winsock2.getsockname(ASocket, Addr, AddrLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.getsockname(ASocket, Addr^, socklen_t(AddrLen));
  {$ELSE}
  Result := fpgetsockname(ASocket, Addr, @AddrLen);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

{ *
  * GetSockOpt – retrieves a socket option (value + length).
}
class function TSocketAPI.GetSockOpt(const ASocket: TSocket; const ALevel, AOptionName: Integer;
  var AOptionValue; var AOptionLen: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Z.FP.Net.Winsock2.getsockopt(ASocket, ALevel, AOptionName, PAnsiChar(@AOptionValue), AOptionLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.getsockopt(ASocket, ALevel, AOptionName, AOptionValue, socklen_t(AOptionLen));
  {$ELSE}
  Result := fpgetsockopt(ASocket, ALevel, AOptionName, @AOptionValue, @AOptionLen);
  {$ENDIF DELPHI}
  {$ENDIF}
end;

{ *
  * GetSockOpt<T> – generic version that automatically supplies the length.
}
class function TSocketAPI.GetSockOpt<T>(const ASocket: TSocket; const ALevel,
  AOptionName: Integer; var AOptionValue: T): Integer;
var
  LOptionLen: Integer;
begin
  Result := GetSockOpt(ASocket, ALevel, AOptionName, AOptionValue, LOptionLen);
end;

{ *
  * IsValidSocket – returns True if the handle is not INVALID_SOCKET.
}
class function TSocketAPI.IsValidSocket(const ASocket: TSocket): Boolean;
begin
  Result := (ASocket <> INVALID_SOCKET);
end;

{ *
  * Listen – puts the socket into listening mode.
}
class function TSocketAPI.Listen(const ASocket: TSocket; const backlog: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Z.FP.Net.Winsock2.listen(ASocket, backlog);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.listen(ASocket, backlog);
  {$ELSE}
  Result := fplisten(ASocket, backlog);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}

  {$IFDEF DEBUG}
//  if (Result <> 0) then
//    RaiseLastOSError;
  {$ENDIF}
end;

{ *
  * Send – sends data over a connected socket.
}
class function TSocketAPI.Send(const ASocket: TSocket; const Buf; const len,
  flags: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Z.FP.Net.Winsock2.send(ASocket, Buf, len, flags);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.send(ASocket, Buf, len, flags);
  {$ELSE}
  Result := fpsend(ASocket, @Buf, len, flags);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

{ *
  * SendTo – sends data to a specific address (UDP).
}
class function TSocketAPI.SendTo(const ASocket: TSocket; const Addr: PSockAddr;
  const AddrLen: Integer; const Buf; const len, flags: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Z.FP.Net.Winsock2.sendto(ASocket, Buf, len, flags, Addr, AddrLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.sendto(ASocket, Buf, len, flags, Addr^, AddrLen);
  {$ELSE}
  Result := fpsendto(ASocket, @Buf, len, flags, Addr, AddrLen);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

{ *
  * SetBroadcast – enables or disables SO_BROADCAST.
}
class function TSocketAPI.SetBroadcast(const ASocket: TSocket;
  const ABroadcast: Boolean): Integer;
var
  LOptVal: Integer;
begin
  if ABroadcast then
    LOptVal := 1
  else
    LOptVal := 0;
  Result := TSocketAPI.SetSockOpt(ASocket, SOL_SOCKET, SO_BROADCAST, LOptVal, SizeOf(Integer));
end;

{ *
  * SetKeepAlive – configures TCP keep‑alive parameters.
  * Windows uses WSAIoctl with SIO_KEEPALIVE_VALS; macOS uses TCP_KEEPALIVE;
  * Linux/Android use TCP_KEEPIDLE, TCP_KEEPINTVL, TCP_KEEPCNT.
}
class function TSocketAPI.SetKeepAlive(const ASocket: TSocket; const AIdleSeconds,
  AInterval, ACount: Integer): Integer;
var
  LOptVal: Integer;
  {$IFDEF MSWINDOWS}
  LKeepAlive: tcp_keepalive;
  LBytes: Cardinal;
  {$ENDIF MSWINDOWS}
begin
  LOptVal := 1;
  Result := SetSockOpt(ASocket, SOL_SOCKET, SO_KEEPALIVE, LOptVal, SizeOf(Integer));
  if (Result < 0) then Exit;

  {$IF defined(MSWINDOWS)}
  // Windows: retry count is fixed at 3, cannot be changed.
  LKeepAlive.onoff := 1;
  LKeepAlive.keepalivetime := AIdleSeconds * 1000;
  LKeepAlive.keepaliveinterval := AInterval * 1000;
  LBytes := 0;
  Result := WSAIoctl(ASocket, SIO_KEEPALIVE_VALS, @LKeepAlive, SizeOf(tcp_keepalive),
    nil, 0, @LBytes, nil, nil);
  {$ELSEIF defined(MACOS)}
  // macOS: TCP_KEEPALIVE is equivalent to Linux's TCP_KEEPIDLE.
  // TCP_KEEPINTVL and TCP_KEEPCNT are not supported.
  Result := SetSockOpt(ASocket, IPPROTO_TCP, TCP_KEEPALIVE, AIdleSeconds, SizeOf(Integer));
  {$ELSEIF defined(LINUX) or defined(ANDROID)}
  Result := SetSockOpt(ASocket, IPPROTO_TCP, TCP_KEEPIDLE, AIdleSeconds, SizeOf(Integer));
  if (Result < 0) then Exit;

  Result := SetSockOpt(ASocket, IPPROTO_TCP, TCP_KEEPINTVL, AInterval, SizeOf(Integer));
  if (Result < 0) then Exit;

  Result := SetSockOpt(ASocket, IPPROTO_TCP, TCP_KEEPCNT, ACount, SizeOf(Integer));
  if (Result < 0) then Exit;
  {$ENDIF}
end;

{ *
  * SetLinger – sets the linger option (SO_LINGER).
}
class function TSocketAPI.SetLinger(const ASocket: TSocket;
  const AOnOff: Boolean; const ALinger: Integer): Integer;
var
  LLinger: linger;
begin
  if AOnOff then
    LLinger.l_onoff := 1
  else
    LLinger.l_onoff := 0;
  LLinger.l_linger := ALinger;
  Result := SetSockOpt(ASocket, SOL_SOCKET, SO_LINGER, LLinger, SizeOf(linger));
end;

{ *
  * SetNonBlock – sets or clears non‑blocking mode.
  * Windows: ioctlsocket with FIONBIO; POSIX: fcntl F_SETFL.
}
class function TSocketAPI.SetNonBlock(const ASocket: TSocket;
  const ANonBlock: Boolean): Integer;
var
  LFlag: Cardinal;
begin
  {$IFDEF MSWINDOWS}
  if ANonBlock then
    LFlag := 1
  else
    LFlag := 0;
  Result := ioctlsocket(ASocket, FIONBIO, LFlag);
  {$ELSE}
  {$IFDEF DELPHI}
  LFlag := fcntl(ASocket, F_GETFL);
  if ANonBlock then
    LFlag := LFlag and not O_SYNC or O_NONBLOCK
  else
    LFlag := LFlag and not O_NONBLOCK or O_SYNC;
  Result := fcntl(ASocket, F_SETFL, LFlag);
  {$ELSE}
  LFlag := fpfcntl(ASocket, F_GETFL);
  if ANonBlock then
    LFlag := LFlag and not O_SYNC or O_NONBLOCK
  else
    LFlag := LFlag and not O_NONBLOCK or O_SYNC;
  Result := fpfcntl(ASocket, F_SETFL, LFlag);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

{ *
  * SetReUseAddr – enables/disables SO_REUSEADDR.
}
class function TSocketAPI.SetReUseAddr(const ASocket: TSocket;
  const AReUseAddr: Boolean): Integer;
var
  LOptVal: Integer;
begin
  if AReUseAddr then
    LOptVal := 1
  else
    LOptVal := 0;
  Result := TSocketAPI.SetSockOpt(ASocket, SOL_SOCKET, SO_REUSEADDR, LOptVal, SizeOf(Integer));
end;

{ *
  * SetReUsePort – enables/disables SO_REUSEPORT (Linux/BSD only).
}
class function TSocketAPI.SetReUsePort(const ASocket: TSocket;
  const AReUsePort: Boolean): Integer;
{$IFDEF LINUX}
var
  LOptVal: Integer;
begin
  if AReUsePort then
    LOptVal := 1
  else
    LOptVal := 0;
  Result := TSocketAPI.SetSockOpt(ASocket, SOL_SOCKET, SO_REUSEPORT, LOptVal, SizeOf(Integer));
end;
{$else}
begin
  Result := -1;
end;
{$ENDIF}

{ *
  * SetRcvBuf – sets the receive buffer size.
}
class function TSocketAPI.SetRcvBuf(const ASocket: TSocket;
  const ABufSize: Integer): Integer;
begin
  Result := TSocketAPI.SetSockOpt(ASocket, SOL_SOCKET, SO_RCVBUF, ABufSize, SizeOf(Integer));
end;

{ *
  * SetRecvTimeout – sets the receive timeout (SO_RCVTIMEO).
}
class function TSocketAPI.SetRecvTimeout(const ASocket: TSocket;
  const ATimeout: Cardinal): Integer;
begin
  Result := SetSockOpt(ASocket,
    SOL_SOCKET, SO_RCVTIMEO, ATimeout, SizeOf(Cardinal));
end;

{ *
  * SetSendTimeout – sets the send timeout (SO_SNDTIMEO).
}
class function TSocketAPI.SetSendTimeout(const ASocket: TSocket;
  const ATimeout: Cardinal): Integer;
begin
  Result := TSocketAPI.SetSockOpt(ASocket,
    SOL_SOCKET, SO_SNDTIMEO, ATimeout, SizeOf(Cardinal));
end;

{ *
  * SetSndBuf – sets the send buffer size.
}
class function TSocketAPI.SetSndBuf(const ASocket: TSocket;
  const ABufSize: Integer): Integer;
begin
  Result := TSocketAPI.SetSockOpt(ASocket, SOL_SOCKET, SO_SNDBUF, ABufSize, SizeOf(Integer));
end;

{ *
  * SetSockOpt (pointer version) – sets a socket option.
}
class function TSocketAPI.SetSockOpt(const ASocket: TSocket; const ALevel,
  AOptionName: Integer; const AOptionValue: Pointer;
  AOptionLen: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Z.FP.Net.Winsock2.setsockopt(ASocket, ALevel, AOptionName, AOptionValue, AOptionLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.setsockopt(ASocket, ALevel, AOptionName, AOptionValue^, Cardinal(AOptionLen));
  {$ELSE}
  Result := fpsetsockopt(ASocket, ALevel, AOptionName, AOptionValue, Cardinal(AOptionLen));
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

{ *
  * SetSockOpt (value version) – sets a socket option by value.
}
class function TSocketAPI.SetSockOpt(const ASocket: TSocket; const ALevel,
  AOptionName: Integer; const AOptionValue; AOptionLen: Integer): Integer;
begin
  Result := SetSockOpt(ASocket, ALevel, AOptionName, @AOptionValue, AOptionLen);
end;

{ *
  * SetSockOpt<T> – generic version that automatically supplies the length.
}
class function TSocketAPI.SetSockOpt<T>(const ASocket: TSocket; const ALevel,
  AOptionName: Integer; const AOptionValue: T): Integer;
begin
  Result := SetSockOpt(ASocket, ALevel, AOptionName, AOptionValue, SizeOf(T));
end;

{ *
  * SetTcpNoDelay – enables/disables TCP_NODELAY.
}
class function TSocketAPI.SetTcpNoDelay(const ASocket: TSocket;
  const ANoDelay: Boolean): Integer;
var
  LOptVal: Integer;
begin
  if ANoDelay then
    LOptVal := 1
  else
    LOptVal := 0;
  Result := TSocketAPI.SetSockOpt(ASocket, IPPROTO_TCP, TCP_NODELAY, LOptVal, SizeOf(Integer));
end;

{ *
  * Writeable – uses select() to check if the socket is writable.
}
class function TSocketAPI.Writeable(const ASocket: TSocket;
  const ATimeout: Integer): Integer;
var
  {$IFDEF MSWINDOWS}
  LFDSet: TFDSet;
  LTime_val: TTimeval;
  {$ELSE}
  LFDSet: {$IFDEF DELPHI}fd_set{$ELSE}TFDSet{$ENDIF};
  LTime_val: timeval;
  {$ENDIF}
  P: PTimeVal;
begin
  if (ATimeout >= 0) then
  begin
    LTime_val.tv_sec := ATimeout div 1000;
    LTime_val.tv_usec :=  1000 * (ATimeout mod 1000);
    P := @LTime_val;
  end else
    P := nil;

  {$IFDEF MSWINDOWS}
  FD_ZERO(LFDSet);
  FD_SET(ASocket, LFDSet);
  Result := Z.FP.Net.Winsock2.select(0, nil, @LFDSet, nil, P);
  {$ELSE}
  {$IFDEF DELPHI}
  FD_ZERO(LFDSet);
  _FD_SET(ASocket, LFDSet);
  Result := Posix.SysSelect.select(0, nil, @LFDSet, nil, P);
  {$ELSE}
  fpFD_ZERO(LFDSet);
  fpFD_SET(ASocket, LFDSet);
  Result := fpselect(0, nil, @LFDSet, nil, P);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

end.
 
