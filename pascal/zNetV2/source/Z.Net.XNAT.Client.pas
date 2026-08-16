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
{ ******************************************************************************
  * XNAT Client Implementation
  * Implements the internal agent that connects to the XNAT Service, establishes
  * P2PVM tunnels, and maps local services to remote public endpoints.
  *
  * Core classes:
  *   – TXNATClient: Main client controller, manages the physics connection and
  *     all mappings.
  *   – TXClientMapping: Handles a single mapping, creates send/receive tunnels,
  *     and forwards traffic to the local target service.
  *   – TXClientCustomProtocol: Represents an individual connection to a local
  *     service, bridging data to/from the XNAT tunnel.
  *
  * Workflow:
  *   1. Configure Host, Port, AuthToken and call AddMapping for each local service.
  *   2. OpenTunnel connects to the Service and performs P2PVM authentication.
  *   3. On success, the Service returns tunnel addresses via C_IPV6Listen,
  *      and each mapping opens its P2PVM tunnels.
  *   4. External requests are received through the receive tunnel, converted to
  *      local connections, and data is forwarded bidirectionally.
  *   5. Workload updates are sent periodically to enable service‑side load balancing.
  ****************************************************************************** }

unit Z.Net.XNAT.Client;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses
{$IFDEF FPC}
  Z.FPC.GenericList,
{$ENDIF FPC}
  Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.Status, Z.UnicodeMixedLib, Z.ListEngine, Z.TextDataEngine,
  Z.Cipher, Z.DFE, Z.MemoryStream, Z.Net, Z.Notify,
  Z.HashList.Templet, Z.Net.XNAT.Physics;

