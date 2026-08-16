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
{ *
  * Client.CrossSocket – Client‑side bridge from Z.FP.Net.CrossSocket to Z.Net.
  *
  * This unit provides a concrete client implementation that wraps the
  * cross‑platform asynchronous I/O engine (TCrossSocket) and adapts it to
  * the Z.Net framework's TZNet_Client class hierarchy.
  *
  * The client uses a global connection pool (TGlobalCrossSocketClientPool)
  * that can be shared by multiple client instances, reducing the overhead
  * of creating separate I/O threads for each client. Each client instance
  * gets its own TCrossSocketClient_PeerIO when a connection is established.
  *
  * It supports both synchronous (blocking) and asynchronous connection
  * attempts, with automatic reconnection capability, and integrates with
  * the Z.Net framework's command sending and receiving mechanisms.
  *
  * Example (synchronous connect and send):
  *   var
  *     client: TZNet_Client_FP_CrossSocket;
  *   begin
  *     client := TZNet_Client_FP_CrossSocket.Create;
  *     if client.Connect('127.0.0.1', 8080) then
  *     begin
  *       client.SendConsoleCmd('ping', 'hello');
  *       while client.Connected do
  *       begin
  *         client.Progress;
  *         CheckThreadSynchronize(10);
  *       end;
  *     end;
  *   end;
  *
  * Example (asynchronous connect with callback):
  *   var
  *     client: TZNet_Client_FP_CrossSocket;
  *   begin
  *     client := TZNet_Client_FP_CrossSocket.Create;
  *     client.AsyncConnectC('127.0.0.1', 8080,
  *       procedure(Success: Boolean)
  *       begin
  *         if Success then
  *           // connected
  *       end);
  *     while True do
  *     begin
  *       client.Progress;
  *       CheckThreadSynchronize(10);
  *     end;
  *   end;
}
unit Z.FP.Net.Client.CrossSocket;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses SysUtils, Classes,
  Z.FP.Net.CrossSocket, Z.FP.Net.SocketAPI, Z.FP.Net.CrossSocket.Base,
  Z.PascalStrings,
  Z.FP.Net.Server.CrossSocket,
  Z.Net, Z.Core, Z.UnicodeMixedLib, Z.MemoryStream,
  Z.Notify;

