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
{ * double tunnel IO framework(Virtual Auth)                                   * }
{ * This unit implements a virtual-authentication double-tunnel communication  * }
{ * framework. It provides a service (TDTService_VirtualAuth) and client       * }
{ * (TDTClient_VirtualAuth) that manage two separate tunnels (Recv and Send)   * }
{ * with application‑level authentication callbacks (OnUserAuth, OnUserReg).   * }
{ * File transfer, batch streams, and P2PVM integration are included.          * }
{ ****************************************************************************** }

unit Z.Net.DoubleTunnelIO.VirtualAuth;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses
{$IFDEF FPC}
  Z.FPC.GenericList,
{$ENDIF FPC}
  Z.Core,
  Z.ListEngine, Z.UnicodeMixedLib,
  Z.DFE, Z.MemoryStream, Z.Net,
  Z.TextDataEngine, Z.Status, Z.Cadencer, Z.Notify, Z.PascalStrings, Z.UPascalStrings, Z.Cipher;

type
  TDTService_VirtualAuth = class; // Forward declaration of the virtual-auth service.
  TService_RecvTunnel_UserDefine_VirtualAuth = class; // Forward declaration for receive tunnel user-defined data.
  TDTService_VirtualAuthClass = class of TDTService_VirtualAuth; // Meta-class for service creation.

  { ============================================================================ }
  { Virtual Authentication I/O object – represents an authentication request. }
  { ============================================================================ }
  TVirtualAuthIO = class(TCore_Object_Intermediate)
  private
    RecvIO_ID: Cardinal; // Receive tunnel client ID. Set by Command_UserLogin.
    SendIO_ID: Cardinal; // Send tunnel client ID. Set by Command_UserLogin.
    AuthResult: TDFE; // DFE stream to write the authentication result. Set by Command_UserLogin (or nil if async).
    Done: Boolean; // Whether authentication is already finalised. Set by Accept/Reject.
  public
    Owner: TDTService_VirtualAuth; // Parent service. Set by Command_UserLogin.
    UserID: SystemString; // User identifier provided by the client. Set by Command_UserLogin.
    Passwd: SystemString; // Password provided by the client. Set by Command_UserLogin.
    function Online: Boolean; // Returns True if the receive tunnel client is still online.
    function UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth; // Returns the user-defined data of the receive tunnel.
    procedure Accept; // Accepts the authentication (calls UserLoginSuccess and sends success response).
    procedure Reject; // Rejects the authentication (sends failure response).
    procedure Bye; // Forcibly disconnects the client.
  end;

  { ============================================================================ }
  { Virtual Registration I/O object – represents a registration request. }
  { ============================================================================ }
  TVirtualRegIO = class(TCore_Object_Intermediate)
  private
    RecvIO_ID: Cardinal; // Receive tunnel client ID. Set by Command_RegisterUser.
    SendIO_ID: Cardinal; // Send tunnel client ID. Set by Command_RegisterUser.
    RegResult: TDFE; // DFE stream to write the registration result. Set by Command_RegisterUser (or nil if async).
    Done: Boolean; // Whether registration is already finalised. Set by Accept/Reject.
  public
    Owner: TDTService_VirtualAuth; // Parent service. Set by Command_RegisterUser.
    UserID: SystemString; // User identifier requested by the client. Set by Command_RegisterUser.
    Passwd: SystemString; // Password requested by the client. Set by Command_RegisterUser.
    function Online: Boolean; // Returns True if the receive tunnel client is still online.
    function UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth; // Returns the user-defined data of the receive tunnel.
    procedure Accept; // Accepts the registration (sends success response).
    procedure Reject; // Rejects the registration (sends failure response).
    procedure Bye; // Forcibly disconnects the client.
  end;

  { ============================================================================ }
  { User-defined data attached to a Send tunnel peer connection. }
  { ============================================================================ }
  TService_SendTunnel_UserDefine_VirtualAuth = class(TPeer_IO_User_Define)
  public
    RecvTunnel: TService_RecvTunnel_UserDefine_VirtualAuth; // Reference to the paired receive tunnel. Set by Command_TunnelLink.
    RecvTunnelID: Cardinal; // Remote ID of the receive tunnel. Set by Command_TunnelLink.
    DoubleTunnelService: TDTService_VirtualAuth; // Parent service instance. Set by Command_TunnelLink.

    constructor Create(Owner_: TPeerIO); override;
    destructor Destroy; override;

    function LinkOk: Boolean; // Returns True if this tunnel is properly linked (DoubleTunnelService assigned).
    property BindOk: Boolean read LinkOk;
  end;

  { ============================================================================ }
  { User-defined data attached to a Recv tunnel peer connection. }
  { ============================================================================ }
  TService_RecvTunnel_UserDefine_VirtualAuth = class(TPeer_IO_User_Define)
  private
    FCurrentFileStream: TCore_Stream; // Stream for currently receiving file. Set during file upload.
    FCurrentReceiveFileName: SystemString; // Full path of the file being received. Set during file upload.
  public
    SendTunnel: TService_SendTunnel_UserDefine_VirtualAuth; // Reference to the paired send tunnel. Set by Command_TunnelLink.
    SendTunnelID: Cardinal; // Remote ID of the send tunnel. Set by Command_TunnelLink.
    DoubleTunnelService: TDTService_VirtualAuth; // Parent service instance. Set by Command_TunnelLink or during login.
    UserID: SystemString; // Authenticated user ID. Set by Accept of TVirtualAuthIO.
    Passwd: SystemString; // Authenticated password. Set by Accept of TVirtualAuthIO.
    LoginSuccessed: Boolean; // Whether login succeeded. Set by Accept of TVirtualAuthIO.

    constructor Create(Owner_: TPeerIO); override;
    destructor Destroy; override;

    function LinkOk: Boolean; // Returns True if the send tunnel is linked.
    property BindOk: Boolean read LinkOk;
    property CurrentFileStream: TCore_Stream read FCurrentFileStream write FCurrentFileStream;
    property CurrentReceiveFileName: SystemString read FCurrentReceiveFileName write FCurrentReceiveFileName;
  end;

  { ============================================================================ }
  { Event callbacks for the virtual-auth service. }
  { ============================================================================ }
  TVirtualAuth_OnAuth = procedure(Sender: TDTService_VirtualAuth; AuthIO: TVirtualAuthIO) of object; // Called when a client tries to authenticate.
  TVirtualAuth_OnReg = procedure(Sender: TDTService_VirtualAuth; RegIO: TVirtualRegIO) of object; // Called when a client tries to register.
  TVirtualAuth_OnLinkSuccess = procedure(Sender: TDTService_VirtualAuth; UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth) of object; // Called when a tunnel link is established.
  TVirtualAuth_OnUserOut = procedure(Sender: TDTService_VirtualAuth; UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth) of object; // Called when a user disconnects.

  { ============================================================================ }
  { Virtual-Authentication Double-Tunnel Service. }
  { Manages two TZNet_Server instances for receive and send tunnels, handles }
  { authentication/registration via application callbacks, file transfer, }
  { batch streams, and P2PVM integration. }
  { ============================================================================ }
  TDTService_VirtualAuth = class(TCore_InterfacedObject_Intermediate)
  protected
    FRecvTunnel: TZNet_Server; // Receive tunnel server. Set by constructor.
    FSendTunnel: TZNet_Server; // Send tunnel server. Set by constructor.
    FCadencerEngine: TCadencer; // Cadencer for progress timing. Created in constructor.
    FProgressEngine: TN_Progress_Tool; // Progress tool for delayed execution. Created in constructor.
    FFileSystem: Boolean; // Enable file system operations. Set by constructor or property.
    FFileShareDirectory: SystemString; // Root directory for file sharing. Set by property.
    { event }
    FOnUserAuth: TVirtualAuth_OnAuth; // Authentication callback. Assigned by user.
    FOnUserReg: TVirtualAuth_OnReg; // Registration callback. Assigned by user.
    FOnLinkSuccess: TVirtualAuth_OnLinkSuccess; // Link success callback. Assigned by user.
    FOnUserOut: TVirtualAuth_OnUserOut; // User out callback. Assigned by user.
  protected
    { virtual event }
    procedure UserAuth(Sender: TVirtualAuthIO); virtual; // Triggers FOnUserAuth.
    procedure UserReg(Sender: TVirtualRegIO); virtual; // Triggers FOnUserReg.
    procedure UserLoginSuccess(UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth); virtual; // Called after successful login (before link).
    procedure UserLinkSuccess(UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth); virtual; // Called after tunnel link. Triggers FOnLinkSuccess.
    procedure UserOut(UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth); virtual; // Called on disconnect. Triggers FOnUserOut.
    procedure UserPostFileSuccess(UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth; fn: SystemString); virtual; // Called after a file is fully received.
  protected
    { registed server command }
    procedure Command_UserLogin(Sender: TPeerIO; InData, OutData: TDFE); virtual; // Handles login request, creates TVirtualAuthIO and calls UserAuth.
    procedure Command_RegisterUser(Sender: TPeerIO; InData, OutData: TDFE); virtual; // Handles registration request, creates TVirtualRegIO and calls UserReg.
    procedure Command_TunnelLink(Sender: TPeerIO; InData, OutData: TDFE); virtual; // Handles tunnel link request.
    procedure Command_GetCurrentCadencer(Sender: TPeerIO; InData, OutData: TDFE); virtual; // Returns current cadencer time.

    procedure Command_GetFileTime(Sender: TPeerIO; InData, OutData: TDFE); virtual; // Gets file modification time.
    procedure Command_GetFileInfo(Sender: TPeerIO; InData, OutData: TDFE); virtual; // Gets file existence and size.
    procedure Do_Th_Command_GetFileMD5(ThSender: THPC_Stream; ThInData, ThOutData: TDFE); // Threaded MD5 computation.
    procedure Command_GetFileMD5(Sender: TPeerIO; InData, OutData: TDFE); virtual; // Requests MD5 of a file.
    procedure Command_GetFile(Sender: TPeerIO; InData, OutData: TDFE); virtual; // Sends a file to the client.
    procedure Command_GetFileAs(Sender: TPeerIO; InData, OutData: TDFE); virtual; // Sends a file with a different save name.
    procedure Command_PostFileInfo(Sender: TPeerIO; InData: TDFE); virtual; // Receives file metadata before file data.
    procedure Command_PostFile(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64); virtual; // Receives file data chunks.
    procedure Command_PostFileOver(Sender: TPeerIO; InData: TDFE); virtual; // Marks file upload completion.
    procedure Command_GetFileFragmentData(Sender: TPeerIO; InData, OutData: TDFE); virtual; // Sends a fragment of a file.

    procedure Command_NewBatchStream(Sender: TPeerIO; InData: TDFE); virtual; // Starts a new batch stream upload.
    procedure Command_PostBatchStream(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64); virtual; // Receives batch stream data.
    procedure Command_ClearBatchStream(Sender: TPeerIO; InData: TDFE); virtual; // Clears pending batch streams.
    procedure Command_PostBatchStreamDone(Sender: TPeerIO; InData: TDFE); virtual; // Notifies completion of a batch stream.
    procedure Command_GetBatchStreamState(Sender: TPeerIO; InData, OutData: TDFE); virtual; // Returns state of batch streams.
  public
    constructor Create(RecvTunnel_, SendTunnel_: TZNet_Server); virtual;
    destructor Destroy; override;

    procedure SwitchAsMaxPerformance; // Sets tunnels to maximum performance mode.
    procedure SwitchAsMaxSecurity; // Sets tunnels to maximum security mode.
    procedure SwitchAsDefaultPerformance; // Sets tunnels to default performance mode.

    procedure Progress; virtual; // Main progress method (call regularly).
    procedure CadencerProgress(Sender: TObject; const deltaTime, newTime: Double); virtual; // Cadencer event handler.

    procedure RegisterCommand; virtual; // Registers all commands with the receive tunnel.
    procedure UnRegisterCommand; virtual; // Unregisters all commands.

    function GetUserDefineRecvTunnel(RecvCli: TPeerIO): TService_RecvTunnel_UserDefine_VirtualAuth; // Returns user-defined data for a recv tunnel.

    function TotalLinkCount: Integer; // Returns total number of linked users.

    { Batch stream operations }
    procedure PostBatchStream(cli: TPeerIO; stream: TCore_Stream; doneFreeStream: Boolean); overload; // Sends a batch stream without completion callback.
    procedure PostBatchStreamC(cli: TPeerIO; stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_C); overload; // Sends with C-style callback.
    procedure PostBatchStreamM(cli: TPeerIO; stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_M); overload; // Sends with method callback.
    procedure PostBatchStreamP(cli: TPeerIO; stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_P); overload; // Sends with nested callback.
    procedure ClearBatchStream(cli: TPeerIO); // Clears all batch streams for a client.
    procedure GetBatchStreamStateM(cli: TPeerIO; OnResult: TOnStream_M); overload; // Retrieves state with method callback.
    procedure GetBatchStreamStateM(cli: TPeerIO; Param1: Pointer; Param2: TObject; OnResult: TOnStreamParam_M); overload; // Retrieves state with parameterized method.
    procedure GetBatchStreamStateP(cli: TPeerIO; OnResult: TOnStream_P); overload; // Retrieves state with nested callback.
    procedure GetBatchStreamStateP(cli: TPeerIO; Param1: Pointer; Param2: TObject; OnResult: TOnStreamParam_P); overload; // Retrieves state with parameterized nested.

    property CadencerEngine: TCadencer read FCadencerEngine;

    property ProgressEngine: TN_Progress_Tool read FProgressEngine;
    property ProgressPost: TN_Progress_Tool read FProgressEngine;
    property PostProgress: TN_Progress_Tool read FProgressEngine;
    property PostRun: TN_Progress_Tool read FProgressEngine;
    property PostExecute: TN_Progress_Tool read FProgressEngine;

    property FileSystem: Boolean read FFileSystem write FFileSystem; // Enable/disable file system features.
    property FileReceiveDirectory: SystemString read FFileShareDirectory write FFileShareDirectory; // Directory for received files.
    property PublicFileDirectory: SystemString read FFileShareDirectory write FFileShareDirectory; // Alias for share directory.
    property FileShareDirectory: SystemString read FFileShareDirectory write FFileShareDirectory;

    property RecvTunnel: TZNet_Server read FRecvTunnel;
    property SendTunnel: TZNet_Server read FSendTunnel;

    property OnUserAuth: TVirtualAuth_OnAuth read FOnUserAuth write FOnUserAuth;
    property OnUserReg: TVirtualAuth_OnReg read FOnUserReg write FOnUserReg;
    property OnLinkSuccess: TVirtualAuth_OnLinkSuccess read FOnLinkSuccess write FOnLinkSuccess;
    property OnUserOut: TVirtualAuth_OnUserOut read FOnUserOut write FOnUserOut;
  end;

  TDTClient_VirtualAuth = class; // Forward declaration of virtual-auth client.
  TClient_SendTunnel_VirtualAuth = class; // Forward declaration for client send tunnel user define.
  TDTClient_VirtualAuthClass = class of TDTClient_VirtualAuth;

  { ============================================================================ }
  { User-defined data for client receive tunnel. }
  { ============================================================================ }
  TClient_RecvTunnel_VirtualAuth = class(TPeer_IO_User_Define)
  public
    Client: TDTClient_VirtualAuth; // Parent client instance. Set by tunnel link.
    SendTunnel: TClient_SendTunnel_VirtualAuth; // Paired send tunnel. Set by tunnel link.

    constructor Create(Owner_: TPeerIO); override;
    destructor Destroy; override;
  end;

  { ============================================================================ }
  { User-defined data for client send tunnel. }
  { ============================================================================ }
  TClient_SendTunnel_VirtualAuth = class(TPeer_IO_User_Define)
  public
    Client: TDTClient_VirtualAuth; // Parent client instance. Set by tunnel link.
    RecvTunnel: TClient_RecvTunnel_VirtualAuth; // Paired receive tunnel. Set by tunnel link.

    constructor Create(Owner_: TPeerIO); override;
    destructor Destroy; override;
  end;

  { ============================================================================ }
  { Callback types for file operations. }
  { ============================================================================ }
  TGetFileInfo_C_VirtualAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const Existed: Boolean; const fSiz: Int64);
  TGetFileInfo_M_VirtualAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const Existed: Boolean; const fSiz: Int64) of object;
  TFileMD5_C_VirtualAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const MD5: TMD5);
  TFileMD5_M_VirtualAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const MD5: TMD5) of object;
  TFileComplete_C_VirtualAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; stream: TCore_Stream; const fileName: SystemString);
  TFileComplete_M_VirtualAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; stream: TCore_Stream; const fileName: SystemString) of object;
  TFileFragmentData_C_VirtualAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const DataPtr: Pointer; const DataSize: Int64; const MD5: TMD5);
  TFileFragmentData_M_VirtualAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const DataPtr: Pointer; const DataSize: Int64; const MD5: TMD5) of object;