type
  TXNATClient = class; { Forward declaration of the main XNAT client class. }
  TXClientCustomProtocol = class; { Forward declaration of the custom protocol client. }
  TXClientCustomProtocol_List = TGenericsList<TXClientCustomProtocol>; { List of custom protocol clients. }

  { Represents a single port mapping on the XNAT client. It connects to the XNAT service,
    establishes P2PVM tunnels, and forwards external requests to the local target service. }
  TXClientMapping = class(TCore_Object_Intermediate)
  private
    FOwner: TXNATClient; { Parent XNAT client instance. Set in constructor. }
    FAddr: TPascalString; { Local target IP address to forward traffic to. Set by AddMapping. }
    FPort: TPascalString; { Local target port. Set by AddMapping. }
    FMapping: TPascalString; { Unique mapping name/identifier. Set by AddMapping. }

    FProtocol_Pool: TXClientCustomProtocol_List; { Pool of active custom protocol connections to local services. Created in Open. }
    FLast_Protocol_ID: Cardinal; { Counter for generating unique local protocol IDs. Initialised in Init. }
    FProtocol_Hash: TUInt32HashObjectList; { Hash map from local protocol ID to TXClientCustomProtocol instance. Created in Open. }

    FRecvTunnel: TZNet_WithP2PVM_Client; { P2PVM client for the receive tunnel (service -> client). Created in Open. }
    FRecvTunnel_IPV6: TPascalString; { IPv6 address of the receive tunnel (obtained from service response). Set by IPV6Listen_Result. }
    FRecvTunnel_Port: Word; { Port of the receive tunnel. Set by IPV6Listen_Result. }

    FSendTunnel: TZNet_WithP2PVM_Client; { P2PVM client for the send tunnel (client -> service). Created in Open. }
    FSendTunnel_IPV6: TPascalString; { IPv6 address of the send tunnel. Set by IPV6Listen_Result. }
    FSendTunnel_Port: Word; { Port of the send tunnel. Set by IPV6Listen_Result. }

    FMaxWorkload: Cardinal; { Maximum workload capacity reported to the service. Set by AddMapping. }
    FLastUpdateWorkload: Cardinal; { Last reported workload (number of active connections). Updated by UpdateWorkload. }
    FLastUpdateTime: TTimeTick; { Timestamp of the last workload update. Set by UpdateWorkload. }

    FRemote_ListenAddr, FRemote_ListenPort: TPascalString; { Remote listen address and port assigned by the service. Set by IPV6Listen_Result. }
    FXNat_Client_Tunnel: TXNATClient; { Back-reference to the parent client. Set in constructor. }

    Complete_Buffer_Sum: Int64; { Accumulated size of complete buffer data sent; used for flow control (NULL packet flush). Updated in OnReceiveBuffer. }

    procedure Init; { Initialises all fields to default values. Called by constructor. }
    procedure SendTunnel_ConnectResult(const cState: Boolean); { Callback when send tunnel connects. Invokes receive tunnel connection. }
    procedure RecvTunnel_ConnectResult(const cState: Boolean); { Callback when receive tunnel connects. Starts RequestListen. }

    procedure RequestListen_Result(Sender: TPeerIO; Result_: TDFE); { Callback for C_RequestListen response. Prints success/failure and updates workload. }
    procedure delay_RequestListen(Sender: TN_Post_Execute); { Delayed execution of RequestListen after receive tunnel is up. }

    procedure Open; { Initialises P2PVM tunnels, registers command handlers, and connects to the remote tunnels. }

    { Command handlers for incoming requests from the service. }
    procedure cmd_connect_request(Sender: TPeerIO; InData: TDFE); { Handles a connection request from the service. Creates a local connection to the target service. }
    procedure cmd_disconnect_request(Sender: TPeerIO; InData: TDFE); { Handles a disconnect request from the service. Disconnects the corresponding local connection. }
    procedure cmd_data(Sender: TPeerIO; InData: PByte; DataSize: NativeInt); { Forwards data payload from the service to the local target service. }

  public
    property Addr: TPascalString read FAddr; { Local target address. }
    property Port: TPascalString read FPort; { Local target port. }
    property Mapping: TPascalString read FMapping; { Mapping name. }

    constructor Create(Owner_: TXNATClient); virtual;
    destructor Destroy; override;

    { Sends a workload update to the service if changed or forced. }
    procedure UpdateWorkload(force: Boolean);
  end;

  { Meta-class for creating TXClientMapping instances. }
  TXClientMapping_Class = class of TXClientMapping;

  { Custom protocol client that connects to the local target service and bridges data to/from the XNAT tunnel. }
  TXClientCustomProtocol = class(TXPhysicsClient)
  protected
    procedure DoConnected(Sender: TPeerIO); override; { Called when local connection is established. }
    procedure DoDisconnect(Sender: TPeerIO); override; { Called when local connection is closed. Sends disconnect response to service. }
  public
    LocalProtocol_ID, RemoteProtocol_ID: Cardinal; { Local and remote protocol IDs for this connection. Set by cmd_connect_request. }
    Remote_IP: SystemString; { IP address of the remote client (from service). Set by cmd_connect_request. }
    FMapping: TXClientMapping; { Parent mapping. Set by cmd_connect_request. }
    Activted: Boolean; { True once the connection is fully active (local connection established). Set by OnConnect_Result. }
    RequestBuffer: TMS64; { Buffer for data received before activation. Created in constructor. }

    procedure OnReceiveBuffer(const buffer: PByte; const Size: NativeInt; var FillDone: Boolean); override; { Forwards received data to the service. }
    procedure OnConnect_Result(const cState: Boolean); { Callback for async connect to local service. Sends connect response to service. }
    constructor Create; override;
    destructor Destroy; override;
  end;

  { Special user data attached to the main physics tunnel connection. }
  TPhysicsEngine_Special = class(TPeer_IO_User_Special)
  protected
    FXNAT_VS: TXNATClient; { Reference to the owning XNAT client. Set by PeerIO_Create. }
    procedure PhysicsConnect_Result_BuildP2PToken(const cState: Boolean); { Callback when physics connection is established. }
    procedure PhysicsVMBuildAuthToken_Result; { Callback after P2PVM authentication token is built. }
    procedure PhysicsOpenVM_Result(const cState: Boolean); { Callback after P2PVM tunnel is opened. }
    procedure IPV6Listen_Result(Sender: TPeerIO; Result_: TDFE); { Callback for C_IPV6Listen response. Parses tunnel addresses for each mapping. }
  public
    constructor Create(Owner_: TPeerIO); override;
    destructor Destroy; override;
  end;

  { List of TXClientMapping instances. }
  TXClientMappingList = TGenericsList<TXClientMapping>;
  { Hash map from mapping name (string) to TXClientMapping instance. }
  TXClientHashMapping = TGeneric_String_Object_Hash<TXClientMapping>;
  { Callback type for tunnel open completion. }
  TOn_XNATClient_Open_Tunnel_Done = procedure(Sender: TXNATClient; State: Boolean) of object;

  { Main XNAT client class that manages the connection to the XNAT service and all port mappings. }
  TXNATClient = class(TCore_InterfacedObject_Intermediate, IIOInterface, IZNet_VMInterface)
  private
    FMappingList: TXClientMappingList; { List of all mappings. Created in constructor. }
    FHashMapping: TXClientHashMapping; { Hash map for fast lookup by mapping name. Created in constructor. }
    Activted: Boolean; { Indicates whether the client tunnel is active. Set in OpenTunnel. }
    WaitAsyncConnecting: Boolean; { True while an asynchronous connection attempt is in progress. Set in OpenTunnel (client mode). }
    WaitAsyncConnecting_BeginTime: TTimeTick; { Timestamp when the async connection attempt started. Set in OpenTunnel (client mode). }
    FPhysicsEngine: TZNet; { Underlying physics engine (server or client). Created/assigned in OpenTunnel. }
    FQuiet: Boolean; { If True, suppresses diagnostic output. Set by Set_Quiet. }

    { IIOInterface methods: called when a peer IO is created/destroyed. }
    procedure PeerIO_Create(const Sender: TPeerIO);
    procedure PeerIO_Destroy(const Sender: TPeerIO);

    { IZNet_VMInterface methods: P2PVM tunnel events. }
    procedure p2pVMTunnelAuth(Sender: TPeerIO; const Token: SystemString; var Accept: Boolean);
    procedure p2pVMTunnelOpenBefore(Sender: TPeerIO; p2pVMTunnel: TZNet_P2PVM);
    procedure p2pVMTunnelOpen(Sender: TPeerIO; p2pVMTunnel: TZNet_P2PVM);
    procedure p2pVMTunnelOpenAfter(Sender: TPeerIO; p2pVMTunnel: TZNet_P2PVM);
    procedure p2pVMTunnelClose(Sender: TPeerIO; p2pVMTunnel: TZNet_P2PVM);

    { Callback when the physics connection is established (client mode). }
    procedure PhysicsConnect_Result_BuildP2PToken(const cState: Boolean);

    { Triggers the On_Open_Tunnel_Done callback with the given state. }
    procedure Do_Open_Done(State: Boolean);

    { Sets the quiet mode and propagates it to all sub-components. }
    procedure Set_Quiet(const Value: Boolean);
  public
    { Tunnel parameters – set by the application before calling OpenTunnel. }
    Host: TPascalString; { Remote host address (for client mode) or local bind address (for server mode). }
    Port: TPascalString; { Remote or local port. Default '4921'. }
    AuthToken: TPascalString; { Authentication token for P2PVM tunnel. }
    MaxVMFragment: TPascalString; { Maximum fragment size for P2PVM packets. Default '8192'. }

    {
      Compression of CompleteBuffer packets using zLib.
      Feature of zLib: slow compression and fast decompression.
      XNAT is used for non‑compressed or non‑encrypted protocols; enabling this option can improve speed.
      Otherwise, if the protocol is already encrypted or compressed, enabling this adds CPU overhead.
      ProtocolCompressed is disabled by default.
    }
    ProtocolCompressed: Boolean;

    Instance_Class: TXClientMapping_Class; { Class reference for creating TXClientMapping instances. Default is TXClientMapping. }
    On_Open_Tunnel_Done: TOn_XNATClient_Open_Tunnel_Done; { Called when tunnel open operation completes (success or failure). }

  public
    property MappingList: TXClientMappingList read FMappingList; { List of all mappings. }
    property HashMapping: TXClientHashMapping read FHashMapping; { Hash map of mappings by name. }
    property PhysicsEngine: TZNet read FPhysicsEngine; { The underlying physics engine (server or client). }
    property Quiet: Boolean read FQuiet write Set_Quiet; { Quiet mode – suppresses log output. }

    constructor Create;
    destructor Destroy; override;

    { Adds a new mapping to the client. }
    procedure AddMapping(const MAddr, MPort, FMapping: TPascalString; FMaxWorkload: Cardinal);

    { Opens the tunnel using the specified physics model (server or client). }
    procedure OpenTunnel(MODEL: TXNAT_PHYSICS_MODEL); overload;
    { Opens the tunnel as a client (default). }
    procedure OpenTunnel; overload;

    { Main progress method – must be called periodically to drive all engines. }
    procedure Progress;
  end;