type
  TZNet_Client_FP_CrossSocket = class;

  { *
    * TCrossSocketClient_PeerIO – Per‑connection IO handler for the CrossSocket client.
    *
    * Inherits from TCrossSocketServer_PeerIO (which provides send buffering)
    * and adds a back‑reference to the owning client instance. When the
    * underlying connection is closed, it notifies the client.
    *
    * @Field OwnerClient: The client instance that owns this IO.
  }
  TCrossSocketClient_PeerIO = class(TCrossSocketServer_PeerIO)
  public
    OwnerClient: TZNet_Client_FP_CrossSocket;
    procedure CreateAfter; override;
    destructor Destroy; override;
    procedure Disconnect; override;
  end;

  { *
    * TZNet_Client_FP_CrossSocket – The main CrossSocket‑based TCP client.
    *
    * This class wraps a global connection pool (TGlobalCrossSocketClientPool)
    * and provides methods to connect synchronously or asynchronously.
    * Each client instance holds a reference to its PeerIO (ClientIOIntf)
    * and manages connection state and asynchronous callback notifications.
    *
    * @Field ClientIOIntf: The PeerIO object for the current connection.
    * @Field FOnAsyncConnectNotify_C/M/P: Callbacks for async connect result.
  }
  TZNet_Client_FP_CrossSocket = class(TZNet_Client)
  private
    ClientIOIntf: TCrossSocketClient_PeerIO;

    FOnAsyncConnectNotify_C: TOnState_C;
    FOnAsyncConnectNotify_M: TOnState_M;
    FOnAsyncConnectNotify_P: TOnState_P;

    // fixed DCC < XE8
    procedure AsyncConnect__(addr: SystemString; Port: Word; OnResultCall: TOnState_C; OnResultMethod: TOnState_M; OnResultProc: TOnState_P);
  protected
    procedure DoConnected(Sender: TPeerIO); override;
    procedure DoDisconnect(Sender: TPeerIO); override;
  public
    constructor Create; override;
    destructor Destroy; override;

    procedure TriggerDoConnectFailed; override;
    procedure TriggerDoConnectFinished; override;

    function Connected: Boolean; override;
    function ClientIO: TPeerIO; override;
    procedure Progress; override;

    procedure AsyncConnect(addr: SystemString; Port: Word); overload;
    procedure AsyncConnectC(addr: SystemString; Port: Word; const OnResult: TOnState_C); overload; override;
    procedure AsyncConnectM(addr: SystemString; Port: Word; const OnResult: TOnState_M); overload; override;
    procedure AsyncConnectP(addr: SystemString; Port: Word; const OnResult: TOnState_P); overload; override;

    function Connect(addr: SystemString; Port: Word): Boolean; overload; override;
    function Connect(Host: SystemString; Port: SystemString): Boolean; overload;
    procedure Disconnect; override;
  end;

  { *
    * TGlobalCrossSocketClientPool – Global pool that manages the underlying
    * CrossSocket engine and dispatches connection results to client instances.
    *
    * A single CrossSocket driver is shared across all client instances,
    * reducing resource usage. The pool handles the actual connection attempts
    * and creates a PeerIO object for each successful connection.
    *
    * @Field driver: The underlying CrossSocket engine.
    * @Field AutoReconnect: If True, the pool will automatically retry
    *        connections on failure.
    * @Field LastCompleted, LastResult, LastConnection: Used internally for
    *        synchronous connection attempts.
  }
  TGlobalCrossSocketClientPool = class
  private
    LastCompleted, LastResult: Boolean;
    LastConnection: ICrossConnection;
  public
    driver: TDriverEngine;
    AutoReconnect: Boolean;

    constructor Create;
    destructor Destroy; override;

    procedure CloseAllConnection;

    procedure DoDisconnect(Sender: TCore_Object; AConnection: ICrossConnection);
    procedure DoReceived(Sender: TCore_Object; AConnection: ICrossConnection; aBuf: Pointer; ALen: Integer);
    procedure DoSendBuffResult(AConnection: ICrossConnection; ASuccess: Boolean);

    procedure Do_Connect_Backcall_(AConnection: ICrossConnection; ASuccess: Boolean);
    function BuildConnect(addr: SystemString; Port: Word; BuildIntf: TZNet_Client_FP_CrossSocket): Boolean;
    procedure BuildAsyncConnect(addr: SystemString; Port: Word; BuildIntf: TZNet_Client_FP_CrossSocket);
  end;

  { *
    * TAsync_Connect_Backcall_Bridge_ – Bridge that captures the asynchronous
    * connect result and creates the PeerIO object on success, or triggers
    * reconnection/error handling on failure.
    *
    * @Field ClientPool: The pool that initiated the connection.
    * @Field addr, Port: The target address used.
    * @Field BuildIntf: The client instance that requested the connection.
  }
  TAsync_Connect_Backcall_Bridge_ = class
  public
    ClientPool: TGlobalCrossSocketClientPool;
    addr: SystemString;
    Port: Word;
    BuildIntf: TZNet_Client_FP_CrossSocket;
    procedure Do_Async_Connect_Bakcall_(AConnection: ICrossConnection; ASuccess: Boolean);
  end;

var
  Global_CrossSocket_ClientPool: TGlobalCrossSocketClientPool = nil;
  CrossSocket_Instance_Num: TAtomInt;

implementation

