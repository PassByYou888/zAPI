{ ******************************************************************************
  * Z.Net.C4.API_Hub – Bridges the language-neutral API Hub framework with the
  * C4 distributed service mesh.
  *
  * This unit provides a service (TC40_API_HUB_Service) that routes API calls
  * and notifications between connected clients, and a client
  * (TC40_API_HUB_Client) that can host a local application (TAPI_APP) and call
  * remote ones over the network. All communication uses C4's P2PVM double-
  * tunnel infrastructure with no authentication (for simplicity, though
  * authentication can be added by changing the base class).
  *
  * ===========================================================================
  * Key Concepts
  * ===========================================================================
  *
  *   – API Hub: A language-neutral RPC framework where applications expose
  *     functions (APIs) as either request-response (Call) or one-way (Notify)
  *     endpoints. Each endpoint is identified by a unique name.
  *
  *   – TAPI_APP: A logical container that groups a set of APIs under one name.
  *     This is the object that gets registered with the network.
  *
  *   – C4 Service Mesh: The underlying distributed framework that provides
  *     service discovery, automatic reconnection, load balancing, and P2PVM
  *     tunnelling. The API Hub sits on top of C4, using its transport layer.
  *
  *   – Double-Tunnel I/O: Each client maintains two separate tunnels
  *     (receive and send) for full-duplex communication. The service uses
  *     these to route messages.
  *
  * ===========================================================================
  * Architecture Overview
  * ===========================================================================
  *
  *   ┌─────────────────────────────────────────────────────────────────────────┐
  *   │                     TC40_API_HUB_Service (Hub)                          │
  *   │  - Accepts client connections via C4 no-auth double-tunnel              │
  *   │  - Maintains a registry of all connected applications                   │
  *   │     (APP_Name, APP_Desc, process info, list of exported API names)      │
  *   │  - Routes incoming 'Call' and 'Notify' requests to the correct client   │
  *   │  - Supports wildcard matching on app names (e.g., 'MyApp*')             │
  *   └─────────────────────────────────────────────────────────────────────────┘
  *                                      │
  *                                      │ (C4 P2PVM Tunnel)
  *                                      ▼
  *   ┌─────────────────────────────────────────────────────────────────────────┐
  *   │                     TC40_API_HUB_Client (Client)                        │
  *   │  - Connects to the Hub and automatically registers its local APP        │
  *   │  - Hosts a TAPI_APP (set via the APP property)                          │
  *   │  - Sends notifications (Send_Execute_Notify) and synchronous calls      │
  *   │     (Wait_Execute_Call) to remote applications                          │
  *   │  - Detects local clients (same process) and executes directly without   │
  *   │     network round-trip (optimisation)                                   │
  *   │  - Reports thread-load statistics to the Hub for load-aware routing     │
  *   └─────────────────────────────────────────────────────────────────────────┘
  *
  * ===========================================================================
  * Key Classes
  * ===========================================================================
  *
  *   – TC40_API_HUB_Service   : The central hub that runs on the server side.
  *                              Handles registration, routing, and forwarding.
  *   – TC40_API_HUB_Client    : The client component that connects to a hub.
  *                              Can host a local app and call remote ones.
  *   – TC40_API_HUB_Service_RecvTunnel_NoAuth : Per-connection registry data.
  *   – TCall_Bridge__         : Internal helper for asynchronous call results.
  *
  * ===========================================================================
  * Typical Usage
  * ===========================================================================
  *
  * 1. On the service side (e.g., inside a C4 PhysicsService):
  *      PhysicsService.BuildDependNetwork('APIHub');
  *    This creates an instance of TC40_API_HUB_Service automatically.
  *
  * 2. On the client side (e.g., inside a C4 PhysicsTunnel):
  *      var
  *        App: TAPI_APP;
  *        Client: TC40_API_HUB_Client;
  *      begin
  *        App := TAPI_APP.Create;
  *        App.Name := 'MyApp';
  *        App.API.Reg_Call('echo', 'Echo service', nil, MyEchoCallback);
  *        Client := PhysicsTunnel.DependNetworkClientPool.FindConnectedClass(...) as TC40_API_HUB_Client;
  *        Client.APP := App;   // This registers the app with the hub.
  *      end;
  *
  * 3. To call a remote API (from any client):
  *      var
  *        Param, Result: TMem64;
  *      begin
  *        Param := TMem64.Create;
  *        Param.WriteString('Hello');
  *        Result := Client.Wait_Execute_Call('RemoteApp', Param, 5000);
  *        if Result <> nil then
  *          // Process Result
  *        DisposeObject(Result);
  *      end;
  *
  * 4. To send a one-way notification:
  *      Client.Send_Execute_Notify('Logger', Param);  // Param is consumed.
  *
  * ===========================================================================
  * Local Execution Optimisation
  * ===========================================================================
  *
  *   The system always checks for a local (same-process) client that matches
  *   the target app name and API. If found, the call/notification is executed
  *   directly without going over the network. This greatly reduces latency
  *   for inter-module communication within the same process.
  *
  *   The check uses the global C40_ClientPool and the `Find_Local_API_Hub`
  *   function, which supports wildcard patterns.
  *
  * ===========================================================================
  * Load-Aware Routing
  * ===========================================================================
  *
  *   Each client reports two thread-count statistics to the service every
  *   second: Host_Running_Thread_Num (threads handling incoming requests) and
  *   Wait_Reponse_Thread_Num (threads waiting for remote replies). When
  *   multiple clients match the target app, the service selects the one with
  *   the lowest combined load (Host + Wait). This helps distribute work
  *   evenly across clients.
  *
  * ===========================================================================
  * Dependencies
  * ===========================================================================
  *
  *   This unit requires:
  *     – Z.Core                (foundation: threads, containers, memory)
  *     – Z.Net                 (base network framework)
  *     – Z.Net.C4              (C4 service mesh)
  *     – Z.Net.DoubleTunnelIO.NoAuth  (double-tunnel no-auth I/O)
  *     – API_HubTool           (core API Hub types and registry)
  *
  *   It also includes the 'Z.System_ProcessID.inc' file for process identification.
  *
  * ===========================================================================
  * Important Notes & Restrictions
  * ===========================================================================
  *
  *   – THREAD SAFETY: The library is NOT thread-safe. All API calls must be
  *     made from the same thread that runs the C4 progress loop (usually the
  *     simulated main thread). Callbacks may be executed in background
  *     threads (from the thread pool), so they must be thread-safe and must
  *     NOT block.
  *
  *   – CALLBACK BLOCKING: Inside a callback, do NOT call Wait_Execute_Call
  *     or any blocking operation – this may cause deadlocks. Offload heavy
  *     work to separate threads.
  *
  *   – DATA HANDLE LIFETIME: TDataHnd and TAppHnd handles must be explicitly
  *     freed using API_Free_DataHnd / API_Free_APPHnd. The library does NOT
  *     automatically free them, even after a remote call.
  *
  *   – APPLICATION NAMES: App names are case-sensitive and should be unique
  *     within the network. Wildcards ('*') are supported for matching but
  *     should not be used as actual app names.
  *
  *   – REGISTRATION ORDER: Clients should set the APP property before the
  *     tunnel link is fully established, or call Init_App_Info after setting
  *     APP to ensure registration occurs.
  *
  *   – TIMEOUTS: A timeout of 0 in Wait_Execute_Call means infinite wait.
  *     On timeout, the function returns nil. Always check the result.
  *
  *   – MAXIMUM BUFFER SIZE: The service limits complete-buffer size to
  *     500 MB by default (configurable via the 'MaxBuffer' parameter).
  *
  * ===========================================================================
  * Example: Service Configuration
  * ===========================================================================
  *
  *   // In your PhysicsService creation (Param string):
  *   'APIHub@MaxBuffer=104857600'   // sets buffer limit to 100 MB
  *
  * ===========================================================================
  * Example: Registering a Local App
  * ===========================================================================
  *
  *   var
  *     MyApp: TAPI_APP;
  *   begin
  *     MyApp := TAPI_APP.Create;
  *     MyApp.Name := 'Calculator';
  *     MyApp.API.Reg_Call('add', 'Adds two integers', nil, @AddCallback);
  *     MyApp.API.Reg_Notify('log', 'Logs a message', nil, @LogCallback);
  *
  *     // After the client is connected and the APP is set, Init_App_Info is
  *     // automatically called, but you can also call it manually:
  *     Client.APP := MyApp;
  *   end;
  *
  * ===========================================================================
  * Example: Making a Remote Call
  * ===========================================================================
  *
  *   var
  *     Param, Result: TMem64;
  *     Sum: Integer;
  *   begin
  *     Param := TMem64.Create;
  *     Param.WriteInt32(5);
  *     Param.WriteInt32(7);
  *     Result := Client.Wait_Execute_Call('Calculator', Param, 3000);
  *     if Result <> nil then
  *     begin
  *       Sum := Result.ReadInt32;
  *       WriteLn('Sum = ', Sum);
  *       DisposeObject(Result);
  *     end;
  *     // Param is consumed (freed) by the method, no need to free it here.
  *   end;
  *
  * ===========================================================================
  * Example: Sending a Notification
  * ===========================================================================
  *
  *   var
  *     Param: TMem64;
  *   begin
  *     Param := TMem64.Create;
  *     Param.WriteString('Hello World');
  *     Client.Send_Execute_Notify('Logger', Param);
  *     // Param is freed by the method.
  *   end;
  *
  * ===========================================================================
  * Troubleshooting
  * ===========================================================================
  *
  *   – If the client fails to register, check the status logs via
  *     API_Get_Status or the C4 status output. Common issues: APP name empty,
  *     duplicate API names, or network connectivity problems.
  *   – If a remote call times out, verify that the target client is online
  *     and that its APP is correctly registered. Also check that the API name
  *     matches exactly.
  *   – If callbacks are not triggered, ensure the callback functions are
  *     assigned to the correct API and that the APP is online.
  *
  * ===========================================================================
  * Author / Version
  * ===========================================================================
  *
  *   Part of the Z.Net.C4 library suite. See the main project documentation
  *   for version and licensing information.
  ****************************************************************************** }
