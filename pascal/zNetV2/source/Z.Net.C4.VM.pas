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
{ ****************************************************************************** }
{ * cloud 4.0 framework-VM                                                     * }
{ * This unit provides Virtual Machine (VM) style service and client           * }
{ * implementations for the C4 framework. It wraps P2PVM double-tunnel         * }
{ * services and clients with different authentication models (NoAuth,         * }
{ * VirtualAuth, and built-in Auth) into easy-to-use VM classes that can       * }
{ * be started/stopped as standalone components.                               * }
{ ****************************************************************************** }
unit Z.Net.C4.VM;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses
{$IFDEF FPC}
  Z.FPC.GenericList,
{$ELSE FPC}
  System.IOUtils,
{$ENDIF FPC}
  Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.Status, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Geometry2D, Z.DFE, Z.Json,
  Z.Notify, Z.Cipher, Z.MemoryStream,
  Z.Expression, Z.OpCode,
  Z.Net, Z.Net.PhysicsIO,
  Z.Net.DoubleTunnelIO,
  Z.Net.DataStoreService,
  Z.Net.DoubleTunnelIO.VirtualAuth,
  Z.Net.DataStoreService.VirtualAuth,
  Z.Net.DoubleTunnelIO.NoAuth,
  Z.Net.DataStoreService.NoAuth,
  Z.Net.C4, Z.Net.Client.IPC, Z.Net.Server.IPC;