function ClientPool: TGlobalCrossSocketClientPool;
{ *
  * Returns the global client pool instance, creating it if necessary.
  * This is a lazy initialisation to avoid creating the pool until it is
  * actually needed.
}
begin
  if Global_CrossSocket_ClientPool = nil then
    begin
      Global_CrossSocket_ClientPool := TGlobalCrossSocketClientPool.Create;
      TCompute.Sleep(100);
    end;
  Result := Global_CrossSocket_ClientPool;
end;

procedure TCrossSocketClient_PeerIO.CreateAfter;
{ *
  * Initialises the OwnerClient field to nil after the base constructor.
}
begin
  inherited CreateAfter;
  OwnerClient := nil;
end;

destructor TCrossSocketClient_PeerIO.Destroy;
{ *
  * On destruction, if OwnerClient is set, it calls DoDisconnect on the
  * client to clean up the client's reference to this IO, then clears the
  * reference and proceeds with base destruction.
}
begin
  if OwnerClient <> nil then
    begin
      OwnerClient.DoDisconnect(Self);
      OwnerClient.ClientIOIntf := nil;
    end;
  OwnerClient := nil;
  inherited Destroy;
end;

procedure TCrossSocketClient_PeerIO.Disconnect;
{ *
  * Overrides Disconnect to notify the owner client that the connection is
  * closing, and clears the client's IO reference before proceeding.
}
begin
  if OwnerClient <> nil then
    begin
      OwnerClient.DoDisconnect(Self);
      OwnerClient.ClientIOIntf := nil;
    end;
  OwnerClient := nil;
  inherited Disconnect;
end;

procedure TZNet_Client_FP_CrossSocket.AsyncConnect__(addr: SystemString; Port: Word; OnResultCall: TOnState_C; OnResultMethod: TOnState_M; OnResultProc: TOnState_P);
{ *
  * Internal helper for all asynchronous connection overloads.
  * It stores the appropriate callback and delegates to the global pool's
  * BuildAsyncConnect method.
  *
  * @Param addr: Target address.
  * @Param Port: Target port.
  * @Param OnResultCall: C‑style callback.
  * @Param OnResultMethod: Method callback.
  * @Param OnResultProc: Nested/reference callback.
}
begin
  FOnAsyncConnectNotify_C := OnResultCall;
  FOnAsyncConnectNotify_M := OnResultMethod;
  FOnAsyncConnectNotify_P := OnResultProc;

  ClientPool.BuildAsyncConnect(addr, Port, Self);
end;

procedure TZNet_Client_FP_CrossSocket.DoConnected(Sender: TPeerIO);
{ *
  * Called when the connection is established. In this client, this event
  * is triggered by the pool after the PeerIO is created and attached.
  * Forwards to the inherited method.
}
begin
  inherited DoConnected(Sender);
end;

procedure TZNet_Client_FP_CrossSocket.DoDisconnect(Sender: TPeerIO);
{ *
  * Called when the connection is closed. Forwards to inherited.
}
begin
  inherited DoDisconnect(Sender);
end;

constructor TZNet_Client_FP_CrossSocket.Create;
{ *
  * Creates a client instance. Increments the global instance counter
  * (CrossSocket_Instance_Num) to track the number of active clients.
  * The actual CrossSocket engine is shared via the global pool.
}
begin
  inherited Create;
  CrossSocket_Instance_Num.UnLock(CrossSocket_Instance_Num.LockP^ + 1);
  FOnAsyncConnectNotify_C := nil;
  FOnAsyncConnectNotify_M := nil;
  FOnAsyncConnectNotify_P := nil;
  name := 'Cross-Socket-Client';
end;

destructor TZNet_Client_FP_CrossSocket.Destroy;
{ *
  * Destroys the client. Disconnects first, then decrements the instance
  * counter. When the counter reaches zero, the global client pool is
  * destroyed.
}
begin
  Disconnect;
  CrossSocket_Instance_Num.UnLock(CrossSocket_Instance_Num.LockP^ - 1);
  if CrossSocket_Instance_Num.V <= 0 then
      DisposeObjectAndNil(Global_CrossSocket_ClientPool);
  inherited Destroy;
