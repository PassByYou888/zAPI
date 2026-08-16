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
unit Z.FP.Net.CrossSocket.Kqueue;

{ *
  * CrossSocket.Kqueue – BSD/macOS/iOS implementation using kqueue.
  *
  * This unit provides an I/O engine based on the kqueue event notification
  * interface, which is used on BSD derivatives including macOS, iOS, and
  * FreeBSD. It supports edge‑triggered (EV_CLEAR) and one‑shot (EV_DISPATCH)
  * events for thread‑safe dispatching.
  *
  * Key design points:
  *   - Unlike epoll, kqueue allows multiple events per file descriptor (one
  *     per filter). So a socket can have separate EVFILT_READ and EVFILT_WRITE
  *     entries. This makes it easier to manage read and write independently.
  *   - EV_CLEAR (edge‑triggered) + EV_DISPATCH (auto‑disable) are used to
  *     ensure that after an event is delivered, it is removed from the queue
  *     until re‑armed. This avoids multiple threads handling the same event.
  *   - A send queue is used per connection to serialize writes, similar to epoll.
  *   - Connections are kept alive by reference counting; when a kevent is
  *     added, the connection's _AddRef is called, and _Release is called when
  *     the event fires. This prevents the connection from being freed while
  *     an event is pending.
  *   - For graceful shutdown, a pipe is used to wake up kevent() calls.
  *
  * Example:
  *   var
  *     sock: TKqueueCrossSocket;
  *   begin
  *     sock := TKqueueCrossSocket.Create(4);
  *     sock.OnConnected := procedure(...) ...;
  *     sock.Listen('::', 8080);
  *     while True do CheckThreadSynchronize(10);
  *   end;
}

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

{$if defined(BSD) or defined(MACOS) or defined(IOS)}
uses
  Z.Core,
  Z.PascalStrings,
  Z.UPascalStrings,
  Z.Status,
  SysUtils,
  Classes,
  {$IFDEF DELPHI}
    Posix.SysSocket,
    Posix.NetinetIn,
    Posix.UniStd,
    Posix.NetDB,
    Posix.Pthread,
    Posix.Errno,
  {$ELSE DELPHI}
    BaseUnix,
    Unix,
    Sockets,
    netdb,
    termio,
    bsd,
    ctypes,
  {$ENDIF DELPHI}
  Z.FP.Net.BSD.kqueue,
  Z.FP.Net.SocketAPI,
  Z.FP.Net.CrossSocket.Base;

{$ifdef fpc}
type
  TPipeDescriptors = packed record
    ReadDes: Integer;
    WriteDes: Integer;
  end;
  PPipeDescriptors = ^TPipeDescriptors;

const
  clib = 'c';
  EV_DISPATCH     = $0080;
  SO_NOSIGPIPE    = $1022;
  IPV6_V6ONLY     = 27;

function pipe(var PipeDes: TPipeDescriptors): Integer; cdecl; external clib name 'pipe';
function __write(Handle: Integer; Buffer: Pointer; Count: size_t): ssize_t; cdecl; external clib name 'write';
function __close(Handle: Integer): Integer; cdecl; external clib name 'close';
{$endif fpc}

