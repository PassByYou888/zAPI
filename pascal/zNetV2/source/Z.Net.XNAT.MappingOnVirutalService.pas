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
  * XNAT Virtual Service – Server‑Side Mapping Abstraction
  * This unit provides a higher‑level server‑side API where each mapping is
  * represented as an independent virtual server (TXNAT_MappingOnVirutalService)
  * that behaves like a standard TZNet_Server. It is particularly useful when
  * building applications that need to manage multiple distinct services without
  * manual tunnel handling.
  *
  * Core classes:
  *   – TXNAT_VS_Mapping: Manager that owns all virtual services and the
  *     underlying physics connection to the XNAT client.
  *   – TXNAT_MappingOnVirutalService: A virtual server instance that listens
  *     for logical connections and forwards them through its own send/receive
  *     P2PVM tunnels.
  *   – TXNAT_MappingOnVirutalService_IO: Represents an incoming connection
  *     on a virtual service.
  *
  * Workflow:
  *   1. Create a TXNAT_VS_Mapping instance and configure its Host/Port/AuthToken.
  *   2. Call AddMappingService for each virtual service you wish to expose.
  *   3. Call OpenTunnel to establish the physics connection to the XNAT client.
  *   4. After the connection is established, the service receives tunnel
  *      addresses via C_IPV6Listen and each virtual service automatically opens
  *      its own P2PVM tunnels.
  *   5. When a client connects to a virtual service (via its standard server
  *      interface), a new TXNAT_MappingOnVirutalService_IO is created and
  *      connected to the remote XNAT client.
  *   6. Data flows transparently between the virtual service and the remote
  *      client using the same protocol as the core XNAT implementation.
  ****************************************************************************** }
