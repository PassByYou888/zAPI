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
(*
  *  Z.IPC.Helper.pas – High-level object-oriented wrapper for the z_ipc C library.
  *  Provides TIPCClient and TIPCServer classes that encapsulate the raw C API
  *  with automatic resource management and convenient overloads for common
  *  Pascal data types (TMem64, TBytes, raw pointers).
  *
  *  The library enables cross‑process communication via named message queues
  *  backed by Boost.Interprocess. All binary payloads are transferred using
  *  shared memory segments for efficiency.
  *
  *  ===========================================================================
  *  USAGE OVERVIEW
  *  ===========================================================================
  *
  *  Two main roles:
  *    - Server: listens on a queue, handles RPC requests and notifications.
  *    - Client: connects to the server, makes RPC calls, sends/receives notifications.
  *
  *  Basic Workflow (see individual method comments for detailed examples):
  *
  *  1. Server side:
  *     - Create a TIPCServer instance.
  *     - Call Start(QueueName) to create the queue and start worker threads.
  *     - Register RPC handlers (RegisterBinaryHandler) and/or notify handlers
  *       (RegisterBinaryNotify) for client‑originated notifications.
  *     - Use SendNotifyBinary to push notifications to specific clients.
  *
  *  2. Client side:
  *     - Create a TIPCClient instance.
  *     - Call Connect(QueueName) to attach to the server's queue.
  *     - Register notify handlers (RegisterBinaryNotify) to receive server‑sent
  *       notifications.
  *     - Call CallBinary to perform synchronous RPC.
  *     - Call NotifyBinary for fire‑and‑forget messages to the server.
  *
  *  3. Cleanup:
  *     - Both classes are auto-managed; destroy them when done. The server stops
  *       and the client disconnects automatically.
  *
  *  Thread Safety: These classes are not thread‑safe. Each instance should be
  *  used from a single thread, or you must add external synchronization.
  *
  *  Error Handling: All methods that perform IPC operations return Integer
  *  error codes (IPC_OK on success). Check these values against the constants
  *  defined in Z.IPC.API.
*)

unit Z.IPC.Helper;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses Z.Core, Z.MemoryStream, Z.IPC.API;