{$IFDEF FPC}
  TGetFileInfo_P_VirtualAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const Existed: Boolean; const fSiz: Int64) is nested;
  TFileMD5_P_VirtualAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const MD5: TMD5) is nested;
  TFileComplete_P_VirtualAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; stream: TCore_Stream; const fileName: SystemString) is nested;
  TFileFragmentData_P_VirtualAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const DataPtr: Pointer; const DataSize: Int64; const MD5: TMD5) is nested;
{$ELSE FPC}
  TGetFileInfo_P_VirtualAuth = reference to procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const Existed: Boolean; const fSiz: Int64);
  TFileMD5_P_VirtualAuth = reference to procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const MD5: TMD5);
  TFileComplete_P_VirtualAuth = reference to procedure(const UserData: Pointer; const UserObject: TCore_Object; stream: TCore_Stream; const fileName: SystemString);
  TFileFragmentData_P_VirtualAuth = reference to procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const DataPtr: Pointer; const DataSize: Int64; const MD5: TMD5);
{$ENDIF FPC}

  { ============================================================================ }
  { Virtual-Authentication Double-Tunnel Client. }
  { Manages two TZNet_Client instances for receive and send tunnels, handles }
  { authentication/registration via async callbacks, file transfers, }
  { batch streams, and P2PVM integration. }
  { ============================================================================ }
  TDTClient_VirtualAuth = class(TCore_InterfacedObject_Intermediate, IZNet_ClientInterface)
  protected
    FSendTunnel: TZNet_Client; // Send tunnel client. Set by constructor.
    FRecvTunnel: TZNet_Client; // Receive tunnel client. Set by constructor.
    FFileSystem: Boolean; // Enable file system operations. Set during tunnel link.
    FAutoFreeTunnel: Boolean; // Whether to auto-free tunnels on destroy. Set by user.
    FLinkOk: Boolean; // Indicates if double-tunnel link is established. Set by tunnel link.
    FWaitCommandTimeout: Cardinal; // Timeout for synchronous commands (ms). Set by user.

    FCurrentStream: TCore_Stream; // Stream currently being received. Set during file download.
    FCurrentReceiveStreamFileName: SystemString; // File name for the current receive stream. Set during file download.

    FCadencerEngine: TCadencer; // Cadencer for progress timing. Created in constructor.
    FProgressEngine: TN_Progress_Tool; // Progress tool. Created in constructor.

    FLastCadencerTime: Double; // Last synced cadencer time. Set by SyncCadencer.
    FServerDelay: Double; // Estimated server delay. Set by GetCurrentCadencer result.
  protected
    { client notify interface }
    procedure ClientConnected(Sender: TZNet_Client); virtual; // Called when a tunnel connects.
    procedure ClientDisconnect(Sender: TZNet_Client); virtual; // Called when a tunnel disconnects.
  public
    { registed client command }
    procedure Command_FileInfo(Sender: TPeerIO; InData: TDFE); virtual; // Receives file metadata from server.
    procedure Command_PostFile(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64); virtual; // Receives file data.
    procedure Command_PostFileOver(Sender: TPeerIO; InData: TDFE); virtual; // Marks file download completion.
    procedure Command_PostFileFragmentData(Sender: TPeerIO; InData: PByte; DataSize: NativeInt); virtual; // Receives file fragment data.

    procedure GetCurrentCadencer_StreamResult(Sender: TPeerIO; Result_: TDFE); virtual; // Handles cadencer sync response.

    procedure GetFileInfo_StreamParamResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; InData, Result_: TDFE); virtual; // Processes file info result.
    procedure GetFileMD5_StreamParamResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; InData, Result_: TDFE); virtual; // Processes MD5 result.

    { Downloading files from the server asynchronously and triggering notifications when completed }
    procedure GetFile_StreamParamResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; InData, Result_: TDFE); virtual;

    { Downloading file fragment data from the server asynchronously and triggering notifications when completed }
    procedure GetFileFragmentData_StreamParamResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; InData, Result_: TDFE); virtual;

    { batch stream support }
    procedure Command_NewBatchStream(Sender: TPeerIO; InData: TDFE); virtual; // Starts a new batch stream.
    procedure Command_PostBatchStream(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64); virtual; // Receives batch stream data.
    procedure Command_ClearBatchStream(Sender: TPeerIO; InData: TDFE); virtual; // Clears batch streams.
    procedure Command_PostBatchStreamDone(Sender: TPeerIO; InData: TDFE); virtual; // Notifies batch stream completion.
    procedure Command_GetBatchStreamState(Sender: TPeerIO; InData, OutData: TDFE); virtual; // Returns batch stream state.
  protected
    { async connect support }
    FAsyncConnectAddr: SystemString; // Address for async connect. Set by AsyncConnect calls.
    FAsyncConnRecvPort: Word; // Receive port for async connect.
    FAsyncConnSendPort: Word; // Send port for async connect.
    FAsyncOnResult_C: TOnState_C; // C-style async result callback. Set by caller.
    FAsyncOnResult_M: TOnState_M; // Method async result callback.
    FAsyncOnResult_P: TOnState_P; // Nested async result callback.
    procedure AsyncSendConnectResult(const cState: Boolean); // Callback after send tunnel connects.
    procedure AsyncRecvConnectResult(const cState: Boolean); // Callback after receive tunnel connects.

    procedure UserLogin_OnResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: TDFE); // Handles login response.
    procedure UserLogin_OnFailed(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: TDFE); // Handles login failure.
    procedure RegisterUser_OnResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: TDFE); // Handles registration response.
    procedure RegisterUser_OnFailed(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: TDFE); // Handles registration failure.
    procedure TunnelLink_OnResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: TDFE); // Handles tunnel link response.
    procedure TunnelLink_OnFailed(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: TDFE); // Handles tunnel link failure.
  public
    constructor Create(RecvTunnel_, SendTunnel_: TZNet_Client); virtual;
    destructor Destroy; override;

    // free receive+send tunnel from destroy, default is false
    property AutoFreeTunnel: Boolean read FAutoFreeTunnel write FAutoFreeTunnel;

    function Connected: Boolean; virtual; // Returns True if both tunnels are connected.

    function IOBusy: Boolean; // Returns True if either tunnel is busy.

    procedure SwitchAsMaxPerformance; // Sets tunnels to max performance.
    procedure SwitchAsMaxSecurity; // Sets tunnels to max security.
    procedure SwitchAsDefaultPerformance; // Sets tunnels to default performance.

    procedure Progress; virtual; // Main progress method.
    procedure CadencerProgress(Sender: TObject; const deltaTime, newTime: Double); virtual;

    { sync connect }
    function Connect(addr: SystemString; const RecvPort, SendPort: Word): Boolean; overload; virtual;

    { async connection }
    procedure AsyncConnectC(addr: SystemString; const RecvPort, SendPort: Word; OnResult: TOnState_C); overload; virtual;
    procedure AsyncConnectM(addr: SystemString; const RecvPort, SendPort: Word; OnResult: TOnState_M); overload; virtual;
    procedure AsyncConnectP(addr: SystemString; const RecvPort, SendPort: Word; OnResult: TOnState_P); overload; virtual;
    { parameter async connection }
    procedure AsyncConnectC(addr: SystemString; const RecvPort, SendPort: Word; Param1: Pointer; Param2: TObject; OnResult: TOnParamState_C); overload;
    procedure AsyncConnectM(addr: SystemString; const RecvPort, SendPort: Word; Param1: Pointer; Param2: TObject; OnResult: TOnParamState_M); overload;
    procedure AsyncConnectP(addr: SystemString; const RecvPort, SendPort: Word; Param1: Pointer; Param2: TObject; OnResult: TOnParamState_P); overload;
    procedure Disconnect; virtual;

    { sync mode }
    function UserLogin(UserID, Passwd: SystemString): Boolean; virtual;
    function RegisterUser(UserID, Passwd: SystemString): Boolean; virtual;
    function TunnelLink: Boolean; virtual;

    { async user login }
    procedure UserLoginC(UserID, Passwd: SystemString; On_C: TOnState_C); virtual;
    procedure UserLoginM(UserID, Passwd: SystemString; On_M: TOnState_M); virtual;
    procedure UserLoginP(UserID, Passwd: SystemString; On_P: TOnState_P); virtual;

    { async user registration }
    procedure RegisterUserC(UserID, Passwd: SystemString; On_C: TOnState_C); virtual;
    procedure RegisterUserM(UserID, Passwd: SystemString; On_M: TOnState_M); virtual;
    procedure RegisterUserP(UserID, Passwd: SystemString; On_P: TOnState_P); virtual;

    { async tunnel link }
    procedure TunnelLinkC(On_C: TOnState_C); virtual;
    procedure TunnelLinkM(On_M: TOnState_M); virtual;
    procedure TunnelLinkP(On_P: TOnState_P); virtual;

    { async mode SyncCadencer }
    procedure SyncCadencer; virtual;

    { remote file time }
    procedure GetFileTimeM(RemoteFilename: SystemString; On_CResult: TOnStream_M); overload;
    procedure GetFileTimeP(RemoteFilename: SystemString; On_CResult: TOnStream_P); overload;
    { remote file information }
    procedure GetFileInfoC(fileName: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TGetFileInfo_C_VirtualAuth); overload;
    procedure GetFileInfoM(fileName: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TGetFileInfo_M_VirtualAuth); overload;
    procedure GetFileInfoP(fileName: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TGetFileInfo_P_VirtualAuth); overload;
    { remote md5 support with public store space }
    procedure GetFileMD5C(fileName: SystemString; const StartPos, EndPos: Int64; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TFileMD5_C_VirtualAuth); overload;
    procedure GetFileMD5M(fileName: SystemString; const StartPos, EndPos: Int64; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TFileMD5_M_VirtualAuth); overload;
    procedure GetFileMD5P(fileName: SystemString; const StartPos, EndPos: Int64; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TFileMD5_P_VirtualAuth); overload;

    { normal download }
    procedure GetFileC(fileName, saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileComplete_C_VirtualAuth); overload;
    procedure GetFileM(fileName, saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileComplete_M_VirtualAuth); overload;
    procedure GetFileP(fileName, saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileComplete_P_VirtualAuth); overload;
    { Synchronously waiting to download files from the server to complete }
    function GetFile(fileName, saveToPath: SystemString): Boolean; overload;
    { restore download }
    procedure GetFileC(fileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileComplete_C_VirtualAuth); overload;
    procedure GetFileM(fileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileComplete_M_VirtualAuth); overload;
    procedure GetFileP(fileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileComplete_P_VirtualAuth); overload;
    procedure GetFileAsC(fileName, saveFileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileComplete_C_VirtualAuth); overload;
    procedure GetFileAsM(fileName, saveFileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileComplete_M_VirtualAuth); overload;
    procedure GetFileAsP(fileName, saveFileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileComplete_P_VirtualAuth); overload;
    { Synchronously waiting to restore download files from the server to complete }
    function GetFile(fileName: SystemString; StartPos: Int64; saveToPath: SystemString): Boolean; overload;

    { file fragment }
    procedure GetFileFragmentDataC(fileName: SystemString; StartPos, EndPos: Int64; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileFragmentData_C_VirtualAuth); overload;
    procedure GetFileFragmentDataM(fileName: SystemString; StartPos, EndPos: Int64; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileFragmentData_M_VirtualAuth); overload;
    procedure GetFileFragmentDataP(fileName: SystemString; StartPos, EndPos: Int64; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileFragmentData_P_VirtualAuth); overload;

    { automated download and verify }
    procedure AutomatedDownloadFileC(remoteFile, localFile: U_String; OnDownloadDone: TFileComplete_C_VirtualAuth);
    procedure AutomatedDownloadFileM(remoteFile, localFile: U_String; OnDownloadDone: TFileComplete_M_VirtualAuth);
    procedure AutomatedDownloadFileP(remoteFile, localFile: U_String; OnDownloadDone: TFileComplete_P_VirtualAuth);

    { Uploading local files asynchronously }
    procedure PostFile(fileName: SystemString); overload;
    procedure PostFile(l_fileName, r_fileName: SystemString); overload;
    { restore Uploading local files asynchronously }
    procedure PostFile(fileName: SystemString; StartPos: Int64); overload;
    procedure PostFile(l_fileName, r_fileName: SystemString; StartPos: Int64); overload;
    { Upload an Stream asynchronously and automatically release Stream after completion }
    procedure PostFile(fn: SystemString; stream: TCore_Stream; doneFreeStream: Boolean); overload;
    { restore Upload an Stream asynchronously and automatically release Stream after completion }
    procedure PostFile(fn: SystemString; stream: TCore_Stream; StartPos: Int64; doneFreeStream: Boolean); overload;

    { automated Upload and verify }
    procedure AutomatedUploadFile(localFile: U_String);

    { batch stream support }
    procedure PostBatchStream(stream: TCore_Stream; doneFreeStream: Boolean); overload;
    procedure PostBatchStreamC(stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_C); overload;
    procedure PostBatchStreamM(stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_M); overload;
    procedure PostBatchStreamP(stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_P); overload;
    procedure ClearBatchStream;
    procedure GetBatchStreamStateM(OnResult: TOnStream_M); overload;
    procedure GetBatchStreamStateM(Param1: Pointer; Param2: TObject; OnResult: TOnStreamParam_M); overload;
    procedure GetBatchStreamStateP(OnResult: TOnStream_P); overload;
    procedure GetBatchStreamStateP(Param1: Pointer; Param2: TObject; OnResult: TOnStreamParam_P); overload;
    function GetBatchStreamState(Result_: TDFE; TimeOut_: TTimeTick): Boolean; overload;

    procedure RegisterCommand; virtual; // Registers client commands with the receive tunnel.
    procedure UnRegisterCommand; virtual; // Unregisters client commands.

    property LinkOk: Boolean read FLinkOk;
    property BindOk: Boolean read FLinkOk;
    property WaitCommandTimeout: Cardinal read FWaitCommandTimeout write FWaitCommandTimeout;

    property CadencerEngine: TCadencer read FCadencerEngine;

    property ProgressEngine: TN_Progress_Tool read FProgressEngine;
    property ProgressPost: TN_Progress_Tool read FProgressEngine;
    property PostProgress: TN_Progress_Tool read FProgressEngine;
    property PostRun: TN_Progress_Tool read FProgressEngine;
    property PostExecute: TN_Progress_Tool read FProgressEngine;

    property ServerDelay: Double read FServerDelay;

    function RemoteInited: Boolean; // Returns True if both tunnels are remotely initialized.

    property RecvTunnel: TZNet_Client read FRecvTunnel;
    property SendTunnel: TZNet_Client read FSendTunnel;
  end;

  { ============================================================================ }
  { P2PVM (Peer-to-Peer Virtual Machine) wrappers for virtual-auth services. }
  { These classes integrate the double-tunnel with P2PVM functionality. }
  { ============================================================================ }

  TDT_P2PVM_VirtualAuth_OnState = record
    On_C: TOnState_C;
    On_M: TOnState_M;
    On_P: TOnState_P;
    procedure Init; // Initializes callbacks to nil.
  end;

  PDT_P2PVM_VirtualAuth_OnState = ^TDT_P2PVM_VirtualAuth_OnState;

  { ============================================================================ }
  { P2PVM Virtual-Auth Service - wraps a virtual-auth service with P2PVM }
  { server tunnels. }
  { ============================================================================ }
  TDT_P2PVM_VirtualAuth_Service = class(TCore_Object_Intermediate)
  private
    function GetQuietMode: Boolean;
    procedure SetQuietMode(const Value: Boolean);
  public
    RecvTunnel: TZNet_WithP2PVM_Server; // P2PVM receive tunnel. Created in constructor.
    SendTunnel: TZNet_WithP2PVM_Server; // P2PVM send tunnel. Created in constructor.
    DTService: TDTService_VirtualAuth; // Underlying virtual-auth service. Created in constructor.
    PhysicsTunnel: TZNet_Server; // Physical server tunnel for P2PVM. Created in constructor.

    constructor Create(ServiceClass_: TDTService_VirtualAuthClass; Physics_Class: TZNet_ServerClass);
    destructor Destroy; override;
    procedure Progress; virtual;
    function StartService(ListenAddr, ListenPort, Auth: SystemString): Boolean;
    procedure StopService;
    property QuietMode: Boolean read GetQuietMode write SetQuietMode;
  end;

  TDT_P2PVM_VirtualAuth_Client = class; // Forward declaration.
  TDT_P2PVM_VirtualAuth_ServicePool = TGenericsList<TDT_P2PVM_VirtualAuth_Service>;
  TOn_DT_P2PVM_VirtualAuth_Client_TunnelLink = procedure(Sender: TDT_P2PVM_VirtualAuth_Client) of object;

  { ============================================================================ }
  { P2PVM Virtual-Auth Client - wraps a virtual-auth client with P2PVM }
  { client tunnels. }
  { ============================================================================ }
  TDT_P2PVM_VirtualAuth_Client = class(TCore_Object_Intermediate)
  private
    OnConnectResultState: TDT_P2PVM_VirtualAuth_OnState; // Callback state for connect result. Set by Connect_* methods.
    Connecting: Boolean; // Whether a connection is in progress. Set internally.
    Reconnection: Boolean; // Whether reconnection is enabled. Set after first successful connection.
    procedure DoConnectionResult(const state: Boolean); // Handles physics tunnel connection result.
    procedure DoAutomatedP2PVMClientConnectionDone(Sender: TZNet; P_IO: TPeerIO); // Called when P2PVM client connection is ready.
    procedure DoRegisterResult(const state: Boolean); // Handles registration result during connection.
    procedure DoLoginResult(const state: Boolean); // Handles login result during connection.
    procedure DoTunnelLinkResult(const state: Boolean); // Handles tunnel link result.

    function GetQuietMode: Boolean;
    procedure SetQuietMode(const Value: Boolean);
  public
    RecvTunnel: TZNet_WithP2PVM_Client; // P2PVM receive tunnel. Created in constructor.
    SendTunnel: TZNet_WithP2PVM_Client; // P2PVM send tunnel. Created in constructor.
    DTClient: TDTClient_VirtualAuth; // Underlying virtual-auth client. Created in constructor.
    PhysicsTunnel: TZNet_Client; // Physical client tunnel for P2PVM. Created in constructor.
    LastAddr: SystemString; // Last connected address. Set by Connect.
    LastPort: SystemString; // Last connected port (as string). Set by Connect.
    LastAuth: SystemString; // Last auth token. Set by Connect.
    LastUser: SystemString; // Last username used for login. Set by Connect.
    LastPasswd: SystemString; // Last password used for login. Set by Connect.
    RegisterUserAndLogin: Boolean; // Whether to register before login. Set by user.
    AutomatedConnection: Boolean; // Whether to automatically reconnect. Set by user.
    OnTunnelLink: TOn_DT_P2PVM_VirtualAuth_Client_TunnelLink; // Called when tunnel link is established. Assigned by user.

    constructor Create(ClientClass_: TDTClient_VirtualAuthClass; Physics_Class: TZNet_ClientClass);
    destructor Destroy; override;
    procedure Progress; virtual;
    procedure Connect(addr, Port, Auth, User, Passwd: SystemString);
    procedure Connect_C(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_C);
    procedure Connect_M(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_M);
    procedure Connect_P(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_P);
    procedure Disconnect;
    property QuietMode: Boolean read GetQuietMode write SetQuietMode;
  end;

  TDT_P2PVM_VirtualAuth_ClientPool = TGenericsList<TDT_P2PVM_VirtualAuth_Client>;

  TDT_P2PVM_VirtualAuth_Custom_Service = class; // Forward declaration.
  TDT_P2PVM_VirtualAuth_Custom_Service_Class = class of TDT_P2PVM_VirtualAuth_Custom_Service;

  { ============================================================================ }
  { P2PVM Virtual-Auth Custom Service - for embedding within a physics service. }
  { ============================================================================ }
  TDT_P2PVM_VirtualAuth_Custom_Service = class(TCore_InterfacedObject_Intermediate)
  private
    function GetQuietMode: Boolean;
    procedure SetQuietMode(const Value: Boolean);
  public
    // bind
    Bind_PhysicsTunnel: TZNet_Server; // Physics tunnel to bind to. Set by constructor.
    Bind_P2PVM_Recv_IP6: SystemString; // IPv6 address for receive tunnel. Set by constructor.
    Bind_P2PVM_Recv_Port: Word; // Port for receive tunnel. Set by constructor.
    Bind_P2PVM_Send_IP6: SystemString; // IPv6 address for send tunnel. Set by constructor.
    Bind_P2PVM_Send_Port: Word; // Port for send tunnel. Set by constructor.
    // local
    RecvTunnel: TZNet_WithP2PVM_Server; // P2PVM receive server. Created in constructor.
    SendTunnel: TZNet_WithP2PVM_Server; // P2PVM send server. Created in constructor.
    DTService: TDTService_VirtualAuth; // Underlying virtual-auth service. Created in constructor.

    constructor Create(ServiceClass_: TDTService_VirtualAuthClass; PhysicsTunnel_: TZNet_Server;
      P2PVM_Recv_Name_, P2PVM_Recv_IP6_, P2PVM_Recv_Port_,
      P2PVM_Send_Name_, P2PVM_Send_IP6_, P2PVM_Send_Port_: SystemString); virtual;
    destructor Destroy; override;
    procedure Progress; virtual;
    procedure StartService(); virtual;
    procedure StopService(); virtual;
    property QuietMode: Boolean read GetQuietMode write SetQuietMode;
  end;

  TDT_P2PVM_VirtualAuth_Custom_ServicePool = TGenericsList<TDT_P2PVM_VirtualAuth_Custom_Service>;

  TDT_P2PVM_VirtualAuth_Custom_Client = class; // Forward declaration.
  TDT_P2PVM_VirtualAuth_Custom_Client_Class = class of TDT_P2PVM_VirtualAuth_Custom_Client;
  TOn_DT_P2PVM_VirtualAuth_Custom_Client_TunnelLink = procedure(Sender: TDT_P2PVM_VirtualAuth_Custom_Client) of object;

  TDT_P2PVM_VirtualAuth_Custom_Client_Clone_Pool_ = TBigList<TDT_P2PVM_VirtualAuth_Custom_Client>;

  { ============================================================================ }
  { Clone pool for custom clients - manages cloning technology. }
  { ============================================================================ }
  TDT_P2PVM_VirtualAuth_Custom_Client_Clone_Pool = class(TDT_P2PVM_VirtualAuth_Custom_Client_Clone_Pool_)
  public
    procedure DoFree(var Data: TDT_P2PVM_VirtualAuth_Custom_Client); override;
  end;

  { ============================================================================ }
  { P2PVM Virtual-Auth Custom Client - for embedding within a physics tunnel. }
  { Supports cloning (multiple clients sharing the same physical tunnel). }
  { ============================================================================ }
  TDT_P2PVM_VirtualAuth_Custom_Client = class(TCore_InterfacedObject_Intermediate)
  private
    OnConnectResultState: TDT_P2PVM_VirtualAuth_OnState; // Connect callback state. Set by Connect_* methods.
    Connecting: Boolean; // Connection in progress flag. Set internally.
    Reconnection: Boolean; // Reconnection flag. Set after first connect.
    procedure DoRegisterResult(const state: Boolean); // Handles registration result.
    procedure DoLoginResult(const state: Boolean); // Handles login result.
    function GetQuietMode: Boolean;
    procedure SetQuietMode(const Value: Boolean);
  private
    // clone Technology
    Parent_Client: TDT_P2PVM_VirtualAuth_Custom_Client; // Parent client if this is a clone. Set by Create_Clone.
    Clone_Instance_Ptr: TDT_P2PVM_VirtualAuth_Custom_Client_Clone_Pool_.PQueueStruct; // Pointer in parent's clone pool. Set by Create_Clone.
    procedure Do_Recv_Connect_State(const state: Boolean); // Callback when receive tunnel connects.
    procedure Do_Send_Connect_State(const state: Boolean); // Callback when send tunnel connects.
  public
    Clone_Pool: TDT_P2PVM_VirtualAuth_Custom_Client_Clone_Pool; // Pool of clones owned by this client. Created in constructor.
    // bind
    Bind_PhysicsTunnel: TZNet_Client; // Physics tunnel to bind to. Set by constructor.
    Bind_P2PVM_Recv_IP6: SystemString; // IPv6 for receive tunnel. Set by constructor.
    Bind_P2PVM_Recv_Port: Word; // Port for receive tunnel. Set by constructor.
    Bind_P2PVM_Send_IP6: SystemString; // IPv6 for send tunnel. Set by constructor.
    Bind_P2PVM_Send_Port: Word; // Port for send tunnel. Set by constructor.
    // local
    ClientClass: TDTClient_VirtualAuthClass; // Client class to instantiate. Set by constructor.
    RecvTunnel: TZNet_WithP2PVM_Client; // P2PVM receive client. Created in constructor.
    SendTunnel: TZNet_WithP2PVM_Client; // P2PVM send client. Created in constructor.
    DTClient: TDTClient_VirtualAuth; // Underlying virtual-auth client. Created in constructor.
    LastUser: SystemString; // Last username. Set by Connect.
    LastPasswd: SystemString; // Last password. Set by Connect.
    RegisterUserAndLogin: Boolean; // Whether to register before login. Set by user.
    AutomatedConnection: Boolean; // Whether to automatically reconnect. Set by user.
    OnTunnelLink: TOn_DT_P2PVM_VirtualAuth_Custom_Client_TunnelLink; // Called when tunnel link is established. Assigned by user.

    constructor Create(ClientClass_: TDTClient_VirtualAuthClass; PhysicsTunnel_: TZNet_Client;
      P2PVM_Recv_Name_, P2PVM_Recv_IP6_, P2PVM_Recv_Port_,
      P2PVM_Send_Name_, P2PVM_Send_IP6_, P2PVM_Send_Port_: SystemString); virtual;
    constructor Create_Clone(Parent_Client_: TDT_P2PVM_VirtualAuth_Custom_Client); virtual;
    destructor Destroy; override;
    procedure Progress;
    function LoginIsSuccessed: Boolean; // Returns True if the user is logged in.
    procedure DoTunnelLinkResult(const state: Boolean); // Handles tunnel link result.
    procedure Connect(User, Passwd: SystemString); overload;
    procedure Connect(); overload;
    procedure Connect_C(User, Passwd: SystemString; OnResult: TOnState_C); overload;
    procedure Connect_C(OnResult: TOnState_C); overload;
    procedure Connect_M(User, Passwd: SystemString; OnResult: TOnState_M); overload;
    procedure Connect_M(OnResult: TOnState_M); overload;
    procedure Connect_P(User, Passwd: SystemString; OnResult: TOnState_P); overload;
    procedure Connect_P(OnResult: TOnState_P); overload;
    procedure Disconnect;
    property QuietMode: Boolean read GetQuietMode write SetQuietMode;
  end;

  TDT_P2PVM_VirtualAuth_Custom_ClientPool = TGenericsList<TDT_P2PVM_VirtualAuth_Custom_Client>;

  { ============================================================================ }
  { Structures for passing parameters in file operation callbacks. }
  { ============================================================================ }
  PGetFileInfoStruct_VirtualAuth = ^TGetFileInfoStruct_VirtualAuth;

  TGetFileInfoStruct_VirtualAuth = record
    UserData: Pointer;
    UserObject: TCore_Object;
    fileName: SystemString;
    OnComplete_C: TGetFileInfo_C_VirtualAuth;
    OnComplete_M: TGetFileInfo_M_VirtualAuth;
    OnComplete_P: TGetFileInfo_P_VirtualAuth;
  end;

  PFileMD5Struct_VirtualAuth = ^TFileMD5Struct_VirtualAuth;

  TFileMD5Struct_VirtualAuth = record
    UserData: Pointer;
    UserObject: TCore_Object;
    fileName: SystemString;
    StartPos, EndPos: Int64;
    OnComplete_C: TFileMD5_C_VirtualAuth;
    OnComplete_M: TFileMD5_M_VirtualAuth;
    OnComplete_P: TFileMD5_P_VirtualAuth;
  end;

  PRemoteFileBackcall_VirtualAuth = ^TRemoteFileBackcall_VirtualAuth;

  TRemoteFileBackcall_VirtualAuth = record
    UserData: Pointer;
    UserObject: TCore_Object;
    OnComplete_C: TFileComplete_C_VirtualAuth;
    OnComplete_M: TFileComplete_M_VirtualAuth;
    OnComplete_P: TFileComplete_P_VirtualAuth;
  end;

  PFileFragmentDataBackcall_VirtualAuth = ^TFileFragmentDataBackcall_VirtualAuth;

  TFileFragmentDataBackcall_VirtualAuth = record
    UserData: Pointer;
    UserObject: TCore_Object;
    fileName: SystemString;
    StartPos, EndPos: Int64;
    OnComplete_C: TFileFragmentData_C_VirtualAuth;
    OnComplete_M: TFileFragmentData_M_VirtualAuth;
    OnComplete_P: TFileFragmentData_P_VirtualAuth;
  end;

  { ============================================================================ }
  { Internal helper classes for automated download/upload. }
  { ============================================================================ }
  TAutomatedDownloadFile_Struct_VirtualAuth = class(TCore_Object_Intermediate)
  private
    remoteFile: SystemString; // Remote file path. Set by caller.
    localFile: SystemString; // Local file path. Set by caller.
    OnDownloadDoneC: TFileComplete_C_VirtualAuth; // C-style completion callback. Set by caller.
    OnDownloadDoneM: TFileComplete_M_VirtualAuth; // Method completion callback. Set by caller.
    OnDownloadDoneP: TFileComplete_P_VirtualAuth; // Nested completion callback. Set by caller.
    Client: TDTClient_VirtualAuth; // Parent client. Set by caller.
    r_fileName: SystemString; // Remote file name (parsed). Set during info retrieval.
    r_fileExisted: Boolean; // Whether remote file exists. Set during info retrieval.
    r_fileSize: Int64; // Remote file size. Set during info retrieval.
    r_fileMD5: Z.Core.TMD5; // Remote file MD5. Set during MD5 retrieval.
    l_fileMD5: Z.Core.TMD5; // Local file MD5. Computed in thread.
    procedure DoComplete(const UserData: Pointer; const UserObject: TCore_Object; stream: TCore_Stream; const fileName: SystemString); // Final completion handler.
    procedure DoResult_GetFileInfo(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const Existed: Boolean; const fSiz: Int64); // Handles file info.
    procedure Do_Th_ComputeLFileMD5(); // Threaded local MD5 computation.
    procedure Done_ComputeLFileMD5(); // Called after thread completes.
    procedure DoResult_GetFileMD5(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const MD5: Z.Core.TMD5); // Handles remote MD5.
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TAutomatedUploadFile_Struct_VirtualAuth = class(TCore_Object_Intermediate)
  private
    localFile: SystemString; // Local file path. Set by caller.
    Client: TDTClient_VirtualAuth; // Parent client. Set by caller.
    r_fileName: SystemString; // Remote file name. Set during info retrieval.
    r_fileExisted: Boolean; // Whether remote file exists. Set during info retrieval.
    r_fileSize: Int64; // Remote file size. Set during info retrieval.
    r_fileMD5: Z.Core.TMD5; // Remote file MD5. Set during MD5 retrieval.
    l_file_StartPos: Int64; // Local file start position for comparison. Set during computation.
    l_file_EndPos: Int64; // Local file end position. Set during computation.
    l_fileMD5: Z.Core.TMD5; // Local file MD5. Computed in thread.
    procedure DoResult_GetFileInfo(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const Existed: Boolean; const fSiz: Int64); // Handles file info.
    procedure Do_Th_ComputeLFileMD5(); // Threaded local MD5 computation.
    procedure Done_ComputeLFileMD5(); // Called after thread completes.
    procedure DoResult_GetFileMD5(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const MD5: Z.Core.TMD5); // Handles remote MD5.
  public
    constructor Create;
    destructor Destroy; override;
  end;

  { Legacy type aliases }
  TZNet_DoubleTunnelService_VirtualAuth = TDTService_VirtualAuth;
  TZNet_DoubleTunnelClient_VirtualAuth = TDTClient_VirtualAuth;

