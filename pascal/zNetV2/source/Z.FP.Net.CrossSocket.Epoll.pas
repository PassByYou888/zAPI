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
unit Z.FP.Net.CrossSocket.Epoll;

{ *
  * CrossSocket.Epoll – Linux implementation using epoll (edge‑triggered + oneshot).
  *
  * This unit provides a high‑performance I/O engine for Linux/Android based on
  * the epoll system call. It uses EPOLLET (edge‑triggered) and EPOLLONESHOT
  * to allow thread‑safe handling of events across multiple I/O threads.
  *
  * Key characteristics:
  *   - Each socket has a single entry in the epoll set; events (read/write) are
  *     combined using bitwise OR.
  *   - EPOLLONESHOT ensures that after an event is delivered, the socket is
  *     automatically removed from the epoll set until re‑armed.
  *   - A send queue (TSendQueue) is per‑connection to serialize writes and
  *     prevent data corruption from concurrent sends.
  *   - UIDs (64‑bit) are used as the epoll data to look up the associated
  *     object after an event, avoiding reference‑counting issues.
  *   - The engine is stopped by writing to an eventfd that is monitored.
  *
  * Example usage (server):
  *   var
  *     sock: TEpollCrossSocket;
  *   begin
  *     sock := TEpollCrossSocket.Create(4);
  *     sock.OnConnected := procedure(Sender: TCore_Object; AConn: ICrossConnection)
  *       begin
  *         // handle new connection
  *       end;
  *     sock.Listen('0.0.0.0', 8080);
  *     while True do
  *       CheckThreadSynchronize(10);
  *   end;
}

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

{$UNDEF Debug_Log} // uncomment for detailed debug output

interface

{$IFDEF LINUX}
uses
  Z.Core,
  Z.PascalStrings,
  Z.UPascalStrings,
  Z.Status,
  SysUtils,
  Classes,
  {$IFDEF LINUX}
    {$IFDEF FPC}
      BaseUnix,
      Unix,
      Sockets,
      netdb,
      termio,
      ctypes,
      linux,
    {$ELSE FPC}
      Posix.Base,
      Posix.SysSocket,
      Posix.NetinetIn,
      Posix.UniStd,
      Posix.NetDB,
      Posix.Pthread,
      Posix.ArpaInet,
      Posix.Errno,
    {$ENDIF FPC}
  {$ENDIF LINUX}
  Z.FP.Net.Linux.epoll,
  Z.FP.Net.SocketAPI,
  Z.FP.Net.CrossSocket.Base;