end;

procedure TZNet_Client_FP_CrossSocket.TriggerDoConnectFailed;
{ *
  * Called when an asynchronous connection attempt fails.
  * Invokes the stored callback (if any) with False, then clears it.
}
begin
  inherited TriggerDoConnectFailed;

  try
    if Assigned(FOnAsyncConnectNotify_C) then
        FOnAsyncConnectNotify_C(False)
    else if Assigned(FOnAsyncConnectNotify_M) then
        FOnAsyncConnectNotify_M(False)
    else if Assigned(FOnAsyncConnectNotify_P) then
        FOnAsyncConnectNotify_P(False);
  except
  end;

  FOnAsyncConnectNotify_C := nil;
  FOnAsyncConnectNotify_M := nil;
  FOnAsyncConnectNotify_P := nil;
end;

procedure TZNet_Client_FP_CrossSocket.TriggerDoConnectFinished;
{ *
  * Called when an asynchronous connection attempt succeeds.
  * Invokes the stored callback with True, then clears it.
}
begin
  inherited TriggerDoConnectFinished;

  try
    if Assigned(FOnAsyncConnectNotify_C) then
        FOnAsyncConnectNotify_C(True)
    else if Assigned(FOnAsyncConnectNotify_M) then
        FOnAsyncConnectNotify_M(True)
    else if Assigned(FOnAsyncConnectNotify_P) then
        FOnAsyncConnectNotify_P(True);
  except
  end;

  FOnAsyncConnectNotify_C := nil;
  FOnAsyncConnectNotify_M := nil;
  FOnAsyncConnectNotify_P := nil;
end;

function TZNet_Client_FP_CrossSocket.Connected: Boolean;
{ *
  * Returns True if the client currently has an active connection and the
  * PeerIO reports as connected.
}
begin
  Result := (ClientIO <> nil) and (ClientIO.Connected);
end;

function TZNet_Client_FP_CrossSocket.ClientIO: TPeerIO;
{ *
  * Returns the current PeerIO object for this client.
}
begin
  Result := ClientIOIntf;
end;

procedure TZNet_Client_FP_CrossSocket.Progress;
{ *
  * Drives the client's network engine. Calls inherited Progress, which
  * will process incoming/outgoing data and update the connection state.
}
begin
  inherited Progress;
end;

procedure TZNet_Client_FP_CrossSocket.AsyncConnect(addr: SystemString; Port: Word);
{ *
  * Initiates an asynchronous connection without a callback.
  * The connection result can be checked via the Connected property later.
}
begin
  FOnAsyncConnectNotify_C := nil;
  FOnAsyncConnectNotify_M := nil;
  FOnAsyncConnectNotify_P := nil;

  ClientPool.BuildAsyncConnect(addr, Port, Self);
end;

procedure TZNet_Client_FP_CrossSocket.AsyncConnectC(addr: SystemString; Port: Word; const OnResult: TOnState_C);
{ *
  * Asynchronous connect with a C‑style callback.
  * @Param addr: Target address.
  * @Param Port: Target port.
  * @Param OnResult: Callback receiving True on success, False on failure.
}
begin
  AsyncConnect__(addr, Port, OnResult, nil, nil);
end;

procedure TZNet_Client_FP_CrossSocket.AsyncConnectM(addr: SystemString; Port: Word; const OnResult: TOnState_M);
{ *
  * Asynchronous connect with a method callback.
}
begin
  AsyncConnect__(addr, Port, nil, OnResult, nil);
end;

procedure TZNet_Client_FP_CrossSocket.AsyncConnectP(addr: SystemString; Port: Word; const OnResult: TOnState_P);
{ *
  * Asynchronous connect with a nested/reference callback.
}
begin
  AsyncConnect__(addr, Port, nil, nil, OnResult);
end;