type
  TByteArray = TBytes; { * Alias for dynamic byte array, used in overloads }

  { * TIPCClient – High‑level client wrapper.
    * This class encapsulates a raw C client handle (TIPCClientHandle) and
    * provides methods to connect to a server, send RPC requests, send
    * notifications, and register handlers for server‑originated notifications.
    * It automatically loads the IPC library when the first instance is created.
    *
    * @Usage:
    *   var Client: TIPCClient;
    *   begin
    *     Client := TIPCClient.Create;
    *     try
    *       if Client.Connect('my_queue') then
    *       begin
    *         // Use Client.CallBinary, Client.NotifyBinary, etc.
    *       end;
    *     finally
    *       Client.Free; // Automatically disconnects
    *     end;
    *   end;
  }
  TIPCClient = class
  private
    FHandle: TIPCClientHandle; { * Raw C handle (0 if not created or destroyed) }
    FConnected: Boolean; { * True if connected to a server }
  public
    constructor Create;
    destructor Destroy; override;

    { * Connect to a server queue.
      * Opens the server's main queue and creates a private response queue.
      * The server must already be running and have a queue with the given name.
      * If already connected, this method disconnects first.
      * @Param QueueName: Name of the server's main queue (case‑sensitive).
      * @Returns True if the connection succeeded, False otherwise (e.g., queue not found).
      * @Example:
      *   if Client.Connect('my_server_queue') then
      *     WriteLn('Connected successfully')
      *   else
      *     WriteLn('Connection failed');
    }
    function Connect(const QueueName: string): Boolean;

    { * Disconnect from the server.
      * Closes the response queue, stops the receiver thread, and frees resources.
      * After disconnection, the client can call Connect again to reconnect.
      * This is called automatically in the destructor.
    }
    procedure Disconnect;

    { * Get the name of this client's private response queue.
      * The server uses this name to send notifications to this client.
      * @Returns The queue name as a string, or empty string if not connected.
      * @Example:
      *   var RespName: string;
      *   begin
      *     RespName := Client.GetRespQueueName;
      *     // Send RespName to server so it knows where to send notifications
      *   end;
    }
    function GetRespQueueName: string;

    { * Register a handler for server‑to‑client binary notifications.
      * This handler will be invoked in the client's receiver thread when the
      * server sends a notification with the matching name.
      * @Param Name: The notification name (must match the name used by the server).
      * @Param Handler: The callback procedure (TIPCBinaryNotifyHandler).
      * @Param Trigger: A user‑supplied pointer that will be passed to the handler.
      * @Returns True if registration succeeded, False if the name is already registered.
      * @Example:
      *   procedure MyNotify(trigger: Pointer; data: Pointer; size: TSize_t); cdecl;
      *   begin
      *     WriteLn('Received notification of ', size, ' bytes');
      *   end;
      *   ...
      *   if Client.RegisterBinaryNotify('data_update', MyNotify, nil) then
      *     WriteLn('Handler registered');
    }
    function RegisterBinaryNotify(const Name: string; Handler: TIPCBinaryNotifyHandler; Trigger: Pointer): Boolean;

    { * Unregister a previously registered notification handler.
      * @Param Name: The notification name to remove.
      * @Returns True if the handler was found and removed, False otherwise.
    }
    function UnregisterBinaryNotify(const Name: string): Boolean;

    { * Binary RPC call – send request data and wait for a reply.
      * This overload uses TMem64 for both input and output.
      * The input data (InData) is read from its current position to the end;
      * the output data (OutData) is cleared and filled with the reply.
      * @Param FuncName: The function name registered on the server.
      * @Param InData: Input data stream (TMem64). Its content is sent as the request.
      * @Param OutData: Output data stream. It will be cleared and contain the reply.
      * @Returns IPC_OK on success, or an error code (e.g., IPC_ERR_TIMEOUT).
      * @Example:
      *   var Req, Resp: TMem64;
      *   begin
      *     Req := TMem64.Create;
      *     Resp := TMem64.Create;
      *     try
      *       Req.WriteString('Hello');
      *       if Client.CallBinary('echo', Req, Resp) = IPC_OK then
      *         WriteLn('Reply: ', Resp.ReadString);
      *     finally
      *       Req.Free; Resp.Free;
      *     end;
      *   end;
    }
    function CallBinary(const FuncName: string; InData, OutData: TMem64): Integer; overload;

    { * Binary RPC call – using raw pointer input and TBytes output.
      * @Param FuncName: The function name on the server.
      * @Param Data: Pointer to the input data (may be nil if Size=0).
      * @Param Size: Number of bytes to send.
      * @Param OutData: Dynamic array that will receive the reply.
      * @Returns IPC_OK on success, or an error code.
    }
    function CallBinary(const FuncName: string; const Data: Pointer; Size: Integer; out OutData: TByteArray): Integer; overload;

    { * Binary RPC call – using TBytes for both input and output.
      * @Param FuncName: The function name on the server.
      * @Param Data: Input TBytes.
      * @Param OutData: Output TBytes.
      * @Returns IPC_OK on success, or an error code.
      * @Example:
      *   var InData, OutData: TBytes;
      *   begin
      *     SetLength(InData, 10);
      *     // fill InData
      *     if Client.CallBinary('process', InData, OutData) = IPC_OK then
      *       // use OutData
      *   end;
    }
    function CallBinary(const FuncName: string; const Data: TByteArray; out OutData: TByteArray): Integer; overload;

    { * Send a binary notification (fire‑and‑forget) using TMem64.
      * This method sends data to the server without waiting for a reply.
      * @Param FuncName: The notification name registered on the server.
      * @Param InData: Payload data (TMem64).
      * @Returns IPC_OK on success, or an error code.
    }
    function NotifyBinary(const FuncName: string; InData: TMem64): Integer; overload;

    { * Send a binary notification using raw pointer.
      * @Param FuncName: Notification name.
      * @Param Data: Pointer to payload (may be nil).
      * @Param Size: Payload size.
      * @Returns IPC_OK on success.
    }
    function NotifyBinary(const FuncName: string; const Data: Pointer; Size: Integer): Integer; overload;

    { * Send a binary notification using TBytes.
      * @Param FuncName: Notification name.
      * @Param Data: Payload TBytes.
      * @Returns IPC_OK on success.
    }
    function NotifyBinary(const FuncName: string; const Data: TByteArray): Integer; overload;

    { * Set the RPC timeout for this client.
      * This timeout affects all subsequent CallBinary calls.
      * @Param Milliseconds: Timeout value in milliseconds (must be > 0).
    }
    procedure SetTimeout(Milliseconds: Integer);

    { * Check if the client is currently connected.
      * @Returns True if connected and the queue is accessible.
    }
    function IsConnected: Boolean;

    property Connected: Boolean read FConnected; { * Alias for IsConnected }
    property Handle: TIPCClientHandle read FHandle; { * Raw C handle (for advanced use) }
  end;

  { * TIPCServer – High‑level server wrapper.
    * Manages the IPC server lifecycle and handler registration.
    * The server listens on a named queue, dispatches RPC requests and
    * notifications to registered handlers, and can send notifications to clients.
    *
    * @Usage:
    *   var Server: TIPCServer;
    *   begin
    *     Server := TIPCServer.Create;
    *     try
    *       if Server.Start('my_queue') then
    *       begin
    *         Server.RegisterBinaryHandler('echo', EchoHandler, nil);
    *         // ... keep server running ...
    *       end;
    *     finally
    *       Server.Free; // Stops the server automatically
    *     end;
    *   end;
  }
  TIPCServer = class
  private
    FHandle: TIPCServerHandle; { * Raw C handle (0 if not started) }
    FStarted: Boolean; { * True if the server is running }
  public
    constructor Create;
    destructor Destroy; override;

    { * Start the server with default configuration.
      * Creates a queue with max_queue_length=1000 and max_msg_size=1024,
      * and uses auto‑detected thread count (0 = auto).
      * @Param QueueName: Name of the main queue.
      * @Returns True if the server started successfully.
    }
    function Start(const QueueName: string): Boolean; overload;

    { * Start the server with a custom configuration record.
      * @Param QueueName: Queue name.
      * @Param Config: TIPCServerConfig record with explicit settings.
      * @Returns True if successful.
    }
    function Start(const QueueName: string; const Config: TIPCServerConfig): Boolean; overload;

    { * Start the server with explicit parameters.
      * This is the most flexible startup method.
      * @Param QueueName: Queue name.
      * @Param ThreadCount: Number of worker threads (0 = auto‑detect).
      * @Param MaxQueueLength: Maximum number of pending messages in the queue.
      * @Param MaxMsgSize: Maximum size (in bytes) of control messages.
      * @Returns True if the server started successfully.
      * @Example:
      *   if Server.StartEx('my_queue', 4, 2000, 2048) then
      *     WriteLn('Server started with 4 threads and larger queue');
    }
    function StartEx(const QueueName: string; ThreadCount: Integer; MaxQueueLength, MaxMsgSize: TSize_t): Boolean;

    { * Stop the server.
      * Removes the queue and frees all resources. All connected clients will
      * be disconnected. Called automatically in the destructor.
    }
    procedure Stop;

    { * Register a binary RPC handler.
      * @Param Name: Function name that clients will call.
      * @Param Handler: Callback of type TIPCBinaryReplyHandler.
      * @Param Trigger: User pointer passed to the handler.
      * @Returns True if registration succeeded, False if the name is already used.
      * @Example:
      *   procedure MyRPC(trigger: Pointer; data: Pointer; size: TSize_t;
      *     out outData: Pointer; out outSize: TSize_t); cdecl;
      *   begin
      *     // process request and set outData/outSize (must allocate with ipc_alloc)
      *   end;
      *   ...
      *   if Server.RegisterBinaryHandler('calculate', MyRPC, nil) then
      *     WriteLn('RPC handler registered');
    }
    function RegisterBinaryHandler(const Name: string; Handler: TIPCBinaryReplyHandler; Trigger: Pointer): Boolean;

    { * Unregister a binary RPC handler.
      * @Param Name: Function name.
      * @Returns True if the handler was found and removed.
    }
    function UnregisterBinaryHandler(const Name: string): Boolean;

    { * Register a binary notify handler (for client‑to‑server notifications).
      * @Param Name: Notification name.
      * @Param Handler: Callback of type TIPCBinaryNotifyHandler.
      * @Param Trigger: User pointer.
      * @Returns True if successful.
    }
    function RegisterBinaryNotify(const Name: string; Handler: TIPCBinaryNotifyHandler; Trigger: Pointer): Boolean;

    { * Unregister a binary notify handler.
      * @Param Name: Notification name.
      * @Returns True if successful.
    }
    function UnregisterBinaryNotify(const Name: string): Boolean;

    { * Send a binary notification to a specific client (using TMem64).
      * The client must have registered a handler with the same FuncName.
      * @Param ClientRespQueue: The client's response queue name (obtained from GetRespQueueName).
      * @Param FuncName: Notification name.
      * @Param InData: Payload (TMem64).
      * @Returns IPC_OK on success, or an error code.
      * @Example:
      *   var Data: TMem64;
      *   begin
      *     Data := TMem64.Create;
      *     Data.WriteString('Hello client');
      *     try
      *       Server.SendNotifyBinary('client_queue_123', 'update', Data);
      *     finally
      *       Data.Free;
      *     end;
      *   end;
    }
    function SendNotifyBinary(const ClientRespQueue, FuncName: string; InData: TMem64): Integer; overload;

    { * Send a binary notification using raw pointer.
      * @Param ClientRespQueue: Client's response queue.
      * @Param FuncName: Notification name.
      * @Param Data: Pointer to payload.
      * @Param Size: Payload size.
      * @Returns IPC_OK on success.
    }
    function SendNotifyBinary(const ClientRespQueue, FuncName: string; const Data: Pointer; Size: Integer): Integer; overload;

    { * Send a binary notification using TBytes.
      * @Param ClientRespQueue: Client's response queue.
      * @Param FuncName: Notification name.
      * @Param Data: Payload TBytes.
      * @Returns IPC_OK on success.
    }
    function SendNotifyBinary(const ClientRespQueue, FuncName: string; const Data: TByteArray): Integer; overload;

    property Started: Boolean read FStarted; { * True if the server is running }
    property Handle: TIPCServerHandle read FHandle; { * Raw C handle (advanced use) }
  end;