type
  { ============================================================================ }
  { NoAuth VM Service – provides a P2PVM double-tunnel service without }
  { authentication. It inherits from TC40_Custom_VM_Service and wraps the }
  { no‑auth double‑tunnel service (TDTService_NoAuth). }
  { ============================================================================ }
  TC40_NoAuth_VM_Service = class(TC40_Custom_VM_Service)
  protected
    { Called when a client successfully links to this service. }
    { Sender        - The underlying no‑auth double‑tunnel service. }
    { UserDefineIO  - The user‑defined I/O object for the linked tunnel. }
    { This method is assigned as the OnLinkSuccess handler of the DTService. }
    procedure DoLinkSuccess_Event(Sender: TDTService_NoAuth; UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth); virtual;

    { Called when a user/client disconnects from this service. }
    { Sender        - The underlying no‑auth double‑tunnel service. }
    { UserDefineIO  - The user‑defined I/O object for the disconnected tunnel. }
    { This method is assigned as the OnUserOut handler of the DTService. }
    procedure DoUserOut_Event(Sender: TDTService_NoAuth; UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth); virtual;
  public
    { Underlying P2PVM service that manages the two tunnels (Recv/Send). }
    { Created in the constructor. }
    Service: TDT_P2PVM_NoAuth_Service;

    { The no‑auth double‑tunnel service exposed by Service.DTService. }
    { Set in the constructor from Service.DTService. }
    DTNoAuthService: TDTService_NoAuth;

    { Property to access the no‑auth double‑tunnel service. }
    property DTNoAuth: TDTService_NoAuth read DTNoAuthService;

    { Returns the class type of the underlying no‑auth service. }
    { Override this in descendants to use a different DTService class. }
    { Default is TDTService_NoAuth. }
    class function Get_Service_Class: TDTService_NoAuthClass; virtual;

    { Constructor that initializes the VM service with a parameter string. }
    { Param_ - Configuration parameters (parsed into ParamList). }
    constructor Create(Param_: U_String); override;

    { Destructor. Stops the service and frees the underlying Service object. }
    destructor Destroy; override;

    { Main progress method – calls inherited and then Service.Progress. }
    procedure Progress; override;

    { Starts the service on the given listening address, port, and auth token. }
    { ListenAddr - IP address to bind. }
    { ListenPort - Port to bind. }
    { Auth       - Authentication token (for no‑auth this is usually ignored). }
    procedure StartService(ListenAddr, ListenPort, Auth: SystemString); override;

    { Stops the service. }
    procedure StopService; override;
  end;

  { ============================================================================ }
  { NoAuth VM Client – connects to a NoAuth VM service. It inherits from }
  { TC40_Custom_VM_Client and implements the IZNet_ClientInterface for }
  { client lifecycle events. }
  { ============================================================================ }
  TC40_NoAuth_VM_Client = class(TC40_Custom_VM_Client, IZNet_ClientInterface)
  protected
    { Called when the underlying physics client connects. }
    { Sender - The physics client that connected. }
    { Currently does nothing but can be overridden. }
    procedure ClientConnected(Sender: TZNet_Client); virtual;

    { Called when the underlying physics client disconnects. }
    { Sender - The physics client that disconnected. }
    { Triggers DoNetworkOffline. }
    procedure ClientDisconnect(Sender: TZNet_Client); virtual;

    { Called when the P2PVM double‑tunnel link is established. }
    { Sender - The P2PVM client. }
    { Triggers DoNetworkOnline. }
    procedure Do_DT_P2PVM_NoAuth_Custom_Client_TunnelLink(Sender: TDT_P2PVM_NoAuth_Client); virtual;
  public
    { Underlying P2PVM client that manages the two tunnel connections. }
    { Created in the constructor. }
    Client: TDT_P2PVM_NoAuth_Client;

    { The no‑auth double‑tunnel client exposed by Client.DTClient. }
    { Set in the constructor from Client.DTClient. }
    DTNoAuthClient: TDTClient_NoAuth;

    { Property to access the no‑auth double‑tunnel client. }
    property DTNoAuth: TDTClient_NoAuth read DTNoAuthClient;

    { Returns the class type of the underlying no‑auth client. }
    { Override in descendants to use a different DTClient class. }
    { Default is TDTClient_NoAuth. }
    class function Get_Client_Class: TDTClient_NoAuthClass; virtual;

    { Constructor that initializes the VM client with a parameter string. }
    { Param_ - Configuration parameters (parsed into ParamList). }
    constructor Create(Param_: U_String); override;

    { Destructor. Disconnects and frees the underlying Client object. }
    destructor Destroy; override;

    { Main progress method – calls inherited and then Client.Progress. }
    procedure Progress; override;

    { Synchronously connects to a NoAuth VM service. }
    { addr  - Remote IP address. }
    { Port  - Remote port. }
    { Auth  - Authentication token (ignored for no‑auth). }
    procedure Connect(addr, Port, Auth: SystemString);

    { Asynchronously connects with a C‑style callback. }
    procedure Connect_C(addr, Port, Auth: SystemString; OnResult: TOnState_C);

    { Asynchronously connects with a method callback. }
    procedure Connect_M(addr, Port, Auth: SystemString; OnResult: TOnState_M);

    { Asynchronously connects with a nested/reference callback. }
    procedure Connect_P(addr, Port, Auth: SystemString; OnResult: TOnState_P);

    { Returns True if the double‑tunnel client is linked (LinkOk). }
    function Connected: Boolean; override;

    { Disconnects the client. }
    procedure Disconnect; override;
  end;

  { ============================================================================ }
  { DataStore NoAuth VM Service – extends TC40_NoAuth_VM_Service to provide }
  { DataStore capabilities (file system and database) without authentication. }
  { ============================================================================ }
  TC40_DataStore_NoAuth_VM_Service = class(TC40_NoAuth_VM_Service)
  public
    { Returns the DTNoAuthService cast to TDataStoreService_NoAuth. }
    function Get_DT_DataStore_NoAuth: TDataStoreService_NoAuth;

    { Property to access the DataStore no‑auth service. }
    property DT_DataStore_NoAuth: TDataStoreService_NoAuth read Get_DT_DataStore_NoAuth;

    { Overrides Get_Service_Class to return TDataStoreService_NoAuth. }
    class function Get_Service_Class: TDTService_NoAuthClass; override;
  end;

  { ============================================================================ }
  { DataStore NoAuth VM Client – extends TC40_NoAuth_VM_Client to provide }
  { DataStore client capabilities. }
  { ============================================================================ }
  TC40_DataStore_NoAuth_VM_Client = class(TC40_NoAuth_VM_Client)
  public
    { Returns the DTNoAuthClient cast to TDataStoreClient_NoAuth. }
    function Get_DT_DataStore_NoAuth: TDataStoreClient_NoAuth;

    { Property to access the DataStore no‑auth client. }
    property DT_DataStore_NoAuth: TDataStoreClient_NoAuth read Get_DT_DataStore_NoAuth;

    { Overrides Get_Client_Class to return TDataStoreClient_NoAuth. }
    class function Get_Client_Class: TDTClient_NoAuthClass; override;
  end;

  { ============================================================================ }
  { VirtualAuth VM Service – provides a P2PVM double‑tunnel service with }
  { virtual authentication (user registration and login callbacks). }
  { ============================================================================ }
  TC40_VirtualAuth_VM_Service = class(TC40_Custom_VM_Service)
  protected
    { Called when a client attempts to register a new user account. }
    { Sender - The virtual‑auth service. }
    { RegIO  - Registration I/O object; call Accept to allow registration. }
    { Default implementation accepts all registrations. }
    procedure DoUserReg_Event(Sender: TDTService_VirtualAuth; RegIO: TVirtualRegIO); virtual;

    { Called when a client attempts to authenticate. }
    { Sender - The virtual‑auth service. }
    { AuthIO - Authentication I/O object; call Accept to allow login. }
    { Default implementation accepts all login attempts. }
    procedure DoUserAuth_Event(Sender: TDTService_VirtualAuth; AuthIO: TVirtualAuthIO); virtual;

    { Called when a client successfully links to this service. }
    procedure DoLinkSuccess_Event(Sender: TDTService_VirtualAuth; UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth); virtual;

    { Called when a user/client disconnects from this service. }
    procedure DoUserOut_Event(Sender: TDTService_VirtualAuth; UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth); virtual;
  public
    { Underlying P2PVM service for virtual authentication. }
    { Created in the constructor. }
    Service: TDT_P2PVM_VirtualAuth_Service;

    { The virtual‑auth double‑tunnel service exposed by Service.DTService. }
    { Set in the constructor from Service.DTService. }
    DTVirtualAuthService: TDTService_VirtualAuth;

    { Property to access the virtual‑auth double‑tunnel service. }
    property DTVirtualAuth: TDTService_VirtualAuth read DTVirtualAuthService;

    { Returns the class type of the underlying virtual‑auth service. }
    { Default is TDTService_VirtualAuth. }
    class function Get_Service_Class: TDTService_VirtualAuthClass; virtual;

    constructor Create(Param_: U_String); override;
    destructor Destroy; override;
    procedure Progress; override;
    procedure StartService(ListenAddr, ListenPort, Auth: SystemString); override;
    procedure StopService; override;
  end;

  { ============================================================================ }
  { VirtualAuth VM Client – connects to a VirtualAuth VM service. }
  { ============================================================================ }
  TC40_VirtualAuth_VM_Client = class(TC40_Custom_VM_Client, IZNet_ClientInterface)
  protected
    { Called when the underlying physics client connects. }
    procedure ClientConnected(Sender: TZNet_Client); virtual;

    { Called when the underlying physics client disconnects. }
    procedure ClientDisconnect(Sender: TZNet_Client); virtual;

    { Called when the P2PVM double‑tunnel link is established. }
    procedure Do_DT_P2PVM_VirtualAuth_Custom_Client_TunnelLink(Sender: TDT_P2PVM_VirtualAuth_Client); virtual;
  public
    { Underlying P2PVM client for virtual authentication. }
    { Created in the constructor. }
    Client: TDT_P2PVM_VirtualAuth_Client;

    { The virtual‑auth double‑tunnel client exposed by Client.DTClient. }
    { Set in the constructor from Client.DTClient. }
    DTVirtualAuthClient: TDTClient_VirtualAuth;

    { Property to access the virtual‑auth double‑tunnel client. }
    property DTVirtualAuth: TDTClient_VirtualAuth read DTVirtualAuthClient;

    { Returns the class type of the underlying virtual‑auth client. }
    { Default is TDTClient_VirtualAuth. }
    class function Get_Client_Class: TDTClient_VirtualAuthClass; virtual;

    constructor Create(Param_: U_String); override;
    destructor Destroy; override;
    procedure Progress; override;

    { Synchronously connects to a VirtualAuth VM service. }
    { addr    - Remote IP address. }
    { Port    - Remote port. }
    { Auth    - Authentication token (used for P2PVM handshake). }
    { User    - Username for login. }
    { Passwd  - Password for login. }
    procedure Connect(addr, Port, Auth, User, Passwd: SystemString);

    { Asynchronously connects with a C‑style callback. }
    procedure Connect_C(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_C);

    { Asynchronously connects with a method callback. }
    procedure Connect_M(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_M);

    { Asynchronously connects with a nested/reference callback. }
    procedure Connect_P(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_P);

    function Connected: Boolean; override;
    procedure Disconnect; override;
  end;

  { ============================================================================ }
  { DataStore VirtualAuth VM Service – provides DataStore with virtual }
  { authentication. }
  { ============================================================================ }
  TC40_DataStore_VirtualAuth_VM_Service = class(TC40_VirtualAuth_VM_Service)
  public
    { Returns the DTVirtualAuthService cast to TDataStoreService_VirtualAuth. }
    function Get_DT_DataStore_VirtualAuth: TDataStoreService_VirtualAuth;

    { Property to access the DataStore virtual‑auth service. }
    property DT_DataStore_VirtualAuth: TDataStoreService_VirtualAuth read Get_DT_DataStore_VirtualAuth;

    { Overrides Get_Service_Class to return TDataStoreService_VirtualAuth. }
    class function Get_Service_Class: TDTService_VirtualAuthClass; override;
  end;

  { ============================================================================ }
  { DataStore VirtualAuth VM Client – connects to a DataStore VirtualAuth }
  { service. }
  { ============================================================================ }
  TC40_DataStore_VirtualAuth_VM_Client = class(TC40_VirtualAuth_VM_Client)
  public
    { Returns the DTVirtualAuthClient cast to TDataStoreClient_VirtualAuth. }
    function Get_DT_DataStore_VirtualAuth: TDataStoreClient_VirtualAuth;

    { Property to access the DataStore virtual‑auth client. }
    property DT_DataStore_VirtualAuth: TDataStoreClient_VirtualAuth read Get_DT_DataStore_VirtualAuth;

    { Overrides Get_Client_Class to return TDataStoreClient_VirtualAuth. }
    class function Get_Client_Class: TDTClient_VirtualAuthClass; override;
  end;

  { ============================================================================ }
  { Built‑in Auth VM Service – provides a P2PVM double‑tunnel service with }
  { built‑in authentication (user database managed by TDTService). }
  { ============================================================================ }
  TC40_VM_Service = class(TC40_Custom_VM_Service)
  protected
    { Called when a client successfully links to this service. }
    procedure DoLinkSuccess_Event(Sender: TDTService; UserDefineIO: TService_RecvTunnel_UserDefine); virtual;

    { Called when a user/client disconnects from this service. }
    procedure DoUserOut_Event(Sender: TDTService; UserDefineIO: TService_RecvTunnel_UserDefine); virtual;
  public
    { Underlying P2PVM service for built‑in authentication. }
    { Created in the constructor. }
    Service: TDT_P2PVM_Service;

    { The built‑in auth double‑tunnel service exposed by Service.DTService. }
    { Set in the constructor from Service.DTService. }
    DTVirtualAuthService: TDTService;

    { Property to access the built‑in auth double‑tunnel service. }
    property DTVirtualAuth: TDTService read DTVirtualAuthService;

    { Returns the class type of the underlying built‑in auth service. }
    { Default is TDTService. }
    class function Get_Service_Class: TDTServiceClass; virtual;

    constructor Create(Param_: U_String); override;
    destructor Destroy; override;
    procedure Progress; override;
    procedure StartService(ListenAddr, ListenPort, Auth: SystemString); override;
    procedure StopService; override;
  end;

  { ============================================================================ }
  { Built‑in Auth VM Client – connects to a built‑in auth VM service. }
  { ============================================================================ }
  TC40_VM_Client = class(TC40_Custom_VM_Client, IZNet_ClientInterface)
  protected
    { Called when the underlying physics client connects. }
    procedure ClientConnected(Sender: TZNet_Client); virtual;

    { Called when the underlying physics client disconnects. }
    procedure ClientDisconnect(Sender: TZNet_Client); virtual;

    { Called when the P2PVM double‑tunnel link is established. }
    procedure Do_DT_P2PVM_Custom_Client_TunnelLink(Sender: TDT_P2PVM_Client); virtual;
  public
    { Underlying P2PVM client for built‑in authentication. }
    { Created in the constructor. }
    Client: TDT_P2PVM_Client;

    { The built‑in auth double‑tunnel client exposed by Client.DTClient. }
    { Set in the constructor from Client.DTClient. }
    DTVirtualAuthClient: TDTClient;

    { Property to access the built‑in auth double‑tunnel client. }
    property DTVirtualAuth: TDTClient read DTVirtualAuthClient;

    { Returns the class type of the underlying built‑in auth client. }
    { Default is TDTClient. }
    class function Get_Client_Class: TDTClientClass; virtual;

    constructor Create(Param_: U_String); override;
    destructor Destroy; override;
    procedure Progress; override;

    { Synchronously connects to a built‑in auth VM service. }
    { addr    - Remote IP address. }
    { Port    - Remote port. }
    { Auth    - Authentication token (for P2PVM handshake). }
    { User    - Username for login. }
    { Passwd  - Password for login. }
    procedure Connect(addr, Port, Auth, User, Passwd: SystemString);

    { Asynchronously connects with a C‑style callback. }
    procedure Connect_C(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_C);

    { Asynchronously connects with a method callback. }
    procedure Connect_M(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_M);

    { Asynchronously connects with a nested/reference callback. }
    procedure Connect_P(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_P);

    function Connected: Boolean; override;
    procedure Disconnect; override;
  end;

  { ============================================================================ }
  { DataStore Built‑in Auth VM Service – provides DataStore with built‑in }
  { authentication. }
  { ============================================================================ }
  TC40_DataStore_VM_Service = class(TC40_VM_Service)
  public
    { Returns the DTVirtualAuthService cast to TDataStoreService. }
    function Get_DT_DataStore: TDataStoreService;

    { Property to access the DataStore built‑in auth service. }
    property DT_DataStore: TDataStoreService read Get_DT_DataStore;

    { Overrides Get_Service_Class to return TDataStoreService. }
    class function Get_Service_Class: TDTServiceClass; override;
  end;

  { ============================================================================ }
  { DataStore Built‑in Auth VM Client – connects to a DataStore built‑in auth }
  { service. }
  { ============================================================================ }
  TC40_DataStore_VM_Client = class(TC40_VM_Client)
  public
    { Returns the DTVirtualAuthClient cast to TDataStoreClient. }
    function Get_DT_DataStore: TDataStoreClient;

    { Property to access the DataStore built‑in auth client. }
    property DT_DataStore: TDataStoreClient read Get_DT_DataStore;

    { Overrides Get_Client_Class to return TDataStoreClient. }
    class function Get_Client_Class: TDTClientClass; override;
  end;