type
  TKqueueCrossSocket = class;
  TIoEvent = (ieRead, ieWrite); // possible I/O events to monitor
  TIoEvents = set of TIoEvent;  // set of events (read/write)

  { *
    * TKqueueListen – kqueue‑specific listener. Manages read event only.
    * It registers the listening socket for EVFILT_READ so that accept()
    * can be called when a new connection arrives.
  }
  TKqueueListen = class(TAbstractCrossListen)
  private
    FLock: TCritical;          // protects event registration
    FIoEvents: TIoEvents;      // currently monitored events (only ieRead is used)
    procedure _Lock;
    procedure _Unlock;
    function _ReadEnabled: Boolean;
    function _UpdateIoEvent(const Inst:TKqueueCrossSocket; const AIoEvents: TIoEvents): Boolean;
  public
    constructor Create(AOwner: ICrossSocket; AListenSocket: THandle;
      AFamily, ASockType, AProtocol: Integer); override;
    destructor Destroy; override;
    function Get_Owner_: TKqueueCrossSocket;
  end;

  PSendItem = ^TSendItem;
  TSendItem = record
    Data: PByte;               // pointer to the data buffer to send
    Size: Integer;             // number of bytes in Data
    Callback: TProc_ICrossConnection_Boolean; // completion callback
  end;

  { *
    * TSendQueue – a queue of send items. Inherits from TBigList to reuse nodes.
    * It automatically frees the PSendItem when removed.
  }
  TSendQueue = class(TBigList<PSendItem>)
  protected
    procedure DoFree(var Data: PSendItem); override;
  end;

  { *
    * TKqueueConnection – kqueue‑specific connection.
    * Manages its own send queue and separate read/write events.
    * It holds a reference to the owner and uses reference counting to ensure
    * it stays alive while events are pending.
  }
  TKqueueConnection = class(TAbstractCrossConnection)
  private
    FLock: TCritical;
    FSendQueue: TSendQueue;              // pending send items
    FIoEvents: TIoEvents;                // currently monitored events
    FConnectCallback: TProc_ICrossConnection_Boolean; // callback for connect result
    procedure _Lock;
    procedure _Unlock;
    function _ReadEnabled: Boolean;
    function _WriteEnabled: Boolean;
    function _UpdateIoEvent(const Inst:TKqueueCrossSocket; const AIoEvents: TIoEvents): Boolean;
  public
    constructor Create(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType); override;
    destructor Destroy; override;
    procedure Close; override; // uses shutdown to trigger events
    function Get_Owner_: TKqueueCrossSocket;
  end;

  { *
    * TKqueueCrossSocket – main kqueue engine.
    *
    * Differences from epoll:
    *   - kqueue allows separate EVFILT_READ and EVFILT_WRITE entries per socket.
    *   - Reference counting is used because events can be outstanding; we
    *     increment the connection's ref count when adding an event and decrement
    *     when the event is delivered.
    *   - The stop mechanism uses a pipe (read end monitored by kevent).
  }
  TKqueueCrossSocket = class(TAbstractCrossSocket)
  private const
    MAX_EVENT_COUNT = 2048;          // max events per kevent() call
    SHUTDOWN_FLAG   = Pointer(-1);   // sentinel value in kevent data to signal stop
  private class threadvar
    FEventList: array [0..MAX_EVENT_COUNT-1] of TKEvent; // thread‑local event buffer
  private
    FKqueueHandle: THandle;          // kqueue file descriptor
    FIoThreads: TArray<TIoEventThread>; // I/O worker threads
    FIdleHandle: THandle;            // file handle to /dev/null, used for EMFILE recovery
    FIdleLock: TCritical;            // protects FIdleHandle
    FStopHandle: TPipeDescriptors;   // pipe for shutdown notification
    procedure _OpenStopHandle;
    procedure _PostStopCommand;
    procedure _CloseStopHandle;
    procedure _OpenIdleHandle;
    procedure _CloseIdleHandle;
    procedure _SetNoSigPipe(ASocket: THandle);
    procedure _HandleAccept(AListen: ICrossListen);
    procedure _HandleConnect(AConnection: ICrossConnection);
    procedure _HandleRead(AConnection: ICrossConnection);
    procedure _HandleWrite(AConnection: ICrossConnection);
  protected
    function CreateConnection(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType): ICrossConnection; override;
    function CreateListen(AOwner: ICrossSocket; AListenSocket: THandle;
      AFamily, ASockType, AProtocol: Integer): ICrossListen; override;
    procedure StartLoop; override;
    procedure StopLoop; override;
    procedure Listen(const AHost: SystemString; APort: Word;
      const ACallback: TProc_ICrossListen_Boolean = nil); override;
    procedure Connect(const AHost: SystemString; APort: Word;
      const ACallback: TProc_ICrossConnection_Boolean = nil); override;
    procedure Send(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer;
      const ACallback: TProc_ICrossConnection_Boolean = nil); override;
    function ProcessIoEvent: Boolean; override;
  public
    constructor Create(AIoThreads: Integer); override;
    destructor Destroy; override;
  end;

