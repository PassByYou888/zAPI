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
unit Z.FP.Net.CrossSocket.Iocp;

{ *
  * CrossSocket.Iocp – Windows implementation using I/O Completion Ports (IOCP).
  *
  * This unit provides a high‑performance, scalable I/O engine for Windows
  * based on the IOCP API. It uses overlapped I/O with completion routines,
  * and supports AcceptEx, ConnectEx, WSASend, WSARecv, etc.
  *
  * Key features:
  *   - Each socket is associated with the completion port via CreateIoCompletionPort.
  *   - Overlapped structures (TPerIoData) are allocated per I/O operation and
  *     freed upon completion.
  *   - AcceptEx is used for accepting connections with zero‑byte receive to
  *     detect client disconnection early.
  *   - WSASend is used for writes; it does not support partial sends, so the
  *     callback indicates success or failure for the whole buffer.
  *   - The loop uses GetQueuedCompletionStatus with INFINITE timeout.
  *
  * Example:
  *   var
  *     sock: TIocpCrossSocket;
  *   begin
  *     sock := TIocpCrossSocket.Create(4);
  *     sock.OnReceived := procedure(Sender: TCore_Object; AConn: ICrossConnection; ABuf: Pointer; ALen: Integer)
  *       begin
  *         // process data
  *       end;
  *     sock.Listen('0.0.0.0', 8080);
  *     while True do
  *       CheckThreadSynchronize(10);
  *   end;
}

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

{$IFDEF MSWINDOWS}

uses
  Z.Core, Z.PascalStrings, Z.UPascalStrings,
  SysUtils,
  Classes,
  Windows,
  Z.FP.Net.Winsock2,
  Z.FP.Net.Wship6,
  Z.FP.Net.SocketAPI,
  Z.FP.Net.CrossSocket.Base;

type
  TIocpListen = class(TAbstractCrossListen)
    // No additional fields – IOCP handles listeners via AcceptEx.
  end;

  TIocpConnection = class(TAbstractCrossConnection)
    // No additional fields – IOCP handles connections via overlapped I/O.
  end;

  { *
    * TIocpCrossSocket – main IOCP engine.
    *
    * It uses a set of I/O threads that call GetQueuedCompletionStatus.
    * Each I/O operation allocates a TPerIoData that carries the operation type,
    * socket, and callback.
  }
  TIocpCrossSocket = class(TAbstractCrossSocket)
  private const
    SHUTDOWN_FLAG = ULONG_PTR(-1); // sentinel for stopping threads
    SO_UPDATE_CONNECT_CONTEXT = $7010;
    IPV6_V6ONLY = 27;
    ERROR_ABANDONED_WAIT_0 = $02DF;
  private type
    // Union for IPv4/IPv6 address buffers used in AcceptEx
    TAddrUnion = record
      case Integer of
        0: (IPv4: TSockAddrIn);
        1: (IPv6: TSockAddrIn6);
    end;

    TAddrBuffer = record
      Addr: TAddrUnion;
      Extra: array [0 .. 15] of Byte;
    end;

    TAcceptExBuffer = array [0 .. SizeOf(TAddrBuffer) * 2 - 1] of Byte;

    { *
      * Per‑I/O data structure. Overlapped is the first field so it can be cast
      * to LPWSAOVERLAPPED. The Buffer union holds either a WSABUF for read/write
      * or the AcceptEx address buffer.
    }
    TPerIoBufUnion = record
      case Integer of
        0: (DataBuf: WSABUF);
        1: (AcceptExBuffer: TAcceptExBuffer);
    end;

    TIocpAction = (ioAccept, ioConnect, ioRead, ioWrite);

    PPerIoData = ^TPerIoData;

    TPerIoData = record
      Overlapped: TWSAOverlapped;
      Buffer: TPerIoBufUnion;
      Action: TIocpAction;
      Socket: THandle;
      CrossData: ICrossData;      // the connection or listen object
      Callback: TProc_ICrossConnection_Boolean;
    end;
  private
    FIocpHandle: THandle;
    FIoThreads: TArray<TIoEventThread>;

    // Memory helpers for TPerIoData
    function _NewIoData: PPerIoData;
    procedure _FreeIoData(P: PPerIoData);

    // Post a new AcceptEx on a listener, or a zero‑byte read on a connection
    function _NewAccept(AListen: ICrossListen): Boolean;
    function _NewReadZero(AConnection: ICrossConnection): Boolean;

    // Completion handlers
    procedure _HandleAccept(APerIoData: PPerIoData);
    procedure _HandleConnect(APerIoData: PPerIoData);
    procedure _HandleRead(APerIoData: PPerIoData);
    procedure _HandleWrite(APerIoData: PPerIoData);
  protected
    function CreateListen(AOwner: ICrossSocket; AListenSocket: THandle;
      AFamily, ASockType, AProtocol: Integer): ICrossListen; override;
    function CreateConnection(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType): ICrossConnection; override;

    procedure StartLoop; override;
    procedure StopLoop; override;

    procedure Listen(const AHost: SystemString; APort: Word;
      const ACallback: TProc_ICrossListen_Boolean = nil); override;
    procedure Connect(const AHost: SystemString; APort: Word;
      const ACallback: TProc_ICrossConnection_Boolean = nil); override;
    procedure Send(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer;
      const ACallback: TProc_ICrossConnection_Boolean = nil); override;

    function ProcessIoEvent: Boolean; override;
  end;