implementation

procedure TC40_NoAuth_VM_Service.DoLinkSuccess_Event(Sender: TDTService_NoAuth; UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth);
begin
  DoLinkSuccess(UserDefineIO);
end;

procedure TC40_NoAuth_VM_Service.DoUserOut_Event(Sender: TDTService_NoAuth; UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth);
begin
  DoUserOut(UserDefineIO);
end;

class function TC40_NoAuth_VM_Service.Get_Service_Class: TDTService_NoAuthClass;
begin
  Result := TDTService_NoAuth;
end;

constructor TC40_NoAuth_VM_Service.Create(Param_: U_String);
begin
  inherited Create(Param_);
  { custom p2pVM service }
  Service := TDT_P2PVM_NoAuth_Service.Create(Get_Service_Class, TIF<TZNet_ServerClass>.Do_(IPC_Mode, TZNet_Server_IPC, TPhysicsServer));
  Service.SendTunnel.SyncOnResult := True;
  Service.SendTunnel.SyncOnCompleteBuffer := True;
  Service.RecvTunnel.SyncOnResult := True;
  Service.RecvTunnel.SyncOnCompleteBuffer := True;
  Service.QuietMode := C40_QuietMode;

  Service.DTService.OnLinkSuccess := DoLinkSuccess_Event;
  Service.DTService.OnUserOut := DoUserOut_Event;
  Service.DTService.FileSystem := EStrToBool(ParamList.GetDefaultValue('FileSystem', umlBoolToStr(Service.DTService.FileSystem)), Service.DTService.FileSystem);

  if enablePerServiceDirectory then
    begin
      Service.DTService.PublicFileDirectory := umlCombinePath(C40_RootPath, ClassName);
      if not umlDirectoryExists(Service.DTService.PublicFileDirectory) then
          umlCreateDirectory(Service.DTService.PublicFileDirectory);
    end
  else
    begin
      Service.DTService.PublicFileDirectory := C40_RootPath;
    end;

  DTNoAuthService := Service.DTService;