implementation

uses SysUtils;

procedure TAutomatedDownloadFile_Struct_VirtualAuth.DoComplete(const UserData: Pointer; const UserObject: TCore_Object; stream: TCore_Stream; const fileName: SystemString);
begin
  try
    if Assigned(OnDownloadDoneC) then
        OnDownloadDoneC(UserData, UserObject, stream, fileName)
    else if Assigned(OnDownloadDoneM) then
        OnDownloadDoneM(UserData, UserObject, stream, fileName)
    else if Assigned(OnDownloadDoneP) then
        OnDownloadDoneP(UserData, UserObject, stream, fileName);
  except
  end;
  DelayFreeObj(1.0, Self);
end;

procedure TAutomatedDownloadFile_Struct_VirtualAuth.DoResult_GetFileInfo(const UserData: Pointer; const UserObject: TCore_Object;
  const fileName: SystemString; const Existed: Boolean; const fSiz: Int64);
begin
  if Existed then
    begin
      r_fileName := fileName;
      r_fileSize := fSiz;
      if not umlFileExists(localFile) then
          Client.GetFileAsM(remoteFile, umlGetFileName(localFile), 0, umlGetFilePath(localFile), nil, nil, DoComplete)
      else if fSiz >= umlGetFileSize(localFile) then
        begin
          umlCacheFileMD5(localFile);
          Client.GetFileMD5M(umlGetFileName(remoteFile), 0, umlGetFileSize(localFile), nil, nil, DoResult_GetFileMD5);
        end
      else
          Client.GetFileAsM(remoteFile, umlGetFileName(localFile), 0, umlGetFilePath(localFile), nil, nil, DoComplete);
    end
  else
    begin
      DoStatus('no found remote file: "%s" ', [remoteFile]);
      DelayFreeObj(1.0, Self);
    end;
end;

procedure TAutomatedDownloadFile_Struct_VirtualAuth.Do_Th_ComputeLFileMD5;
begin
  DoStatus('compute md5 from local "%s"', [localFile]);
  l_fileMD5 := umlFileMD5(localFile);
  TCompute.PostM1(Done_ComputeLFileMD5);
end;

procedure TAutomatedDownloadFile_Struct_VirtualAuth.Done_ComputeLFileMD5;
begin
  if umlMD5Compare(l_fileMD5, r_fileMD5) then
    begin
      if r_fileSize = umlGetFileSize(localFile) then
          DoComplete(nil, nil, nil, localFile)
      else
          Client.GetFileAsM(r_fileName, umlGetFileName(localFile), umlGetFileSize(localFile), umlGetFilePath(localFile), nil, nil, DoComplete);
    end
  else
      Client.GetFileAsM(r_fileName, umlGetFileName(localFile), 0, umlGetFilePath(localFile), nil, nil, DoComplete);
end;

procedure TAutomatedDownloadFile_Struct_VirtualAuth.DoResult_GetFileMD5(const UserData: Pointer; const UserObject: TCore_Object;
  const fileName: SystemString; const StartPos, EndPos: Int64; const MD5: Z.Core.TMD5);
begin
  r_fileMD5 := MD5;
  TCompute.RunM_NP(Do_Th_ComputeLFileMD5);
end;

constructor TAutomatedDownloadFile_Struct_VirtualAuth.Create;
begin
  inherited Create;
  remoteFile := '';
  localFile := '';
  OnDownloadDoneC := nil;
  OnDownloadDoneM := nil;
  OnDownloadDoneP := nil;
  Client := nil;
  r_fileName := '';
  r_fileExisted := False;
  r_fileSize := -1;
  r_fileMD5 := NullMD5;
  l_fileMD5 := NullMD5;
end;

destructor TAutomatedDownloadFile_Struct_VirtualAuth.Destroy;
begin
  remoteFile := '';
  localFile := '';
  r_fileName := '';
  inherited Destroy;
end;

procedure TAutomatedUploadFile_Struct_VirtualAuth.DoResult_GetFileInfo(const UserData: Pointer; const UserObject: TCore_Object;
  const fileName: SystemString; const Existed: Boolean; const fSiz: Int64);
begin
  r_fileExisted := Existed;

  if Existed then
    begin
      r_fileName := fileName;
      r_fileSize := fSiz;
      if r_fileSize <= umlGetFileSize(localFile) then
          Client.GetFileMD5M(umlGetFileName(localFile), 0, r_fileSize, nil, nil, DoResult_GetFileMD5)
      else
        begin
          Client.PostFile(localFile);
          DelayFreeObj(1.0, Self);
        end;
    end
  else
    begin
      Client.PostFile(localFile);
      DelayFreeObj(1.0, Self);
    end;
end;

procedure TAutomatedUploadFile_Struct_VirtualAuth.Do_Th_ComputeLFileMD5;
begin
  DoStatus('compute md5 from local "%s"', [localFile]);
  l_fileMD5 := umlFileMD5(localFile, l_file_StartPos, l_file_EndPos);
  TCompute.PostM1(Done_ComputeLFileMD5);
end;

procedure TAutomatedUploadFile_Struct_VirtualAuth.Done_ComputeLFileMD5;
begin
  if umlMD5Compare(r_fileMD5, l_fileMD5) then
    begin
      if umlGetFileSize(localFile) > r_fileSize then
          Client.PostFile(localFile, r_fileSize);
    end
  else
      Client.PostFile(localFile);
  DelayFreeObj(1.0, Self);
end;

procedure TAutomatedUploadFile_Struct_VirtualAuth.DoResult_GetFileMD5(const UserData: Pointer; const UserObject: TCore_Object;
  const fileName: SystemString; const StartPos, EndPos: Int64; const MD5: Z.Core.TMD5);
begin
  r_fileMD5 := MD5;
  l_file_StartPos := StartPos;
  l_file_EndPos := EndPos;
  TCompute.RunM_NP(Do_Th_ComputeLFileMD5);
end;

constructor TAutomatedUploadFile_Struct_VirtualAuth.Create;
begin
  inherited Create;
  localFile := '';
  Client := nil;
  r_fileName := '';
  r_fileExisted := False;
  r_fileSize := -1;
  r_fileMD5 := NullMD5;

  l_file_StartPos := 0;
  l_file_EndPos := 0;
  l_fileMD5 := NullMD5;
end;

destructor TAutomatedUploadFile_Struct_VirtualAuth.Destroy;
begin
  localFile := '';
  r_fileName := '';
  inherited Destroy;
end;

function TVirtualAuthIO.Online: Boolean;
begin
  Result := Owner.RecvTunnel.Exists(RecvIO_ID);
end;

function TVirtualAuthIO.UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth;
begin
  Result := nil;
  if not Online then
      exit;
  Result := Owner.RecvTunnel[RecvIO_ID].UserDefine as TService_RecvTunnel_UserDefine_VirtualAuth;
end;

procedure TVirtualAuthIO.Accept;
var
  IO: TPeerIO;
  n: SystemString;
begin
  if AuthResult <> nil then
    begin
      UserDefineIO.UserID := UserID;
      UserDefineIO.Passwd := Passwd;
      UserDefineIO.LoginSuccessed := True;
      AuthResult.WriteBool(True);
      AuthResult.WriteString(PFormat('success Login:%s', [UserID]));
      Owner.UserLoginSuccess(UserDefineIO);
      Done := True;
      exit;
    end
  else if Online then
    begin
      IO := Owner.RecvTunnel.PeerIO[RecvIO_ID];
      if (IO.ResultSendIsPaused) then
        begin
          UserDefineIO.UserID := UserID;
          UserDefineIO.Passwd := Passwd;
          UserDefineIO.LoginSuccessed := True;
          IO.OutDataFrame.WriteBool(True);
          IO.OutDataFrame.WriteString(PFormat('success Login:%s', [UserID]));
          IO.ContinueResultSend;
          Owner.UserLoginSuccess(UserDefineIO);
        end;
    end;
  DelayFreeObj(1.0, Self);
end;

procedure TVirtualAuthIO.Reject;
var
  IO: TPeerIO;
  r_IO, s_IO: TPeerIO;
begin
  if AuthResult <> nil then
    begin
      UserDefineIO.UserID := UserID;
      UserDefineIO.Passwd := Passwd;
      UserDefineIO.LoginSuccessed := False;
      AuthResult.WriteBool(False);
      AuthResult.WriteString(PFormat('Reject user:%s', [UserID]));
      Done := True;
      exit;
    end
  else if Online then
    begin
      IO := Owner.RecvTunnel.PeerIO[RecvIO_ID];
      if (IO.ResultSendIsPaused) then
        begin
          UserDefineIO.UserID := UserID;
          UserDefineIO.Passwd := Passwd;
          UserDefineIO.LoginSuccessed := False;
          IO.OutDataFrame.WriteBool(False);
          IO.OutDataFrame.WriteString(PFormat('Reject user:%s', [UserID]));
          IO.ContinueResultSend;
        end;
    end;

  DelayFreeObj(1.0, Self);
end;

procedure TVirtualAuthIO.Bye;
var
  r_IO, s_IO: TPeerIO;
begin
  r_IO := Owner.RecvTunnel.PeerIO[RecvIO_ID];
  if r_IO <> nil then
      r_IO.delayClose(1.0);

  DelayFreeObj(1.0, Self);
end;

function TVirtualRegIO.Online: Boolean;
begin
  Result := Owner.RecvTunnel.Exists(RecvIO_ID);
end;

function TVirtualRegIO.UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth;
begin
  Result := nil;
  if not Online then
      exit;
  Result := Owner.RecvTunnel[RecvIO_ID].UserDefine as TService_RecvTunnel_UserDefine_VirtualAuth;
end;

procedure TVirtualRegIO.Accept;
var
  IO: TPeerIO;
  n: SystemString;
begin
  if RegResult <> nil then
    begin
      RegResult.WriteBool(True);
      RegResult.WriteString(PFormat('success Reg:%s', [UserID]));
      Done := True;
      exit;
    end
  else if Online then
    begin
      IO := Owner.RecvTunnel.PeerIO[RecvIO_ID];
      if (IO.ResultSendIsPaused) then
        begin
          IO.OutDataFrame.WriteBool(True);
          IO.OutDataFrame.WriteString(PFormat('success Reg:%s', [UserID]));
          IO.ContinueResultSend;
        end;
    end;
  DelayFreeObj(1.0, Self);
end;

procedure TVirtualRegIO.Reject;
var
  IO: TPeerIO;
  r_IO, s_IO: TPeerIO;
begin
  if RegResult <> nil then
    begin
      RegResult.WriteBool(False);
      RegResult.WriteString(PFormat('Reject Reg:%s', [UserID]));
      Done := True;
      exit;
    end
  else if Online then
    begin
      IO := Owner.RecvTunnel.PeerIO[RecvIO_ID];
      if (IO.ResultSendIsPaused) then
        begin
          IO.OutDataFrame.WriteBool(False);
          IO.OutDataFrame.WriteString(PFormat('Reject Reg:%s', [UserID]));
          IO.ContinueResultSend;
        end;
    end;

  DelayFreeObj(1.0, Self);
end;

procedure TVirtualRegIO.Bye;
var
  r_IO, s_IO: TPeerIO;
begin
  r_IO := Owner.RecvTunnel.PeerIO[RecvIO_ID];
  if r_IO <> nil then
      r_IO.delayClose(1.0);

  DelayFreeObj(1.0, Self);
end;

constructor TService_SendTunnel_UserDefine_VirtualAuth.Create(Owner_: TPeerIO);
begin
  inherited Create(Owner_);
  RecvTunnel := nil;
  RecvTunnelID := 0;
  DoubleTunnelService := nil;
end;

destructor TService_SendTunnel_UserDefine_VirtualAuth.Destroy;
begin
  if (DoubleTunnelService <> nil) and (RecvTunnelID > 0) and (RecvTunnel <> nil) then
    begin
      if DoubleTunnelService.FRecvTunnel.Exists(RecvTunnelID) then
          DoubleTunnelService.FRecvTunnel.PeerIO[RecvTunnelID].Disconnect;
    end;
  inherited Destroy;
end;

function TService_SendTunnel_UserDefine_VirtualAuth.LinkOk: Boolean;
begin
  Result := DoubleTunnelService <> nil;
end;

constructor TService_RecvTunnel_UserDefine_VirtualAuth.Create(Owner_: TPeerIO);
begin
  inherited Create(Owner_);
  SendTunnel := nil;
  SendTunnelID := 0;
  DoubleTunnelService := nil;
  FCurrentFileStream := nil;
  FCurrentReceiveFileName := '';
  UserID := '';
  Passwd := '';
  LoginSuccessed := False;
end;

destructor TService_RecvTunnel_UserDefine_VirtualAuth.Destroy;
begin
  if DoubleTunnelService <> nil then
    begin
      DoubleTunnelService.UserOut(Self);

      if (DoubleTunnelService <> nil) and (SendTunnelID > 0) and (SendTunnel <> nil) then
        begin
          if DoubleTunnelService.FSendTunnel.Exists(SendTunnelID) then
              DoubleTunnelService.FSendTunnel.PeerIO[SendTunnelID].Disconnect;
        end;
      DoubleTunnelService := nil;
    end;

  if FCurrentFileStream <> nil then
      DisposeObject(FCurrentFileStream);
  FCurrentFileStream := nil;
  inherited Destroy;
end;

function TService_RecvTunnel_UserDefine_VirtualAuth.LinkOk: Boolean;
begin
  Result := DoubleTunnelService <> nil;
end;

procedure TDTService_VirtualAuth.UserAuth(Sender: TVirtualAuthIO);
begin
  try
    if Assigned(FOnUserAuth) then
        FOnUserAuth(Self, Sender);
  except
  end;
end;

procedure TDTService_VirtualAuth.UserReg(Sender: TVirtualRegIO);
begin
  try
    if Assigned(FOnUserReg) then
        FOnUserReg(Self, Sender);
  except
  end;
end;

procedure TDTService_VirtualAuth.UserLoginSuccess(UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth);
begin
end;

procedure TDTService_VirtualAuth.UserLinkSuccess(UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth);
begin
  try
    if Assigned(FOnLinkSuccess) then
        FOnLinkSuccess(Self, UserDefineIO);
  except
  end;
end;

procedure TDTService_VirtualAuth.UserOut(UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth);
begin
  try
    if Assigned(FOnUserOut) then
        FOnUserOut(Self, UserDefineIO);
  except
  end;
end;

procedure TDTService_VirtualAuth.UserPostFileSuccess(UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth; fn: SystemString);
begin
end;

procedure TDTService_VirtualAuth.Command_UserLogin(Sender: TPeerIO; InData, OutData: TDFE);
var
  SendTunnelID: Cardinal;
  UserID, UserPasswd: SystemString;
  UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth;
  AuthIO: TVirtualAuthIO;
begin
  SendTunnelID := InData.Reader.ReadCardinal;
  UserID := InData.Reader.ReadString;
  UserPasswd := InData.Reader.ReadString;

  UserDefineIO := GetUserDefineRecvTunnel(Sender);

  if not FSendTunnel.Exists(SendTunnelID) then
    begin
      OutData.WriteBool(False);
      OutData.WriteString(PFormat('send tunnel Illegal:%d', [SendTunnelID]));
      exit;
    end;

  AuthIO := TVirtualAuthIO.Create;
  AuthIO.Owner := Self;
  AuthIO.RecvIO_ID := Sender.ID;
  AuthIO.SendIO_ID := SendTunnelID;
  AuthIO.AuthResult := OutData;
  AuthIO.Done := False;
  AuthIO.UserID := UserID;
  AuthIO.Passwd := UserPasswd;

  try
      UserAuth(AuthIO);
  except
  end;

  if AuthIO.Done then
    begin
      DisposeObject(AuthIO);
    end
  else
    begin
      AuthIO.AuthResult := nil;
      Sender.PauseResultSend;
    end;
end;

procedure TDTService_VirtualAuth.Command_RegisterUser(Sender: TPeerIO; InData, OutData: TDFE);
var
  SendTunnelID: Cardinal;
  UserID, UserPasswd: SystemString;
  UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth;
  RegIO: TVirtualRegIO;
begin
  SendTunnelID := InData.Reader.ReadCardinal;
  UserID := InData.Reader.ReadString;
  UserPasswd := InData.Reader.ReadString;

  UserDefineIO := GetUserDefineRecvTunnel(Sender);

  if not FSendTunnel.Exists(SendTunnelID) then
    begin
      OutData.WriteBool(False);
      OutData.WriteString(PFormat('send tunnel Illegal:%d', [SendTunnelID]));
      exit;
    end;

  RegIO := TVirtualRegIO.Create;
  RegIO.Owner := Self;
  RegIO.RecvIO_ID := Sender.ID;
  RegIO.SendIO_ID := SendTunnelID;
  RegIO.RegResult := OutData;
  RegIO.Done := False;
  RegIO.UserID := UserID;
  RegIO.Passwd := UserPasswd;

  try
      UserReg(RegIO);
  except
  end;

  if RegIO.Done then
    begin
      DisposeObject(RegIO);
    end
  else
    begin
      RegIO.RegResult := nil;
      Sender.PauseResultSend;
    end;
end;

procedure TDTService_VirtualAuth.Command_TunnelLink(Sender: TPeerIO; InData, OutData: TDFE);
var
  RecvID, SendID: Cardinal;
  UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth;
begin
  RecvID := InData.Reader.ReadCardinal;
  SendID := InData.Reader.ReadCardinal;

  UserDefineIO := GetUserDefineRecvTunnel(Sender);

  if not FSendTunnel.Exists(SendID) then
    begin
      OutData.WriteBool(False);
      OutData.WriteString(PFormat('send tunnel Illegal:%d', [SendID]));
      OutData.WriteBool(FFileSystem);
      exit;
    end;

  if not FRecvTunnel.Exists(RecvID) then
    begin
      OutData.WriteBool(False);
      OutData.WriteString(PFormat('received tunnel Illegal:%d', [RecvID]));
      OutData.WriteBool(FFileSystem);
      exit;
    end;

  if Sender.ID <> RecvID then
    begin
      OutData.WriteBool(False);
      OutData.WriteString(PFormat('received tunnel Illegal:%d-%d', [Sender.ID, RecvID]));
      OutData.WriteBool(FFileSystem);
      exit;
    end;

  UserDefineIO.SendTunnel := FSendTunnel.PeerIO[SendID].UserDefine as TService_SendTunnel_UserDefine_VirtualAuth;
  UserDefineIO.SendTunnelID := SendID;
  UserDefineIO.DoubleTunnelService := Self;

  UserDefineIO.SendTunnel.RecvTunnel := UserDefineIO;
  UserDefineIO.SendTunnel.RecvTunnelID := RecvID;
  UserDefineIO.SendTunnel.DoubleTunnelService := Self;

  OutData.WriteBool(True);
  OutData.WriteString(PFormat('tunnel link success! received:%d <-> send:%d', [RecvID, SendID]));
  OutData.WriteBool(FFileSystem);

  UserLinkSuccess(UserDefineIO);
end;

procedure TDTService_VirtualAuth.Command_GetCurrentCadencer(Sender: TPeerIO; InData, OutData: TDFE);
begin
  FCadencerEngine.Progress;
  OutData.WriteDouble(FCadencerEngine.CurrentTime);
end;

procedure TDTService_VirtualAuth.Command_GetFileTime(Sender: TPeerIO; InData, OutData: TDFE);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth;
  fullfn, fileName: SystemString;
begin
  if not FFileSystem then
      exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
      exit;

  fileName := InData.Reader.ReadString;
  fullfn := umlCombineFileName(FFileShareDirectory, fileName);
  if not umlFileExists(fullfn) then
    begin
      OutData.WriteBool(False);
      exit;
    end;
  OutData.WriteBool(True);
  OutData.WriteString(fileName);
  OutData.WriteDouble(umlGetFileTime(fullfn));
end;

procedure TDTService_VirtualAuth.Command_GetFileInfo(Sender: TPeerIO; InData, OutData: TDFE);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth;
  fullfn, fileName: SystemString;
begin
  if not FFileSystem then
      exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
      exit;

  fileName := InData.Reader.ReadString;

  fullfn := umlCombineFileName(FFileShareDirectory, fileName);
  if umlFileExists(fullfn) then
    begin
      OutData.WriteBool(True);
      OutData.WriteInt64(umlGetFileSize(fullfn));
    end
  else
    begin
      OutData.WriteBool(False);
      OutData.WriteInt64(0);
    end;
end;

procedure TDTService_VirtualAuth.Do_Th_Command_GetFileMD5(ThSender: THPC_Stream; ThInData, ThOutData: TDFE);
var
  fullfn, fileName: SystemString;
  StartPos, EndPos: Int64;
  fs: TCore_FileStream;
  MD5: TMD5;
