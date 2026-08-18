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
  ******************************************************************************
  * Z.Net.C4_Console_APP.pas - C4 Console Application Framework
  *
  * This unit provides a command-line and script-driven entry point for
  * deploying and running Cloud 4.0 (C4) networks. It parses command-line
  * arguments or script arrays into C4 service and client configurations,
  * builds the corresponding physics tunnels/services, and executes a main
  * loop with an interactive console for runtime management and diagnostics.
  *
  * It is designed to be used both in GUI (C4AppTemplate) and headless
  * console environments (Windows/Linux/macOS servers, IoT devices).
  * The scripting engine (TOpCustomRunTime) interprets expressions like
  *   Service('0.0.0.0','127.0.0.1',8008,'DP')
  *   KeepAlive('127.0.0.1',8008,'DP')
  * to build the C4 topology dynamically at startup.
  *
  * Dependencies:
  *   - Z.Core, Z.PascalStrings, Z.UnicodeMixedLib, Z.Status, Z.Expression
  *   - Z.Net.C4 (core C4 framework)
  *   - Z.Net.C4_UserDB, Z.Net.C4_Var, Z.Net.C4_FS, Z.Net.C4_Log_DB, etc.
  *   - Z.ZDB2.* for data store support (modern ZDB2 route)
  *
  * This unit is part of the Z-series storage ecosystem. It sits at the
  * application layer, using the C4 framework (which itself uses ZDB2 for
  * persistent services like UserDB, FS, Var, Log, etc.). It does not directly
  * implement storage; instead it orchestrates the deployment of C4 services
  * that rely on ZDB2-based data engines. For legacy storage (Z.ZDB.Engine,
  * Z.ZDB.ObjectData_LIB), those are retained for backward compatibility but
  * are not recommended for new projects; modern C4 services are ZDB2-native.
  *
  * Use cases:
  *   - Deploy a C4 server cluster via shell scripts or command line.
  *   - Create an interactive console application for system administrators.
  *   - Automate startup of distributed C4 nodes with retry and keep-alive.
  *
  * The main entry points are C40_Extract_CmdLine() to parse and build the
  * network, and C40_Execute_Main_Loop() to start the main loop with a console
  * command interpreter.
  ******************************************************************************
  *
  * C4 Console Script Quick Reference
  *
  * This section provides a concise reference for all C4 script commands and
  * configuration variables that can be used in C4_Extract_CmdLine() or
  * directly in the C4 console application (C4AppTemplate).
  *
  * All commands are evaluated as expressions in the scripting engine.
  * For string parameters, use single or double quotes (e.g., '127.0.0.1').
  * Numeric parameters (port, timers) are plain integers.
  * Boolean parameters can be True/False or 1/0.
  *
  * Most commands have multiple aliases; use whichever is convenient.
  *
  * The dependency string ("depend") specifies which C4 service type(s) to
  * start or connect to. It can be a single identifier (e.g., 'DP') or multiple
  * identifiers separated by '|<>' (e.g., 'DP|<>UserDB'). Each identifier may
  * have optional parameters after '@', e.g., 'UserDB@SafeCheckTime=60000'.
  *
  * For detailed service parameters, refer to the respective service units.
  *
  * Example of a typical startup script for a DP server and a client:
  *   Service('0.0.0.0','127.0.0.1',8008,'DP')
  *   KeepAlive('127.0.0.1',8008,'DP')
  *
  * In shell, combine commands with commas (win) or separate lines (linux):
  *   C4.exe "Service('0.0.0.0','127.0.0.1',8008,'DP')" "KeepAlive('127.0.0.1',8008,'DP')"
  *
  * ----------------------------------------------------------------------------
  * 1. Service Commands (Server-side)
  * ----------------------------------------------------------------------------
  *   Service ( listen_ip, local_ip, port, depend )
  *   Service ( local_ip, port, depend )   // listen_ip auto-detected from local_ip
  *   Aliases: Server, Serv, Listen, Listening
  *   Creates and starts a C4 physics service with specified listening IP and port,
  *   and builds the dependent services listed in 'depend'.
  *
  * ----------------------------------------------------------------------------
  * 2. Client Commands (Client-side)
  * ----------------------------------------------------------------------------
  *   Client ( ip, port, depend )
  *   Aliases: Cli, Tunnel, Connect, Connection, Net, Build
  *   Connects to a remote C4 physics service at ip:port and builds the dependent
  *   clients listed in 'depend'. No auto-retry on failure.
  *
  *   Auto ( ip, port, depend [, Min_Workload ] )
  *   Aliases: AutoClient, AutoCli, AutoTunnel, AutoConnect, AutoConnection,
  *            AutoNet, AutoBuild
  *   Same as Client, but automatically searches for a suitable service via the
  *   DP discovery mechanism. If Min_Workload = True (default False), it connects
  *   to the service with the minimal workload among matching ones.
  *   Fails if no DP service is available.
  *
  *   KeepAlive ( ip, port, depend [, Min_Workload ] )
  *   Aliases: KeepAliveClient, KeepAliveCli, KeepAliveTunnel, KeepAliveConnect,
  *            KeepAliveConnection, KeepAliveNet, KeepAliveBuild
  *   Like Auto, but designed for deployment scenarios: it will continuously
  *   retry the connection if it fails, making it suitable for environments
  *   where startup order is not guaranteed. It also enables auto-reconnect
  *   after disconnection. The internal flag Auto_Repair_First_BuildDependNetwork_Fault
  *   is set to True automatically.
  *
  * ----------------------------------------------------------------------------
  * 3. Utility Commands
  * ----------------------------------------------------------------------------
  *   Wait ( milliseconds )
  *   Sleep ( milliseconds )
  *   Pauses script execution for the specified time (useful for sequencing).
  *
  *   Quiet ( Boolean )
  *   SetQuiet ( Boolean )
  *   Enables/disables quiet mode (suppresses most log output).
  *
  *   Title ( string )
  *   Sets the window title (GUI mode only).
  *
  *   AppTitle ( string )
  *   Sets the application title (GUI mode only).
  *
  *   DisableUI ( string )
  *   Disables UI interaction (GUI mode only).
  *
  *   Timer ( milliseconds )
  *   Sets the main loop timer interval for GUI mode.
  *
  * ----------------------------------------------------------------------------
  * 4. Configuration Variables (can be set before other commands)
  * ----------------------------------------------------------------------------
  *   The following variables can be assigned as "Name = Value" expressions
  *   (e.g., "SafeCheckTime = 60000"). They affect global C4 behavior.
  *
  *   Root (string)                 : Working directory for C4 data files.
  *                                   Default: executable path.
  *   Password (string)             : Authentication password for P2PVM and C4 network.
  *                                   Default: 'DTC40@ZSERVER'.
  *   SafeCheckTime (integer ms)    : Periodic safe-check interval for services.
  *                                   Default: 45*1000 ms.
  *   PhysicsReconnectionDelayTime (float sec) : Reconnection delay after disconnect.
  *                                   Default: 5.0 sec.
  *   UpdateServiceInfoDelayTime (integer ms): DP info update interval.
  *                                   Default: 1000 ms.
  *   PhysicsServiceTimeout (integer ms): Idle timeout for physics services.
  *                                   Default: 15 minutes.
  *   PhysicsTunnelTimeout (integer ms): Idle timeout for physics tunnels.
  *                                   Default: 15 minutes.
  *   KillIDCFaultTimeout (integer ms): Time after which a disconnected client
  *                                   is considered IDC-faulted and cleaned up.
  *                                   Default: 7 days.
  *
  * ----------------------------------------------------------------------------
  * 5. Example of a Full Deployment Script
  * ----------------------------------------------------------------------------
  *   // First set configuration
  *   Root('/var/c4/')
  *   Password('MySecurePassword')
  *   SafeCheckTime(30000)
  *
  *   // Start a DP service and a UserDB service on same port
  *   Service('0.0.0.0', '192.168.1.100', 8008, 'DP|<>UserDB@SafeCheckTime=10000')
  *
  *   // Start a client that keeps reconnecting
  *   KeepAlive('192.168.1.100', 8008, 'DP')
  *
  *   // Wait a bit, then start another client
  *   Wait(2000)
  *   Client('192.168.1.100', 8008, 'MyCustomService')
  *
  * ----------------------------------------------------------------------------
  * 6. Aliases Quick Reference
  * ----------------------------------------------------------------------------
  *   Service  : Server, Serv, Listen, Listening
  *   Client   : Cli, Tunnel, Connect, Connection, Net, Build
  *   Auto     : AutoClient, AutoCli, AutoTunnel, AutoConnect, AutoConnection, AutoNet, AutoBuild
  *   KeepAlive: KeepAliveClient, KeepAliveCli, KeepAliveTunnel, KeepAliveConnect, KeepAliveConnection, KeepAliveNet, KeepAliveBuild
  *   Wait     : Sleep
  *   Quiet    : SetQuiet
  *
  * ----------------------------------------------------------------------------
  * 7. Important Notes
  * ----------------------------------------------------------------------------
  *   - KeepAlive and Auto require a working DP service in the network for
  *     service discovery; Client does not.
  *   - The 'depend' parameter can be a single identifier or a composite
  *     expression with parameters (e.g., 'UserDB@Identifier_HashPool=8*1024*1024').
  *   - In Windows shell, escape quotes properly; in Linux, use single quotes.
  *   - For headless servers, use the Console version of C4AppTemplate.
  *
  * See also: Z.Net.C4_Console_APP unit for implementation details.
  ******************************************************************************