end;

destructor TC40_NoAuth_VM_Service.Destroy;
begin
  StopService;
  disposeObject(Service);
  inherited Destroy;
end;

procedure TC40_NoAuth_VM_Service.Progress;
begin
  inherited Progress;
  Service.Progress;
end;

procedure TC40_NoAuth_VM_Service.StartService(ListenAddr, ListenPort, Auth: SystemString);
begin
  Service.StartService(ListenAddr, ListenPort, Auth);
end;

procedure TC40_NoAuth_VM_Service.StopService;
begin
  Service.StopService;
end;

procedure TC40_NoAuth_VM_Client.ClientConnected(Sender: TZNet_Client);
begin

end;

procedure TC40_NoAuth_VM_Client.ClientDisconnect(Sender: TZNet_Client);
begin
  DoNetworkOffline();
end;

procedure TC40_NoAuth_VM_Client.Do_DT_P2PVM_NoAuth_Custom_Client_TunnelLink(Sender: TDT_P2PVM_NoAuth_Client);
begin
  DoNetworkOnline();
end;

class function TC40_NoAuth_VM_Client.Get_Client_Class: TDTClient_NoAuthClass;
begin
  Result := TDTClient_NoAuth;
end;

constructor TC40_NoAuth_VM_Client.Create(Param_: U_String);
begin
  inherited Create(Param_);
  { custom p2pVM client }
  Client := TDT_P2PVM_NoAuth_Client.Create(Get_Client_Class, TIF<TZNet_ClientClass>.Do_(IPC_Mode, TZNet_Client_IPC, C40_PhysicsClientClass));
  Client.SendTunnel.SyncOnResult := True;
  Client.SendTunnel.SyncOnCompleteBuffer := True;
  Client.RecvTunnel.SyncOnResult := True;
  Client.RecvTunnel.SyncOnCompleteBuffer := True;
  Client.QuietMode := C40_QuietMode;

  Client.OnTunnelLink := Do_DT_P2PVM_NoAuth_Custom_Client_TunnelLink;
  DTNoAuthClient := Client.DTClient;
  Client.PhysicsTunnel.OnInterface := Self;
