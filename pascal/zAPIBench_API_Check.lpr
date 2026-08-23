program zAPIBench_API_Check;

{
  项目: zAPI 单 API 功能验证工具 (API Check)
  功能: 顺序调用 BenchServer 的 20 个 API，逐个验证功能正确性
  编译: fpc zAPIBench_API_Check.lpr
  运行: ./zAPIBench_API_Check

  用途:
    - 开发阶段验证所有 API 是否正常工作
    - 定位问题 API (与压测客户端配合使用)
    - 检查 API 接口变更后的兼容性
}

{$ifdef FPC}
  {$mode delphi}{$H+}
  {$modeswitch advancedrecords}
  {$CODEPAGE UTF8}
{$endif}

{$APPTYPE CONSOLE}

uses
{$IFDEF UNIX}
  cthreads,
{$ENDIF}
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  Classes, SysUtils, DateUtils,
  z_api_hubtool_helper,
  z_api_hubtool_import,
  Z.Core,
  Z.Json,
  Z.PascalStrings,
  Z.UPascalStrings,
  Z.UnicodeMixedLib;

{ ----------------------------------------------------------------------------
  UTF-8 控制台输出
-----------------------------------------------------------------------------}
function ToUTF8(const S: string): UTF8String;
begin
{$IFDEF FPC}
  if StringCodePage(S) = CP_UTF8 then
    Result := UTF8String(S)
  else
    Result := UTF8Encode(S);
{$ELSE}
  Result := UTF8Encode(S);
{$ENDIF}
end;

procedure ConsoleWrite(const S: string);
var
  UTF8Str: UTF8String;
{$IFDEF MSWINDOWS}
  WStr: UnicodeString;
  Written: DWORD;
{$ENDIF}
begin
  if not IsConsole then Exit;
  UTF8Str := ToUTF8(S);
{$IFDEF MSWINDOWS}
  WStr := UTF8Decode(UTF8Str);
  WriteConsoleW(GetStdHandle(STD_OUTPUT_HANDLE),
                PWideChar(WStr), Length(WStr), Written, nil);
{$ELSE}
  Write(UTF8Str);
{$ENDIF}
end;

procedure ConsoleWriteLn(const S: string = '');
begin
  if S <> '' then ConsoleWrite(S);
{$IFDEF MSWINDOWS}
  ConsoleWrite(sLineBreak);
{$ELSE}
  WriteLn;
{$ENDIF}
end;

procedure ConsoleWriteLnColor(const S: string; const IsOK: Boolean);
begin
  if IsOK then
    ConsoleWriteLn('[通过] ' + S)
  else
    ConsoleWriteLn('[失败] ' + S);
end;

{ ----------------------------------------------------------------------------
  配置
-----------------------------------------------------------------------------}
const
  SERVER_APP = 'BenchServer';
  SERVER_ENDPOINT = 'ipc:bench_service';
  TIMEOUT_MS = 5000;

{ ----------------------------------------------------------------------------
  远程调用辅助函数
-----------------------------------------------------------------------------}
function DoRemoteCall(const APIName, RequestJSON: string; out ResponseJSON: string; out ErrorMsg: string): Boolean;
var
  HndData, HndRes: API.TDataHandle;
begin
  Result := False;
  ResponseJSON := '';
  ErrorMsg := '';

  HndData := API.TDataHandle.Create(APIName);
  try
    HndData.WriteString(RequestJSON);
    HndRes := API.CallApp(SERVER_APP, HndData, TIMEOUT_MS);
    try
      if HndRes = nil then
      begin
        ErrorMsg := 'CallApp 返回 nil';
        Exit;
      end;
      HndRes.SetPos(0);
      if not HndRes.ReadString(ResponseJSON) then
      begin
        ErrorMsg := '读取响应字符串失败';
        Exit;
      end;
      Result := True;
    finally
      HndRes.Free;
    end;
  finally
    HndData.Free;
  end;
end;