implementation

procedure TXClientMapping.Init;
begin
  FAddr := '';
  FPort := '';
  FMapping := '';
  FProtocol_Pool := nil;
  FLast_Protocol_ID := 1;
  FProtocol_Hash := nil;
  FRecvTunnel := nil;
  FRecvTunnel_IPV6 := '';
  FRecvTunnel_Port := 0;
  FSendTunnel := nil;
  FSendTunnel_IPV6 := '';
  FSendTunnel_Port := 0;
  FMaxWorkload := 100;
  FLastUpdateWorkload := 0;
  FLastUpdateTime := GetTimeTick();
  FRemote_ListenAddr := '';
  FRemote_ListenPort := '0';
  FXNat_Client_Tunnel := nil;
  Complete_Buffer_Sum := 0;
end;

procedure TXClientMapping.SendTunnel_ConnectResult(const cState: Boolean);
begin
  if cState then
    begin
      FSendTunnel.Print('[%s] Send Tunnel connect success.', [FMapping.Text]);
      if not FRecvTunnel.Connected then
          FRecvTunnel.AsyncConnectM(FRecvTunnel_IPV6, FRecvTunnel_Port, RecvTunnel_ConnectResult)
      else
          RecvTunnel_ConnectResult(True);
    end
  else
      FSendTunnel.Print('error: [%s] Send Tunnel connect failed!', [FMapping.Text]);
end;

procedure TXClientMapping.RecvTunnel_ConnectResult(const cState: Boolean);
begin
  if cState then
    begin
      FRecvTunnel.Print('[%s] Receive Tunnel connect success.', [FMapping.Text]);
      FSendTunnel.ProgressPost.PostExecuteM(0, delay_RequestListen);
    end
  else
      FRecvTunnel.Print('error: [%s] Receive Tunnel connect failed!', [FMapping.Text]);
end;

procedure TXClientMapping.RequestListen_Result(Sender: TPeerIO; Result_: TDFE);
begin
  if Result_.Reader.ReadBool then
    begin
      FSendTunnel.Print('success: remote host:%s port:%s mapping to host:%s port:%s', [FXNat_Client_Tunnel.Host.Text, FRemote_ListenPort.Text, FAddr.Text, FPort.Text]);
      UpdateWorkload(True);
    end
  else
      FSendTunnel.Print('failed: remote host:%s port:%s listen error!', [FXNat_Client_Tunnel.Host.Text, FRemote_ListenPort.Text]);
end;

procedure TXClientMapping.delay_RequestListen(Sender: TN_Post_Execute);
var
  de: TDFE;
begin
  de := TDFE.Create;
  de.WriteCardinal(FSendTunnel.RemoteID);
  de.WriteCardinal(FRecvTunnel.RemoteID);
  FSendTunnel.SendStreamCmdM(C_RequestListen, de, RequestListen_Result);
  disposeObject(de);
end;

procedure TXClientMapping.Open;
var
  io_array: TIO_Array;
  p_id: Cardinal;
  p_io: TPeerIO;