implementation

{ ============================================================================== }
{ TIPCClient }
{ ============================================================================== }

constructor TIPCClient.Create;
begin
  { * Ensure the IPC library is loaded before creating any objects.
    RaiseInfo raises an exception if the library cannot be loaded.
  }
  if not LoadIPCLibrary then
    RaiseInfo('no found Z-IPC library.');
  inherited Create;
  FHandle := ipc_client_create; { * Create a raw C client handle }
  FConnected := False;
end;

destructor TIPCClient.Destroy;
begin
  Disconnect; { * Ensure we disconnect before destroying the handle }
  if FHandle <> 0 then
      ipc_client_destroy(FHandle); { * Free the raw C handle }
  inherited;
end;

function TIPCClient.Connect(const QueueName: string): Boolean;
begin
  Result := False;
  if FHandle = 0 then
    Exit;
  if FConnected then
    Disconnect; { * Reconnect: disconnect first }
  { * Call the raw C function. If successful, the client will have a response queue.
    The C function returns IPC_OK on success.
  }
  if ipc_client_connect(FHandle, PAnsiChar(AnsiString(QueueName))) = IPC_OK then
    begin
      FConnected := True;
      Result := True;
    end;
end;

procedure TIPCClient.Disconnect;
begin
  if FConnected and (FHandle <> 0) then
    begin
      ipc_client_disconnect(FHandle); { * Tell the C library to disconnect }
      FConnected := False;
    end;