*)
unit Z.Net.C4_Console_APP;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses
{$IFDEF FPC}
  Z.FPC.GenericList,
{$ENDIF FPC}
  Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib, Z.Status,
  Z.ListEngine, Z.HashList.Templet, Z.Expression, Z.OpCode, Z.Parsing, Z.DFE, Z.TextDataEngine,
  Z.Json, Z.Geometry2D, Z.Geometry3D, Z.Number,
  Z.MemoryStream,
  Z.ZDB.ObjectData_LIB, Z.ZDB, Z.ZDB.Engine, Z.ZDB.LocalManager,
  Z.ZDB.FileIndexPackage_LIB, Z.ZDB.FilePackage_LIB, Z.ZDB.ItemStream_LIB, Z.ZDB.HashField_LIB, Z.ZDB.HashItem_LIB,
  Z.ZDB2, Z.ZDB2.FileEncoder,
  Z.Net, Z.Net.C4, Z.Net.PhysicsIO;

var
  { Array of command-line parameters extracted from the system command line. }
  { Assigned by C40_Init_AppParamFromSystemCmdLine or by caller. }
  C40AppParam: U_StringArray;

  { Text style (Pascal, C, etc.) used for parsing script expressions. }
  { Default is tsPascal; can be changed before calling C40_Extract_CmdLine. }
  C40AppParsingTextStyle: TTextStyle;

  { Event interface for physics tunnel events (e.g., connect/disconnect). }
  { Can be assigned by user to receive tunnel lifecycle callbacks. }
  On_C40_PhysicsTunnel_Event_Console: IC40_PhysicsTunnel_Event;

  { Event interface for physics service events (e.g., start/stop, link). }
  { Can be assigned by user to receive service lifecycle callbacks. }
  On_C40_PhysicsService_Event_Console: IC40_PhysicsService_Event;

  { -------------------------------------------------------------------------- }
  { Public API }
  { -------------------------------------------------------------------------- }

  { Copies the system command-line parameters (ParamStr) into C40AppParam. }
  { Typically called at program startup before C40_Extract_CmdLine. }