begin
  if FProtocol_Pool = nil then
      FProtocol_Pool := TXClientCustomProtocol_List.Create;

  if FProtocol_Hash = nil then
      FProtocol_Hash := TUInt32HashObjectList.CustomCreate(8192);

  if FRecvTunnel = nil then
    begin
      FRecvTunnel := TZNet_WithP2PVM_Client.Create;
      FRecvTunnel.QuietMode := FOwner.Quiet;
      FRecvTunnel.CompleteBufferSwapSpace := True;
    end;
  if FSendTunnel = nil then
    begin
      FSendTunnel := TZNet_WithP2PVM_Client.Create;
      FSendTunnel.QuietMode := FOwner.Quiet;
      FSendTunnel.CompleteBufferSwapSpace := True;
    end;

  FXNat_Client_Tunnel.FPhysicsEngine.GetIO_Array(io_array);
  for p_id in io_array do
    begin
      p_io := TPeerIO(FXNat_Client_Tunnel.FPhysicsEngine.PeerIO_HashPool[p_id]);
      if p_io <> nil then
        begin
          { uninstall p2pVM }
          p_io.p2pVMTunnel.UninstallLogicFramework(FSendTunnel);
          p_io.p2pVMTunnel.UninstallLogicFramework(FRecvTunnel);

          { install p2pVM }
          p_io.p2pVMTunnel.InstallLogicFramework(FSendTunnel);
          p_io.p2pVMTunnel.InstallLogicFramework(FRecvTunnel);
        end;
    end;
  SetLength(io_array, 0);

  { sequence sync }
  FRecvTunnel.SyncOnCompleteBuffer := True;
  FRecvTunnel.SyncOnResult := True;
  FRecvTunnel.SwitchMaxPerformance;

  FSendTunnel.SyncOnCompleteBuffer := True;
  FSendTunnel.SyncOnResult := True;
  FSendTunnel.SwitchMaxPerformance;

  { compressed complete buffer }
  FSendTunnel.CompleteBufferCompressed := FXNat_Client_Tunnel.ProtocolCompressed;
  FRecvTunnel.CompleteBufferCompressed := FXNat_Client_Tunnel.ProtocolCompressed;

  if not FRecvTunnel.ExistsRegistedCmd(C_Connect_request) then
      FRecvTunnel.RegisterStreamNotify(C_Connect_request).OnExecute := cmd_connect_request;

  if not FRecvTunnel.ExistsRegistedCmd(C_Disconnect_request) then
      FRecvTunnel.RegisterStreamNotify(C_Disconnect_request).OnExecute := cmd_disconnect_request;

  if not FRecvTunnel.ExistsRegistedCmd(C_Data) then
      FRecvTunnel.RegisterCompleteBuffer(C_Data).OnExecute := cmd_data;

  if not FSendTunnel.Connected then
      FSendTunnel.AsyncConnectM(FSendTunnel_IPV6, FSendTunnel_Port, SendTunnel_ConnectResult)
  else
      SendTunnel_ConnectResult(True);

  FSendTunnel.PrintParams[C_Connect_reponse] := False;
  FSendTunnel.PrintParams[C_Disconnect_reponse] := False;
  FSendTunnel.PrintParams[C_Data] := False;
  FSendTunnel.PrintParams[C_Workload] := False;

  FRecvTunnel.PrintParams[C_Connect_request] := False;
  FRecvTunnel.PrintParams[C_Disconnect_request] := False;
  FRecvTunnel.PrintParams[C_Data] := False;
end;

procedure TXClientMapping.cmd_connect_request(Sender: TPeerIO; InData: TDFE);
var
  Remote_id: Cardinal;
  Remote_IP: SystemString;
  xCli: TXClientCustomProtocol;
begin
  Remote_id := InData.Reader.ReadCardinal;
  Remote_IP := InData.Reader.ReadString;

  xCli := TXClientCustomProtocol.Create;
  xCli.QuietMode := FOwner.Quiet;
  xCli.Protocol := cpCustom;
  while FProtocol_Hash.Exists(FLast_Protocol_ID) do
      inc(FLast_Protocol_ID);
  xCli.LocalProtocol_ID := FLast_Protocol_ID;
  xCli.Remote_IP := Remote_IP;
  inc(FLast_Protocol_ID);
  FProtocol_Pool.Add(xCli);
  FProtocol_Hash.Add(xCli.LocalProtocol_ID, xCli, False);

  xCli.RemoteProtocol_ID := Remote_id;
  xCli.FMapping := Self;
  xCli.Activted := False;

  { async connection }
  xCli.AsyncConnectM(FAddr, umlStrToInt(FPort), xCli.OnConnect_Result);
end;

procedure TXClientMapping.cmd_disconnect_request(Sender: TPeerIO; InData: TDFE);
var
  local_id, Remote_id: Cardinal;
  phy_io: TXClientCustomProtocol;
begin
  Remote_id := InData.Reader.ReadCardinal;
  local_id := InData.Reader.ReadCardinal;

  phy_io := TXClientCustomProtocol(FProtocol_Hash[local_id]);
  if phy_io <> nil then
      phy_io.Disconnect;
end;