unit Z.Net.C4.API_Hub;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\pascal\zNetV2\source\Z.Define.inc}

interface

uses
{$IFDEF FPC}
  SysUtils,
  Z.FPC.GenericList,
{$ELSE FPC}
{$IFDEF MSWINDOWS}
  Windows,
{$ELSE}
  Posix.Unistd,
{$ENDIF}
{$ENDIF FPC}
  Variants, Math,
  Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.Status, Z.UnicodeMixedLib,
  Z.ListEngine, Z.Geometry2D, Z.DFE, Z.Json, Z.Expression, Z.OpCode, Z.Notify,
  Z.Cipher, Z.MemoryStream, Z.Int128,
  Z.Net, Z.Net.PhysicsIO, Z.Net.DoubleTunnelIO.NoAuth, Z.Net.C4,
  Z.API_HubTool;

type
  TC40_API_HUB_Service = class;

  { * TC40_API_HUB_Service_RecvTunnel_NoAuth
    * Per-connection user-defined object attached to each receive-tunnel
    * connection on the service side. Stores all registration information
    * about the application that this client exposes, plus runtime thread
    * statistics for load-aware routing.
    *
    * @Field API_HUB_Service       – Owning service instance.
    * @Field APP_Name              – Registered application name (case-sensitive).
    * @Field APP_Desc              – Human-readable description.
    * @Field APP_Process_Info      – Process identifier (e.g., "MyApp(1234)").
    * @Field api_info_data         – Hash list where keys are exported API names.
    * @Field Host_Running_Thread_Num – Number of active threads handling requests from this client.
    * @Field Wait_Reponse_Thread_Num – Number of threads waiting for responses from this client. }
  TC40_API_HUB_Service_RecvTunnel_NoAuth = class(TService_RecvTunnel_UserDefine_NoAuth)
  private
    Last_Selected_Time: TTimeTick; // Timestamp of last selection for load balancing
  public
    API_HUB_Service: TC40_API_HUB_Service;
    APP_Name: TAPI_String;
    APP_Desc: TAPI_String;
    APP_Process_Info: TAPI_String;
    api_info_data: THashList; // API names (keys only, values are nil)
    Host_Running_Thread_Num: Integer;
    Wait_Reponse_Thread_Num: Integer;
    Is_Local: Boolean; // True if connected via IPC or local network

    constructor Create(Owner_: TPeerIO); override;
    destructor Destroy; override;
  end;

  TC40_API_HUB_Service_RecvTunnel_NoAuth_List = class(TBigList<TC40_API_HUB_Service_RecvTunnel_NoAuth>)
  end;

  { * TAPI_Service_Info__: Internal snapshot of a client's registration data.
    * Used for broadcasting service information to other service instances. }
  TAPI_Service_Info__ = class
  public
    APP_Name: TAPI_String;
    APP_Desc: TAPI_String;
    APP_Process_Info: TAPI_String;
    api_info_data: THashList;
    Host_Running_Thread_Num: Integer;
    Wait_Reponse_Thread_Num: Integer;
    Is_Local: Boolean;

    constructor Create;
    destructor Destroy; override;
    procedure Assign(source: TC40_API_HUB_Service_RecvTunnel_NoAuth);
    procedure SaveToStream(stream: TCore_Stream);
    procedure LoadFromStream(stream: TCore_Stream);
  end;

  { * TAPI_Service_Info_Pool__: List of TAPI_Service_Info__ objects,
    * used to build and store a snapshot of all currently registered
    * applications for broadcasting to other service instances. }
  TAPI_Service_Info_Pool__ = class(TBig_Object_List<TAPI_Service_Info__>)
  public
    constructor Create;
    destructor Destroy; override;
    procedure Build_Info_Form(Inst: TC40_API_HUB_Service_RecvTunnel_NoAuth);
    procedure SaveToStream(d: TDFE);
    procedure LoadFromStream(d: TDFE);
    function Find_API(appName, apiName: TAPI_String): Boolean;
    function Find_APP(appName: TAPI_String): Boolean;
  end;

  { * TC40_API_HUB_Service_SendTunnel_NoAuth
    * User-defined object for the send-tunnel side; holds a back-reference
    * to the owning service for housekeeping. }
  TC40_API_HUB_Service_SendTunnel_NoAuth = class(TService_SendTunnel_UserDefine_NoAuth)
  public
    API_HUB_Service: TC40_API_HUB_Service;
    constructor Create(Owner_: TPeerIO); override;
    destructor Destroy; override;
  end;

  { * TC40_API_HUB_Service
    * Central hub that accepts client connections, maintains a registry of all
    * applications (including those on other service instances), and routes API
    * calls and notifications to the correct destination.
    *
    * Routing logic:
    *   1. For a 'Call' or 'Notify', the service extracts the target application
    *      name and the API name.
    *   2. It first tries to find a local (same-process) API Hub client using
    *      Find_Local_API_Hub – if found, the request is executed locally
    *      (bypassing the network) for optimal performance.
    *   3. Otherwise, it scans all connected clients (including those on other
    *      service instances) that match the application name (wildcards
    *      supported) and forwards the request to the first matching client.
    *
    * @Example:
    *   // In your C4 service startup code:
    *   PhysicsService.BuildDependNetwork('APIHub');
    *   // This will create an instance of TC40_API_HUB_Service automatically.
    *   // Clients can then connect and register their applications. }
  TC40_API_HUB_Service = class(TC40_Base_NoAuth_Service)
  private
    FDelay_Broadcast_API_Info_Time: TTimeTick; // Earliest time when the next broadcast is allowed
    FNeed_Broadcast_API_Info: Boolean; // Flag indicating a broadcast is pending
    procedure Do_Delay_Broadcast_API_Info;
  protected
    procedure DoLinkSuccess_Event(Sender: TDTService_NoAuth; UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth); override;
    procedure DoUserOut_Event(Sender: TDTService_NoAuth; UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth); override;

    { * cmd_Init_APP_Info
      * Registers an application from a client. Reads the application name,
      * description, process info and a list of API names, and stores them in
      * the receive-tunnel user object for later routing.
      *
      * @Param Sender:   The bridge that contains the incoming data.
      * @Param InData:   DFE containing: appName, appDesc, processInfo, and a
      *                  Pascal-string list of API names.
      * @Param OutData:  Unused (this command expects no reply).
      *
      * @Example (client side):
      *   var
      *     d: TDFE;
      *   begin
      *     d := TDFE.Create;
      *     d.WriteString('MyApp');
      *     d.WriteString('My description');
      *     d.WriteString('MyApp(1234)');
      *     d.WritePascalStrings(['add', 'echo']);
      *     SendCompleteBuffer_NoWait_StreamM('Init_APP_Info', d, ...);
      *   end; }
    procedure cmd_Init_APP_Info(Sender: TCommandCompleteBuffer_NoWait_Bridge; InData, OutData: TDFE);
    procedure cmd_No_App_Info(Sender: TPeerIO; InData: SystemString);

    { * cmd_Thread_State
      * Receives runtime thread-count updates from a client. These are used
      * for load-aware routing: the service may prefer clients with lower
      * thread load when multiple match the target app.
      *
      * @Param Sender:   The peer I/O that sent the command.
      * @Param InData:   DFE containing two integers: Host_Running_Thread_Num
      *                  and Wait_Reponse_Thread_Num. }
    procedure cmd_Thread_State(Sender: TPeerIO; InData: TDFE);

    { * Do_Run_Notify_Th
      * Background thread worker that executes a local notification. Runs inside
      * a THPC_StreamNotify context. Decodes the incoming DFE to retrieve the
      * target application name and the payload, finds the local TAPI_APP from
      * the thread's UserObject, and executes the notification.
      *
      * @Param thSender:  The HPC thread object containing the UserObject (TAPI_APP).
      * @Param ThInData:  DFE containing: appName and a TMem64 payload. }
    procedure Do_Run_Notify_Th(thSender: THPC_StreamNotify; ThInData: TDFE);

    { * cmd_Notify
      * Handles an incoming notification from a client. Extracts the target
      * application name and payload, then routes it to a matching local or
      * remote client. If a local API Hub client matches, the notification is
      * executed directly in a background thread; otherwise it is forwarded to
      * the appropriate service instance/client.
      *
      * @Param Sender:   The peer I/O that sent this command.
      * @Param InData:   DFE containing: appName and a TMem64 payload. }
    procedure cmd_Notify(Sender: TPeerIO; InData: TDFE);

    { * Do_Run_Call_Th
      * Background thread worker that executes a synchronous call locally. Runs
      * inside a THPC_CompleteBuffer_Stream context. Decodes the incoming DFE
      * to get the target application and payload, invokes the local API, and
      * writes the result back into ThOutData.
      *
      * @Param thSender:  HPC object with UserObject = TAPI_APP.
      * @Param ThInData:  DFE containing: appName and a TMem64 payload.
      * @Param ThOutData: DFE that will contain the result TMem64. }
    procedure Do_Run_Call_Th(thSender: THPC_CompleteBuffer_Stream; ThInData, ThOutData: TDFE);

    { * cmd_Call
      * Handles an incoming synchronous call from a client. Extracts the target
      * app and payload, attempts local execution (via Find_Local_API_Hub) or
      * forwards to a matching remote client. If a remote client is found, the
      * call is forwarded and the result is returned via the bridge (the caller
      * waits for the response).
      *
      * @Param Sender:   The bridge that contains the incoming data.
      * @Param InData:   DFE containing: appName and a TMem64 payload.
      * @Param OutData:  DFE that will be filled with the result TMem64. }
    procedure cmd_Call(Sender: TCommandCompleteBuffer_NoWait_Bridge; InData, OutData: TDFE);

  public
    constructor Create(PhysicsService_: TC40_PhysicsService; ServiceTyp, Param_: U_String); override;
    destructor Destroy; override;
    procedure SafeCheck; override;
    procedure Progress; override;

    { * Broadcasts the current list of registered applications to all connected
      * clients (so that each client knows which apps are available on other
      * clients). This is called periodically or when a new registration occurs. }
    procedure Broadcast_API_Info();

    { * Find_API
      * Searches all connected clients (receive tunnels) for one that hosts the
      * specified application and exposes the given API name. Wildcards are
      * supported in appName (e.g., '*' matches any).
      *
      * @Param appName   Application name to match (case-sensitive, supports wildcards).
      * @Param apiName   Exact API name to look for.
      * @Returns         The receive-tunnel user object of the first matching
      *                  client, or nil if none found.
      *
      * @Example:
      *   var IO := Service.Find_API('MyApp', 'add');
      *   if IO <> nil then
      *     IO.SendTunnel.Owner.SendCompleteBuffer(...); // forward to that client }
    function Do_CmpIOThNum(var L, R: TC40_API_HUB_Service_RecvTunnel_NoAuth): Integer;
    function Find_API(appName, apiName: TAPI_String): TC40_API_HUB_Service_RecvTunnel_NoAuth;
  end;

  { * TC40_API_HUB_Client
    * Client-side component that connects to a TC40_API_HUB_Service. It can host
    * a local TAPI_APP (set via APP property) and provides methods to send
    * notifications and calls to remote or local applications. The client
    * automatically registers its application with the service upon connection.
    *
    * @Example:
    *   // Create a TAPI_APP and register some APIs.
    *   var App := TAPI_APP.Create;
    *   App.Name := 'my_app';
    *   App.API.Reg_Call('echo', 'Echo service', nil, MyEchoCallback);
    *   // In your C4 client code, after obtaining the client instance:
    *   Client.APP := App;   // This will register with the service.
    *   // To call a remote API:
    *   var Param := TMem64.Create;
    *   Param.WriteString('Hello');
    *   var Result := Client.Wait_Execute_Call('another_app', Param, 5000);
    *   // Result contains the response TMem64. }
  TC40_API_HUB_Client = class(TC40_Base_NoAuth_Client)
  private
    Last_Selected_Time: TTimeTick; // timestamp of last selection for load balancing
  protected
    FService_Info: TAPI_Service_Info_Pool__; // Cached service info received from the hub
    FHost_Running_Thread_Num: TAtomInt32; // Number of active threads handling incoming calls/notifications
    FWait_Reponse_Thread_Num: TAtomInt32; // Number of threads waiting for remote call responses
    FLast_Update_Thread_State_TimeTick: TTimeTick; // Last time thread state was sent to the service (throttling)
    FAPP: TAPI_APP; // The local application to be registered
    FAPI_APP_Is_Online: Boolean; // True after successful registration with the service

    procedure Do_DT_P2PVM_NoAuth_Custom_Client_TunnelLink(Sender: TDT_P2PVM_NoAuth_Custom_Client); override;

    { * cmd_update_service_api_info
      * Receives the service's broadcast of available applications and updates
      * the local FService_Info cache. }
    procedure cmd_update_service_api_info(Sender: TPeerIO; InData: PByte; DataSize: NativeInt);

    { * Do_Notify
      * Background thread worker for executing a local notification. Maps the
      * raw input buffer to a TMem64 and invokes Execute_Notify on the local APP.
      *
      * @Param thSender:   HPC thread context.
      * @Param ThInData:   Pointer to the raw notification data.
      * @Param ThDataSize: Size of the data. }
    procedure Do_Notify(thSender: THPC_CompleteBuffer; ThInData: PByte; ThDataSize: NativeInt);

    { * cmd_Notify
      * Handler for incoming 'Notify' commands received on the receive tunnel.
      * Offloads processing to a background thread via RunHPC_CompleteBufferM to
      * avoid blocking the main network loop.
      *
      * @Param Sender:    The peer I/O that sent this command.
      * @Param InData:    Raw buffer containing the notification payload.
      * @Param DataSize:  Size of the buffer. }
    procedure cmd_Notify(Sender: TPeerIO; InData: PByte; DataSize: NativeInt);

    { * cmd_Call
      * Handler for incoming 'Call' commands. Decodes the request, executes the
      * local API call synchronously (in the main thread), and writes the result
      * back to OutData.
      *
      * @Param Sender:    The peer I/O.
      * @Param InData:    DFE containing: appName and a TMem64 payload.
      * @Param OutData:   DFE that will contain the result TMem64. }
    procedure cmd_Call(Sender: TPeerIO; InData, OutData: TDFE);

    procedure Do_APP_Update(Sender: TAPI_APP);
  public
    constructor Create(PhysicsTunnel_: TC40_PhysicsTunnel; source_: TC40_Info; Param_: U_String); override;
    destructor Destroy; override;
    procedure SafeCheck; override;
    procedure Progress; override;
    procedure DoNetworkOnline; override; // Called when the client successfully connects.
    procedure DoNetworkOffline; override; // Called when the client disconnects.

    property Service_Info: TAPI_Service_Info_Pool__ read FService_Info; // Cached service info.

    { * Update_LocalThread_State_To_Service
      * Sends the current thread-count statistics (Host_Running_Thread_Num and
      * Wait_Reponse_Thread_Num) to the service. The service can use these for
      * load-aware routing. This is called automatically every second while
      * the client is online. }
    procedure Update_LocalThread_State_To_Service;

    { * Init_App_Info
      * Sends the current application registration to the service. This is
      * called automatically when the tunnel is linked and APP is set.
      * You may call it manually after changing APP.
      *
      * The registration contains: app name, description, process info, and a
      * list of all API names currently registered in the APP. }
    procedure Init_App_Info;

    { * Do_Init_App_Info_Result
      * Callback for the 'Init_APP_Info' command's response. Sets the online
      * flag to True, indicating the registration was successful.
      *
      * @Param Sender:   The peer I/O that sent the response.
      * @Param Result_:  DFE (ignored, only presence matters). }
    procedure Do_Init_App_Info_Result(Sender: TPeerIO; Result_: TDFE);

    property API_APP_Is_Online: Boolean read FAPI_APP_Is_Online; // True if registration is complete.

    { * Set_API_APP
      * Binds a local application to this client. The client will automatically
      * register the app's APIs with the service upon connection (or immediately
      * if already connected).
      *
      * @Param Value:  A TAPI_APP instance (must have a non-empty Name). }
    procedure Set_API_APP(const Value: TAPI_APP);
    property APP: TAPI_APP read FAPP write Set_API_APP;

    { * Send_Execute_Notify___
      * Internal method that sends a one-way notification to the specified
      * application. The notification is delivered asynchronously; no response
      * is expected. If the target application matches the local one (or another
      * local client), execution is performed locally without network overhead.
      *
      * @Param appName  Target application name (wildcards supported).
      * @Param Param    Binary payload (will be consumed; a clone is sent if
      *                 forwarded over the network).
      *
      * @Example:
      *   var Param := TMem64.Create;
      *   Param.WriteString('log message');
      *   Client.Send_Execute_Notify('logger', Param);
      *   // Param is freed by the method (it consumes it). }
    procedure Send_Execute_Notify___(const appName: TAPI_String; Param: TMem64);
    procedure Send_Execute_Notify(const appName: TAPI_String; Param: TMem64);

    { * Wait_Execute_Call___
      * Performs a synchronous call to the specified application and waits for
      * the result. If the target application is local, the call is executed
      * directly. Otherwise, a request is sent to the service and the call
      * blocks until the response arrives or the timeout expires.
      *
      * @Param appName   Target application name (wildcards supported).
      * @Param Param     Input binary data (will be consumed).
      * @Param TimeOut__ Timeout in milliseconds (0 = infinite).
      * @Returns         A new TMem64 containing the result, or nil if the call
      *                  timed out or failed.
      *
      * @Example:
      *   var Param := TMem64.Create;
      *   Param.WriteInt32(10);
      *   Param.WriteInt32(20);
      *   var Result := Client.Wait_Execute_Call('calc', Param, 5000);
      *   if Result <> nil then
      *     WriteLn('Result = ', Result.ReadInt32);
      *   DisposeObject(Result); }
    function Wait_Execute_Call___(const appName: TAPI_String; Param: TMem64; TimeOut__: TTimeTick): TMem64;
    function Wait_Execute_Call(const appName: TAPI_String; Param: TMem64; TimeOut__: TTimeTick): TMem64;
  end;

  TC40_API_HUB_Client_List = TBigList<TC40_API_HUB_Client>;

  { * TCall_Bridge__
    * Internal helper used by Wait_Execute_Call to capture the asynchronous
    * result from a complete-buffer stream response. Holds an output TMem64
    * and a flag indicating whether the call is still pending. }
  TCall_Bridge__ = class
  private
    Cli: TC40_API_HUB_Client; // Back reference to the client
    Output: TMem64; // Buffer for the result
    IsRunning: Boolean; // True while waiting for the response
    Error_: Boolean; // True if the response indicates an error
    procedure Do_Result(Sender: TPeerIO; Result_: TDFE); // Called when the response arrives
  public
    constructor Create;
    destructor Destroy; override;
  end;

function Find_Local_APP_Hub(appName: TAPI_String; Update_Selected_Time: Boolean): TC40_API_HUB_Client;
function Find_Remote_APP_Hub(appName: TAPI_String; Update_Selected_Time: Boolean): TC40_API_HUB_Client;
function Find_Local_API_Hub(appName, apiName: TAPI_String; Update_Selected_Time: Boolean): TC40_API_HUB_Client;
function Find_Remote_API_Hub(appName, apiName: TAPI_String; Update_Selected_Time: Boolean): TC40_API_HUB_Client;

implementation

{$I Z.System_ProcessID.inc} // Include file that provides MakeProcessName() function.

var
  Find_Hub_Safe_Critical: TCritical = nil; // Critical section protecting Find_*_Hub functions

function Do_Cmp_Last_Selected_Time(var L, R: TC40_API_HUB_Client): Integer;
{ * Comparison function for sorting TC40_API_HUB_Client by Last_Selected_Time.
  * Used to implement load balancing by selecting the least recently used client. }
begin
  Result := CompareUInt64(L.Last_Selected_Time, R.Last_Selected_Time);
end;

function Find_Local_APP_Hub(appName: TAPI_String; Update_Selected_Time: Boolean): TC40_API_HUB_Client;
{ * Finds a local application hub client (same process) that hosts the given
  * application name. Wildcards are supported.
  *
  * @Param appName: Target application name (wildcard allowed).
  * @Param Update_Selected_Time: If True, updates Last_Selected_Time of the found client.
  * @Returns: The matching TC40_API_HUB_Client, or nil if none found. }
var
  arry: TC40_Custom_Client_Array;
  i: Integer;
  Cli: TC40_API_HUB_Client;
  L: TC40_API_HUB_Client_List;
begin
  Result := nil;
  L := TC40_API_HUB_Client_List.Create;

  Find_Hub_Safe_Critical.Lock;
  try
    arry := C40_ClientPool.SearchClass(TC40_API_HUB_Client);
    for i := 0 to length(arry) - 1 do
      begin
        Cli := arry[i] as TC40_API_HUB_Client;
        if Cli.APP <> nil then
          begin
            if umlMultipleMatch(appName.Text, Cli.APP.Name.Text) then
                L.Add(Cli);
          end;
      end;
  finally
      Find_Hub_Safe_Critical.UnLock;
  end;

  L.Sort_C(Do_Cmp_Last_Selected_Time);
  if L.Num > 0 then
    begin
      Result := L.First^.Data;
      if Update_Selected_Time then
          Result.Last_Selected_Time := GetTimeTick();
    end;

  DisposeObject(L);
end;

function Find_Remote_APP_Hub(appName: TAPI_String; Update_Selected_Time: Boolean): TC40_API_HUB_Client;
{ * Finds a remote application hub client (different process) that hosts the given
  * application name. Wildcards are supported.
  *
  * @Param appName: Target application name (wildcard allowed).
  * @Param Update_Selected_Time: If True, updates Last_Selected_Time of the found client.
  * @Returns: The matching TC40_API_HUB_Client, or nil if none found. }
var
  arry: TC40_Custom_Client_Array;
  i: Integer;
  Cli: TC40_API_HUB_Client;
  L: TC40_API_HUB_Client_List;
begin
  Result := nil;
  L := TC40_API_HUB_Client_List.Create;

  Find_Hub_Safe_Critical.Lock;
  try
    arry := C40_ClientPool.SearchClass(TC40_API_HUB_Client, True);
    for i := 0 to length(arry) - 1 do
      begin
        Cli := arry[i] as TC40_API_HUB_Client;
        if Cli.Service_Info.Find_APP(appName) then
            L.Add(Cli);
      end;
  finally
      Find_Hub_Safe_Critical.UnLock;
  end;

  L.Sort_C(Do_Cmp_Last_Selected_Time);
  if L.Num > 0 then
    begin
      Result := L.First^.Data;
      if Update_Selected_Time then
          Result.Last_Selected_Time := GetTimeTick();
    end;

  DisposeObject(L);
end;

function Find_Local_API_Hub(appName, apiName: TAPI_String; Update_Selected_Time: Boolean): TC40_API_HUB_Client;
{ * Finds a local application hub client that hosts the given application name
  * AND exports the specified API. Wildcards are supported for appName.
  *
  * @Param appName: Target application name (wildcard allowed).
  * @Param apiName: Exact API name to look for.
  * @Param Update_Selected_Time: If True, updates Last_Selected_Time of the found client.
  * @Returns: The matching TC40_API_HUB_Client, or nil if none found. }
var
  arry: TC40_Custom_Client_Array;
  i: Integer;
  Cli: TC40_API_HUB_Client;
  L: TC40_API_HUB_Client_List;
begin
  Result := nil;
  L := TC40_API_HUB_Client_List.Create;

  Find_Hub_Safe_Critical.Lock;
  try
    arry := C40_ClientPool.SearchClass(TC40_API_HUB_Client);
    for i := 0 to length(arry) - 1 do
      begin
        Cli := arry[i] as TC40_API_HUB_Client;
        if Cli.APP <> nil then
          begin
            if umlMultipleMatch(appName.Text, Cli.APP.Name.Text) and Cli.APP.API.API_Pool.Exists_Key(apiName) then
                L.Add(Cli);
          end;
      end;
  finally
      Find_Hub_Safe_Critical.UnLock;
  end;

  L.Sort_C(Do_Cmp_Last_Selected_Time);
  if L.Num > 0 then
    begin
      Result := L.First^.Data;
      if Update_Selected_Time then
          Result.Last_Selected_Time := GetTimeTick();
    end;

  DisposeObject(L);
end;

function Find_Remote_API_Hub(appName, apiName: TAPI_String; Update_Selected_Time: Boolean): TC40_API_HUB_Client;
{ * Finds a remote application hub client that hosts the given application name
  * AND exports the specified API. Wildcards are supported for appName.
  *
  * @Param appName: Target application name (wildcard allowed).
  * @Param apiName: Exact API name to look for.
  * @Param Update_Selected_Time: If True, updates Last_Selected_Time of the found client.
  * @Returns: The matching TC40_API_HUB_Client, or nil if none found. }
var
  arry: TC40_Custom_Client_Array;
  i: Integer;
  Cli: TC40_API_HUB_Client;
  L: TC40_API_HUB_Client_List;
begin
  Result := nil;
  L := TC40_API_HUB_Client_List.Create;

  Find_Hub_Safe_Critical.Lock;
  try
    arry := C40_ClientPool.SearchClass(TC40_API_HUB_Client, True);
    for i := 0 to length(arry) - 1 do
      begin
        Cli := arry[i] as TC40_API_HUB_Client;
        if Cli.Service_Info.Find_API(appName, apiName) then
            L.Add(Cli);
      end;
  finally
      Find_Hub_Safe_Critical.UnLock;
  end;

  L.Sort_C(Do_Cmp_Last_Selected_Time);
  if L.Num > 0 then
    begin
      Result := L.First^.Data;
      if Update_Selected_Time then
          Result.Last_Selected_Time := GetTimeTick();
    end;

  DisposeObject(L);
end;

{ * TC40_API_HUB_Service_RecvTunnel_NoAuth }
constructor TC40_API_HUB_Service_RecvTunnel_NoAuth.Create(Owner_: TPeerIO);
{ * Initializes the API info hash list. }
begin
  inherited Create(Owner_);
  API_HUB_Service := nil;
  APP_Name := '';
  APP_Desc := '';
  APP_Process_Info := '';
  api_info_data := THashList.Create;
  Host_Running_Thread_Num := 0;
  Wait_Reponse_Thread_Num := 0;
  Is_Local := False;
  Last_Selected_Time := 0;
end;

destructor TC40_API_HUB_Service_RecvTunnel_NoAuth.Destroy;
{ * Frees the API info hash list. }
begin
  DisposeObject(api_info_data);
  inherited Destroy;
end;

{ * TAPI_Service_Info__ Implementation }
constructor TAPI_Service_Info__.Create;
begin
  inherited Create;
  APP_Name := '';
  APP_Desc := '';
  APP_Process_Info := '';
  api_info_data := THashList.Create;
  Host_Running_Thread_Num := 0;
  Wait_Reponse_Thread_Num := 0;
  Is_Local := False;
end;

destructor TAPI_Service_Info__.Destroy;
begin
  DisposeObject(api_info_data);
  inherited Destroy;
end;

procedure TAPI_Service_Info__.Assign(source: TC40_API_HUB_Service_RecvTunnel_NoAuth);
{ * Copies registration data from a receive-tunnel user object. }
begin
  APP_Name := source.APP_Name;
  APP_Desc := source.APP_Desc;
  APP_Process_Info := source.APP_Process_Info;
  api_info_data.Assign(source.api_info_data);
  Host_Running_Thread_Num := source.Host_Running_Thread_Num;
  Wait_Reponse_Thread_Num := source.Wait_Reponse_Thread_Num;
  Is_Local := source.Is_Local;
end;

procedure TAPI_Service_Info__.SaveToStream(stream: TCore_Stream);
{ * Serializes this service info to a stream using DFE encoding. }
var
  d: TDFE;
  pl: TPascalStringList;
begin
  d := TDFE.Create;
  d.WriteString(APP_Name);
  d.WriteString(APP_Desc);
  d.WriteString(APP_Process_Info);

  pl := TPascalStringList.Create;
  api_info_data.GetNameList(pl);
  d.WritePascalStrings(pl);
  DisposeObject(pl);

  d.WriteInteger(Host_Running_Thread_Num);
  d.WriteInteger(Wait_Reponse_Thread_Num);
  d.WriteBool(Is_Local);

  d.FastEncodeTo(stream);
  DisposeObject(d);
end;

procedure TAPI_Service_Info__.LoadFromStream(stream: TCore_Stream);
{ * Deserializes service info from a stream. }
var
  d: TDFE;
  pl: TPascalStringList;
  i: Integer;
begin
  d := TDFE.Create;
  d.DecodeFrom(stream, True);
  APP_Name := d.R.ReadString;
  APP_Desc := d.R.ReadString;
  APP_Process_Info := d.R.ReadString;

  pl := TPascalStringList.Create;
  d.R.ReadPascalStrings(pl);
  api_info_data.Clear;
  for i := 0 to pl.Count - 1 do
      api_info_data.Add(pl[i], nil, False);
  DisposeObject(pl);

  Host_Running_Thread_Num := d.R.ReadInteger;
  Wait_Reponse_Thread_Num := d.R.ReadInteger;
  Is_Local := d.R.ReadBool;

  DisposeObject(d);
end;

{ * TAPI_Service_Info_Pool__ Implementation }
constructor TAPI_Service_Info_Pool__.Create;
begin
  inherited Create(True);
end;

destructor TAPI_Service_Info_Pool__.Destroy;
begin
  inherited Destroy;
end;

procedure TAPI_Service_Info_Pool__.Build_Info_Form(Inst: TC40_API_HUB_Service_RecvTunnel_NoAuth);
{ * Builds a snapshot entry from a client's registration data.
  * Only adds the entry if the client has at least one registered API. }
var
  tmp: TAPI_Service_Info__;
begin
  if Inst.api_info_data.Count > 0 then
    begin
      tmp := TAPI_Service_Info__.Create;
      tmp.Assign(Inst);
      Add(tmp);
    end;
end;

procedure TAPI_Service_Info_Pool__.SaveToStream(d: TDFE);
{ * Saves the entire pool to a DFE stream. }
var
  m64: TMS64;
begin
  if Num <= 0 then exit;

  m64 := TMS64.CustomCreate($FFFF);
  with repeat_ do
    repeat
      queue^.Data.SaveToStream(m64);
      d.WriteStream(m64);
      m64.Clear;
    until not Next;

  DisposeObject(m64);
end;

procedure TAPI_Service_Info_Pool__.LoadFromStream(d: TDFE);
{ * Loads the pool from a DFE stream. }
var
  m64: TMS64;
  Inst: TAPI_Service_Info__;
begin
  Clear;
  m64 := TMS64.CustomCreate($FFFF);

  while d.R.NotEnd do
    begin
      d.R.ReadMS64_As_Mapping(m64);
      m64.Position := 0;
      Inst := TAPI_Service_Info__.Create;
      Inst.LoadFromStream(m64);
      Add(Inst);
      m64.Clear;
    end;

  DisposeObject(m64);
end;

function TAPI_Service_Info_Pool__.Find_API(appName, apiName: TAPI_String): Boolean;
{ * Checks if any entry has the given appName and exports the given API. }
begin
  Result := False;
  if Num <= 0 then exit;
  with repeat_ do
    repeat
      if appName.Same(queue^.Data.APP_Name) and queue^.Data.api_info_data.Exists(apiName) then
        begin
          Result := True;
          exit;
        end;
    until not Next;
end;

function TAPI_Service_Info_Pool__.Find_APP(appName: TAPI_String): Boolean;
{ * Checks if any entry has the given appName (regardless of APIs). }
begin
  Result := False;
  if Num <= 0 then exit;
  with repeat_ do
    repeat
      if appName.Same(queue^.Data.APP_Name) then
        begin
          Result := True;
          exit;
        end;
    until not Next;
end;

{ * TC40_API_HUB_Service_SendTunnel_NoAuth }
constructor TC40_API_HUB_Service_SendTunnel_NoAuth.Create(Owner_: TPeerIO);
begin
  inherited Create(Owner_);
  API_HUB_Service := nil;
end;

destructor TC40_API_HUB_Service_SendTunnel_NoAuth.Destroy;
begin
  inherited Destroy;
end;

{ TC40_API_HUB_Service }

procedure TC40_API_HUB_Service.Do_Delay_Broadcast_API_Info;
{ * Schedules a broadcast of API info after a 2-second delay.
  * This coalesces multiple registration changes into a single broadcast. }
begin
  FDelay_Broadcast_API_Info_Time := GetTimeTick() + 2000;
  FNeed_Broadcast_API_Info := True;
end;

procedure TC40_API_HUB_Service.DoLinkSuccess_Event(Sender: TDTService_NoAuth;
  UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth);
{ * Sets back-references in the receive and send tunnel user objects. }
var
  user_io: TC40_API_HUB_Service_RecvTunnel_NoAuth;
begin
  inherited DoLinkSuccess_Event(Sender, UserDefineIO);
  user_io := UserDefineIO as TC40_API_HUB_Service_RecvTunnel_NoAuth;
  user_io.API_HUB_Service := Self;
  (user_io.SendTunnel as TC40_API_HUB_Service_SendTunnel_NoAuth).API_HUB_Service := Self;
end;

procedure TC40_API_HUB_Service.DoUserOut_Event(Sender: TDTService_NoAuth;
  UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth);
{ * Overridden; no extra logic needed because the user object will be freed
  * automatically when the connection drops. }
begin
  inherited DoUserOut_Event(Sender, UserDefineIO);
end;

procedure TC40_API_HUB_Service.cmd_Init_APP_Info(Sender: TCommandCompleteBuffer_NoWait_Bridge; InData, OutData: TDFE);
{ * Registers an application from a client. Stores the registration data
  * in the receive-tunnel user object for future routing.
  * The registration contains: app name, description, process info,
  * a list of API names, and a local flag. }
var
  user_io: TC40_API_HUB_Service_RecvTunnel_NoAuth;
  L: TPascalStringList;
  i: Integer;
begin
  user_io := DTNoAuthService.GetUserDefineRecvTunnel(Sender.R_IO) as TC40_API_HUB_Service_RecvTunnel_NoAuth;
  if user_io = nil then
      exit;

  user_io.APP_Name := InData.R.ReadString;
  user_io.APP_Desc := InData.R.ReadString;
  user_io.APP_Process_Info := InData.R.ReadString;

  user_io.api_info_data.Clear;
  L := TPascalStringList.Create;
  InData.R.ReadPascalStrings(L);
  for i := 0 to L.Count - 1 do
      user_io.api_info_data.Add(L[i], nil, False);
  DisposeObject(L);

  user_io.Is_Local := InData.R.ReadBool;

  Do_Delay_Broadcast_API_Info();
end;

procedure TC40_API_HUB_Service.cmd_No_App_Info(Sender: TPeerIO; InData: SystemString);
{ * Handles a client that has no application to register (or an empty app).
  * Clears the registration data and schedules a broadcast. }
var
  user_io: TC40_API_HUB_Service_RecvTunnel_NoAuth;
begin
  user_io := DTNoAuthService.GetUserDefineRecvTunnel(Sender) as TC40_API_HUB_Service_RecvTunnel_NoAuth;
  if user_io = nil then
      exit;

  user_io.APP_Name := '';
  user_io.APP_Desc := '';
  user_io.APP_Process_Info := InData;
  user_io.api_info_data.Clear;
  user_io.Host_Running_Thread_Num := 0;
  user_io.Wait_Reponse_Thread_Num := 0;
  user_io.Is_Local := False;

  Do_Delay_Broadcast_API_Info();
end;

procedure TC40_API_HUB_Service.cmd_Thread_State(Sender: TPeerIO; InData: TDFE);
{ * Receives runtime thread-count updates from a client and stores them in the
  * user object for load-aware routing. }
var
  user_io: TC40_API_HUB_Service_RecvTunnel_NoAuth;
begin
  user_io := DTNoAuthService.GetUserDefineRecvTunnel(Sender) as TC40_API_HUB_Service_RecvTunnel_NoAuth;
  if user_io = nil then
      exit;

  user_io.Host_Running_Thread_Num := InData.R.ReadInteger;
  user_io.Wait_Reponse_Thread_Num := InData.R.ReadInteger;
end;

procedure TC40_API_HUB_Service.Do_Run_Notify_Th(thSender: THPC_StreamNotify; ThInData: TDFE);
{ * Background thread worker for executing a local notification.
  * Uses the TAPI_APP stored in thSender.UserObject.
  * Increments/decrements Host_Running_Thread_Num around the call. }
var
  tmp_cli__: TC40_API_HUB_Client;
  appName: TAPI_String;
  Param: TMem64;
  apiName: TAPI_String;
begin
  tmp_cli__ := thSender.UserObject as TC40_API_HUB_Client;

  appName := ThInData.R.ReadString;
  Param := TMem64.Create;
  ThInData.R.ReadMem64_As_Mapping(Param);
  apiName := TMemory_Param_Tool.Get_apiName(Param);

  tmp_cli__.FHost_Running_Thread_Num.UnLock(tmp_cli__.FHost_Running_Thread_Num.LockP^ + 1);
  try
      tmp_cli__.APP.API.Execute_Notify(Param);
  finally
      tmp_cli__.FHost_Running_Thread_Num.UnLock(tmp_cli__.FHost_Running_Thread_Num.LockP^ - 1);
  end;

  DisposeObject(Param);
end;

procedure TC40_API_HUB_Service.cmd_Notify(Sender: TPeerIO; InData: TDFE);
{ * Routes an incoming notification to the appropriate destination.
  * 1) Tries local execution (same process) via Find_Local_API_Hub.
  * 2) If not found, forwards to other service instances (IPC first, then remote).
  * 3) Logs an error if no matching destination is found. }