procedure C40_Init_AppParamFromSystemCmdLine;

{ Parses the parameters stored in C40AppParam and builds the C4 network. }
{ Returns True if at least one service or tunnel was successfully initialized. }
function C40_Extract_CmdLine(): Boolean; overload;

{ Parses the given parameter array instead of using C40AppParam. }
function C40_Extract_CmdLine(const Param_: U_StringArray): Boolean; overload;

{ Parses the given parameter array with a specified text style for expressions. }
function C40_Extract_CmdLine(const TextStyle_: TTextStyle; const Param_: U_StringArray): Boolean; overload;

{ Starts the main application loop with an interactive console. }
{ This loop continuously processes C4 progress and reads user input for commands. }
{ It exits when the user types 'exit' in the console. }
procedure C40_Execute_Main_Loop;

implementation

uses Variants;

type
  TCmd_Net_Info_ = record
    listen_ip: string;
    ip: string;
    port: word;
    depend: string;
    isAuto, Min_Workload: Boolean;
    KeepAlive_Connected: Boolean;
    procedure Init;
  end;

  TCmd_Net_Info_List = TGenericsList<TCmd_Net_Info_>;

  TCommand_Script = class(TCore_Object_Intermediate)
  private
    function Do_Config(OpRunTime: TOpCustomRunTime; OP_RT_Data: POpRTData; var OP_Param: TOpParam): Variant;
    function Do_KeepAlive_Client(var OP_Param: TOpParam): Variant;
    function Do_AutoClient(var OP_Param: TOpParam): Variant;
    function Do_Client(var OP_Param: TOpParam): Variant;
    function Do_Service(var OP_Param: TOpParam): Variant;
    function Do_Sleep(var OP_Param: TOpParam): Variant;
  public
    opRT: TOpCustomRunTime;
    Config: THashStringList;
    ConfigIsUpdate: Boolean;
    Client_NetInfo_List: TCmd_Net_Info_List;
    Service_NetInfo_List: TCmd_Net_Info_List;
    constructor Create;
    destructor Destroy; override;
    procedure RegApi;
    procedure Execute(Expression: U_String);
  end;