unit Z.Net.XNAT.MappingOnVirutalService;

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
  TXNAT_VS_Mapping = class; { Forward declaration of the virtual service mapping manager. }
  TXNAT_MappingOnVirutalService = class; { Forward declaration of a virtual service that acts as a server. }

  { Special TPeerIO subclass used by TXNAT_MappingOnVirutalService to represent an incoming client connection. }
  TXNAT_MappingOnVirutalService_IO = class(TPeerIO)
  protected
    FRemote_ID: Cardinal; { Remote protocol ID assigned by the XNAT client. Set by cmd_connect_request. }
    FRemote_IP: SystemString; { IP address of the remote client. Set by cmd_connect_request. }
    FSendingStream: TMS64; { Internal buffer for outgoing data before it is forwarded to the XNAT client. Created in CreateAfter. }
  public
    procedure CreateAfter; override; { Initialises FSendingStream. Called by the framework. }
    destructor Destroy; override;

    function OwnerVS: TXNAT_MappingOnVirutalService; { Returns the owning virtual service instance. }

    function Connected: Boolean; override; { Always returns True because the IO is logical. }
    procedure Disconnect; override; { Sends a disconnect request to the XNAT client and delays destruction. }
    procedure Write_IO_Buffer(const buff: PByte; const Size: nativeInt); override; { Buffers outgoing data. }
    procedure WriteBufferOpen; override; { Clears the send buffer. }
    procedure WriteBufferFlush; override; { Flushes the buffer by building an XNAT packet and sending it via CompleteBuffer. }
    procedure WriteBufferClose; override; { Calls WriteBufferFlush. }
    function GetPeerIP: SystemString; override; { Returns the remote client IP. }
    function WriteBuffer_is_NULL: Boolean; override; { Always returns True (not used). }
    procedure Progress; override; { Calls inherited and processes send buffer. }
  end;

  { A virtual service that is mapped to a remote XNAT service. It acts as a server that accepts
    incoming logical connections and forwards traffic through P2PVM tunnels to the XNAT client. }
  TXNAT_MappingOnVirutalService = class(TZNet_Server)
  private
    FOwner: TXNAT_VS_Mapping; { Parent manager. Set in constructor. }
    FMapping: TPascalString; { Unique name of this mapping. Set by AddMappingService/AddMappingServer. }

    FRecvTunnel: TZNet_WithP2PVM_Client; { P2PVM client for receive tunnel (service -> client). Created in Open. }
    FRecvTunnel_IPV6: TPascalString; { IPv6 address of the receive tunnel (obtained from IPV6Listen_Result). Set by IPV6Listen_Result. }
    FRecvTunnel_Port: Word; { Port of the receive tunnel. Set by IPV6Listen_Result. }

    FSendTunnel: TZNet_WithP2PVM_Client; { P2PVM client for send tunnel (client -> service). Created in Open. }
    FSendTunnel_IPV6: TPascalString; { IPv6 address of the send tunnel. Set by IPV6Listen_Result. }
    FSendTunnel_Port: Word; { Port of the send tunnel. Set by IPV6Listen_Result. }

    FMaxWorkload: Cardinal; { Maximum workload capacity reported to the XNAT service. Set by AddMappingService/AddMappingServer. }
    FLastUpdateWorkload: Cardinal; { Last reported workload (number of active connections). Updated by UpdateWorkload. }
    FLastUpdateTime: TTimeTick; { Timestamp of the last workload update. Set by UpdateWorkload. }
    FRemote_ListenAddr, FRemote_ListenPort: TPascalString; { Remote listen address and port assigned by the XNAT service. Set by IPV6Listen_Result. }
    FXNAT_VS: TXNAT_VS_Mapping; { Back-reference to the parent manager. Set by AddMappingService/AddMappingServer. }

    procedure Init; { Initialises all fields to default values. Called by constructor. }
    procedure SendTunnel_ConnectResult(const cState: Boolean); { Callback when send tunnel connects. Invokes receive tunnel connection. }
    procedure RecvTunnel_ConnectResult(const cState: Boolean); { Callback when receive tunnel connects. Starts RequestListen. }

    procedure RequestListen_Result(Sender: TPeerIO; Result_: TDFE); { Callback for C_RequestListen response. Triggers On_VS_Ready. }
    procedure delay_RequestListen(Sender: TN_Post_Execute); { Delayed execution of RequestListen after receive tunnel is up. }

    procedure Open; { Initialises P2PVM tunnels, registers command handlers, and connects to the remote tunnels. }

    { Command handlers for incoming requests from the XNAT client. }
    procedure cmd_connect_request(Sender: TPeerIO; InData: TDFE); { Handles a connection request. Creates a new TXNAT_MappingOnVirutalService_IO. }
    procedure cmd_disconnect_request(Sender: TPeerIO; InData: TDFE); { Handles a disconnect request. Destroys the corresponding IO. }
    procedure cmd_data(Sender: TPeerIO; InData: PByte; DataSize: nativeInt); { Forwards data to the corresponding IO. }

  public
    constructor Create(Owner_: TXNAT_VS_Mapping); virtual;
    destructor Destroy; override;

    property XNAT_VS: TXNAT_VS_Mapping read FXNAT_VS; { Returns the parent manager. }

    procedure UpdateWorkload(force: Boolean); virtual; { Sends a workload update to the XNAT service. }

    function StartService(Host: SystemString; Port: Word): Boolean; override; { Override – does nothing (virtual service). }
    procedure StopService; override; { Override – does nothing. }
    procedure Progress; override; { Override – calls parent and progresses tunnels. }
    function WaitSendConsoleCmd(p_io: TPeerIO; const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString; override; { Not supported, raises exception. }
    procedure WaitSendStreamCmd(p_io: TPeerIO; const Cmd: SystemString; StreamData, Result_: TDFE; TimeOut_: TTimeTick); override; { Not supported, raises exception. }
  end;

  { Meta-class for creating TXNAT_MappingOnVirutalService instances. }
  TXNAT_MappingOnVirutalService_Class = class of TXNAT_MappingOnVirutalService;

  { Special user data attached to the main physics tunnel connection. }
  TPhysicsEngine_Special = class(TPeer_IO_User_Special)
  protected
    FXNAT_VS: TXNAT_VS_Mapping; { Reference to the parent mapping manager. Set by PeerIO_Create. }
    procedure PhysicsConnect_Result_BuildP2PToken(const cState: Boolean); { Callback when physics connection is established. }
    procedure PhysicsVMBuildAuthToken_Result; { Callback after P2PVM authentication token is built. }
    procedure PhysicsOpenVM_Result(const cState: Boolean); { Callback after P2PVM tunnel is opened. }
    procedure IPV6Listen_Result(Sender: TPeerIO; Result_: TDFE); { Callback for C_IPV6Listen response. Parses tunnel addresses for each mapping. }
  public
    constructor Create(Owner_: TPeerIO); override;
    destructor Destroy; override;
  end;

  { List of TXNAT_MappingOnVirutalService instances. }
  TXVirutalServiceMappingList = TGenericsList<TXNAT_MappingOnVirutalService>;
  { Hash map from mapping name to TXNAT_MappingOnVirutalService. }
  TXVirutalServiceHashMapping = TGeneric_String_Object_Hash<TXNAT_MappingOnVirutalService>;
  { List of TXNAT_VS_Mapping instances (not used in this unit, but declared for external use). }
  TXNAT_VS_Mapping_List_Decl = TGenericsList<TXNAT_VS_Mapping>;
  { Callback type for virtual service readiness notification. }
  TOn_VS_Ready = procedure(Sender: TXNAT_VS_Mapping; vs: TXNAT_MappingOnVirutalService; state: Boolean; info: SystemString) of object;

  { Main manager for virtual services. It connects to an XNAT service and creates multiple
    TXNAT_MappingOnVirutalService instances, each representing a mapping. }
  TXNAT_VS_Mapping = class(TCore_InterfacedObject_Intermediate, IIOInterface, IZNet_VMInterface)
  private
    MappingList: TXVirutalServiceMappingList; { List of all virtual services. Created in constructor. }
    HashMapping: TXVirutalServiceHashMapping; { Hash map for fast lookup by mapping name. Created in constructor. }
    Activted: Boolean; { Indicates whether the manager is active. Set in OpenTunnel. }
    WaitAsyncConnecting: Boolean; { True while an asynchronous connection attempt is in progress. Set in OpenTunnel (client mode). }
    WaitAsyncConnecting_BeginTime: TTimeTick; { Timestamp when the async connection attempt started. Set in OpenTunnel (client mode). }
    PhysicsEngine: TZNet; { Underlying physics engine (server or client). Created/assigned in OpenTunnel. }
    FQuiet: Boolean; { If True, suppresses diagnostic output. Set by Set_Quiet. }
    Progressing: Boolean; { Re-entrancy guard for Progress. Set to True during Progress execution. }

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

    { Sets the quiet mode and propagates it to all sub-components. }
    procedure Set_Quiet(const Value: Boolean);

    { Triggers the On_VS_Ready callback for the given virtual service. }
    procedure Do_VS_State(vs: TXNAT_MappingOnVirutalService; state: Boolean; info: SystemString);

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

    Instance_Class: TXNAT_MappingOnVirutalService_Class; { Class reference for creating virtual services. Default is TXNAT_MappingOnVirutalService. }
    On_VS_Ready: TOn_VS_Ready; { Called when a virtual service successfully (or not) establishes its tunnel. }

    property Quiet: Boolean read FQuiet write Set_Quiet; { Quiet mode – suppresses log output. }

    constructor Create;
    destructor Destroy; override;

    { Creates a new virtual service mapping (service mode). }
    function AddMappingService(const FMapping: TPascalString; FMaxWorkload: Cardinal): TXNAT_MappingOnVirutalService;
    { Alias for AddMappingService. }
    function AddMappingServer(const FMapping: TPascalString; FMaxWorkload: Cardinal): TXNAT_MappingOnVirutalService;

    { Opens the tunnel using the specified physics model (server or client). }
    procedure OpenTunnel(MODEL: TXNAT_PHYSICS_MODEL); overload;
    { Opens the tunnel as a client (default). }
    procedure OpenTunnel; overload;

    { Main progress method – must be called periodically to drive all engines. }
    procedure Progress;

    { Returns the number of virtual services. }
    function GetCount: Integer;
    property Count: Integer read GetCount;
    { Returns the virtual service at the given index. }
    function GetServices(const index: Integer): TXNAT_MappingOnVirutalService;
    property Services[const index: Integer]: TXNAT_MappingOnVirutalService read GetServices; default;
    { Returns the virtual service with the given mapping name. }
    function GetServicesOnMapping(const FMapping: SystemString): TXNAT_MappingOnVirutalService;
    property ServicesOnMapping[const FMapping: SystemString]: TXNAT_MappingOnVirutalService read GetServicesOnMapping;
  end;

implementation

procedure TXNAT_MappingOnVirutalService_IO.CreateAfter;
begin
  inherited CreateAfter;
  FSendingStream := TMS64.Create;
  FSendingStream.Delta := 2048;
  FRemote_ID := 0;
  FRemote_IP := '';
end;

destructor TXNAT_MappingOnVirutalService_IO.Destroy;
begin
  DisposeObject(FSendingStream);
  inherited Destroy;
end;

function TXNAT_MappingOnVirutalService_IO.OwnerVS: TXNAT_MappingOnVirutalService;
begin
  Result := OwnerFramework as TXNAT_MappingOnVirutalService;
end;

function TXNAT_MappingOnVirutalService_IO.Connected: Boolean;
begin
  Result := True;
end;

procedure TXNAT_MappingOnVirutalService_IO.Disconnect;
var
  de: TDFE;
begin
  de := TDFE.Create;
  de.WriteCardinal(ID);
  de.WriteCardinal(FRemote_ID);
  OwnerVS.FSendTunnel.SendStreamNotifyCmd(C_Disconnect_reponse, de);
  DisposeObject(de);
  DelayFree(5.0);
end;

procedure TXNAT_MappingOnVirutalService_IO.Write_IO_Buffer(const buff: PByte; const Size: nativeInt);
begin
  FSendingStream.WritePtr(buff, Size);
end;

procedure TXNAT_MappingOnVirutalService_IO.WriteBufferOpen;
begin
  FSendingStream.Clear;
end;

procedure TXNAT_MappingOnVirutalService_IO.WriteBufferFlush;
var
  nSiz: nativeInt;
  nBuff: PByte;
begin
  if FSendingStream.Size > 0 then
    begin
      Build_XNAT_Buff(FSendingStream.Memory, FSendingStream.Size, ID, FRemote_ID, nSiz, nBuff);
      OwnerVS.FSendTunnel.SendCompleteBuffer(C_Data, nBuff, nSiz, True);
      FSendingStream.Clear;
    end;
end;

procedure TXNAT_MappingOnVirutalService_IO.WriteBufferClose;
begin
  WriteBufferFlush;
end;

function TXNAT_MappingOnVirutalService_IO.GetPeerIP: SystemString;
begin
  Result := FRemote_IP;
end;

function TXNAT_MappingOnVirutalService_IO.WriteBuffer_is_NULL: Boolean;
begin
  Result := True;
end;

procedure TXNAT_MappingOnVirutalService_IO.Progress;
begin
  inherited Progress;
  Process_Send_Buffer();
end;

procedure TXNAT_MappingOnVirutalService.Init;
begin
  FMapping := '';
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
  FXNAT_VS := nil;
end;

procedure TXNAT_MappingOnVirutalService.SendTunnel_ConnectResult(const cState: Boolean);
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
    begin
      FSendTunnel.Print('error: [%s] Send Tunnel connect failed!', [FMapping.Text]);
      FOwner.Do_VS_State(self, cState, PFormat('error: [%s] Send Tunnel connect failed!', [FMapping.Text]));
    end;
end;

procedure TXNAT_MappingOnVirutalService.RecvTunnel_ConnectResult(const cState: Boolean);
begin
  if cState then
    begin
      FRecvTunnel.Print('[%s] Receive Tunnel connect success.', [FMapping.Text]);
      FSendTunnel.ProgressPost.PostExecuteM(0, delay_RequestListen);
    end
  else
    begin
      FRecvTunnel.Print('error: [%s] Receive Tunnel connect failed!', [FMapping.Text]);
      FOwner.Do_VS_State(self, cState, PFormat('error: [%s] Receive Tunnel connect failed!', [FMapping.Text]));
    end;
end;

procedure TXNAT_MappingOnVirutalService.RequestListen_Result(Sender: TPeerIO; Result_: TDFE);
begin
  if Result_.Reader.ReadBool then
    begin
      FSendTunnel.Print('success: remote host:%s port:%s mapping to local Service', [FXNAT_VS.Host.Text, FRemote_ListenPort.Text]);
      UpdateWorkload(True);
      FOwner.Do_VS_State(self, True, PFormat('success: remote host:%s port:%s mapping to local Service', [FXNAT_VS.Host.Text, FRemote_ListenPort.Text]));
    end
  else
    begin
      FSendTunnel.Print('failed: remote host:%s port:%s listen error!', [FXNAT_VS.Host.Text, FRemote_ListenPort.Text]);
      FOwner.Do_VS_State(self, False, PFormat('failed: remote host:%s port:%s listen error!', [FXNAT_VS.Host.Text, FRemote_ListenPort.Text]));
    end;
end;

procedure TXNAT_MappingOnVirutalService.delay_RequestListen(Sender: TN_Post_Execute);
var
  de: TDFE;
begin
  de := TDFE.Create;
  de.WriteCardinal(FSendTunnel.RemoteID);
  de.WriteCardinal(FRecvTunnel.RemoteID);
  FSendTunnel.SendStreamCmdM(C_RequestListen, de, RequestListen_Result);
  DisposeObject(de);
end;

procedure TXNAT_MappingOnVirutalService.Open;
var
  io_array: TIO_Array;
  p_id: Cardinal;
  p_io: TPeerIO;
begin
  if FRecvTunnel = nil then
    begin
      FRecvTunnel := TZNet_WithP2PVM_Client.Create;
      FRecvTunnel.QuietMode := FOwner.Quiet;
      { sequence sync }
      FRecvTunnel.SyncOnCompleteBuffer := True;
      FRecvTunnel.SyncOnResult := True;
      FRecvTunnel.SwitchMaxPerformance;
      { compressed complete buffer }
      FRecvTunnel.CompleteBufferCompressed := FXNAT_VS.ProtocolCompressed;
      { automated swap space }
      FRecvTunnel.CompleteBufferSwapSpace := True;
      { register cmd }
      if not FRecvTunnel.ExistsRegistedCmd(C_Connect_request) then
          FRecvTunnel.RegisterStreamNotify(C_Connect_request).OnExecute := cmd_connect_request;
      if not FRecvTunnel.ExistsRegistedCmd(C_Disconnect_request) then
          FRecvTunnel.RegisterStreamNotify(C_Disconnect_request).OnExecute := cmd_disconnect_request;
      if not FRecvTunnel.ExistsRegistedCmd(C_Data) then
          FRecvTunnel.RegisterCompleteBuffer(C_Data).OnExecute := cmd_data;
      { disable status }
      FRecvTunnel.PrintParams[C_Connect_request] := False;
      FRecvTunnel.PrintParams[C_Disconnect_request] := False;
      FRecvTunnel.PrintParams[C_Data] := False;
    end;
  if FSendTunnel = nil then
    begin
      FSendTunnel := TZNet_WithP2PVM_Client.Create;
      FSendTunnel.QuietMode := FOwner.Quiet;
      { sequence sync }
      FSendTunnel.SyncOnCompleteBuffer := True;
      FSendTunnel.SyncOnResult := True;
      FSendTunnel.SwitchMaxPerformance;
      { compressed complete buffer }
      FSendTunnel.CompleteBufferCompressed := FXNAT_VS.ProtocolCompressed;
      { automated swap space }
      FSendTunnel.CompleteBufferSwapSpace := True;
      { disable status }
      FSendTunnel.PrintParams[C_Connect_reponse] := False;
      FSendTunnel.PrintParams[C_Disconnect_reponse] := False;
      FSendTunnel.PrintParams[C_Data] := False;
      FSendTunnel.PrintParams[C_Workload] := False;
    end;

  FXNAT_VS.PhysicsEngine.GetIO_Array(io_array);
  for p_id in io_array do
    begin
      p_io := TPeerIO(FXNAT_VS.PhysicsEngine.PeerIO_HashPool[p_id]);
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

  if not FSendTunnel.Connected then
      FSendTunnel.AsyncConnectM(FSendTunnel_IPV6, FSendTunnel_Port, SendTunnel_ConnectResult)
  else
      SendTunnel_ConnectResult(True);
end;

procedure TXNAT_MappingOnVirutalService.cmd_connect_request(Sender: TPeerIO; InData: TDFE);
var
  Remote_ID: Cardinal;
  x_io: TXNAT_MappingOnVirutalService_IO;
  de: TDFE;
begin
  Remote_ID := InData.Reader.ReadCardinal;
  x_io := TXNAT_MappingOnVirutalService_IO.Create(self, FXNAT_VS);
  x_io.FRemote_ID := Remote_ID;
  x_io.FRemote_IP := InData.Reader.ReadString;

  de := TDFE.Create;
  de.WriteBool(True);
  de.WriteCardinal(x_io.ID);
  de.WriteCardinal(x_io.FRemote_ID);
  FSendTunnel.SendStreamNotifyCmd(C_Connect_reponse, de);
  DisposeObject(de);
end;

procedure TXNAT_MappingOnVirutalService.cmd_disconnect_request(Sender: TPeerIO; InData: TDFE);
var
  local_id, Remote_ID: Cardinal;
  p_io: TPeerIO;
begin
  Remote_ID := InData.Reader.ReadCardinal;
  local_id := InData.Reader.ReadCardinal;
  p_io := PeerIO[local_id];
  if p_io <> nil then
      DisposeObject(p_io);
end;

procedure TXNAT_MappingOnVirutalService.cmd_data(Sender: TPeerIO; InData: PByte; DataSize: nativeInt);
var
  local_id, Remote_ID: Cardinal;
  destSiz: nativeInt;
  destBuff: PByte;
  x_io: TXNAT_MappingOnVirutalService_IO;
begin
  Extract_XNAT_Buff(InData, DataSize, Remote_ID, local_id, destSiz, destBuff);
  x_io := TXNAT_MappingOnVirutalService_IO(PeerIO[local_id]);
  if x_io <> nil then
    begin
      x_io.Write_Physics_Fragment(destBuff, destSiz);
    end;
end;

constructor TXNAT_MappingOnVirutalService.Create(Owner_: TXNAT_VS_Mapping);
begin
  inherited Create;
  FOwner := Owner_;
  Init;
end;

destructor TXNAT_MappingOnVirutalService.Destroy;
begin
  if FSendTunnel <> nil then
    begin
      FSendTunnel.Disconnect;
      DisposeObject(FSendTunnel);
    end;

  if FRecvTunnel <> nil then
    begin
      FRecvTunnel.Disconnect;
      DisposeObject(FRecvTunnel);
    end;

  inherited Destroy;
end;

procedure TXNAT_MappingOnVirutalService.UpdateWorkload(force: Boolean);
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
    if (Count = FLastUpdateWorkload) or (GetTimeTick() - FLastUpdateTime < 1000) then
        exit;

  de := TDFE.Create;
  de.WriteCardinal(FMaxWorkload);
  de.WriteCardinal(Count);
  FSendTunnel.SendStreamNotifyCmd(C_Workload, de);
  DisposeObject(de);

  FLastUpdateWorkload := Count;
  FLastUpdateTime := GetTimeTick();
end;

function TXNAT_MappingOnVirutalService.StartService(Host: SystemString; Port: Word): Boolean;
begin
  Result := True;
end;

procedure TXNAT_MappingOnVirutalService.StopService;
begin
end;

procedure TXNAT_MappingOnVirutalService.Progress;
begin
  if (FXNAT_VS <> nil) and (not FXNAT_VS.Progressing) then
    begin
      FXNAT_VS.Progress;
      exit;
    end;

  inherited Progress;

  if FSendTunnel <> nil then
      FSendTunnel.Progress;
  if FRecvTunnel <> nil then
      FRecvTunnel.Progress;
end;

function TXNAT_MappingOnVirutalService.WaitSendConsoleCmd(p_io: TPeerIO; const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString;
begin
  Result := '';
  RaiseInfo('WaitSend no Suppport');
end;

procedure TXNAT_MappingOnVirutalService.WaitSendStreamCmd(p_io: TPeerIO; const Cmd: SystemString; StreamData, Result_: TDFE; TimeOut_: TTimeTick);
begin
  RaiseInfo('WaitSend no Suppport');
end;

procedure TPhysicsEngine_Special.PhysicsConnect_Result_BuildP2PToken(const cState: Boolean);
begin
  if cState then
      FOwner.BuildP2PAuthTokenM(PhysicsVMBuildAuthToken_Result)
  else
      FXNAT_VS.WaitAsyncConnecting := False;
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
      FXNAT_VS.WaitAsyncConnecting := False;
end;

procedure TPhysicsEngine_Special.IPV6Listen_Result(Sender: TPeerIO; Result_: TDFE);
var
  FMapping: TPascalString;
  FRemote_ListenAddr, FRemote_ListenPort: TPascalString;
  FRecvTunnel_IPV6: TPascalString;
  FRecvTunnel_Port: Word;
  FSendTunnel_IPV6: TPascalString;
  FSendTunnel_Port: Word;
  tunMp: TXNAT_MappingOnVirutalService;
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
      tunMp := FXNAT_VS.HashMapping[FMapping];
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

procedure TXNAT_VS_Mapping.PeerIO_Create(const Sender: TPeerIO);
begin
  TPhysicsEngine_Special(Sender.UserSpecial).FXNAT_VS := self;
end;

procedure TXNAT_VS_Mapping.PeerIO_Destroy(const Sender: TPeerIO);
begin
end;

procedure TXNAT_VS_Mapping.p2pVMTunnelAuth(Sender: TPeerIO; const Token: SystemString; var Accept: Boolean);
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

  if PhysicsEngine is TZNet_Server then
    begin
    end
  else if PhysicsEngine is TZNet_Client then
    begin
    end;

  Accept := CompareQuantumCryptographyPassword(AuthToken, Token);
  if Accept then
      Sender.Print('p2pVM auth Successed!')
  else
      Sender.Print('p2pVM auth failed!');
end;

procedure TXNAT_VS_Mapping.p2pVMTunnelOpenBefore(Sender: TPeerIO; p2pVMTunnel: TZNet_P2PVM);
begin
  if PhysicsEngine is TZNet_Server then
    begin
    end
  else if PhysicsEngine is TZNet_Client then
    begin
    end;
  Sender.Print('XTunnel Open Before on %s', [Sender.PeerIP]);
end;

procedure TXNAT_VS_Mapping.p2pVMTunnelOpen(Sender: TPeerIO; p2pVMTunnel: TZNet_P2PVM);
begin
  if PhysicsEngine is TZNet_Server then
    begin
    end
  else if PhysicsEngine is TZNet_Client then
    begin
    end;
  Sender.Print('XTunnel Open on %s', [Sender.PeerIP]);
end;

procedure TXNAT_VS_Mapping.p2pVMTunnelOpenAfter(Sender: TPeerIO; p2pVMTunnel: TZNet_P2PVM);
begin
  if PhysicsEngine is TZNet_Server then
    begin
      Sender.SendStreamCmdM(C_IPV6Listen, nil, TPhysicsEngine_Special(Sender.UserSpecial).IPV6Listen_Result);
    end
  else if PhysicsEngine is TZNet_Client then
    begin
    end;
  Sender.Print('XTunnel Open After on %s', [Sender.PeerIP]);
end;

procedure TXNAT_VS_Mapping.p2pVMTunnelClose(Sender: TPeerIO; p2pVMTunnel: TZNet_P2PVM);
begin
  if PhysicsEngine is TZNet_Server then
    begin
    end
  else if PhysicsEngine is TZNet_Client then
    begin
    end;
  Sender.Print('XTunnel Close on %s', [Sender.PeerIP]);
end;

procedure TXNAT_VS_Mapping.PhysicsConnect_Result_BuildP2PToken(const cState: Boolean);
begin
  TPhysicsEngine_Special(TZNet_Client(PhysicsEngine).ClientIO.UserSpecial).PhysicsConnect_Result_BuildP2PToken(cState);
end;

procedure TXNAT_VS_Mapping.Set_Quiet(const Value: Boolean);
var
  i: Integer;
  tunMp: TXNAT_MappingOnVirutalService;
begin
  FQuiet := Value;
  i := 0;
  while i < MappingList.Count do
    begin
      tunMp := MappingList[i];
      if tunMp.FRecvTunnel <> nil then
          Set_Instance_QuietMode(tunMp.FRecvTunnel, FQuiet);

      if tunMp.FSendTunnel <> nil then
          Set_Instance_QuietMode(tunMp.FSendTunnel, FQuiet);
      inc(i);
    end;
end;

procedure TXNAT_VS_Mapping.Do_VS_State(vs: TXNAT_MappingOnVirutalService; state: Boolean; info: SystemString);
begin
  if Assigned(On_VS_Ready) then
    begin
      On_VS_Ready(self, vs, state, info);
      On_VS_Ready := nil;
    end;
end;

constructor TXNAT_VS_Mapping.Create;
begin
  inherited Create;
  Host := '';
  Port := '4921';
  AuthToken := '';
  MaxVMFragment := '8192';
  ProtocolCompressed := False;
  MappingList := TXVirutalServiceMappingList.Create;
  HashMapping := TXVirutalServiceHashMapping.Create(False, 64, nil);
  Activted := False;
  WaitAsyncConnecting := False;
  PhysicsEngine := nil;
  Instance_Class := TXNAT_MappingOnVirutalService;
  On_VS_Ready := nil;
  FQuiet := False;
  Progressing := False;
end;

destructor TXNAT_VS_Mapping.Destroy;
var
  i: Integer;
begin
  for i := MappingList.Count - 1 downto 0 do
      DisposeObject(MappingList[i]);
  DisposeObject(MappingList);
  DisposeObject(HashMapping);

  if PhysicsEngine <> nil then
    begin
      if PhysicsEngine is TZNet_Client then
        begin
          TZNet_Client(PhysicsEngine).Disconnect;
        end;
    end;

  DisposeObject(PhysicsEngine);
  inherited Destroy;
end;

function TXNAT_VS_Mapping.AddMappingService(const FMapping: TPascalString; FMaxWorkload: Cardinal): TXNAT_MappingOnVirutalService;
begin
  Result := Instance_Class.Create(self);
  Result.FMapping := FMapping;
  Result.FMaxWorkload := FMaxWorkload;
  Result.FXNAT_VS := self;
  MappingList.Add(Result);
  HashMapping.Add(Result.FMapping, Result);
end;

function TXNAT_VS_Mapping.AddMappingServer(const FMapping: TPascalString; FMaxWorkload: Cardinal): TXNAT_MappingOnVirutalService;
begin
  Result := AddMappingService(FMapping, FMaxWorkload);
end;

procedure TXNAT_VS_Mapping.OpenTunnel(MODEL: TXNAT_PHYSICS_MODEL);
begin
  Activted := True;

  { init tunnel engine }
  if PhysicsEngine = nil then
    begin
      if MODEL = TXNAT_PHYSICS_MODEL.XNAT_PHYSICS_SERVICE then
          PhysicsEngine := TXPhysicsServer.Create
      else
          PhysicsEngine := TXPhysicsClient.Create;
      PhysicsEngine.QuietMode := Quiet;
    end;

  PhysicsEngine.UserSpecialClass := TPhysicsEngine_Special;
  PhysicsEngine.IOInterface := self;
  PhysicsEngine.VMInterface := self;

  { Security protocol }
  PhysicsEngine.SwitchMaxSecurity;

  if PhysicsEngine is TZNet_Server then
    begin
      if TZNet_Server(PhysicsEngine).StartService(Host, umlStrToInt(Port)) then
          PhysicsEngine.Print('Tunnel Open %s:%s successed', [TranslateBindAddr(Host), Port.Text])
      else
          PhysicsEngine.Print('error: Tunnel is Closed for %s:%s', [TranslateBindAddr(Host), Port.Text]);
    end
  else if PhysicsEngine is TZNet_Client then
    begin
      if not TZNet_Client(PhysicsEngine).Connected then
        begin
          WaitAsyncConnecting := True;
          WaitAsyncConnecting_BeginTime := GetTimeTick;
          TZNet_Client(PhysicsEngine).AsyncConnectM(Host, umlStrToInt(Port), PhysicsConnect_Result_BuildP2PToken);
        end;
    end;
end;

procedure TXNAT_VS_Mapping.OpenTunnel;
begin
  OpenTunnel(TXNAT_PHYSICS_MODEL.XNAT_PHYSICS_CLIENT);
end;

procedure TXNAT_VS_Mapping.Progress;
var
  i: Integer;
  tunMp: TXNAT_MappingOnVirutalService;
begin
  if Progressing then
      exit;

  Progressing := True;

  if (PhysicsEngine <> nil) then
    begin
      if (PhysicsEngine is TZNet_Client) then
        begin
          if WaitAsyncConnecting and (GetTimeTick - WaitAsyncConnecting_BeginTime > 15000) then
              WaitAsyncConnecting := False;

          if Activted and (not TZNet_Client(PhysicsEngine).Connected) then
            begin
              if not WaitAsyncConnecting then
                begin
                  OpenTunnel(TXNAT_PHYSICS_MODEL.XNAT_PHYSICS_CLIENT);
                end;
            end;
        end;
      PhysicsEngine.Progress;
    end;

  i := 0;
  while i < MappingList.Count do
    begin
      tunMp := MappingList[i];
      tunMp.UpdateWorkload(False);
      tunMp.Progress;
      inc(i);
    end;

  Progressing := False;
end;

function TXNAT_VS_Mapping.GetCount: Integer;
begin
  Result := MappingList.Count;
end;

function TXNAT_VS_Mapping.GetServices(const index: Integer): TXNAT_MappingOnVirutalService;
begin
  Result := MappingList[index];
end;

function TXNAT_VS_Mapping.GetServicesOnMapping(const FMapping: SystemString): TXNAT_MappingOnVirutalService;
begin
  Result := HashMapping[FMapping];
end;

end.
 