{$ifend}
implementation

{$if defined(BSD) or defined(MACOS) or defined(IOS)}

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

{$ENDIF FPC}

{$I Z.FP.Net.Posix.inc}

{ *
  * TKqueueListen.Create – initialises the listener with a new critical section.
}
constructor TKqueueListen.Create(AOwner: ICrossSocket; AListenSocket: THandle;
  AFamily, ASockType, AProtocol: Integer);
begin
  inherited;
  FLock := TCritical.Create;
end;

{ *
  * TKqueueListen.Destroy – frees the critical section.
}
destructor TKqueueListen.Destroy;
begin
  DisposeObjectAndNil(FLock);
  inherited;
end;

function TKqueueListen.Get_Owner_: TKqueueCrossSocket;
begin
  Result := Owner as TKqueueCrossSocket;
end;

procedure TKqueueListen._Lock;
begin
  FLock.Lock;
end;

function TKqueueListen._ReadEnabled: Boolean;
begin
  Result := (ieRead in FIoEvents);
end;

procedure TKqueueListen._Unlock;
begin
  FLock.UnLock;
end;

{ *
  * _UpdateIoEvent – (re)register the read event for this listener.
  * Uses EV_ADD|EV_ONESHOT|EV_CLEAR|EV_DISPATCH to get edge‑triggered,
  * one‑shot behaviour. If the listener is closed or no event is requested,
  * it returns False.
}
function TKqueueListen._UpdateIoEvent(const Inst:TKqueueCrossSocket; const AIoEvents: TIoEvents): Boolean;
var
  LCrossData: Pointer;
  LEvents: array [0..1] of TKEvent;
  N: Integer;
begin
  FIoEvents := AIoEvents;

  if (FIoEvents = []) or IsClosed then Exit(False);

  LCrossData := Pointer(Self);
  N := 0;

  if _ReadEnabled then
  begin
    EV_SET(@LEvents[N], Socket, EVFILT_READ,
      EV_ADD or EV_ONESHOT or EV_CLEAR or EV_DISPATCH, 0, 0, Pointer(LCrossData));
    Inc(N);
  end;

  if (N <= 0) then Exit(False);

  Result := (kevent(Inst.FKqueueHandle, @LEvents, N, nil, 0, nil) >= 0);

  {$IFDEF DEBUG}
  if not Result then
    _Log('listen %d kevent error %d', [Socket, GetLastError]);
  {$ENDIF}
end;

{ *
  * TSendQueue.DoFree – frees the PSendItem and its callback reference.
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
  * TKqueueConnection.Create – initialises send queue and lock.
}
constructor TKqueueConnection.Create(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType);
begin
  inherited;

  FSendQueue := TSendQueue.Create;
  FLock := TCritical.Create;
end;

{ *
  * TKqueueConnection.Destroy – flushes pending callbacks and frees resources.
}
destructor TKqueueConnection.Destroy;
var
  LConnection: ICrossConnection;
  LSendItem: PSendItem;
begin
  LConnection := Self;

  _Lock;
  try
    if Assigned(FConnectCallback) then
    begin
      FConnectCallback(LConnection, False);
      FConnectCallback := nil;
    end;

    if (FSendQueue.Count > 0) then
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

function TKqueueConnection.Get_Owner_: TKqueueCrossSocket;
begin
  Result := Owner as TKqueueCrossSocket;
end;

{ *
  * TKqueueConnection.Close – overridden to use shutdown instead of close.
  * This ensures that kqueue events are triggered (so the reference count
  * added when the event was registered can be released). Direct close
  * would remove the socket from kqueue without triggering, causing a leak.
}
procedure TKqueueConnection.Close;
begin
  if (_SetConnectStatus(csClosed) = csClosed) then Exit;

  // Shutdown triggers events in kqueue, which will cause the connection's
  // _Release to be called, freeing it later. Direct Close would remove the
  // socket from kqueue without triggering, causing a leak.
  TSocketAPI.Shutdown(Socket, 2);