{$ENDIF MSWINDOWS}

implementation

{$IFDEF MSWINDOWS}

{ *
  * _NewIoData – allocate and zero a TPerIoData.
}
function TIocpCrossSocket._NewIoData: PPerIoData;
begin
  System.New(Result);
  FillChar(Result^, SizeOf(TPerIoData), 0);
end;

{ *
  * _FreeIoData – release the overlapped structure.
}
procedure TIocpCrossSocket._FreeIoData(P: PPerIoData);
begin
  P.CrossData := nil;
  System.Dispose(P);
end;

{ *
  * _NewAccept – post an AcceptEx on the listener.
  * Creates a new socket for the incoming connection and issues AcceptEx.
  * Returns True if the operation was successfully queued (or pending).
}
function TIocpCrossSocket._NewAccept(AListen: ICrossListen): Boolean;
var
  LClientSocket: THandle;
  LPerIoData: PPerIoData;
  LBytes: Cardinal;
begin
  Result := False;
  LClientSocket := WSASocket(AListen.Family, AListen.SockType, AListen.Protocol,
    nil, 0, WSA_FLAG_OVERLAPPED);
  if (LClientSocket = INVALID_SOCKET) then
    begin
{$IFDEF DEBUG}
      _LogLastOsError('TIocpCrossSocket._NewAccept.WSASocket');
{$ENDIF}
      Exit;
    end;

  if not TriggerAccept(AListen) then
    begin
      TSocketAPI.CloseSocket(LClientSocket);
      Exit;
    end;

  TSocketAPI.SetNonBlock(LClientSocket, True);
  SetKeepAlive(LClientSocket);
  TSocketAPI.SetTcpNoDelay(LClientSocket, True);

  LPerIoData := _NewIoData;
  LPerIoData.Action := ioAccept;
  LPerIoData.Socket := LClientSocket;
  LPerIoData.CrossData := AListen;
  if (not AcceptEx(AListen.Socket, LClientSocket, @LPerIoData.Buffer.AcceptExBuffer, 0,
      SizeOf(TAddrBuffer), SizeOf(TAddrBuffer), LBytes, POverlapped(LPerIoData)))
    and (WSAGetLastError <> WSA_IO_PENDING) then
    begin
{$IFDEF DEBUG}
      _LogLastOsError('TIocpCrossSocket._NewAccept.AcceptEx');
{$ENDIF}
      TSocketAPI.CloseSocket(LClientSocket);
      _FreeIoData(LPerIoData);
    end
  else
    Result := True;
end;

{ *
  * _NewReadZero – post a zero‑byte WSARecv to detect connection closure.
  * This is a common IOCP pattern to get notified when the client closes.
}
function TIocpCrossSocket._NewReadZero(AConnection: ICrossConnection): Boolean;
var
  LPerIoData: PPerIoData;
  LBytes, LFlags: Cardinal;
begin
  LPerIoData := _NewIoData;
  LPerIoData.Buffer.DataBuf.buf := nil;
  LPerIoData.Buffer.DataBuf.len := 0;
  LPerIoData.Action := ioRead;
  LPerIoData.Socket := AConnection.Socket;
  LPerIoData.CrossData := AConnection;

  LFlags := 0;
  LBytes := 0;
  if (WSARecv(AConnection.Socket, @LPerIoData.Buffer.DataBuf, 1, LBytes, LFlags, PWSAOverlapped(LPerIoData), nil) < 0)
    and (WSAGetLastError <> WSA_IO_PENDING) then
    begin
{$IFDEF DEBUG}
      // _LogLastOsError('TIocpCrossSocket._NewReadZero.WSARecv');
{$ENDIF}
      _FreeIoData(LPerIoData);
      Exit(False);
    end;

  Result := True;