procedure TXClientMapping.cmd_data(Sender: TPeerIO; InData: PByte; DataSize: NativeInt);
var
  local_id, Remote_id: Cardinal;
  destSiz: NativeInt;
  destBuff: PByte;
  phy_io: TXClientCustomProtocol;
begin
  Extract_XNAT_Buff(InData, DataSize, Remote_id, local_id, destSiz, destBuff);

  phy_io := TXClientCustomProtocol(FProtocol_Hash[local_id]);
  if phy_io <> nil then
    begin
      phy_io.BeginWriteBuffer;
      phy_io.WriteBuffer(destBuff, destSiz);
      phy_io.EndWriteBuffer;
    end;
end;

constructor TXClientMapping.Create(Owner_: TXNATClient);
begin
  inherited Create;
  FOwner := Owner_;
  Init;
end;

destructor TXClientMapping.Destroy;
var
  j: integer;
begin
  if FProtocol_Pool <> nil then
    begin
      for j := 0 to FProtocol_Pool.Count - 1 do
        begin
          FProtocol_Pool[j].Disconnect;
          disposeObject(FProtocol_Pool[j]);
        end;
      disposeObject(FProtocol_Pool);
    end;

  if FProtocol_Hash <> nil then
      disposeObject(FProtocol_Hash);

  if FSendTunnel <> nil then
    begin
      FSendTunnel.Disconnect;
      disposeObject(FSendTunnel);
    end;

  if FRecvTunnel <> nil then
    begin
      FRecvTunnel.Disconnect;
      disposeObject(FRecvTunnel);
    end;

  inherited Destroy;
end;

procedure TXClientMapping.UpdateWorkload(force: Boolean);
var
  de: TDFE;
begin
  if FSendTunnel = nil then
      exit;
  if FRecvTunnel = nil then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if (not force) then
    if (FProtocol_Hash.Count = FLastUpdateWorkload) or (GetTimeTick() - FLastUpdateTime < 1000) then
        exit;

  de := TDFE.Create;
  de.WriteCardinal(FMaxWorkload);
  de.WriteCardinal(FProtocol_Hash.Count);
  FSendTunnel.SendStreamNotifyCmd(C_Workload, de);
  disposeObject(de);

  FLastUpdateWorkload := FProtocol_Hash.Count;
  FLastUpdateTime := GetTimeTick();
end;

procedure TXClientCustomProtocol.DoConnected(Sender: TPeerIO);
begin
  inherited DoConnected(Sender);
end;

procedure TXClientCustomProtocol.DoDisconnect(Sender: TPeerIO);
var
  de: TDFE;
begin
  if Activted then
    begin
      de := TDFE.Create;
      de.WriteCardinal(LocalProtocol_ID);
      de.WriteCardinal(RemoteProtocol_ID);
      FMapping.FSendTunnel.SendStreamNotifyCmd(C_Disconnect_reponse, de);
      disposeObject(de);
    end;
  inherited DoDisconnect(Sender);
end;

procedure TXClientCustomProtocol.OnReceiveBuffer(const buffer: PByte; const Size: NativeInt; var FillDone: Boolean);
var
  nSiz: NativeInt;
  nBuff: PByte;
begin
  if Activted then
    begin
      Build_XNAT_Buff(buffer, Size, LocalProtocol_ID, RemoteProtocol_ID, nSiz, nBuff);
      FMapping.FSendTunnel.SendCompleteBuffer(C_Data, nBuff, nSiz, True);
      inc(FMapping.Complete_Buffer_Sum, nSiz);
      if FMapping.Complete_Buffer_Sum > 10 * 1024 * 1024 then
        begin
          FMapping.FSendTunnel.Send_NULL;
          FMapping.Complete_Buffer_Sum := 0;
        end
      else if FMapping.FSendTunnel.ClientIO <> nil then
          FMapping.FSendTunnel.Progress_IO_Now_Send(FMapping.FSendTunnel.ClientIO);
    end
  else
    begin
      RequestBuffer.WritePtr(buffer, Size);
    end;
end;

procedure TXClientCustomProtocol.OnConnect_Result(const cState: Boolean);
var
  de: TDFE;
  nSiz: NativeInt;
  nBuff: PByte;
begin
  de := TDFE.Create;
  de.WriteBool(cState);
  de.WriteCardinal(LocalProtocol_ID);
  de.WriteCardinal(RemoteProtocol_ID);
  FMapping.FSendTunnel.SendStreamNotifyCmd(C_Connect_reponse, de);
  disposeObject(de);

  if cState then
    begin
      Activted := True;
      if RequestBuffer.Size > 0 then
        begin
          Build_XNAT_Buff(RequestBuffer.Memory, RequestBuffer.Size, LocalProtocol_ID, RemoteProtocol_ID, nSiz, nBuff);
          FMapping.FSendTunnel.SendCompleteBuffer(C_Data, nBuff, nSiz, True);
          RequestBuffer.Clear;
        end;
    end
  else
    begin
      de := TDFE.Create;
      de.WriteCardinal(LocalProtocol_ID);
      de.WriteCardinal(RemoteProtocol_ID);
      FMapping.FSendTunnel.SendStreamNotifyCmd(C_Disconnect_reponse, de);
      disposeObject(de);

      disposeObject(Self);
    end;
end;

constructor TXClientCustomProtocol.Create;
begin
  inherited Create;
  LocalProtocol_ID := 0;
  RemoteProtocol_ID := 0;
  Remote_IP := '';
  FMapping := nil;
  Activted := False;
  RequestBuffer := TMS64.Create;