function TZNet_Client_FP_CrossSocket.Connect(addr: SystemString; Port: Word): Boolean;
{ *
  * Synchronous (blocking) connection attempt.
  * It delegates to the global pool's BuildConnect, which waits (with
  * timeout) for the connection to complete or fail, then returns the
  * final connection state.
  * @Param addr: Target address.
  * @Param Port: Target port.
  * @Returns: True if the connection was established successfully.
}
begin
  Result := ClientPool.BuildConnect(addr, Port, Self);
end;

function TZNet_Client_FP_CrossSocket.Connect(Host: SystemString; Port: SystemString): Boolean;
{ *
  * Overloaded version that accepts the port as a SystemString (parsed to integer).
}
begin
  Result := Connect(Host, umlStrToInt(Port, 0));
end;

procedure TZNet_Client_FP_CrossSocket.Disconnect;
{ *
  * Disconnects the client by closing the PeerIO if it exists, and clears
  * any pending asynchronous connection callbacks.
}
begin
  if Connected then
    begin
      ClientIO.Disconnect;
    end;

  FOnAsyncConnectNotify_C := nil;
  FOnAsyncConnectNotify_M := nil;
  FOnAsyncConnectNotify_P := nil;
end;

constructor TGlobalCrossSocketClientPool.Create;
{ *
  * Creates the global pool. Instantiates a TDriverEngine (CrossSocket)
  * with a number of I/O threads based on the debug mode or the system's
  * parallel granularity. Sets up the event handlers for disconnection
  * and received data.
}
begin
  inherited Create;
  driver := TDriverEngine.Create(
{$IFDEF DEBUG}
    2
{$ELSE DEBUG}
    Z.Core.Get_Parallel_Granularity
{$ENDIF DEBUG}
    );
  driver.OnDisconnected := DoDisconnect;
  driver.OnReceived := DoReceived;

  AutoReconnect := False;
end;

destructor TGlobalCrossSocketClientPool.Destroy;
{ *
  * Destroys the pool. Disconnects all connections, synchronises the soft
  * thread queue, and frees the driver.
}
begin
  try
      ICrossSocket(driver).DisconnectAll;
  except
  end;
  // CrossSocket使用了RTL的Synchronize机制,这是兼容UI的机制,在服务器领域这是非常蛋疼的东西
  // soft_synchronize_technology是Synchronize硬件仿真技术,用于DLL和静态库使用独立线程仿RTL真主线程,
  // 使用soft_synchronize_technology系技术,必须非常小心,同步队列一旦出问题都是传导型的问题
  // 如果开启了soft_synchronize_technology,这里必须同步一下
  // 同步的作用是清理IO同步事件,以免卡端口,导致PostQueuedCompletionStatus消息过去卡队列
  // 无论Used_Soft_Synchronize是否开启Check_Soft_Thread_Synchronize都会清理掉当前的UI同步队列.
  Check_Soft_Thread_Synchronize(1, False);
  DisposeObject(driver);
  inherited Destroy;
end;

procedure TGlobalCrossSocketClientPool.CloseAllConnection;
{ *
  * Closes all active connections managed by the driver.
}
begin
  ICrossSocket(driver).CloseAllConnections;
end;

procedure TGlobalCrossSocketClientPool.DoDisconnect(Sender: TCore_Object; AConnection: ICrossConnection);
{ *
  * Called by the driver when a connection is disconnected.
  * If the connection has a TCrossSocketClient_PeerIO attached, it detaches
  * the IO from the connection, schedules its delayed destruction, and
  * clears the connection's UserObject.
}
var
  p_io: TCrossSocketClient_PeerIO;
begin
  if AConnection = nil then
      exit;
  if AConnection.UserObject is TCrossSocketClient_PeerIO then
    begin
      p_io := TCrossSocketClient_PeerIO(AConnection.UserObject);

      if p_io = nil then
          exit;

      p_io.IOInterface := nil;

      if p_io.OwnerClient <> nil then
        begin
          try
              p_io.DelayFree;
          except
          end;
        end;

      AConnection.UserObject := nil;
    end;