end;

procedure TKqueueConnection._Lock;
begin
  FLock.Lock;
end;

function TKqueueConnection._ReadEnabled: Boolean;
begin
  Result := (ieRead in FIoEvents);
end;

procedure TKqueueConnection._Unlock;
begin
  FLock.UnLock;
end;

{ *
  * _UpdateIoEvent – register or modify read and/or write events.
  * Note: We increase the reference count for each event added; it will be
  * decreased when the event is delivered. This keeps the object alive.
}
function TKqueueConnection._UpdateIoEvent(const Inst:TKqueueCrossSocket; const AIoEvents: TIoEvents): Boolean;
var
  LCrossData: Pointer;
  LEvents: array [0..1] of TKEvent;
  N: Integer;
begin
  FIoEvents := AIoEvents;

  if (FIoEvents = []) or IsClosed then Exit(False);

  LCrossData := Pointer(Self);
  N := 0;

  if _ReadEnabled then
  begin
    Self._AddRef; // will be released in the event handler
    EV_SET(@LEvents[N], Socket, EVFILT_READ,
      EV_ADD or EV_ONESHOT or EV_CLEAR or EV_DISPATCH, 0, 0, Pointer(LCrossData));
    Inc(N);
  end;

  if _WriteEnabled then
  begin
    Self._AddRef;
    EV_SET(@LEvents[N], Socket, EVFILT_WRITE,
      EV_ADD or EV_ONESHOT or EV_CLEAR or EV_DISPATCH, 0, 0, Pointer(LCrossData));
    Inc(N);
  end;

  if (N <= 0) then Exit(False);

  Result := (kevent(Inst.FKqueueHandle, @LEvents, N, nil, 0, nil) >= 0);

  if not Result then
  begin
    {$IFDEF DEBUG}
    _Log('connection %d kevent error %d', [Socket, GetLastError]);
    {$ENDIF}

    // On failure, release the refs we just added
    while (N > 0) do
    begin
      Self._Release;
      Dec(N);
    end;
  end;
end;

function TKqueueConnection._WriteEnabled: Boolean;
begin
  Result := (ieWrite in FIoEvents);
end;

{ *
  * TKqueueCrossSocket.Create – initialises the idle lock.
}
constructor TKqueueCrossSocket.Create(AIoThreads: Integer);
begin
  inherited;

  FIdleLock := TCritical.Create;
end;

{ *
  * TKqueueCrossSocket.Destroy – frees the idle lock.
}
destructor TKqueueCrossSocket.Destroy;
begin
  DisposeObjectAndNil(FIdleLock);

  inherited;
end;

{ *
  * _OpenIdleHandle – opens /dev/null to have a spare file descriptor for EMFILE recovery.
}
procedure TKqueueCrossSocket._OpenIdleHandle;
begin
  FIdleHandle := FileOpen('/dev/null', fmOpenRead);
end;

{ *
  * _CloseIdleHandle – closes the idle file descriptor.
}
procedure TKqueueCrossSocket._CloseIdleHandle;
begin
  FileClose(FIdleHandle);
end;

{ *
  * _OpenStopHandle – creates a pipe and adds its read end to kqueue.
  * The read end is monitored for EVFILT_READ; when the pipe is written to,
  * kevent() will wake up and return the SHUTDOWN_FLAG.
}
procedure TKqueueCrossSocket._OpenStopHandle;
var
  LEvent: TKEvent;
begin
  pipe(FStopHandle);

  EV_SET(@LEvent, FStopHandle.ReadDes, EVFILT_READ,
    EV_ADD, 0, 0, SHUTDOWN_FLAG);
  kevent(FKqueueHandle, @LEvent, 1, nil, 0, nil);
end;

{ *
  * _PostStopCommand – writes a byte to the pipe to wake up all kevent() calls.
}
procedure TKqueueCrossSocket._PostStopCommand;
var
  LStuff: UInt64;