procedure TCmd_Net_Info_.Init;
begin
  listen_ip := '';
  ip := '';
  port := 0;
  depend := '';
  isAuto := False;
  Min_Workload := False;
  KeepAlive_Connected := False;
end;

function TCommand_Script.Do_Config(OpRunTime: TOpCustomRunTime; OP_RT_Data: POpRTData; var OP_Param: TOpParam): Variant;
begin
  if length(OP_Param) > 0 then
    begin
      Config.SetDefaultValue(OP_RT_Data^.Name, VarToStr(OP_Param[0]));
      Result := True;
      ConfigIsUpdate := True;
    end
  else
      Result := Config[OP_RT_Data^.Name];
end;

function TCommand_Script.Do_KeepAlive_Client(var OP_Param: TOpParam): Variant;
var
  net_info_: TCmd_Net_Info_;
begin
  net_info_.Init;
  net_info_.listen_ip := '';
  net_info_.ip := OP_Param[0];
  net_info_.port := OP_Param[1];
  net_info_.depend := OP_Param[2];
  net_info_.isAuto := False;
  if length(OP_Param) > 3 then
      net_info_.Min_Workload := OP_Param[3]
  else
      net_info_.Min_Workload := False;
  net_info_.KeepAlive_Connected := True;
  Client_NetInfo_List.Add(net_info_);
  Result := True;
end;

function TCommand_Script.Do_AutoClient(var OP_Param: TOpParam): Variant;
var
  net_info_: TCmd_Net_Info_;
begin
  net_info_.Init;
  net_info_.listen_ip := '';
  net_info_.ip := OP_Param[0];
  net_info_.port := OP_Param[1];
  net_info_.depend := OP_Param[2];
  net_info_.isAuto := True;
  if length(OP_Param) > 3 then
      net_info_.Min_Workload := OP_Param[3]
  else
      net_info_.Min_Workload := False;
  net_info_.KeepAlive_Connected := False;
  Client_NetInfo_List.Add(net_info_);
  Result := True;
end;

function TCommand_Script.Do_Client(var OP_Param: TOpParam): Variant;
var
  net_info_: TCmd_Net_Info_;
begin
  net_info_.Init;
  net_info_.listen_ip := '';
  net_info_.ip := OP_Param[0];
  net_info_.port := OP_Param[1];
  net_info_.depend := OP_Param[2];
  net_info_.isAuto := False;
  net_info_.Min_Workload := False;
  net_info_.KeepAlive_Connected := False;
  Client_NetInfo_List.Add(net_info_);
  Result := True;
end;

function TCommand_Script.Do_Service(var OP_Param: TOpParam): Variant;
var
  net_info_: TCmd_Net_Info_;