end;

destructor TC40_NoAuth_VM_Client.Destroy;
begin
  Client.PhysicsTunnel.OnInterface := nil;
  Client.Disconnect;
  disposeObject(Client);
  inherited Destroy;
end;

procedure TC40_NoAuth_VM_Client.Progress;
begin
  inherited Progress;
  Client.Progress;
end;

procedure TC40_NoAuth_VM_Client.Connect(addr, Port, Auth: SystemString);
begin
  Client.Connect(addr, Port, Auth);
end;

procedure TC40_NoAuth_VM_Client.Connect_C(addr, Port, Auth: SystemString; OnResult: TOnState_C);
begin
  Client.Connect_C(addr, Port, Auth, OnResult);
end;

procedure TC40_NoAuth_VM_Client.Connect_M(addr, Port, Auth: SystemString; OnResult: TOnState_M);
begin
  Client.Connect_M(addr, Port, Auth, OnResult);
end;

procedure TC40_NoAuth_VM_Client.Connect_P(addr, Port, Auth: SystemString; OnResult: TOnState_P);
begin
  Client.Connect_P(addr, Port, Auth, OnResult);
end;

function TC40_NoAuth_VM_Client.Connected: Boolean;
begin
  Result := Client.DTClient.LinkOk;
end;

procedure TC40_NoAuth_VM_Client.Disconnect;
begin
  Client.Disconnect;
