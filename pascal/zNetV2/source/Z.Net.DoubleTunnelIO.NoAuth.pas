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
{ * double tunnel IO framework                                                 * }
{ * This unit implements a No-Authentication double-tunnel communication       * }
{ * framework. It provides a service (TDTService_NoAuth) and client            * }
{ * (TDTClient_NoAuth) that manage two separate tunnels (Recv and Send)        * }
{ * for bidirectional data transfer. It includes file transfer, batch stream   * }
{ * processing, and P2PVM (Peer-to-Peer Virtual Machine) integration.          * }
{ ****************************************************************************** }

unit Z.Net.DoubleTunnelIO.NoAuth;

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
  Z.TextDataEngine, Z.Status, Z.Cadencer, Z.Notify, Z.PascalStrings, Z.UPascalStrings;

type
  TDTService_NoAuth = class; // Forward declaration of the no-auth service.
  TService_RecvTunnel_UserDefine_NoAuth = class; // Forward declaration for receive tunnel user-defined data.
  TDTService_NoAuthClass = class of TDTService_NoAuth; // Meta-class for service creation.

  { ============================================================================ }
  { User-defined data attached to a Send tunnel peer connection. }
  { ============================================================================ }
  TService_SendTunnel_UserDefine_NoAuth = class(TPeer_IO_User_Define)
  public
    RecvTunnel: TService_RecvTunnel_UserDefine_NoAuth; // Reference to the paired receive tunnel. Set by Command_TunnelLink.
    RecvTunnelID: Cardinal; // Remote ID of the receive tunnel. Set by Command_TunnelLink.
    DoubleTunnelService: TDTService_NoAuth; // Parent service instance. Set by Command_TunnelLink.

    constructor Create(Owner_: TPeerIO); override;
    destructor Destroy; override;

    function LinkOk: Boolean; // Returns True if this tunnel is properly linked (DoubleTunnelService assigned).
    property BindOk: Boolean read LinkOk;
  end;

  { ============================================================================ }
  { User-defined data attached to a Recv tunnel peer connection. }
  { ============================================================================ }
  TService_RecvTunnel_UserDefine_NoAuth = class(TPeer_IO_User_Define)
  private
    FCurrentFileStream: TCore_Stream; // Stream for currently receiving file. Set during file upload.
    FCurrentReceiveFileName: SystemString; // Full path of the file being received. Set during file upload.
  public
    SendTunnel: TService_SendTunnel_UserDefine_NoAuth; // Reference to the paired send tunnel. Set by Command_TunnelLink.
    SendTunnelID: Cardinal; // Remote ID of the send tunnel. Set by Command_TunnelLink.
    DoubleTunnelService: TDTService_NoAuth; // Parent service instance. Set by Command_TunnelLink.

    constructor Create(Owner_: TPeerIO); override;
    destructor Destroy; override;

    function LinkOk: Boolean; // Returns True if this tunnel is properly linked.
    property BindOk: Boolean read LinkOk;
    property CurrentFileStream: TCore_Stream read FCurrentFileStream write FCurrentFileStream;
    property CurrentReceiveFileName: SystemString read FCurrentReceiveFileName write FCurrentReceiveFileName;
  end;

  { ============================================================================ }
  { Event callbacks for the no-auth service. }
  { ============================================================================ }
  TNoAuth_OnLinkSuccess = procedure(Sender: TDTService_NoAuth; UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth) of object;
  TNoAuth_OnUserOut = procedure(Sender: TDTService_NoAuth; UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth) of object;

  { ============================================================================ }
  { No-Authentication Double-Tunnel Service. }
  { Manages two TZNet_Server instances for receive and send tunnels, handles }
  { file transfer, batch streams, and P2PVM integration. }
  { ============================================================================ }
  TDTService_NoAuth = class(TCore_InterfacedObject_Intermediate)
  protected
    FRecvTunnel: TZNet_Server; // Receive tunnel server. Set by constructor.
    FSendTunnel: TZNet_Server; // Send tunnel server. Set by constructor.
    FCadencerEngine: TCadencer; // Cadencer for progress timing. Created in constructor.
    FProgressEngine: TN_Progress_Tool; // Progress tool for delayed execution. Created in constructor.
    FFileSystem: Boolean; // Enable file system operations. Set by constructor or property.
    FFileShareDirectory: SystemString; // Root directory for file sharing. Set by property.
    { event }
    FOnLinkSuccess: TNoAuth_OnLinkSuccess; // Called when a tunnel link is successfully established. Assigned by user.
    FOnUserOut: TNoAuth_OnUserOut; // Called when a user disconnects. Assigned by user.
  protected
    { virtual event }
    procedure UserLinkSuccess(UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth); virtual; // Triggers FOnLinkSuccess.
    procedure UserOut(UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth); virtual; // Triggers FOnUserOut.
    procedure UserPostFileSuccess(UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth; fn: SystemString); virtual; // Called after a file is fully received.
  protected
    { registed server command }
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

    function GetUserDefineRecvTunnel(RecvCli: TPeerIO): TService_RecvTunnel_UserDefine_NoAuth; // Returns user-defined data for a recv tunnel.

    function TotalLinkCount: Integer; // Returns total number of linked tunnels.

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

    property OnLinkSuccess: TNoAuth_OnLinkSuccess read FOnLinkSuccess write FOnLinkSuccess;
    property OnUserOut: TNoAuth_OnUserOut read FOnUserOut write FOnUserOut;
  end;

  TDTClient_NoAuth = class; // Forward declaration of no-auth client.
  TClient_SendTunnel_NoAuth = class; // Forward declaration for client send tunnel user define.
  TDTClient_NoAuthClass = class of TDTClient_NoAuth;

  { ============================================================================ }
  { User-defined data for client receive tunnel. }
  { ============================================================================ }
  TClient_RecvTunnel_NoAuth = class(TPeer_IO_User_Define)
  public
    Client: TDTClient_NoAuth; // Parent client instance. Set by tunnel link.
    SendTunnel: TClient_SendTunnel_NoAuth; // Paired send tunnel. Set by tunnel link.

    constructor Create(Owner_: TPeerIO); override;
    destructor Destroy; override;
  end;

  { ============================================================================ }
  { User-defined data for client send tunnel. }
  { ============================================================================ }
  TClient_SendTunnel_NoAuth = class(TPeer_IO_User_Define)
  public
    Client: TDTClient_NoAuth; // Parent client instance. Set by tunnel link.
    RecvTunnel: TClient_RecvTunnel_NoAuth; // Paired receive tunnel. Set by tunnel link.

    constructor Create(Owner_: TPeerIO); override;
    destructor Destroy; override;
  end;

  { ============================================================================ }
  { Callback types for file operations. }
  { ============================================================================ }
  TGetFileInfo_C_NoAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const Existed: Boolean; const fSiz: Int64);
  TGetFileInfo_M_NoAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const Existed: Boolean; const fSiz: Int64) of object;
  TFileMD5_C_NoAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const MD5: TMD5);
  TFileMD5_M_NoAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const MD5: TMD5) of object;
  TFileComplete_C_NoAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; stream: TCore_Stream; const fileName: SystemString);
  TFileComplete_M_NoAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; stream: TCore_Stream; const fileName: SystemString) of object;
  TFileFragmentData_C_NoAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const DataPtr: Pointer; const DataSize: Int64; const MD5: TMD5);
  TFileFragmentData_M_NoAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const DataPtr: Pointer; const DataSize: Int64; const MD5: TMD5) of object;