end;

procedure TGlobalCrossSocketClientPool.DoReceived(Sender: TCore_Object; AConnection: ICrossConnection; aBuf: Pointer; ALen: Integer);
{ *
  * Called by the driver when data is received. Forwards the raw data to the
  * associated PeerIO's Write_Physics_Fragment method.
}
var
  p_io: TCrossSocketClient_PeerIO;
begin
  if ALen <= 0 then
      exit;
  if AConnection = nil then
      exit;
  if not(AConnection.UserObject is TCrossSocketClient_PeerIO) then
      exit;

  p_io := AConnection.UserObject as TCrossSocketClient_PeerIO;

  if (p_io.IOInterface = nil) then
      exit;

  p_io.Write_Physics_Fragment(aBuf, ALen);
end;

procedure TGlobalCrossSocketClientPool.DoSendBuffResult(AConnection: ICrossConnection; ASuccess: Boolean);
{ *
  * Called when a send operation completes. Forwards the result to the
  * associated PeerIO's SendBuffResult method.
}
var
  p_io: TCrossSocketClient_PeerIO;
begin
  if AConnection = nil then
      exit;
  if not(AConnection.UserObject is TCrossSocketClient_PeerIO) then
      exit;

  p_io := TCrossSocketClient_PeerIO(AConnection.UserObject);

  if p_io = nil then
      exit;
  p_io.SendBuffResult(ASuccess);
end;

procedure TGlobalCrossSocketClientPool.Do_Connect_Backcall_(AConnection: ICrossConnection; ASuccess: Boolean);
{ *
  * Internal callback used by the driver's Connect method to report the
  * result of an asynchronous connect attempt. Stores the result and the
  * connection reference for later retrieval by BuildConnect (synchronous
  * wrapper).
}
begin
  LastCompleted := True;
  LastResult := ASuccess;
  if LastResult then
      LastConnection := AConnection;
end;

function TGlobalCrossSocketClientPool.BuildConnect(addr: SystemString; Port: Word; BuildIntf: TZNet_Client_FP_CrossSocket): Boolean;
{ *
  * Performs a synchronous (blocking) connection attempt for a given client.
  * It cleans up any existing connection, initiates a new asynchronous
  * connect via the driver, then waits (with a timeout) for the result.
  * If successful, it creates a TCrossSocketClient_PeerIO, attaches it to
  * the connection, and notifies the client via DoConnected.
  * If AutoReconnect is enabled, it retries on failure.
  *
  * @Param addr: Target address.
  * @Param Port: Target port.
  * @Param BuildIntf: The client instance that is requesting the connection.
  * @Returns: True if the connection was established and the client's
  *           remote initialisation is complete.
}
var
  dt: TTimeTick;
  p_io: TCrossSocketClient_PeerIO;
begin
  LastResult := False;
  LastCompleted := False;
  LastConnection := nil;

  if BuildIntf.ClientIOIntf <> nil then
      Check_Soft_Thread_Synchronize(10, False);

  if BuildIntf.ClientIOIntf <> nil then
    begin
      try
        if BuildIntf.ClientIOIntf.Context <> nil then
            BuildIntf.ClientIOIntf.Context.Close;
      except
      end;
      while BuildIntf.ClientIOIntf <> nil do
        begin
          Check_Soft_Thread_Synchronize(10, False);
          BuildIntf.Progress;
        end;
    end;

  (driver as ICrossSocket).Connect(addr, Port, Do_Connect_Backcall_);

  TCore_Thread.Sleep(10);

  dt := GetTimeTick + 5000;
  while (not LastCompleted) and (GetTimeTick < dt) do
    begin
      BuildIntf.Progress;
      Check_Soft_Thread_Synchronize(5, False);
    end;

  if LastResult then
    begin
      p_io := TCrossSocketClient_PeerIO.Create(BuildIntf, LastConnection.ConnectionIntf);
      p_io.OwnerClient := BuildIntf;
      LastConnection.UserObject := p_io;
      p_io.OwnerClient.ClientIOIntf := p_io;
      p_io.OnSendBackcall := DoSendBuffResult;
      BuildIntf.DoConnected(p_io);
    end;

  dt := GetTimeTick + 5000;
  while (LastCompleted) and (LastResult) and (not BuildIntf.RemoteInited) do
    begin
      BuildIntf.Progress;
      if GetTimeTick > dt then
        begin
          if LastConnection <> nil then
              LastConnection.Disconnect;
          Break;
        end;
    end;

  Result := BuildIntf.RemoteInited;

  if (not Result) and (AutoReconnect) then
      Result := BuildConnect(addr, Port, BuildIntf);