end;

function TIPCClient.GetRespQueueName: string;
begin
  Result := '';
  if FHandle = 0 then
    Exit;
  Result := string(ipc_client_get_resp_queue_name(FHandle));
  { * Returns the internal C string as a Pascal string }
end;

function TIPCClient.RegisterBinaryNotify(const Name: string; Handler: TIPCBinaryNotifyHandler; Trigger: Pointer): Boolean;
begin
  Result := False;
  if FHandle = 0 then
    Exit;
  Result := ipc_client_register_binary_notify(FHandle, PAnsiChar(AnsiString(Name)), Handler, Trigger) = IPC_OK;
end;

function TIPCClient.UnregisterBinaryNotify(const Name: string): Boolean;
begin
  Result := False;
  if FHandle = 0 then
    Exit;
  Result := ipc_client_unregister_binary_notify(FHandle, PAnsiChar(AnsiString(Name))) = IPC_OK;
end;

function TIPCClient.CallBinary(const FuncName: string; InData, OutData: TMem64): Integer;
var
  outPtr: Pointer;
  outSize: TSize_t;
begin
  OutData.Clear;
  Result := IPC_ERR_UNKNOWN;
  if not FConnected or (FHandle = 0) then
    Exit;
  { * Call the raw C RPC function. The library will allocate outPtr using ipc_alloc,
    which we must free after copying the data to OutData.
  }
  Result := ipc_client_call_binary(FHandle, PAnsiChar(AnsiString(FuncName)),
    InData.Memory, InData.Size, outPtr, outSize);
  if Result = IPC_OK then
    begin
      OutData.WritePtr(outPtr, outSize); { * Copy the reply into the output stream }
      OutData.Position := 0; { * Reset position for reading }
      ipc_free(outPtr); { * Free the C-allocated buffer }
    end;