type
  TEpollCrossSocket = class;
  TIoEvent = (ieRead, ieWrite);
  TIoEvents = set of TIoEvent;

  { *
    * TEpollListen – epoll‑specific listener object.
    * Manages its epoll registration and event re‑arming.
  }
  TEpollListen = class(TAbstractCrossListen)
  private
    FLock: TCritical;          // protects event registration
    FIoEvents: TIoEvents;      // currently monitored events
    FOpCode: Integer;          // EPOLL_CTL_ADD or EPOLL_CTL_MOD

    procedure _Lock;
    procedure _Unlock;

    function _ReadEnabled: Boolean;
    function _UpdateIoEvent(const Inst:TEpollCrossSocket; const AIoEvents: TIoEvents): Boolean;
  public
    constructor Create(AOwner: ICrossSocket; AListenSocket: THandle;
      AFamily, ASockType, AProtocol: Integer); override;
    destructor Destroy; override;
    function Get_Owner_: TEpollCrossSocket;
  end;

  PSendItem = ^TSendItem;
  TSendItem = record
    Data: PByte;               // pointer to the data to send
    Size: Integer;             // number of bytes
    Callback: TProc_ICrossConnection_Boolean; // completion callback
  end;

  { *
    * TSendQueue – a queue of send items. Inherits from TBigList to reuse nodes.
  }
  TSendQueue = class(TBigList<PSendItem>)
  protected
    procedure DoFree(var Data: PSendItem); override;
  end;

  { *
    * TEpollConnection – epoll‑specific connection.
    * Maintains its own send queue and controls epoll registration.
  }
  TEpollConnection = class(TAbstractCrossConnection)
  private
    FLock: TCritical;
    FSendQueue: TSendQueue;
    FIoEvents: TIoEvents;
    FConnectCallback: TProc_ICrossConnection_Boolean; // called on connect result
    FOpCode: Integer;          // EPOLL_CTL_ADD or EPOLL_CTL_MOD

    procedure _Lock;
    procedure _Unlock;

    function _ReadEnabled: Boolean;
    function _WriteEnabled: Boolean;
    function _UpdateIoEvent(const Inst:TEpollCrossSocket; const AIoEvents: TIoEvents): Boolean;
  public
    constructor Create(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType); override;
    destructor Destroy; override;
    function Get_Owner_: TEpollCrossSocket;
  end;

  { *
    * TEpollCrossSocket – main epoll engine.
    *
    * Design notes:
    *   - Epoll does not support duplicate entries per fd; we combine read/write
    *     into a single event bitmask.
    *   - EPOLLONESHOT is used to make epoll thread‑safe: after an event is
    *     delivered, the fd is disabled; we must re‑arm with epoll_ctl(EPOLL_CTL_MOD).
    *   - Send operations are queued per‑connection; the actual send is performed
    *     when EPOLLOUT triggers.
    *   - Connection lookup is done by UID (stored in epoll_data.u64) to avoid
    *     dangling references.
  }
  TEpollCrossSocket = class(TAbstractCrossSocket)
  private const
    MAX_EVENT_COUNT = 2048;       // max events per epoll_wait call
    SHUTDOWN_FLAG   = UInt64(-1); // sentinel value for epoll_data when stopping
  private class threadvar
    FEventList: array [0..MAX_EVENT_COUNT-1] of TEPoll_Event; // thread‑local event buffer
  private
    FEpollHandle: THandle;       // epoll file descriptor
    FIoThreads: array of TIoEventThread; // worker threads
    FIdleHandle: THandle;        // file handle to /dev/null, used to recover from EMFILE
    FIdleLock: TCritical;        // protects FIdleHandle
    FStopHandle: THandle;        // eventfd for shutdown notification

    // --- Helper methods for stop handle ---
    procedure _OpenStopHandle;
    procedure _PostStopCommand;
    procedure _CloseStopHandle;

    // --- Idle handle (for EMFILE recovery) ---
    procedure _OpenIdleHandle;
    procedure _CloseIdleHandle;

    // --- Event handlers (called from the I/O threads) ---
    procedure _HandleAccept(AListen: ICrossListen);
    procedure _HandleConnect(AConnection: ICrossConnection);
    procedure _HandleRead(AConnection: ICrossConnection);
    procedure _HandleWrite(AConnection: ICrossConnection);
  protected
    // Factory methods
    function CreateConnection(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType): ICrossConnection; override;
    function CreateListen(AOwner: ICrossSocket; AListenSocket: THandle;
      AFamily, ASockType, AProtocol: Integer): ICrossListen; override;

    // Lifecycle
    procedure StartLoop; override;
    procedure StopLoop; override;

    // Public API overrides
    procedure Listen(const AHost: SystemString; APort: Word;
      const ACallback: TProc_ICrossListen_Boolean = nil); override;
    procedure Connect(const AHost: SystemString; APort: Word;
      const ACallback: TProc_ICrossConnection_Boolean = nil); override;
    procedure Send(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer;
      const ACallback: TProc_ICrossConnection_Boolean = nil); override;

    // I/O loop method
    function ProcessIoEvent: Boolean; override;
  public
    constructor Create(AIoThreads: Integer); override;
    destructor Destroy; override;
  end;

{$ENDIF LINUX}

implementation

{$IFDEF LINUX}

{$IFDEF FPC}
const
  EINTR       = ESysEINTR;
  EAGAIN      = ESysEAGAIN;
  EWOULDBLOCK = ESysEWOULDBLOCK;
  EMFILE      = ESysEMFILE;
  EINPROGRESS = ESysEINPROGRESS;

  AI_PASSIVE  = $00000001;
  INVALID_HANDLE_VALUE = DWORD(-1);

function GetLastError: Integer;
begin
  Result := fpgeterrno;
end;

{$LINKLIB c}
function eventfd(initval: Cardinal; flags: Integer): Integer; cdecl; external;

{$ENDIF FPC}

{$I Z.FP.Net.Posix.inc}

{ *
  * TEpollListen – constructor: initialise lock and opcode.
}
constructor TEpollListen.Create(AOwner: ICrossSocket; AListenSocket: THandle;
  AFamily, ASockType, AProtocol: Integer);