end;

function TC40_DataStore_NoAuth_VM_Service.Get_DT_DataStore_NoAuth: TDataStoreService_NoAuth;
begin
  Result := DTNoAuthService as TDataStoreService_NoAuth;
end;

class function TC40_DataStore_NoAuth_VM_Service.Get_Service_Class: TDTService_NoAuthClass;
begin
  Result := TDataStoreService_NoAuth;
end;

function TC40_DataStore_NoAuth_VM_Client.Get_DT_DataStore_NoAuth: TDataStoreClient_NoAuth;
begin
  Result := DTNoAuthClient as TDataStoreClient_NoAuth;
end;

class function TC40_DataStore_NoAuth_VM_Client.Get_Client_Class: TDTClient_NoAuthClass;
begin
  Result := TDataStoreClient_NoAuth;
end;

procedure TC40_VirtualAuth_VM_Service.DoUserReg_Event(Sender: TDTService_VirtualAuth; RegIO: TVirtualRegIO);
begin
  RegIO.Accept;
end;

procedure TC40_VirtualAuth_VM_Service.DoUserAuth_Event(Sender: TDTService_VirtualAuth; AuthIO: TVirtualAuthIO);
begin
  AuthIO.Accept;
end;

procedure TC40_VirtualAuth_VM_Service.DoLinkSuccess_Event(Sender: TDTService_VirtualAuth; UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth);
begin
  DoLinkSuccess(UserDefineIO);
end;

procedure TC40_VirtualAuth_VM_Service.DoUserOut_Event(Sender: TDTService_VirtualAuth; UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth);
begin
  DoUserOut(UserDefineIO);
end;

class function TC40_VirtualAuth_VM_Service.Get_Service_Class: TDTService_VirtualAuthClass;
begin
  Result := TDTService_VirtualAuth;
end;

constructor TC40_VirtualAuth_VM_Service.Create(Param_: U_String);
begin
  inherited Create(Param_);
  { custom p2pVM service }
  Service := TDT_P2PVM_VirtualAuth_Service.Create(Get_Service_Class, TIF<TZNet_ServerClass>.Do_(IPC_Mode, TZNet_Server_IPC, TPhysicsServer));
  Service.SendTunnel.SyncOnResult := True;
  Service.SendTunnel.SyncOnCompleteBuffer := True;
  Service.RecvTunnel.SyncOnResult := True;
  Service.RecvTunnel.SyncOnCompleteBuffer := True;
  Service.QuietMode := C40_QuietMode;

  Service.DTService.OnUserAuth := DoUserAuth_Event;
  Service.DTService.OnUserReg := DoUserReg_Event;
  Service.DTService.OnLinkSuccess := DoLinkSuccess_Event;
  Service.DTService.OnUserOut := DoUserOut_Event;
  Service.DTService.FileSystem := EStrToBool(ParamList.GetDefaultValue('FileSystem', umlBoolToStr(Service.DTService.FileSystem)), Service.DTService.FileSystem);

  if enablePerServiceDirectory then
    begin
      Service.DTService.PublicFileDirectory := umlCombinePath(C40_RootPath, ClassName);
      if not umlDirectoryExists(Service.DTService.PublicFileDirectory) then
          umlCreateDirectory(Service.DTService.PublicFileDirectory);
    end
  else
    begin
      Service.DTService.PublicFileDirectory := C40_RootPath;
    end;

  DTVirtualAuthService := Service.DTService;
end;

destructor TC40_VirtualAuth_VM_Service.Destroy;
begin
  StopService;
  disposeObject(Service);
  inherited Destroy;
end;

procedure TC40_VirtualAuth_VM_Service.Progress;
begin
  inherited Progress;
  Service.Progress;
end;

procedure TC40_VirtualAuth_VM_Service.StartService(ListenAddr, ListenPort, Auth: SystemString);
begin
  Service.StartService(ListenAddr, ListenPort, Auth);
end;

procedure TC40_VirtualAuth_VM_Service.StopService;
begin
  Service.StopService;