begin
  net_info_.Init;
  if length(OP_Param) > 3 then
    begin
      net_info_.listen_ip := OP_Param[0];
      net_info_.ip := OP_Param[1];
      net_info_.port := OP_Param[2];
      net_info_.depend := OP_Param[3];
      net_info_.isAuto := False;
      net_info_.Min_Workload := False;
      net_info_.KeepAlive_Connected := False;
      Service_NetInfo_List.Add(net_info_);
    end
  else if length(OP_Param) = 3 then
    begin
      net_info_.ip := OP_Param[0];
      if Z.Net.IsIPv4(net_info_.ip) then
          net_info_.listen_ip := '0.0.0.0'
      else if Z.Net.IsIPV6(net_info_.ip) then
          net_info_.listen_ip := '::'
      else if Is_IPC_Addr(net_info_.ip) then
          net_info_.listen_ip := net_info_.ip
      else
          net_info_.listen_ip := '0.0.0.0';

      net_info_.port := OP_Param[1];
      net_info_.depend := OP_Param[2];
      net_info_.isAuto := False;
      net_info_.Min_Workload := False;
      net_info_.KeepAlive_Connected := False;
      Service_NetInfo_List.Add(net_info_);
    end;
  Result := True;
end;

function TCommand_Script.Do_Sleep(var OP_Param: TOpParam): Variant;
begin
  TCompute.Sleep(OP_Param[0]);
  Result := True;
end;

constructor TCommand_Script.Create;
begin
  inherited Create;
  opRT := TOpCustomRunTime.Create;

  Config := THashStringList.Create;
  ConfigIsUpdate := False;

  Client_NetInfo_List := TCmd_Net_Info_List.Create;
  Service_NetInfo_List := TCmd_Net_Info_List.Create;
end;

destructor TCommand_Script.Destroy;
begin
  disposeObject(Client_NetInfo_List);
  disposeObject(Service_NetInfo_List);
  disposeObject(opRT);
  disposeObject(Config);
  inherited Destroy;
end;

procedure TCommand_Script.RegApi;
var
  L: TListPascalString;
  i: Integer;
begin
  L := TListPascalString.Create;
  Config.GetNameList(L);
  for i := 0 to L.Count - 1 do
    begin
      opRT.Reg_RT_OpM(L[i], Do_Config)^.Category := 'C4 Param variant';
    end;
  disposeObject(L);

  opRT.Reg_Param_OpM('KeepAlive', Do_KeepAlive_Client)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('KeepAliveClient', Do_KeepAlive_Client)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('KeepAliveCli', Do_KeepAlive_Client)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('KeepAliveTunnel', Do_KeepAlive_Client)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('KeepAliveConnect', Do_KeepAlive_Client)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('KeepAliveConnection', Do_KeepAlive_Client)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('KeepAliveNet', Do_KeepAlive_Client)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('KeepAliveBuild', Do_KeepAlive_Client)^.Category := 'C4 Param Command';

  opRT.Reg_Param_OpM('Auto', Do_AutoClient)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('AutoClient', Do_AutoClient)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('AutoCli', Do_AutoClient)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('AutoTunnel', Do_AutoClient)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('AutoConnect', Do_AutoClient)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('AutoConnection', Do_AutoClient)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('AutoNet', Do_AutoClient)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('AutoBuild', Do_AutoClient)^.Category := 'C4 Param Command';

  opRT.Reg_Param_OpM('Client', Do_Client)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('Cli', Do_Client)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('Tunnel', Do_Client)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('Connect', Do_Client)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('Connection', Do_Client)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('Net', Do_Client)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('Build', Do_Client)^.Category := 'C4 Param Command';

  opRT.Reg_Param_OpM('Service', Do_Service)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('Server', Do_Service)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('Serv', Do_Service)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('Listen', Do_Service)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('Listening', Do_Service)^.Category := 'C4 Param Command';

  opRT.Reg_Param_OpM('Wait', Do_Sleep)^.Category := 'C4 Param Command';
  opRT.Reg_Param_OpM('Sleep', Do_Sleep)^.Category := 'C4 Param Command';
end;

procedure TCommand_Script.Execute(Expression: U_String);
begin
  EvaluateExpressionValue(False, C40AppParsingTextStyle, Expression, opRT);
end;

procedure C40_Init_AppParamFromSystemCmdLine;
var
  i: Integer;
begin
  SetLength(C40AppParam, ParamCount);
  for i := 1 to ParamCount do
      C40AppParam[i - 1] := ParamStr(i);