end;

procedure TGlobalCrossSocketClientPool.BuildAsyncConnect(addr: SystemString; Port: Word; BuildIntf: TZNet_Client_FP_CrossSocket);
{ *
  * Initiates an asynchronous connection attempt for a client.
  * It first cleans up any existing connection, then calls the driver's
  * Connect method with a bridge callback (TAsync_Connect_Backcall_Bridge_)
  * that will handle the result.
}
var
  bridge_: TAsync_Connect_Backcall_Bridge_;
begin
  try
    if BuildIntf.ClientIOIntf <> nil then
        Z.Core.Check_Soft_Thread_Synchronize(10, False);
    if BuildIntf.ClientIOIntf <> nil then
      begin
        try
          if BuildIntf.ClientIOIntf.Context <> nil then
              BuildIntf.ClientIOIntf.Context.Close;
        except
        end;

        while BuildIntf.ClientIOIntf <> nil do
          begin
            try
                BuildIntf.Progress;
            except
            end;
          end;
      end;
  except
    BuildIntf.TriggerDoConnectFailed;
    exit;
  end;

  bridge_ := TAsync_Connect_Backcall_Bridge_.Create;
  bridge_.ClientPool := Self;
  bridge_.addr := addr;
  bridge_.Port := Port;
  bridge_.BuildIntf := BuildIntf;
  (driver as ICrossSocket).Connect(addr, Port, bridge_.Do_Async_Connect_Bakcall_);
end;

procedure TAsync_Connect_Backcall_Bridge_.Do_Async_Connect_Bakcall_(AConnection: ICrossConnection; ASuccess: Boolean);
{ *
  * Called when the asynchronous connection attempt completes.
  * If successful, it creates a TCrossSocketClient_PeerIO and attaches it
  * to the connection, then notifies the client via DoConnected.
  * If the connection fails and AutoReconnect is enabled, it retries.
  * Otherwise, it triggers the client's connect failure callback.
  * Finally, the bridge object frees itself.
}
var
  p_io: TCrossSocketClient_PeerIO;
begin
  if ASuccess then
    begin
      p_io := TCrossSocketClient_PeerIO.Create(BuildIntf, AConnection.ConnectionIntf);
      p_io.OwnerClient := BuildIntf;
      AConnection.UserObject := p_io;
      p_io.OwnerClient.ClientIOIntf := p_io;
      p_io.OnSendBackcall := ClientPool.DoSendBuffResult;
      BuildIntf.DoConnected(p_io);
    end
  else
    begin
      if ClientPool.AutoReconnect then
        begin
          ClientPool.BuildAsyncConnect(addr, Port, BuildIntf);
          exit;
        end;
      if BuildIntf <> nil then
          BuildIntf.TriggerDoConnectFailed;
    end;
  DisposeObject(Self);
end;

initialization

Global_CrossSocket_ClientPool := nil;
CrossSocket_Instance_Num := TAtomInt.Create(0);

finalization

DisposeObjectAndNil(Global_CrossSocket_ClientPool);
DisposeObjectAndNil(CrossSocket_Instance_Num);

end.
 
