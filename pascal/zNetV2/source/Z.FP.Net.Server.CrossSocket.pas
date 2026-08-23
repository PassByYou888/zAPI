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
  * Server.CrossSocket – Server‑side bridge from Z.FP.Net.CrossSocket to Z.Net.
  *
  * This unit provides a concrete server implementation that wraps the
  * cross‑platform asynchronous I/O engine (TCrossSocket) and adapts it to
  * the Z.Net framework's TZNet_Server class hierarchy.
  *
  * It handles:
  *   - Accepting new connections (with a configurable maximum)
  *   - Creating a TPeerIO subclass (TCrossSocketServer_PeerIO) for each
  *     connection to manage buffering, send queues, and asynchronous callbacks
  *   - Mapping CrossSocket events (OnConnected, OnReceived, etc.) to the
  *     Z.Net progress model
  *   - Providing StartService/StopService lifecycle management
  *
  * The server uses a write‑buffer per connection: data is accumulated in
  * a TMem64, then flushed to the underlying socket via the CrossSocket's
  * asynchronous send mechanism. A send queue allows multiple pending buffers
  * to be serialised without blocking the main loop.
  *
  * Example (basic TCP server on port 8080):
  *   var
  *     server: TZNet_Server_FP_CrossSocket;
  *   begin
  *     server := TZNet_Server_FP_CrossSocket.Create;
  *     server.MaxConnection := 1000;          // limit concurrent clients
  *     if server.StartService('0.0.0.0', 8080) then
  *     begin
  *       while True do
  *       begin
  *         server.Progress;                   // drive the network engine
  *         CheckThreadSynchronize(10);        // process sync calls
  *       end;
  *     end;
  *   end;
}
unit Z.FP.Net.Server.CrossSocket;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses SysUtils, Classes,
  Z.FP.Net.CrossSocket, Z.FP.Net.SocketAPI, Z.FP.Net.CrossSocket.Base,
  Z.PascalStrings, Z.UPascalStrings, Z.Status,
  Z.Net, Z.Core, Z.UnicodeMixedLib, Z.MemoryStream,
  Z.DFE;