end;

{ *
  * _HandleAccept – completion of AcceptEx.
  * Sets SO_UPDATE_ACCEPT_CONTEXT, associates the new socket with the IOCP,
  * creates the connection object, and posts a zero‑byte read.
}
procedure TIocpCrossSocket._HandleAccept(APerIoData: PPerIoData);
var
  LListen: ICrossListen;
  LConnection: ICrossConnection;
  LClientSocket, LListenSocket: THandle;
begin
  LListen := APerIoData.CrossData as ICrossListen;
  if not _NewAccept(LListen) then
    Exit; // post next AcceptEx

  LClientSocket := APerIoData.Socket;
  LListenSocket := LListen.Socket;

  // Required for getpeername to work on accepted socket
  if (TSocketAPI.SetSockOpt<THandle>(LClientSocket, SOL_SOCKET,
      SO_UPDATE_ACCEPT_CONTEXT, LListenSocket) < 0) then
    begin
{$IFDEF DEBUG}
      _LogLastOsError('TIocpCrossSocket._HandleAccept.SetSockOpt');
{$ENDIF}
      TSocketAPI.CloseSocket(LClientSocket);
      Exit;
    end;

  if (CreateIoCompletionPort(LClientSocket, FIocpHandle, ULONG_PTR(LClientSocket), 0) = 0) then
    begin
{$IFDEF DEBUG}
      _LogLastOsError('TIocpCrossSocket._HandleAccept.CreateIoCompletionPort');
{$ENDIF}
      TSocketAPI.CloseSocket(LClientSocket);
      Exit;
    end;

  LConnection := CreateConnection(Self, LClientSocket, ctAccept);
  TriggerConnecting(LConnection);
  TriggerConnected(LConnection);

  if not _NewReadZero(LConnection) then
      LConnection.Close;
end;

{ *
  * _HandleConnect – completion of ConnectEx (or connect via overlapped).
  * Checks for errors, sets SO_UPDATE_CONNECT_CONTEXT, and posts a zero‑byte read.
}
procedure TIocpCrossSocket._HandleConnect(APerIoData: PPerIoData);
var
  LClientSocket: THandle;
  LConnection: ICrossConnection;
  LSuccess: Boolean;

  procedure _Failed1;
  begin
{$IFDEF DEBUG}
    _LogLastOsError('TIocpCrossSocket._HandleConnect');
{$ENDIF}
    TSocketAPI.CloseSocket(LClientSocket);

    if Assigned(APerIoData.Callback) then
        APerIoData.Callback(nil, False);
  end;

begin
  LClientSocket := APerIoData.Socket;

  if (TSocketAPI.GetError(LClientSocket) <> 0) then
    begin
      _Failed1;
      Exit;
    end;

  // Required for getpeername to work
  if (TSocketAPI.SetSockOpt<Integer>(LClientSocket, SOL_SOCKET,
      SO_UPDATE_CONNECT_CONTEXT, 1) < 0) then
    begin
      _Failed1;
      Exit;
    end;

  LConnection := CreateConnection(Self, LClientSocket, ctConnect);
  TriggerConnecting(LConnection);

  LSuccess := _NewReadZero(LConnection);
  if LSuccess then
      TriggerConnected(LConnection)
  else
      LConnection.Close;

  if Assigned(APerIoData.Callback) then
      APerIoData.Callback(LConnection, LSuccess);
end;

{ *
  * _HandleRead – completion of a zero‑byte read (or actual data read?).
  * This implementation uses the zero‑byte read only to detect closure; actual
  * data is read via synchronous recv in a loop.
}
procedure TIocpCrossSocket._HandleRead(APerIoData: PPerIoData);
var
  LConnection: ICrossConnection;
  LRcvd, LError: Integer;