{$IFDEF FPC}
  TGetFileInfo_P_NoAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const Existed: Boolean; const fSiz: Int64) is nested;
  TFileMD5_P_NoAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const MD5: TMD5) is nested;
  TFileComplete_P_NoAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; stream: TCore_Stream; const fileName: SystemString) is nested;
  TFileFragmentData_P_NoAuth = procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const DataPtr: Pointer; const DataSize: Int64; const MD5: TMD5) is nested;
{$ELSE FPC}
  TGetFileInfo_P_NoAuth = reference to procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const Existed: Boolean; const fSiz: Int64);
  TFileMD5_P_NoAuth = reference to procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const MD5: TMD5);
  TFileComplete_P_NoAuth = reference to procedure(const UserData: Pointer; const UserObject: TCore_Object; stream: TCore_Stream; const fileName: SystemString);
  TFileFragmentData_P_NoAuth = reference to procedure(const UserData: Pointer; const UserObject: TCore_Object; const fileName: SystemString; const StartPos, EndPos: Int64; const DataPtr: Pointer; const DataSize: Int64; const MD5: TMD5);
{$ENDIF FPC}

  { ============================================================================ }
  { No-Authentication Double-Tunnel Client. }
  { Manages two TZNet_Client instances for receive and send tunnels, handles }
  { file transfers, batch streams, and P2PVM integration. }
  { ============================================================================ }
  TDTClient_NoAuth = class(TCore_InterfacedObject_Intermediate, IZNet_ClientInterface)
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
    procedure TunnelLink_OnResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: TDFE); // Handles tunnel link response.
    procedure TunnelLink_OnFailed(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: TDFE); // Handles tunnel link failure.
  public
    constructor Create(RecvTunnel_, SendTunnel_: TZNet_Client); virtual;
    destructor Destroy; override;

    property FileSystem: Boolean read FFileSystem; // Whether file system is enabled (set by server).
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

    { sync mode TunnelLink }
    function TunnelLink: Boolean; virtual;

    { async mode TunnelLink }
    procedure TunnelLinkC(On_C: TOnState_C); virtual;
    procedure TunnelLinkM(On_M: TOnState_M); virtual;
    procedure TunnelLinkP(On_P: TOnState_P); virtual;

    { async mode SyncCadencer }
    procedure SyncCadencer; virtual; // Synchronizes cadencer with server.

    { remote file time }
    procedure GetFileTimeM(RemoteFilename: SystemString; On_CResult: TOnStream_M); overload; // Gets file time with method callback.
    procedure GetFileTimeP(RemoteFilename: SystemString; On_CResult: TOnStream_P); overload; // Gets file time with nested callback.

    { remote file information }
    procedure GetFileInfoC(fileName: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TGetFileInfo_C_NoAuth); overload;
    procedure GetFileInfoM(fileName: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TGetFileInfo_M_NoAuth); overload;
    procedure GetFileInfoP(fileName: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TGetFileInfo_P_NoAuth); overload;

    { remote md5 support with public store space }
    procedure GetFileMD5C(fileName: SystemString; const StartPos, EndPos: Int64; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TFileMD5_C_NoAuth); overload;
    procedure GetFileMD5M(fileName: SystemString; const StartPos, EndPos: Int64; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TFileMD5_M_NoAuth); overload;
    procedure GetFileMD5P(fileName: SystemString; const StartPos, EndPos: Int64; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TFileMD5_P_NoAuth); overload;

    { normal download }
    procedure GetFileC(fileName, saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileComplete_C_NoAuth); overload;
    procedure GetFileM(fileName, saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileComplete_M_NoAuth); overload;
    procedure GetFileP(fileName, saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileComplete_P_NoAuth); overload;
    procedure GetFileAsC(fileName, saveFileName, saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileComplete_C_NoAuth); overload;
    procedure GetFileAsM(fileName, saveFileName, saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileComplete_M_NoAuth); overload;
    procedure GetFileAsP(fileName, saveFileName, saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileComplete_P_NoAuth); overload;
    { Synchronously waiting to download files from the server to complete }
    function GetFile(fileName, saveToPath: SystemString): Boolean; overload;
    { restore download }
    procedure GetFileC(fileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileComplete_C_NoAuth); overload;
    procedure GetFileM(fileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileComplete_M_NoAuth); overload;
    procedure GetFileP(fileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileComplete_P_NoAuth); overload;
    procedure GetFileAsC(fileName, saveFileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileComplete_C_NoAuth); overload;
    procedure GetFileAsM(fileName, saveFileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileComplete_M_NoAuth); overload;
    procedure GetFileAsP(fileName, saveFileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileComplete_P_NoAuth); overload;
    { Synchronously waiting to restore download files from the server to complete }
    function GetFile(fileName: SystemString; StartPos: Int64; saveToPath: SystemString): Boolean; overload;

    { file fragment }
    procedure GetFileFragmentDataC(fileName: SystemString; StartPos, EndPos: Int64; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileFragmentData_C_NoAuth); overload;
    procedure GetFileFragmentDataM(fileName: SystemString; StartPos, EndPos: Int64; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileFragmentData_M_NoAuth); overload;
    procedure GetFileFragmentDataP(fileName: SystemString; StartPos, EndPos: Int64; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileFragmentData_P_NoAuth); overload;

    { automated download and verify }
    procedure AutomatedDownloadFileC(remoteFile, localFile: U_String; OnDownloadDone: TFileComplete_C_NoAuth);
    procedure AutomatedDownloadFileM(remoteFile, localFile: U_String; OnDownloadDone: TFileComplete_M_NoAuth);
    procedure AutomatedDownloadFileP(remoteFile, localFile: U_String; OnDownloadDone: TFileComplete_P_NoAuth);

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
    procedure AutomatedUploadFile(localFile: U_String); overload;

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

    property ServerDelay: Double read FServerDelay; // Estimated network delay to server.

    function RemoteInited: Boolean; // Returns True if both tunnels are remotely initialized.

    property RecvTunnel: TZNet_Client read FRecvTunnel;
    property SendTunnel: TZNet_Client read FSendTunnel;
  end;

  { ============================================================================ }
  { P2PVM (Peer-to-Peer Virtual Machine) wrappers for NoAuth. }
  { These classes integrate the double-tunnel with P2PVM functionality. }
  { ============================================================================ }

  TDT_P2PVM_NoAuth_OnState = record
    On_C: TOnState_C;
    On_M: TOnState_M;
    On_P: TOnState_P;
    procedure Init; // Initializes callbacks to nil.
  end;

  PDT_P2PVM_NoAuth_OnState = ^TDT_P2PVM_NoAuth_OnState;

  { ============================================================================ }
  { P2PVM NoAuth Service - wraps a no-auth service with P2PVM server tunnels. }
  { ============================================================================ }
  TDT_P2PVM_NoAuth_Service = class(TCore_Object_Intermediate)
  private
    function GetQuietMode: Boolean;
    procedure SetQuietMode(const Value: Boolean);
  public
    RecvTunnel: TZNet_WithP2PVM_Server; // P2PVM receive tunnel. Created in constructor.
    SendTunnel: TZNet_WithP2PVM_Server; // P2PVM send tunnel. Created in constructor.
    DTService: TDTService_NoAuth; // Underlying no-auth service. Created in constructor.
    PhysicsTunnel: TZNet_Server; // Physical server tunnel for P2PVM. Created in constructor.

    constructor Create(ServiceClass_: TDTService_NoAuthClass; Physics_Class: TZNet_ServerClass);
    destructor Destroy; override;
    procedure Progress; virtual;
    function StartService(ListenAddr, ListenPort, Auth: SystemString): Boolean;
    procedure StopService;
    property QuietMode: Boolean read GetQuietMode write SetQuietMode;
  end;

  TDT_P2PVM_NoAuth_Client = class; // Forward declaration.
  TDT_P2PVM_NoAuth_ServicePool = TGenericsList<TDT_P2PVM_NoAuth_Service>;
  TOn_DT_P2PVM_NoAuth_Client_TunnelLink = procedure(Sender: TDT_P2PVM_NoAuth_Client) of object;

  { ============================================================================ }
  { P2PVM NoAuth Client - wraps a no-auth client with P2PVM client tunnels. }
  { ============================================================================ }
  TDT_P2PVM_NoAuth_Client = class(TCore_Object_Intermediate)
  private
    OnConnectResultState: TDT_P2PVM_NoAuth_OnState; // Callback state for connect result. Set by Connect_* methods.
    Connecting: Boolean; // Whether a connection is in progress. Set internally.
    Reconnection: Boolean; // Whether reconnection is enabled. Set after first successful connection.
    procedure DoConnectionResult(const state: Boolean); // Handles physics tunnel connection result.
    procedure DoAutomatedP2PVMClientConnectionDone(Sender: TZNet; P_IO: TPeerIO); // Called when P2PVM client connection is ready.
    procedure DoTunnelLinkResult(const state: Boolean); // Handles tunnel link result.

    function GetQuietMode: Boolean;
    procedure SetQuietMode(const Value: Boolean);
  public
    RecvTunnel: TZNet_WithP2PVM_Client; // P2PVM receive tunnel. Created in constructor.
    SendTunnel: TZNet_WithP2PVM_Client; // P2PVM send tunnel. Created in constructor.
    DTClient: TDTClient_NoAuth; // Underlying no-auth client. Created in constructor.
    PhysicsTunnel: TZNet_Client; // Physical client tunnel for P2PVM. Created in constructor.
    LastAddr: SystemString; // Last connected address. Set by Connect.
    LastPort: SystemString; // Last connected port (as string). Set by Connect.
    LastAuth: SystemString; // Last auth token. Set by Connect.
    AutomatedConnection: Boolean; // Whether to automatically reconnect. Set by user.
    OnTunnelLink: TOn_DT_P2PVM_NoAuth_Client_TunnelLink; // Called when tunnel link is established. Assigned by user.

    constructor Create(ClientClass_: TDTClient_NoAuthClass; Physics_Class: TZNet_ClientClass);
    destructor Destroy; override;
    procedure Progress; virtual;
    procedure Connect(addr, Port, Auth: SystemString);
    procedure Connect_C(addr, Port, Auth: SystemString; OnResult: TOnState_C);
    procedure Connect_M(addr, Port, Auth: SystemString; OnResult: TOnState_M);
    procedure Connect_P(addr, Port, Auth: SystemString; OnResult: TOnState_P);
    procedure Disconnect;
    property QuietMode: Boolean read GetQuietMode write SetQuietMode;
  end;

  TDT_P2PVM_NoAuth_ClientPool = TGenericsList<TDT_P2PVM_NoAuth_Client>;

  TDT_P2PVM_NoAuth_Custom_Service = class; // Forward declaration.
  TDT_P2PVM_NoAuth_Custom_Service_Class = class of TDT_P2PVM_NoAuth_Custom_Service;

  { ============================================================================ }
  { P2PVM NoAuth Custom Service - for embedding within a physics service. }
  { ============================================================================ }
  TDT_P2PVM_NoAuth_Custom_Service = class(TCore_InterfacedObject_Intermediate)
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
    DTService: TDTService_NoAuth; // Underlying no-auth service. Created in constructor.

    constructor Create(ServiceClass_: TDTService_NoAuthClass; PhysicsTunnel_: TZNet_Server;
      P2PVM_Recv_Name_, P2PVM_Recv_IP6_, P2PVM_Recv_Port_,
      P2PVM_Send_Name_, P2PVM_Send_IP6_, P2PVM_Send_Port_: SystemString); virtual;
    destructor Destroy; override;
    procedure Progress; virtual;
    procedure StartService(); virtual;
    procedure StopService(); virtual;
    property QuietMode: Boolean read GetQuietMode write SetQuietMode;
  end;

  TDT_P2PVM_NoAuth_Custom_ServicePool = TGenericsList<TDT_P2PVM_NoAuth_Custom_Service>;

  TDT_P2PVM_NoAuth_Custom_Client = class; // Forward declaration.
  TDT_P2PVM_NoAuth_Custom_Client_Class = class of TDT_P2PVM_NoAuth_Custom_Client;
  TOn_DT_P2PVM_NoAuth_Custom_Client_TunnelLink = procedure(Sender: TDT_P2PVM_NoAuth_Custom_Client) of object;

  TDT_P2PVM_NoAuth_Custom_Client_Clone_Pool_ = TBigList<TDT_P2PVM_NoAuth_Custom_Client>;

  { ============================================================================ }
  { Clone pool for custom clients - manages cloning technology. }
  { ============================================================================ }
  TDT_P2PVM_NoAuth_Custom_Client_Clone_Pool = class(TDT_P2PVM_NoAuth_Custom_Client_Clone_Pool_)
  public
    procedure DoFree(var Data: TDT_P2PVM_NoAuth_Custom_Client); override;
  end;

  { ============================================================================ }
  { P2PVM NoAuth Custom Client - for embedding within a physics tunnel client. }
  { Supports cloning (multiple clients sharing the same physical tunnel). }
  { ============================================================================ }
  TDT_P2PVM_NoAuth_Custom_Client = class(TCore_InterfacedObject_Intermediate)
  private
    OnConnectResultState: TDT_P2PVM_NoAuth_OnState; // Connect callback state. Set by Connect_* methods.
    Connecting: Boolean; // Connection in progress flag. Set internally.
    Reconnection: Boolean; // Reconnection flag. Set after first connect.
    function GetQuietMode: Boolean;
    procedure SetQuietMode(const Value: Boolean);
  private
    // clone Technology
    Parent_Client: TDT_P2PVM_NoAuth_Custom_Client; // Parent client if this is a clone. Set by Create_Clone.
    Clone_Instance_Ptr: TDT_P2PVM_NoAuth_Custom_Client_Clone_Pool_.PQueueStruct; // Pointer in parent's clone pool. Set by Create_Clone.
    procedure Do_Recv_Connect_State(const state: Boolean); // Callback when receive tunnel connects.
    procedure Do_Send_Connect_State(const state: Boolean); // Callback when send tunnel connects.
  public
    // clone Technology
    Clone_Pool: TDT_P2PVM_NoAuth_Custom_Client_Clone_Pool; // Pool of clones owned by this client. Created in constructor.
    // bind
    Bind_PhysicsTunnel: TZNet_Client; // Physics tunnel to bind to. Set by constructor.
    Bind_P2PVM_Recv_IP6: SystemString; // IPv6 for receive tunnel. Set by constructor.
    Bind_P2PVM_Recv_Port: Word; // Port for receive tunnel. Set by constructor.
    Bind_P2PVM_Send_IP6: SystemString; // IPv6 for send tunnel. Set by constructor.
    Bind_P2PVM_Send_Port: Word; // Port for send tunnel. Set by constructor.
    // local
    ClientClass: TDTClient_NoAuthClass; // Client class to instantiate. Set by constructor.
    RecvTunnel: TZNet_WithP2PVM_Client; // P2PVM receive client. Created in constructor.
    SendTunnel: TZNet_WithP2PVM_Client; // P2PVM send client. Created in constructor.
    DTClient: TDTClient_NoAuth; // Underlying no-auth client. Created in constructor.
    AutomatedConnection: Boolean; // Whether to automatically reconnect. Set by user.
    OnTunnelLink: TOn_DT_P2PVM_NoAuth_Custom_Client_TunnelLink; // Called when tunnel link is established. Assigned by user.

    constructor Create(ClientClass_: TDTClient_NoAuthClass; PhysicsTunnel_: TZNet_Client;
      P2PVM_Recv_Name_, P2PVM_Recv_IP6_, P2PVM_Recv_Port_, P2PVM_Send_Name_, P2PVM_Send_IP6_, P2PVM_Send_Port_: SystemString); virtual;
    constructor Create_Clone(Parent_Client_: TDT_P2PVM_NoAuth_Custom_Client); virtual;
    destructor Destroy; override;
    procedure Progress;
    procedure DoTunnelLinkResult(const state: Boolean); // Handles tunnel link result.
    procedure AutoCheckPhysicsTunnelAndConnect; // Enables auto-reconnect when physics tunnel is ready.
    procedure Connect();
    procedure Connect_C(OnResult: TOnState_C);
    procedure Connect_M(OnResult: TOnState_M);
    procedure Connect_P(OnResult: TOnState_P);
    procedure Disconnect;
    property QuietMode: Boolean read GetQuietMode write SetQuietMode;
  end;

  TDT_P2PVM_NoAuth_Custom_ClientPool = TGenericsList<TDT_P2PVM_NoAuth_Custom_Client>;

  { ============================================================================ }
  { Structures for passing parameters in file operation callbacks. }
  { ============================================================================ }
  PGetFileInfoStruct_NoAuth = ^TGetFileInfoStruct_NoAuth;

  TGetFileInfoStruct_NoAuth = record
    UserData: Pointer;
    UserObject: TCore_Object;
    fileName: SystemString;
    OnComplete_C: TGetFileInfo_C_NoAuth;
    OnComplete_M: TGetFileInfo_M_NoAuth;
    OnComplete_P: TGetFileInfo_P_NoAuth;
  end;

  PFileMD5Struct_NoAuth = ^TFileMD5Struct_NoAuth;

  TFileMD5Struct_NoAuth = record
    UserData: Pointer;
    UserObject: TCore_Object;
    fileName: SystemString;
    StartPos, EndPos: Int64;
    OnComplete_C: TFileMD5_C_NoAuth;
    OnComplete_M: TFileMD5_M_NoAuth;
    OnComplete_P: TFileMD5_P_NoAuth;
  end;

  PRemoteFileBackcall_NoAuth = ^TRemoteFileBackcall_NoAuth;

  TRemoteFileBackcall_NoAuth = record
    UserData: Pointer;
    UserObject: TCore_Object;
    OnComplete_C: TFileComplete_C_NoAuth;
    OnComplete_M: TFileComplete_M_NoAuth;
    OnComplete_P: TFileComplete_P_NoAuth;
  end;

  PFileFragmentDataBackcall_NoAuth = ^TFileFragmentDataBackcall_NoAuth;

  TFileFragmentDataBackcall_NoAuth = record
    UserData: Pointer;
    UserObject: TCore_Object;
    fileName: SystemString;
    StartPos, EndPos: Int64;
    OnComplete_C: TFileFragmentData_C_NoAuth;
    OnComplete_M: TFileFragmentData_M_NoAuth;
    OnComplete_P: TFileFragmentData_P_NoAuth;
  end;

  { ============================================================================ }
  { Internal helper classes for automated download/upload. }
  { ============================================================================ }
  TAutomatedDownloadFile_Struct_NoAuth = class(TCore_Object_Intermediate)
  private
    remoteFile: SystemString; // Remote file path. Set by caller.
    localFile: SystemString; // Local file path. Set by caller.
    OnDownloadDoneC: TFileComplete_C_NoAuth; // C-style completion callback. Set by caller.
    OnDownloadDoneM: TFileComplete_M_NoAuth; // Method completion callback. Set by caller.
    OnDownloadDoneP: TFileComplete_P_NoAuth; // Nested completion callback. Set by caller.
    Client: TDTClient_NoAuth; // Parent client. Set by caller.
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

  TAutomatedUploadFile_Struct_NoAuth = class(TCore_Object_Intermediate)
  private
    localFile: SystemString; // Local file path. Set by caller.
    Client: TDTClient_NoAuth; // Parent client. Set by caller.
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
  TZNet_DoubleTunnelService_NoAuth = TDTService_NoAuth;
  TZNet_DoubleTunnelClient_NoAuth = TDTClient_NoAuth;