end;

function TIPCClient.CallBinary(const FuncName: string; const Data: Pointer; Size: Integer; out OutData: TByteArray): Integer;
var
  outPtr: Pointer;
  outSize: TSize_t;
begin
  SetLength(OutData, 0);
  Result := IPC_ERR_UNKNOWN;
  if not FConnected or (FHandle = 0) then
    Exit;
  Result := ipc_client_call_binary(FHandle, PAnsiChar(AnsiString(FuncName)),
    Data, Size, outPtr, outSize);
  if Result = IPC_OK then
    begin
      SetLength(OutData, outSize);
      if outSize > 0 then
          CopyPtr(outPtr, @OutData[0], outSize); { * Copy raw bytes to Pascal array }
      ipc_free(outPtr);
    end;
end;

function TIPCClient.CallBinary(const FuncName: string; const Data: TByteArray; out OutData: TByteArray): Integer;
begin
  if Length(Data) > 0 then
      Result := CallBinary(FuncName, @Data[0], Length(Data), OutData)
  else
      Result := CallBinary(FuncName, nil, 0, OutData);
end;

function TIPCClient.NotifyBinary(const FuncName: string; InData: TMem64): Integer;
begin
  Result := IPC_ERR_UNKNOWN;
  if not FConnected or (FHandle = 0) then
    Exit;
  Result := ipc_client_notify_binary(FHandle, PAnsiChar(AnsiString(FuncName)), InData.Memory, InData.Size);
end;

function TIPCClient.NotifyBinary(const FuncName: string; const Data: Pointer; Size: Integer): Integer;
begin
  Result := IPC_ERR_UNKNOWN;
  if not FConnected or (FHandle = 0) then
    Exit;
  Result := ipc_client_notify_binary(FHandle, PAnsiChar(AnsiString(FuncName)), Data, Size);
end;

function TIPCClient.NotifyBinary(const FuncName: string; const Data: TByteArray): Integer;
begin
  if Length(Data) > 0 then
      Result := NotifyBinary(FuncName, @Data[0], Length(Data))
  else
      Result := NotifyBinary(FuncName, nil, 0);
end;

procedure TIPCClient.SetTimeout(Milliseconds: Integer);
begin
  if FHandle <> 0 then
      ipc_client_set_timeout(FHandle, Milliseconds);
end;

function TIPCClient.IsConnected: Boolean;
begin
  Result := False;
  if FHandle = 0 then
    Exit;
  Result := ipc_client_is_connected(FHandle) = 1; { * C returns 1 for true, 0 for false }
end;

{ ============================================================================== }
{ TIPCServer }
{ ============================================================================== }

constructor TIPCServer.Create;
begin
  if not LoadIPCLibrary() then
    RaiseInfo('no found Z-IPC library.');
  inherited Create;
  FHandle := 0;
  FStarted := False;
end;

destructor TIPCServer.Destroy;
begin
  Stop; { * Stop the server if running }
  if FHandle <> 0 then
      ipc_server_destroy(FHandle); { * Free the raw C handle }
  inherited;