end;

function C40_Extract_CmdLine(): Boolean;
var
  error_: Boolean;
  IsInited_: Boolean;
  cmd_script_: TCommand_Script;
  i, j: Integer;
  net_info_: TCmd_Net_Info_;
  arry: TC40_DependNetworkInfoArray;
  c4_opt: THashStringList;
  phy_: TC40_PhysicsTunnel;
begin
  Result := False;
  if length(C40AppParam) = 0 then
      exit;
  error_ := False;
  IsInited_ := False;
  try
    cmd_script_ := TCommand_Script.Create;
    Z.Net.C4.C40WriteConfig(cmd_script_.Config);
    cmd_script_.Config.SetDefaultValue('Root', Z.Net.C4.C40_RootPath);
    cmd_script_.Config.SetDefaultValue('Password', Z.Net.C4.C40_Password);
    cmd_script_.RegApi;

    for i := low(C40AppParam) to high(C40AppParam) do
      begin
        // ignore none c4 param
        if (not umlMultipleMatch([
              '-Task:*', '-TaskID:*', // Protected Param
              '-minimized', 'minimized', '-min', 'min', // Protected Param
              '-Max_Mem_Protected:*', '-Max_Memory:*', '-Memory:*', '-Mem:*', 'mem:*', 'memory:*', // Protected Param
              '-NUMA:*', 'NUMA:*', '-NODE:*', 'Node:*', // Protected Param
              '-D3D', '-D3D', '-D2D', '-GPU', '-SOFT', '-GrayTheme', '-DefaultTheme' // fmx app param
              ], C40AppParam[i])) and
          ((Ignore_Command_Line.Count <= 0) or (not umlMultipleMatch(Ignore_Command_Line, C40AppParam[i]))) then
            cmd_script_.Execute(C40AppParam[i]);
      end;

    if (not error_) and (cmd_script_.Client_NetInfo_List.Count > 0) then
      begin
        for i := 0 to cmd_script_.Client_NetInfo_List.Count - 1 do
          begin
            net_info_ := cmd_script_.Client_NetInfo_List[i];
            if (IsMobile) and (Is_IPC_Addr(net_info_.listen_ip) or Is_IPC_Addr(net_info_.ip)) then
              begin
                  DoStatus('no support "%s"', [net_info_.ip]);
                  error_ := True;
              end;
            arry := ExtractDependInfo(net_info_.depend);
            for j := Low(arry) to high(arry) do
              if FindRegistedC40(arry[j].Typ) = nil then
                begin
                  DoStatus('no found %s', [arry[j].Typ.Text]);
                  error_ := True;
                end;
          end;
      end;

    if (not error_) and (cmd_script_.Service_NetInfo_List.Count > 0) then
      begin
        for i := 0 to cmd_script_.Service_NetInfo_List.Count - 1 do
          begin
            net_info_ := cmd_script_.Service_NetInfo_List[i];
            if (IsMobile) and (Is_IPC_Addr(net_info_.listen_ip) or Is_IPC_Addr(net_info_.ip)) then
              begin
                  DoStatus('no support "%s"', [net_info_.ip]);
                  error_ := True;
              end;
            arry := ExtractDependInfo(net_info_.depend);
            for j := Low(arry) to high(arry) do
              if FindRegistedC40(arry[j].Typ) = nil then
                begin
                  DoStatus('no found %s', [arry[j].Typ.Text]);
                  error_ := True;
                end;
          end;
      end;

    if not error_ then
      begin
        if cmd_script_.ConfigIsUpdate then
          begin
            Z.Net.C4.C40ReadConfig(cmd_script_.Config);
            Z.Net.C4.C40_RootPath := cmd_script_.Config.GetDefaultValue('Root', Z.Net.C4.C40_RootPath);
            if not umlDirectoryExists(Z.Net.C4.C40_RootPath) then
                umlCreateDirectory(Z.Net.C4.C40_RootPath);
            Z.Net.C4.C40_Password := cmd_script_.Config.GetDefaultValue('Password', Z.Net.C4.C40_Password);
          end;

        if cmd_script_.Service_NetInfo_List.Count > 0 then
          begin
            IsInited_ := True;
            for i := 0 to cmd_script_.Service_NetInfo_List.Count - 1 do
              begin
                net_info_ := cmd_script_.Service_NetInfo_List[i];

                with Z.Net.C4.TC40_PhysicsService.Create(net_info_.listen_ip, net_info_.ip, net_info_.port, Get_Physics_Server_Class(net_info_.listen_ip, net_info_.ip).Create) do
                  begin
                    AutoFreePhysicsTunnel := True;
                    BuildDependNetwork(net_info_.depend);
                    OnEvent := On_C40_PhysicsService_Event_Console;
                    StartService;
                    IsInited_ := IsInited_ or Activted;
                  end;
              end;
          end;

        if cmd_script_.Client_NetInfo_List.Count > 0 then
          begin
            IsInited_ := True;
            for i := 0 to cmd_script_.Client_NetInfo_List.Count - 1 do
              begin
                net_info_ := cmd_script_.Client_NetInfo_List[i];

                if net_info_.KeepAlive_Connected then
                  begin
                    C40_PhysicsTunnelPool.Auto_Repair_First_BuildDependNetwork_Fault := True;
                  end;

                if net_info_.isAuto then
                    Z.Net.C4.C40_PhysicsTunnelPool.SearchServiceAndBuildConnection(net_info_.ip, net_info_.port, not net_info_.Min_Workload, net_info_.depend, On_C40_PhysicsTunnel_Event_Console)
                else
                    Z.Net.C4.C40_PhysicsTunnelPool.GetOrCreatePhysicsTunnel(net_info_.ip, net_info_.port, net_info_.depend, On_C40_PhysicsTunnel_Event_Console);
              end;
          end;
      end;

    cmd_script_.Free;