implementation

uses SysUtils;

procedure TAutomatedDownloadFile_Struct_NoAuth.DoComplete(const UserData: Pointer; const UserObject: TCore_Object; stream: TCore_Stream; const fileName: SystemString);
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

procedure TAutomatedDownloadFile_Struct_NoAuth.DoResult_GetFileInfo(const UserData: Pointer; const UserObject: TCore_Object;
  const fileName: SystemString; const Existed: Boolean; const fSiz: Int64);
begin
  r_fileExisted := Existed;

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

procedure TAutomatedDownloadFile_Struct_NoAuth.Do_Th_ComputeLFileMD5();
begin
  DoStatus('compute md5 from local "%s"', [localFile]);
  l_fileMD5 := umlFileMD5(localFile);
  TCompute.PostM1(Done_ComputeLFileMD5);
end;

procedure TAutomatedDownloadFile_Struct_NoAuth.Done_ComputeLFileMD5();
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

procedure TAutomatedDownloadFile_Struct_NoAuth.DoResult_GetFileMD5(const UserData: Pointer; const UserObject: TCore_Object;
  const fileName: SystemString; const StartPos, EndPos: Int64; const MD5: Z.Core.TMD5);
begin
  r_fileMD5 := MD5;
  TCompute.RunM_NP(Do_Th_ComputeLFileMD5);
end;

constructor TAutomatedDownloadFile_Struct_NoAuth.Create;
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

destructor TAutomatedDownloadFile_Struct_NoAuth.Destroy;
begin
  remoteFile := '';
  localFile := '';
  r_fileName := '';
  inherited Destroy;
end;

procedure TAutomatedUploadFile_Struct_NoAuth.DoResult_GetFileInfo(const UserData: Pointer; const UserObject: TCore_Object;
  const fileName: SystemString; const Existed: Boolean; const fSiz: Int64);
begin
  r_fileExisted := Existed;

  if Existed then
    begin
      r_fileName := fileName;
      r_fileSize := fSiz;
      if r_fileSize <= umlGetFileSize(localFile) then
        begin
          Client.GetFileMD5M(r_fileName, 0, r_fileSize, nil, nil, DoResult_GetFileMD5);
        end
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

procedure TAutomatedUploadFile_Struct_NoAuth.Do_Th_ComputeLFileMD5;
begin
  DoStatus('compute md5 from local "%s"', [localFile]);
  l_fileMD5 := umlFileMD5(localFile, l_file_StartPos, l_file_EndPos);
  TCompute.PostM1(Done_ComputeLFileMD5);
end;

procedure TAutomatedUploadFile_Struct_NoAuth.Done_ComputeLFileMD5;
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

procedure TAutomatedUploadFile_Struct_NoAuth.DoResult_GetFileMD5(const UserData: Pointer; const UserObject: TCore_Object;
  const fileName: SystemString; const StartPos, EndPos: Int64; const MD5: Z.Core.TMD5);
begin
  r_fileMD5 := MD5;
  l_file_StartPos := StartPos;
  l_file_EndPos := EndPos;
  TCompute.RunM_NP(Do_Th_ComputeLFileMD5);
end;

constructor TAutomatedUploadFile_Struct_NoAuth.Create;
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

destructor TAutomatedUploadFile_Struct_NoAuth.Destroy;
begin
  localFile := '';
  r_fileName := '';
  inherited Destroy;
end;

constructor TService_SendTunnel_UserDefine_NoAuth.Create(Owner_: TPeerIO);
begin
  inherited Create(Owner_);
  RecvTunnel := nil;
  RecvTunnelID := 0;
  DoubleTunnelService := nil;
end;

destructor TService_SendTunnel_UserDefine_NoAuth.Destroy;
begin
  if (DoubleTunnelService <> nil) and (RecvTunnelID > 0) and (RecvTunnel <> nil) then
    begin
      if DoubleTunnelService.FRecvTunnel.Exists(RecvTunnelID) then
          DoubleTunnelService.FRecvTunnel.PeerIO[RecvTunnelID].Disconnect;
    end;
  inherited Destroy;
end;

function TService_SendTunnel_UserDefine_NoAuth.LinkOk: Boolean;
begin
  Result := DoubleTunnelService <> nil;
end;

constructor TService_RecvTunnel_UserDefine_NoAuth.Create(Owner_: TPeerIO);
begin
  inherited Create(Owner_);
  SendTunnel := nil;
  SendTunnelID := 0;
  DoubleTunnelService := nil;
  FCurrentFileStream := nil;
  FCurrentReceiveFileName := '';
end;

destructor TService_RecvTunnel_UserDefine_NoAuth.Destroy;
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

function TService_RecvTunnel_UserDefine_NoAuth.LinkOk: Boolean;
begin
  Result := DoubleTunnelService <> nil;
end;

procedure TDTService_NoAuth.UserLinkSuccess(UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth);
begin
  try
    if Assigned(FOnLinkSuccess) then
        FOnLinkSuccess(Self, UserDefineIO);
  except
  end;
end;

procedure TDTService_NoAuth.UserOut(UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth);
begin
  try
    if Assigned(FOnUserOut) then
        FOnUserOut(Self, UserDefineIO);
  except
  end;
end;

procedure TDTService_NoAuth.UserPostFileSuccess(UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth; fn: SystemString);
begin
end;

procedure TDTService_NoAuth.Command_TunnelLink(Sender: TPeerIO; InData, OutData: TDFE);
var
  RecvID, SendID: Cardinal;
  UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth;
begin
  RecvID := InData.Reader.ReadCardinal;
  SendID := InData.Reader.ReadCardinal;

  UserDefineIO := GetUserDefineRecvTunnel(Sender);

  if not FSendTunnel.Exists(SendID) then
    begin
      OutData.WriteBool(False);
      OutData.WriteString(PFormat('send tunnel Illegal:%d', [SendID]));
      OutData.WriteBool(FFileSystem);
      Exit;
    end;

  if not FRecvTunnel.Exists(RecvID) then
    begin
      OutData.WriteBool(False);
      OutData.WriteString(PFormat('received tunnel Illegal:%d', [RecvID]));
      OutData.WriteBool(FFileSystem);
      Exit;
    end;

  if Sender.ID <> RecvID then
    begin
      OutData.WriteBool(False);
      OutData.WriteString(PFormat('received tunnel Illegal:%d-%d', [Sender.ID, RecvID]));
      OutData.WriteBool(FFileSystem);
      Exit;
    end;

  UserDefineIO.SendTunnel := FSendTunnel.PeerIO[SendID].UserDefine as TService_SendTunnel_UserDefine_NoAuth;
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

procedure TDTService_NoAuth.Command_GetCurrentCadencer(Sender: TPeerIO; InData, OutData: TDFE);
begin
  FCadencerEngine.Progress;
  OutData.WriteDouble(FCadencerEngine.CurrentTime);