begin
  fileName := ThInData.Reader.ReadString;
  StartPos := ThInData.Reader.ReadInt64;
  EndPos := ThInData.Reader.ReadInt64;

  fullfn := umlCombineFileName(FFileShareDirectory, fileName);
  if not umlFileExists(fullfn) then
    begin
      ThOutData.WriteBool(False);
      exit;
    end;

  try
      fs := TCore_FileStream.Create(fullfn, fmOpenRead or fmShareDenyNone);
  except
    ThOutData.WriteBool(False);
    exit;
  end;

  if (EndPos > fs.Size) then
      EndPos := fs.Size;

  if ((EndPos = StartPos) or (EndPos = 0)) or ((StartPos = 0) and (EndPos = fs.Size)) then
      MD5 := umlFileMD5(fullfn)
  else
      MD5 := umlStreamMD5(fs, StartPos, EndPos);

  ThOutData.WriteBool(True);
  ThOutData.WriteMD5(MD5);
  DisposeObject(fs);
end;

procedure TDTService_VirtualAuth.Command_GetFileMD5(Sender: TPeerIO; InData, OutData: TDFE);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
      exit;

  RunHPC_StreamM(Sender, nil, nil, InData, OutData, Do_Th_Command_GetFileMD5);
end;

procedure TDTService_VirtualAuth.Command_GetFile(Sender: TPeerIO; InData, OutData: TDFE);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth;
  fullfn, fileName, remoteinfo: SystemString;
  StartPos: Int64;
  RemoteBackcallAddr: UInt64;
  sendDE: TDFE;
  fs: TCore_FileStream;
begin
  if not FFileSystem then
      exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
      exit;

  fileName := InData.Reader.ReadString;
  StartPos := InData.Reader.ReadInt64;
  remoteinfo := InData.Reader.ReadString;
  RemoteBackcallAddr := InData.Reader.ReadPointer;

  fullfn := umlCombineFileName(FFileShareDirectory, fileName);
  if not umlFileExists(fullfn) then
    begin
      OutData.WriteBool(False);
      OutData.WriteString(PFormat('filename invailed %s', [fileName]));
      exit;
    end;

  try
      fs := TCore_FileStream.Create(fullfn, fmOpenRead or fmShareDenyNone);
  except
      exit;
  end;

  sendDE := TDFE.Create;
  sendDE.WriteString(fileName);
  sendDE.WriteInt64(StartPos);
  sendDE.WriteInt64(fs.Size);
  sendDE.WriteString(remoteinfo);
  UserDefineIO.SendTunnel.Owner.SendStreamNotifyCmd(C_FileInfo, sendDE);
  DisposeObject(sendDE);

  fs.Position := 0;
  UserDefineIO.SendTunnel.Owner.SendBigStream(C_PostFile, fs, StartPos, True);

  sendDE := TDFE.Create;
  sendDE.WritePointer(RemoteBackcallAddr);
  UserDefineIO.SendTunnel.Owner.SendStreamNotifyCmd(C_PostFileOver, sendDE);
  DisposeObject(sendDE);

  OutData.WriteBool(True);
  OutData.WriteString(PFormat('post %s to send tunnel', [fileName]));
end;

procedure TDTService_VirtualAuth.Command_GetFileAs(Sender: TPeerIO; InData, OutData: TDFE);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth;
  fullfn, fileName, saveFileName, remoteinfo: SystemString;
  StartPos: Int64;
  RemoteBackcallAddr: UInt64;
  sendDE: TDFE;
  fs: TCore_FileStream;
begin
  if not FFileSystem then
      exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
      exit;

  fileName := InData.Reader.ReadString;
  saveFileName := InData.Reader.ReadString;
  StartPos := InData.Reader.ReadInt64;
  remoteinfo := InData.Reader.ReadString;
  RemoteBackcallAddr := InData.Reader.ReadPointer;

  fullfn := umlCombineFileName(FFileShareDirectory, fileName);
  if not umlFileExists(fullfn) then
    begin
      OutData.WriteBool(False);
      OutData.WriteString(PFormat('filename invailed %s', [fileName]));
      exit;
    end;

  try
      fs := TCore_FileStream.Create(fullfn, fmOpenRead or fmShareDenyNone);
  except
      exit;
  end;

  sendDE := TDFE.Create;
  sendDE.WriteString(saveFileName);
  sendDE.WriteInt64(StartPos);
  sendDE.WriteInt64(fs.Size);
  sendDE.WriteString(remoteinfo);
  UserDefineIO.SendTunnel.Owner.SendStreamNotifyCmd(C_FileInfo, sendDE);
  DisposeObject(sendDE);

  fs.Position := 0;
  UserDefineIO.SendTunnel.Owner.SendBigStream(C_PostFile, fs, StartPos, True);

  sendDE := TDFE.Create;
  sendDE.WritePointer(RemoteBackcallAddr);
  UserDefineIO.SendTunnel.Owner.SendStreamNotifyCmd(C_PostFileOver, sendDE);
  DisposeObject(sendDE);

  OutData.WriteBool(True);
  OutData.WriteString(PFormat('post %s to send tunnel', [fileName]));
end;

procedure TDTService_VirtualAuth.Command_PostFileInfo(Sender: TPeerIO; InData: TDFE);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth;
  fn: SystemString;
  StartPos: Int64;
  FSize: Int64;
  fullfn: SystemString;
begin
  if not FFileSystem then
      exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
    begin
      Sender.delayClose();
      exit;
    end;

  if UserDefineIO.FCurrentFileStream <> nil then
    begin
      DisposeObject(UserDefineIO.FCurrentFileStream);
      UserDefineIO.FCurrentFileStream := nil;
    end;

  fn := InData.Reader.ReadString;
  StartPos := InData.Reader.ReadInt64;
  FSize := InData.Reader.ReadInt64;

  fullfn := umlCombineFileName(FFileShareDirectory, fn);
  UserDefineIO.FCurrentReceiveFileName := fullfn;
  try
    if (StartPos > 0) and (umlFileExists(fullfn)) then
      begin
        UserDefineIO.FCurrentFileStream := TCore_FileStream.Create(fullfn, fmOpenReadWrite);
        if StartPos <= UserDefineIO.FCurrentFileStream.Size then
            UserDefineIO.FCurrentFileStream.Position := StartPos
        else
            UserDefineIO.FCurrentFileStream.Position := UserDefineIO.FCurrentFileStream.Size;
        Sender.Print(PFormat('restore post to public: %s', [fullfn]));
      end
    else
      begin
        UserDefineIO.FCurrentFileStream := TCore_FileStream.Create(fullfn, fmCreate);
        Sender.Print(PFormat('normal post to public: %s', [fullfn]));
      end;
  except
    Sender.Print('post file failed: %s', [fullfn]);
    UserDefineIO.FCurrentFileStream := nil;
  end;
end;

procedure TDTService_VirtualAuth.Command_PostFile(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
    begin
      Sender.delayClose();
      exit;
    end;

  if UserDefineIO.FCurrentFileStream <> nil then
    begin
      InData.Position := 0;
      if InData.Size > 0 then
          UserDefineIO.FCurrentFileStream.CopyFrom(InData, InData.Size);
    end;
end;

procedure TDTService_VirtualAuth.Command_PostFileOver(Sender: TPeerIO; InData: TDFE);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth;
  fn: SystemString;
begin
  if not FFileSystem then
      exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
    begin
      Sender.delayClose();
      exit;
    end;

  if UserDefineIO.FCurrentFileStream <> nil then
    begin
      fn := UserDefineIO.FCurrentReceiveFileName;
      DisposeObject(UserDefineIO.FCurrentFileStream);
      UserDefineIO.FCurrentFileStream := nil;

      Sender.Print('Received File Completed:%s', [fn]);
      UserPostFileSuccess(UserDefineIO, fn);
    end;
end;

procedure TDTService_VirtualAuth.Command_GetFileFragmentData(Sender: TPeerIO; InData, OutData: TDFE);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_VirtualAuth;
  fullfn, fileName: SystemString;
  StartPos, EndPos, siz, fp: Int64;
  RemoteBackcallAddr: UInt64;
  fs: TCore_FileStream;
  mem_: TMS64;
  MD5: TMD5;
begin
  if not FFileSystem then
      exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
      exit;

  fileName := InData.Reader.ReadString;
  StartPos := InData.Reader.ReadInt64;
  EndPos := InData.Reader.ReadInt64;
  RemoteBackcallAddr := InData.Reader.ReadPointer;

  fullfn := umlCombineFileName(FFileShareDirectory, fileName);
  if not umlFileExists(fullfn) then
    begin
      OutData.WriteBool(False);
      exit;
    end;

  try
      fs := TCore_FileStream.Create(fullfn, fmOpenRead or fmShareDenyNone);
  except
    OutData.WriteBool(False);
    exit;
  end;

  if EndPos < StartPos then
      TSwap<Int64>.Do_(EndPos, StartPos);

  if (EndPos > fs.Size) then
      EndPos := fs.Size;

  siz := EndPos - StartPos;
  if siz <= 0 then
    begin
      OutData.WriteBool(False);
      DisposeObject(fs);
      exit;
    end;

  fs.Position := StartPos;
  mem_ := TMS64.Create;
  mem_.WriteUInt64(RemoteBackcallAddr);
  mem_.WriteInt64(StartPos);
  mem_.WriteInt64(EndPos);
  mem_.WriteInt64(siz);
  fp := mem_.Position;
  mem_.CopyFrom(fs, siz);
  MD5 := umlStreamMD5(mem_, fp, mem_.Size);
  mem_.WriteMD5(MD5);

  DisposeObject(fs);
  UserDefineIO.SendTunnel.Owner.SendCompleteBuffer(C_PostFileFragmentData, mem_.Memory, mem_.Size, True);
  mem_.DiscardMemory;
  DisposeObject(mem_);

  OutData.WriteBool(True);
end;

procedure TDTService_VirtualAuth.Command_NewBatchStream(Sender: TPeerIO; InData: TDFE);
var
  RT: TService_RecvTunnel_UserDefine_VirtualAuth;
  p: PBigStreamBatchPostData;
begin
  RT := GetUserDefineRecvTunnel(Sender);
  if not RT.LinkOk then
      exit;
  p := RT.BigStreamBatchList.NewPostData;
  p^.RemoteMD5 := InData.Reader.ReadMD5;
  p^.CompletedBackcallPtr := InData.Reader.ReadPointer;
end;

procedure TDTService_VirtualAuth.Command_PostBatchStream(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64);
var
  RT: TService_RecvTunnel_UserDefine_VirtualAuth;
  p: PBigStreamBatchPostData;
  de: TDFE;
begin
  RT := GetUserDefineRecvTunnel(Sender);
  if not RT.LinkOk then
      exit;

  if Sender.UserDefine.BigStreamBatchList.Count > 0 then
    begin
      p := RT.BigStreamBatchList.Last;
      p^.Source.Position := p^.Source.Size;
      p^.Source.CopyFrom(InData, InData.Size);
      if (p^.Source.Size >= BigStreamTotal) then
        begin
          p^.Source.Position := 0;
          p^.SourceMD5 := umlStreamMD5(p^.Source);

          if p^.CompletedBackcallPtr <> 0 then
            begin
              de := TDFE.Create;
              de.WriteMD5(p^.RemoteMD5);
              de.WriteMD5(p^.SourceMD5);
              de.WritePointer(p^.CompletedBackcallPtr);
              RT.SendTunnel.Owner.SendStreamNotifyCmd(C_PostBatchStreamDone, de);
              DisposeObject(de);
            end;
        end;
    end;
end;

procedure TDTService_VirtualAuth.Command_ClearBatchStream(Sender: TPeerIO; InData: TDFE);
var
  RT: TService_RecvTunnel_UserDefine_VirtualAuth;
begin
  RT := GetUserDefineRecvTunnel(Sender);
  if not RT.LinkOk then
      exit;
  RT.BigStreamBatchList.Clear;
end;

procedure TDTService_VirtualAuth.Command_PostBatchStreamDone(Sender: TPeerIO; InData: TDFE);
var
  RT: TService_RecvTunnel_UserDefine_VirtualAuth;
  rMD5, sMD5: TMD5;
  backCallVal: UInt64;
  backCallValPtr: POnStateStruct;
  MD5Verify: Boolean;
begin
  RT := GetUserDefineRecvTunnel(Sender);
  if not RT.LinkOk then
      exit;

  rMD5 := InData.Reader.ReadMD5;
  sMD5 := InData.Reader.ReadMD5;
  backCallVal := InData.Reader.ReadPointer;

  backCallValPtr := POnStateStruct(Pointer(backCallVal));
  MD5Verify := umlMD5Compare(rMD5, sMD5);

  if backCallValPtr = nil then
      exit;

  try
    if Assigned(backCallValPtr^.On_C) then
        backCallValPtr^.On_C(MD5Verify)
    else if Assigned(backCallValPtr^.On_M) then
        backCallValPtr^.On_M(MD5Verify)
    else if Assigned(backCallValPtr^.On_P) then
        backCallValPtr^.On_P(MD5Verify);
  except
  end;

  try
      Dispose(backCallValPtr);
  except
  end;
end;

procedure TDTService_VirtualAuth.Command_GetBatchStreamState(Sender: TPeerIO; InData, OutData: TDFE);
var
  RT: TService_RecvTunnel_UserDefine_VirtualAuth;
  i: Integer;
  p: PBigStreamBatchPostData;

  de: TDFE;
begin
  RT := GetUserDefineRecvTunnel(Sender);
  if not RT.LinkOk then
      exit;

  for i := 0 to RT.BigStreamBatchList.Count - 1 do
    begin
      p := RT.BigStreamBatchList[i];
      de := TDFE.Create;
      p^.Encode(de);
      OutData.WriteDataFrame(de);
      DisposeObject(de);
    end;
end;

constructor TDTService_VirtualAuth.Create(RecvTunnel_, SendTunnel_: TZNet_Server);
begin
  inherited Create;
  FRecvTunnel := RecvTunnel_;
  FRecvTunnel.PeerClientUserDefineClass := TService_RecvTunnel_UserDefine_VirtualAuth;
  FSendTunnel := SendTunnel_;
  FSendTunnel.PeerClientUserDefineClass := TService_SendTunnel_UserDefine_VirtualAuth;

  FRecvTunnel.DoubleChannelFramework := Self;
  FSendTunnel.DoubleChannelFramework := Self;

  FCadencerEngine := TCadencer.Create;
  FCadencerEngine.OnProgress := CadencerProgress;
  FProgressEngine := TN_Progress_Tool.Create;

  FFileSystem := {$IFDEF DoubleIOFileSystem}True{$ELSE DoubleIOFileSystem}False{$ENDIF DoubleIOFileSystem};
  FFileShareDirectory := umlCurrentPath;

  if not umlDirectoryExists(FFileShareDirectory) then
      umlCreateDirectory(FFileShareDirectory);

  SwitchAsDefaultPerformance;

  FOnUserAuth := nil;
  FOnUserReg := nil;
  FOnLinkSuccess := nil;
  FOnUserOut := nil;
end;

destructor TDTService_VirtualAuth.Destroy;
begin
  DisposeObject(FCadencerEngine);
  DisposeObject(FProgressEngine);
  inherited Destroy;
end;

procedure TDTService_VirtualAuth.SwitchAsMaxPerformance;
begin
  FRecvTunnel.SwitchMaxPerformance;
  FSendTunnel.SwitchMaxPerformance;
end;

procedure TDTService_VirtualAuth.SwitchAsMaxSecurity;
begin
  FRecvTunnel.SwitchMaxSecurity;
  FSendTunnel.SwitchMaxSecurity;
end;

procedure TDTService_VirtualAuth.SwitchAsDefaultPerformance;
begin
  FRecvTunnel.SwitchDefaultPerformance;
  FSendTunnel.SwitchDefaultPerformance;
end;

procedure TDTService_VirtualAuth.Progress;
begin
  FCadencerEngine.Progress;
  FRecvTunnel.Progress;
  FSendTunnel.Progress;
end;

procedure TDTService_VirtualAuth.CadencerProgress(Sender: TObject; const deltaTime, newTime: Double);
begin
  FProgressEngine.Progress(deltaTime);
end;

procedure TDTService_VirtualAuth.RegisterCommand;
begin
  FRecvTunnel.RegisterStream(C_UserLogin).OnExecute := Command_UserLogin;
  FRecvTunnel.RegisterStream(C_RegisterUser).OnExecute := Command_RegisterUser;
  FRecvTunnel.RegisterStream(C_TunnelLink).OnExecute := Command_TunnelLink;
  FRecvTunnel.RegisterStream(C_GetCurrentCadencer).OnExecute := Command_GetCurrentCadencer;

  FRecvTunnel.RegisterStream(C_GetFileTime).OnExecute := Command_GetFileTime;
  FRecvTunnel.RegisterStream(C_GetFileInfo).OnExecute := Command_GetFileInfo;
  FRecvTunnel.RegisterStream(C_GetFileMD5).OnExecute := Command_GetFileMD5;
  FRecvTunnel.RegisterStream(C_GetFile).OnExecute := Command_GetFile;
  FRecvTunnel.RegisterStream(C_GetFileAs).OnExecute := Command_GetFileAs;
  FRecvTunnel.RegisterStreamNotify(C_PostFileInfo).OnExecute := Command_PostFileInfo;
  FRecvTunnel.RegisterBigStream(C_PostFile).OnExecute := Command_PostFile;
  FRecvTunnel.RegisterStreamNotify(C_PostFileOver).OnExecute := Command_PostFileOver;
  FRecvTunnel.RegisterStream(C_GetFileFragmentData).OnExecute := Command_GetFileFragmentData;

  FRecvTunnel.RegisterStreamNotify(C_NewBatchStream).OnExecute := Command_NewBatchStream;
  FRecvTunnel.RegisterBigStream(C_PostBatchStream).OnExecute := Command_PostBatchStream;
  FRecvTunnel.RegisterStreamNotify(C_ClearBatchStream).OnExecute := Command_ClearBatchStream;
  FRecvTunnel.RegisterStreamNotify(C_PostBatchStreamDone).OnExecute := Command_PostBatchStreamDone;
  FRecvTunnel.RegisterStream(C_GetBatchStreamState).OnExecute := Command_GetBatchStreamState;
end;

procedure TDTService_VirtualAuth.UnRegisterCommand;
begin
  FRecvTunnel.DeleteRegistedCMD(C_UserLogin);
  FRecvTunnel.DeleteRegistedCMD(C_RegisterUser);
  FRecvTunnel.DeleteRegistedCMD(C_TunnelLink);
  FRecvTunnel.DeleteRegistedCMD(C_GetCurrentCadencer);

  FRecvTunnel.DeleteRegistedCMD(C_GetFileTime);
  FRecvTunnel.DeleteRegistedCMD(C_GetFileInfo);
  FRecvTunnel.DeleteRegistedCMD(C_GetFileMD5);
  FRecvTunnel.DeleteRegistedCMD(C_GetFile);
  FRecvTunnel.DeleteRegistedCMD(C_GetFileAs);
  FRecvTunnel.DeleteRegistedCMD(C_PostFileInfo);
  FRecvTunnel.DeleteRegistedCMD(C_PostFile);
  FRecvTunnel.DeleteRegistedCMD(C_PostFileOver);
  FRecvTunnel.DeleteRegistedCMD(C_GetFileFragmentData);

  FRecvTunnel.DeleteRegistedCMD(C_NewBatchStream);
  FRecvTunnel.DeleteRegistedCMD(C_PostBatchStream);
  FRecvTunnel.DeleteRegistedCMD(C_ClearBatchStream);
  FRecvTunnel.DeleteRegistedCMD(C_PostBatchStreamDone);
  FRecvTunnel.DeleteRegistedCMD(C_GetBatchStreamState);
end;

function TDTService_VirtualAuth.GetUserDefineRecvTunnel(RecvCli: TPeerIO): TService_RecvTunnel_UserDefine_VirtualAuth;
begin
  if RecvCli = nil then
      exit(nil);
  Result := RecvCli.UserDefine as TService_RecvTunnel_UserDefine_VirtualAuth;
end;

function TDTService_VirtualAuth.TotalLinkCount: Integer;
begin
  Result := RecvTunnel.Count;
end;

procedure TDTService_VirtualAuth.PostBatchStream(cli: TPeerIO; stream: TCore_Stream; doneFreeStream: Boolean);
var
  de: TDFE;
begin
  de := TDFE.Create;

  de.WriteMD5(umlStreamMD5(stream));
  de.WritePointer(0);
  cli.SendStreamNotifyCmd(C_NewBatchStream, de);
  DisposeObject(de);

  cli.SendBigStream(C_PostBatchStream, stream, doneFreeStream);
end;

procedure TDTService_VirtualAuth.PostBatchStreamC(cli: TPeerIO; stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_C);
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;

  p := nil;

  if Assigned(OnCompletedBackcall) then
    begin
      new(p);
      p^.Init;
      p^.On_C := OnCompletedBackcall;
    end;

  de.WriteMD5(umlStreamMD5(stream));
  de.WritePointer(p);
  cli.SendStreamNotifyCmd(C_NewBatchStream, de);
  DisposeObject(de);

  cli.SendBigStream(C_PostBatchStream, stream, doneFreeStream);
end;

procedure TDTService_VirtualAuth.PostBatchStreamM(cli: TPeerIO; stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_M);
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;

  p := nil;

  if Assigned(OnCompletedBackcall) then
    begin
      new(p);
      p^.Init;
      p^.On_M := OnCompletedBackcall;
    end;

  de.WriteMD5(umlStreamMD5(stream));
  de.WritePointer(p);
  cli.SendStreamNotifyCmd(C_NewBatchStream, de);
  DisposeObject(de);

  cli.SendBigStream(C_PostBatchStream, stream, doneFreeStream);
end;

procedure TDTService_VirtualAuth.PostBatchStreamP(cli: TPeerIO; stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_P);
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;

  p := nil;

  if Assigned(OnCompletedBackcall) then
    begin
      new(p);
      p^.Init;
      p^.On_P := OnCompletedBackcall;
    end;

  de.WriteMD5(umlStreamMD5(stream));
  de.WritePointer(p);
  cli.SendStreamNotifyCmd(C_NewBatchStream, de);
  DisposeObject(de);

  cli.SendBigStream(C_PostBatchStream, stream, doneFreeStream);
end;

procedure TDTService_VirtualAuth.ClearBatchStream(cli: TPeerIO);
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;
  cli.SendStreamNotifyCmd(C_ClearBatchStream, de);
  DisposeObject(de);
end;

procedure TDTService_VirtualAuth.GetBatchStreamStateM(cli: TPeerIO; OnResult: TOnStream_M);
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;
  cli.SendStreamCmdM(C_GetBatchStreamState, de, OnResult);
  DisposeObject(de);
end;

procedure TDTService_VirtualAuth.GetBatchStreamStateM(cli: TPeerIO; Param1: Pointer; Param2: TObject; OnResult: TOnStreamParam_M);
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;
  cli.SendStreamCmdM(C_GetBatchStreamState, de, Param1, Param2, OnResult);
  DisposeObject(de);
end;

procedure TDTService_VirtualAuth.GetBatchStreamStateP(cli: TPeerIO; OnResult: TOnStream_P);
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;
  cli.SendStreamCmdP(C_GetBatchStreamState, de, OnResult);
  DisposeObject(de);
end;

procedure TDTService_VirtualAuth.GetBatchStreamStateP(cli: TPeerIO; Param1: Pointer; Param2: TObject; OnResult: TOnStreamParam_P);
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;
  cli.SendStreamCmdP(C_GetBatchStreamState, de, Param1, Param2, OnResult);
  DisposeObject(de);
end;

constructor TClient_RecvTunnel_VirtualAuth.Create(Owner_: TPeerIO);
begin
  inherited Create(Owner_);
  Client := nil;
  SendTunnel := nil;
end;

destructor TClient_RecvTunnel_VirtualAuth.Destroy;
begin
  if Client <> nil then
      Client.FLinkOk := False;
  inherited Destroy;
end;

constructor TClient_SendTunnel_VirtualAuth.Create(Owner_: TPeerIO);
begin
  inherited Create(Owner_);
  Client := nil;
  RecvTunnel := nil;
end;

destructor TClient_SendTunnel_VirtualAuth.Destroy;
begin
  if Client <> nil then
      Client.FLinkOk := False;
  inherited Destroy;
end;

{ client notify interface }

procedure TDTClient_VirtualAuth.ClientConnected(Sender: TZNet_Client);
begin
end;

procedure TDTClient_VirtualAuth.ClientDisconnect(Sender: TZNet_Client);
begin
  if FCurrentStream <> nil then
    begin
      DisposeObject(FCurrentStream);
      FCurrentStream := nil;
    end;
  FCurrentReceiveStreamFileName := '';
end;

procedure TDTClient_VirtualAuth.Command_FileInfo(Sender: TPeerIO; InData: TDFE);
var
  fn: SystemString;
  StartPos: Int64;
  FSize: Int64;
  remoteinfo: SystemString;
  fullfn: SystemString;
begin
  if FCurrentStream <> nil then
    begin
      DisposeObject(FCurrentStream);
      FCurrentStream := nil;
    end;

  fn := InData.Reader.ReadString;
  StartPos := InData.Reader.ReadInt64;
  FSize := InData.Reader.ReadInt64;
  remoteinfo := InData.Reader.ReadString;

  if not umlDirectoryExists(remoteinfo) then
      umlCreateDirectory(remoteinfo);

  fullfn := umlCombineFileName(remoteinfo, fn);
  FCurrentReceiveStreamFileName := fullfn;
  try
    if StartPos > 0 then
      begin
        FCurrentStream := TCore_FileStream.Create(fullfn, fmOpenReadWrite);
        FCurrentStream.Position := StartPos;
      end
    else
        FCurrentStream := TCore_FileStream.Create(fullfn, fmCreate);
  except
    Sender.Print('post file failed: %s', [fullfn]);
    { FRecvTunnel.ClientIO.Disconnect; }
    FCurrentStream := nil;
  end;
end;

procedure TDTClient_VirtualAuth.Command_PostFile(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64);
begin
  if FCurrentStream <> nil then
    begin
      InData.Position := 0;
      if InData.Size > 0 then
        begin
          FCurrentStream.Position := FCurrentStream.Size;
          FCurrentStream.CopyFrom(InData, InData.Size);
        end;
    end;
end;

procedure TDTClient_VirtualAuth.Command_PostFileOver(Sender: TPeerIO; InData: TDFE);
var
  RemoteBackcallAddr: UInt64;
  p: PRemoteFileBackcall_VirtualAuth;
  fn: SystemString;
begin
  RemoteBackcallAddr := InData.Reader.ReadPointer;
  p := Pointer(RemoteBackcallAddr);
  fn := FCurrentReceiveStreamFileName;

  if FCurrentStream <> nil then
    begin
      Sender.Print(PFormat('Receive %s ok', [umlGetFileName(fn).Text]));

      try
        if p <> nil then
          begin
            if Assigned(p^.OnComplete_C) then
              begin
                FCurrentStream.Position := 0;
                p^.OnComplete_C(p^.UserData, p^.UserObject, FCurrentStream, fn);
              end
            else if Assigned(p^.OnComplete_M) then
              begin
                FCurrentStream.Position := 0;
                p^.OnComplete_M(p^.UserData, p^.UserObject, FCurrentStream, fn);
              end
            else if Assigned(p^.OnComplete_P) then
              begin
                FCurrentStream.Position := 0;
                p^.OnComplete_P(p^.UserData, p^.UserObject, FCurrentStream, fn);
              end;
            Dispose(p);
          end;
      except
      end;

      DisposeObject(FCurrentStream);
      FCurrentStream := nil;
    end;
end;

procedure TDTClient_VirtualAuth.Command_PostFileFragmentData(Sender: TPeerIO; InData: PByte; DataSize: NativeInt);
var
  mem_: TMS64;
  StartPos, EndPos, siz: Int64;
  RemoteBackcallAddr: UInt64;
  p: PFileFragmentDataBackcall_VirtualAuth;
  fp: Pointer;
  MD5: TMD5;
begin
  mem_ := TMS64.Create;
  mem_.SetPointerWithProtectedMode(InData, DataSize);
  RemoteBackcallAddr := mem_.ReadUInt64;
  StartPos := mem_.ReadInt64;
  EndPos := mem_.ReadInt64;
  siz := mem_.ReadInt64;
  fp := mem_.PositionAsPtr;
  mem_.Position := mem_.Position + siz;
  MD5 := mem_.ReadMD5;
  DisposeObject(mem_);

  p := Pointer(RemoteBackcallAddr);
  if p <> nil then
    begin
      try
        if Assigned(p^.OnComplete_C) then
            p^.OnComplete_C(p^.UserData, p^.UserObject, p^.fileName, p^.StartPos, p^.EndPos, fp, siz, MD5)
        else if Assigned(p^.OnComplete_M) then
            p^.OnComplete_M(p^.UserData, p^.UserObject, p^.fileName, p^.StartPos, p^.EndPos, fp, siz, MD5)
        else if Assigned(p^.OnComplete_P) then
            p^.OnComplete_P(p^.UserData, p^.UserObject, p^.fileName, p^.StartPos, p^.EndPos, fp, siz, MD5);
      except
      end;
      p^.fileName := '';
      Dispose(p);
    end;
end;

procedure TDTClient_VirtualAuth.GetCurrentCadencer_StreamResult(Sender: TPeerIO; Result_: TDFE);
var
  servTime: Double;
begin
  servTime := Result_.Reader.ReadDouble;

  FCadencerEngine.Progress;
  FServerDelay := FCadencerEngine.CurrentTime - FLastCadencerTime;

  FCadencerEngine.CurrentTime := servTime + FServerDelay;
  FCadencerEngine.Progress;
end;

procedure TDTClient_VirtualAuth.GetFileInfo_StreamParamResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; InData, Result_: TDFE);
var
  p: PGetFileInfoStruct_VirtualAuth;
  Existed: Boolean;
  fSiz: Int64;