end;

destructor TXClientCustomProtocol.Destroy;
var
  i: integer;
begin
  FMapping.FProtocol_Hash.Delete(LocalProtocol_ID);
  i := 0;
  while i < FMapping.FProtocol_Pool.Count do
    begin
      if FMapping.FProtocol_Pool[i] = Self then
          FMapping.FProtocol_Pool.Delete(i)
      else
          inc(i);
    end;
  disposeObject(RequestBuffer);
  inherited Destroy;
end;

procedure TPhysicsEngine_Special.PhysicsConnect_Result_BuildP2PToken(const cState: Boolean);
begin
  if cState then
      FOwner.BuildP2PAuthTokenM(PhysicsVMBuildAuthToken_Result)
  else
    begin
      FXNAT_VS.WaitAsyncConnecting := False;
      FXNAT_VS.Do_Open_Done(False);
    end;
end;

procedure TPhysicsEngine_Special.PhysicsVMBuildAuthToken_Result;
begin
  {
    QuantumCryptographyPassword: used sha-3 shake256 cryptography as 512 bits password

    SHA-3 (Secure Hash Algorithm 3) is the latest member of the Secure Hash Algorithm family of standards,
    released by NIST on August 5, 2015.[4][5] Although part of the same series of standards,
    SHA-3 is internally quite different from the MD5-like structure of SHA-1 and SHA-2.

    Keccak is based on a novel approach called sponge construction.
    Sponge construction is based on a wide random function or random permutation, and allows inputting ("absorbing" in sponge terminology) any amount of data,
    and outputting ("squeezing") any amount of data,
    while acting as a pseudorandom function with regard to all previous inputs. This leads to great flexibility.

    NIST does not currently plan to withdraw SHA-2 or remove it from the revised Secure Hash Standard.
    The purpose of SHA-3 is that it can be directly substituted for SHA-2 in current applications if necessary,
    and to significantly improve the robustness of NIST's overall hash algorithm toolkit

    ref wiki
    https://en.wikipedia.org/wiki/SHA-3
  }
  FOwner.OpenP2pVMTunnelM(True, GenerateQuantumCryptographyPassword(FXNAT_VS.AuthToken), PhysicsOpenVM_Result)
end;

procedure TPhysicsEngine_Special.PhysicsOpenVM_Result(const cState: Boolean);
begin
  if cState then
    begin
      FOwner.p2pVMTunnel.MaxVMFragmentSize := umlStrToInt(FXNAT_VS.MaxVMFragment, FOwner.p2pVMTunnel.MaxVMFragmentSize);
      FOwner.SendStreamCmdM(C_IPV6Listen, nil, IPV6Listen_Result);
    end
  else
    begin
      FXNAT_VS.WaitAsyncConnecting := False;
      FXNAT_VS.Do_Open_Done(False);
    end;
end;

procedure TPhysicsEngine_Special.IPV6Listen_Result(Sender: TPeerIO; Result_: TDFE);
var
  FMapping: TPascalString;
  FRemote_ListenAddr, FRemote_ListenPort: TPascalString;
  FRecvTunnel_IPV6: TPascalString;
  FRecvTunnel_Port: Word;
  FSendTunnel_IPV6: TPascalString;
  FSendTunnel_Port: Word;
  tunMp: TXClientMapping;
begin
  while Result_.Reader.NotEnd do
    begin
      FMapping := Result_.Reader.ReadString;
      FRemote_ListenAddr := Result_.Reader.ReadString;
      FRemote_ListenPort := Result_.Reader.ReadString;
      FSendTunnel_IPV6 := Result_.Reader.ReadString;
      FSendTunnel_Port := Result_.Reader.ReadWord;
      FRecvTunnel_IPV6 := Result_.Reader.ReadString;
      FRecvTunnel_Port := Result_.Reader.ReadWord;
      tunMp := FXNAT_VS.FHashMapping[FMapping];
      if tunMp <> nil then
        begin
          tunMp.FRecvTunnel_IPV6 := FRecvTunnel_IPV6;
          tunMp.FRecvTunnel_Port := FRecvTunnel_Port;
          tunMp.FSendTunnel_IPV6 := FSendTunnel_IPV6;
          tunMp.FSendTunnel_Port := FSendTunnel_Port;
          tunMp.FRemote_ListenAddr := FRemote_ListenAddr;
          tunMp.FRemote_ListenPort := FRemote_ListenPort;
          tunMp.Open;
        end;
    end;
  FXNAT_VS.Activted := True;
  FXNAT_VS.WaitAsyncConnecting := False;
  FXNAT_VS.Do_Open_Done(True);
end;

constructor TPhysicsEngine_Special.Create(Owner_: TPeerIO);
begin
  inherited Create(Owner_);
  FXNAT_VS := nil;
end;

destructor TPhysicsEngine_Special.Destroy;
begin
  inherited Destroy;
end;

procedure TXNATClient.PeerIO_Create(const Sender: TPeerIO);
begin
  TPhysicsEngine_Special(Sender.UserSpecial).FXNAT_VS := Self;
end;

procedure TXNATClient.PeerIO_Destroy(const Sender: TPeerIO);
begin
end;

