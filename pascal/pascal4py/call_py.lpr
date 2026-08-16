program call_py;

{$APPTYPE CONSOLE}

{$ifdef FPC}
  {$mode delphi}{$H+}
  {$modeswitch advancedrecords}
  {$CODEPAGE UTF8}
{$endif}

uses
{$IFDEF UNIX}
  cthreads,
{$ENDIF}
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  SysUtils,
  Z.Core,
  Z.PascalStrings,
  Z.UPascalStrings,
  Z.UnicodeMixedLib,
  Z.Status,
  z_api_hubtool_import,
  z_api_hubtool_helper;

const
  BRIDGE_APP = 'HttpBridge';          // 桥接应用名
  BRIDGE_ENDPOINT = '127.0.0.1:9898'; // 桥接 TCP 地址
  MY_APP_NAME = 'PascalApp';          // 本应用名
  TIMEOUT_MS = 5000;

{ ----------------------------------------------------------------------------
  回调函数：pascal_echo – 供远程调用，返回带前缀的字符串
-----------------------------------------------------------------------------}
procedure PascalEchoCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
var
  InHnd, OutHnd: TDataHandle;
  Msg: string;
begin
  InHnd := TDataHandle.Create(TDataHnd(Input), False);
  OutHnd := TDataHandle.Create(TDataHnd(Output), False);
  try
    InHnd.SetPos(0);
    if InHnd.ReadString(Msg) then
    begin
      DoStatus('[PascalEcho] Received: %s', [Msg]);
      OutHnd.WriteString('Pascal says: ' + Msg);
    end
    else
      OutHnd.WriteString('Error: no message');
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

{ ----------------------------------------------------------------------------
  辅助：从 TDataHnd 读取原始 UTF-8 字符串（兼容桥接的 #0 结尾格式）
-----------------------------------------------------------------------------}
function ReadRawString(Hnd: TDataHnd): string;
var
  Size: Int64;
  Buf: PByte;
begin
  Result := '';
  Size := API_GetSize(Hnd);
  if Size = 0 then Exit;
  Buf := API_GetBuffer(Hnd);
  if Buf = nil then Exit;
  // 去除末尾的 #0（如果存在）
  while (Size > 0) and (Buf[Size - 1] = 0) do Dec(Size);
  if Size = 0 then Exit;
  SetString(Result, PAnsiChar(Buf), Size);
  Result := UTF8Decode(Result);
end;

{ ----------------------------------------------------------------------------
  辅助：通过桥接调用远程 API（使用 JSON 数组参数）
  写入格式：纯 UTF-8 字符串 + #0（与桥接期望一致）
-----------------------------------------------------------------------------}
function CallBridgeAPI(const APIName: string; const Args: array of const; out ResultStr: string): Boolean;
var
  Param, Res: TDataHandle;
  ReqJson: string;
  i: Integer;
  Utf8Bytes: UTF8String;
begin
  Result := False;
  ResultStr := '';

  // 构建 JSON 数组参数
  ReqJson := '[';
  for i := 0 to High(Args) do
  begin
    if i > 0 then ReqJson := ReqJson + ',';
    case Args[i].VType of
      vtString: ReqJson := ReqJson + '"' + string(Args[i].VString^) + '"';
      vtAnsiString: ReqJson := ReqJson + '"' + string(Args[i].VAnsiString) + '"';
      vtPChar: ReqJson := ReqJson + '"' + string(Args[i].VPChar) + '"';
      vtInteger: ReqJson := ReqJson + IntToStr(Args[i].VInteger);
      vtInt64: ReqJson := ReqJson + IntToStr(Args[i].VInt64^);
      vtBoolean: ReqJson := ReqJson + BoolToStr(Args[i].VBoolean, True);
      vtExtended: ReqJson := ReqJson + FloatToStr(Args[i].VExtended^);
      vtChar: ReqJson := ReqJson + '"' + string(Args[i].VChar) + '"';
    else
      ReqJson := ReqJson + '"?"';
    end;
  end;
  ReqJson := ReqJson + ']';

  Param := TDataHandle.Create(APIName);
  try
    // 直接写入原始 UTF-8 字符串 + #0（不写长度前缀）
    Utf8Bytes := UTF8String(ReqJson) + #0;
    Param.WriteBuffer(Utf8Bytes[1], Length(Utf8Bytes));

    Res := CallApp(BRIDGE_APP, Param, TIMEOUT_MS);
    try
      if Res = nil then
      begin
        DoStatus('CallApp returned nil');
        Exit;
      end;
      ResultStr := ReadRawString(Res.Handle);
      if ResultStr <> '' then
        Result := True
      else
        DoStatus('Response is empty');
    finally
      Res.Free;
    end;
  finally
    Param.Free;
  end;
end;

{ ----------------------------------------------------------------------------
  主程序
-----------------------------------------------------------------------------}
var
  App: TAppHandle;
  ResultStr: string;
  Success: Boolean;
begin
  DoStatus('=== Pascal Cross Test ===');
  DoStatus('Connecting to bridge at ' + BRIDGE_ENDPOINT);

  // 1. 创建本应用并注册 API
  App := TAppHandle.Create(MY_APP_NAME, 'Pascal cross test');
  App.RegisterCall('pascal_echo', 'Echo with prefix', nil, @PascalEchoCallback);

  // 2. 连接到桥接（TCP），并暴露本应用
  ResetPrepare;
  PrepareClient(BRIDGE_ENDPOINT, App);
  if not PrepareDone then
  begin
    DoStatus('Failed to connect to bridge');
    Halt(1);
  end;
  DoStatus('Connected to bridge, app registered.');

  // 3. 调用 PHP 的 php_echo
  DoStatus('');
  DoStatus('Calling PHP webhook (php_echo)...');
  Success := CallBridgeAPI('php_echo', ['Hello from Pascal!'], ResultStr);
  if Success then
    DoStatus('PHP echo response: %s', [ResultStr])
  else
    DoStatus('PHP echo call failed');

  // 4. 调用 Python 的 py_echo
  DoStatus('');
  DoStatus('Calling Python webhook (py_echo)...');
  Success := CallBridgeAPI('py_echo', ['Pascal says hi'], ResultStr);
  if Success then
    DoStatus('Python echo response: %s', [ResultStr])
  else
    DoStatus('Python echo call failed');

  DoStatus('');
  DoStatus('Test completed. Press Enter to exit...');
  ReadLn;

  // 清理
  ExitMainThread;
  Shutdown;
  App.Free;
end.