var
  user_io: TC40_API_HUB_Service_RecvTunnel_NoAuth;
  appName: TAPI_String;
  Param: TMem64;
  apiName: TAPI_String;
  arry: TC40_Custom_Service_Array;
  tmp_cli__: TC40_API_HUB_Client;

  function Search_API_And_Send(): Boolean;
  var
    i: Integer;
    serv: TC40_API_HUB_Service;
    IO__: TC40_API_HUB_Service_RecvTunnel_NoAuth;
  begin
    Result := False;
    if length(arry) > 0 then
      begin
        for i := 0 to length(arry) - 1 do
          begin
            serv := arry[i] as TC40_API_HUB_Service;
            IO__ := serv.Find_API(appName, apiName);
            if IO__ <> nil then
              begin
                IO__.SendTunnel.Owner.SendCompleteBuffer('Notify', Param.NewClone, True);
                Result := True;
                exit;
              end;
          end;
      end;
  end;

begin
  user_io := DTNoAuthService.GetUserDefineRecvTunnel(Sender) as TC40_API_HUB_Service_RecvTunnel_NoAuth;

  appName := InData.R.ReadString;
  Param := TMem64.Create;
  InData.R.ReadMem64_As_Mapping(Param);
  apiName := TMemory_Param_Tool.Get_apiName(Param);

  tmp_cli__ := Find_Local_API_Hub(appName, apiName, True);
  if tmp_cli__ <> nil then
    begin
      InData.R.Index := 0;
      DisposeObject(Param);
      RunHPC_StreamNotifyM(Sender, nil, tmp_cli__, InData, Do_Run_Notify_Th);
      exit;
    end;

  try
    arry := Z.Net.C4.C40_ServicePool.GetFromClass(TC40_API_HUB_Service, True);
    if Search_API_And_Send then
        exit;

    arry := Z.Net.C4.C40_ServicePool.GetFromClass(TC40_API_HUB_Service, False);
    if Search_API_And_Send then
        exit;

    DoStatus('no found app("%s") api("%s")', [appName.Text, apiName.Text]);
  finally
    DisposeObject(Param);
    SetLength(arry, 0);
  end;