procedure TXNATClient.p2pVMTunnelAuth(Sender: TPeerIO; const Token: SystemString; var Accept: Boolean);
begin
  {
    QuantumCryptographyPassword: used sha-3 shake256 cryptography as 512 bits password

    SHA-3 (Secure Hash Algorithm 3) is the latest member of the Secure Hash Algorithm family of standards,
    released by NIST on August 5, 2015.[4][5] Although part of the same series of standards,
    SHA-3 is internally quite different from the MD5-like structure of SHA-1 and SHA-2.

    Keccak is based on a novel approach called sponge construction.
    Sponge construction is based on a wide random function or random permutation, and allows inputting ("absorbing" in sponge terminology) any amount of data,
    and outputting ("squeezing") any amount of data,
    while acting as a pseudorandom function with regard to all previous inputs. This leads to great flexibility.

    NIST does not currently plan to withdraw SHA-2 or remove it from the revised Secure Hash Standard.
    The purpose of SHA-3 is that it can be directly substituted for SHA-2 in current applications if necessary,
    and to significantly improve the robustness of NIST's overall hash algorithm toolkit

    ref wiki
    https://en.wikipedia.org/wiki/SHA-3
  }

  if FPhysicsEngine is TZNet_Server then
    begin
    end
  else if FPhysicsEngine is TZNet_Client then
    begin
    end;

  Accept := CompareQuantumCryptographyPassword(AuthToken, Token);
  if Accept then
      Sender.Print('p2pVM auth Successed!')
  else
      Sender.Print('p2pVM auth failed!');
end;

procedure TXNATClient.p2pVMTunnelOpenBefore(Sender: TPeerIO; p2pVMTunnel: TZNet_P2PVM);
begin
  if FPhysicsEngine is TZNet_Server then
    begin
    end
  else if FPhysicsEngine is TZNet_Client then
    begin
    end;
  Sender.Print('XTunnel Open Before on %s', [Sender.PeerIP]);
end;

procedure TXNATClient.p2pVMTunnelOpen(Sender: TPeerIO; p2pVMTunnel: TZNet_P2PVM);
begin
  if FPhysicsEngine is TZNet_Server then
    begin
    end
  else if FPhysicsEngine is TZNet_Client then
    begin
    end;
  Sender.Print('XTunnel Open on %s', [Sender.PeerIP]);
end;

procedure TXNATClient.p2pVMTunnelOpenAfter(Sender: TPeerIO; p2pVMTunnel: TZNet_P2PVM);
begin
  if FPhysicsEngine is TZNet_Server then
    begin
      Sender.SendStreamCmdM(C_IPV6Listen, nil, TPhysicsEngine_Special(Sender.UserSpecial).IPV6Listen_Result);
    end
  else if FPhysicsEngine is TZNet_Client then
    begin
    end;
  Sender.Print('XTunnel Open After on %s', [Sender.PeerIP]);
end;

procedure TXNATClient.p2pVMTunnelClose(Sender: TPeerIO; p2pVMTunnel: TZNet_P2PVM);
begin
  if FPhysicsEngine is TZNet_Server then
    begin
    end
  else if FPhysicsEngine is TZNet_Client then
    begin
    end;
  Sender.Print('XTunnel Close on %s', [Sender.PeerIP]);
end;

procedure TXNATClient.PhysicsConnect_Result_BuildP2PToken(const cState: Boolean);
begin
  if cState then
    begin
      TPhysicsEngine_Special(TZNet_Client(FPhysicsEngine).ClientIO.UserSpecial).PhysicsConnect_Result_BuildP2PToken(cState);
    end
  else
    begin
      WaitAsyncConnecting := False;
      Do_Open_Done(False);
    end;
end;

procedure TXNATClient.Do_Open_Done(State: Boolean);
begin
  if Assigned(On_Open_Tunnel_Done) then
    begin
      try
          On_Open_Tunnel_Done(Self, State);
      except
      end;
      On_Open_Tunnel_Done := nil;
    end;
end;

procedure TXNATClient.Set_Quiet(const Value: Boolean);
var
  i, j: integer;
  tunMp: TXClientMapping;
  xCliProt: TXClientCustomProtocol;
begin
  FQuiet := Value;

  if FPhysicsEngine <> nil then
      Set_Instance_QuietMode(FPhysicsEngine, FQuiet);

  i := 0;
  while i < FMappingList.Count do
    begin
      tunMp := FMappingList[i] as TXClientMapping;
      if tunMp.FRecvTunnel <> nil then
          Set_Instance_QuietMode(tunMp.FRecvTunnel, FQuiet);

      if tunMp.FSendTunnel <> nil then
          Set_Instance_QuietMode(tunMp.FSendTunnel, FQuiet);

      if tunMp.FProtocol_Pool <> nil then
        begin
          j := 0;
          while j < tunMp.FProtocol_Pool.Count do
            begin
              xCliProt := tunMp.FProtocol_Pool[j];
              Set_Instance_QuietMode(xCliProt, FQuiet);
              inc(j);
            end;
        end;
      inc(i);
    end;
end;

constructor TXNATClient.Create;
begin
  inherited Create;
  Host := '';
  Port := '4921';
  AuthToken := '';
  MaxVMFragment := '8192';
  ProtocolCompressed := False;
  FMappingList := TXClientMappingList.Create;
  FHashMapping := TXClientHashMapping.Create(False, $FF, nil);
  Activted := False;
  WaitAsyncConnecting := False;
  FPhysicsEngine := nil;
  FQuiet := False;
  Instance_Class := TXClientMapping;
  On_Open_Tunnel_Done := nil;