type
  { *
    * Thread‑safe ordered queue of TMem64 buffers.
    * Used to store pending send buffers for each connection.
  }
  TCrossSocketServer_Mem_Order = class(TCriticalOrderStruct<TMem64>)
    // order structure for memory buffers
  end;

  { *
    * TCrossSocketServer_PeerIO – Per‑connection IO handler for the CrossSocket server.
    *
    * This class inherits from TPeerIO (Z.Net's core IO state machine) and adds
    * a write‑buffer management layer. It accumulates outgoing data in a
    * TMem64, then flushes it to the underlying socket asynchronously.
    *
    * The send process is guarded by a critical section and maintains a queue
    * of pending buffers to prevent overlap. A callback (OnSendBackcall) is
    * invoked when the underlying socket confirms the send completion.
    *
    * @Field LastPeerIP: Cached peer IP address.
    * @Field Sending: True while an asynchronous send is in progress.
    * @Field Internal_Send_Queue: FIFO queue of pending buffers.
    * @Field CurrentBuff: Buffer being accumulated before flush.
    * @Field LastSendingBuff: The buffer currently being sent.
    * @Field OnSendBackcall: Callback invoked when a send completes.
    * @Field FSendCritical: Lock protecting the send state.
    * @Field FWriteBuffer_Size: Total bytes currently queued (including the one being sent).
  }
  TCrossSocketServer_PeerIO = class(TPeerIO)
  public
    LastPeerIP: SystemString;
    Sending: Boolean; // True when a send is in progress
    Internal_Send_Queue: TCrossSocketServer_Mem_Order; // queue of pending buffers
    CurrentBuff: TMem64; // currently accumulating data
    LastSendingBuff: TMem64; // the buffer being sent
    OnSendBackcall: TProc_ICrossConnection_Boolean;
    FSendCritical: TCritical;
    FWriteBuffer_Size: Int64; // total bytes in send queue
    procedure CreateAfter; override;
    destructor Destroy; override;
    function Context: TCrossConnection;
    function Connected: Boolean; override;
    procedure Disconnect; override;
    procedure SendBuffResult(Success_: Boolean);
    procedure Write_IO_Buffer(const buff: PByte; const Size: NativeInt); override;
    procedure WriteBufferOpen; override;
    procedure WriteBufferFlush; override;
    procedure WriteBufferClose; override;
    function GetPeerIP: SystemString; override;
    function WriteBuffer_is_NULL: Boolean; override;
    function WriteBuffer_State(var WriteBuffer_Queue_Num, WriteBuffer_Size: Int64): Boolean; override;
    procedure Progress; override;
  end;

  { *
    * Bridge class that counts the results of an asynchronous listen call.
    * Used to determine whether the StartService succeeded on all requested
    * addresses.
  }
  TListen_Backcall_Bridge_ = class
  public
    Completed, Successed: Integer;
    procedure Do_Backcall(Listen: ICrossListen; Success_: Boolean);
  end;

  TDriverEngine = TCrossSocket;

  { *
    * TZNet_Server_FP_CrossSocket – The main CrossSocket‑based TCP server.
    *
    * This class wraps a TCrossSocket instance and connects its event handlers
    * to the Z.Net framework. It provides StartService/StopService and manages
    * the maximum connection limit.
    *
    * @Field FDriver: The underlying TCrossSocket engine.
    * @Field FStartedService: True if the server is currently listening.
    * @Field FBindHost: The host address used in the last StartService call.
    * @Field FBindPort: The port used in the last StartService call.
    * @Field FMaxConnection: Maximum number of concurrent connections allowed.
  }
  TZNet_Server_FP_CrossSocket = class(TZNet_Server)
  private
    FDriver: TDriverEngine;
    FStartedService: Boolean;
    FBindHost: SystemString;
    FBindPort: Word;
    FMaxConnection: Integer;
  protected
    // Event handlers from the cross‑socket engine
    procedure DoAccept(Sender: TCore_Object; AListen: ICrossListen; var Accept: Boolean);
    procedure DoConnected(Sender: TCore_Object; AConnection: ICrossConnection);
    procedure DoDisconnect(Sender: TCore_Object; AConnection: ICrossConnection);
    procedure DoReceived(Sender: TCore_Object; AConnection: ICrossConnection; aBuf: Pointer; ALen: Integer);
    procedure DoSent(Sender: TCore_Object; AConnection: ICrossConnection; aBuf: Pointer; ALen: Integer);
    procedure DoSendBuffResult(AConnection: ICrossConnection; Success_: Boolean);
  public
    constructor Create; override;
    constructor CreateTh(maxThPool: Word);
    destructor Destroy; override;

    function StartService(Host: SystemString; Port: Word): Boolean; override;
    procedure StopService; override;

    procedure Progress; override;

    // These are not supported in this server (blocking calls)
    function WaitSendConsoleCmd(p_io: TPeerIO; const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString; override;
    procedure WaitSendStreamCmd(p_io: TPeerIO; const Cmd: SystemString; StreamData, ResultData: TDFE; TimeOut_: TTimeTick); override;

    property StartedService: Boolean read FStartedService;
    property driver: TDriverEngine read FDriver;
    property BindPort: Word read FBindPort;
    property BindHost: SystemString read FBindHost;
    property MaxConnection: Integer read FMaxConnection write FMaxConnection;
  end;

implementation

procedure TCrossSocketServer_PeerIO.CreateAfter;
{ *
  * Called after the object is constructed. Initialises all buffers,
  * the send queue, and the critical section.
}
begin
  inherited CreateAfter;
  LastPeerIP := '';
  Sending := False;
  Internal_Send_Queue := TCrossSocketServer_Mem_Order.Create;
  CurrentBuff := TMem64.Create;
  LastSendingBuff := nil;
  OnSendBackcall := nil;
  FSendCritical := TCritical.Create(ClassName + '.FSendCritical');
  FWriteBuffer_Size := 0;
end;

destructor TCrossSocketServer_PeerIO.Destroy;
{ *
  * Releases all resources: closes the underlying connection, frees all
  * pending buffers and the queue, and cleans up the critical section.
  * If the IOInterface (CrossConnection) is still alive, it is closed.
}
var
  c: TCrossConnection;
begin
  if IOInterface <> nil then
    begin
      c := Context;
      Context.UserObject := nil;
      IOInterface := nil;
      try
          c.Close;
      except
      end;
    end;

  while Internal_Send_Queue.Num > 0 do
    begin
      DisposeObject(Internal_Send_Queue.First^.Data);
      Internal_Send_Queue.Next;
    end;

  if LastSendingBuff <> nil then
      DisposeObjectAndNil(LastSendingBuff);

  DisposeObjectAndNil(CurrentBuff);
  DisposeObjectAndNil(Internal_Send_Queue);
  DisposeObjectAndNil(FSendCritical);

  inherited Destroy;
end;

function TCrossSocketServer_PeerIO.Context: TCrossConnection;
{ *
  * Returns the underlying CrossSocket connection interface as a TCrossConnection.
  * The IOInterface is set by the server when a new connection is accepted.
}
begin
  Result := IOInterface as TCrossConnection;
end;

function TCrossSocketServer_PeerIO.Connected: Boolean;
{ *
  * Returns True if the underlying CrossSocket connection is in the
  * 'connected' state.
}
begin
  Result := (IOInterface <> nil) and (Context.ConnectStatus = TConnectStatus.csConnected);
end;

procedure TCrossSocketServer_PeerIO.Disconnect;
{ *
  * Immediately closes the underlying connection and frees this IO object.
}
var
  c: TCrossConnection;
begin
  if IOInterface <> nil then
    begin
      c := Context;
      Context.UserObject := nil;
      IOInterface := nil;
      try
          c.Close;
      except
      end;
    end;
  DisposeObject(Self);
end;

procedure TCrossSocketServer_PeerIO.SendBuffResult(Success_: Boolean);
{ *
  * Called when the underlying CrossSocket confirms that a send operation
  * has completed (or failed). This method:
  *   1. Updates the write‑buffer size counter.
  *   2. If the send failed, it closes the connection.
  *   3. If successful, it dequeues the next buffer from Internal_Send_Queue
  *      and initiates the next send, or clears the Sending flag if the queue
  *      is empty.
}
var
  c: TCrossConnection;
  Num: Integer;
begin
  try
    if LastSendingBuff <> nil then
      begin
        AtomDec(FWriteBuffer_Size, LastSendingBuff.Size);
        if FSendCritical <> nil then
            FSendCritical.Lock;
        DisposeObjectAndNil(LastSendingBuff);
        if FSendCritical <> nil then
            FSendCritical.UnLock;
      end;

    if (not Success_) then
      begin
        Sending := False;
        if IOInterface <> nil then
          begin
            c := Context;
            Context.UserObject := nil;
            IOInterface := nil;
          end;
        DelayFree();
        exit;
      end;

    if Connected then
      begin
        FSendCritical.Lock;
        try
          UpdateLastCommunicationTime;
          Num := Internal_Send_Queue.Num;

          if Num > 0 then
            begin
              // 将发送队列拾取出来
              LastSendingBuff := Internal_Send_Queue.First^.Data;
              // 删除队列，下次回调时后置式释放
              Internal_Send_Queue.Next;

              if Context <> nil then
                begin
                  Context.SendBuf(LastSendingBuff.Memory, LastSendingBuff.Size, OnSendBackcall);
                  FSendCritical.UnLock;
                end
              else
                begin
                  FSendCritical.UnLock;
                  SendBuffResult(False);
                end;
            end
          else
            begin
              Sending := False;
              FWriteBuffer_Size := 0;
              FSendCritical.UnLock;
            end;
        except
          FSendCritical.UnLock;
          if IOInterface <> nil then
            begin
              c := Context;
              Context.UserObject := nil;
              IOInterface := nil;
            end;
          DelayClose();
        end;
      end
    else
      begin
        Sending := False;
      end;
  except
  end;
end;

procedure TCrossSocketServer_PeerIO.Write_IO_Buffer(const buff: PByte; const Size: NativeInt);
{ *
  * Writes raw bytes to the current accumulating buffer (CurrentBuff).
  * This is called by the framework's internal send path. Data is not sent
  * immediately; it is queued until WriteBufferFlush is called.
}
begin
  // 避免大量零碎数据消耗流量资源，碎片收集
  // 在flush中实现精确异步发送和校验
  if Size > 0 then
    begin
      FSendCritical.Lock;
      CurrentBuff.Position := CurrentBuff.Size;
      CurrentBuff.write(Pointer(buff)^, Size);
      FSendCritical.UnLock;
    end;
end;

procedure TCrossSocketServer_PeerIO.WriteBufferOpen;
{ *
  * Prepares the buffer for writing. In this implementation, no special action
  * is needed; CurrentBuff is already created.
}
begin
end;

procedure TCrossSocketServer_PeerIO.WriteBufferFlush;
{ *
  * Flushes the accumulated data in CurrentBuff to the underlying connection.
  * If a send is already in progress (Sending=True), the buffer is pushed
  * into the Internal_Send_Queue. Otherwise, it is sent immediately and the
  * Sending flag is set. The buffer object is replaced with a fresh one.
}
begin
  if not Connected then
      exit;

  if CurrentBuff.Size = 0 then
      exit;

  FSendCritical.Lock;
  if Sending then
    begin
      Internal_Send_Queue.Push(CurrentBuff);
      AtomInc(FWriteBuffer_Size, CurrentBuff.Size);
      CurrentBuff := TMem64.Create;
    end
  else
    begin
      if Internal_Send_Queue.Num = 0 then
          DisposeObjectAndNil(LastSendingBuff);

      Internal_Send_Queue.Push(CurrentBuff);
      AtomInc(FWriteBuffer_Size, CurrentBuff.Size);
      CurrentBuff := TMem64.Create;
      LastSendingBuff := Internal_Send_Queue.First^.Data;
      Internal_Send_Queue.Next;
      Sending := True;
      Context.SendBuf(LastSendingBuff.Memory, LastSendingBuff.Size, OnSendBackcall);
    end;
  FSendCritical.UnLock;
end;

procedure TCrossSocketServer_PeerIO.WriteBufferClose;
{ *
  * Finalises the write buffer by flushing any remaining data.
}
begin
  WriteBufferFlush;
end;

function TCrossSocketServer_PeerIO.GetPeerIP: SystemString;
{ *
  * Returns the peer IP address. If the connection is active, the IP is
  * obtained from the underlying CrossConnection and cached; otherwise the
  * cached value is returned.
}
begin
  if Connected then
    begin
      Result := Context.PeerAddr;
      LastPeerIP := Result;
    end
  else
      Result := LastPeerIP;
end;

function TCrossSocketServer_PeerIO.WriteBuffer_is_NULL: Boolean;
{ *
  * Returns True if there is no data pending in the send queue and no send
  * is currently in progress.
}
begin
  try
    FSendCritical.Lock;
    Result := (not Sending) and (Internal_Send_Queue.Num <= 0);
    FSendCritical.UnLock;
  except
  end;
end;

function TCrossSocketServer_PeerIO.WriteBuffer_State(var WriteBuffer_Queue_Num, WriteBuffer_Size: Int64): Boolean;
{ *
  * Provides the current state of the send buffer: the number of queued
  * buffers (Internal_Send_Queue.Num) and the total bytes in the queue
  * (FWriteBuffer_Size). Returns True if a send is currently in progress.
}
var
  p: TCrossSocketServer_Mem_Order.POrderStruct;
begin
  try
    Result := Sending;
    WriteBuffer_Queue_Num := Internal_Send_Queue.Num;
    WriteBuffer_Size := FWriteBuffer_Size;
  except
  end;
end;

procedure TCrossSocketServer_PeerIO.Progress;
{ *
  * Called periodically to drive the IO state machine. In addition to the
  * base class progress, it processes the send buffer.
}
begin
  inherited Progress;
  Process_Send_Buffer();
end;

procedure TListen_Backcall_Bridge_.Do_Backcall(Listen: ICrossListen; Success_: Boolean);
{ *
  * Called for each listen result. Increments Completed and Successed
  * counters so that StartService can determine whether all listens succeeded.
}
begin
  inc(Completed);
  if Success_ then
      inc(Successed);
end;

procedure TZNet_Server_FP_CrossSocket.DoAccept(Sender: TCore_Object; AListen: ICrossListen; var Accept: Boolean);
{ *
  * Called when a new incoming connection is about to be accepted.
  * Accepts the connection only if the current connection count is below
  * the FMaxConnection limit.
}
begin
  Accept := Count < FMaxConnection;
end;

procedure TZNet_Server_FP_CrossSocket.DoConnected(Sender: TCore_Object; AConnection: ICrossConnection);
{ *
  * Called when a new connection has been successfully established.
  * Creates a TCrossSocketServer_PeerIO instance, attaches it to the
  * connection's UserObject, and sets up the send‑result callback.
}
var
  p_io: TCrossSocketServer_PeerIO;
begin
  p_io := TCrossSocketServer_PeerIO.Create(Self, AConnection.ConnectionIntf);
  AConnection.UserObject := p_io;
  p_io.OnSendBackcall := DoSendBuffResult;
end;

procedure TZNet_Server_FP_CrossSocket.DoDisconnect(Sender: TCore_Object; AConnection: ICrossConnection);
{ *
  * Called when a connection is closed. Detaches the TCrossSocketServer_PeerIO
  * from the connection and schedules it for delayed destruction.
}
var
  p_io: TCrossSocketServer_PeerIO;
begin
  if AConnection.UserObject is TCrossSocketServer_PeerIO then
    begin
      p_io := TCrossSocketServer_PeerIO(AConnection.UserObject);
      if p_io <> nil then
        begin
          p_io.IOInterface := nil;
          AConnection.UserObject := nil;
          p_io.DelayFree;
        end;
    end;
end;

procedure TZNet_Server_FP_CrossSocket.DoReceived(Sender: TCore_Object; AConnection: ICrossConnection; aBuf: Pointer; ALen: Integer);
{ *
  * Called when data is received. Forwards the raw data to the PeerIO's
  * physical fragment handler (Write_Physics_Fragment), which will eventually
  * be processed by the Z.Net protocol parser.
}
var
  p_io: TCrossSocketServer_PeerIO;
begin
  if ALen <= 0 then
      exit;

  try
    p_io := TCrossSocketServer_PeerIO(AConnection.UserObject);
    if (p_io = niL) or (p_io.IOInterface = nil) then
        exit;
    p_io.Write_Physics_Fragment(aBuf, ALen);
  except
  end;
end;

procedure TZNet_Server_FP_CrossSocket.DoSent(Sender: TCore_Object; AConnection: ICrossConnection; aBuf: Pointer; ALen: Integer);
{ *
  * Called by the underlying CrossSocket when a send completes. This
  * implementation does nothing; the actual send completion logic is
  * handled by TCrossSocketServer_PeerIO.SendBuffResult.
}
begin
end;

procedure TZNet_Server_FP_CrossSocket.DoSendBuffResult(AConnection: ICrossConnection; Success_: Boolean);
{ *
  * Forwards the send completion result to the associated PeerIO.
}
var
  p_io: TCrossSocketServer_PeerIO;
begin
  if (AConnection = nil) or (AConnection.UserObject = nil) then
      exit;

  p_io := TCrossSocketServer_PeerIO(AConnection.UserObject);
  if (p_io = niL) or (p_io.IOInterface = nil) then
      exit;

  p_io.SendBuffResult(Success_);
end;

constructor TZNet_Server_FP_CrossSocket.Create;
{ *
  * Creates the server with a default thread pool size:
  *   - 1 thread in DEBUG mode (for easier debugging)
  *   - 4 threads otherwise (good balance for typical servers)
}
begin
  CreateTh({$IFDEF DEBUG}1{$ELSE DEBUG}4{$ENDIF DEBUG} ); // ZNet内部走的并发模型,不会阻塞线程,普通服务器并发线程2个就够了,如果高并发服务器,给8个线程
end;

constructor TZNet_Server_FP_CrossSocket.CreateTh(maxThPool: Word);
{ *
  * Creates the server with a specified number of I/O threads for the
  * underlying CrossSocket engine.
  * @Param maxThPool: Number of I/O threads to allocate. Should be tuned
  *                   according to the expected workload.
}
begin
  inherited Create;
  EnabledAtomicLockAndMultiThread := False;
  FDriver := TDriverEngine.Create(maxThPool);
  FDriver.OnAccept := DoAccept;
  FDriver.OnConnected := DoConnected;
  FDriver.OnDisconnected := DoDisconnect;
  FDriver.OnReceived := DoReceived;
  FDriver.OnSent := DoSent;
  FStartedService := False;
  FBindPort := 0;
  FBindHost := '';
  FMaxConnection := 20000;
  name := 'Cross-Socket-Server';
end;

destructor TZNet_Server_FP_CrossSocket.Destroy;
{ *
  * Stops the service, synchronises the soft thread queue, and frees the
  * underlying CrossSocket driver.
}
begin
  StopService;
  // CrossSocket使用了RTL的Synchronize机制,这是兼容UI的机制,在服务器领域这是非常蛋疼的东西
  // soft_synchronize_technology是Synchronize硬件仿真技术,用于DLL和静态库使用独立线程仿真RTL主线程,
  // 使用soft_synchronize_technology系技术,必须非常小心,同步队列一旦出问题都是传导型的问题
  // 如果开启了soft_synchronize_technology,这里必须同步一下
  // 同步的作用是清理IO同步事件,以免卡端口,导致PostQueuedCompletionStatus消息过去卡队列
  // 无论Used_Soft_Synchronize是否开启Check_Soft_Thread_Synchronize都会清理掉当前的UI同步队列.
  Check_Soft_Thread_Synchronize(0, False);
  try
      DisposeObject(FDriver);
  except
  end;
  inherited Destroy;
end;

function TZNet_Server_FP_CrossSocket.StartService(Host: SystemString; Port: Word): Boolean;
{ *
  * Starts the server by calling Listen on the underlying CrossSocket engine.
  * It uses a bridge to collect the results of the asynchronous listen
  * operation and returns True only if all requested addresses succeeded.
  * @Param Host: IP address or hostname to bind to.
  * @Param Port: Port number.
  * @Returns: True if at least one listen succeeded and all completes matched.
}
var
  Bridge_: TListen_Backcall_Bridge_;
begin
  StopService;

  Bridge_ := TListen_Backcall_Bridge_.Create;
  Bridge_.Completed := 0;
  Bridge_.Successed := 0;

  try
    ICrossSocket(FDriver).Listen(Host, Port, Bridge_.Do_Backcall);

    Check_Soft_Thread_Synchronize(5, False);

    FBindPort := Port;
    FBindHost := Host;
    Result := (Bridge_.Successed > 0) and (Bridge_.Successed = Bridge_.Completed);
    FStartedService := Result;
    DisposeObject(Bridge_);
  except
      Result := False;
  end;
end;

procedure TZNet_Server_FP_CrossSocket.StopService;
{ *
  * Stops the server by closing all connections and listens through the
  * underlying CrossSocket engine.
}
begin
  try
    try
        ICrossSocket(FDriver).CloseAll;
    except
    end;
    FStartedService := False;
  except
  end;
end;

procedure TZNet_Server_FP_CrossSocket.Progress;
{ *
  * Drives the network engine. This must be called periodically.
  * In this implementation, it simply calls the inherited Progress and the
  * driver's Progress (which is inherited through the base class).
}
begin
  inherited Progress;
end;

function TZNet_Server_FP_CrossSocket.WaitSendConsoleCmd(p_io: TPeerIO; const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString;
{ *
  * Blocking command send is not supported by this server because CrossSocket
  * is purely asynchronous. This raises an exception.
}
begin
  Result := '';
  RaiseInfo('WaitSend no Suppport CrossSocket');
end;

procedure TZNet_Server_FP_CrossSocket.WaitSendStreamCmd(p_io: TPeerIO; const Cmd: SystemString; StreamData, ResultData: TDFE; TimeOut_: TTimeTick);
{ *
  * Blocking command send is not supported. Raises an exception.
}
begin
  RaiseInfo('WaitSend no Suppport CrossSocket');
end;

initialization

finalization

end.
 