end;

procedure TDTService_NoAuth.Command_GetFileTime(Sender: TPeerIO; InData, OutData: TDFE);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth;
  fullfn, fileName: SystemString;
begin
  if not FFileSystem then
      Exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
      Exit;

  fileName := InData.Reader.ReadString;
  fullfn := umlCombineFileName(FFileShareDirectory, fileName);
  if not umlFileExists(fullfn) then
    begin
      OutData.WriteBool(False);
      Exit;
    end;
  OutData.WriteBool(True);
  OutData.WriteString(fileName);
  OutData.WriteDouble(umlGetFileTime(fullfn));
end;

procedure TDTService_NoAuth.Command_GetFileInfo(Sender: TPeerIO; InData, OutData: TDFE);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth;
  fullfn, fileName: SystemString;
begin
  if not FFileSystem then
      Exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
      Exit;

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

procedure TDTService_NoAuth.Do_Th_Command_GetFileMD5(ThSender: THPC_Stream; ThInData, ThOutData: TDFE);
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
      Exit;
    end;

  try
      fs := TCore_FileStream.Create(fullfn, fmOpenRead or fmShareDenyNone);
  except
    ThOutData.WriteBool(False);
    Exit;
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

procedure TDTService_NoAuth.Command_GetFileMD5(Sender: TPeerIO; InData, OutData: TDFE);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth;
begin
  if not FFileSystem then
      Exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
      Exit;

  RunHPC_StreamM(Sender, nil, nil, InData, OutData, Do_Th_Command_GetFileMD5);
end;

procedure TDTService_NoAuth.Command_GetFile(Sender: TPeerIO; InData, OutData: TDFE);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth;
  fullfn, fileName, remoteinfo: SystemString;
  StartPos: Int64;
  RemoteBackcallAddr: UInt64;
  sendDE: TDFE;
  fs: TCore_FileStream;
begin
  if not FFileSystem then
      Exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
      Exit;

  fileName := InData.Reader.ReadString;
  StartPos := InData.Reader.ReadInt64;
  remoteinfo := InData.Reader.ReadString;
  RemoteBackcallAddr := InData.Reader.ReadPointer;

  fullfn := umlCombineFileName(FFileShareDirectory, fileName);
  if not umlFileExists(fullfn) then
    begin
      OutData.WriteBool(False);
      OutData.WriteString(PFormat('filename invailed %s', [fileName]));
      Exit;
    end;

  try
      fs := TCore_FileStream.Create(fullfn, fmOpenRead or fmShareDenyNone);
  except
      Exit;
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

procedure TDTService_NoAuth.Command_GetFileAs(Sender: TPeerIO; InData, OutData: TDFE);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth;
  fullfn, fileName, saveFileName, remoteinfo: SystemString;
  StartPos: Int64;
  RemoteBackcallAddr: UInt64;
  sendDE: TDFE;
  fs: TCore_FileStream;
begin
  if not FFileSystem then
      Exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
      Exit;

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
      Exit;
    end;

  try
      fs := TCore_FileStream.Create(fullfn, fmOpenRead or fmShareDenyNone);
  except
      Exit;
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

procedure TDTService_NoAuth.Command_PostFileInfo(Sender: TPeerIO; InData: TDFE);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth;
  fn: SystemString;
  StartPos: Int64;
  FSize: Int64;
  fullfn: SystemString;
begin
  if not FFileSystem then
      Exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
    begin
      Sender.DelayClose();
      Exit;
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

procedure TDTService_NoAuth.Command_PostFile(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth;
begin
  if not FFileSystem then
      Exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
    begin
      Sender.DelayClose();
      Exit;
    end;

  if UserDefineIO.FCurrentFileStream <> nil then
    begin
      InData.Position := 0;
      if InData.Size > 0 then
          UserDefineIO.FCurrentFileStream.CopyFrom(InData, InData.Size);
    end;
end;

procedure TDTService_NoAuth.Command_PostFileOver(Sender: TPeerIO; InData: TDFE);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth;
  fn: SystemString;
begin
  if not FFileSystem then
      Exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
    begin
      Sender.DelayClose();
      Exit;
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

procedure TDTService_NoAuth.Command_GetFileFragmentData(Sender: TPeerIO; InData, OutData: TDFE);
var
  UserDefineIO: TService_RecvTunnel_UserDefine_NoAuth;
  fullfn, fileName: SystemString;
  StartPos, EndPos, siz, fp: Int64;
  RemoteBackcallAddr: UInt64;
  fs: TCore_FileStream;
  mem_: TMS64;
  MD5: TMD5;
begin
  if not FFileSystem then
      Exit;
  UserDefineIO := GetUserDefineRecvTunnel(Sender);
  if not UserDefineIO.LinkOk then
      Exit;

  fileName := InData.Reader.ReadString;
  StartPos := InData.Reader.ReadInt64;
  EndPos := InData.Reader.ReadInt64;
  RemoteBackcallAddr := InData.Reader.ReadPointer;

  fullfn := umlCombineFileName(FFileShareDirectory, fileName);
  if not umlFileExists(fullfn) then
    begin
      OutData.WriteBool(False);
      Exit;
    end;

  try
      fs := TCore_FileStream.Create(fullfn, fmOpenRead or fmShareDenyNone);
  except
    OutData.WriteBool(False);
    Exit;
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
      Exit;
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

procedure TDTService_NoAuth.Command_NewBatchStream(Sender: TPeerIO; InData: TDFE);
var
  RT: TService_RecvTunnel_UserDefine_NoAuth;
  p: PBigStreamBatchPostData;
begin
  RT := GetUserDefineRecvTunnel(Sender);
  if not RT.LinkOk then
      Exit;
  p := RT.BigStreamBatchList.NewPostData;
  p^.RemoteMD5 := InData.Reader.ReadMD5;
  p^.CompletedBackcallPtr := InData.Reader.ReadPointer;
end;

procedure TDTService_NoAuth.Command_PostBatchStream(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64);
var
  RT: TService_RecvTunnel_UserDefine_NoAuth;
  p: PBigStreamBatchPostData;
  de: TDFE;
begin
  RT := GetUserDefineRecvTunnel(Sender);
  if not RT.LinkOk then
      Exit;

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

procedure TDTService_NoAuth.Command_ClearBatchStream(Sender: TPeerIO; InData: TDFE);
var
  RT: TService_RecvTunnel_UserDefine_NoAuth;
begin
  RT := GetUserDefineRecvTunnel(Sender);
  if not RT.LinkOk then
      Exit;
  RT.BigStreamBatchList.Clear;
end;

procedure TDTService_NoAuth.Command_PostBatchStreamDone(Sender: TPeerIO; InData: TDFE);
var
  RT: TService_RecvTunnel_UserDefine_NoAuth;
  rMD5, sMD5: TMD5;
  backCallVal: UInt64;
  backCallValPtr: POnStateStruct;
  MD5Verify: Boolean;
begin
  RT := GetUserDefineRecvTunnel(Sender);
  if not RT.LinkOk then
      Exit;

  rMD5 := InData.Reader.ReadMD5;
  sMD5 := InData.Reader.ReadMD5;
  backCallVal := InData.Reader.ReadPointer;

  backCallValPtr := POnStateStruct(Pointer(backCallVal));
  MD5Verify := umlMD5Compare(rMD5, sMD5);

  if backCallValPtr = nil then
      Exit;

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

procedure TDTService_NoAuth.Command_GetBatchStreamState(Sender: TPeerIO; InData, OutData: TDFE);
var
  RT: TService_RecvTunnel_UserDefine_NoAuth;
  i: Integer;
  p: PBigStreamBatchPostData;

  de: TDFE;
begin
  RT := GetUserDefineRecvTunnel(Sender);
  if not RT.LinkOk then
      Exit;

  for i := 0 to RT.BigStreamBatchList.Count - 1 do
    begin
      p := RT.BigStreamBatchList[i];
      de := TDFE.Create;
      p^.Encode(de);
      OutData.WriteDataFrame(de);
      DisposeObject(de);
    end;
end;

constructor TDTService_NoAuth.Create(RecvTunnel_, SendTunnel_: TZNet_Server);
begin
  inherited Create;
  FRecvTunnel := RecvTunnel_;
  FRecvTunnel.PeerClientUserDefineClass := TService_RecvTunnel_UserDefine_NoAuth;
  FSendTunnel := SendTunnel_;
  FSendTunnel.PeerClientUserDefineClass := TService_SendTunnel_UserDefine_NoAuth;

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

  FOnLinkSuccess := nil;
  FOnUserOut := nil;
end;

destructor TDTService_NoAuth.Destroy;
begin
  DisposeObject(FCadencerEngine);
  DisposeObject(FProgressEngine);
  inherited Destroy;
end;

procedure TDTService_NoAuth.SwitchAsMaxPerformance;
begin
  FRecvTunnel.SwitchMaxPerformance;
  FSendTunnel.SwitchMaxPerformance;
end;

procedure TDTService_NoAuth.SwitchAsMaxSecurity;
begin
  FRecvTunnel.SwitchMaxSecurity;
  FSendTunnel.SwitchMaxSecurity;
end;

procedure TDTService_NoAuth.SwitchAsDefaultPerformance;
begin
  FRecvTunnel.SwitchDefaultPerformance;
  FSendTunnel.SwitchDefaultPerformance;
end;

procedure TDTService_NoAuth.Progress;
begin
  FCadencerEngine.Progress;
  FRecvTunnel.Progress;
  FSendTunnel.Progress;
end;

procedure TDTService_NoAuth.CadencerProgress(Sender: TObject; const deltaTime, newTime: Double);
begin
  FProgressEngine.Progress(deltaTime);
end;

procedure TDTService_NoAuth.RegisterCommand;
begin
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

procedure TDTService_NoAuth.UnRegisterCommand;
begin
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

function TDTService_NoAuth.GetUserDefineRecvTunnel(RecvCli: TPeerIO): TService_RecvTunnel_UserDefine_NoAuth;
begin
  if RecvCli = nil then
      Exit(nil);
  Result := RecvCli.UserDefine as TService_RecvTunnel_UserDefine_NoAuth;
end;

function TDTService_NoAuth.TotalLinkCount: Integer;
begin
  Result := RecvTunnel.Count;
end;

procedure TDTService_NoAuth.PostBatchStream(cli: TPeerIO; stream: TCore_Stream; doneFreeStream: Boolean);
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

procedure TDTService_NoAuth.PostBatchStreamC(cli: TPeerIO; stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_C);
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

procedure TDTService_NoAuth.PostBatchStreamM(cli: TPeerIO; stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_M);
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

procedure TDTService_NoAuth.PostBatchStreamP(cli: TPeerIO; stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_P);
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

procedure TDTService_NoAuth.ClearBatchStream(cli: TPeerIO);
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;
  cli.SendStreamNotifyCmd(C_ClearBatchStream, de);
  DisposeObject(de);
end;

procedure TDTService_NoAuth.GetBatchStreamStateM(cli: TPeerIO; OnResult: TOnStream_M);
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;
  cli.SendStreamCmdM(C_GetBatchStreamState, de, OnResult);
  DisposeObject(de);
end;

procedure TDTService_NoAuth.GetBatchStreamStateM(cli: TPeerIO; Param1: Pointer; Param2: TObject; OnResult: TOnStreamParam_M);
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;
  cli.SendStreamCmdM(C_GetBatchStreamState, de, Param1, Param2, OnResult);
  DisposeObject(de);
end;

procedure TDTService_NoAuth.GetBatchStreamStateP(cli: TPeerIO; OnResult: TOnStream_P);
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;
  cli.SendStreamCmdP(C_GetBatchStreamState, de, OnResult);
  DisposeObject(de);
end;

procedure TDTService_NoAuth.GetBatchStreamStateP(cli: TPeerIO; Param1: Pointer; Param2: TObject; OnResult: TOnStreamParam_P);
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;
  cli.SendStreamCmdP(C_GetBatchStreamState, de, Param1, Param2, OnResult);
  DisposeObject(de);
end;

constructor TClient_RecvTunnel_NoAuth.Create(Owner_: TPeerIO);
begin
  inherited Create(Owner_);
  Client := nil;
  SendTunnel := nil;
end;

destructor TClient_RecvTunnel_NoAuth.Destroy;
begin
  if Client <> nil then
      Client.FLinkOk := False;
  inherited Destroy;
end;

constructor TClient_SendTunnel_NoAuth.Create(Owner_: TPeerIO);
begin
  inherited Create(Owner_);
  Client := nil;
  RecvTunnel := nil;
end;

destructor TClient_SendTunnel_NoAuth.Destroy;
begin
  if Client <> nil then
      Client.FLinkOk := False;
  inherited Destroy;
end;

{ client notify interface }
procedure TDTClient_NoAuth.ClientConnected(Sender: TZNet_Client);
begin
end;

procedure TDTClient_NoAuth.ClientDisconnect(Sender: TZNet_Client);
begin
  if FCurrentStream <> nil then
    begin
      DisposeObject(FCurrentStream);
      FCurrentStream := nil;
    end;
  FCurrentReceiveStreamFileName := '';
end;

procedure TDTClient_NoAuth.Command_FileInfo(Sender: TPeerIO; InData: TDFE);
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

procedure TDTClient_NoAuth.Command_PostFile(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64);
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

procedure TDTClient_NoAuth.Command_PostFileOver(Sender: TPeerIO; InData: TDFE);
var
  RemoteBackcallAddr: UInt64;
  p: PRemoteFileBackcall_NoAuth;
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

procedure TDTClient_NoAuth.Command_PostFileFragmentData(Sender: TPeerIO; InData: PByte; DataSize: NativeInt);
var
  mem_: TMS64;
  StartPos, EndPos, siz: Int64;
  RemoteBackcallAddr: UInt64;
  p: PFileFragmentDataBackcall_NoAuth;
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

procedure TDTClient_NoAuth.GetCurrentCadencer_StreamResult(Sender: TPeerIO; Result_: TDFE);
var
  servTime: Double;
begin
  servTime := Result_.Reader.ReadDouble;

  FCadencerEngine.Progress;
  FServerDelay := FCadencerEngine.CurrentTime - FLastCadencerTime;

  FCadencerEngine.CurrentTime := servTime + FServerDelay;
  FCadencerEngine.Progress;
end;

procedure TDTClient_NoAuth.GetFileInfo_StreamParamResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; InData, Result_: TDFE);
var
  p: PGetFileInfoStruct_NoAuth;
  Existed: Boolean;
  fSiz: Int64;