begin
  inherited;

  FLock := TCritical.Create;
  FOpCode := EPOLL_CTL_ADD; // first registration is an ADD
end;

destructor TEpollListen.Destroy;
begin
  DisposeObjectAndNil(FLock);
  inherited;
end;

function TEpollListen.Get_Owner_: TEpollCrossSocket;
begin
  Result := Owner as TEpollCrossSocket;
end;

procedure TEpollListen._Lock;
begin
  FLock.Lock;
end;

function TEpollListen._ReadEnabled: Boolean;
begin
  Result := (ieRead in FIoEvents);
end;

procedure TEpollListen._Unlock;
begin
  FLock.UnLock;
end;

{ *
  * _UpdateIoEvent – (re)register this listener with epoll.
  * Uses the current FIoEvents and updates the epoll set.
  * @param Inst    the owning TEpollCrossSocket
  * @param AIoEvents new event set (only ieRead is used for listeners)
  * @return True if epoll_ctl succeeded
}
function TEpollListen._UpdateIoEvent(const Inst:TEpollCrossSocket; const AIoEvents: TIoEvents): Boolean;
var
  LEvent: TEPoll_Event;
  rcode{$IFDEF Debug_Log}, err{$ENDIF Debug_Log}:Integer;
begin
  FIoEvents := AIoEvents;

  if (FIoEvents = []) or IsClosed then Exit(False);

  LEvent.Events := EPOLLET or EPOLLONESHOT;
  LEvent.Data.u64 := Self.UID;

  if _ReadEnabled then
    LEvent.Events := LEvent.Events or EPOLLIN;

  rcode := epoll_ctl(Inst.FEpollHandle, FOpCode, Socket, @LEvent);
  Result := (rcode >= 0);
  FOpCode := EPOLL_CTL_MOD; // subsequent calls are MOD

  {$IFDEF Debug_Log}
  Err := GetLastError;
  _Log('[LISTEN REG] Op=%d, EpFd=%d, SockFd=%d, UID=%x, Ret=%s, rcode=%d, Errno=%d',
    [FOpCode, Inst.FEpollHandle, Socket, Self.UID, BoolToStr(Result,True), rcode, Err]);
  {$ENDIF Debug_Log}
end;

{ *
  * TSendQueue.DoFree – frees the PSendItem and its callback.
}
procedure TSendQueue.DoFree(var Data: PSendItem);
begin
  if Data <> nil then
    begin
      Data^.Callback := nil;
      System.Dispose(Data);
      Data := nil;
    end;
  inherited;
end;

{ *
  * TEpollConnection – constructor: create send queue and lock, set initial opcode.
}
constructor TEpollConnection.Create(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType);
begin
  inherited;

  FSendQueue := TSendQueue.Create;
  FLock := TCritical.Create;

  FOpCode := EPOLL_CTL_ADD;
end;

{ *
  * TEpollConnection.Destroy – flush pending callbacks on failure.
}
destructor TEpollConnection.Destroy;
var
  LConnection: ICrossConnection;
  LSendItem: PSendItem;
begin
  LConnection := Self;

  _Lock;
  try
    // If we still have a connect callback, it means the connection never succeeded
    if Assigned(FConnectCallback) then
    begin
      FConnectCallback(LConnection, False);
      FConnectCallback := nil;
    end;

    // Invoke all pending send callbacks with failure
    if (FSendQueue.Num > 0) then
    begin
      with FSendQueue.Repeat_ do
       repeat
        if Assigned(Queue^.Data^.Callback) then
          Queue^.Data^.Callback(LConnection, False);
       until not Next;

      FSendQueue.Clear;
    end;

    DisposeObjectAndNil(FSendQueue);
  finally
    _Unlock;
  end;

  DisposeObjectAndNil(FLock);

  inherited;
end;

function TEpollConnection.Get_Owner_: TEpollCrossSocket;
begin
  Result := Owner as TEpollCrossSocket;
end;

procedure TEpollConnection._Lock;
begin
  FLock.Lock;
end;

function TEpollConnection._ReadEnabled: Boolean;
begin
  Result := (ieRead in FIoEvents);
end;

procedure TEpollConnection._Unlock;
begin
  FLock.UnLock;
end;

{ *
  * _UpdateIoEvent – (re)register this connection with epoll.
  * Combines read and/or write events.
}
function TEpollConnection._UpdateIoEvent(const Inst:TEpollCrossSocket; const AIoEvents: TIoEvents): Boolean;
var
  LEvent: TEPoll_Event;