end;

procedure TC40_VirtualAuth_VM_Client.ClientConnected(Sender: TZNet_Client);
begin

end;

procedure TC40_VirtualAuth_VM_Client.ClientDisconnect(Sender: TZNet_Client);
begin
  DoNetworkOffline();
end;

procedure TC40_VirtualAuth_VM_Client.Do_DT_P2PVM_VirtualAuth_Custom_Client_TunnelLink(Sender: TDT_P2PVM_VirtualAuth_Client);
begin
  DoNetworkOnline();
end;

class function TC40_VirtualAuth_VM_Client.Get_Client_Class: TDTClient_VirtualAuthClass;
begin
  Result := TDTClient_VirtualAuth;
end;

constructor TC40_VirtualAuth_VM_Client.Create(Param_: U_String);
begin
  inherited Create(Param_);
  { custom p2pVM client }
  Client := TDT_P2PVM_VirtualAuth_Client.Create(Get_Client_Class, TIF<TZNet_ClientClass>.Do_(IPC_Mode, TZNet_Client_IPC, C40_PhysicsClientClass));
  Client.SendTunnel.SyncOnResult := True;
  Client.SendTunnel.SyncOnCompleteBuffer := True;
  Client.RecvTunnel.SyncOnResult := True;
  Client.RecvTunnel.SyncOnCompleteBuffer := True;
  Client.QuietMode := C40_QuietMode;

  Client.OnTunnelLink := Do_DT_P2PVM_VirtualAuth_Custom_Client_TunnelLink;
  DTVirtualAuthClient := Client.DTClient;
  Client.PhysicsTunnel.OnInterface := Self;
end;

destructor TC40_VirtualAuth_VM_Client.Destroy;
begin
  Client.PhysicsTunnel.OnInterface := nil;
  Client.Disconnect;
  disposeObject(Client);
  inherited Destroy;
end;

procedure TC40_VirtualAuth_VM_Client.Progress;
begin
  inherited Progress;
  Client.Progress;
end;

procedure TC40_VirtualAuth_VM_Client.Connect(addr, Port, Auth, User, Passwd: SystemString);
begin
  Client.Connect(addr, Port, Auth, User, Passwd);
end;

procedure TC40_VirtualAuth_VM_Client.Connect_C(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_C);
begin
  Client.Connect_C(addr, Port, Auth, User, Passwd, OnResult);
end;

procedure TC40_VirtualAuth_VM_Client.Connect_M(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_M);
begin
  Client.Connect_M(addr, Port, Auth, User, Passwd, OnResult);
end;

procedure TC40_VirtualAuth_VM_Client.Connect_P(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_P);
begin
  Client.Connect_P(addr, Port, Auth, User, Passwd, OnResult);
end;

function TC40_VirtualAuth_VM_Client.Connected: Boolean;
begin
  Result := Client.DTClient.LinkOk;
end;

procedure TC40_VirtualAuth_VM_Client.Disconnect;
begin
  Client.Disconnect;
end;

function TC40_DataStore_VirtualAuth_VM_Service.Get_DT_DataStore_VirtualAuth: TDataStoreService_VirtualAuth;
begin
  Result := DTVirtualAuthService as TDataStoreService_VirtualAuth;
end;

class function TC40_DataStore_VirtualAuth_VM_Service.Get_Service_Class: TDTService_VirtualAuthClass;
begin
  Result := TDataStoreService_VirtualAuth;
end;

function TC40_DataStore_VirtualAuth_VM_Client.Get_DT_DataStore_VirtualAuth: TDataStoreClient_VirtualAuth;
begin
  Result := DTVirtualAuthClient as TDataStoreClient_VirtualAuth;
end;

class function TC40_DataStore_VirtualAuth_VM_Client.Get_Client_Class: TDTClient_VirtualAuthClass;
begin
  Result := TDataStoreClient_VirtualAuth;
end;

procedure TC40_VM_Service.DoLinkSuccess_Event(Sender: TDTService; UserDefineIO: TService_RecvTunnel_UserDefine);
begin
  DoLinkSuccess(UserDefineIO);
end;

procedure TC40_VM_Service.DoUserOut_Event(Sender: TDTService; UserDefineIO: TService_RecvTunnel_UserDefine);
begin
  DoUserOut(UserDefineIO);
end;

class function TC40_VM_Service.Get_Service_Class: TDTServiceClass;
begin
  Result := TDTService;
end;