end;

destructor TXNATClient.Destroy;
var
  i: integer;
begin
  for i := FMappingList.Count - 1 downto 0 do
      disposeObject(FMappingList[i]);
  disposeObject(FMappingList);
  disposeObject(FHashMapping);

  if FPhysicsEngine <> nil then
    begin
      if FPhysicsEngine is TZNet_Client then
        begin
          TZNet_Client(FPhysicsEngine).Disconnect;
        end;
    end;

  disposeObject(FPhysicsEngine);
  inherited Destroy;
end;

procedure TXNATClient.AddMapping(const MAddr, MPort, FMapping: TPascalString; FMaxWorkload: Cardinal);
var
  tunMp: TXClientMapping;
begin
  tunMp := Instance_Class.Create(Self);
  tunMp.FAddr := MAddr;
  tunMp.FPort := MPort;
  tunMp.FMapping := FMapping;
  tunMp.FMaxWorkload := FMaxWorkload;
  tunMp.FXNat_Client_Tunnel := Self;

  if tunMp.FRecvTunnel <> nil then
      Set_Instance_QuietMode(tunMp.FRecvTunnel, FQuiet);
  if tunMp.FSendTunnel <> nil then
      Set_Instance_QuietMode(tunMp.FSendTunnel, FQuiet);

  FMappingList.Add(tunMp);
  FHashMapping.Add(tunMp.FMapping, tunMp);
end;

procedure TXNATClient.OpenTunnel(MODEL: TXNAT_PHYSICS_MODEL);
begin
  Activted := True;

  { init tunnel engine }
  if FPhysicsEngine = nil then
    begin
      if MODEL = TXNAT_PHYSICS_MODEL.XNAT_PHYSICS_SERVICE then
          FPhysicsEngine := TXPhysicsServer.Create
      else
          FPhysicsEngine := TXPhysicsClient.Create;
    end;

  FPhysicsEngine.UserSpecialClass := TPhysicsEngine_Special;
  FPhysicsEngine.IOInterface := Self;
  FPhysicsEngine.VMInterface := Self;

  Set_Instance_QuietMode(FPhysicsEngine, FQuiet);

  { Security protocol }
  FPhysicsEngine.SwitchMaxPerformance;

  if FPhysicsEngine is TZNet_Server then
    begin
      if TZNet_Server(FPhysicsEngine).StartService(Host, umlStrToInt(Port)) then
        begin
          Do_Open_Done(True);
          FPhysicsEngine.Print('Tunnel Open %s:%s successed', [TranslateBindAddr(Host), Port.Text]);
        end
      else
        begin
          Do_Open_Done(False);
          FPhysicsEngine.Print('error: Tunnel is Closed for %s:%s', [TranslateBindAddr(Host), Port.Text]);
        end;
    end
  else if FPhysicsEngine is TZNet_Client then
    begin
      if not TZNet_Client(FPhysicsEngine).Connected then
        begin
          WaitAsyncConnecting := True;
          WaitAsyncConnecting_BeginTime := GetTimeTick;
          TZNet_Client(FPhysicsEngine).AsyncConnectM(Host, umlStrToInt(Port), PhysicsConnect_Result_BuildP2PToken);
        end;
    end;
end;

procedure TXNATClient.OpenTunnel;
begin
  OpenTunnel(TXNAT_PHYSICS_MODEL.XNAT_PHYSICS_CLIENT);
end;

procedure TXNATClient.Progress;
var
  i, j: integer;
  tunMp: TXClientMapping;
  xCliProt: TXClientCustomProtocol;
begin
  if (FPhysicsEngine <> nil) then
    begin
      if (FPhysicsEngine is TZNet_Client) then
        begin
          if WaitAsyncConnecting and (GetTimeTick - WaitAsyncConnecting_BeginTime > 15000) then
              WaitAsyncConnecting := False;

          if Activted and (not TZNet_Client(FPhysicsEngine).Connected) then
            begin
              if not WaitAsyncConnecting then
                begin
                  OpenTunnel(TXNAT_PHYSICS_MODEL.XNAT_PHYSICS_CLIENT);
                end;
            end;
        end;
      FPhysicsEngine.Progress;
    end;

  i := 0;
  while i < FMappingList.Count do
    begin
      tunMp := FMappingList[i] as TXClientMapping;

      tunMp.UpdateWorkload(False);

      if tunMp.FRecvTunnel <> nil then
          tunMp.FRecvTunnel.Progress;

      if tunMp.FSendTunnel <> nil then
          tunMp.FSendTunnel.Progress;

      if tunMp.FProtocol_Pool <> nil then
        begin
          j := 0;
          while j < tunMp.FProtocol_Pool.Count do
            begin
              xCliProt := tunMp.FProtocol_Pool[j];
              try
                if xCliProt.Activted and (not xCliProt.Connected) then
                  begin
                    disposeObject(xCliProt);
                    break;
                  end
                else
                  begin
                    xCliProt.Progress;
                    inc(j);
                  end;
              except
                  break;
              end;
            end;
        end;
      inc(i);
    end;
end;

end.
 
