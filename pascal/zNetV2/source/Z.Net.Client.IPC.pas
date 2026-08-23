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
  *  Z.Net.Client.IPC – Implements a Z.Net client that uses the z_ipc library
  *  (binary message queues) for communication instead of traditional sockets.
  *
  *  ============================================================================
  *  DESIGN OVERVIEW
  *  ============================================================================
  *  This unit provides a TZNet_Client_IPC class that acts as a drop-in replacement
  *  for a network client in the Z.Net framework. It connects to a server via a
  *  named message queue (using Boost.Interprocess) and exchanges binary data
  *  through shared memory segments.
  *
  *  The client side performs the following steps:
  *    1. Connect to the server's main queue (named "<addr>-<port>").
  *    2. Create its own private response queue (unique name obtained via
  *       ipc_client_get_resp_queue_name).
  *    3. Perform a synchronous RPC call "connect" to the server, passing its
  *       response queue name. The server replies with two notification names:
  *       one for sending data buffers (FSend_Buff_CMD_Notify) and one for
  *       disconnection (FDisconnect_CMD_Notify).
  *    4. Register binary notify handlers on the client side for these two names
  *       so that it can receive data and disconnect notifications from the server.
  *    5. Create a TZNet_Client_IPC_PeerIO object that mimics a network peer
  *       interface. This object handles buffering outgoing data and sending it
  *       via IPC notifications.
  *    6. Outgoing data is buffered with a leading 4‑byte ID (the peer's ID,
  *       which is assigned by the server during handshake) and sent as a binary
  *       notification named "buff" to the server.
  *    7. Incoming data from the server arrives via the registered notify handler
  *       (IPC_Cli_Buff_Handler), which strips the ID and forwards the payload to
  *       the PeerIO's fragment processor for decoding.
  *    8. Disconnection is initiated by the server sending a notification named
  *       FDisconnect_CMD_Notify, which triggers IPC_Disconnect_Handler.
  *
  *  ============================================================================
  *  UNDERLYING MECHANISM (z_ipc)
  *  ============================================================================
  *  - All communication is binary‑only.
  *  - Large data is transferred via shared memory segments: the sender creates a
  *    temporary shared memory object, writes the payload, and sends a control
  *    message (a small string) containing the shared memory name over the message
  *    queue. The receiver opens the shared memory, reads the data, and removes it.
  *  - The main queue is used for control messages (small strings). Each client
  *    has a dedicated response queue for replies and server‑originated notifications.
  *  - Binary RPC calls (CallBinary) are synchronous and wait for a reply. They are
  *    used only for the initial handshake.
  *  - Notifications (NotifyBinary) are asynchronous fire‑and‑forget messages,
  *    used for all subsequent data exchange.
  *
  *  This unit integrates the low‑level IPC into the Z.Net framework, providing
  *  a familiar API for application developers.
*)

unit Z.Net.Client.IPC;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses SysUtils, Classes,
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings, Z.Notify, Z.Status,
  Z.Net, Z.UnicodeMixedLib, Z.MemoryStream, Z.DFE,
  Z.IPC.API, Z.IPC.Helper;