begin
  FIoEvents := AIoEvents;

  if (FIoEvents = []) or IsClosed then Exit(False);

  LEvent.Events := EPOLLET or EPOLLONESHOT;
  LEvent.Data.u64 := Self.UID;

  if _ReadEnabled then
    LEvent.Events := LEvent.Events or EPOLLIN;

  if _WriteEnabled then
    LEvent.Events := LEvent.Events or EPOLLOUT;

  Result := (epoll_ctl(Inst.FEpollHandle, FOpCode, Socket, @LEvent) >= 0);
  FOpCode := EPOLL_CTL_MOD;

  {$IFDEF Debug_Log}
  _Log('connection %.16x epoll_ctl socket=%d events=0x%.8x error %d', [UID, LEvent.Events, Socket, GetLastError]);
  {$ENDIF Debug_Log}
end;

function TEpollConnection._WriteEnabled: Boolean;
begin
  Result := (ieWrite in FIoEvents);
end;

{ *
  * TEpollCrossSocket.Create – initialise the idle lock.
}
constructor TEpollCrossSocket.Create(AIoThreads: Integer);
begin
  inherited;

  FIdleLock := TCritical.Create;
end;

destructor TEpollCrossSocket.Destroy;
begin
  DisposeObjectAndNil(FIdleLock);

  inherited;
end;

{ *
  * _OpenStopHandle – create an eventfd and add it to the epoll set for shutdown.
}
procedure TEpollCrossSocket._OpenStopHandle;
var
  LEvent: TEPoll_Event;
begin
  FStopHandle := eventfd(0, 0);
  // Do not use EPOLLET so that every thread sees the wake‑up.
  LEvent.Events := EPOLLIN;
  LEvent.Data.u64 := SHUTDOWN_FLAG;
  epoll_ctl(FEpollHandle, EPOLL_CTL_ADD, FStopHandle, @LEvent);
end;

{ *
  * _PostStopCommand – write a value to the eventfd to wake all epoll_wait calls.
}
procedure TEpollCrossSocket._PostStopCommand;
var
  LStuff: UInt64;
begin
  LStuff := 1;
  FileWrite(FStopHandle, LStuff, SizeOf(LStuff));
end;

procedure TEpollCrossSocket._CloseStopHandle;
begin
  FileClose(FStopHandle);
end;

{ *
  * _OpenIdleHandle – open /dev/null to have a spare file descriptor for EMFILE.
}
procedure TEpollCrossSocket._OpenIdleHandle;
begin
  FIdleHandle := FileOpen('/dev/null', fmOpenRead);
end;

procedure TEpollCrossSocket._CloseIdleHandle;
begin
  FileClose(FIdleHandle);
end;

{ *
  * _HandleAccept – called when EPOLLIN triggers on a listening socket.
  * Accepts all pending connections until EAGAIN or EMFILE.
}
procedure TEpollCrossSocket._HandleAccept(AListen: ICrossListen);
var
  LListen: ICrossListen;
  LConnection: ICrossConnection;
  LEpConnection: TEpollConnection;
  LSocket, LError: Integer;
  LListenSocket, LClientSocket: THandle;
  LSuccess: Boolean;
begin
  LListen := AListen;
  LListenSocket := LListen.Socket;
  {$IFDEF Debug_Log}
  _Log('[ACCEPT TRIGGER] ListenFd=%d', [LListenSocket]);
  {$ENDIF Debug_Log}

  while True do
  begin
    LSocket := TSocketAPI.Accept(LListenSocket, nil, nil);

    // Accept failed?
    if (LSocket < 0) then
    begin
      LError := GetLastError;

      // If out of file descriptors, release the idle handle, accept one more,
      // close it immediately (to drain the pending connection), then reopen the idle.
      if (LError = EMFILE) then
      begin
        FIdleLock.Lock;
        try
          _CloseIdleHandle;
          LSocket := TSocketAPI.Accept(LListenSocket, nil, nil);
          TSocketAPI.CloseSocket(LSocket);
          _OpenIdleHandle;
        finally
          FIdleLock.UnLock;
        end;
      end;

      Break; // no more ready connections
    end;

    // Check if the user allows this new connection (OnAccept event)
    if not TriggerAccept(AListen) then
      begin
        TSocketAPI.CloseSocket(LSocket);
        continue;
      end;

    LClientSocket := LSocket;
    TSocketAPI.SetNonBlock(LClientSocket, True);
    SetKeepAlive(LClientSocket);
    TSocketAPI.SetTcpNoDelay(LClientSocket, True);

    LConnection := CreateConnection(Self, LClientSocket, ctAccept);
    TriggerConnecting(LConnection);
    TriggerConnected(LConnection);

    // Arm the connection for read events only initially
    LEpConnection := LConnection as TEpollConnection;
    LEpConnection._Lock;
    try
      LSuccess := LEpConnection._UpdateIoEvent(Self, [ieRead]);
    finally
      LEpConnection._Unlock;
    end;

    if not LSuccess then
      LConnection.Close;
  end;