begin
  p := PGetFileInfoStruct_VirtualAuth(Param1);
  Existed := Result_.Reader.ReadBool;
  fSiz := Result_.Reader.ReadInt64;
  if p <> nil then
    begin
      if Assigned(p^.OnComplete_C) then
          p^.OnComplete_C(p^.UserData, p^.UserObject, p^.fileName, Existed, fSiz)
      else if Assigned(p^.OnComplete_M) then
          p^.OnComplete_M(p^.UserData, p^.UserObject, p^.fileName, Existed, fSiz)
      else if Assigned(p^.OnComplete_P) then
          p^.OnComplete_P(p^.UserData, p^.UserObject, p^.fileName, Existed, fSiz);
      p^.fileName := '';
      Dispose(p);
    end;
end;

procedure TDTClient_VirtualAuth.GetFileMD5_StreamParamResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; InData, Result_: TDFE);
var
  p: PFileMD5Struct_VirtualAuth;
  successed: Boolean;
  MD5: TMD5;
begin
  p := PFileMD5Struct_VirtualAuth(Param1);
  successed := Result_.Reader.ReadBool;
  if successed then
      MD5 := Result_.Reader.ReadMD5
  else
      MD5 := NullMD5;
  if p <> nil then
    begin
      if Assigned(p^.OnComplete_C) then
          p^.OnComplete_C(p^.UserData, p^.UserObject, p^.fileName, p^.StartPos, p^.EndPos, MD5)
      else if Assigned(p^.OnComplete_M) then
          p^.OnComplete_M(p^.UserData, p^.UserObject, p^.fileName, p^.StartPos, p^.EndPos, MD5)
      else if Assigned(p^.OnComplete_P) then
          p^.OnComplete_P(p^.UserData, p^.UserObject, p^.fileName, p^.StartPos, p^.EndPos, MD5);
      p^.fileName := '';
      Dispose(p);
    end;
end;

procedure TDTClient_VirtualAuth.GetFile_StreamParamResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; InData, Result_: TDFE);
var
  p: PRemoteFileBackcall_VirtualAuth;
begin
  if Result_.Count > 0 then
    begin
      if Result_.Reader.ReadBool then
          exit;
      Sender.Print('get file failed:%s', [Result_.Reader.ReadString]);
    end;

  p := Param1;
  Dispose(p);
end;

procedure TDTClient_VirtualAuth.GetFileFragmentData_StreamParamResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; InData, Result_: TDFE);
var
  p: PFileFragmentDataBackcall_VirtualAuth;
begin
  if Result_.Count > 0 then
    begin
      if Result_.Reader.ReadBool then
          exit;
    end;

  p := Param1;
  Dispose(p);
end;

procedure TDTClient_VirtualAuth.Command_NewBatchStream(Sender: TPeerIO; InData: TDFE);
var
  RT: TClient_RecvTunnel_VirtualAuth;
  p: PBigStreamBatchPostData;
begin
  if not LinkOk then
      exit;
  RT := Sender.UserDefine as TClient_RecvTunnel_VirtualAuth;
  p := RT.BigStreamBatchList.NewPostData;
  p^.RemoteMD5 := InData.Reader.ReadMD5;
  p^.CompletedBackcallPtr := InData.Reader.ReadPointer;
end;

procedure TDTClient_VirtualAuth.Command_PostBatchStream(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64);
var
  RT: TClient_RecvTunnel_VirtualAuth;
  p: PBigStreamBatchPostData;
  de: TDFE;
begin
  if not LinkOk then
      exit;
  RT := Sender.UserDefine as TClient_RecvTunnel_VirtualAuth;

  if Sender.UserDefine.BigStreamBatchList.Count > 0 then
    begin
      p := RT.BigStreamBatchList.Last;
      p^.Source.Position := p^.Source.Size;
      p^.Source.CopyFrom(InData, InData.Size);
      if (p^.Source.Size >= BigStreamTotal) then
        begin
          p^.Source.Position := 0;
          p^.SourceMD5 := umlStreamMD5(p^.Source);

          if p^.CompletedBackcallPtr <> 0 then
            begin
              de := TDFE.Create;
              de.WriteMD5(p^.RemoteMD5);
              de.WriteMD5(p^.SourceMD5);
              de.WritePointer(p^.CompletedBackcallPtr);
              SendTunnel.SendStreamNotifyCmd(C_PostBatchStreamDone, de);
              DisposeObject(de);
            end;
        end;
    end;
end;

procedure TDTClient_VirtualAuth.Command_ClearBatchStream(Sender: TPeerIO; InData: TDFE);
var
  RT: TClient_RecvTunnel_VirtualAuth;
  p: PBigStreamBatchPostData;
  de: TDFE;
begin
  if not LinkOk then
      exit;
  RT := Sender.UserDefine as TClient_RecvTunnel_VirtualAuth;
  RT.BigStreamBatchList.Clear;
end;

procedure TDTClient_VirtualAuth.Command_PostBatchStreamDone(Sender: TPeerIO; InData: TDFE);
var
  RT: TClient_RecvTunnel_VirtualAuth;
  rMD5, sMD5: TMD5;
  backCallVal: UInt64;
  backCallValPtr: POnStateStruct;
  MD5Verify: Boolean;
begin
  if not LinkOk then
      exit;
  RT := Sender.UserDefine as TClient_RecvTunnel_VirtualAuth;

  rMD5 := InData.Reader.ReadMD5;
  sMD5 := InData.Reader.ReadMD5;
  backCallVal := InData.Reader.ReadPointer;

  backCallValPtr := POnStateStruct(Pointer(backCallVal));
  MD5Verify := umlMD5Compare(rMD5, sMD5);

  if backCallValPtr = nil then
      exit;

  try
    if Assigned(backCallValPtr^.On_C) then
        backCallValPtr^.On_C(MD5Verify)
    else if Assigned(backCallValPtr^.On_M) then
        backCallValPtr^.On_M(MD5Verify)
    else if Assigned(backCallValPtr^.On_P) then
        backCallValPtr^.On_P(MD5Verify);
  except
  end;

  try
      Dispose(backCallValPtr);
  except
  end;
end;

procedure TDTClient_VirtualAuth.Command_GetBatchStreamState(Sender: TPeerIO; InData, OutData: TDFE);
var
  RT: TClient_RecvTunnel_VirtualAuth;
  i: Integer;
  p: PBigStreamBatchPostData;

  de: TDFE;
begin
  if not LinkOk then
      exit;
  RT := Sender.UserDefine as TClient_RecvTunnel_VirtualAuth;

  for i := 0 to RT.BigStreamBatchList.Count - 1 do
    begin
      p := RT.BigStreamBatchList[i];
      de := TDFE.Create;
      p^.Encode(de);
      OutData.WriteDataFrame(de);
      DisposeObject(de);
    end;
end;

procedure TDTClient_VirtualAuth.AsyncSendConnectResult(const cState: Boolean);
begin
  if not cState then
    begin
      try
        if Assigned(FAsyncOnResult_C) then
            FAsyncOnResult_C(False)
        else if Assigned(FAsyncOnResult_M) then
            FAsyncOnResult_M(False)
        else if Assigned(FAsyncOnResult_P) then
            FAsyncOnResult_P(False);
      except
      end;
      FAsyncConnectAddr := '';
      FAsyncConnRecvPort := 0;
      FAsyncConnSendPort := 0;
      FAsyncOnResult_C := nil;
      FAsyncOnResult_M := nil;
      FAsyncOnResult_P := nil;
      exit;
    end;

  RecvTunnel.AsyncConnectM(FAsyncConnectAddr, FAsyncConnRecvPort, AsyncRecvConnectResult);
end;

procedure TDTClient_VirtualAuth.AsyncRecvConnectResult(const cState: Boolean);
begin
  if not cState then
      SendTunnel.Disconnect;

  try
    if Assigned(FAsyncOnResult_C) then
        FAsyncOnResult_C(cState)
    else if Assigned(FAsyncOnResult_M) then
        FAsyncOnResult_M(cState)
    else if Assigned(FAsyncOnResult_P) then
        FAsyncOnResult_P(cState);
  except
  end;

  FAsyncConnectAddr := '';
  FAsyncConnRecvPort := 0;
  FAsyncConnSendPort := 0;
  FAsyncOnResult_C := nil;
  FAsyncOnResult_M := nil;
  FAsyncOnResult_P := nil;
end;

procedure TDTClient_VirtualAuth.UserLogin_OnResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: TDFE);
var
  r: Boolean;
  p: POnStateStruct;
begin
  p := Param1;
  r := False;
  if Result_.Count > 0 then
    begin
      r := Result_.ReadBool(0);
      FSendTunnel.ClientIO.Print(Result_.ReadString(1));
    end;

  if Assigned(p^.On_C) then
      p^.On_C(r)
  else if Assigned(p^.On_M) then
      p^.On_M(r)
  else if Assigned(p^.On_P) then
      p^.On_P(r);

  Dispose(p);
end;

procedure TDTClient_VirtualAuth.UserLogin_OnFailed(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: TDFE);
var
  p: POnStateStruct;
begin
  p := Param1;
  if Assigned(p^.On_C) then
      p^.On_C(False)
  else if Assigned(p^.On_M) then
      p^.On_M(False)
  else if Assigned(p^.On_P) then
      p^.On_P(False);

  Dispose(p);
end;

procedure TDTClient_VirtualAuth.RegisterUser_OnResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: TDFE);
var
  r: Boolean;
  p: POnStateStruct;
begin
  p := Param1;
  r := False;
  if Result_.Count > 0 then
    begin
      r := Result_.ReadBool(0);
      FSendTunnel.ClientIO.Print(Result_.ReadString(1));
    end;

  if Assigned(p^.On_C) then
      p^.On_C(r)
  else if Assigned(p^.On_M) then
      p^.On_M(r)
  else if Assigned(p^.On_P) then
      p^.On_P(r);

  Dispose(p);
end;

procedure TDTClient_VirtualAuth.RegisterUser_OnFailed(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: TDFE);
var
  p: POnStateStruct;
begin
  p := Param1;
  if Assigned(p^.On_C) then
      p^.On_C(False)
  else if Assigned(p^.On_M) then
      p^.On_M(False)
  else if Assigned(p^.On_P) then
      p^.On_P(False);

  Dispose(p);
end;

procedure TDTClient_VirtualAuth.TunnelLink_OnResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: TDFE);
var
  r: Boolean;
  p: POnStateStruct;
begin
  p := Param1;
  r := False;
  if Result_.Count > 0 then
    begin
      r := Result_.ReadBool(0);
      FSendTunnel.ClientIO.Print(Result_.ReadString(1));

      if r then
        begin
          if Result_.Count >= 2 then
              FFileSystem := Result_.ReadBool(2)
          else
              FFileSystem := True;
          TClient_SendTunnel_VirtualAuth(FSendTunnel.ClientIO.UserDefine).Client := Self;
          TClient_SendTunnel_VirtualAuth(FSendTunnel.ClientIO.UserDefine).RecvTunnel := TClient_RecvTunnel_VirtualAuth(FRecvTunnel.ClientIO.UserDefine);

          TClient_RecvTunnel_VirtualAuth(FRecvTunnel.ClientIO.UserDefine).Client := Self;
          TClient_RecvTunnel_VirtualAuth(FRecvTunnel.ClientIO.UserDefine).SendTunnel := TClient_SendTunnel_VirtualAuth(FSendTunnel.ClientIO.UserDefine);

          FLinkOk := True;
        end;
    end;

  if Assigned(p^.On_C) then
      p^.On_C(r)
  else if Assigned(p^.On_M) then
      p^.On_M(r)
  else if Assigned(p^.On_P) then
      p^.On_P(r);

  Dispose(p);
end;

procedure TDTClient_VirtualAuth.TunnelLink_OnFailed(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: TDFE);
var
  p: POnStateStruct;
begin
  p := Param1;
  if Assigned(p^.On_C) then
      p^.On_C(False)
  else if Assigned(p^.On_M) then
      p^.On_M(False)
  else if Assigned(p^.On_P) then
      p^.On_P(False);

  Dispose(p);
end;

constructor TDTClient_VirtualAuth.Create(RecvTunnel_, SendTunnel_: TZNet_Client);
begin
  inherited Create;
  FRecvTunnel := RecvTunnel_;
  FRecvTunnel.NotyifyInterface := Self;
  FRecvTunnel.PeerClientUserDefineClass := TClient_RecvTunnel_VirtualAuth;

  FSendTunnel := SendTunnel_;
  FSendTunnel.NotyifyInterface := Self;
  FSendTunnel.PeerClientUserDefineClass := TClient_SendTunnel_VirtualAuth;

  FRecvTunnel.DoubleChannelFramework := Self;
  FSendTunnel.DoubleChannelFramework := Self;

  FFileSystem := False;
  FAutoFreeTunnel := False;

  FLinkOk := False;
  FWaitCommandTimeout := 5000;

  FCurrentStream := nil;
  FCurrentReceiveStreamFileName := '';

  FCadencerEngine := TCadencer.Create;
  FCadencerEngine.OnProgress := CadencerProgress;
  FProgressEngine := TN_Progress_Tool.Create;

  FLastCadencerTime := 0;
  FServerDelay := 0;

  FAsyncConnectAddr := '';
  FAsyncConnRecvPort := 0;
  FAsyncConnSendPort := 0;
  FAsyncOnResult_C := nil;
  FAsyncOnResult_M := nil;
  FAsyncOnResult_P := nil;

  SwitchAsDefaultPerformance;
end;

destructor TDTClient_VirtualAuth.Destroy;
begin
  if FCurrentStream <> nil then
    begin
      DisposeObject(FCurrentStream);
      FCurrentStream := nil;
    end;
  FCurrentReceiveStreamFileName := '';

  FRecvTunnel.NotyifyInterface := nil;
  FSendTunnel.NotyifyInterface := nil;
  if FAutoFreeTunnel then
    begin
      DisposeObjectAndNil(FRecvTunnel);
      DisposeObjectAndNil(FSendTunnel);
    end;
  DisposeObject([FCadencerEngine, FProgressEngine]);

  inherited Destroy;
end;

function TDTClient_VirtualAuth.Connected: Boolean;
begin
  try
      Result := FSendTunnel.Connected and FRecvTunnel.Connected;
  except
      Result := False;
  end;
end;

function TDTClient_VirtualAuth.IOBusy: Boolean;
begin
  try
      Result := FSendTunnel.IOBusy and FRecvTunnel.IOBusy;
  except
      Result := True;
  end;
end;

procedure TDTClient_VirtualAuth.SwitchAsMaxPerformance;
begin
  FRecvTunnel.SwitchMaxPerformance;
  FSendTunnel.SwitchMaxPerformance;
end;

procedure TDTClient_VirtualAuth.SwitchAsMaxSecurity;
begin
  FRecvTunnel.SwitchMaxSecurity;
  FSendTunnel.SwitchMaxSecurity;
end;

procedure TDTClient_VirtualAuth.SwitchAsDefaultPerformance;
begin
  FRecvTunnel.SwitchDefaultPerformance;
  FSendTunnel.SwitchDefaultPerformance;
end;

procedure TDTClient_VirtualAuth.Progress;
var
  p2pVMDone: Boolean;
begin
  FCadencerEngine.Progress;

  try
    p2pVMDone := False;

    if (not p2pVMDone) and (FRecvTunnel is TZNet_WithP2PVM_Client) then
      if FRecvTunnel.ClientIO <> nil then
        begin
          FRecvTunnel.ProgressWaitSend(FRecvTunnel.ClientIO);
          p2pVMDone := True;
        end;
    FRecvTunnel.Progress;

    if (not p2pVMDone) and (FSendTunnel is TZNet_WithP2PVM_Client) then
      if FSendTunnel.ClientIO <> nil then
        begin
          FSendTunnel.ProgressWaitSend(FSendTunnel.ClientIO);
          p2pVMDone := True;
        end;
    FSendTunnel.Progress;

    if not Connected then
        FLinkOk := False;
  except
  end;
end;

procedure TDTClient_VirtualAuth.CadencerProgress(Sender: TObject; const deltaTime, newTime: Double);
begin
  FProgressEngine.Progress(deltaTime);
end;

function TDTClient_VirtualAuth.Connect(addr: SystemString; const RecvPort, SendPort: Word): Boolean;
var
  t: Cardinal;