begin
  p := PGetFileInfoStruct_NoAuth(Param1);
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

procedure TDTClient_NoAuth.GetFileMD5_StreamParamResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; InData, Result_: TDFE);
var
  p: PFileMD5Struct_NoAuth;
  successed: Boolean;
  MD5: TMD5;
begin
  p := PFileMD5Struct_NoAuth(Param1);
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

procedure TDTClient_NoAuth.GetFile_StreamParamResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; InData, Result_: TDFE);
var
  p: PRemoteFileBackcall_NoAuth;
begin
  if Result_.Count > 0 then
    begin
      if Result_.Reader.ReadBool then
          Exit;
      Sender.Print('get file failed:%s', [Result_.Reader.ReadString]);
    end;

  p := Param1;
  Dispose(p);
end;

procedure TDTClient_NoAuth.GetFileFragmentData_StreamParamResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; InData, Result_: TDFE);
var
  p: PFileFragmentDataBackcall_NoAuth;
begin
  if Result_.Count > 0 then
    begin
      if Result_.Reader.ReadBool then
          Exit;
    end;

  p := Param1;
  Dispose(p);
end;

procedure TDTClient_NoAuth.Command_NewBatchStream(Sender: TPeerIO; InData: TDFE);
var
  RT: TClient_RecvTunnel_NoAuth;
  p: PBigStreamBatchPostData;
begin
  if not LinkOk then
      Exit;
  RT := Sender.UserDefine as TClient_RecvTunnel_NoAuth;
  p := RT.BigStreamBatchList.NewPostData;
  p^.RemoteMD5 := InData.Reader.ReadMD5;
  p^.CompletedBackcallPtr := InData.Reader.ReadPointer;
end;

procedure TDTClient_NoAuth.Command_PostBatchStream(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64);
var
  RT: TClient_RecvTunnel_NoAuth;
  p: PBigStreamBatchPostData;
  de: TDFE;
begin
  if not LinkOk then
      Exit;
  RT := Sender.UserDefine as TClient_RecvTunnel_NoAuth;

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

procedure TDTClient_NoAuth.Command_ClearBatchStream(Sender: TPeerIO; InData: TDFE);
var
  RT: TClient_RecvTunnel_NoAuth;
  p: PBigStreamBatchPostData;
  de: TDFE;
begin
  if not LinkOk then
      Exit;
  RT := Sender.UserDefine as TClient_RecvTunnel_NoAuth;
  RT.BigStreamBatchList.Clear;
end;

procedure TDTClient_NoAuth.Command_PostBatchStreamDone(Sender: TPeerIO; InData: TDFE);
var
  RT: TClient_RecvTunnel_NoAuth;
  rMD5, sMD5: TMD5;
  backCallVal: UInt64;
  backCallValPtr: POnStateStruct;
  MD5Verify: Boolean;
begin
  if not LinkOk then
      Exit;
  RT := Sender.UserDefine as TClient_RecvTunnel_NoAuth;

  rMD5 := InData.Reader.ReadMD5;
  sMD5 := InData.Reader.ReadMD5;
  backCallVal := InData.Reader.ReadPointer;

  backCallValPtr := POnStateStruct(Pointer(backCallVal));
  MD5Verify := umlMD5Compare(rMD5, sMD5);

  if backCallValPtr = nil then
      Exit;

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

procedure TDTClient_NoAuth.Command_GetBatchStreamState(Sender: TPeerIO; InData, OutData: TDFE);
var
  RT: TClient_RecvTunnel_NoAuth;
  i: Integer;
  p: PBigStreamBatchPostData;

  de: TDFE;
begin
  if not LinkOk then
      Exit;
  RT := Sender.UserDefine as TClient_RecvTunnel_NoAuth;

  for i := 0 to RT.BigStreamBatchList.Count - 1 do
    begin
      p := RT.BigStreamBatchList[i];
      de := TDFE.Create;
      p^.Encode(de);
      OutData.WriteDataFrame(de);
      DisposeObject(de);
    end;
end;

procedure TDTClient_NoAuth.AsyncSendConnectResult(const cState: Boolean);
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
      Exit;
    end;

  RecvTunnel.AsyncConnectM(FAsyncConnectAddr, FAsyncConnRecvPort, AsyncRecvConnectResult);
end;

procedure TDTClient_NoAuth.AsyncRecvConnectResult(const cState: Boolean);
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

procedure TDTClient_NoAuth.TunnelLink_OnResult(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: TDFE);
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
          TClient_SendTunnel_NoAuth(FSendTunnel.ClientIO.UserDefine).Client := Self;
          TClient_SendTunnel_NoAuth(FSendTunnel.ClientIO.UserDefine).RecvTunnel := TClient_RecvTunnel_NoAuth(FRecvTunnel.ClientIO.UserDefine);

          TClient_RecvTunnel_NoAuth(FRecvTunnel.ClientIO.UserDefine).Client := Self;
          TClient_RecvTunnel_NoAuth(FRecvTunnel.ClientIO.UserDefine).SendTunnel := TClient_SendTunnel_NoAuth(FSendTunnel.ClientIO.UserDefine);

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

procedure TDTClient_NoAuth.TunnelLink_OnFailed(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: TDFE);
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

constructor TDTClient_NoAuth.Create(RecvTunnel_, SendTunnel_: TZNet_Client);
begin
  inherited Create;
  FRecvTunnel := RecvTunnel_;
  FRecvTunnel.NotyifyInterface := Self;
  FRecvTunnel.PeerClientUserDefineClass := TClient_RecvTunnel_NoAuth;

  FSendTunnel := SendTunnel_;
  FSendTunnel.NotyifyInterface := Self;
  FSendTunnel.PeerClientUserDefineClass := TClient_SendTunnel_NoAuth;

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

destructor TDTClient_NoAuth.Destroy;
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

function TDTClient_NoAuth.Connected: Boolean;
begin
  try
      Result := FSendTunnel.Connected and FRecvTunnel.Connected;
  except
      Result := False;
  end;
end;

function TDTClient_NoAuth.IOBusy: Boolean;
begin
  try
      Result := FSendTunnel.IOBusy and FRecvTunnel.IOBusy;
  except
      Result := True;
  end;
end;

procedure TDTClient_NoAuth.SwitchAsMaxPerformance;
begin
  FRecvTunnel.SwitchMaxPerformance;
  FSendTunnel.SwitchMaxPerformance;
end;

procedure TDTClient_NoAuth.SwitchAsMaxSecurity;
begin
  FRecvTunnel.SwitchMaxSecurity;
  FSendTunnel.SwitchMaxSecurity;
end;

procedure TDTClient_NoAuth.SwitchAsDefaultPerformance;
begin
  FRecvTunnel.SwitchDefaultPerformance;
  FSendTunnel.SwitchDefaultPerformance;
end;

procedure TDTClient_NoAuth.Progress;
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

procedure TDTClient_NoAuth.CadencerProgress(Sender: TObject; const deltaTime, newTime: Double);
begin
  FProgressEngine.Progress(deltaTime);
end;

function TDTClient_NoAuth.Connect(addr: SystemString; const RecvPort, SendPort: Word): Boolean;
var
  t: Cardinal;
begin
  Result := False;
  Disconnect;

  if not FSendTunnel.Connect(addr, SendPort) then
    begin
      DoStatus('connect %s failed!', [addr]);
      Exit;
    end;
  if not FRecvTunnel.Connect(addr, RecvPort) then
    begin
      DoStatus('connect %s failed!', [addr]);
      Exit;
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

procedure TDTClient_NoAuth.AsyncConnectC(addr: SystemString; const RecvPort, SendPort: Word; OnResult: TOnState_C);
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

procedure TDTClient_NoAuth.AsyncConnectM(addr: SystemString; const RecvPort, SendPort: Word; OnResult: TOnState_M);
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