end;

procedure TC40_API_HUB_Service.Do_Run_Call_Th(thSender: THPC_CompleteBuffer_Stream; ThInData, ThOutData: TDFE);
{ * Background thread worker for executing a local synchronous call.
  * Uses the TAPI_APP stored in thSender.UserObject.
  * Increments/decrements Host_Running_Thread_Num around the call. }
var
  tmp_cli__: TC40_API_HUB_Client;
  appName: TAPI_String;
  Param, Output: TMem64;
  apiName: TAPI_String;
begin
  tmp_cli__ := thSender.UserObject as TC40_API_HUB_Client;
  appName := ThInData.R.ReadString;
  Param := TMem64.Create;
  ThInData.R.ReadMem64_As_Mapping(Param);
  apiName := TMemory_Param_Tool.Get_apiName(Param);

  tmp_cli__.FHost_Running_Thread_Num.UnLock(tmp_cli__.FHost_Running_Thread_Num.LockP^ + 1);
  try
      Output := tmp_cli__.APP.API.Execute_Call(Param);
  finally
      tmp_cli__.FHost_Running_Thread_Num.UnLock(tmp_cli__.FHost_Running_Thread_Num.LockP^ - 1);
  end;
  DisposeObject(Param);

  ThOutData.WriteMem64(Output);
  DisposeObject(Output);