begin
  LStuff := 1;
  {$IFDEF DELPHI}Posix.UniStd.__write{$ELSE DELPHI}__write{$ENDIF DELPHI}(FStopHandle.WriteDes, @LStuff, SizeOf(LStuff));
end;

{ *
  * _CloseStopHandle – closes both ends of the stop pipe.
}
procedure TKqueueCrossSocket._CloseStopHandle;
begin
  {$IFDEF DELPHI}FileClose{$ELSE DELPHI}__close{$ENDIF DELPHI}(FStopHandle.ReadDes);
  {$IFDEF DELPHI}FileClose{$ELSE DELPHI}__close{$ENDIF DELPHI}(FStopHandle.WriteDes);
end;

{ *
  * _SetNoSigPipe – sets SO_NOSIGPIPE to avoid SIGPIPE on macOS/BSD.
  * This prevents the process from being killed when writing to a closed socket.
}
procedure TKqueueCrossSocket._SetNoSigPipe(ASocket: THandle);
begin
  TSocketAPI.SetSockOpt<Integer>(ASocket, SOL_SOCKET, SO_NOSIGPIPE, 1);
end;

{ *
  * _HandleAccept – accepts all pending connections on a listening socket.
  * It loops until accept() returns EAGAIN or an error. For each accepted
  * connection, it creates a TKqueueConnection and arms its read event.
}
procedure TKqueueCrossSocket._HandleAccept(AListen: ICrossListen);
var
  LListen: ICrossListen;
  LKqListen: TKqueueListen;
  LConnection: ICrossConnection;
  LKqConnection: TKqueueConnection;
  LSocket, LError: Integer;
  LListenSocket, LClientSocket: THandle;
  LSuccess: Boolean;
begin
  LListen := AListen;
  LListenSocket := LListen.Socket;

  while True do
  begin
    LSocket := TSocketAPI.Accept(LListenSocket, nil, nil);

    if (LSocket < 0) then
    begin
      LError := GetLastError;

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

    if not TriggerAccept(AListen) then
      begin
        TSocketAPI.CloseSocket(LSocket);
        continue;
      end;

    LClientSocket := LSocket;
    TSocketAPI.SetNonBlock(LClientSocket, True);
    SetKeepAlive(LClientSocket);
    TSocketAPI.SetTcpNoDelay(LClientSocket, True);
    _SetNoSigPipe(LClientSocket);

    LConnection := CreateConnection(Self, LClientSocket, ctAccept);
    TriggerConnecting(LConnection);
    TriggerConnected(LConnection);

    LKqConnection := LConnection as TKqueueConnection;
    LKqConnection._Lock;
    try
      LSuccess := LKqConnection._UpdateIoEvent(Self, [ieRead]);
    finally
      LKqConnection._Unlock;
    end;

    if not LSuccess then
      TriggerDisconnected(LConnection);
  end;

  // Re‑arm listener
  LKqListen := LListen as TKqueueListen;
  LKqListen._Lock;
  LKqListen._UpdateIoEvent(Self, [ieRead]);
  LKqListen._Unlock;
end;

