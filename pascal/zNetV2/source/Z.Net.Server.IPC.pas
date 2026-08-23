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
  * Z.Net.Server.IPC – Implements a Z.Net server that uses the z_ipc library
  * for communication via message queues.
  *
  * ============================================================================
  * DESIGN OVERVIEW
  * ============================================================================
  * This unit provides a TZNet_Server_IPC class that acts as a server in the
  * Z.Net framework, accepting connections from IPC clients (such as the
  * TZNet_Client_IPC from the companion unit). It mimics a TCP server but
  * uses Boost.Interprocess message queues for transport.
  *
  * The server listens on a main queue (named "<addr>-<port>") and handles
  * incoming RPC requests and notifications from clients. Each client is
  * represented by a TZNet_Server_IPC_PeerIO object, which manages the
  * communication with that client.
  *
  * MESSAGE FLOW
  * ------------
  * 1. The server starts by creating a TIPCServer on a named main queue.
  * 2. It registers three handlers:
  *      - "connect" (RPC handler) – handles client connection handshake.
  *      - "close" (notify handler) – handles client‑initiated disconnection.
  *      - "buff" (notify handler) – handles incoming data from clients.
  * 3. When a client connects, it calls the "connect" RPC, passing its response
  *    queue name. The server creates a new TZNet_Server_IPC_PeerIO object,
  *    assigns a unique ID, generates two notification names (one for data,
  *    one for disconnect), and replies with these names and the assigned ID.
  * 4. The server does **not** need to register handlers for client‑specific names
  *    because it sends notifications to the client using the client's response
  *    queue (via ipc_server_send_notify_binary). The handlers "buff" and "close"
  *    are the server‑side handlers for notifications **from** clients, which are
  *    global (all clients use the same "buff" and "close" notify names). The
  *    client‑specific names are only used on the client side to receive server‑sent
  *    notifications.
  * 5. For outgoing data, the server's PeerIO buffers the data with a leading
  *    ID and sends it as a notification to the client's response queue using
  *    the client‑specific FSend_Buff_CMD_Notify name.
  * 6. For incoming data, clients send a notification named "buff" containing
  *    the ID and payload. The server's IPC_Buff_Handler reads the ID, finds
  *    the corresponding PeerIO, and feeds the payload into its fragment processor.
  * 7. Disconnection can be initiated by either side: client sends "close",
  *    server sends the disconnect notification to the client.
  *
  * UNDERLYING MECHANISM (z_ipc)
  * ----------------------------
  * - The server uses a TIPCServer with multiple worker threads.
  * - Binary RPC handlers are used only for "connect" (synchronous handshake).
  * - All other communication uses asynchronous binary notifications.
  * - Shared memory is used for transporting binary data, but the framework
  *   abstracts this away: the PeerIO uses FTempBuff and NotifyBinary to send data,
  *   and the server's notify handler receives the payload.
  *
  * This unit integrates the IPC server into the Z.Net server framework,
  * allowing application code to use the same event‑driven architecture as
  * traditional network servers.
*)

unit Z.Net.Server.IPC;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses SysUtils, Classes,
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings, Z.Notify, Z.Status,
  Z.Net, Z.UnicodeMixedLib, Z.MemoryStream, Z.DFE,
  Z.IPC.API, Z.IPC.Helper;