end;

procedure TC40_API_HUB_Service.cmd_Call(Sender: TCommandCompleteBuffer_NoWait_Bridge; InData, OutData: TDFE);
{ * Routes an incoming synchronous call to the appropriate destination.
  * 1) Tries local execution (same process) via Find_Local_API_Hub.
  * 2) If not found, forwards to other service instances (IPC first, then remote).
  * 3) Logs an error if no matching destination is found. }
var
  appName: TAPI_String;
  Param, Output: TMem64;
  apiName: TAPI_String;
  arry: TC40_Custom_Service_Array;
  tmp_cli__: TC40_API_HUB_Client;

  function Search_API_And_Send(): Boolean;
  var
    i: Integer;
    serv: TC40_API_HUB_Service;
    IO__: TC40_API_HUB_Service_RecvTunnel_NoAuth;
  begin
    Result := False;
    if length(arry) > 0 then
      begin
        for i := 0 to length(arry) - 1 do
          begin
            serv := arry[i] as TC40_API_HUB_Service;
            IO__ := serv.Find_API(appName, apiName);
            if IO__ <> nil then
              begin
                IO__.SendTunnel.Owner.SendCompleteBuffer_NoWait_StreamM('Call', InData,
                  TCompleteBuffer_Stream_Event_Bridge.Create(Sender, True).DoStreamEvent);
                Result := True;
                exit;
              end;
          end;
      end;
  end;