procedure TDTClient_NoAuth.AsyncConnectP(addr: SystemString; const RecvPort, SendPort: Word; OnResult: TOnState_P);
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

procedure TDTClient_NoAuth.AsyncConnectC(addr: SystemString; const RecvPort, SendPort: Word; Param1: Pointer; Param2: TObject; OnResult: TOnParamState_C);
var
  ParamBridge: TState_Param_Bridge;
begin
  ParamBridge := TState_Param_Bridge.Create;
  ParamBridge.Param1 := Param1;
  ParamBridge.Param2 := Param2;
  ParamBridge.OnNotifyC := OnResult;
  AsyncConnectM(addr, RecvPort, SendPort, ParamBridge.DoStateResult);
end;

procedure TDTClient_NoAuth.AsyncConnectM(addr: SystemString; const RecvPort, SendPort: Word; Param1: Pointer; Param2: TObject; OnResult: TOnParamState_M);
var
  ParamBridge: TState_Param_Bridge;
begin
  ParamBridge := TState_Param_Bridge.Create;
  ParamBridge.Param1 := Param1;
  ParamBridge.Param2 := Param2;
  ParamBridge.OnNotifyM := OnResult;
  AsyncConnectM(addr, RecvPort, SendPort, ParamBridge.DoStateResult);
end;

procedure TDTClient_NoAuth.AsyncConnectP(addr: SystemString; const RecvPort, SendPort: Word; Param1: Pointer; Param2: TObject; OnResult: TOnParamState_P);
var
  ParamBridge: TState_Param_Bridge;
begin
  ParamBridge := TState_Param_Bridge.Create;
  ParamBridge.Param1 := Param1;
  ParamBridge.Param2 := Param2;
  ParamBridge.OnNotifyP := OnResult;
  AsyncConnectM(addr, RecvPort, SendPort, ParamBridge.DoStateResult);
end;

procedure TDTClient_NoAuth.Disconnect;
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

function TDTClient_NoAuth.TunnelLink: Boolean;
var
  sendDE, resDE: TDFE;
begin
  if FLinkOk then
      Exit(True);
  FLinkOk := False;
  Result := False;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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
          TClient_SendTunnel_NoAuth(FSendTunnel.ClientIO.UserDefine).Client := Self;
          TClient_SendTunnel_NoAuth(FSendTunnel.ClientIO.UserDefine).RecvTunnel := TClient_RecvTunnel_NoAuth(FRecvTunnel.ClientIO.UserDefine);

          TClient_RecvTunnel_NoAuth(FRecvTunnel.ClientIO.UserDefine).Client := Self;
          TClient_RecvTunnel_NoAuth(FRecvTunnel.ClientIO.UserDefine).SendTunnel := TClient_SendTunnel_NoAuth(FSendTunnel.ClientIO.UserDefine);

          FLinkOk := True;
        end;
    end;

  DisposeObject(sendDE);
  DisposeObject(resDE);
end;

procedure TDTClient_NoAuth.TunnelLinkC(On_C: TOnState_C);
var
  sendDE: TDFE;
  p: POnStateStruct;
begin
  if FLinkOk then
      Exit;

  FLinkOk := False;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.TunnelLinkM(On_M: TOnState_M);
var
  sendDE: TDFE;
  p: POnStateStruct;
begin
  if FLinkOk then
      Exit;

  FLinkOk := False;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.TunnelLinkP(On_P: TOnState_P);
var
  sendDE: TDFE;
  p: POnStateStruct;
begin
  if FLinkOk then
      Exit;

  FLinkOk := False;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.SyncCadencer;
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

procedure TDTClient_NoAuth.GetFileTimeM(RemoteFilename: SystemString; On_CResult: TOnStream_M);
var
  sendDE: TDFE;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

  sendDE := TDFE.Create;
  sendDE.WriteString(RemoteFilename);
  FSendTunnel.SendStreamCmdM(C_GetFileTime, sendDE, On_CResult);
  DisposeObject(sendDE);
end;

procedure TDTClient_NoAuth.GetFileTimeP(RemoteFilename: SystemString; On_CResult: TOnStream_P);
var
  sendDE: TDFE;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

  sendDE := TDFE.Create;
  sendDE.WriteString(RemoteFilename);
  FSendTunnel.SendStreamCmdP(C_GetFileTime, sendDE, On_CResult);
  DisposeObject(sendDE);
end;

{ remote file exists }
procedure TDTClient_NoAuth.GetFileInfoC(fileName: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TGetFileInfo_C_NoAuth);
var
  sendDE: TDFE;
  p: PGetFileInfoStruct_NoAuth;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.GetFileInfoM(fileName: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TGetFileInfo_M_NoAuth);
var
  sendDE: TDFE;
  p: PGetFileInfoStruct_NoAuth;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.GetFileInfoP(fileName: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TGetFileInfo_P_NoAuth);
var
  sendDE: TDFE;
  p: PGetFileInfoStruct_NoAuth;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

{ remote md5 support with public store space }
procedure TDTClient_NoAuth.GetFileMD5C(fileName: SystemString; const StartPos, EndPos: Int64;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TFileMD5_C_NoAuth);
var
  sendDE: TDFE;
  p: PFileMD5Struct_NoAuth;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.GetFileMD5M(fileName: SystemString; const StartPos, EndPos: Int64;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TFileMD5_M_NoAuth);
var
  sendDE: TDFE;
  p: PFileMD5Struct_NoAuth;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.GetFileMD5P(fileName: SystemString; const StartPos, EndPos: Int64;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete: TFileMD5_P_NoAuth);
var
  sendDE: TDFE;
  p: PFileMD5Struct_NoAuth;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.GetFileC(fileName, saveToPath: SystemString;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileComplete_C_NoAuth);
begin
  GetFileC(fileName, 0, saveToPath, UserData, UserObject, OnComplete_C);
end;

procedure TDTClient_NoAuth.GetFileM(fileName, saveToPath: SystemString;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileComplete_M_NoAuth);
begin
  GetFileM(fileName, 0, saveToPath, UserData, UserObject, OnComplete_M);
end;

procedure TDTClient_NoAuth.GetFileP(fileName, saveToPath: SystemString;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileComplete_P_NoAuth);
begin
  GetFileP(fileName, 0, saveToPath, UserData, UserObject, OnComplete_P);
end;

procedure TDTClient_NoAuth.GetFileAsC(fileName, saveFileName, saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileComplete_C_NoAuth);
begin
  GetFileAsC(fileName, saveFileName, 0, saveToPath, UserData, UserObject, OnComplete_C);
end;

procedure TDTClient_NoAuth.GetFileAsM(fileName, saveFileName, saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileComplete_M_NoAuth);
begin
  GetFileAsM(fileName, saveFileName, 0, saveToPath, UserData, UserObject, OnComplete_M);
end;

procedure TDTClient_NoAuth.GetFileAsP(fileName, saveFileName, saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileComplete_P_NoAuth);
begin
  GetFileAsP(fileName, saveFileName, 0, saveToPath, UserData, UserObject, OnComplete_P);
end;

function TDTClient_NoAuth.GetFile(fileName, saveToPath: SystemString): Boolean;
begin
  Result := GetFile(fileName, 0, saveToPath);
end;

{ restore download }
procedure TDTClient_NoAuth.GetFileC(fileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileComplete_C_NoAuth);
var
  sendDE: TDFE;
  p: PRemoteFileBackcall_NoAuth;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.GetFileM(fileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileComplete_M_NoAuth);
var
  sendDE: TDFE;
  p: PRemoteFileBackcall_NoAuth;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.GetFileP(fileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileComplete_P_NoAuth);
var
  sendDE: TDFE;
  p: PRemoteFileBackcall_NoAuth;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.GetFileAsC(fileName, saveFileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileComplete_C_NoAuth);
var
  sendDE: TDFE;
  p: PRemoteFileBackcall_NoAuth;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.GetFileAsM(fileName, saveFileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileComplete_M_NoAuth);
var
  sendDE: TDFE;
  p: PRemoteFileBackcall_NoAuth;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.GetFileAsP(fileName, saveFileName: SystemString; StartPos: Int64; saveToPath: SystemString; const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileComplete_P_NoAuth);
var
  sendDE: TDFE;
  p: PRemoteFileBackcall_NoAuth;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

{ Synchronously waiting to download files from the server to complete }
function TDTClient_NoAuth.GetFile(fileName: SystemString; StartPos: Int64; saveToPath: SystemString): Boolean;
var
  sendDE, resDE: TDFE;
begin
  Result := False;
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.GetFileFragmentDataC(fileName: SystemString; StartPos, EndPos: Int64;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_C: TFileFragmentData_C_NoAuth);
var
  sendDE: TDFE;
  p: PFileFragmentDataBackcall_NoAuth;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.GetFileFragmentDataM(fileName: SystemString; StartPos, EndPos: Int64;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_M: TFileFragmentData_M_NoAuth);
var
  sendDE: TDFE;
  p: PFileFragmentDataBackcall_NoAuth;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.GetFileFragmentDataP(fileName: SystemString; StartPos, EndPos: Int64;
  const UserData: Pointer; const UserObject: TCore_Object; const OnComplete_P: TFileFragmentData_P_NoAuth);
var
  sendDE: TDFE;
  p: PFileFragmentDataBackcall_NoAuth;
begin
  if not FFileSystem then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.AutomatedDownloadFileC(remoteFile, localFile: U_String; OnDownloadDone: TFileComplete_C_NoAuth);
var
  tmp: TAutomatedDownloadFile_Struct_NoAuth;
begin
  if not FFileSystem then
      Exit;
  tmp := TAutomatedDownloadFile_Struct_NoAuth.Create;
  tmp.remoteFile := remoteFile;
  tmp.localFile := localFile;
  tmp.OnDownloadDoneC := OnDownloadDone;
  tmp.Client := Self;

  GetFileInfoM(umlGetFileName(remoteFile), nil, nil, tmp.DoResult_GetFileInfo);
end;

procedure TDTClient_NoAuth.AutomatedDownloadFileM(remoteFile, localFile: U_String; OnDownloadDone: TFileComplete_M_NoAuth);
var
  tmp: TAutomatedDownloadFile_Struct_NoAuth;
begin
  if not FFileSystem then
      Exit;
  tmp := TAutomatedDownloadFile_Struct_NoAuth.Create;
  tmp.remoteFile := remoteFile;
  tmp.localFile := localFile;
  tmp.OnDownloadDoneM := OnDownloadDone;
  tmp.Client := Self;

  GetFileInfoM(umlGetFileName(remoteFile), nil, nil, tmp.DoResult_GetFileInfo);
end;

procedure TDTClient_NoAuth.AutomatedDownloadFileP(remoteFile, localFile: U_String; OnDownloadDone: TFileComplete_P_NoAuth);
var
  tmp: TAutomatedDownloadFile_Struct_NoAuth;
begin
  if not FFileSystem then
      Exit;
  tmp := TAutomatedDownloadFile_Struct_NoAuth.Create;
  tmp.remoteFile := remoteFile;
  tmp.localFile := localFile;
  tmp.OnDownloadDoneP := OnDownloadDone;
  tmp.Client := Self;

  GetFileInfoM(umlGetFileName(remoteFile), nil, nil, tmp.DoResult_GetFileInfo);
end;