begin
  LConnection := APerIoData.CrossData as ICrossConnection;

  while True do
    begin
      LRcvd := TSocketAPI.Recv(LConnection.Socket, FRecvBuf[0], RCV_BUF_SIZE);

      if (LRcvd = 0) then
        begin
          LConnection.Close;
          Exit;
        end;

      if (LRcvd < 0) then
        begin
          LError := GetLastError;

          if (LError = WSAEINTR) then
              Continue
          else if (LError = WSAEWOULDBLOCK) or (LError = WSAEINPROGRESS) then
              Break
          else
            begin
              LConnection.Close;
              Exit;
            end;
        end;

      TriggerReceived(LConnection, @FRecvBuf[0], LRcvd);

      if (LRcvd < RCV_BUF_SIZE) then
        Break;
    end;

  if not _NewReadZero(LConnection) then
      LConnection.Close;
end;

{ *
  * _HandleWrite – completion of WSASend. Simply invoke the callback with success.
}
procedure TIocpCrossSocket._HandleWrite(APerIoData: PPerIoData);
begin
  if Assigned(APerIoData.Callback) then
      APerIoData.Callback(APerIoData.CrossData as ICrossConnection, True);
end;

{ *
  * StartLoop – create the completion port and start I/O threads.
}
procedure TIocpCrossSocket.StartLoop;
var
  I: Integer;
begin
  if (FIoThreads <> nil) then
    Exit;

  FIocpHandle := CreateIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, 0);
  SetLength(FIoThreads, GetIoThreads);
  for I := 0 to Length(FIoThreads) - 1 do
      FIoThreads[I] := TIoEventThread.Create(Self);
end;

{ *
  * StopLoop – post shutdown packets, wait for threads to finish.
}
procedure TIocpCrossSocket.StopLoop;
var
  I: Integer;
  LCurrentThreadID: TThreadID;
begin
  if (FIoThreads = nil) then
    Exit;

  CloseAll;
  while (ListensCount > 0) or (ConnectionsCount > 0) do
    Sleep(1);

  // Post a special packet to each thread
  for I := 0 to Length(FIoThreads) - 1 do
      PostQueuedCompletionStatus(FIocpHandle, 0, 0, POverlapped(SHUTDOWN_FLAG));

  LCurrentThreadID := GetCurrentThreadId;
  for I := 0 to Length(FIoThreads) - 1 do
    begin
      if (FIoThreads[I].ThreadID = LCurrentThreadID) then
          raise ECrossSocket.Create('Cannot call StopLoop from an I/O thread!');

      while FIoThreads[I].IO_Is_Busy do
          Check_Soft_Thread_Synchronize(10, False);
      FreeAndNil(FIoThreads[I]);
    end;
  FIoThreads := nil;

  CloseHandle(FIocpHandle);
end;

{ *
  * Connect – use ConnectEx (or fallback) with overlapped I/O.
}
procedure TIocpCrossSocket.Connect(const AHost: SystemString; APort: Word;
  const ACallback: TProc_ICrossConnection_Boolean);
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LSocket: THandle;

  procedure _Failed1;
  begin
    if Assigned(ACallback) then
        ACallback(nil, False);
  end;

  function _Connect(ASocket: THandle; AAddr: PRawAddrInfo): Boolean;
    procedure _Failed2;
    begin
      TSocketAPI.CloseSocket(ASocket);
      if Assigned(ACallback) then
          ACallback(nil, False);
    end;

  var
    LSockAddr: TRawSockAddrIn;
    LPerIoData: PPerIoData;
    LBytes: Cardinal;
  begin
    // Bind to a temporary local address
    LSockAddr.AddrLen := AAddr.ai_addrlen;
    Move(AAddr.ai_addr^, LSockAddr.Addr, AAddr.ai_addrlen);
    if (AAddr.ai_family = AF_INET6) then
      begin
        LSockAddr.Addr6.sin6_addr := in6addr_any;
        LSockAddr.Addr6.sin6_port := 0;
      end
    else
      begin
        LSockAddr.Addr.sin_addr.S_addr := INADDR_ANY;
        LSockAddr.Addr.sin_port := 0;
      end;
    if (TSocketAPI.Bind(ASocket, @LSockAddr.Addr, LSockAddr.AddrLen) < 0) then
      begin
        _Failed2;
        Exit(False);
      end;

    if (CreateIoCompletionPort(ASocket, FIocpHandle, ULONG_PTR(ASocket), 0) = 0) then
      begin
        _Failed2;
        Exit(False);
      end;

    LPerIoData := _NewIoData;
    LPerIoData.Action := ioConnect;
    LPerIoData.Socket := ASocket;
    LPerIoData.Callback := ACallback;
    if not ConnectEx(ASocket, AAddr.ai_addr, AAddr.ai_addrlen, nil, 0, LBytes, PWSAOverlapped(LPerIoData)) and
      (WSAGetLastError <> WSA_IO_PENDING) then
      begin
        _FreeIoData(LPerIoData);
        _Failed2;
        Exit(False);
      end;

    Result := True;
  end;