end;

function TIPCServer.Start(const QueueName: string): Boolean;
begin
  Result := StartEx(QueueName, 0, 1000, 1024); { * Use default config }
end;

function TIPCServer.Start(const QueueName: string; const Config: TIPCServerConfig): Boolean;
begin
  Result := StartEx(QueueName, Config.thread_count, Config.max_queue_length, Config.max_msg_size);
end;

function TIPCServer.StartEx(const QueueName: string; ThreadCount: Integer; MaxQueueLength, MaxMsgSize: TSize_t): Boolean;
var
  cfg: TIPCServerConfig;
begin
  Result := False;
  if FStarted then
    Stop; { * Stop any existing server before starting a new one }
  if FHandle = 0 then
    begin
      cfg.thread_count := ThreadCount;
      cfg.max_queue_length := MaxQueueLength;
      cfg.max_msg_size := MaxMsgSize;
      { * Call the C function to create and start the server }
      FHandle := ipc_server_create_ex(PAnsiChar(AnsiString(QueueName)), @cfg);
    end;
  if FHandle <> 0 then
    begin
      FStarted := True;
      Result := True;
    end;
end;

procedure TIPCServer.Stop;
begin
  if FStarted and (FHandle <> 0) then
    begin
      ipc_server_destroy(FHandle); { * Stops the server and removes the queue }
      FHandle := 0;
      FStarted := False;
    end;
end;

function TIPCServer.RegisterBinaryHandler(const Name: string; Handler: TIPCBinaryReplyHandler; Trigger: Pointer): Boolean;
begin
  Result := False;
  if not FStarted or (FHandle = 0) then
    Exit;
  Result := ipc_server_register_binary_reply(FHandle, PAnsiChar(AnsiString(Name)), Handler, Trigger) = IPC_OK;
end;

function TIPCServer.UnregisterBinaryHandler(const Name: string): Boolean;
begin
  Result := False;
  if not FStarted or (FHandle = 0) then
    Exit;
  Result := ipc_server_unregister_binary_reply(FHandle, PAnsiChar(AnsiString(Name))) = IPC_OK;
end;

function TIPCServer.RegisterBinaryNotify(const Name: string; Handler: TIPCBinaryNotifyHandler; Trigger: Pointer): Boolean;
begin
  Result := False;
  if not FStarted or (FHandle = 0) then
    Exit;
  Result := ipc_server_register_binary_notify(FHandle, PAnsiChar(AnsiString(Name)), Handler, Trigger) = IPC_OK;
end;

function TIPCServer.UnregisterBinaryNotify(const Name: string): Boolean;
begin
  Result := False;
  if not FStarted or (FHandle = 0) then
    Exit;
  Result := ipc_server_unregister_binary_notify(FHandle, PAnsiChar(AnsiString(Name))) = IPC_OK;
end;

function TIPCServer.SendNotifyBinary(const ClientRespQueue, FuncName: string; InData: TMem64): Integer;
begin
  Result := IPC_ERR_INVAL;
  if not FStarted or (FHandle = 0) then
    Exit;
  Result := ipc_server_send_notify_binary(FHandle,
    PAnsiChar(AnsiString(ClientRespQueue)),
    PAnsiChar(AnsiString(FuncName)),
    InData.Memory, InData.Size);
end;

function TIPCServer.SendNotifyBinary(const ClientRespQueue, FuncName: string; const Data: Pointer; Size: Integer): Integer;
begin
  Result := IPC_ERR_INVAL;
  if not FStarted or (FHandle = 0) then
    Exit;
  Result := ipc_server_send_notify_binary(FHandle,
    PAnsiChar(AnsiString(ClientRespQueue)),
    PAnsiChar(AnsiString(FuncName)),
    Data, Size);
end;

function TIPCServer.SendNotifyBinary(const ClientRespQueue, FuncName: string; const Data: TByteArray): Integer;
begin
  if Length(Data) > 0 then
      Result := SendNotifyBinary(ClientRespQueue, FuncName, @Data[0], Length(Data))
  else
      Result := SendNotifyBinary(ClientRespQueue, FuncName, nil, 0);
end;

end.
 