begin
  appName := InData.R.ReadString;
  Param := TMem64.Create;
  InData.R.ReadMem64_As_Mapping(Param);
  apiName := TMemory_Param_Tool.Get_apiName(Param);
  InData.R.Index := 0;

  tmp_cli__ := Find_Local_API_Hub(appName, apiName, True);
  if tmp_cli__ <> nil then
    begin
      DisposeObject(Param);
      RunHPC_CompleteBuffer_StreamM(Sender, nil, tmp_cli__, InData, OutData, Do_Run_Call_Th);
      exit;
    end;

  try
    arry := Z.Net.C4.C40_ServicePool.GetFromClass(TC40_API_HUB_Service, True);
    if Search_API_And_Send then
        exit;

    arry := Z.Net.C4.C40_ServicePool.GetFromClass(TC40_API_HUB_Service, False);
    if Search_API_And_Send then
        exit;

    DoStatus('no found app("%s") api("%s")', [appName.Text, apiName.Text]);
  finally
    DisposeObject(Param);
    SetLength(arry, 0);
  end;
end;

constructor TC40_API_HUB_Service.Create(PhysicsService_: TC40_PhysicsService; ServiceTyp, Param_: U_String);
{ * Constructor: sets up the service with custom user-defined classes,
  * configures buffer sizes, and registers the command handlers.
  * Temporarily disables per-service directories to avoid clutter. }
var
  bak_: Boolean;
begin
  bak_ := C40_EnablePerServiceDirectory;
  C40_EnablePerServiceDirectory := False;
  inherited Create(PhysicsService_, ServiceTyp, Param_);
  C40_EnablePerServiceDirectory := bak_;

  FDelay_Broadcast_API_Info_Time := 0;
  FNeed_Broadcast_API_Info := False;

  ServiceInfo.OnlyInstance := False;

  DTNoAuth.RecvTunnel.UserDefineClass := TC40_API_HUB_Service_RecvTunnel_NoAuth;
  DTNoAuth.SendTunnel.UserDefineClass := TC40_API_HUB_Service_SendTunnel_NoAuth;

  DTNoAuth.RecvTunnel.MaxCompleteBufferSize := EStrToInt64(ParamList.GetDefaultValue('MaxBuffer', '500*1024*1024'), 500 * 1024 * 1024);
  DTNoAuth.RecvTunnel.CompleteBufferCompressed := False;

  DTNoAuth.RecvTunnel.RegisterCompleteBuffer_NoWait_Bridge_Stream('Init_APP_Info').OnExecute := cmd_Init_APP_Info;
  DTNoAuth.RecvTunnel.RegisterConsoleNotify('No_App_Info').OnExecute := cmd_No_App_Info;
  DTNoAuth.RecvTunnel.RegisterCompleteBuffer_StreamNotify('Thread_State').OnExecute := cmd_Thread_State;
  DTNoAuth.RecvTunnel.RegisterCompleteBuffer_StreamNotify('Notify').OnExecute := cmd_Notify;
  DTNoAuth.RecvTunnel.RegisterCompleteBuffer_NoWait_Bridge_Stream('Call').OnExecute := cmd_Call;

  DTNoAuth.RecvTunnel.PrintParams.Add('update_service_api_info', False, True);
  DTNoAuth.RecvTunnel.PrintParams.Add('Init_APP_Info', False, True);
  DTNoAuth.RecvTunnel.PrintParams.Add('No_App_Info', False, True);
  DTNoAuth.RecvTunnel.PrintParams.Add('Thread_State', False, True);
  DTNoAuth.RecvTunnel.PrintParams.Add('Notify', False, True);
  DTNoAuth.RecvTunnel.PrintParams.Add('Call', False, True);

  DTNoAuth.SendTunnel.PrintParams.Add('update_service_api_info', False, True);
  DTNoAuth.SendTunnel.PrintParams.Add('Init_APP_Info', False, True);
  DTNoAuth.SendTunnel.PrintParams.Add('No_App_Info', False, True);
  DTNoAuth.SendTunnel.PrintParams.Add('Thread_State', False, True);
  DTNoAuth.SendTunnel.PrintParams.Add('Notify', False, True);
  DTNoAuth.SendTunnel.PrintParams.Add('Call', False, True);
end;

destructor TC40_API_HUB_Service.Destroy;
begin
  inherited Destroy;
end;

procedure TC40_API_HUB_Service.SafeCheck;
begin
  inherited SafeCheck;
end;

procedure TC40_API_HUB_Service.Progress;
{ * Main progress method. Drives the network and triggers broadcast
  * when the scheduled broadcast time is reached. }
begin
  inherited Progress;
  if FNeed_Broadcast_API_Info then
    begin
      if GetTimeTick() > FDelay_Broadcast_API_Info_Time then
        begin
          Broadcast_API_Info;
          FNeed_Broadcast_API_Info := False;
        end;
    end;
end;

procedure TC40_API_HUB_Service.Broadcast_API_Info();
{ * Builds a snapshot of all registered applications and sends it to every
  * connected client using the 'update_service_api_info' command. }