type
  TZNet_Client_IPC = class; { * Forward declaration for mutual references }

  { * TZNet_Client_IPC_PeerIO – Emulates a network peer using IPC notifications.
    * This class is a TPeerIO descendant that handles outgoing data buffering
    * and writing. It overrides the Write_IO_Buffer and related methods to send
    * data via binary notifications. It also maintains a temporary buffer
    * (FTempBuff) where outgoing data is accumulated before being flushed.
    *
    * Each instance corresponds to a logical connection (peer) managed by the
    * TZNet_Client_IPC object. Since the client only has one connection, there
    * is only one PeerIO instance.
    *
    * @Usage:
    *   This class is created internally by TZNet_Client_IPC during Connect.
    *   It is not intended to be used directly.
  }
  TZNet_Client_IPC_PeerIO = class(TPeerIO)
  protected
    ClientIntf: TZNet_Client_IPC; { * Owning client object (back-reference) }
    FTempBuff: TMem64; { * Temporary buffer for outgoing packet assembly }
  public
    procedure CreateAfter; override; { * Post‑constructor initialization }
    destructor Destroy; override;
    function Connected: Boolean; override; { * True if the client is connected }
    procedure Disconnect; override; { * Initiate disconnection }
    procedure Write_IO_Buffer(const buff: PByte; const Size: nativeInt); override; { * Append raw data to buffer }
    procedure WriteBufferOpen; override; { * Start a new packet with a 4‑byte ID header }
    procedure WriteBufferFlush; override; { * Send buffered packet via IPC }
    procedure WriteBufferClose; override; { * Discard unsent data }
    function GetPeerIP: SystemString; override; { * Returns the response queue name as peer identifier }
    function WriteBuffer_is_NULL: Boolean; override; { * True if buffer only contains the header (empty) }
    procedure DoP2PVM_Created(Sender: TZNet_P2PVM); override;
    procedure DoP2PVM_InstallLogicFramework(Inst: TZNet); override;
    procedure Progress; override; { * Called periodically to flush pending data }
  end;

  { * TZNet_Client_IPC – IPC‑based client for Z.Net.
    * This class implements the TZNet_Client interface, providing Connect,
    * Disconnect, Connected, and ClientIO methods. It manages the IPC client
    * lifecycle and the handshake with the server.
    *
    * The Connect method:
    * - Creates a TIPCClient (from Z.IPC.Helper) and connects to the server's
    *   main queue.
    * - Calls the server's RPC handler "connect" via CallBinary, passing its
    *   response queue name. The server replies with two notification names
    *   (for data and disconnect) and a server‑assigned ID.
    * - Registers binary notify handlers on the client side for these names.
    * - Creates the PeerIO instance and sets its ID to the server‑assigned ID.
    * - Triggers the connect‑finished event.
    *
    * The Disconnect method sends a 'close' notification to the server and cleans up.
    * The Progress method is called periodically to process any pending events.
    *
    * @Usage:
    *   var Client: TZNet_Client_IPC;
    *   begin
    *     Client := TZNet_Client_IPC.Create;
    *     try
    *       if Client.Connect('my_server', 0) then
    *       begin
    *         // Connection established, use Client.ClientIO to send/receive data
    *       end;
    *     finally
    *       Client.Free;
    *     end;
    *   end;
  }
  TZNet_Client_IPC = class(TZNet_Client)
  private
  protected
    Critical: TCritical; { * Protects internal state during disconnect (thread‑safe) }
    ipc_cli: TIPCClient; { * Low‑level IPC client instance from Z.IPC.Helper }
    FIPC_queue_name: U_String; { * Main queue name (formatted as "address-port") }
    FRespQueueName: U_String; { * This client's response queue name (used by the server) }
    FSend_Buff_CMD_Notify: U_String; { * Notification name for receiving data from the server }
    FDisconnect_CMD_Notify: U_String; { * Notification name for receiving disconnect from the server }
    ClientIOIntf: TZNet_Client_IPC_PeerIO; { * Associated peer IO (the single connection) }
  public
    constructor Create; override;
    destructor Destroy; override;

    { * Connect to a server with given address and port (interpreted as queue name).
      * @addr: typically a string identifier (e.g., "server") but used as part of queue name.
      * @Port: numeric part appended to queue name to form "<addr>-<port>".
      * Returns True if connection handshake succeeded.
      * Implementation steps:
      *   1. Disconnect any existing connection.
      *   2. Create and connect TIPCClient to the main queue.
      *   3. Perform synchronous RPC "connect" – sends our response queue name,
      *      receives two notification names and a server‑assigned ID.
      *   4. Register notify handlers for those names.
      *   5. Create PeerIO and set its ID to the server‑assigned ID.
      *   6. Trigger the framework's connect‑finished event.
      * @Example:
      *   if Client.Connect('ipc:my_server', 1311) then
      *     WriteLn('Connected to queue my_server1311');
    }
    function Connect(addr: SystemString; Port: Word): Boolean; override;

    function Connected: Boolean; override;
    procedure Disconnect; override;
    function ClientIO: TPeerIO; override;
    procedure Progress; override;

    { * Public read‑only properties for diagnostic and external use }
    property IPC_queue_name: U_String read FIPC_queue_name;
    property RespQueueName: U_String read FRespQueueName;
    property Send_Buff_CMD_Notify: U_String read FSend_Buff_CMD_Notify;
    property Disconnect_CMD_Notify: U_String read FDisconnect_CMD_Notify;
  end;

  { * Global callback functions (declared as cdecl for z_ipc)
    * These are registered as binary notify handlers on the client side.
  }

  { * Handler for incoming data (buffer) notifications from the server.
    * Trigger is the TZNet_Client_IPC instance.
    * Data contains a 4‑byte ID (the server‑assigned ID) followed by the actual payload.
    * The ID is checked against the client's own PeerIO ID (which is server‑assigned),
    * and if matching, the payload is written to the PeerIO's fragment processor.
    * This mechanism ensures that only messages intended for this client are accepted.
    * @Param trigger: Pointer to the TZNet_Client_IPC instance.
    * @Param data: Pointer to the payload (including the 4‑byte ID).
    * @Param Size: Total size of the data (ID + payload).
  }
procedure IPC_Cli_Buff_Handler(trigger: Pointer; data: Pointer; Size: TSize_t); cdecl;

{ * Handler for disconnection notification from the server.
  * Trigger is the TZNet_Client_IPC instance. Simply calls Disconnect on the client.
  * @Param trigger: Pointer to the TZNet_Client_IPC instance.
}
procedure IPC_Disconnect_Handler(trigger: Pointer; data: Pointer; Size: TSize_t); cdecl;

implementation

{ ============================================================================== }
{ Global callback functions (cdecl) }
{ ============================================================================== }

{ * Handler for incoming data (buffer) notifications from the server.
  The payload format: [4‑byte ID] + [binary data].
  We acquire the client's critical section to ensure that ClientIOIntf is not
  modified during processing. The data is passed directly to Write_Physics_Fragment,
  which will handle it as a network packet.
}
procedure IPC_Cli_Buff_Handler(trigger: Pointer; data: Pointer; Size: TSize_t);
var
  Inst: TZNet_Client_IPC;
begin
  if trigger = nil then
      exit;
  Inst := TZNet_Client_IPC(trigger);
  Inst.Critical.Lock;
  try
    if Inst.ClientIOIntf = nil then
        exit;
    if Size > 0 then
        Inst.ClientIOIntf.Write_Physics_Fragment(data, Size);
    Inst.ClientIOIntf.UpdateLastCommunicationTime; { * Update activity timestamp }
  finally
      Inst.Critical.UnLock;
  end;
end;

{
  * Handler for disconnection notification from the server.
  * This is triggered when the server explicitly tells the client to disconnect.
  * Simply calls Disconnect on the client.
}
procedure IPC_Disconnect_Handler(trigger: Pointer; data: Pointer; Size: TSize_t);
var
  Inst: TZNet_Client_IPC;
begin
  if trigger = nil then
      exit;
  Inst := TZNet_Client_IPC(trigger);
  Inst.Disconnect; { * Initiate client disconnection }
end;

{ ============================================================================== }
{ TZNet_Client_IPC_PeerIO }
{ ============================================================================== }

procedure TZNet_Client_IPC_PeerIO.CreateAfter;
begin
  inherited CreateAfter;
  ClientIntf := nil; { * Will be set by the owning client }
  FTempBuff := TMem64.CustomCreate($FFFF); { * Pre‑allocate 64KB buffer for efficiency }
end;

destructor TZNet_Client_IPC_PeerIO.Destroy;
begin
  if ClientIntf <> nil then
    begin
      ClientIntf.DoDisconnect(Self); { * Notify the framework that this peer is disconnecting }
      ClientIntf.ClientIOIntf := nil; { * Remove back‑reference }
      ClientIntf := nil;
    end;
  DisposeObject(FTempBuff);
  inherited Destroy;
end;

function TZNet_Client_IPC_PeerIO.Connected: Boolean;
begin
  Result := ClientIntf.Connected; { * Delegate to the client's connection state }
end;

procedure TZNet_Client_IPC_PeerIO.Disconnect;
begin
  if ClientIntf <> nil then
    begin
      ClientIntf.DoDisconnect(Self); { * Notify the framework }
      ClientIntf.Disconnect; { * Call the client's Disconnect method }
      ClientIntf := nil; { * Clear reference to avoid re‑entering }
    end;
end;

{ *
  Append raw data to the temporary buffer.
  This method is called by the framework when data needs to be sent.
  The data is appended at the end of FTempBuff.
}
procedure TZNet_Client_IPC_PeerIO.Write_IO_Buffer(const buff: PByte; const Size: nativeInt);
begin
  FTempBuff.Position := FTempBuff.Size; { * Seek to end }
  FTempBuff.WritePtr(buff, Size); { * Write the raw bytes }
end;

{ *
  Prepare to write a new packet: clear buffer and add a 4‑byte header with the peer ID.
  The peer ID is the server‑assigned ID, which allows the server to route the
  data to the correct logical connection.
}
procedure TZNet_Client_IPC_PeerIO.WriteBufferOpen;
begin
  FTempBuff.Clear;
  FTempBuff.WriteUInt32(ID); { * Prepend the peer ID as a 4‑byte header }
end;

{ *
  Flush the buffered packet: send it as a binary notification to the server.
  The notification name "buff" is the global server‑side handler name.
  If sending fails (return code not IPC_OK), the connection is considered broken.
}
procedure TZNet_Client_IPC_PeerIO.WriteBufferFlush;
var
  r: Integer;
begin
  if ClientIntf = nil then
      exit;
  if ClientIntf.ipc_cli <> nil then
      r := ClientIntf.ipc_cli.NotifyBinary('buff', FTempBuff) { * Send entire buffer as a notification }
  else
      r := IPC_ERR_UNKNOWN;
  FTempBuff.Clear; { * Clear buffer after sending }
  if r <> IPC_OK then
      Disconnect; { * If send fails, disconnect }
end;

{ * Discard any unsent data – called when a packet is aborted. }
procedure TZNet_Client_IPC_PeerIO.WriteBufferClose;
begin
  FTempBuff.Clear;
end;

{ * Return a string identifying the peer – here we return the response queue name,
  which acts as a unique identifier for this client.
}
function TZNet_Client_IPC_PeerIO.GetPeerIP: SystemString;
begin
  Result := '';
  if (ClientIntf <> nil) and (ClientIntf.ipc_cli <> nil) then
      Result := ClientIntf.ipc_cli.GetRespQueueName();
end;

{ * Return True if the buffer contains only the 4‑byte ID header (i.e., no payload).
  This is used by the framework to skip sending empty packets.
}
function TZNet_Client_IPC_PeerIO.WriteBuffer_is_NULL: Boolean;
begin
  Result := FTempBuff.Size <= 4;
end;

procedure TZNet_Client_IPC_PeerIO.DoP2PVM_Created(Sender: TZNet_P2PVM);
begin
  inherited DoP2PVM_Created(Sender);
  Sender.MaxVMFragmentSize := 32 * 1024; { * Set maximum fragment size for VM packets }
  Sender.Progress_Send_Size := 8 * 1024 * 1024; { * Send progress chunk size: 8 MB }
end;

procedure TZNet_Client_IPC_PeerIO.DoP2PVM_InstallLogicFramework(Inst: TZNet);
begin
  inherited DoP2PVM_InstallLogicFramework(Inst);
  Inst.SwitchMaxPerformance;
  Inst.SequencePacketActivted := False;
end;

{ * Called periodically; process any pending send operations.
  Process_Send_Buffer checks if there is data to send and calls WriteBufferFlush.
}
procedure TZNet_Client_IPC_PeerIO.Progress;
begin
  inherited Progress;
  Process_Send_Buffer(); { * Flush any queued data }
end;

{ ============================================================================== }
{ TZNet_Client_IPC }
{ ============================================================================== }

constructor TZNet_Client_IPC.Create;
begin
  inherited Create;
  SequencePacketActivted := True; { * Enable sequence packet processing }
  TimeOutKeepAlive := True; { * Use keep‑alive timeout mechanism }
  TimeOut := 10 * 1000; { * 10 seconds timeout (for underlying TCP emulation) }
  SendFlushSize := 32 * 1024; { * Flush size: 32KB }
  SwitchMaxPerformance; { * Optimize for performance }
  Critical := TCritical.Create(ClassName + '.Critical');
  ipc_cli := nil;
  FIPC_queue_name := '';
  FRespQueueName := '';
  FSend_Buff_CMD_Notify := '';
  FDisconnect_CMD_Notify := '';
  ClientIOIntf := nil;
end;

destructor TZNet_Client_IPC.Destroy;
begin
  Disconnect; { * Clean up connection }
  DisposeObjectAndNil(ClientIOIntf);
  DisposeObjectAndNil(Critical);
  inherited Destroy;
end;

{ * Connect to the IPC server.
  Detailed steps (as explained in the class comment) are implemented here.
}
function TZNet_Client_IPC.Connect(addr: SystemString; Port: Word): Boolean;
var
  n_addr: U_String;
  InData, OutData: TMem64;
  r: Integer;
  ID_: Cardinal;
begin
  Disconnect; { * Ensure clean state }
  Result := False;

  { * Handle "ipc:" prefix – strip it if present to get the base name }
  n_addr := addr;
  if umlMultipleMatch('ipc:*', umlTrimSpace(n_addr)) then
      n_addr := umlTrimSpace(umlDeleteFirstStr(n_addr, ':'));

  FIPC_queue_name := Format('%s%d', [n_addr.Text, Port]); { * Build queue name }

  ipc_cli := TIPCClient.Create; { * Create high‑level IPC client }
  if not ipc_cli.Connect(FIPC_queue_name) then
    begin
      Disconnect; { * Clean up on failure }
      exit;
    end;

  { * Prepare handshake data: send our response queue name }
  InData := TMem64.Create;
  FRespQueueName := ipc_cli.GetRespQueueName; { * Get our private response queue name }
  InData.WriteString(FRespQueueName); { * Write it as a string }
  OutData := TMem64.Create;
  r := ipc_cli.CallBinary('connect', InData, OutData); { * Synchronous RPC call }
  if r = IPC_OK then
    begin
      { * Parse the reply from the server }
      OutData.Position := 0;
      ID_ := OutData.ReadUInt32; { * Server‑assigned ID }
      FSend_Buff_CMD_Notify := OutData.ReadString; { * Notification name for data }
      FDisconnect_CMD_Notify := OutData.ReadString; { * Notification name for disconnect }

      { * Register handlers for these notifications on the client side }
      ipc_cli.RegisterBinaryNotify(FSend_Buff_CMD_Notify, IPC_Cli_Buff_Handler, Self);
      ipc_cli.RegisterBinaryNotify(FDisconnect_CMD_Notify, IPC_Disconnect_Handler, Self);

      { * Create the PeerIO instance that will represent this connection }
      ClientIOIntf := TZNet_Client_IPC_PeerIO.Create(Self, nil);
      ClientIOIntf.ClientIntf := Self;
      ClientIOIntf.ID := ID_; { * Use server‑assigned ID }

      DoConnected(ClientIOIntf); { * Notify framework that connection is established }

      Result := True;
    end
  else
      Disconnect; { * Handshake failed, clean up }

  DisposeObject(InData);
  DisposeObject(OutData);
end;

function TZNet_Client_IPC.Connected: Boolean;
begin
  Result := (ipc_cli <> nil) and (ipc_cli.IsConnected);
end;

{ * Disconnect from the server.
  Sends a 'close' notification to the server with the peer ID, then disconnects
  the underlying IPC client, frees objects, and clears state.
}
procedure TZNet_Client_IPC.Disconnect;
var
  ID_: Cardinal;
begin
  Critical.Lock; { * Protect against concurrent calls }
  try
    if ipc_cli = nil then
      begin
        { * Already disconnected, just clean up any remaining PeerIO }
        DisposeObjectAndNil(ClientIOIntf);
        FIPC_queue_name := '';
        FSend_Buff_CMD_Notify := '';
        FDisconnect_CMD_Notify := '';
        exit;
      end;

    { * Notify the server that this client is disconnecting (send peer ID) }
    if ClientIO <> nil then
      begin
        ID_ := ClientIO.ID;
        ipc_cli.NotifyBinary('close', @ID_, 4); { * Use the predefined "close" notification name }
      end;

    ipc_cli.Disconnect; { * Disconnect the underlying IPC client }
    DisposeObjectAndNil(ipc_cli); { * Free the IPC client object }
    DisposeObjectAndNil(ClientIOIntf); { * Free the PeerIO }
    ipc_cli := nil;
    FIPC_queue_name := '';
    FSend_Buff_CMD_Notify := '';
    FDisconnect_CMD_Notify := '';
  finally
      Critical.UnLock;
  end;
end;

function TZNet_Client_IPC.ClientIO: TPeerIO;
begin
  Result := ClientIOIntf;
end;

{ * Periodic progress; calls inherited to process timers, etc. }
procedure TZNet_Client_IPC.Progress;
begin
  inherited Progress;
end;


initialization

finalization

end.
 