begin
  Result := False;
  Disconnect;

  if not FSendTunnel.Connect(addr, SendPort) then
    begin
      DoStatus('connect %s failed!', [addr]);
      exit;
    end;
  if not FRecvTunnel.Connect(addr, RecvPort) then
    begin
      DoStatus('connect %s failed!', [addr]);
      exit;
    end;

  t := GetTimeTick + 10000;
  while not RemoteInited do
    begin
      if TCore_Thread.GetTickCount > t then
          Break;
      if not Connected then
          Break;
      Progress;
    end;

  Result := Connected;
end;

procedure TDTClient_VirtualAuth.AsyncConnectC(addr: SystemString; const RecvPort, SendPort: Word; OnResult: TOnState_C);
begin
  Disconnect;
  FAsyncConnectAddr := addr;
  FAsyncConnRecvPort := RecvPort;
  FAsyncConnSendPort := SendPort;
  FAsyncOnResult_C := OnResult;
  FAsyncOnResult_M := nil;
  FAsyncOnResult_P := nil;
  SendTunnel.AsyncConnectM(FAsyncConnectAddr, FAsyncConnSendPort, AsyncSendConnectResult);
end;

procedure TDTClient_VirtualAuth.AsyncConnectM(addr: SystemString; const RecvPort, SendPort: Word; OnResult: TOnState_M);
begin
  Disconnect;
  FAsyncConnectAddr := addr;
  FAsyncConnRecvPort := RecvPort;
  FAsyncConnSendPort := SendPort;
  FAsyncOnResult_C := nil;
  FAsyncOnResult_M := OnResult;
  FAsyncOnResult_P := nil;
  SendTunnel.AsyncConnectM(FAsyncConnectAddr, FAsyncConnSendPort, AsyncSendConnectResult);
end;

procedure TDTClient_VirtualAuth.AsyncConnectP(addr: SystemString; const RecvPort, SendPort: Word; OnResult: TOnState_P);
begin
  Disconnect;
  FAsyncConnectAddr := addr;
  FAsyncConnRecvPort := RecvPort;
  FAsyncConnSendPort := SendPort;
  FAsyncOnResult_C := nil;
  FAsyncOnResult_M := nil;
  FAsyncOnResult_P := OnResult;

  SendTunnel.AsyncConnectM(FAsyncConnectAddr, FAsyncConnSendPort, AsyncSendConnectResult);
end;

procedure TDTClient_VirtualAuth.AsyncConnectC(addr: SystemString; const RecvPort, SendPort: Word; Param1: Pointer; Param2: TObject; OnResult: TOnParamState_C);
var
  ParamBridge: TState_Param_Bridge;
begin
  ParamBridge := TState_Param_Bridge.Create;
  ParamBridge.Param1 := Param1;
  ParamBridge.Param2 := Param2;
  ParamBridge.OnNotifyC := OnResult;
  AsyncConnectM(addr, RecvPort, SendPort, ParamBridge.DoStateResult);
end;

procedure TDTClient_VirtualAuth.AsyncConnectM(addr: SystemString; const RecvPort, SendPort: Word; Param1: Pointer; Param2: TObject; OnResult: TOnParamState_M);
var
  ParamBridge: TState_Param_Bridge;
begin
  ParamBridge := TState_Param_Bridge.Create;
  ParamBridge.Param1 := Param1;
  ParamBridge.Param2 := Param2;
  ParamBridge.OnNotifyM := OnResult;
  AsyncConnectM(addr, RecvPort, SendPort, ParamBridge.DoStateResult);
end;

procedure TDTClient_VirtualAuth.AsyncConnectP(addr: SystemString; const RecvPort, SendPort: Word; Param1: Pointer; Param2: TObject; OnResult: TOnParamState_P);
var
  ParamBridge: TState_Param_Bridge;
begin
  ParamBridge := TState_Param_Bridge.Create;
  ParamBridge.Param1 := Param1;
  ParamBridge.Param2 := Param2;
  ParamBridge.OnNotifyP := OnResult;
  AsyncConnectM(addr, RecvPort, SendPort, ParamBridge.DoStateResult);
end;

procedure TDTClient_VirtualAuth.Disconnect;
begin
  if FSendTunnel.ClientIO <> nil then
      FSendTunnel.Disconnect;

  if FRecvTunnel.ClientIO <> nil then
      FRecvTunnel.Disconnect;

  FAsyncConnectAddr := '';
  FAsyncConnRecvPort := 0;
  FAsyncConnSendPort := 0;
  FAsyncOnResult_C := nil;
  FAsyncOnResult_M := nil;
  FAsyncOnResult_P := nil;
end;

function TDTClient_VirtualAuth.UserLogin(UserID, Passwd: SystemString): Boolean;
var
  sendDE, resDE: TDFE;
begin
  Result := False;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;
  sendDE := TDFE.Create;
  resDE := TDFE.Create;

  sendDE.WriteCardinal(FRecvTunnel.RemoteID);
  sendDE.WriteString(UserID);
  sendDE.WriteString(Passwd);
  FSendTunnel.WaitSendStreamCmd(C_UserLogin, sendDE, resDE, FWaitCommandTimeout * 2);

  if resDE.Count > 0 then
    begin
      Result := resDE.ReadBool(0);
      FSendTunnel.ClientIO.Print(resDE.ReadString(1));
    end;

  DisposeObject(sendDE);
  DisposeObject(resDE);
end;

function TDTClient_VirtualAuth.RegisterUser(UserID, Passwd: SystemString): Boolean;
var
  sendDE, resDE: TDFE;
begin
  Result := False;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;
  sendDE := TDFE.Create;
  resDE := TDFE.Create;

  sendDE.WriteCardinal(FRecvTunnel.RemoteID);
  sendDE.WriteString(UserID);
  sendDE.WriteString(Passwd);
  FSendTunnel.WaitSendStreamCmd(C_RegisterUser, sendDE, resDE, FWaitCommandTimeout * 2);

  if resDE.Count > 0 then
    begin
      Result := resDE.ReadBool(0);
      FSendTunnel.ClientIO.Print(resDE.ReadString(1));
    end;

  DisposeObject(sendDE);
  DisposeObject(resDE);
end;

function TDTClient_VirtualAuth.TunnelLink: Boolean;
var
  sendDE, resDE: TDFE;
begin
  if FLinkOk then
      exit(True);
  FLinkOk := False;
  Result := False;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  SyncCadencer;

  sendDE := TDFE.Create;
  resDE := TDFE.Create;

  sendDE.WriteCardinal(FSendTunnel.RemoteID);
  sendDE.WriteCardinal(FRecvTunnel.RemoteID);

  FSendTunnel.WaitSendStreamCmd(C_TunnelLink, sendDE, resDE, FWaitCommandTimeout);

  if resDE.Count > 0 then
    begin
      Result := resDE.ReadBool(0);
      FSendTunnel.ClientIO.Print(resDE.ReadString(1));

      if Result then
        begin
          if resDE.Count >= 2 then
              FFileSystem := resDE.ReadBool(2)
          else
              FFileSystem := True;
          TClient_SendTunnel_VirtualAuth(FSendTunnel.ClientIO.UserDefine).Client := Self;
          TClient_SendTunnel_VirtualAuth(FSendTunnel.ClientIO.UserDefine).RecvTunnel := TClient_RecvTunnel_VirtualAuth(FRecvTunnel.ClientIO.UserDefine);

          TClient_RecvTunnel_VirtualAuth(FRecvTunnel.ClientIO.UserDefine).Client := Self;
          TClient_RecvTunnel_VirtualAuth(FRecvTunnel.ClientIO.UserDefine).SendTunnel := TClient_SendTunnel_VirtualAuth(FSendTunnel.ClientIO.UserDefine);

          FLinkOk := True;
        end;
    end;

  DisposeObject(sendDE);
  DisposeObject(resDE);
end;

procedure TDTClient_VirtualAuth.UserLoginC(UserID, Passwd: SystemString; On_C: TOnState_C);
var
  sendDE: TDFE;
  p: POnStateStruct;
begin
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;
  sendDE := TDFE.Create;

  sendDE.WriteCardinal(FRecvTunnel.RemoteID);
  sendDE.WriteString(UserID);
  sendDE.WriteString(Passwd);

  new(p);
  p^.Init;
  p^.On_C := On_C;
  FSendTunnel.SendStreamCmdM(C_UserLogin, sendDE, p, nil, UserLogin_OnResult, UserLogin_OnFailed);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.UserLoginM(UserID, Passwd: SystemString; On_M: TOnState_M);
var
  sendDE: TDFE;
  p: POnStateStruct;
begin
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;
  sendDE := TDFE.Create;

  sendDE.WriteCardinal(FRecvTunnel.RemoteID);
  sendDE.WriteString(UserID);
  sendDE.WriteString(Passwd);

  new(p);
  p^.Init;
  p^.On_M := On_M;
  FSendTunnel.SendStreamCmdM(C_UserLogin, sendDE, p, nil, UserLogin_OnResult, UserLogin_OnFailed);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.UserLoginP(UserID, Passwd: SystemString; On_P: TOnState_P);
var
  sendDE: TDFE;
  p: POnStateStruct;
begin
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;
  sendDE := TDFE.Create;

  sendDE.WriteCardinal(FRecvTunnel.RemoteID);
  sendDE.WriteString(UserID);
  sendDE.WriteString(Passwd);

  new(p);
  p^.Init;
  p^.On_P := On_P;
  FSendTunnel.SendStreamCmdM(C_UserLogin, sendDE, p, nil, UserLogin_OnResult, UserLogin_OnFailed);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.RegisterUserC(UserID, Passwd: SystemString; On_C: TOnState_C);
var
  sendDE: TDFE;
  p: POnStateStruct;
begin
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;
  sendDE := TDFE.Create;

  sendDE.WriteCardinal(FRecvTunnel.RemoteID);
  sendDE.WriteString(UserID);
  sendDE.WriteString(Passwd);

  new(p);
  p^.Init;
  p^.On_C := On_C;
  FSendTunnel.SendStreamCmdM(C_RegisterUser, sendDE, p, nil, RegisterUser_OnResult, RegisterUser_OnFailed);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.RegisterUserM(UserID, Passwd: SystemString; On_M: TOnState_M);
var
  sendDE: TDFE;
  p: POnStateStruct;
begin
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;
  sendDE := TDFE.Create;

  sendDE.WriteCardinal(FRecvTunnel.RemoteID);
  sendDE.WriteString(UserID);
  sendDE.WriteString(Passwd);

  new(p);
  p^.Init;
  p^.On_M := On_M;
  FSendTunnel.SendStreamCmdM(C_RegisterUser, sendDE, p, nil, RegisterUser_OnResult, RegisterUser_OnFailed);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.RegisterUserP(UserID, Passwd: SystemString; On_P: TOnState_P);
var
  sendDE: TDFE;
  p: POnStateStruct;
begin
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;
  sendDE := TDFE.Create;

  sendDE.WriteCardinal(FRecvTunnel.RemoteID);
  sendDE.WriteString(UserID);
  sendDE.WriteString(Passwd);

  new(p);
  p^.Init;
  p^.On_P := On_P;
  FSendTunnel.SendStreamCmdM(C_RegisterUser, sendDE, p, nil, RegisterUser_OnResult, RegisterUser_OnFailed);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.TunnelLinkC(On_C: TOnState_C);
var
  sendDE: TDFE;
  p: POnStateStruct;
begin
  if FLinkOk then
      exit;

  FLinkOk := False;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  SyncCadencer;

  sendDE := TDFE.Create;

  sendDE.WriteCardinal(FSendTunnel.RemoteID);
  sendDE.WriteCardinal(FRecvTunnel.RemoteID);
  new(p);
  p^.Init;
  p^.On_C := On_C;
  FSendTunnel.SendStreamCmdM(C_TunnelLink, sendDE, p, nil, TunnelLink_OnResult, TunnelLink_OnFailed);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.TunnelLinkM(On_M: TOnState_M);
var
  sendDE: TDFE;
  p: POnStateStruct;
begin
  if FLinkOk then
      exit;

  FLinkOk := False;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  SyncCadencer;

  sendDE := TDFE.Create;

  sendDE.WriteCardinal(FSendTunnel.RemoteID);
  sendDE.WriteCardinal(FRecvTunnel.RemoteID);
  new(p);
  p^.Init;
  p^.On_M := On_M;
  FSendTunnel.SendStreamCmdM(C_TunnelLink, sendDE, p, nil, TunnelLink_OnResult, TunnelLink_OnFailed);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.TunnelLinkP(On_P: TOnState_P);
var
  sendDE: TDFE;
  p: POnStateStruct;
begin
  if FLinkOk then
      exit;

  FLinkOk := False;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  SyncCadencer;

  sendDE := TDFE.Create;

  sendDE.WriteCardinal(FSendTunnel.RemoteID);
  sendDE.WriteCardinal(FRecvTunnel.RemoteID);
  new(p);
  p^.Init;
  p^.On_P := On_P;
  FSendTunnel.SendStreamCmdM(C_TunnelLink, sendDE, p, nil, TunnelLink_OnResult, TunnelLink_OnFailed);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.SyncCadencer;
var
  sendDE: TDFE;