constructor TC40_VM_Service.Create(Param_: U_String);
begin
  inherited Create(Param_);
  { custom p2pVM service }
  Service := TDT_P2PVM_Service.Create(Get_Service_Class, TIF<TZNet_ServerClass>.Do_(IPC_Mode, TZNet_Server_IPC, TPhysicsServer));
  Service.SendTunnel.SyncOnResult := True;
  Service.SendTunnel.SyncOnCompleteBuffer := True;
  Service.RecvTunnel.SyncOnResult := True;
  Service.RecvTunnel.SyncOnCompleteBuffer := True;
  Service.QuietMode := C40_QuietMode;

  Service.DTService.OnLinkSuccess := DoLinkSuccess_Event;
  Service.DTService.OnUserOut := DoUserOut_Event;
  Service.DTService.FileSystem := EStrToBool(ParamList.GetDefaultValue('FileSystem', umlBoolToStr(Service.DTService.FileSystem)), Service.DTService.FileSystem);

  if enablePerServiceDirectory then
    begin
      Service.DTService.RootPath := umlCombinePath(C40_RootPath, ClassName);
      Service.DTService.PublicPath := Service.DTService.RootPath;
      if not umlDirectoryExists(Service.DTService.RootPath) then
          umlCreateDirectory(Service.DTService.RootPath);
    end
  else
    begin
      Service.DTService.RootPath := C40_RootPath;
      Service.DTService.PublicPath := Service.DTService.RootPath;
    end;

  DTVirtualAuthService := Service.DTService;
end;

destructor TC40_VM_Service.Destroy;
begin
  StopService;
  disposeObject(Service);
  inherited Destroy;
end;

procedure TC40_VM_Service.Progress;
begin
  inherited Progress;
  Service.Progress;
end;

procedure TC40_VM_Service.StartService(ListenAddr, ListenPort, Auth: SystemString);
begin
  Service.StartService(ListenAddr, ListenPort, Auth);
end;

procedure TC40_VM_Service.StopService;
begin
  Service.StopService;
end;

procedure TC40_VM_Client.ClientConnected(Sender: TZNet_Client);
begin

end;

procedure TC40_VM_Client.ClientDisconnect(Sender: TZNet_Client);
begin
  DoNetworkOffline();
end;

procedure TC40_VM_Client.Do_DT_P2PVM_Custom_Client_TunnelLink(Sender: TDT_P2PVM_Client);
begin
  DoNetworkOnline();
end;

class function TC40_VM_Client.Get_Client_Class: TDTClientClass;
begin
  Result := TDTClient;
end;

constructor TC40_VM_Client.Create(Param_: U_String);
begin
  inherited Create(Param_);
  { custom p2pVM client }
  Client := TDT_P2PVM_Client.Create(Get_Client_Class, TIF<TZNet_ClientClass>.Do_(IPC_Mode, TZNet_Client_IPC, C40_PhysicsClientClass));
  Client.SendTunnel.SyncOnResult := True;
  Client.SendTunnel.SyncOnCompleteBuffer := True;
  Client.RecvTunnel.SyncOnResult := True;
  Client.RecvTunnel.SyncOnCompleteBuffer := True;
  Client.QuietMode := C40_QuietMode;

  Client.OnTunnelLink := Do_DT_P2PVM_Custom_Client_TunnelLink;
  DTVirtualAuthClient := Client.DTClient;
  Client.PhysicsTunnel.OnInterface := Self;
end;

destructor TC40_VM_Client.Destroy;
begin
  Client.PhysicsTunnel.OnInterface := nil;
  Client.Disconnect;
  disposeObject(Client);
  inherited Destroy;
end;

procedure TC40_VM_Client.Progress;
begin
  inherited Progress;
  Client.Progress;
end;

procedure TC40_VM_Client.Connect(addr, Port, Auth, User, Passwd: SystemString);
begin
  Client.Connect(addr, Port, Auth, User, Passwd);
end;

procedure TC40_VM_Client.Connect_C(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_C);
begin
  Client.Connect_C(addr, Port, Auth, User, Passwd, OnResult);
end;

procedure TC40_VM_Client.Connect_M(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_M);
begin
  Client.Connect_M(addr, Port, Auth, User, Passwd, OnResult);
end;

procedure TC40_VM_Client.Connect_P(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_P);
begin
  Client.Connect_P(addr, Port, Auth, User, Passwd, OnResult);
end;

function TC40_VM_Client.Connected: Boolean;
begin
  Result := Client.DTClient.LinkOk;
end;

procedure TC40_VM_Client.Disconnect;
begin
  Client.Disconnect;
end;

function TC40_DataStore_VM_Service.Get_DT_DataStore: TDataStoreService;
begin
  Result := DTVirtualAuthService as TDataStoreService;
end;

class function TC40_DataStore_VM_Service.Get_Service_Class: TDTServiceClass;
begin
  Result := TDataStoreService;
end;

function TC40_DataStore_VM_Client.Get_DT_DataStore: TDataStoreClient;
begin
  Result := DTVirtualAuthClient as TDataStoreClient;
end;

class function TC40_DataStore_VM_Client.Get_Client_Class: TDTClientClass;
begin
  Result := TDataStoreClient;
end;

end.
 