begin
  FillChar(LHints, SizeOf(TRawAddrInfo), 0);
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LAddrInfo := TSocketAPI.GetAddrInfo(AHost, APort, LHints);
  if (LAddrInfo = nil) then
    begin
      _Failed1;
      Exit;
    end;

  P := LAddrInfo;
  try
    while (LAddrInfo <> nil) do
      begin
        LSocket := WSASocket(LAddrInfo.ai_family, LAddrInfo.ai_socktype,
          LAddrInfo.ai_protocol, nil, 0, WSA_FLAG_OVERLAPPED);
        if (LSocket = INVALID_SOCKET) then
          begin
            _Failed1;
            Exit;
          end;

        TSocketAPI.SetNonBlock(LSocket, True);
        SetKeepAlive(LSocket);

        if _Connect(LSocket, LAddrInfo) then
          Exit;

        LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
      end;
  finally
      TSocketAPI.FreeAddrInfo(P);
  end;

  _Failed1;
end;

function TIocpCrossSocket.CreateConnection(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType): ICrossConnection;
begin
  Result := TIocpConnection.Create(AOwner, AClientSocket, AConnectType);
end;

function TIocpCrossSocket.CreateListen(AOwner: ICrossSocket;
  AListenSocket: THandle; AFamily, ASockType, AProtocol: Integer): ICrossListen;
begin
  Result := TIocpListen.Create(AOwner, AListenSocket, AFamily, ASockType, AProtocol);
end;

{ *
  * Listen – bind, listen, and post one AcceptEx per I/O thread.
}
procedure TIocpCrossSocket.Listen(const AHost: SystemString; APort: Word;
  const ACallback: TProc_ICrossListen_Boolean);
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LListenSocket: THandle;
  LListen: ICrossListen;
  I: Integer;

  procedure _Failed;
  begin
    if (LListen <> nil) then
        LListen.Close;

    if Assigned(ACallback) then
        ACallback(LListen, False);
  end;

  procedure _Success;
  begin
    TriggerListened(LListen);

    if Assigned(ACallback) then
        ACallback(LListen, True);
  end;

begin
  LListen := nil;
  FillChar(LHints, SizeOf(TRawAddrInfo), 0);

  LHints.ai_flags := AI_PASSIVE;
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LAddrInfo := TSocketAPI.GetAddrInfo(AHost, APort, LHints);
  if (LAddrInfo = nil) then
    begin
{$IFDEF DEBUG}
      _LogLastOsError('TIocpCrossSocket.Listen.GetAddrInfo');
{$ENDIF}
      _Failed;
      Exit;
    end;

  P := LAddrInfo;
  try
    while (LAddrInfo <> nil) do
      begin
        LListenSocket := WSASocket(LAddrInfo.ai_family, LAddrInfo.ai_socktype,
          LAddrInfo.ai_protocol, nil, 0, WSA_FLAG_OVERLAPPED);
        if (LListenSocket = INVALID_SOCKET) then
          begin
{$IFDEF DEBUG}
            _LogLastOsError('TIocpCrossSocket.Listen.WSASocket');
{$ENDIF}
            _Failed;
            Exit;
          end;

        TSocketAPI.SetNonBlock(LListenSocket, True);
        // Do not enable SO_REUSEADDR on Windows; it can cause false success.
        if (LAddrInfo.ai_family = AF_INET6) then
            TSocketAPI.SetSockOpt<Integer>(LListenSocket, IPPROTO_IPV6, IPV6_V6ONLY, 1);

        if (TSocketAPI.Bind(LListenSocket, LAddrInfo.ai_addr, LAddrInfo.ai_addrlen) < 0)
          or (TSocketAPI.Listen(LListenSocket) < 0) then
          begin
{$IFDEF DEBUG}
            _LogLastOsError('TIocpCrossSocket.Listen.Bind');
{$ENDIF}
            _Failed;
            Exit;
          end;

        LListen := CreateListen(Self, LListenSocket, LAddrInfo.ai_family,
          LAddrInfo.ai_socktype, LAddrInfo.ai_protocol);

        if (CreateIoCompletionPort(LListenSocket, FIocpHandle, ULONG_PTR(LListenSocket), 0) = 0) then
          begin
{$IFDEF DEBUG}
            _LogLastOsError('TIocpCrossSocket.Listen.CreateIoCompletionPort');
{$ENDIF}
            _Failed;
            Exit;
          end;

        // Post one AcceptEx per I/O thread to allow load balancing
        for I := 1 to GetIoThreads do
            _NewAccept(LListen);

        _Success;

        if (APort = 0) and (LAddrInfo.ai_next <> nil) then
            LAddrInfo.ai_next.ai_addr.sin_port := LListen.LocalPort;

        LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
      end;
  finally
      TSocketAPI.FreeAddrInfo(P);
  end;