end;

{ *
  * _HandleConnect – called when EPOLLOUT triggers on a connecting socket.
  * Checks for errors, then marks the connection as connected.
}
procedure TEpollCrossSocket._HandleConnect(AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LEpConnection: TEpollConnection;
  LConnectCallback: TProc_ICrossConnection_Boolean;
begin
  LConnection := AConnection;
  {$IFDEF Debug_Log}
  _Log('[connect TRIGGER] socket:%d', [LConnection.Socket]);
  {$ENDIF Debug_Log}

  // If getpeername fails, connection failed
  if (TSocketAPI.GetError(LConnection.Socket) <> 0) then
  begin
    {$IFDEF Debug_Log}
    _LogLastOsError;
    {$ENDIF Debug_Log}
    LConnection.Close;
    Exit;
  end;

  LEpConnection := LConnection as TEpollConnection;

  LEpConnection._Lock;
  try
    LConnectCallback := LEpConnection.FConnectCallback;
    LEpConnection.FConnectCallback := nil; // consume the callback
  finally
    LEpConnection._Unlock;
  end;

  TriggerConnected(LConnection);

  if Assigned(LConnectCallback) then
    LConnectCallback(LConnection, True);
end;

{ *
  * _HandleRead – called when EPOLLIN triggers on a connection.
  * Reads data until EAGAIN or a full buffer.
}
procedure TEpollCrossSocket._HandleRead(AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LRcvd, LError: Integer;
begin
  LConnection := AConnection;
  {$IFDEF Debug_Log}
  _Log('[read TRIGGER] socket:%d', [LConnection.Socket]);
  {$ENDIF Debug_Log}

  while True do
  begin
    LRcvd := TSocketAPI.Recv(LConnection.Socket, FRecvBuf[0], RCV_BUF_SIZE);

    // Remote closed the connection
    if (LRcvd = 0) then
    begin
      {$IFDEF Debug_Log}
      _Log('connection=%.16x socket=%d read 0', [LConnection.UID, LConnection.Socket]);
      {$ENDIF Debug_Log}
      LConnection.Close;
      Exit;
    end;

    if (LRcvd < 0) then
    begin
      LError := GetLastError;

      if (LError = EINTR) then
        Continue
      else if (LError = EAGAIN) or (LError = EWOULDBLOCK) then
        Break
      else
      begin
        {$IFDEF Debug_Log}
        _Log('connection=%.16x socket=%d read error %d', [LConnection.UID, LConnection.Socket, GetLastError]);
        {$ENDIF Debug_Log}
        LConnection.Close;
        Exit;
      end;
    end;

    TriggerReceived(LConnection, @FRecvBuf[0], LRcvd);

    if (LRcvd < RCV_BUF_SIZE) then Break;
  end;
end;

{ *
  * _HandleWrite – called when EPOLLOUT triggers on a connection.
  * Sends the first item in the send queue; if more remain, re‑arm with write.
}
procedure TEpollCrossSocket._HandleWrite(AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LEpConnection: TEpollConnection;
  LSendItem: PSendItem;
  LCallback: TProc_ICrossConnection_Boolean;
  LSent: Integer;
begin
  LConnection := AConnection;
  LEpConnection := LConnection as TEpollConnection;

  {$IFDEF Debug_Log}
  _Log('[write TRIGGER] socket:%d', [LConnection.Socket]);
  {$ENDIF Debug_Log}

  LEpConnection._Lock;

  if (LEpConnection.FSendQueue.Num <= 0) then
  begin
    LEpConnection._Unlock;
    Exit;
  end;

  LSendItem := LEpConnection.FSendQueue.First^.Data;

  LSent := PosixSend(LConnection.Socket, LSendItem^.Data, LSendItem^.Size);

  // Fully sent
  if (LSent >= LSendItem^.Size) then
  begin
    LCallback := LSendItem^.Callback;

    if (LEpConnection.FSendQueue.Num > 0) then
      LEpConnection.FSendQueue.Next; // remove the sent item

    if (LEpConnection.FSendQueue.Num <= 0) then
      LEpConnection._UpdateIoEvent(Self, []); // no more data, disable write

    LEpConnection._Unlock;

    if Assigned(LCallback) then
      LCallback(LConnection, True);

    Exit;
  end;

  // Partial send: update the item and re‑arm
  if (LSent > 0) then
  begin
    dec(LSendItem^.Size, LSent);
    inc(LSendItem^.Data, LSent);
    LEpConnection._Unlock;
  end
  else if (LSent < 0) then
  begin
    LCallback := LSendItem.Callback;
    if (LEpConnection.FSendQueue.Num > 0) then
      LEpConnection.FSendQueue.Next;
    LEpConnection._Unlock;
    if Assigned(LCallback) then
      LCallback(LConnection, False);
  end;
end;

{ *
  * StartLoop – create epoll fd, start I/O threads, add stop event.
}
procedure TEpollCrossSocket.StartLoop;
var
  I: Integer;
begin
  if (FIoThreads <> nil) then Exit;

  _OpenIdleHandle;

  FEpollHandle := epoll_create(MAX_EVENT_COUNT);
  SetLength(FIoThreads, GetIoThreads);
  for I := 0 to Length(FIoThreads) - 1 do
    FIoThreads[I] := TIoEventThread.Create(Self);

  _OpenStopHandle;
end;

{ *
  * StopLoop – signal shutdown, wait for threads to finish.
}
procedure TEpollCrossSocket.StopLoop;
var
  I: Integer;
  LCurrentThreadID: TThreadID;
begin
  if (FIoThreads = nil) then Exit;

  CloseAll;
  while (FListensCount > 0) or (FConnectionsCount > 0) do Sleep(1); // wait for all to close

  _PostStopCommand;

  LCurrentThreadID := GetCurrentThreadId;
  for I := 0 to Length(FIoThreads) - 1 do
  begin
    if (FIoThreads[I].ThreadID = LCurrentThreadID) then
      raise ECrossSocket.Create('Cannot call StopLoop from within an I/O thread!');

    while FIoThreads[I].IO_Is_Busy do
      Check_Soft_Thread_Synchronize(10, False);
    DisposeObjectAndNil(FIoThreads[I]);
  end;
  FIoThreads := nil;

  FileClose(FEpollHandle);
  _CloseIdleHandle;
  _CloseStopHandle;
end;

{ *
  * Listen – bind and listen on one or more addresses (IPv4/IPv6).
  * For each successful address, create a TEpollListen and arm its read event.
}
procedure TEpollCrossSocket.Listen(const AHost: SystemString; APort: Word;
  const ACallback: TProc_ICrossListen_Boolean);
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LListenSocket: TSocket;
  LListen: ICrossListen;
  LEpListen: TEpollListen;
  LSuccess: Boolean;

  procedure _Failed;
  begin
    if Assigned(ACallback) then
      ACallback(nil, False);
  end;
var
  si__:Integer;
begin
  si__:=SizeOf(TEPoll_Event);

  FillChar(LHints, SizeOf(TRawAddrInfo), 0);

  LHints.ai_flags := AI_PASSIVE;
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LAddrInfo := TSocketAPI.GetAddrInfo(AHost, APort, LHints);
  if (LAddrInfo = nil) then
  begin
    _Failed;
    Exit;
  end;

  P := LAddrInfo;
  try
    while (LAddrInfo <> nil) do
    begin
      LListenSocket := TSocketAPI.NewSocket(LAddrInfo^.ai_family, LAddrInfo^.ai_socktype,
        LAddrInfo^.ai_protocol);
      if (LListenSocket = INVALID_HANDLE_VALUE) then
      begin
        _Failed;
        Exit;
      end;

      TSocketAPI.SetNonBlock(LListenSocket, True);
      TSocketAPI.SetReUseAddr(LListenSocket, True);

      if (LAddrInfo^.ai_family = AF_INET6) then
        TSocketAPI.SetSockOpt<Integer>(LListenSocket, IPPROTO_IPV6, IPV6_V6ONLY, 1);

      if (TSocketAPI.Bind(LListenSocket, LAddrInfo.ai_addr, LAddrInfo.ai_addrlen) < 0) then
      begin
        _LogLastOsError('bind');
        _Failed;
        Exit;
      end;

      if (TSocketAPI.Listen(LListenSocket) < 0) then
      begin
        _LogLastOsError('Listen');
        _Failed;
        Exit;
      end;

      LListen := CreateListen(Self, LListenSocket, LAddrInfo.ai_family,
        LAddrInfo.ai_socktype, LAddrInfo.ai_protocol);
      LEpListen := LListen as TEpollListen;

      LEpListen._Lock;
      try
        LSuccess := LEpListen._UpdateIoEvent(Self, [ieRead]);
      finally
        LEpListen._Unlock;
      end;

      if not LSuccess then
      begin
        _LogLastOsError('LEpListen._UpdateIoEvent');
        _Failed;
        Exit;
      end;

      TriggerListened(LListen);
      if Assigned(ACallback) then
        ACallback(LListen, True);

      // If APort=0, reuse the assigned port for subsequent addresses
      if (APort = 0) and (LAddrInfo.ai_next <> nil) then
        Psockaddr_in(LAddrInfo.ai_next.ai_addr).sin_port := LListen.LocalPort;

      LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;
end;

{ *
  * Connect – initiate an outbound connection. Uses non‑blocking connect and
  * arms the socket for EPOLLOUT to detect completion.
}
procedure TEpollCrossSocket.Connect(const AHost: SystemString; APort: Word;
  const ACallback: TProc_ICrossConnection_Boolean);

  procedure _Failed1;
  begin
    if Assigned(ACallback) then
      ACallback(nil, False);
  end;

  function _Connect(ASocket: THandle; AAddr: PRawAddrInfo): Boolean;
  var
    LConnection: ICrossConnection;
    LEpConnection: TEpollConnection;
  begin
    if (TSocketAPI.Connect(ASocket, AAddr^.ai_addr, AAddr^.ai_addrlen) = 0)
      or (GetLastError = EINPROGRESS) then
    begin
      LConnection := CreateConnection(Self, ASocket, ctConnect);
      TriggerConnecting(LConnection);
      LEpConnection := LConnection as TEpollConnection;

      LEpConnection._Lock;
      try
        LEpConnection.ConnectStatus := csConnecting;
        LEpConnection.FConnectCallback := ACallback;
        if not LEpConnection._UpdateIoEvent(Self, [ieWrite]) then
        begin
          LConnection.Close;
          Exit(False);
        end;
      finally
        LEpConnection._Unlock;
      end;
    end else
    begin
      TSocketAPI.CloseSocket(ASocket);
      if Assigned(ACallback) then
        ACallback(nil, False);
      Exit(False);
    end;

    Result := True;
  end;

var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LSocket: THandle;
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
      LSocket := TSocketAPI.NewSocket(LAddrInfo^.ai_family, LAddrInfo^.ai_socktype,
        LAddrInfo^.ai_protocol);
      if (LSocket = INVALID_HANDLE_VALUE) then
      begin
        _Failed1;
        Exit;
      end;

      TSocketAPI.SetNonBlock(LSocket, True);
      SetKeepAlive(LSocket);

      if _Connect(LSocket, LAddrInfo) then Exit;

      LAddrInfo := PRawAddrInfo(LAddrInfo^.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;

  _Failed1;
end;

{ *
  * CreateConnection – returns a TEpollConnection instance.
}
function TEpollCrossSocket.CreateConnection(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType): ICrossConnection;
begin
  Result := TEpollConnection.Create(AOwner, AClientSocket, AConnectType);
end;

{ *
  * CreateListen – returns a TEpollListen instance.
}
function TEpollCrossSocket.CreateListen(AOwner: ICrossSocket;
  AListenSocket: THandle; AFamily, ASockType, AProtocol: Integer): ICrossListen;
begin
  Result := TEpollListen.Create(AOwner, AListenSocket, AFamily, ASockType, AProtocol);
end;

{ *
  * Send – enqueue data into the connection's send queue and arm EPOLLOUT if needed.
}
procedure TEpollCrossSocket.Send(AConnection: ICrossConnection; ABuf: Pointer;
  ALen: Integer; const ACallback: TProc_ICrossConnection_Boolean);
var
  LEpConnection: TEpollConnection;
  LSendItem: PSendItem;
begin
  System.New(LSendItem);
  LSendItem.Data := ABuf;
  LSendItem.Size := ALen;
  LSendItem.Callback := ACallback;

  LEpConnection := AConnection as TEpollConnection;

  LEpConnection._Lock;
  try
    LEpConnection.FSendQueue.Add(LSendItem);

    // If write event is not already enabled, enable it (along with read)
    if not LEpConnection._WriteEnabled then
      LEpConnection._UpdateIoEvent(Self, [ieRead, ieWrite]);
  finally
    LEpConnection._Unlock;
  end;
end;

{ *
  * ProcessIoEvent – main I/O loop: call epoll_wait, dispatch events by UID.
  * Returns False when the shutdown event is received.
}
function TEpollCrossSocket.ProcessIoEvent: Boolean;
var
  LRet, I: Integer;
  LEvent: TEPoll_Event;
  LCrossUID: UInt64;
  LCrossTag: Byte;
  LListens: TCrossListens;
  LConnections: TCrossConnections;
  LListen: ICrossListen;
  LEpListen: TEpollListen;
  LConnection: ICrossConnection;
  LEpConnection: TEpollConnection;
  LSuccess: Boolean;
  LIoEvents: TIoEvents;
begin
  LRet := epoll_wait(FEpollHandle, @FEventList[0], MAX_EVENT_COUNT, -1);
  if (LRet < 0) then
  begin
    LRet := GetLastError;
    Exit(LRet = EINTR); // retry on signal interrupt
  end;

  for I := 0 to LRet - 1 do
  begin
    LEvent := FEventList[I];

    if (LEvent.Data.u64 = SHUTDOWN_FLAG) then Exit(False);

    LCrossUID := LEvent.Data.u64;
    LCrossTag := GetTagByUID(LCrossUID);
    LListen := nil;
    LConnection := nil;

  {$IFDEF Debug_Log}
    _Log('epoll events %.8x, uid %.16x, tag %d', [LEvent.Events, LEvent.Data.u64, LCrossTag]);
  {$ENDIF Debug_Log}
    case LCrossTag of
      UID_LISTEN:
        begin
          LListens := LockListens;
          try
            if not LListens.TryGetValue(LCrossUID, LListen) then
              Continue;
          finally
            UnlockListens;
          end;
        end;

      UID_CONNECTION:
        begin
          LConnections := LockConnections;
          try
            if not LConnections.TryGetValue(LCrossUID, LConnection)
              or (LConnection = nil) then
              Continue;
          finally
            UnlockConnections;
          end;
        end;
    else
      Continue;
    end;

    // ---- Handle listen event ----
    if (LListen <> nil) then
    begin
      if (LEvent.Events and EPOLLIN <> 0) then
        _HandleAccept(LListen);

      LEpListen := LListen as TEpollListen;
      LEpListen._Lock;
      LEpListen._UpdateIoEvent(Self, [ieRead]);
      LEpListen._Unlock;
    end
    else
    // ---- Handle connection event ----
    if (LConnection <> nil) then
    begin
      if (LEvent.Events and EPOLLIN <> 0) then
        begin
          LEpConnection := LConnection as TEpollConnection;
          LEpConnection._Lock;
          _HandleRead(LConnection);
          LEpConnection._Unlock;
        end;

      if (LEvent.Events and EPOLLOUT <> 0) then
      begin
        if (LConnection.ConnectStatus = csConnecting) then
          _HandleConnect(LConnection)
        else
          _HandleWrite(LConnection);
      end;

      // Re‑arm the connection with the appropriate events (read always, write if queue non‑empty)
      if not LConnection.IsClosed then
      begin
        LEpConnection := LConnection as TEpollConnection;
        LEpConnection._Lock;
        try
          if (LEpConnection.FSendQueue.Num > 0) then
            LIoEvents := [ieRead, ieWrite]
          else
            LIoEvents := [ieRead];
          LSuccess := LEpConnection._UpdateIoEvent(Self, LIoEvents);
        finally
          LEpConnection._Unlock;
        end;

        if not LSuccess then
          LConnection.Close;
      end;
    end;
  end;

  Result := True;
end;

{$ENDIF LINUX}

end.
 