{ ----------------------------------------------------------------------------
  各 API 测试函数
-----------------------------------------------------------------------------}
procedure TestAdd;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  a, b, sum: Integer;
begin
  a := 10; b := 20;
  Req := Format('{"a":%d,"b":%d}', [a, b]);
  ConsoleWriteLn(Format('[add] 请求: %s', [Req]));

  if DoRemoteCall('add', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[add] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('add 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('result') then
      begin
        sum := jo.I['result'];
        if sum = a + b then
          ConsoleWriteLnColor(Format('add(%d,%d)=%d 正确', [a, b, sum]), True)
        else
          ConsoleWriteLnColor(Format('add(%d,%d) 结果 %d 期望 %d', [a, b, sum, a+b]), False);
      end
      else
        ConsoleWriteLnColor('add 响应缺少 result 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('add 调用失败: ' + Err, False);
end;

procedure TestSub;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  a, b, diff: Integer;
begin
  a := 50; b := 30;
  Req := Format('{"a":%d,"b":%d}', [a, b]);
  ConsoleWriteLn(Format('[sub] 请求: %s', [Req]));

  if DoRemoteCall('sub', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[sub] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('sub 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('result') then
      begin
        diff := jo.I['result'];
        if diff = a - b then
          ConsoleWriteLnColor(Format('sub(%d,%d)=%d 正确', [a, b, diff]), True)
        else
          ConsoleWriteLnColor(Format('sub(%d,%d) 结果 %d 期望 %d', [a, b, diff, a-b]), False);
      end
      else
        ConsoleWriteLnColor('sub 响应缺少 result 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('sub 调用失败: ' + Err, False);
end;

procedure TestMul;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  a, b, prod: Integer;
begin
  a := 6; b := 7;
  Req := Format('{"a":%d,"b":%d}', [a, b]);
  ConsoleWriteLn(Format('[mul] 请求: %s', [Req]));

  if DoRemoteCall('mul', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[mul] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('mul 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('result') then
      begin
        prod := jo.I['result'];
        if prod = a * b then
          ConsoleWriteLnColor(Format('mul(%d,%d)=%d 正确', [a, b, prod]), True)
        else
          ConsoleWriteLnColor(Format('mul(%d,%d) 结果 %d 期望 %d', [a, b, prod, a*b]), False);
      end
      else
        ConsoleWriteLnColor('mul 响应缺少 result 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('mul 调用失败: ' + Err, False);
end;

procedure TestDiv;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  a, b: Integer;
  quot: Double;
begin
  a := 10; b := 3;
  Req := Format('{"a":%d,"b":%d}', [a, b]);
  ConsoleWriteLn(Format('[div] 请求: %s', [Req]));

  if DoRemoteCall('div', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[div] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('div 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('result') then
      begin
        quot := jo.F['result'];
        if Abs(quot - (a / b)) < 0.0001 then
          ConsoleWriteLnColor(Format('div(%d,%d)=%f 正确', [a, b, quot]), True)
        else
          ConsoleWriteLnColor(Format('div(%d,%d) 结果 %f 期望 %f', [a, b, quot, a/b]), False);
      end
      else
        ConsoleWriteLnColor('div 响应缺少 result 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('div 调用失败: ' + Err, False);
end;

procedure TestEval;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
begin
  Req := '{"expr":"1+2*3"}';
  ConsoleWriteLn(Format('[eval] 请求: %s', [Req]));

  if DoRemoteCall('eval', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[eval] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('eval 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('result') then
        ConsoleWriteLnColor(Format('eval(1+2*3)=%s', [jo.S['result']]), True)
      else
        ConsoleWriteLnColor('eval 响应缺少 result 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('eval 调用失败: ' + Err, False);
end;

procedure TestMD5;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  data, md5: string;
begin
  data := 'hello';
  Req := Format('{"data":"%s"}', [data]);
  ConsoleWriteLn(Format('[md5] 请求: %s', [Req]));

  if DoRemoteCall('md5', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[md5] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('md5 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('md5') then
      begin
        md5 := jo.S['md5'];
        if Length(md5) = 32 then
          ConsoleWriteLnColor(Format('md5("hello")=%s 长度正确', [md5]), True)
        else
          ConsoleWriteLnColor(Format('md5("hello") 长度 %d 期望 32', [Length(md5)]), False);
      end
      else
        ConsoleWriteLnColor('md5 响应缺少 md5 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('md5 调用失败: ' + Err, False);
end;

procedure TestSHA1;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  data, sha1: string;
begin
  data := 'hello';
  Req := Format('{"data":"%s"}', [data]);
  ConsoleWriteLn(Format('[sha1] 请求: %s', [Req]));

  if DoRemoteCall('sha1', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[sha1] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('sha1 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('sha1') then
      begin
        sha1 := jo.S['sha1'];
        if Length(sha1) = 40 then
          ConsoleWriteLnColor(Format('sha1("hello")=%s 长度正确', [sha1]), True)
        else
          ConsoleWriteLnColor(Format('sha1("hello") 长度 %d 期望 40', [Length(sha1)]), False);
      end
      else
        ConsoleWriteLnColor('sha1 响应缺少 sha1 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('sha1 调用失败: ' + Err, False);
end;

procedure TestSHA256;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  data, sha256: string;
begin
  data := 'hello';
  Req := Format('{"data":"%s"}', [data]);
  ConsoleWriteLn(Format('[sha256] 请求: %s', [Req]));

  if DoRemoteCall('sha256', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[sha256] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('sha256 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('sha256') then
      begin
        sha256 := jo.S['sha256'];
        if Length(sha256) = 64 then
          ConsoleWriteLnColor(Format('sha256("hello")=%s 长度正确', [sha256]), True)
        else
          ConsoleWriteLnColor(Format('sha256("hello") 长度 %d 期望 64', [Length(sha256)]), False);
      end
      else
        ConsoleWriteLnColor('sha256 响应缺少 sha256 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('sha256 调用失败: ' + Err, False);
end;

procedure TestSHA512;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  data, sha512: string;
begin
  data := 'hello';
  Req := Format('{"data":"%s"}', [data]);
  ConsoleWriteLn(Format('[sha512] 请求: %s', [Req]));

  if DoRemoteCall('sha512', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[sha512] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('sha512 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('sha512') then
      begin
        sha512 := jo.S['sha512'];
        if Length(sha512) = 128 then
          ConsoleWriteLnColor(Format('sha512("hello")=%s 长度正确', [sha512]), True)
        else
          ConsoleWriteLnColor(Format('sha512("hello") 长度 %d 期望 128', [Length(sha512)]), False);
      end
      else
        ConsoleWriteLnColor('sha512 响应缺少 sha512 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('sha512 调用失败: ' + Err, False);
end;

procedure TestAESEncrypt;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  data, key, cipher: string;
begin
  data := 'secret';
  key := 'password';
  Req := Format('{"data":"%s","key":"%s"}', [data, key]);
  ConsoleWriteLn(Format('[aes_encrypt] 请求: %s', [Req]));

  if DoRemoteCall('aes_encrypt', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[aes_encrypt] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('aes_encrypt 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('cipher') then
      begin
        cipher := jo.S['cipher'];
        if Length(cipher) > 0 then
          ConsoleWriteLnColor(Format('aes_encrypt 成功，密文长度 %d', [Length(cipher)]), True)
        else
          ConsoleWriteLnColor('aes_encrypt 返回空密文', False);
      end
      else
        ConsoleWriteLnColor('aes_encrypt 响应缺少 cipher 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('aes_encrypt 调用失败: ' + Err, False);
end;

procedure TestAESDecrypt;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  cipher, key, plain: string;
begin
  cipher := 'aGVsbG8=';
  key := 'password';
  Req := Format('{"cipher":"%s","key":"%s"}', [cipher, key]);
  ConsoleWriteLn(Format('[aes_decrypt] 请求: %s', [Req]));

  if DoRemoteCall('aes_decrypt', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[aes_decrypt] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('aes_decrypt 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('plain') then
      begin
        plain := jo.S['plain'];
        ConsoleWriteLnColor(Format('aes_decrypt 成功，明文: %s', [plain]), True);
      end
      else
        ConsoleWriteLnColor('aes_decrypt 响应缺少 plain 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('aes_decrypt 调用失败: ' + Err, False);
end;

procedure TestBase64Encode;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  data, encoded: string;
begin
  data := 'hello';
  Req := Format('{"data":"%s"}', [data]);
  ConsoleWriteLn(Format('[base64_encode] 请求: %s', [Req]));

  if DoRemoteCall('base64_encode', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[base64_encode] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('base64_encode 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('base64') then
      begin
        encoded := jo.S['base64'];
        if Length(encoded) > 0 then
          ConsoleWriteLnColor(Format('base64_encode("hello")=%s', [encoded]), True)
        else
          ConsoleWriteLnColor('base64_encode 返回空字符串', False);
      end
      else
        ConsoleWriteLnColor('base64_encode 响应缺少 base64 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('base64_encode 调用失败: ' + Err, False);
end;

procedure TestBase64Decode;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  encoded, decoded: string;
begin
  encoded := 'aGVsbG8=';
  Req := Format('{"base64":"%s"}', [encoded]);
  ConsoleWriteLn(Format('[base64_decode] 请求: %s', [Req]));

  if DoRemoteCall('base64_decode', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[base64_decode] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('base64_decode 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('decoded') then
      begin
        decoded := jo.S['decoded'];
        if decoded = 'hello' then
          ConsoleWriteLnColor(Format('base64_decode("aGVsbG8=")="%s" 正确', [decoded]), True)
        else
          ConsoleWriteLnColor(Format('base64_decode 结果 "%s" 期望 "hello"', [decoded]), False);
      end
      else
        ConsoleWriteLnColor('base64_decode 响应缺少 decoded 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('base64_decode 调用失败: ' + Err, False);
end;

procedure TestRandom;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  minVal, maxVal, value: Integer;
begin
  minVal := 1; maxVal := 100;
  Req := Format('{"min":%d,"max":%d}', [minVal, maxVal]);
  ConsoleWriteLn(Format('[random] 请求: %s', [Req]));

  if DoRemoteCall('random', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[random] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('random 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('value') then
      begin
        value := jo.I['value'];
        if (value >= minVal) and (value <= maxVal) then
          ConsoleWriteLnColor(Format('random(%d,%d)=%d 在区间内', [minVal, maxVal, value]), True)
        else
          ConsoleWriteLnColor(Format('random(%d,%d)=%d 超出区间', [minVal, maxVal, value]), False);
      end
      else
        ConsoleWriteLnColor('random 响应缺少 value 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('random 调用失败: ' + Err, False);
end;

procedure TestUpper;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  str, result: string;
begin
  str := 'hello';
  Req := Format('{"str":"%s"}', [str]);
  ConsoleWriteLn(Format('[upper] 请求: %s', [Req]));

  if DoRemoteCall('upper', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[upper] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('upper 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('result') then
      begin
        result := jo.S['result'];
        if result = 'HELLO' then
          ConsoleWriteLnColor(Format('upper("hello")="%s" 正确', [result]), True)
        else
          ConsoleWriteLnColor(Format('upper("hello")="%s" 期望 "HELLO"', [result]), False);
      end
      else
        ConsoleWriteLnColor('upper 响应缺少 result 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('upper 调用失败: ' + Err, False);
end;

procedure TestLower;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  str, result: string;
begin
  str := 'HELLO';
  Req := Format('{"str":"%s"}', [str]);
  ConsoleWriteLn(Format('[lower] 请求: %s', [Req]));

  if DoRemoteCall('lower', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[lower] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('lower 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('result') then
      begin
        result := jo.S['result'];
        if result = 'hello' then
          ConsoleWriteLnColor(Format('lower("HELLO")="%s" 正确', [result]), True)
        else
          ConsoleWriteLnColor(Format('lower("HELLO")="%s" 期望 "hello"', [result]), False);
      end
      else
        ConsoleWriteLnColor('lower 响应缺少 result 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('lower 调用失败: ' + Err, False);
end;

procedure TestReverse;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  str, result: string;
begin
  str := 'hello';
  Req := Format('{"str":"%s"}', [str]);
  ConsoleWriteLn(Format('[reverse] 请求: %s', [Req]));

  if DoRemoteCall('reverse', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[reverse] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('reverse 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('result') then
      begin
        result := jo.S['result'];
        if result = 'olleh' then
          ConsoleWriteLnColor(Format('reverse("hello")="%s" 正确', [result]), True)
        else
          ConsoleWriteLnColor(Format('reverse("hello")="%s" 期望 "olleh"', [result]), False);
      end
      else
        ConsoleWriteLnColor('reverse 响应缺少 result 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('reverse 调用失败: ' + Err, False);
end;

procedure TestTimestamp;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  ts: Int64;
begin
  Req := '{}';
  ConsoleWriteLn('[timestamp] 请求: {}');

  if DoRemoteCall('timestamp', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[timestamp] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('timestamp 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('timestamp') then
      begin
        ts := jo.I64['timestamp'];
        ConsoleWriteLnColor(Format('timestamp 成功，值: %d', [ts]), True);
      end
      else
        ConsoleWriteLnColor('timestamp 响应缺少 timestamp 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('timestamp 调用失败: ' + Err, False);
end;

procedure TestSleep;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  ms: Integer;
begin
  ms := 100;
  Req := Format('{"ms":%d}', [ms]);
  ConsoleWriteLn(Format('[sleep] 请求: %s', [Req]));

  if DoRemoteCall('sleep', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[sleep] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('sleep 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('status') then
        ConsoleWriteLnColor(Format('sleep(%d) 返回 status="%s"', [ms, jo.S['status']]), True)
      else
        ConsoleWriteLnColor('sleep 响应缺少 status 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('sleep 调用失败: ' + Err, False);
end;

procedure TestEcho;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  msg, result: string;
begin
  msg := 'Hello, zAPI!';
  Req := Format('{"msg":"%s"}', [msg]);
  ConsoleWriteLn(Format('[echo] 请求: %s', [Req]));

  if DoRemoteCall('echo', Req, Resp, Err) then
  begin
    ConsoleWriteLn(Format('[echo] 响应: %s', [Resp]));
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('error') then
        ConsoleWriteLnColor('echo 返回错误: ' + jo.S['error'], False)
      else if jo.Exists('echo') then
      begin
        result := jo.S['echo'];
        if result = msg then
          ConsoleWriteLnColor(Format('echo 正确返回 "%s"', [result]), True)
        else
          ConsoleWriteLnColor(Format('echo 返回 "%s" 期望 "%s"', [result, msg]), False);
      end
      else
        ConsoleWriteLnColor('echo 响应缺少 echo 字段', False);
    finally
      jo.Free;
    end;
  end
  else
    ConsoleWriteLnColor('echo 调用失败: ' + Err, False);
end;

{ ----------------------------------------------------------------------------
  主程序
-----------------------------------------------------------------------------}
var
  input_: string;
begin
  ConsoleWriteLn('╔══════════════════════════════════════════════════════════════╗');
  ConsoleWriteLn('║       zAPI 单 API 功能验证工具 (API Check)  v1.0           ║');
  ConsoleWriteLn('║       顺序测试 BenchServer 的 20 个 API                     ║');
  ConsoleWriteLn('╚══════════════════════════════════════════════════════════════╝');
  ConsoleWriteLn('');

  ConsoleWriteLn(Format('目标服务: %s @ %s', [SERVER_APP, SERVER_ENDPOINT]));
  ConsoleWriteLn('');

  // 连接服务器
  API.ResetPrepare;
  API.PrepareClient(SERVER_ENDPOINT, nil);

  if not API.PrepareDone then
  begin
    ConsoleWriteLn('连接服务器失败，请确保 BenchServer 已启动');
    API.Shutdown;
    Halt(1);
  end;

  ConsoleWriteLn('已连接到 ' + SERVER_ENDPOINT);
  ConsoleWriteLn('');
  ConsoleWriteLn('开始测试...');
  ConsoleWriteLn('');

  // 依次测试每个 API
  TestAdd;      ConsoleWriteLn('');
  TestSub;      ConsoleWriteLn('');
  TestMul;      ConsoleWriteLn('');
  TestDiv;      ConsoleWriteLn('');
  TestEval;     ConsoleWriteLn('');
  TestMD5;      ConsoleWriteLn('');
  TestSHA1;     ConsoleWriteLn('');
  TestSHA256;   ConsoleWriteLn('');
  TestSHA512;   ConsoleWriteLn('');
  TestAESEncrypt; ConsoleWriteLn('');
  TestAESDecrypt; ConsoleWriteLn('');
  TestBase64Encode; ConsoleWriteLn('');
  TestBase64Decode; ConsoleWriteLn('');
  TestRandom;   ConsoleWriteLn('');
  TestUpper;    ConsoleWriteLn('');
  TestLower;    ConsoleWriteLn('');
  TestReverse;  ConsoleWriteLn('');
  TestTimestamp; ConsoleWriteLn('');
  TestSleep;    ConsoleWriteLn('');
  TestEcho;     ConsoleWriteLn('');

  ConsoleWriteLn('所有测试完成！输入 exit 退出...');
  repeat
    ReadLn(input_);
  until umlTrimSpace(input_).Same('exit');

  API.ExitMainThread;
  API.Shutdown;
end.