type
  TZNet_Server_IPC = class; // Forward declaration for mutual references

  { * TZNet_Server_IPC_PeerIO – Represents a connected client in the server.
    * Each client that successfully handshakes gets a PeerIO instance.
    * This object maintains the client's response queue name and the two
    * notification names exchanged during handshake. It also buffers outgoing
    * data before sending via IPC.
    *
    * The WriteBufferFlush method sends the buffered data to the client using
    * ipc_server_send_notify_binary with the client‑specific notification name.
    *
    * @Usage:
    *   This class is created internally by TZNet_Server_IPC during the
    *   "connect" RPC handler. It is not intended to be used directly.
  }
  TZNet_Server_IPC_PeerIO = class(TPeerIO)
  protected
    FRespQueueName: U_String; { * Client's response queue name (used for sending notifications) }
    FSend_Buff_CMD_Notify: U_String; { * Notification name for sending data to this client }
    FDisconnect_CMD_Notify: U_String; { * Notification name for disconnecting this client }
    FTempBuff: TMem64; { * Temporary buffer for outgoing packet assembly }
  public
    procedure CreateAfter; override;
    destructor Destroy; override;
    function Connected: Boolean; override; { * Always true while object exists }
    procedure Disconnect; override; { * Send disconnect notification and schedule deletion }
    procedure Write_IO_Buffer(const buff: PByte; const Size: nativeInt); override; { * Append raw data }
    procedure WriteBufferOpen; override; { * Start a new packet (adds an ID header) }
    procedure WriteBufferFlush; override; { * Send buffered data to the client }
    procedure WriteBufferClose; override; { * Discard unsent data }
    function GetPeerIP: SystemString; override; { * Returns the client's response queue name as identifier }
    function WriteBuffer_is_NULL: Boolean; override; { * True if buffer is empty }
    procedure DoP2PVM_Created(Sender: TZNet_P2PVM); override;
    procedure DoP2PVM_InstallLogicFramework(Inst: TZNet); override;
    procedure Progress; override; { * Called periodically to flush pending data }
  end;

  { * TZNet_Server_IPC – IPC‑based server for Z.Net.
    * Manages the IPC server instance and the pool of client PeerIO objects.
    * The StartService method creates the TIPCServer and registers the three
    * required handlers. The StopService cleans up and disconnects all clients.
    *
    * Handlers are global functions (cdecl) that are registered with the IPC
    * server. They receive the trigger pointer (the server instance) and the
    * payload, and dispatch to the appropriate PeerIO.
    *
    * @Usage:
    *   var Server: TZNet_Server_IPC;
    *   begin
    *     Server := TZNet_Server_IPC.Create;
    *     try
    *       if Server.StartService('ipc:my_server', 1311) then
    *       begin
    *         WriteLn('Server listening on queue my_server-1311');
    *         // ... keep server running (call Progress periodically)
    *       end;
    *     finally
    *       Server.Free;
    *     end;
    *   end;
  }
  TZNet_Server_IPC = class(TZNet_Server)
  private
  protected
    Critical: TCritical; { * Protects access to IOPool during concurrent operations }
    ipc_serv: TIPCServer; { * Low‑level IPC server instance from Z.IPC.Helper }
    ipc_queue_name: U_String; { * Main queue name (formatted as "address-port") }
  public
  class var
    IPC_Serv_ThreadCount: Integer;
    IPC_Serv_MaxQueueLength, IPC_Serv_MaxMsgSize: NativeUInt;
  public
    constructor Create; override;
    destructor Destroy; override;
    function StartService(Host: SystemString; Port: Word): Boolean; override;
    procedure StopService; override;
    procedure Progress; override;

    { * Overridden to raise an error because IPC does not support
      * synchronous command/stream waiting. All communication is asynchronous.
    }
    function WaitSendConsoleCmd(p_io: TPeerIO; const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString; override;
    procedure WaitSendStreamCmd(p_io: TPeerIO; const Cmd: SystemString; StreamData, ResultData: TDFE; TimeOut_: TTimeTick); override;
  end;

  { * Global callback functions (cdecl) registered with the IPC server.
    * These are called by the z_ipc library from worker threads.
  }

  { * RPC handler for client connection request.
    * Trigger: TZNet_Server_IPC instance.
    * Data: contains the client's response queue name (as a string).
    * Output: three values – server‑assigned ID (4 bytes), data notification name,
    * disconnect notification name.
    * This handler creates a new PeerIO object, stores the client's queue name,
    * assigns unique notification names (using the server's queue name and the
    * client's ID), and replies with the ID and names.
    * @Param trigger: Pointer to the TZNet_Server_IPC instance.
    * @Param data: Pointer to the request payload (the client's response queue name).
    * @Param Size: Size of the payload.
    * @Param outData: Output buffer (must be allocated with ipc_alloc).
    * @Param outSize: Output size.
  }
procedure IPC_Connect_Handler(trigger: Pointer; data: Pointer; Size: TSize_t; out outData: Pointer; out outSize: TSize_t); cdecl;

{ * Notify handler for client‑initiated disconnection.
  * Payload: 4‑byte ID of the client to disconnect.
  * @Param trigger: Pointer to the TZNet_Server_IPC instance.
  * @Param data: Pointer to the 4-byte client ID.
  * @Param Size: Should be 4 bytes.
}
procedure IPC_Close_Handler(trigger: Pointer; data: Pointer; Size: TSize_t); cdecl;

{ * Notify handler for incoming data from a client.
  * Payload: [4‑byte ID] + [binary data].
  * @Param trigger: Pointer to the TZNet_Server_IPC instance.
  * @Param data: Pointer to the payload (ID + data).
  * @Param Size: Total size (>=4).
}
procedure IPC_Buff_Handler(trigger: Pointer; data: Pointer; Size: TSize_t); cdecl;

implementation

{ ============================================================================== }
{ Global callback implementations }
{ ============================================================================== }

{ * IPC_Connect_Handler – Handles the "connect" RPC call from a new client.
  * This is a synchronous RPC handler; it creates a new PeerIO object,
  * extracts the client's response queue name from the request data,
  * generates two unique notification names for this client,
  * and returns them as a binary reply.
  *
  * The notification names are generated using the server's queue name and
  * the client's ID, ensuring uniqueness.
  *
  * After the reply is sent, the client will register handlers for these names
  * on its side, and the server will use these names when sending notifications
  * to this client via ipc_server_send_notify_binary.
}
procedure IPC_Connect_Handler(trigger: Pointer; data: Pointer; Size: TSize_t; out outData: Pointer; out outSize: TSize_t);
var
  Inst: TZNet_Server_IPC;
  io_: TZNet_Server_IPC_PeerIO;
  m64: TMem64;
begin
  if trigger = nil then
      exit;
  Inst := TZNet_Server_IPC(trigger);

  // Create a new PeerIO object for this client (it will be added to the server's pool)
  Inst.Critical.Lock;
  try
    io_ := TZNet_Server_IPC_PeerIO.Create(Inst, nil);

    // Read the client's response queue name from the request data (a string)
    m64 := TMem64.Create;
    m64.Mapping(data, Size);
    io_.FRespQueueName := m64.ReadString;
    DisposeObject(m64);

    // Generate two unique notification names for this client
    // Format: "<main_queue>-C<clientID>-buff" and "...-disconnect"
    io_.FSend_Buff_CMD_Notify := PFormat('%s-C%d-buff', [Inst.ipc_queue_name.Text, io_.ID]);
    io_.FDisconnect_CMD_Notify := PFormat('%s-C%d-disconnect', [Inst.ipc_queue_name.Text, io_.ID]);

    // Build the reply: server‑assigned ID (4 bytes) + two strings (notification names)
    m64 := TMem64.Create;
    m64.WriteUInt32(io_.ID); // send back the ID that the client must use
    m64.WriteString(io_.FSend_Buff_CMD_Notify);
    m64.WriteString(io_.FDisconnect_CMD_Notify);

    // Allocate reply buffer using ipc_alloc (required for RPC replies)
    outSize := m64.Size;
    outData := ipc_alloc(outSize);
    CopyPtr(m64.Memory, outData, outSize);
    DisposeObject(m64);
  finally
      Inst.Critical.UnLock;
  end;
end;

{ * IPC_Close_Handler – Handles the "close" notification from a client.
  * This is an asynchronous notify handler. The payload is a 4-byte ID of the
  * client that wishes to disconnect. We find the PeerIO object by that ID and
  * call its Disconnect method (which marks it for delayed freeing).
}
procedure IPC_Close_Handler(trigger: Pointer; data: Pointer; Size: TSize_t);
var
  Inst: TZNet_Server_IPC;
  io_: TZNet_Server_IPC_PeerIO;
begin
  if trigger = nil then
      exit;
  Inst := TZNet_Server_IPC(trigger);
  if Size <> 4 then
      exit; // invalid payload

  Inst.Critical.Lock;
  try
    // Retrieve the PeerIO from the server's pool using the ID
    io_ := Inst.IOPool[PCardinal(data)^] as TZNet_Server_IPC_PeerIO;
    if io_ <> nil then
        io_.DelayFree // Mark for delayed destruction (framework will free it later)
    else
        Inst.PrintError('IPC_Buff_Handler-IO error:%d', [PCardinal(data)^]);
  finally
      Inst.Critical.UnLock;
  end;
end;

{ * IPC_Buff_Handler – Handles incoming data from a client.
  * Payload format: [4-byte ID] + [binary data].
  * We find the PeerIO with that ID and pass the rest of the data to its
  * Write_Physics_Fragment method, which will process it as a network packet.
}
procedure IPC_Buff_Handler(trigger: Pointer; data: Pointer; Size: TSize_t);
var
  Inst: TZNet_Server_IPC;
  io_: TZNet_Server_IPC_PeerIO;
begin
  if trigger = nil then
      exit;
  Inst := TZNet_Server_IPC(trigger);
  if Size <= 4 then
      exit;

  Inst.Critical.Lock;
  try
    io_ := Inst.IOPool[PCardinal(data)^] as TZNet_Server_IPC_PeerIO;
    if io_ <> nil then
        io_.Write_Physics_Fragment(GetPtr(data, 4), Size - 4) // Skip the ID header
    else
        Inst.PrintError('IPC_Buff_Handler-IO error:%d', [PCardinal(data)^]);
  finally
      Inst.Critical.UnLock;
  end;
end;

{ ============================================================================== }
{ TZNet_Server_IPC_PeerIO }
{ ============================================================================== }

procedure TZNet_Server_IPC_PeerIO.CreateAfter;
begin
  inherited CreateAfter;
  FRespQueueName := '';
  FSend_Buff_CMD_Notify := '';
  FDisconnect_CMD_Notify := '';
  FTempBuff := TMem64.CustomCreate($FFFF); // Pre‑allocate 64KB buffer
end;

destructor TZNet_Server_IPC_PeerIO.Destroy;
begin
  DisposeObject(FTempBuff);
  inherited Destroy;
end;

{ Connected is always true as long as the object exists }
function TZNet_Server_IPC_PeerIO.Connected: Boolean;
begin
  Result := True;
end;

{ * Disconnect – Initiate disconnection of this client.
  * Sends a disconnect notification to the client using its specific
  * FDisconnect_CMD_Notify name, and then schedules this PeerIO for freeing.
  * The server framework will remove it from the pool after the delay.
}
procedure TZNet_Server_IPC_PeerIO.Disconnect;
var
  serv: TZNet_Server_IPC;
  id_: Cardinal;
begin
  Print('Disconnect');
  serv := OwnerFramework as TZNet_Server_IPC;
  id_ := ID;

  // Send the disconnect notification to the client
  if serv.ipc_serv <> nil then
      serv.ipc_serv.SendNotifyBinary(FRespQueueName, FDisconnect_CMD_Notify, @id_, 4);

  // Mark this object for delayed destruction (framework method)
  DelayFree;
end;

{ Append raw data to the outgoing buffer }
procedure TZNet_Server_IPC_PeerIO.Write_IO_Buffer(const buff: PByte; const Size: nativeInt);
begin
  FTempBuff.Position := FTempBuff.Size;
  FTempBuff.WritePtr(buff, Size);
end;

{ Prepare to write a new packet: clear buffer (no header needed for server->client,
  because the client expects raw data; the ID is not needed in this direction) }
procedure TZNet_Server_IPC_PeerIO.WriteBufferOpen;
begin
  FTempBuff.Clear;
end;

{ Flush the buffered packet: send it to the client via IPC notification.
  The server uses ipc_server_send_notify_binary to send the data to the
  client's response queue, using the client‑specific FSend_Buff_CMD_Notify name.
}
procedure TZNet_Server_IPC_PeerIO.WriteBufferFlush;
var
  serv: TZNet_Server_IPC;
  r: Integer;
begin
  serv := OwnerFramework as TZNet_Server_IPC;
  if serv.ipc_serv <> nil then
      r := serv.ipc_serv.SendNotifyBinary(FRespQueueName, FSend_Buff_CMD_Notify, FTempBuff.Memory, FTempBuff.Size)
  else
      r := IPC_ERR_UNKNOWN;
  FTempBuff.Clear;
  if r <> IPC_OK then
      Disconnect; // if send fails, the connection is broken
end;

{ Discard unsent data }
procedure TZNet_Server_IPC_PeerIO.WriteBufferClose;
begin
  FTempBuff.Clear;
end;

function TZNet_Server_IPC_PeerIO.GetPeerIP: SystemString;
begin
  Result := FRespQueueName; // use the client's response queue name as identifier
end;

function TZNet_Server_IPC_PeerIO.WriteBuffer_is_NULL: Boolean;
begin
  Result := FTempBuff.Size = 0;
end;

procedure TZNet_Server_IPC_PeerIO.DoP2PVM_Created(Sender: TZNet_P2PVM);
begin
  inherited DoP2PVM_Created(Sender);
  Sender.MaxVMFragmentSize := 32 * 1024; // Maximum fragment size for VM packets
  Sender.Progress_Send_Size := 8 * 1024 * 1024; // Send progress chunk size: 8 MB
end;

procedure TZNet_Server_IPC_PeerIO.DoP2PVM_InstallLogicFramework(Inst: TZNet);
begin
  inherited DoP2PVM_InstallLogicFramework(Inst);
  Inst.SwitchMaxPerformance;
  Inst.SequencePacketActivted := False;
end;

procedure TZNet_Server_IPC_PeerIO.Progress;
begin
  inherited Progress;
  Process_Send_Buffer(); // Flush any queued data
end;

{ ============================================================================== }
{ TZNet_Server_IPC }
{ ============================================================================== }

constructor TZNet_Server_IPC.Create;
begin
  inherited Create;
  SequencePacketActivted := True; // Enable sequence packet processing
  TimeOutKeepAlive := True; // Use keep‑alive timeout mechanism
  SendFlushSize := 32 * 1024; // Flush size: 32KB
  SwitchMaxPerformance; // Optimize for performance
  Critical := TCritical.Create(ClassName + '.Critical');
  TimeOut := 10 * 1000; // 10 seconds timeout (for underlying emulation)
  ipc_serv := nil;
end;

destructor TZNet_Server_IPC.Destroy;
begin
  StopService;
  DisposeObject(Critical);
  inherited Destroy;
end;

{ * StartService – Initialise the IPC server.
  * Creates a TIPCServer with the main queue named "<Host>-<Port>".
  * The server is configured with 5 worker threads, max queue length 1024,
  * and max message size 1024 bytes (for control messages).
  * Then registers the three handlers: "connect" (RPC), "close" and "buff" (notify).
}
function TZNet_Server_IPC.StartService(Host: SystemString; Port: Word): Boolean;
var
  n_host: U_String;
begin
  StopService;
  ipc_serv := TIPCServer.Create;

  n_host := Host;
  if umlMultipleMatch('ipc:*', umlTrimSpace(n_host)) then
      n_host := umlTrimSpace(umlDeleteFirstStr(n_host, ':'));

  ipc_queue_name := Format('%s%d', [n_host.Text, Port]);

  // Start the server with explicit configuration
  Result := ipc_serv.StartEx(ipc_queue_name, IPC_Serv_ThreadCount, IPC_Serv_MaxQueueLength, IPC_Serv_MaxMsgSize);
  if Result then
    begin
      // Register the RPC handler for connection establishment
      ipc_serv.RegisterBinaryHandler('connect', IPC_Connect_Handler, self);
      // Register notify handlers for client‑sent messages
      ipc_serv.RegisterBinaryNotify('close', IPC_Close_Handler, self);
      ipc_serv.RegisterBinaryNotify('buff', IPC_Buff_Handler, self);
    end;
end;

{ * StopService – Shut down the server.
  * Disconnects all connected clients by iterating the IOPool and calling
  * Disconnect on each PeerIO. Then stops the IPC server and frees it.
}
procedure TZNet_Server_IPC.StopService;
var
  IO_Array: TIO_Array;
  pframeworkID: Cardinal;
  c: TPeerIO;
begin
  // Disconnect all clients
  if (PeerIO_HashPool.Count > 0) then
    begin
      GetIO_Array(IO_Array);
      for pframeworkID in IO_Array do
        begin
          c := PeerIO_HashPool[pframeworkID];
          if c <> nil then
            begin
              try
                  c.Disconnect;
              except
              end;
            end;
        end;
    end;

  Progress; // Process any pending events (e.g., delayed frees)

  if ipc_serv = nil then
      exit;

  ipc_serv.Stop; // Stop the low‑level IPC server
  DisposeObjectAndNil(ipc_serv);
end;

procedure TZNet_Server_IPC.Progress;
begin
  inherited Progress;
end;

{ * Overridden to raise an error because IPC does not support
  * synchronous command/stream waiting. All communication is asynchronous.
}
function TZNet_Server_IPC.WaitSendConsoleCmd(p_io: TPeerIO;
  const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString;
begin
  Result := '';
  RaiseInfo('WaitSend no Suppport');
end;

procedure TZNet_Server_IPC.WaitSendStreamCmd(p_io: TPeerIO;
  const Cmd: SystemString; StreamData, ResultData: TDFE; TimeOut_: TTimeTick);
begin
  RaiseInfo('WaitSend no Suppport');
end;

initialization

{$IFDEF CPU64}
TZNet_Server_IPC.IPC_Serv_ThreadCount := 4;
TZNet_Server_IPC.IPC_Serv_MaxQueueLength := 1024;
TZNet_Server_IPC.IPC_Serv_MaxMsgSize := 32 * 1024;
{$ELSE CPU64}
TZNet_Server_IPC.IPC_Serv_ThreadCount := 2;
TZNet_Server_IPC.IPC_Serv_MaxQueueLength := 1024;
TZNet_Server_IPC.IPC_Serv_MaxMsgSize := 1024;
{$ENDIF CPU64}

finalization

end.
 