procedure TDTClient_NoAuth.PostFile(fileName: SystemString);
var
  sendDE: TDFE;
  fs: TCore_FileStream;
begin
  if not FFileSystem then
      Exit;
  if not umlFileExists(fileName) then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.PostFile(l_fileName, r_fileName: SystemString);
var
  sendDE: TDFE;
  fs: TCore_FileStream;
begin
  if not FFileSystem then
      Exit;
  if not umlFileExists(l_fileName) then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.PostFile(fileName: SystemString; StartPos: Int64);
var
  sendDE: TDFE;
  fs: TCore_FileStream;
begin
  if not FFileSystem then
      Exit;
  if not umlFileExists(fileName) then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.PostFile(l_fileName, r_fileName: SystemString; StartPos: Int64);
var
  sendDE: TDFE;
  fs: TCore_FileStream;
begin
  if not FFileSystem then
      Exit;
  if not umlFileExists(l_fileName) then
      Exit;
  if not FSendTunnel.Connected then
      Exit;
  if not FRecvTunnel.Connected then
      Exit;

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

procedure TDTClient_NoAuth.PostFile(fn: SystemString; stream: TCore_Stream; doneFreeStream: Boolean);
var
  sendDE: TDFE;
begin
  if (not FSendTunnel.Connected) or (not FRecvTunnel.Connected) or (not FFileSystem) then
    begin
      if doneFreeStream then
          DisposeObject(stream);
      Exit;
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

procedure TDTClient_NoAuth.PostFile(fn: SystemString; stream: TCore_Stream; StartPos: Int64; doneFreeStream: Boolean);
var
  sendDE: TDFE;
begin
  if (not FSendTunnel.Connected) or (not FRecvTunnel.Connected) or (not FFileSystem) then
    begin
      if doneFreeStream then
          DisposeObject(stream);
      Exit;
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

procedure TDTClient_NoAuth.AutomatedUploadFile(localFile: U_String);
var
  tmp: TAutomatedUploadFile_Struct_NoAuth;
begin
  if not FFileSystem then
      Exit;
  tmp := TAutomatedUploadFile_Struct_NoAuth.Create;
  tmp.localFile := localFile;
  tmp.Client := Self;

  GetFileInfoM(umlGetFileName(localFile), nil, nil, tmp.DoResult_GetFileInfo);
end;

procedure TDTClient_NoAuth.PostBatchStream(stream: TCore_Stream; doneFreeStream: Boolean);
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

procedure TDTClient_NoAuth.PostBatchStreamC(stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_C);
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

procedure TDTClient_NoAuth.PostBatchStreamM(stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_M);
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

procedure TDTClient_NoAuth.PostBatchStreamP(stream: TCore_Stream; doneFreeStream: Boolean; OnCompletedBackcall: TOnState_P);
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

procedure TDTClient_NoAuth.ClearBatchStream;
var
  de: TDFE;
  p: POnStateStruct;
begin
  de := TDFE.Create;
  SendTunnel.SendStreamNotifyCmd(C_ClearBatchStream, de);
  DisposeObject(de);
end;

procedure TDTClient_NoAuth.GetBatchStreamStateM(OnResult: TOnStream_M);
var
  de: TDFE;
begin
  de := TDFE.Create;
  SendTunnel.SendStreamCmdM(C_GetBatchStreamState, de, OnResult);
  DisposeObject(de);
end;

procedure TDTClient_NoAuth.GetBatchStreamStateM(Param1: Pointer; Param2: TObject; OnResult: TOnStreamParam_M);
var
  de: TDFE;
begin
  de := TDFE.Create;
  SendTunnel.SendStreamCmdM(C_GetBatchStreamState, de, Param1, Param2, OnResult);
  DisposeObject(de);
end;

procedure TDTClient_NoAuth.GetBatchStreamStateP(OnResult: TOnStream_P);
var
  de: TDFE;
begin
  de := TDFE.Create;
  SendTunnel.SendStreamCmdP(C_GetBatchStreamState, de, OnResult);
  DisposeObject(de);
end;

procedure TDTClient_NoAuth.GetBatchStreamStateP(Param1: Pointer; Param2: TObject; OnResult: TOnStreamParam_P);
var
  de: TDFE;
begin
  de := TDFE.Create;
  SendTunnel.SendStreamCmdP(C_GetBatchStreamState, de, Param1, Param2, OnResult);
  DisposeObject(de);
end;

function TDTClient_NoAuth.GetBatchStreamState(Result_: TDFE; TimeOut_: TTimeTick): Boolean;
var
  de: TDFE;
begin
  de := TDFE.Create;
  SendTunnel.WaitSendStreamCmd(C_GetBatchStreamState, de, Result_, TimeOut_);
  Result := Result_.Count > 0;
  DisposeObject(de);
end;

procedure TDTClient_NoAuth.RegisterCommand;
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

procedure TDTClient_NoAuth.UnRegisterCommand;
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

function TDTClient_NoAuth.RemoteInited: Boolean;
begin
  Result := FSendTunnel.RemoteInited and FRecvTunnel.RemoteInited;
end;

procedure TDT_P2PVM_NoAuth_OnState.Init;
begin
  On_C := nil;
  On_M := nil;
  On_P := nil;
end;

function TDT_P2PVM_NoAuth_Service.GetQuietMode: Boolean;
begin
  Result := RecvTunnel.QuietMode and SendTunnel.QuietMode and PhysicsTunnel.QuietMode;
end;

procedure TDT_P2PVM_NoAuth_Service.SetQuietMode(const Value: Boolean);
begin
  RecvTunnel.QuietMode := Value;
  SendTunnel.QuietMode := Value;
  PhysicsTunnel.QuietMode := Value;
end;

constructor TDT_P2PVM_NoAuth_Service.Create(ServiceClass_: TDTService_NoAuthClass; Physics_Class: TZNet_ServerClass);
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

  RecvTunnel.PrefixName := 'NA';
  RecvTunnel.Name := 'R';
  SendTunnel.PrefixName := 'NA';
  SendTunnel.Name := 'S';
  PhysicsTunnel.PrefixName := 'Physics';
  PhysicsTunnel.Name := 'p2pVM';
end;

destructor TDT_P2PVM_NoAuth_Service.Destroy;
begin
  StopService;
  DisposeObject(RecvTunnel);
  DisposeObject(SendTunnel);
  DisposeObject(DTService);
  DisposeObject(PhysicsTunnel);
  inherited Destroy;
end;

procedure TDT_P2PVM_NoAuth_Service.Progress;
begin
  DTService.Progress;
  PhysicsTunnel.Progress;
end;

function TDT_P2PVM_NoAuth_Service.StartService(ListenAddr, ListenPort, Auth: SystemString): Boolean;
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

procedure TDT_P2PVM_NoAuth_Service.StopService;
begin
  PhysicsTunnel.StopService;
  RecvTunnel.StopService;
  SendTunnel.StopService;
end;

procedure TDT_P2PVM_NoAuth_Client.DoConnectionResult(const state: Boolean);
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

procedure TDT_P2PVM_NoAuth_Client.DoAutomatedP2PVMClientConnectionDone(Sender: TZNet; P_IO: TPeerIO);
begin
  DTClient.TunnelLinkM(DoTunnelLinkResult);
  PhysicsTunnel.Print('DT p2pVM done.');
end;

procedure TDT_P2PVM_NoAuth_Client.DoTunnelLinkResult(const state: Boolean);
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
      if AutomatedConnection then
          Reconnection := True;
      if Assigned(OnTunnelLink) then
          OnTunnelLink(Self);
    end;
end;

function TDT_P2PVM_NoAuth_Client.GetQuietMode: Boolean;
begin
  Result := RecvTunnel.QuietMode and SendTunnel.QuietMode and PhysicsTunnel.QuietMode;
end;

procedure TDT_P2PVM_NoAuth_Client.SetQuietMode(const Value: Boolean);
begin
  RecvTunnel.QuietMode := Value;
  SendTunnel.QuietMode := Value;
  PhysicsTunnel.QuietMode := Value;
end;

constructor TDT_P2PVM_NoAuth_Client.Create(ClientClass_: TDTClient_NoAuthClass; Physics_Class: TZNet_ClientClass);
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

  AutomatedConnection := True;
  OnTunnelLink := nil;

  RecvTunnel.PrefixName := 'NA';
  RecvTunnel.Name := 'R';
  SendTunnel.PrefixName := 'NA';
  SendTunnel.Name := 'S';
  PhysicsTunnel.PrefixName := 'Physics';
  PhysicsTunnel.Name := 'p2pVM';
end;

destructor TDT_P2PVM_NoAuth_Client.Destroy;
begin
  Disconnect;
  DisposeObject(RecvTunnel);
  DisposeObject(SendTunnel);
  DisposeObject(DTClient);
  DisposeObject(PhysicsTunnel);
  inherited Destroy;
end;

procedure TDT_P2PVM_NoAuth_Client.Progress;
begin
  DTClient.Progress;
  PhysicsTunnel.Progress;

  if (AutomatedConnection) and ((not PhysicsTunnel.Connected) or (not DTClient.LinkOk)) and (not Connecting) and (Reconnection) then
      Connect(LastAddr, LastPort, LastAuth);
end;

procedure TDT_P2PVM_NoAuth_Client.Connect(addr, Port, Auth: SystemString);
begin
  if Connecting then
      Exit;
  Connecting := True;
  if not Reconnection then
    begin
      LastAddr := addr;
      LastPort := Port;
      LastAuth := Auth;
    end;
  PhysicsTunnel.AutomatedP2PVMAuthToken := Auth;
  OnConnectResultState.Init;
  PhysicsTunnel.OnAutomatedP2PVMClientConnectionDone_M := DoAutomatedP2PVMClientConnectionDone;
  PhysicsTunnel.AsyncConnectM(addr, umlStrToInt(Port), DoConnectionResult);
end;

procedure TDT_P2PVM_NoAuth_Client.Connect_C(addr, Port, Auth: SystemString; OnResult: TOnState_C);
begin
  if Connecting then
      Exit;
  Connecting := True;
  if not Reconnection then
    begin
      LastAddr := addr;
      LastPort := Port;
      LastAuth := Auth;
    end;
  PhysicsTunnel.AutomatedP2PVMAuthToken := Auth;
  OnConnectResultState.Init;
  OnConnectResultState.On_C := OnResult;
  PhysicsTunnel.OnAutomatedP2PVMClientConnectionDone_M := DoAutomatedP2PVMClientConnectionDone;
  PhysicsTunnel.AsyncConnectM(addr, umlStrToInt(Port), DoConnectionResult);
end;

procedure TDT_P2PVM_NoAuth_Client.Connect_M(addr, Port, Auth: SystemString; OnResult: TOnState_M);
begin
  if Connecting then
      Exit;
  Connecting := True;
  if not Reconnection then
    begin
      LastAddr := addr;
      LastPort := Port;
      LastAuth := Auth;
    end;
  PhysicsTunnel.AutomatedP2PVMAuthToken := Auth;
  OnConnectResultState.Init;
  OnConnectResultState.On_M := OnResult;
  PhysicsTunnel.OnAutomatedP2PVMClientConnectionDone_M := DoAutomatedP2PVMClientConnectionDone;
  PhysicsTunnel.AsyncConnectM(addr, umlStrToInt(Port), DoConnectionResult);