var
  info_pool: TAPI_Service_Info_Pool__;
  arry: TIO_Array;
  ID_: Cardinal;
  IO_: TPeerIO;
  tmp: TC40_API_HUB_Service_RecvTunnel_NoAuth;
  d: TDFE;
  final_data: TMS64;
begin
  info_pool := TAPI_Service_Info_Pool__.Create;
  DTNoAuth.RecvTunnel.GetIO_Array(arry);
  for ID_ in arry do
    begin
      IO_ := DTNoAuth.RecvTunnel.PeerIO[ID_];
      if IO_ <> nil then
        begin
          tmp := IO_.Define as TC40_API_HUB_Service_RecvTunnel_NoAuth;
          if tmp.LinkOk then
              info_pool.Build_Info_Form(tmp);
        end;
    end;

  d := TDFE.Create;
  info_pool.SaveToStream(d);
  DisposeObject(info_pool);
  final_data := TMS64.CustomCreate(1024 * 1024);
  d.FastEncodeTo(final_data);
  DisposeObject(d);
  final_data.Position := 0;

  for ID_ in arry do
    begin
      IO_ := DTNoAuth.RecvTunnel.PeerIO[ID_];
      if IO_ <> nil then
        begin
          tmp := IO_.Define as TC40_API_HUB_Service_RecvTunnel_NoAuth;
          if tmp.LinkOk then
            begin
              tmp.SendTunnel.Owner.SendCompleteBuffer('update_service_api_info', final_data.NewClone, True);
            end;
        end;
    end;

  DisposeObject(final_data);
end;

function TC40_API_HUB_Service.Do_CmpIOThNum(var L, R: TC40_API_HUB_Service_RecvTunnel_NoAuth): Integer;
{ * Comparison function for sorting connected clients by Last_Selected_Time.
  * Used to implement load balancing by selecting the least recently used client. }
begin
  Result := CompareUInt64(L.Last_Selected_Time, R.Last_Selected_Time);
end;

function TC40_API_HUB_Service.Find_API(appName, apiName: TAPI_String): TC40_API_HUB_Service_RecvTunnel_NoAuth;
{ * Scans all connected clients and returns the receive-tunnel user object of
  * the first one that matches the given application name (wildcard) and
  * exposes the specified API. If multiple clients match, the one with the
  * lowest Last_Selected_Time is returned (load balancing). }
var
  arry: TIO_Array;
  ID_: Cardinal;
  IO_: TPeerIO;
  tmp: TC40_API_HUB_Service_RecvTunnel_NoAuth;
  L: TC40_API_HUB_Service_RecvTunnel_NoAuth_List;
begin
  Result := nil;
  DTNoAuth.RecvTunnel.GetIO_Array(arry);
  L := TC40_API_HUB_Service_RecvTunnel_NoAuth_List.Create;
  for ID_ in arry do
    begin
      IO_ := DTNoAuth.RecvTunnel.PeerIO[ID_];
      if IO_ <> nil then
        begin
          tmp := IO_.Define as TC40_API_HUB_Service_RecvTunnel_NoAuth;
          if umlMultipleMatch(appName.Text, tmp.APP_Name.Text) and tmp.api_info_data.Exists(apiName) then
              L.Add(tmp);
        end;
    end;
  if L.Num > 1 then
      L.Sort_M(Do_CmpIOThNum);
  if L.Num > 0 then
    begin
      Result := L.First^.Data;
      Result.Last_Selected_Time := GetTimeTick();
    end;
  DisposeObject(L);
end;

{ TC40_API_HUB_Client }

procedure TC40_API_HUB_Client.Do_DT_P2PVM_NoAuth_Custom_Client_TunnelLink(Sender: TDT_P2PVM_NoAuth_Custom_Client);
{ * Called when the double-tunnel link is established. If an APP is set,
  * automatically registers it with the service. }
begin
  inherited Do_DT_P2PVM_NoAuth_Custom_Client_TunnelLink(Sender);
  if APP <> nil then
      Init_App_Info;
end;

procedure TC40_API_HUB_Client.cmd_update_service_api_info(Sender: TPeerIO; InData: PByte; DataSize: NativeInt);
{ * Receives service info broadcast and updates the local cache.
  * The data is DFE-encoded and contains a snapshot of all registered apps. }
var
  m64: TMS64;
  d: TDFE;
begin
  m64 := TMS64.Create;
  m64.Mapping(InData, DataSize);
  d := TDFE.Create;
  d.DecodeFrom(m64, True);
  DisposeObject(m64);
  FService_Info.LoadFromStream(d);
  DisposeObject(d);
end;

procedure TC40_API_HUB_Client.Do_Notify(thSender: THPC_CompleteBuffer; ThInData: PByte; ThDataSize: NativeInt);
{ * Background thread worker for executing a local notification.
  * Maps the raw input buffer to a TMem64 and invokes Execute_Notify on the local APP. }
var
  m64: TMem64;
begin
  if FAPP = nil then
      exit;

  FHost_Running_Thread_Num.UnLock(FHost_Running_Thread_Num.LockP^ + 1);
  try
    m64 := TMem64.Create;
    m64.Mapping(ThInData, ThDataSize);
    FAPP.API.Execute_Notify(m64);
    DisposeObject(m64);
  finally
      FHost_Running_Thread_Num.UnLock(FHost_Running_Thread_Num.LockP^ - 1);
  end;
end;

procedure TC40_API_HUB_Client.cmd_Notify(Sender: TPeerIO; InData: PByte; DataSize: NativeInt);
{ * Handles incoming 'Notify' commands by offloading processing to a background
  * thread using RunHPC_CompleteBufferM. }
begin
  if FAPP = nil then
      exit;
  RunHPC_CompleteBufferM(Sender, nil, nil, InData, DataSize, Do_Notify);
end;

procedure TC40_API_HUB_Client.cmd_Call(Sender: TPeerIO; InData, OutData: TDFE);
{ * Handles incoming 'Call' commands synchronously. Decodes the request,
  * executes the API call locally, and writes the result back.
  * This runs in the main thread (not background). }
var
  appName: TAPI_String;
  m64, Output: TMem64;
begin
  if FAPP = nil then
      exit;

  FHost_Running_Thread_Num.UnLock(FHost_Running_Thread_Num.LockP^ + 1);
  try
    appName := InData.R.ReadString;
    m64 := TMem64.Create;
    InData.R.ReadMem64_As_Mapping(m64);
    Output := FAPP.API.Execute_Call(m64);
    DisposeObject(m64);
    OutData.WriteMem64(Output);
    DisposeObject(Output);
  finally
      FHost_Running_Thread_Num.UnLock(FHost_Running_Thread_Num.LockP^ - 1);
  end;
end;