begin
  sendDE := TDFE.Create;

  FCadencerEngine.Progress;
  FLastCadencerTime := FCadencerEngine.CurrentTime;
  FServerDelay := 0;
  sendDE.WriteDouble(FLastCadencerTime);
  FSendTunnel.SendStreamCmdM(C_GetCurrentCadencer, sendDE, GetCurrentCadencer_StreamResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.GetFileTimeM(RemoteFilename: SystemString; On_CResult: TOnStream_M);
var
  sendDE: TDFE;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  sendDE := TDFE.Create;
  sendDE.WriteString(RemoteFilename);
  FSendTunnel.SendStreamCmdM(C_GetFileTime, sendDE, On_CResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.GetFileTimeP(RemoteFilename: SystemString; On_CResult: TOnStream_P);
var
  sendDE: TDFE;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  sendDE := TDFE.Create;
  sendDE.WriteString(RemoteFilename);
  FSendTunnel.SendStreamCmdP(C_GetFileTime, sendDE, On_CResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.GetFileInfoC(fileName: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TGetFileInfo_C_VirtualAuth);
var
  sendDE: TDFE;
  p: PGetFileInfoStruct_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  sendDE := TDFE.Create;
  sendDE.WriteString(fileName);
  new(p);
  p^.UserData := UserData;
  p^.UserObject := UserObject;
  p^.fileName := fileName;
  p^.OnComplete_C := OnComplete;
  p^.OnComplete_M := nil;
  p^.OnComplete_P := nil;
  sendDE.WritePointer(p);

  FSendTunnel.SendStreamCmdM(C_GetFileInfo, sendDE, p, nil, GetFileInfo_StreamParamResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.GetFileInfoM(fileName: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TGetFileInfo_M_VirtualAuth);
var
  sendDE: TDFE;
  p: PGetFileInfoStruct_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  sendDE := TDFE.Create;
  sendDE.WriteString(fileName);
  new(p);
  p^.UserData := UserData;
  p^.UserObject := UserObject;
  p^.fileName := fileName;
  p^.OnComplete_C := nil;
  p^.OnComplete_M := OnComplete;
  p^.OnComplete_P := nil;
  sendDE.WritePointer(p);

  FSendTunnel.SendStreamCmdM(C_GetFileInfo, sendDE, p, nil, GetFileInfo_StreamParamResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.GetFileInfoP(fileName: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TGetFileInfo_P_VirtualAuth);
var
  sendDE: TDFE;
  p: PGetFileInfoStruct_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  sendDE := TDFE.Create;
  sendDE.WriteString(fileName);
  new(p);
  p^.UserData := UserData;
  p^.UserObject := UserObject;
  p^.fileName := fileName;
  p^.OnComplete_C := nil;
  p^.OnComplete_M := nil;
  p^.OnComplete_P := OnComplete;
  sendDE.WritePointer(p);

  FSendTunnel.SendStreamCmdM(C_GetFileInfo, sendDE, p, nil, GetFileInfo_StreamParamResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.GetFileMD5C(fileName: SystemString; const StartPos, EndPos: Int64;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TFileMD5_C_VirtualAuth);
var
  sendDE: TDFE;
  p: PFileMD5Struct_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  sendDE := TDFE.Create;
  sendDE.WriteString(fileName);
  sendDE.WriteInt64(StartPos);
  sendDE.WriteInt64(EndPos);
  new(p);
  p^.UserData := UserData;
  p^.UserObject := UserObject;
  p^.fileName := fileName;
  p^.StartPos := StartPos;
  p^.EndPos := EndPos;
  p^.OnComplete_C := OnComplete;
  p^.OnComplete_M := nil;
  p^.OnComplete_P := nil;
  sendDE.WritePointer(p);

  FSendTunnel.SendStreamCmdM(C_GetFileMD5, sendDE, p, nil, GetFileMD5_StreamParamResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.GetFileMD5M(fileName: SystemString; const StartPos, EndPos: Int64;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TFileMD5_M_VirtualAuth);
var
  sendDE: TDFE;
  p: PFileMD5Struct_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  sendDE := TDFE.Create;
  sendDE.WriteString(fileName);
  sendDE.WriteInt64(StartPos);
  sendDE.WriteInt64(EndPos);
  new(p);
  p^.UserData := UserData;
  p^.UserObject := UserObject;
  p^.fileName := fileName;
  p^.StartPos := StartPos;
  p^.EndPos := EndPos;
  p^.OnComplete_C := nil;
  p^.OnComplete_M := OnComplete;
  p^.OnComplete_P := nil;
  sendDE.WritePointer(p);

  FSendTunnel.SendStreamCmdM(C_GetFileMD5, sendDE, p, nil, GetFileMD5_StreamParamResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.GetFileMD5P(fileName: SystemString; const StartPos, EndPos: Int64;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TFileMD5_P_VirtualAuth);
var
  sendDE: TDFE;
  p: PFileMD5Struct_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  sendDE := TDFE.Create;
  sendDE.WriteString(fileName);
  sendDE.WriteInt64(StartPos);
  sendDE.WriteInt64(EndPos);
  new(p);
  p^.UserData := UserData;
  p^.UserObject := UserObject;
  p^.fileName := fileName;
  p^.StartPos := StartPos;
  p^.EndPos := EndPos;
  p^.OnComplete_C := nil;
  p^.OnComplete_M := nil;
  p^.OnComplete_P := OnComplete;
  sendDE.WritePointer(p);

  FSendTunnel.SendStreamCmdM(C_GetFileMD5, sendDE, p, nil, GetFileMD5_StreamParamResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.GetFileC(fileName, saveToPath: SystemString;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileComplete_C_VirtualAuth);
begin
  GetFileC(fileName, 0, saveToPath, UserData, UserObject, OnComplete_C);
end;

procedure TDTClient_VirtualAuth.GetFileM(fileName, saveToPath: SystemString;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileComplete_M_VirtualAuth);
begin
  GetFileM(fileName, 0, saveToPath, UserData, UserObject, OnComplete_M);
end;

procedure TDTClient_VirtualAuth.GetFileP(fileName, saveToPath: SystemString;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileComplete_P_VirtualAuth);
begin
  GetFileP(fileName, 0, saveToPath, UserData, UserObject, OnComplete_P);
end;

function TDTClient_VirtualAuth.GetFile(fileName, saveToPath: SystemString): Boolean;
begin
  Result := GetFile(fileName, 0, saveToPath);
end;

procedure TDTClient_VirtualAuth.GetFileC(fileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileComplete_C_VirtualAuth);
var
  sendDE: TDFE;
  p: PRemoteFileBackcall_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  sendDE := TDFE.Create;

  sendDE.WriteString(fileName);
  sendDE.WriteInt64(StartPos);
  sendDE.WriteString(saveToPath);
  new(p);
  p^.UserData := UserData;
  p^.UserObject := UserObject;
  p^.OnComplete_C := OnComplete_C;
  p^.OnComplete_M := nil;
  p^.OnComplete_P := nil;
  sendDE.WritePointer(p);

  FSendTunnel.SendStreamCmdM(C_GetFile, sendDE, p, nil, GetFile_StreamParamResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.GetFileM(fileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileComplete_M_VirtualAuth);
var
  sendDE: TDFE;
  p: PRemoteFileBackcall_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  sendDE := TDFE.Create;

  sendDE.WriteString(fileName);
  sendDE.WriteInt64(StartPos);
  sendDE.WriteString(saveToPath);
  new(p);
  p^.UserData := UserData;
  p^.UserObject := UserObject;
  p^.OnComplete_C := nil;
  p^.OnComplete_M := OnComplete_M;
  p^.OnComplete_P := nil;
  sendDE.WritePointer(p);

  FSendTunnel.SendStreamCmdM(C_GetFile, sendDE, p, nil, GetFile_StreamParamResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.GetFileP(fileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileComplete_P_VirtualAuth);
var
  sendDE: TDFE;
  p: PRemoteFileBackcall_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  sendDE := TDFE.Create;

  sendDE.WriteString(fileName);
  sendDE.WriteInt64(StartPos);
  sendDE.WriteString(saveToPath);
  new(p);
  p^.UserData := UserData;
  p^.UserObject := UserObject;
  p^.OnComplete_C := nil;
  p^.OnComplete_M := nil;
  p^.OnComplete_P := OnComplete_P;
  sendDE.WritePointer(p);

  FSendTunnel.SendStreamCmdM(C_GetFile, sendDE, p, nil, GetFile_StreamParamResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.GetFileAsC(fileName, saveFileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileComplete_C_VirtualAuth);
var
  sendDE: TDFE;
  p: PRemoteFileBackcall_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  sendDE := TDFE.Create;

  sendDE.WriteString(fileName);
  sendDE.WriteString(saveFileName);
  sendDE.WriteInt64(StartPos);
  sendDE.WriteString(saveToPath);
  new(p);
  p^.UserData := UserData;
  p^.UserObject := UserObject;
  p^.OnComplete_C := OnComplete_C;
  p^.OnComplete_M := nil;
  p^.OnComplete_P := nil;
  sendDE.WritePointer(p);

  FSendTunnel.SendStreamCmdM(C_GetFileAs, sendDE, p, nil, GetFile_StreamParamResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.GetFileAsM(fileName, saveFileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileComplete_M_VirtualAuth);
var
  sendDE: TDFE;
  p: PRemoteFileBackcall_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  sendDE := TDFE.Create;

  sendDE.WriteString(fileName);
  sendDE.WriteString(saveFileName);
  sendDE.WriteInt64(StartPos);
  sendDE.WriteString(saveToPath);
  new(p);
  p^.UserData := UserData;
  p^.UserObject := UserObject;
  p^.OnComplete_C := nil;
  p^.OnComplete_M := OnComplete_M;
  p^.OnComplete_P := nil;
  sendDE.WritePointer(p);

  FSendTunnel.SendStreamCmdM(C_GetFileAs, sendDE, p, nil, GetFile_StreamParamResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.GetFileAsP(fileName, saveFileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileComplete_P_VirtualAuth);
var
  sendDE: TDFE;
  p: PRemoteFileBackcall_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  sendDE := TDFE.Create;

  sendDE.WriteString(fileName);
  sendDE.WriteString(saveFileName);
  sendDE.WriteInt64(StartPos);
  sendDE.WriteString(saveToPath);
  new(p);
  p^.UserData := UserData;
  p^.UserObject := UserObject;
  p^.OnComplete_C := nil;
  p^.OnComplete_M := nil;
  p^.OnComplete_P := OnComplete_P;
  sendDE.WritePointer(p);

  FSendTunnel.SendStreamCmdM(C_GetFileAs, sendDE, p, nil, GetFile_StreamParamResult);
  DisposeObject(sendDE);
end;

function TDTClient_VirtualAuth.GetFile(fileName: SystemString; StartPos: Int64; saveToPath: SystemString): Boolean;
var
  sendDE, resDE: TDFE;
begin
  Result := False;
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  sendDE := TDFE.Create;
  resDE := TDFE.Create;

  sendDE.WriteString(fileName);
  sendDE.WriteInt64(StartPos);
  sendDE.WriteString(saveToPath);
  sendDE.WritePointer(0);

  FSendTunnel.WaitSendStreamCmd(C_GetFile, sendDE, resDE, FWaitCommandTimeout);

  if resDE.Count > 0 then
    begin
      Result := resDE.Reader.ReadBool;
      FSendTunnel.ClientIO.Print(resDE.Reader.ReadString);
    end;

  DisposeObject(sendDE);
  DisposeObject(resDE);
end;

procedure TDTClient_VirtualAuth.GetFileFragmentDataC(fileName: SystemString; StartPos, EndPos: Int64;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileFragmentData_C_VirtualAuth);
var
  sendDE: TDFE;
  p: PFileFragmentDataBackcall_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  new(p);
  p^.UserData := UserData;
  p^.UserObject := UserObject;
  p^.fileName := fileName;
  p^.StartPos := StartPos;
  p^.EndPos := EndPos;
  p^.OnComplete_C := OnComplete_C;
  p^.OnComplete_M := nil;
  p^.OnComplete_P := nil;

  sendDE := TDFE.Create;

  sendDE.WriteString(fileName);
  sendDE.WriteInt64(StartPos);
  sendDE.WriteInt64(EndPos);
  sendDE.WritePointer(p);

  FSendTunnel.SendStreamCmdM(C_GetFileFragmentData, sendDE, p, nil, GetFileFragmentData_StreamParamResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.GetFileFragmentDataM(fileName: SystemString; StartPos, EndPos: Int64;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileFragmentData_M_VirtualAuth);
var
  sendDE: TDFE;
  p: PFileFragmentDataBackcall_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  new(p);
  p^.UserData := UserData;
  p^.UserObject := UserObject;
  p^.fileName := fileName;
  p^.StartPos := StartPos;
  p^.EndPos := EndPos;
  p^.OnComplete_C := nil;
  p^.OnComplete_M := OnComplete_M;
  p^.OnComplete_P := nil;

  sendDE := TDFE.Create;

  sendDE.WriteString(fileName);
  sendDE.WriteInt64(StartPos);
  sendDE.WriteInt64(EndPos);
  sendDE.WritePointer(p);

  FSendTunnel.SendStreamCmdM(C_GetFileFragmentData, sendDE, p, nil, GetFileFragmentData_StreamParamResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.GetFileFragmentDataP(fileName: SystemString; StartPos, EndPos: Int64;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileFragmentData_P_VirtualAuth);
var
  sendDE: TDFE;
  p: PFileFragmentDataBackcall_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  new(p);
  p^.UserData := UserData;
  p^.UserObject := UserObject;
  p^.fileName := fileName;
  p^.StartPos := StartPos;
  p^.EndPos := EndPos;
  p^.OnComplete_C := nil;
  p^.OnComplete_M := nil;
  p^.OnComplete_P := OnComplete_P;

  sendDE := TDFE.Create;

  sendDE.WriteString(fileName);
  sendDE.WriteInt64(StartPos);
  sendDE.WriteInt64(EndPos);
  sendDE.WritePointer(p);

  FSendTunnel.SendStreamCmdM(C_GetFileFragmentData, sendDE, p, nil, GetFileFragmentData_StreamParamResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.AutomatedDownloadFileC(remoteFile, localFile: U_String; OnDownloadDone: TFileComplete_C_VirtualAuth);
var
  tmp: TAutomatedDownloadFile_Struct_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  tmp := TAutomatedDownloadFile_Struct_VirtualAuth.Create;
  tmp.remoteFile := remoteFile;
  tmp.localFile := localFile;
  tmp.OnDownloadDoneC := OnDownloadDone;
  tmp.Client := Self;

  GetFileInfoM(umlGetFileName(remoteFile), nil, nil, tmp.DoResult_GetFileInfo);
end;

procedure TDTClient_VirtualAuth.AutomatedDownloadFileM(remoteFile, localFile: U_String; OnDownloadDone: TFileComplete_M_VirtualAuth);
var
  tmp: TAutomatedDownloadFile_Struct_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  tmp := TAutomatedDownloadFile_Struct_VirtualAuth.Create;
  tmp.remoteFile := remoteFile;
  tmp.localFile := localFile;
  tmp.OnDownloadDoneM := OnDownloadDone;
  tmp.Client := Self;

  GetFileInfoM(umlGetFileName(remoteFile), nil, nil, tmp.DoResult_GetFileInfo);
end;

procedure TDTClient_VirtualAuth.AutomatedDownloadFileP(remoteFile, localFile: U_String; OnDownloadDone: TFileComplete_P_VirtualAuth);
var
  tmp: TAutomatedDownloadFile_Struct_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  tmp := TAutomatedDownloadFile_Struct_VirtualAuth.Create;
  tmp.remoteFile := remoteFile;
  tmp.localFile := localFile;
  tmp.OnDownloadDoneP := OnDownloadDone;
  tmp.Client := Self;

  GetFileInfoM(umlGetFileName(remoteFile), nil, nil, tmp.DoResult_GetFileInfo);
end;

procedure TDTClient_VirtualAuth.PostFile(fileName: SystemString);
var
  sendDE: TDFE;
  fs: TCore_FileStream;
begin
  if not FFileSystem then
      exit;
  if not umlFileExists(fileName) then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  fs := TCore_FileStream.Create(fileName, fmOpenRead or fmShareDenyNone);

  sendDE := TDFE.Create;
  sendDE.WriteString(umlGetFileName(fileName));
  sendDE.WriteInt64(0);
  sendDE.WriteInt64(fs.Size);
  FSendTunnel.SendStreamNotifyCmd(C_PostFileInfo, sendDE);
  DisposeObject(sendDE);

  fs.Position := 0;
  FSendTunnel.SendBigStream(C_PostFile, fs, True);

  sendDE := TDFE.Create;
  FSendTunnel.SendStreamNotifyCmd(C_PostFileOver, sendDE);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.PostFile(l_fileName, r_fileName: SystemString);
var
  sendDE: TDFE;
  fs: TCore_FileStream;
begin
  if not FFileSystem then
      exit;
  if not umlFileExists(l_fileName) then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  fs := TCore_FileStream.Create(l_fileName, fmOpenRead or fmShareDenyNone);

  sendDE := TDFE.Create;
  sendDE.WriteString(r_fileName);
  sendDE.WriteInt64(0);
  sendDE.WriteInt64(fs.Size);
  FSendTunnel.SendStreamNotifyCmd(C_PostFileInfo, sendDE);
  DisposeObject(sendDE);

  fs.Position := 0;
  FSendTunnel.SendBigStream(C_PostFile, fs, True);

  sendDE := TDFE.Create;
  FSendTunnel.SendStreamNotifyCmd(C_PostFileOver, sendDE);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.PostFile(fileName: SystemString; StartPos: Int64);
var
  sendDE: TDFE;
  fs: TCore_FileStream;
begin
  if not FFileSystem then
      exit;
  if not umlFileExists(fileName) then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  fs := TCore_FileStream.Create(fileName, fmOpenRead or fmShareDenyNone);

  sendDE := TDFE.Create;
  sendDE.WriteString(umlGetFileName(fileName));
  sendDE.WriteInt64(StartPos);
  sendDE.WriteInt64(fs.Size);
  FSendTunnel.SendStreamNotifyCmd(C_PostFileInfo, sendDE);
  DisposeObject(sendDE);

  fs.Position := 0;
  FSendTunnel.SendBigStream(C_PostFile, fs, StartPos, True);

  sendDE := TDFE.Create;
  FSendTunnel.SendStreamNotifyCmd(C_PostFileOver, sendDE);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.PostFile(l_fileName, r_fileName: SystemString; StartPos: Int64);
var
  sendDE: TDFE;
  fs: TCore_FileStream;
begin
  if not FFileSystem then
      exit;
  if not umlFileExists(l_fileName) then
      exit;
  if not FSendTunnel.Connected then
      exit;
  if not FRecvTunnel.Connected then
      exit;

  fs := TCore_FileStream.Create(l_fileName, fmOpenRead or fmShareDenyNone);

  sendDE := TDFE.Create;
  sendDE.WriteString(r_fileName);
  sendDE.WriteInt64(StartPos);
  sendDE.WriteInt64(fs.Size);
  FSendTunnel.SendStreamNotifyCmd(C_PostFileInfo, sendDE);
  DisposeObject(sendDE);

  fs.Position := 0;
  FSendTunnel.SendBigStream(C_PostFile, fs, StartPos, True);

  sendDE := TDFE.Create;
  FSendTunnel.SendStreamNotifyCmd(C_PostFileOver, sendDE);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.PostFile(fn: SystemString; stream: TCore_Stream; doneFreeStream: Boolean);
var
  sendDE: TDFE;
begin
  if (not FSendTunnel.Connected) or (not FRecvTunnel.Connected) or (not FFileSystem) then
    begin
      if doneFreeStream then
          DisposeObject(stream);
      exit;
    end;

  sendDE := TDFE.Create;
  sendDE.WriteString(umlGetFileName(fn));
  sendDE.WriteInt64(0);
  sendDE.WriteInt64(stream.Size);
  FSendTunnel.SendStreamNotifyCmd(C_PostFileInfo, sendDE);
  DisposeObject(sendDE);

  stream.Position := 0;
  FSendTunnel.SendBigStream(C_PostFile, stream, doneFreeStream);

  sendDE := TDFE.Create;
  FSendTunnel.SendStreamNotifyCmd(C_PostFileOver, sendDE);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.PostFile(fn: SystemString; stream: TCore_Stream; StartPos: Int64; doneFreeStream: Boolean);
var
  sendDE: TDFE;
begin
  if (not FSendTunnel.Connected) or (not FRecvTunnel.Connected) or (not FFileSystem) then
    begin
      if doneFreeStream then
          DisposeObject(stream);
      exit;
    end;

  sendDE := TDFE.Create;
  sendDE.WriteString(umlGetFileName(fn));
  sendDE.WriteInt64(StartPos);
  sendDE.WriteInt64(stream.Size);
  FSendTunnel.SendStreamNotifyCmd(C_PostFileInfo, sendDE);
  DisposeObject(sendDE);

  stream.Position := 0;
  FSendTunnel.SendBigStream(C_PostFile, stream, StartPos, doneFreeStream);

  sendDE := TDFE.Create;
  FSendTunnel.SendStreamNotifyCmd(C_PostFileOver, sendDE);
  DisposeObject(sendDE);
end;

procedure TDTClient_VirtualAuth.AutomatedUploadFile(localFile: U_String);
var
  tmp: TAutomatedUploadFile_Struct_VirtualAuth;
begin
  if not FFileSystem then
      exit;
  tmp := TAutomatedUploadFile_Struct_VirtualAuth.Create;
  tmp.localFile := localFile;
  tmp.Client := Self;

  GetFileInfoM(umlGetFileName(localFile), nil, nil, tmp.DoResult_GetFileInfo);
end;

procedure TDTClient_VirtualAuth.PostBatchStream(stream: TCore_Stream; doneFreeStream: Boolean);
var
  de: TDFE;
begin
  de := TDFE.Create;

  de.WriteMD5(umlStreamMD5(stream));
  de.WritePointer(0);
  SendTunnel.SendStreamNotifyCmd(C_NewBatchStream, de);
  DisposeObject(de);

  SendTunnel.SendBigStream(C_PostBatchStream, stream, doneFreeStream);
end;

procedure TDTClient_VirtualAuth.PostBatchStreamC(stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_C);
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;

  p := nil;

  if Assigned(OnCompletedBackcall) then
    begin
      new(p);
      p^.Init;
      p^.On_C := OnCompletedBackcall;
    end;

  de.WriteMD5(umlStreamMD5(stream));
  de.WritePointer(p);
  SendTunnel.SendStreamNotifyCmd(C_NewBatchStream, de);
  DisposeObject(de);

  SendTunnel.SendBigStream(C_PostBatchStream, stream, doneFreeStream);
end;

procedure TDTClient_VirtualAuth.PostBatchStreamM(stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_M);
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;

  p := nil;

  if Assigned(OnCompletedBackcall) then
    begin
      new(p);
      p^.Init;
      p^.On_M := OnCompletedBackcall;
    end;

  de.WriteMD5(umlStreamMD5(stream));
  de.WritePointer(p);
  SendTunnel.SendStreamNotifyCmd(C_NewBatchStream, de);
  DisposeObject(de);

  SendTunnel.SendBigStream(C_PostBatchStream, stream, doneFreeStream);
end;

procedure TDTClient_VirtualAuth.PostBatchStreamP(stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_P);
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;

  p := nil;

  if Assigned(OnCompletedBackcall) then
    begin
      new(p);
      p^.Init;
      p^.On_P := OnCompletedBackcall;
    end;

  de.WriteMD5(umlStreamMD5(stream));
  de.WritePointer(p);
  SendTunnel.SendStreamNotifyCmd(C_NewBatchStream, de);
  DisposeObject(de);

  SendTunnel.SendBigStream(C_PostBatchStream, stream, doneFreeStream);
end;

procedure TDTClient_VirtualAuth.ClearBatchStream;
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;
  SendTunnel.SendStreamNotifyCmd(C_ClearBatchStream, de);
  DisposeObject(de);
end;

procedure TDTClient_VirtualAuth.GetBatchStreamStateM(OnResult: TOnStream_M);
var
  de: TDFE;
begin
  de := TDFE.Create;
  SendTunnel.SendStreamCmdM(C_GetBatchStreamState, de, OnResult);
  DisposeObject(de);
end;

procedure TDTClient_VirtualAuth.GetBatchStreamStateM(Param1: Pointer; Param2: TObject; OnResult: TOnStreamParam_M);
var
  de: TDFE;
begin
  de := TDFE.Create;
  SendTunnel.SendStreamCmdM(C_GetBatchStreamState, de, Param1, Param2, OnResult);
  DisposeObject(de);
end;

procedure TDTClient_VirtualAuth.GetBatchStreamStateP(OnResult: TOnStream_P);
var
  de: TDFE;
begin
  de := TDFE.Create;
  SendTunnel.SendStreamCmdP(C_GetBatchStreamState, de, OnResult);
  DisposeObject(de);
end;

procedure TDTClient_VirtualAuth.GetBatchStreamStateP(Param1: Pointer; Param2: TObject; OnResult: TOnStreamParam_P);
var
  de: TDFE;
begin
  de := TDFE.Create;
  SendTunnel.SendStreamCmdP(C_GetBatchStreamState, de, Param1, Param2, OnResult);
  DisposeObject(de);
end;

function TDTClient_VirtualAuth.GetBatchStreamState(Result_: TDFE; TimeOut_: TTimeTick): Boolean;
var
  de: TDFE;
begin
  de := TDFE.Create;
  SendTunnel.WaitSendStreamCmd(C_GetBatchStreamState, de, Result_, TimeOut_);
  Result := Result_.Count > 0;
  DisposeObject(de);
end;

procedure TDTClient_VirtualAuth.RegisterCommand;
begin
  FRecvTunnel.RegisterStreamNotify(C_FileInfo).OnExecute := Command_FileInfo;
  FRecvTunnel.RegisterBigStream(C_PostFile).OnExecute := Command_PostFile;
  FRecvTunnel.RegisterStreamNotify(C_PostFileOver).OnExecute := Command_PostFileOver;
  FRecvTunnel.RegisterCompleteBuffer(C_PostFileFragmentData).OnExecute := Command_PostFileFragmentData;

  FRecvTunnel.RegisterStreamNotify(C_NewBatchStream).OnExecute := Command_NewBatchStream;
  FRecvTunnel.RegisterBigStream(C_PostBatchStream).OnExecute := Command_PostBatchStream;
  FRecvTunnel.RegisterStreamNotify(C_ClearBatchStream).OnExecute := Command_ClearBatchStream;
  FRecvTunnel.RegisterStreamNotify(C_PostBatchStreamDone).OnExecute := Command_PostBatchStreamDone;
  FRecvTunnel.RegisterStream(C_GetBatchStreamState).OnExecute := Command_GetBatchStreamState;
end;

procedure TDTClient_VirtualAuth.UnRegisterCommand;
begin
  FRecvTunnel.DeleteRegistedCMD(C_FileInfo);
  FRecvTunnel.DeleteRegistedCMD(C_PostFile);
  FRecvTunnel.DeleteRegistedCMD(C_PostFileOver);
  FRecvTunnel.DeleteRegistedCMD(C_PostFileFragmentData);

  FRecvTunnel.DeleteRegistedCMD(C_NewBatchStream);
  FRecvTunnel.DeleteRegistedCMD(C_PostBatchStream);
  FRecvTunnel.DeleteRegistedCMD(C_ClearBatchStream);
  FRecvTunnel.DeleteRegistedCMD(C_PostBatchStreamDone);
  FRecvTunnel.DeleteRegistedCMD(C_GetBatchStreamState);
end;

function TDTClient_VirtualAuth.RemoteInited: Boolean;
begin
  Result := FSendTunnel.RemoteInited and FRecvTunnel.RemoteInited;
end;

{ remote file exists }
{ remote md5 support with public store space }
{ restore download }
{ Synchronously waiting to download files from the server to complete }
procedure TDT_P2PVM_VirtualAuth_OnState.Init;
begin
  On_C := nil;
  On_M := nil;
  On_P := nil;
end;

function TDT_P2PVM_VirtualAuth_Service.GetQuietMode: Boolean;
begin
  Result := RecvTunnel.QuietMode and SendTunnel.QuietMode and PhysicsTunnel.QuietMode;
end;

procedure TDT_P2PVM_VirtualAuth_Service.SetQuietMode(const Value: Boolean);
begin
  RecvTunnel.QuietMode := Value;
  SendTunnel.QuietMode := Value;
  PhysicsTunnel.QuietMode := Value;
end;

constructor TDT_P2PVM_VirtualAuth_Service.Create(ServiceClass_: TDTService_VirtualAuthClass; Physics_Class: TZNet_ServerClass);
begin
  inherited Create;
  RecvTunnel := TZNet_WithP2PVM_Server.Create;
  RecvTunnel.QuietMode := True;

  SendTunnel := TZNet_WithP2PVM_Server.Create;
  SendTunnel.QuietMode := True;

  DTService := ServiceClass_.Create(RecvTunnel, SendTunnel);
  DTService.RegisterCommand;
  DTService.SwitchAsDefaultPerformance;

  PhysicsTunnel := Physics_Class.Create;
  PhysicsTunnel.QuietMode := True;
  PhysicsTunnel.AutomatedP2PVMBindService.AddService(RecvTunnel);
  PhysicsTunnel.AutomatedP2PVMBindService.AddService(SendTunnel);
  PhysicsTunnel.AutomatedP2PVMService := True;

  RecvTunnel.PrefixName := 'VA';
  RecvTunnel.Name := 'R';
  SendTunnel.PrefixName := 'VA';
  SendTunnel.Name := 'S';
  PhysicsTunnel.PrefixName := 'Physics';
  PhysicsTunnel.Name := 'p2pVM';
end;

destructor TDT_P2PVM_VirtualAuth_Service.Destroy;
begin
  StopService;
  DisposeObject(RecvTunnel);
  DisposeObject(SendTunnel);
  DisposeObject(DTService);
  DisposeObject(PhysicsTunnel);
  inherited Destroy;
end;

procedure TDT_P2PVM_VirtualAuth_Service.Progress;
begin
  DTService.Progress;
  PhysicsTunnel.Progress;
end;

function TDT_P2PVM_VirtualAuth_Service.StartService(ListenAddr, ListenPort, Auth: SystemString): Boolean;
begin
  StopService;
  RecvTunnel.StartService('::', 1);
  SendTunnel.StartService('::', 2);
  PhysicsTunnel.AutomatedP2PVMAuthToken := Auth;
  Result := PhysicsTunnel.StartService(ListenAddr, umlStrToInt(ListenPort));
  if Result then
      DoStatus('listening %s:%s ok.', [TranslateBindAddr(ListenAddr), ListenPort])
  else
      DoStatus('listening %s:%s failed!', [TranslateBindAddr(ListenAddr), ListenPort]);
end;

procedure TDT_P2PVM_VirtualAuth_Service.StopService;
begin
  PhysicsTunnel.StopService;
  RecvTunnel.StopService;
  SendTunnel.StopService;
end;

procedure TDT_P2PVM_VirtualAuth_Client.DoConnectionResult(const state: Boolean);
begin
  if not state then
    begin
      Connecting := False;

      if Assigned(OnConnectResultState.On_C) then
          OnConnectResultState.On_C(state)
      else if Assigned(OnConnectResultState.On_M) then
          OnConnectResultState.On_M(state)
      else if Assigned(OnConnectResultState.On_P) then
          OnConnectResultState.On_P(state);
      OnConnectResultState.Init;
    end;

  PhysicsTunnel.PrintParam('DT Physics Connect %s', umlBoolToStr(state));
end;

procedure TDT_P2PVM_VirtualAuth_Client.DoAutomatedP2PVMClientConnectionDone(Sender: TZNet; P_IO: TPeerIO);
begin
  PhysicsTunnel.Print('DT p2pVM done.');
  if (LastUser = '') or (LastPasswd = '') then
    begin
      DTClient.TunnelLinkM(DoTunnelLinkResult);
    end
  else if RegisterUserAndLogin then
    begin
      DTClient.RegisterUserM(LastUser, LastPasswd, DoLoginResult);
    end
  else
    begin
      DTClient.UserLoginM(LastUser, LastPasswd, DoLoginResult);
    end;
end;

procedure TDT_P2PVM_VirtualAuth_Client.DoRegisterResult(const state: Boolean);
begin
  DTClient.UserLoginM(LastUser, LastPasswd, DoLoginResult);
end;

procedure TDT_P2PVM_VirtualAuth_Client.DoLoginResult(const state: Boolean);
begin
  if not state then
    begin
      Connecting := False;

      if Assigned(OnConnectResultState.On_C) then
          OnConnectResultState.On_C(state)
      else if Assigned(OnConnectResultState.On_M) then
          OnConnectResultState.On_M(state)
      else if Assigned(OnConnectResultState.On_P) then
          OnConnectResultState.On_P(state);
      OnConnectResultState.Init;
      exit;
    end;

  DTClient.TunnelLinkM(DoTunnelLinkResult);
end;

procedure TDT_P2PVM_VirtualAuth_Client.DoTunnelLinkResult(const state: Boolean);
begin
  if Assigned(OnConnectResultState.On_C) then
      OnConnectResultState.On_C(state)
  else if Assigned(OnConnectResultState.On_M) then
      OnConnectResultState.On_M(state)
  else if Assigned(OnConnectResultState.On_P) then
      OnConnectResultState.On_P(state);
  OnConnectResultState.Init;
  Connecting := False;

  if state then
    begin
      RegisterUserAndLogin := False;

      if AutomatedConnection then
          Reconnection := True;
      if Assigned(OnTunnelLink) then
          OnTunnelLink(Self);
    end;
end;

function TDT_P2PVM_VirtualAuth_Client.GetQuietMode: Boolean;
begin
  Result := RecvTunnel.QuietMode and SendTunnel.QuietMode and PhysicsTunnel.QuietMode;
end;

procedure TDT_P2PVM_VirtualAuth_Client.SetQuietMode(const Value: Boolean);
begin
  RecvTunnel.QuietMode := Value;
  SendTunnel.QuietMode := Value;
  PhysicsTunnel.QuietMode := Value;
end;

constructor TDT_P2PVM_VirtualAuth_Client.Create(ClientClass_: TDTClient_VirtualAuthClass; Physics_Class: TZNet_ClientClass);
begin
  inherited Create;
  OnConnectResultState.Init;
  Connecting := False;
  Reconnection := False;

  RecvTunnel := TZNet_WithP2PVM_Client.Create;
  RecvTunnel.QuietMode := True;

  SendTunnel := TZNet_WithP2PVM_Client.Create;
  SendTunnel.QuietMode := True;

  DTClient := ClientClass_.Create(RecvTunnel, SendTunnel);
  DTClient.RegisterCommand;
  DTClient.SwitchAsDefaultPerformance;

  PhysicsTunnel := Physics_Class.Create;
  PhysicsTunnel.QuietMode := True;
  PhysicsTunnel.AutomatedP2PVMBindClient.AddClient(SendTunnel, '::', 1);
  PhysicsTunnel.AutomatedP2PVMBindClient.AddClient(RecvTunnel, '::', 2);
  PhysicsTunnel.AutomatedP2PVMClient := True;
  PhysicsTunnel.AutomatedP2PVMClientDelayBoot := 0;

  LastAddr := '';
  LastPort := '';
  LastAuth := '';
  LastUser := '';
  LastPasswd := '';

  RegisterUserAndLogin := False;
  AutomatedConnection := True;
  OnTunnelLink := nil;

  RecvTunnel.PrefixName := 'VA';
  RecvTunnel.Name := 'R';
  SendTunnel.PrefixName := 'VA';
  SendTunnel.Name := 'S';
  PhysicsTunnel.PrefixName := 'Physics';
  PhysicsTunnel.Name := 'p2pVM';
end;

destructor TDT_P2PVM_VirtualAuth_Client.Destroy;
begin
  Disconnect;
  DisposeObject(RecvTunnel);
  DisposeObject(SendTunnel);
  DisposeObject(DTClient);
  DisposeObject(PhysicsTunnel);
  inherited Destroy;
end;

procedure TDT_P2PVM_VirtualAuth_Client.Progress;
begin
  DTClient.Progress;
  PhysicsTunnel.Progress;

  if (AutomatedConnection) and ((not PhysicsTunnel.Connected) or (not DTClient.LinkOk)) and (not Connecting) and (Reconnection) then
      Connect(LastAddr, LastPort, LastAuth, LastUser, LastPasswd);
end;

procedure TDT_P2PVM_VirtualAuth_Client.Connect(addr, Port, Auth, User, Passwd: SystemString);
begin
  if Connecting then
      exit;
  Connecting := True;
  if not Reconnection then
    begin
      LastAddr := addr;
      LastPort := Port;
      LastAuth := Auth;
    end;
  LastUser := User;
  LastPasswd := Passwd;
  PhysicsTunnel.AutomatedP2PVMAuthToken := Auth;
  OnConnectResultState.Init;
  PhysicsTunnel.OnAutomatedP2PVMClientConnectionDone_M := DoAutomatedP2PVMClientConnectionDone;
  PhysicsTunnel.AsyncConnectM(addr, umlStrToInt(Port), DoConnectionResult);
end;

procedure TDT_P2PVM_VirtualAuth_Client.Connect_C(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_C);
begin
  if Connecting then
      exit;
  Connecting := True;
  if not Reconnection then
    begin
      LastAddr := addr;
      LastPort := Port;
      LastAuth := Auth;
    end;
  LastUser := User;
  LastPasswd := Passwd;
  PhysicsTunnel.AutomatedP2PVMAuthToken := Auth;
  OnConnectResultState.Init;
  OnConnectResultState.On_C := OnResult;
  PhysicsTunnel.OnAutomatedP2PVMClientConnectionDone_M := DoAutomatedP2PVMClientConnectionDone;
  PhysicsTunnel.AsyncConnectM(addr, umlStrToInt(Port), DoConnectionResult);
end;

procedure TDT_P2PVM_VirtualAuth_Client.Connect_M(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_M);
begin
  if Connecting then
      exit;
  Connecting := True;
  if not Reconnection then
    begin
      LastAddr := addr;
      LastPort := Port;
      LastAuth := Auth;
    end;
  LastUser := User;
  LastPasswd := Passwd;
  PhysicsTunnel.AutomatedP2PVMAuthToken := Auth;
  OnConnectResultState.Init;
  OnConnectResultState.On_M := OnResult;
  PhysicsTunnel.OnAutomatedP2PVMClientConnectionDone_M := DoAutomatedP2PVMClientConnectionDone;
  PhysicsTunnel.AsyncConnectM(addr, umlStrToInt(Port), DoConnectionResult);
end;

procedure TDT_P2PVM_VirtualAuth_Client.Connect_P(addr, Port, Auth, User, Passwd: SystemString; OnResult: TOnState_P);
begin
  if Connecting then
      exit;
  Connecting := True;
  if not Reconnection then
    begin
      LastAddr := addr;
      LastPort := Port;
      LastAuth := Auth;
    end;
  LastUser := User;
  LastPasswd := Passwd;
  PhysicsTunnel.AutomatedP2PVMAuthToken := Auth;
  OnConnectResultState.Init;
  OnConnectResultState.On_P := OnResult;
  PhysicsTunnel.OnAutomatedP2PVMClientConnectionDone_M := DoAutomatedP2PVMClientConnectionDone;
  PhysicsTunnel.AsyncConnectM(addr, umlStrToInt(Port), DoConnectionResult);
end;

procedure TDT_P2PVM_VirtualAuth_Client.Disconnect;
begin
  Connecting := False;
  Reconnection := False;
  LastAddr := '';
  LastPort := '';
  LastAuth := '';
  PhysicsTunnel.Disconnect;
end;

function TDT_P2PVM_VirtualAuth_Custom_Service.GetQuietMode: Boolean;
begin
  Result := RecvTunnel.QuietMode and SendTunnel.QuietMode;
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Service.SetQuietMode(const Value: Boolean);
begin
  RecvTunnel.QuietMode := Value;
  SendTunnel.QuietMode := Value;
end;

constructor TDT_P2PVM_VirtualAuth_Custom_Service.Create(ServiceClass_: TDTService_VirtualAuthClass; PhysicsTunnel_: TZNet_Server;
  P2PVM_Recv_Name_, P2PVM_Recv_IP6_, P2PVM_Recv_Port_,
  P2PVM_Send_Name_, P2PVM_Send_IP6_, P2PVM_Send_Port_: SystemString);
begin
  inherited Create;

  Bind_PhysicsTunnel := PhysicsTunnel_;
  Bind_P2PVM_Recv_IP6 := P2PVM_Recv_IP6_;
  Bind_P2PVM_Recv_Port := umlStrToInt(P2PVM_Recv_Port_);
  Bind_P2PVM_Send_IP6 := P2PVM_Send_IP6_;
  Bind_P2PVM_Send_Port := umlStrToInt(P2PVM_Send_Port_);

  RecvTunnel := TZNet_WithP2PVM_Server.Create;
  RecvTunnel.QuietMode := PhysicsTunnel_.QuietMode;
  RecvTunnel.PrefixName := 'VA';
  RecvTunnel.Name := P2PVM_Recv_Name_;

  SendTunnel := TZNet_WithP2PVM_Server.Create;
  SendTunnel.QuietMode := PhysicsTunnel_.QuietMode;
  SendTunnel.PrefixName := 'VA';
  SendTunnel.Name := P2PVM_Send_Name_;

  DTService := ServiceClass_.Create(RecvTunnel, SendTunnel);
  DTService.RegisterCommand;
  DTService.SwitchAsDefaultPerformance;

  Bind_PhysicsTunnel.AutomatedP2PVMServiceBind.AddService(RecvTunnel);
  Bind_PhysicsTunnel.AutomatedP2PVMServiceBind.AddService(SendTunnel);
  Bind_PhysicsTunnel.AutomatedP2PVMService := True;
  StartService();
end;

destructor TDT_P2PVM_VirtualAuth_Custom_Service.Destroy;
begin
  StopService;
  Bind_PhysicsTunnel.AutomatedP2PVMServiceBind.RemoveService(RecvTunnel);
  Bind_PhysicsTunnel.AutomatedP2PVMServiceBind.RemoveService(SendTunnel);
  DisposeObject(RecvTunnel);
  DisposeObject(SendTunnel);
  DisposeObject(DTService);
  inherited Destroy;
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Service.Progress;
begin
  Bind_PhysicsTunnel.Progress;
  DTService.Progress;
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Service.StartService;
begin
  RecvTunnel.StartService(Bind_P2PVM_Recv_IP6, Bind_P2PVM_Recv_Port);
  SendTunnel.StartService(Bind_P2PVM_Send_IP6, Bind_P2PVM_Send_Port);
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Service.StopService;
begin
  RecvTunnel.StopService;
  RecvTunnel.StopService;
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client_Clone_Pool.DoFree(var Data: TDT_P2PVM_VirtualAuth_Custom_Client);
begin
  if Data <> nil then
    begin
      Data.Clone_Instance_Ptr := nil;
      DisposeObjectAndNil(Data);
    end;
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client.DoRegisterResult(const state: Boolean);
begin
  DTClient.UserLoginM(LastUser, LastPasswd, DoLoginResult);
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client.DoLoginResult(const state: Boolean);
begin
  if not state then
    begin
      if Assigned(OnConnectResultState.On_C) then
          OnConnectResultState.On_C(state)
      else if Assigned(OnConnectResultState.On_M) then
          OnConnectResultState.On_M(state)
      else if Assigned(OnConnectResultState.On_P) then
          OnConnectResultState.On_P(state);
      OnConnectResultState.Init;
      Connecting := False;
      exit;
    end;

  DTClient.TunnelLinkM(DoTunnelLinkResult);
end;

function TDT_P2PVM_VirtualAuth_Custom_Client.GetQuietMode: Boolean;
begin
  Result := RecvTunnel.QuietMode and SendTunnel.QuietMode;
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client.SetQuietMode(const Value: Boolean);
begin
  RecvTunnel.QuietMode := Value;
  SendTunnel.QuietMode := Value;
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client.Do_Recv_Connect_State(const state: Boolean);
begin
  if not state then
      exit;
  if SendTunnel.RemoteInited then
      Connecting := False;
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client.Do_Send_Connect_State(const state: Boolean);
begin
  if not state then
      exit;
  if RecvTunnel.RemoteInited then
      Connecting := False;
end;

constructor TDT_P2PVM_VirtualAuth_Custom_Client.Create(ClientClass_: TDTClient_VirtualAuthClass; PhysicsTunnel_: TZNet_Client;
  P2PVM_Recv_Name_, P2PVM_Recv_IP6_, P2PVM_Recv_Port_,
  P2PVM_Send_Name_, P2PVM_Send_IP6_, P2PVM_Send_Port_: SystemString);
begin
  inherited Create;
  // internal
  OnConnectResultState.Init;
  Connecting := False;
  Reconnection := False;

  // clone Technology
  Parent_Client := nil;
  Clone_Instance_Ptr := nil;
  Clone_Pool := TDT_P2PVM_VirtualAuth_Custom_Client_Clone_Pool.Create;

  // bind
  Bind_PhysicsTunnel := PhysicsTunnel_;
  Bind_P2PVM_Recv_IP6 := P2PVM_Recv_IP6_;
  Bind_P2PVM_Recv_Port := umlStrToInt(P2PVM_Recv_Port_);
  Bind_P2PVM_Send_IP6 := P2PVM_Send_IP6_;
  Bind_P2PVM_Send_Port := umlStrToInt(P2PVM_Send_Port_);

  // local
  RecvTunnel := TZNet_WithP2PVM_Client.Create;
  RecvTunnel.QuietMode := PhysicsTunnel_.QuietMode;
  RecvTunnel.PrefixName := 'VA';
  RecvTunnel.Name := P2PVM_Recv_Name_;
  SendTunnel := TZNet_WithP2PVM_Client.Create;
  SendTunnel.QuietMode := PhysicsTunnel_.QuietMode;
  SendTunnel.PrefixName := 'VA';
  SendTunnel.Name := P2PVM_Send_Name_;

  ClientClass := ClientClass_;
  DTClient := ClientClass.Create(RecvTunnel, SendTunnel);
  DTClient.RegisterCommand;
  DTClient.SwitchAsDefaultPerformance;
  LastUser := '';
  LastPasswd := '';
  RegisterUserAndLogin := False;
  AutomatedConnection := True;
  OnTunnelLink := nil;

  // automated p2pVM
  Bind_PhysicsTunnel.AutomatedP2PVMBindClient.AddClient(RecvTunnel, Bind_P2PVM_Recv_IP6, Bind_P2PVM_Recv_Port);
  Bind_PhysicsTunnel.AutomatedP2PVMBindClient.AddClient(SendTunnel, Bind_P2PVM_Send_IP6, Bind_P2PVM_Send_Port);
  Bind_PhysicsTunnel.AutomatedP2PVMClient := True;
  Bind_PhysicsTunnel.AutomatedP2PVMClientDelayBoot := 0;
end;

constructor TDT_P2PVM_VirtualAuth_Custom_Client.Create_Clone(Parent_Client_: TDT_P2PVM_VirtualAuth_Custom_Client);
begin
  inherited Create;

  if not Parent_Client_.AutomatedConnection then
      RaiseInfo('Host not established');
  if Parent_Client_.LastUser = '' then
      RaiseInfo('Host loss user info');
  if Parent_Client_.LastPasswd = '' then
      RaiseInfo('Host loss password info');
  if not Parent_Client_.DTClient.LinkOk then
      RaiseInfo('Host is Offline.');

  // internal
  OnConnectResultState.Init;
  Connecting := True;
  Reconnection := True;

  // clone Technology
  Parent_Client := Parent_Client_;
  Clone_Instance_Ptr := Parent_Client_.Clone_Pool.Add(Self);
  Clone_Pool := TDT_P2PVM_VirtualAuth_Custom_Client_Clone_Pool.Create;

  // bind
  Bind_PhysicsTunnel := Parent_Client_.Bind_PhysicsTunnel;
  Bind_P2PVM_Recv_IP6 := Parent_Client_.Bind_P2PVM_Recv_IP6;
  Bind_P2PVM_Recv_Port := Parent_Client_.Bind_P2PVM_Recv_Port;
  Bind_P2PVM_Send_IP6 := Parent_Client_.Bind_P2PVM_Send_IP6;
  Bind_P2PVM_Send_Port := Parent_Client_.Bind_P2PVM_Send_Port;

  // local
  RecvTunnel := TZNet_WithP2PVM_Client.Create;
  RecvTunnel.QuietMode := Bind_PhysicsTunnel.QuietMode;
  RecvTunnel.PrefixName := 'DT';
  RecvTunnel.Name := Parent_Client_.RecvTunnel.Name;
  SendTunnel := TZNet_WithP2PVM_Client.Create;
  SendTunnel.QuietMode := Bind_PhysicsTunnel.QuietMode;
  SendTunnel.PrefixName := 'DT';
  SendTunnel.Name := Parent_Client_.SendTunnel.Name;
  // local DT
  ClientClass := Parent_Client_.ClientClass;
  DTClient := ClientClass.Create(RecvTunnel, SendTunnel);
  DTClient.RegisterCommand;
  DTClient.SwitchAsDefaultPerformance;

  LastUser := Parent_Client_.LastUser;
  LastPasswd := Parent_Client_.LastPasswd;
  RegisterUserAndLogin := False;
  AutomatedConnection := True;
  OnTunnelLink := nil;

  // automated p2pVM
  Bind_PhysicsTunnel.AutomatedP2PVMBindClient.AddClient(RecvTunnel, Bind_P2PVM_Recv_IP6, Bind_P2PVM_Recv_Port);
  Bind_PhysicsTunnel.AutomatedP2PVMBindClient.AddClient(SendTunnel, Bind_P2PVM_Send_IP6, Bind_P2PVM_Send_Port);
  Bind_PhysicsTunnel.AutomatedP2PVMClient := True;
  Bind_PhysicsTunnel.AutomatedP2PVMClientDelayBoot := 0;

  Bind_PhysicsTunnel.P2PVM.InstallLogicFramework(RecvTunnel);
  Bind_PhysicsTunnel.P2PVM.InstallLogicFramework(SendTunnel);

  if Parent_Client_.RecvTunnel.RemoteInited then
      RecvTunnel.AsyncConnectM(Bind_P2PVM_Recv_IP6, Bind_P2PVM_Recv_Port, Do_Recv_Connect_State);
  if Parent_Client_.SendTunnel.RemoteInited then
      SendTunnel.AsyncConnectM(Bind_P2PVM_Send_IP6, Bind_P2PVM_Send_Port, Do_Send_Connect_State);
end;

destructor TDT_P2PVM_VirtualAuth_Custom_Client.Destroy;
begin
  if (Parent_Client <> nil) and (Clone_Instance_Ptr <> nil) then
    begin
      Clone_Instance_Ptr^.Data := nil;
      Parent_Client.Clone_Pool.Remove_P(Clone_Instance_Ptr);
    end;
  Clone_Pool.Clear;

  if Bind_PhysicsTunnel <> nil then
    begin
      Bind_PhysicsTunnel.AutomatedP2PVMBindClient.RemoveClient(RecvTunnel);
      Bind_PhysicsTunnel.AutomatedP2PVMBindClient.RemoveClient(SendTunnel);
    end;

  Disconnect;
  DisposeObject(RecvTunnel);
  DisposeObject(SendTunnel);
  DisposeObject(DTClient);
  inherited Destroy;
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client.Progress;
begin
  Bind_PhysicsTunnel.Progress;
  DTClient.Progress;
  if (AutomatedConnection) and (Bind_PhysicsTunnel.RemoteInited) and (Bind_PhysicsTunnel.AutomatedP2PVMClientConnectionDone(Bind_PhysicsTunnel.ClientIO))
    and (not Connecting) and (Reconnection) and (not DTClient.LinkOk) then
      Connect(LastUser, LastPasswd);

  if Clone_Pool.Num > 0 then
    with Clone_Pool.Invert_Repeat_ do
      repeat
          queue^.Data.Progress;
      until not Prev;
end;

function TDT_P2PVM_VirtualAuth_Custom_Client.LoginIsSuccessed: Boolean;
begin
  Result := False;
  if (LastUser = '') or (LastPasswd = '') then
      exit;
  Result := DTClient.LinkOk;
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client.DoTunnelLinkResult(const state: Boolean);
begin
  if Assigned(OnConnectResultState.On_C) then
      OnConnectResultState.On_C(state)
  else if Assigned(OnConnectResultState.On_M) then
      OnConnectResultState.On_M(state)
  else if Assigned(OnConnectResultState.On_P) then
      OnConnectResultState.On_P(state);
  OnConnectResultState.Init;
  Connecting := False;

  if state then
    begin
      RegisterUserAndLogin := False;

      if AutomatedConnection then
          Reconnection := True;

      if Assigned(OnTunnelLink) then
          OnTunnelLink(Self);
    end;
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client.Connect(User, Passwd: SystemString);
begin
  if Connecting then
      exit;
  Connecting := True;
  if not Bind_PhysicsTunnel.RemoteInited then
    begin
      Connecting := False;
      exit;
    end;
  LastUser := User;
  LastPasswd := Passwd;
  OnConnectResultState.Init;

  if (LastUser = '') or (LastPasswd = '') then
      DTClient.TunnelLinkM(DoTunnelLinkResult)
  else if RegisterUserAndLogin then
      DTClient.RegisterUserM(LastUser, LastPasswd, DoRegisterResult)
  else
      DTClient.UserLoginM(LastUser, LastPasswd, DoLoginResult);
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client.Connect;
begin
  Connect('', '');
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client.Connect_C(User, Passwd: SystemString; OnResult: TOnState_C);
begin
  if Connecting then
      exit;
  Connecting := True;
  if not Bind_PhysicsTunnel.RemoteInited then
    begin
      Connecting := False;
      OnResult(False);
      exit;
    end;
  LastUser := User;
  LastPasswd := Passwd;
  OnConnectResultState.Init;
  OnConnectResultState.On_C := OnResult;
  if (LastUser = '') or (LastPasswd = '') then
      DTClient.TunnelLinkM(DoTunnelLinkResult)
  else if RegisterUserAndLogin then
      DTClient.RegisterUserM(LastUser, LastPasswd, DoRegisterResult)
  else
      DTClient.UserLoginM(LastUser, LastPasswd, DoLoginResult);
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client.Connect_C(OnResult: TOnState_C);
begin
  Connect_C('', '', OnResult);
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client.Connect_M(User, Passwd: SystemString; OnResult: TOnState_M);
begin
  if Connecting then
      exit;
  Connecting := True;
  if not Bind_PhysicsTunnel.RemoteInited then
    begin
      Connecting := False;
      OnResult(False);
      exit;
    end;
  LastUser := User;
  LastPasswd := Passwd;
  OnConnectResultState.Init;
  OnConnectResultState.On_M := OnResult;
  if (LastUser = '') or (LastPasswd = '') then
      DTClient.TunnelLinkM(DoTunnelLinkResult)
  else if RegisterUserAndLogin then
      DTClient.RegisterUserM(LastUser, LastPasswd, DoRegisterResult)
  else
      DTClient.UserLoginM(LastUser, LastPasswd, DoLoginResult);
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client.Connect_M(OnResult: TOnState_M);
begin
  Connect_M('', '', OnResult);
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client.Connect_P(User, Passwd: SystemString; OnResult: TOnState_P);
begin
  if Connecting then
      exit;
  Connecting := True;
  if not Bind_PhysicsTunnel.RemoteInited then
    begin
      Connecting := False;
      OnResult(False);
      exit;
    end;
  LastUser := User;
  LastPasswd := Passwd;
  OnConnectResultState.Init;
  OnConnectResultState.On_P := OnResult;
  if (LastUser = '') or (LastPasswd = '') then
      DTClient.TunnelLinkM(DoTunnelLinkResult)
  else if RegisterUserAndLogin then
      DTClient.RegisterUserM(LastUser, LastPasswd, DoRegisterResult)
  else
      DTClient.UserLoginM(LastUser, LastPasswd, DoLoginResult);
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client.Connect_P(OnResult: TOnState_P);
begin
  Connect_P('', '', OnResult);
end;

procedure TDT_P2PVM_VirtualAuth_Custom_Client.Disconnect;
begin
  Connecting := False;
  Reconnection := False;
  DTClient.Disconnect;

  if Clone_Pool.Num > 0 then
    with Clone_Pool.Invert_Repeat_ do
      repeat
          queue^.Data.Disconnect;
      until not Prev;
end;

end.
 