end;

procedure TDT_P2PVM_NoAuth_Client.Connect_P(addr, Port, Auth: SystemString; OnResult: TOnState_P);
begin
  if Connecting then
      Exit;
  Connecting := True;
  if not Reconnection then
    begin
      LastAddr := addr;
      LastPort := Port;
      LastAuth := Auth;
    end;
  PhysicsTunnel.AutomatedP2PVMAuthToken := Auth;
  OnConnectResultState.Init;
  OnConnectResultState.On_P := OnResult;
  PhysicsTunnel.OnAutomatedP2PVMClientConnectionDone_M := DoAutomatedP2PVMClientConnectionDone;
  PhysicsTunnel.AsyncConnectM(addr, umlStrToInt(Port), DoConnectionResult);
end;

procedure TDT_P2PVM_NoAuth_Client.Disconnect;
begin
  Connecting := False;
  Reconnection := False;
  LastAddr := '';
  LastPort := '';
  LastAuth := '';
  PhysicsTunnel.Disconnect;
end;

function TDT_P2PVM_NoAuth_Custom_Service.GetQuietMode: Boolean;
begin
  Result := RecvTunnel.QuietMode and SendTunnel.QuietMode;
end;

procedure TDT_P2PVM_NoAuth_Custom_Service.SetQuietMode(const Value: Boolean);
begin
  RecvTunnel.QuietMode := Value;
  SendTunnel.QuietMode := Value;
end;

constructor TDT_P2PVM_NoAuth_Custom_Service.Create(ServiceClass_: TDTService_NoAuthClass; PhysicsTunnel_: TZNet_Server;
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
  RecvTunnel.PrefixName := 'NA';
  RecvTunnel.Name := P2PVM_Recv_Name_;

  SendTunnel := TZNet_WithP2PVM_Server.Create;
  SendTunnel.QuietMode := PhysicsTunnel_.QuietMode;
  SendTunnel.PrefixName := 'NA';
  SendTunnel.Name := P2PVM_Send_Name_;

  DTService := ServiceClass_.Create(RecvTunnel, SendTunnel);
  DTService.RegisterCommand;
  DTService.SwitchAsDefaultPerformance;

  Bind_PhysicsTunnel.AutomatedP2PVMServiceBind.AddService(RecvTunnel);
  Bind_PhysicsTunnel.AutomatedP2PVMServiceBind.AddService(SendTunnel);
  Bind_PhysicsTunnel.AutomatedP2PVMService := True;
  StartService();
end;

destructor TDT_P2PVM_NoAuth_Custom_Service.Destroy;
begin
  StopService;
  Bind_PhysicsTunnel.AutomatedP2PVMServiceBind.RemoveService(RecvTunnel);
  Bind_PhysicsTunnel.AutomatedP2PVMServiceBind.RemoveService(SendTunnel);
  DisposeObject(RecvTunnel);
  DisposeObject(SendTunnel);
  DisposeObject(DTService);
  inherited Destroy;
end;

procedure TDT_P2PVM_NoAuth_Custom_Service.Progress;
begin
  Bind_PhysicsTunnel.Progress;
  DTService.Progress;
end;

procedure TDT_P2PVM_NoAuth_Custom_Service.StartService;
begin
  RecvTunnel.StartService(Bind_P2PVM_Recv_IP6, Bind_P2PVM_Recv_Port);
  SendTunnel.StartService(Bind_P2PVM_Send_IP6, Bind_P2PVM_Send_Port);
end;

procedure TDT_P2PVM_NoAuth_Custom_Service.StopService;
begin
  RecvTunnel.StopService;
  RecvTunnel.StopService;
end;

procedure TDT_P2PVM_NoAuth_Custom_Client_Clone_Pool.DoFree(var Data: TDT_P2PVM_NoAuth_Custom_Client);
begin
  if Data <> nil then
    begin
      Data.Clone_Instance_Ptr := nil;
      DisposeObjectAndNil(Data);
    end;
end;

function TDT_P2PVM_NoAuth_Custom_Client.GetQuietMode: Boolean;
begin
  Result := RecvTunnel.QuietMode and SendTunnel.QuietMode;
end;

procedure TDT_P2PVM_NoAuth_Custom_Client.SetQuietMode(const Value: Boolean);
begin
  RecvTunnel.QuietMode := Value;
  SendTunnel.QuietMode := Value;
end;

procedure TDT_P2PVM_NoAuth_Custom_Client.Do_Recv_Connect_State(const state: Boolean);
begin
  if not state then
      Exit;
  if SendTunnel.RemoteInited then
      Connecting := False;
end;

procedure TDT_P2PVM_NoAuth_Custom_Client.Do_Send_Connect_State(const state: Boolean);
begin
  if not state then
      Exit;
  if RecvTunnel.RemoteInited then
      Connecting := False;
end;

constructor TDT_P2PVM_NoAuth_Custom_Client.Create(ClientClass_: TDTClient_NoAuthClass; PhysicsTunnel_: TZNet_Client;
  P2PVM_Recv_Name_, P2PVM_Recv_IP6_, P2PVM_Recv_Port_, P2PVM_Send_Name_, P2PVM_Send_IP6_, P2PVM_Send_Port_: SystemString);
begin
  inherited Create;
  // internal
  OnConnectResultState.Init;
  Connecting := False;
  Reconnection := False;

  // clone Technology
  Parent_Client := nil;
  Clone_Instance_Ptr := nil;
  Clone_Pool := TDT_P2PVM_NoAuth_Custom_Client_Clone_Pool.Create;

  // bind
  Bind_PhysicsTunnel := PhysicsTunnel_;
  Bind_P2PVM_Recv_IP6 := P2PVM_Recv_IP6_;
  Bind_P2PVM_Recv_Port := umlStrToInt(P2PVM_Recv_Port_);
  Bind_P2PVM_Send_IP6 := P2PVM_Send_IP6_;
  Bind_P2PVM_Send_Port := umlStrToInt(P2PVM_Send_Port_);

  // local
  RecvTunnel := TZNet_WithP2PVM_Client.Create;
  RecvTunnel.QuietMode := PhysicsTunnel_.QuietMode;
  RecvTunnel.PrefixName := 'NA';
  RecvTunnel.Name := P2PVM_Recv_Name_;
  SendTunnel := TZNet_WithP2PVM_Client.Create;
  SendTunnel.QuietMode := PhysicsTunnel_.QuietMode;
  SendTunnel.PrefixName := 'NA';
  SendTunnel.Name := P2PVM_Send_Name_;
  // local DT
  ClientClass := ClientClass_;
  DTClient := ClientClass.Create(RecvTunnel, SendTunnel);
  DTClient.RegisterCommand;
  DTClient.SwitchAsDefaultPerformance;
  AutomatedConnection := True;
  OnTunnelLink := nil;

  // automated p2pVM
  Bind_PhysicsTunnel.AutomatedP2PVMBindClient.AddClient(RecvTunnel, Bind_P2PVM_Recv_IP6, Bind_P2PVM_Recv_Port);
  Bind_PhysicsTunnel.AutomatedP2PVMBindClient.AddClient(SendTunnel, Bind_P2PVM_Send_IP6, Bind_P2PVM_Send_Port);
  Bind_PhysicsTunnel.AutomatedP2PVMClient := True;
  Bind_PhysicsTunnel.AutomatedP2PVMClientDelayBoot := 0;
end;

constructor TDT_P2PVM_NoAuth_Custom_Client.Create_Clone(Parent_Client_: TDT_P2PVM_NoAuth_Custom_Client);
begin
  inherited Create;

  if not Parent_Client_.AutomatedConnection then
      RaiseInfo('Host not established');
  if not Parent_Client_.DTClient.LinkOk then
      RaiseInfo('Host is Offline.');

  // internal
  OnConnectResultState.Init;
  Connecting := True;
  Reconnection := True;

  // clone Technology
  Parent_Client := Parent_Client_;
  Clone_Instance_Ptr := Parent_Client_.Clone_Pool.Add(Self);
  Clone_Pool := TDT_P2PVM_NoAuth_Custom_Client_Clone_Pool.Create;

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

destructor TDT_P2PVM_NoAuth_Custom_Client.Destroy;
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
  DisposeObject(Clone_Pool);
  inherited Destroy;
end;

procedure TDT_P2PVM_NoAuth_Custom_Client.Progress;
begin
  Bind_PhysicsTunnel.Progress;
  DTClient.Progress;
  if (AutomatedConnection) and (Bind_PhysicsTunnel.RemoteInited) and (Bind_PhysicsTunnel.AutomatedP2PVMClientConnectionDone(Bind_PhysicsTunnel.ClientIO))
    and (not Connecting) and (Reconnection) and (not DTClient.LinkOk) then
      Connect();

  if Clone_Pool.Num > 0 then
    with Clone_Pool.Invert_Repeat_ do
      repeat
          queue^.Data.Progress;
      until not Prev;
end;

procedure TDT_P2PVM_NoAuth_Custom_Client.DoTunnelLinkResult(const state: Boolean);
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
      if AutomatedConnection then
          Reconnection := True;

      if Assigned(OnTunnelLink) then
          OnTunnelLink(Self);
    end;
end;

procedure TDT_P2PVM_NoAuth_Custom_Client.AutoCheckPhysicsTunnelAndConnect;
begin
  AutomatedConnection := True;
  Reconnection := True;
end;

procedure TDT_P2PVM_NoAuth_Custom_Client.Connect;
begin
  if Connecting then
      Exit;
  Connecting := True;
  if not Bind_PhysicsTunnel.RemoteInited then
    begin
      Connecting := False;
      Exit;
    end;
  OnConnectResultState.Init;
  DTClient.TunnelLinkM(DoTunnelLinkResult);
end;

procedure TDT_P2PVM_NoAuth_Custom_Client.Connect_C(OnResult: TOnState_C);
begin
  if Connecting then
      Exit;
  Connecting := True;
  if not Bind_PhysicsTunnel.RemoteInited then
    begin
      Connecting := False;
      OnResult(False);
      Exit;
    end;
  OnConnectResultState.Init;
  OnConnectResultState.On_C := OnResult;
  DTClient.TunnelLinkM(DoTunnelLinkResult);
end;

procedure TDT_P2PVM_NoAuth_Custom_Client.Connect_M(OnResult: TOnState_M);
begin
  if Connecting then
      Exit;
  Connecting := True;
  if not Bind_PhysicsTunnel.RemoteInited then
    begin
      Connecting := False;
      OnResult(False);
      Exit;
    end;
  OnConnectResultState.Init;
  OnConnectResultState.On_M := OnResult;
  DTClient.TunnelLinkM(DoTunnelLinkResult);
end;

procedure TDT_P2PVM_NoAuth_Custom_Client.Connect_P(OnResult: TOnState_P);
begin
  if Connecting then
      Exit;
  Connecting := True;
  if not Bind_PhysicsTunnel.RemoteInited then
    begin
      Connecting := False;
      OnResult(False);
      Exit;
    end;
  OnConnectResultState.Init;
  OnConnectResultState.On_P := OnResult;
  DTClient.TunnelLinkM(DoTunnelLinkResult);
end;

procedure TDT_P2PVM_NoAuth_Custom_Client.Disconnect;
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
 