{ *
  * _HandleConnect – completion handler for a connect attempt.
  * Checks the socket error, then arms read event and fires the connect callback.
}
procedure TKqueueCrossSocket._HandleConnect(AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LKqConnection: TKqueueConnection;
  LConnectCallback: TProc_ICrossConnection_Boolean;
  LSuccess: Boolean;
begin
  LConnection := AConnection;

  if (TSocketAPI.GetError(LConnection.Socket) <> 0) then
  begin
    TriggerDisconnected(LConnection);
    Exit;
  end;

  LKqConnection := LConnection as TKqueueConnection;

  LKqConnection._Lock;
  try
    LConnectCallback := LKqConnection.FConnectCallback;
    LKqConnection.FConnectCallback := nil;
    LSuccess := LKqConnection._UpdateIoEvent(Self, [ieRead]);
  finally
    LKqConnection._Unlock;
  end;

  if LSuccess then
    TriggerConnected(LConnection)
  else
    TriggerDisconnected(LConnection);

  if Assigned(LConnectCallback) then
    LConnectCallback(LConnection, LSuccess);
end;

{ *
  * _HandleRead – reads data from a connection until EAGAIN or a full buffer.
  * Then re‑arms the read event.
}
procedure TKqueueCrossSocket._HandleRead(AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LRcvd, LError: Integer;
  LKqConnection: TKqueueConnection;
  LSuccess: Boolean;
begin
  LConnection := AConnection;

  while True do
  begin
    LRcvd := TSocketAPI.Recv(LConnection.Socket, FRecvBuf[0], RCV_BUF_SIZE);

    if (LRcvd = 0) then // remote closed the connection
    begin
      TriggerDisconnected(LConnection);
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
        TriggerDisconnected(LConnection);
        Exit;
      end;
    end;

    TriggerReceived(LConnection, @FRecvBuf[0], LRcvd);

    if (LRcvd < RCV_BUF_SIZE) then Break;
  end;

  LKqConnection := LConnection as TKqueueConnection;
  LKqConnection._Lock;
  try
    LSuccess := LKqConnection._UpdateIoEvent(Self, [ieRead]);
  finally
    LKqConnection._Unlock;
  end;

  if not LSuccess then
    TriggerDisconnected(LConnection);
end;

{ *
  * _HandleWrite – sends the first item from the send queue.
  * If the item is fully sent, it is removed and the next is scheduled.
  * If a partial send occurs, the item is updated and the write event is re‑armed.
}
procedure TKqueueCrossSocket._HandleWrite(AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LKqConnection: TKqueueConnection;
  LSendItem: PSendItem;
  LCallback: TProc_ICrossConnection_Boolean;
  LSent: Integer;
begin
  LConnection := AConnection;
  LKqConnection := LConnection as TKqueueConnection;

  LKqConnection._Lock;

  if (LKqConnection.FSendQueue.Count <= 0) then
  begin
    LKqConnection._Unlock;
    LKqConnection._UpdateIoEvent(Self, []);
    Exit;
  end;

  LSendItem := LKqConnection.FSendQueue.Items[0];

  LSent := PosixSend(LConnection.Socket, LSendItem.Data, LSendItem.Size);

  if (LSent >= LSendItem.Size) then // fully sent
  begin
    LCallback := LSendItem.Callback;

    if (LKqConnection.FSendQueue.Count > 0) then
      LKqConnection.FSendQueue.Next;

    if (LKqConnection.FSendQueue.Count <= 0) then
      LKqConnection._UpdateIoEvent(Self, []);

    LKqConnection._Unlock;

    if Assigned(LCallback) then
      LCallback(LConnection, True);

    Exit;
  end;

  if (LSent > 0) then // partial send
  begin
    Dec(LSendItem.Size, LSent);
    Inc(LSendItem.Data, LSent);

    LKqConnection._UpdateIoEvent(Self, [ieWrite]);
    LKqConnection._Unlock;
  end
  else if (LSent < 0) then // send error
  begin
    LCallback := LSendItem.Callback;
    if (LKqConnection.FSendQueue.Count > 0) then
      LKqConnection.FSendQueue.Next;
    LKqConnection._Unlock;
    if Assigned(LCallback) then
      LCallback(LConnection, False);
  end;
end;

{ *
  * StartLoop – creates kqueue, starts I/O threads, and opens the stop pipe.
}
procedure TKqueueCrossSocket.StartLoop;
var
  I: Integer;
begin
  if (FIoThreads <> nil) then Exit;

  _OpenIdleHandle;

  FKqueueHandle := kqueue();
  SetLength(FIoThreads, GetIoThreads);
  for I := 0 to Length(FIoThreads) - 1 do
    FIoThreads[i] := TIoEventThread.Create(Self);

  _OpenStopHandle;
end;

{ *
  * StopLoop – signals all threads to stop and waits for them to finish.
  * Also closes all sockets and cleans up handles.
}
procedure TKqueueCrossSocket.StopLoop;
var
  I: Integer;
  LCurrentThreadID: TThreadID;
begin
  if (FIoThreads = nil) then Exit;

  CloseAll;
  while (ListensCount > 0) or (ConnectionsCount > 0) do Sleep(1);

  _PostStopCommand;

  LCurrentThreadID := GetCurrentThreadId;
  for I := 0 to Length(FIoThreads) - 1 do
  begin
    if (FIoThreads[I].ThreadID = LCurrentThreadID) then
      raise ECrossSocket.Create('Cannot call StopLoop from I/O thread!');

    while FIoThreads[I].IO_Is_Busy do
      Check_Soft_Thread_Synchronize(10, False);
    DisposeObjectAndNil(FIoThreads[I]);
  end;
  FIoThreads := nil;

  FileClose(FKqueueHandle);
  _CloseIdleHandle;
  _CloseStopHandle;
end;

{ *
  * Connect – initiates a non‑blocking connect and arms the write event.
}
procedure TKqueueCrossSocket.Connect(const AHost: SystemString; APort: Word;
  const ACallback: TProc_ICrossConnection_Boolean);

  procedure _Failed1;
  begin
    if Assigned(ACallback) then
      ACallback(nil, False);
  end;

  function _Connect(ASocket: THandle; AAddr: PRawAddrInfo): Boolean;
  var
    LConnection: ICrossConnection;
    LKqConnection: TKqueueConnection;
  begin
    if (TSocketAPI.Connect(ASocket, AAddr.ai_addr, AAddr.ai_addrlen) = 0)
      or (GetLastError = EINPROGRESS) then
    begin
      LConnection := CreateConnection(Self, ASocket, ctConnect);
      TriggerConnecting(LConnection);
      LKqConnection := LConnection as TKqueueConnection;

      LKqConnection._Lock;
      try
        LKqConnection.ConnectStatus := csConnecting;
        LKqConnection.FConnectCallback := ACallback;
        if not LKqConnection._UpdateIoEvent(Self, [ieWrite]) then
        begin
          TriggerDisconnected(LConnection);
          Exit(False);
        end;
      finally
        LKqConnection._Unlock;
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
      LSocket := TSocketAPI.NewSocket(LAddrInfo.ai_family, LAddrInfo.ai_socktype,
        LAddrInfo.ai_protocol);
      if (LSocket = INVALID_HANDLE_VALUE) then
      begin
        _Failed1;
        Exit;
      end;

      TSocketAPI.SetNonBlock(LSocket, True);
      SetKeepAlive(LSocket);
      _SetNoSigPipe(LSocket);

      if _Connect(LSocket, LAddrInfo) then Exit;

      LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;

  _Failed1;
end;

{ *
  * CreateConnection – factory method returning a TKqueueConnection instance.
}
function TKqueueCrossSocket.CreateConnection(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType): ICrossConnection;
begin
  Result := TKqueueConnection.Create(AOwner, AClientSocket, AConnectType);
end;

{ *
  * CreateListen – factory method returning a TKqueueListen instance.
}
function TKqueueCrossSocket.CreateListen(AOwner: ICrossSocket;
  AListenSocket: THandle; AFamily, ASockType, AProtocol: Integer): ICrossListen;
begin
  Result := TKqueueListen.Create(AOwner, AListenSocket, AFamily, ASockType, AProtocol);
end;

{ *
  * Listen – binds to the given address and port, creates a listener, and arms its read event.
}
procedure TKqueueCrossSocket.Listen(const AHost: SystemString; APort: Word;
  const ACallback: TProc_ICrossListen_Boolean);
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LListenSocket: THandle;
  LListen: ICrossListen;
  LKqListen: TKqueueListen;
  LSuccess: Boolean;

  procedure _Failed;
  begin
    if Assigned(ACallback) then
      ACallback(nil, False);
  end;

begin
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
      LListenSocket := TSocketAPI.NewSocket(LAddrInfo.ai_family, LAddrInfo.ai_socktype,
        LAddrInfo.ai_protocol);
      if (LListenSocket = INVALID_HANDLE_VALUE) then
      begin
        _Failed;
        Exit;
      end;

      TSocketAPI.SetNonBlock(LListenSocket, True);
      TSocketAPI.SetReUseAddr(LListenSocket, True);

      if (LAddrInfo.ai_family = AF_INET6) then
        TSocketAPI.SetSockOpt<Integer>(LListenSocket, IPPROTO_IPV6, IPV6_V6ONLY, 1);

      if (TSocketAPI.Bind(LListenSocket, LAddrInfo.ai_addr, LAddrInfo.ai_addrlen) < 0)
        or (TSocketAPI.Listen(LListenSocket) < 0) then
      begin
        _Failed;
        Exit;
      end;

      LListen := CreateListen(Self, LListenSocket, LAddrInfo.ai_family,
        LAddrInfo.ai_socktype, LAddrInfo.ai_protocol);
      LKqListen := LListen as TKqueueListen;

      LKqListen._Lock;
      try
        LSuccess := LKqListen._UpdateIoEvent(Self, [ieRead]);
      finally
        LKqListen._Unlock;
      end;

      if not LSuccess then
      begin
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
  * Send – enqueues data for transmission and arms the write event if not already.
}
procedure TKqueueCrossSocket.Send(AConnection: ICrossConnection; ABuf: Pointer;
  ALen: Integer; const ACallback: TProc_ICrossConnection_Boolean);
var
  LKqConnection: TKqueueConnection;
  LSendItem: PSendItem;
begin
  System.New(LSendItem);
  LSendItem.Data := ABuf;
  LSendItem.Size := ALen;
  LSendItem.Callback := ACallback;

  LKqConnection := AConnection as TKqueueConnection;

  LKqConnection._Lock;
  try
    LKqConnection.FSendQueue.Add(LSendItem);

    if not LKqConnection._WriteEnabled then
      LKqConnection._UpdateIoEvent(Self, [ieWrite]);
  finally
    LKqConnection._Unlock;
  end;
end;

{ *
  * ProcessIoEvent – main I/O loop: call kevent, dispatch events by object pointer.
  * Important: after getting an event, we call _Release on the connection
  * to balance the _AddRef done when the event was added.
}
function TKqueueCrossSocket.ProcessIoEvent: Boolean;
var
  LRet, I: Integer;
  LEvent: TKEvent;
  LCrossData: TCrossData;
  LListen: ICrossListen;
  LConnection: ICrossConnection;
begin
  LRet := kevent(FKqueueHandle, nil, 0, @FEventList[0], MAX_EVENT_COUNT, nil);
  if (LRet < 0) then
  begin
    LRet := GetLastError;
    Exit(LRet = EINTR); // retry on signal interrupt
  end;

  for I := 0 to LRet - 1 do
  begin
    LEvent := FEventList[I];

    if (LEvent.uData = SHUTDOWN_FLAG) then Exit(False);

    if (LEvent.uData = nil) then Continue;

    LCrossData := TCrossData(LEvent.uData);

    if (LCrossData is TKqueueListen) then
      LListen := LCrossData as ICrossListen
    else
      LListen := nil;

    if (LCrossData is TKqueueConnection) then
      LConnection := LCrossData as ICrossConnection
    else
      LConnection := nil;

    if (LListen <> nil) then
    begin
      if (LEvent.Filter = EVFILT_READ) then
        _HandleAccept(LListen);
    end else
    if (LConnection <> nil) then
    begin
      LConnection._Release; // balance the addref from _UpdateIoEvent

      if (LEvent.Filter = EVFILT_READ) then
        _HandleRead(LConnection)
      else if (LEvent.Filter = EVFILT_WRITE) then
      begin
        if (LConnection.ConnectStatus = csConnecting) then
          _HandleConnect(LConnection)
        else
          _HandleWrite(LConnection);
      end;
    end;
  end;

  Result := True;
end;

{$ifend}

end.
 