end;

{ *
  * Send – post a WSASend. Note that WSASend does not support partial sends;
  * if it fails, the callback is invoked with failure.
}
procedure TIocpCrossSocket.Send(AConnection: ICrossConnection; ABuf: Pointer;
  ALen: Integer; const ACallback: TProc_ICrossConnection_Boolean);
var
  LPerIoData: PPerIoData;
  LBytes, LFlags: Cardinal;
begin
  LPerIoData := _NewIoData;
  LPerIoData.Buffer.DataBuf.buf := ABuf;
  LPerIoData.Buffer.DataBuf.len := ALen;
  LPerIoData.Action := ioWrite;
  LPerIoData.Socket := AConnection.Socket;
  LPerIoData.CrossData := AConnection;
  LPerIoData.Callback := ACallback;

  LFlags := 0;
  LBytes := 0;
  if (WSASend(AConnection.Socket, @LPerIoData.Buffer.DataBuf, 1, LBytes, LFlags, PWSAOverlapped(LPerIoData), nil) < 0)
    and (WSAGetLastError <> WSA_IO_PENDING) then
    begin
      _FreeIoData(LPerIoData);
      AConnection.Close;

      if Assigned(ACallback) then
          ACallback(AConnection, False);
    end;
end;

{ *
  * ProcessIoEvent – main loop: wait for completion, dispatch by action.
}
function TIocpCrossSocket.ProcessIoEvent: Boolean;
var
  LBytes: Cardinal;
  LSocket: THandle;
  LPerIoData: PPerIoData;
{$IFDEF DEBUG}
  LErrNo: Cardinal;
{$ENDIF}
begin
  if not GetQueuedCompletionStatus(FIocpHandle, LBytes, ULONG_PTR(LSocket), POverlapped(LPerIoData), INFINITE) then
    begin
      if (LPerIoData = nil) then
        begin
{$IFDEF DEBUG}
          LErrNo := GetLastError;
          if (LErrNo <> ERROR_INVALID_HANDLE)
            and (LErrNo <> ERROR_ABANDONED_WAIT_0)
          then
              _LogLastOsError('TIocpCrossSocket.ProcessIoEvent.GetQueuedCompletionStatus');
{$ENDIF}
          Exit(False);
        end;

      try
        if (LPerIoData.CrossData <> nil) then
          begin
            if (LPerIoData.Action = ioAccept) then
              begin
                if (GetLastError <> WSA_OPERATION_ABORTED) then
                    _NewAccept(LPerIoData.CrossData as ICrossListen);
              end
            else
              begin
                LPerIoData.CrossData.Close;
                if Assigned(LPerIoData.Callback)
                  and (LPerIoData.CrossData is TIocpConnection) then
                    LPerIoData.Callback(LPerIoData.CrossData as ICrossConnection, False);
              end;
          end
        else
          begin
            TSocketAPI.CloseSocket(LPerIoData.Socket);
            if Assigned(LPerIoData.Callback) then
              begin
                try
                    LPerIoData.Callback(nil, False);
                except
                end;
              end;
          end;
      finally
          _FreeIoData(LPerIoData);
      end;

      Exit(True); // retry
    end;

  if (LBytes = 0) and (ULONG_PTR(LPerIoData) = SHUTDOWN_FLAG) then
    Exit(False);

  if (LPerIoData = nil) then
    Exit(True);

  try
    case LPerIoData.Action of
      ioAccept: _HandleAccept(LPerIoData);
      ioConnect: _HandleConnect(LPerIoData);
      ioRead: _HandleRead(LPerIoData);
      ioWrite: _HandleWrite(LPerIoData);
    end;
  finally
      _FreeIoData(LPerIoData);
  end;

  Result := True;
end;

{$ENDIF MSWINDOWS}

end.
 