{$IFDEF DEBUG}
    if IsInited_ then
      begin
        c4_opt := THashStringList.Create;
        C40WriteConfig(c4_opt);
        DoStatus('');
        DoStatus('C40 Network Options');
        DoStatus(c4_opt.AsText);
        disposeObject(c4_opt);
        DoStatus('');
      end;
{$ENDIF DEBUG}
  except
  end;
  Result := IsInited_;
end;

function C40_Extract_CmdLine(const Param_: U_StringArray): Boolean;
begin
  C40AppParam := Param_;
  Result := C40_Extract_CmdLine();
end;

function C40_Extract_CmdLine(const TextStyle_: TTextStyle; const Param_: U_StringArray): Boolean;
begin
  C40AppParsingTextStyle := TextStyle_;
  C40AppParam := Param_;
  Result := C40_Extract_CmdLine();
end;

type
  TMain_Loop_Instance__ = class(TCore_Object_Intermediate)
  private
    exit_signal: Boolean;
    procedure Do_Check_On_Exit;
  public
    constructor Create;
    procedure Wait();
  end;

procedure TMain_Loop_Instance__.Do_Check_On_Exit;
var
  n: string;
  cH: TC40_Console_Help;
begin
  TCompute.Set_Thread_Info('C4 Console-help Thread');
  cH := nil;
  repeat
    TCompute.Sleep(100);
    Readln(n);
    n := umlTrimSpace(n);
    if cH = nil then
        cH := TC40_Console_Help.Create;
    if n <> '' then
        cH.Run_HelpCmd(n);
  until cH.IsExit;
  DisposeObjectAndNil(cH);
  exit_signal := True;
end;

constructor TMain_Loop_Instance__.Create;
begin
  inherited Create;
  exit_signal := False;
  TCompute.RunM_NP(Do_Check_On_Exit);
end;

procedure TMain_Loop_Instance__.Wait;
begin
  while not exit_signal do
      Z.Net.C4.C40Progress;
end;

procedure C40_Execute_Main_Loop;
begin
  with TMain_Loop_Instance__.Create do
    begin
      Wait;
      Free;
    end;
end;

initialization

SetLength(C40AppParam, 0);
C40AppParsingTextStyle := TTextStyle.tsPascal;

try
  On_C40_PhysicsTunnel_Event_Console := nil;
  On_C40_PhysicsService_Event_Console := nil;
except
end;

finalization

try
  On_C40_PhysicsTunnel_Event_Console := nil;
  On_C40_PhysicsService_Event_Console := nil;
except
end;

end.
 