procedure TC40_API_HUB_Client.Do_APP_Update(Sender: TAPI_APP);
{ * Called when the APP's API list changes. Re-registers the app with the service. }
begin
  Init_App_Info;
end;

constructor TC40_API_HUB_Client.Create(PhysicsTunnel_: TC40_PhysicsTunnel; source_: TC40_Info; Param_: U_String);
{ * Constructor: initialises the client and registers command handlers for
  * incoming calls and notifications. }
begin
  inherited Create(PhysicsTunnel_, source_, Param_);
  FService_Info := TAPI_Service_Info_Pool__.Create;
  FHost_Running_Thread_Num := TAtomInt32.Create(0);
  FWait_Reponse_Thread_Num := TAtomInt32.Create(0);
  FLast_Update_Thread_State_TimeTick := 0;

  FAPP := nil;
  FAPI_APP_Is_Online := False;

  Last_Selected_Time := 0;

  DTNoAuth.RecvTunnel.RegisterCompleteBuffer('update_service_api_info').OnExecute := cmd_update_service_api_info;
  DTNoAuth.RecvTunnel.RegisterCompleteBuffer('Notify').OnExecute := cmd_Notify;
  DTNoAuth.RecvTunnel.RegisterCompleteBuffer_NoWait_Stream_Thread('Call').OnExecute := cmd_Call;

  DTNoAuth.RecvTunnel.PrintParams.Add('update_service_api_info', False, True);
  DTNoAuth.RecvTunnel.PrintParams.Add('Init_APP_Info', False, True);
  DTNoAuth.RecvTunnel.PrintParams.Add('No_App_Info', False, True);
  DTNoAuth.RecvTunnel.PrintParams.Add('Thread_State', False, True);
  DTNoAuth.RecvTunnel.PrintParams.Add('Notify', False, True);
  DTNoAuth.RecvTunnel.PrintParams.Add('Call', False, True);

  DTNoAuth.SendTunnel.PrintParams.Add('update_service_api_info', False, True);
  DTNoAuth.SendTunnel.PrintParams.Add('Init_APP_Info', False, True);
  DTNoAuth.SendTunnel.PrintParams.Add('No_App_Info', False, True);
  DTNoAuth.SendTunnel.PrintParams.Add('Thread_State', False, True);
  DTNoAuth.SendTunnel.PrintParams.Add('Notify', False, True);
  DTNoAuth.SendTunnel.PrintParams.Add('Call', False, True);
end;

destructor TC40_API_HUB_Client.Destroy;
{ * Destructor: waits for any background threads to finish (with a 2-second
  * timeout) before freeing the thread counters. }
var
  tk: TTimeTick;
begin
  if FAPP <> nil then
      FAPP.Remove_Update(Self);
  tk := GetTimeTick() + 2000;
  while (FHost_Running_Thread_Num.V + FWait_Reponse_Thread_Num.V > 0) and (GetTimeTick() < tk) do
      TCompute.Sleep(100);
  DisposeObjectAndNil(FHost_Running_Thread_Num);
  DisposeObjectAndNil(FWait_Reponse_Thread_Num);
  DisposeObjectAndNil(FService_Info);
  inherited Destroy;
end;

procedure TC40_API_HUB_Client.SafeCheck;
begin
  inherited SafeCheck;
end;

procedure TC40_API_HUB_Client.Progress;
{ * Main progress method. If the client is online, sends thread-state updates
  * to the service every second (throttled to 100ms check interval). }
var
  tk: TTimeTick;
begin
  if API_APP_Is_Online then
    begin
      tk := GetTimeTick();
      if tk - FLast_Update_Thread_State_TimeTick > 100 then
        begin
          if not DTNoAuth.SendTunnel.IOBusy then
              Update_LocalThread_State_To_Service;
          FLast_Update_Thread_State_TimeTick := tk;
        end;
    end;
  inherited Progress;
end;

procedure TC40_API_HUB_Client.DoNetworkOnline;
begin
  inherited;
end;

procedure TC40_API_HUB_Client.DoNetworkOffline;
{ * Called when the client disconnects; resets the online flag. }
begin
  inherited;
  FAPI_APP_Is_Online := False;
end;

procedure TC40_API_HUB_Client.Update_LocalThread_State_To_Service;
{ * Sends the current thread-count statistics to the service using the
  * 'Thread_State' command. This allows the service to perform load-aware routing. }
begin
  if not API_APP_Is_Online then
      exit;
  DTNoAuth.SendTunnel.SendCompleteBuffer_StreamNotify('Thread_State',
    TDFE.Create.WriteInteger(FHost_Running_Thread_Num.V).WriteInteger(FWait_Reponse_Thread_Num.V).DelayFree);
end;

procedure TC40_API_HUB_Client.Do_Init_App_Info_Result(Sender: TPeerIO; Result_: TDFE);
{ * Callback for the 'Init_APP_Info' command's response. Sets the online flag
  * to True, indicating the registration was successful, and subscribes to APP updates. }
begin
  FAPI_APP_Is_Online := True;
  FAPP.Subscribe_Update(Self, Do_APP_Update);
end;

procedure TC40_API_HUB_Client.Init_App_Info;
{ * Builds a list of API names from the current TAPI_APP and sends the
  * registration to the service using the 'Init_APP_Info' command.
  * If APP is nil or has no name, sends a 'No_App_Info' notification instead. }
var
  api_info_data: TPascalStringList;
  R: TAPI_Info_Pool.TRepeat___;
begin
  if (APP = nil) or (APP.Name.TrimChar(#32#9) = '') then
    begin
      DTNoAuth.SendTunnel.SendConsoleNotifyCmd('No_App_Info', MakeProcessName());
      exit;
    end;

  api_info_data := TPascalStringList.Create;
  if APP.API.API_Pool.Num > 0 then
    begin
      R := APP.API.API_Pool.Queue_Pool.repeat_;
      repeat
          api_info_data.Add(R.queue^.Data.Data.Primary);
      until not R.Next;
    end;

  DTNoAuth.SendTunnel.SendCompleteBuffer_NoWait_StreamM('Init_APP_Info',
    TDFE.Create
      .WriteString(APP.Name.Text)
      .WriteString(APP.Desc.Text)
      .WriteString(MakeProcessName())
      .WritePascalStrings(api_info_data)
      .WriteBool(IsLocal())
      .DelayFree,
    Do_Init_App_Info_Result);

  DisposeObject(api_info_data);
end;

procedure TC40_API_HUB_Client.Set_API_APP(const Value: TAPI_APP);
{ * Binds a new TAPI_APP to the client. If the client is already connected,
  * immediately registers the new app with the service. }
begin
  if FAPP <> nil then
      FAPP.Remove_Update(Self);
  FAPP := Value;
  if DTNoAuth.LinkOk then
      Init_App_Info;
end;

procedure TC40_API_HUB_Client.Send_Execute_Notify___(const appName: TAPI_String; Param: TMem64);
{ * Internal method that sends a notification by forwarding to the service.
  * The payload is wrapped in a DFE and sent via the send tunnel.
  * If the payload is large (>100KB), sends a NULL packet to flush the buffer. }
begin
  DTNoAuth.SendTunnel.SendCompleteBuffer_StreamNotify('Notify',
    TDFE.Create
      .WriteString(appName)
      .WriteMem64(Param)
      .DelayFree
    );
  if Param.Size > 100 * 1024 then
      DTNoAuth.SendTunnel.SendNULL;
end;

procedure TC40_API_HUB_Client.Send_Execute_Notify(const appName: TAPI_String; Param: TMem64);
{ * Sends a notification to the target application. Performs local execution
  * if the target matches a local client; otherwise forwards to the service. }
var
  apiName: TAPI_String;
  tmp_cli__: TC40_API_HUB_Client;
begin
  apiName := TMemory_Param_Tool.Get_apiName(Param);
  tmp_cli__ := Find_Local_API_Hub(appName, apiName, True);
  if tmp_cli__ <> nil then
    begin
      tmp_cli__.FHost_Running_Thread_Num.UnLock(tmp_cli__.FHost_Running_Thread_Num.LockP^ + 1);
      try
          tmp_cli__.APP.API.Execute_Notify(Param);
      finally
          tmp_cli__.FHost_Running_Thread_Num.UnLock(tmp_cli__.FHost_Running_Thread_Num.LockP^ - 1);
      end;
      exit;
    end;

  tmp_cli__ := Find_Remote_API_Hub(appName, apiName, True);
  if tmp_cli__ <> nil then
      tmp_cli__.Send_Execute_Notify___(appName, Param)
  else
      Send_Execute_Notify___(appName, Param);
end;

function TC40_API_HUB_Client.Wait_Execute_Call___(const appName: TAPI_String; Param: TMem64; TimeOut__: TTimeTick): TMem64;
{ * Internal method that performs a synchronous call by forwarding to the service.
  * Blocks until the response arrives or the timeout expires.
  * Uses TCall_Bridge__ to capture the asynchronous result. }
var
  apiName: TAPI_String;
  tmp: TCall_Bridge__;
  tk: TTimeTick;
begin
  Result := nil;
  apiName := TMemory_Param_Tool.Get_apiName(Param);

  FWait_Reponse_Thread_Num.UnLock(FWait_Reponse_Thread_Num.LockP^ + 1);
  tmp := TCall_Bridge__.Create;
  tmp.Cli := Self;
  tmp.IsRunning := True;

  DTNoAuth.SendTunnel.SendCompleteBuffer_NoWait_StreamM('Call',
    TDFE.Create
      .WriteString(appName)
      .WriteMem64(Param)
      .DelayFree,
    tmp.Do_Result);

  if Param.Size > 100 * 1024 then
      DTNoAuth.SendTunnel.SendNULL;

  tk := GetTimeTick + TimeOut__;
  while tmp.IsRunning do
    begin
      TCompute.Sleep(10);
      if (TimeOut__ > 0) and (GetTimeTick > tk) then
        begin
          FWait_Reponse_Thread_Num.UnLock(FWait_Reponse_Thread_Num.LockP^ - 1);
          DoStatus('%s -> %s call timeout', [appName.Text, apiName.Text]);
          exit;
        end;
    end;

  Result := tmp.Output.Swap_To_New_Instance;
  FWait_Reponse_Thread_Num.UnLock(FWait_Reponse_Thread_Num.LockP^ - 1);
  DisposeObject(tmp);
end;

function TC40_API_HUB_Client.Wait_Execute_Call(const appName: TAPI_String; Param: TMem64; TimeOut__: TTimeTick): TMem64;
{ * Performs a synchronous call to the target application. First tries local
  * execution (same process), then remote execution via the service. }
var
  apiName: TAPI_String;
  tmp_cli__: TC40_API_HUB_Client;
begin
  Result := nil;

  apiName := TMemory_Param_Tool.Get_apiName(Param);
  tmp_cli__ := Find_Local_API_Hub(appName, apiName, True);
  if tmp_cli__ <> nil then
    begin
      tmp_cli__.FHost_Running_Thread_Num.UnLock(tmp_cli__.FHost_Running_Thread_Num.LockP^ + 1);
      try
          Result := tmp_cli__.APP.API.Execute_Call(Param);
      finally
          tmp_cli__.FHost_Running_Thread_Num.UnLock(tmp_cli__.FHost_Running_Thread_Num.LockP^ - 1);
      end;
      exit;
    end;

  tmp_cli__ := Find_Remote_API_Hub(appName, apiName, True);
  if tmp_cli__ <> nil then
      Result := tmp_cli__.Wait_Execute_Call___(appName, Param, TimeOut__)
  else
      Result := Wait_Execute_Call___(appName, Param, TimeOut__);
end;

{ TCall_Bridge__ }

constructor TCall_Bridge__.Create;
{ * Initialises an empty output and sets IsRunning to False. }
begin
  inherited Create;
  Cli := nil;
  Output := TMem64.Create;
  IsRunning := False;
  Error_ := False;
end;

destructor TCall_Bridge__.Destroy;
{ * Frees the output memory. }
begin
  DisposeObjectAndNil(Output);
  inherited Destroy;
end;

procedure TCall_Bridge__.Do_Result(Sender: TPeerIO; Result_: TDFE);
{ * Called when the asynchronous response for a call arrives. Reads the result
  * TMem64 from the DFE and signals completion by setting IsRunning to False. }
begin
  Error_ := Result_.Count <= 0;
  if not Error_ then
      Result_.R.ReadMem64(Output);
  IsRunning := False;
end;

initialization

RegisterC40('APIHub', TC40_API_HUB_Service, TC40_API_HUB_Client);
Find_Hub_Safe_Critical := TCritical.Create('Find_Hub_Safe_Critical');

finalization

DisposeObjectAndNil(Find_Hub_Safe_Critical);

end.
