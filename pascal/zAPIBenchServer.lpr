program zAPIBenchServer;

{
  项目: zAPI 压测服务器 (Benchmark Server)
  功能: 提供 20 个标准 API，用于跨语言 RPC 压测和功能验证
  编译: fpc zAPIBenchServer.lpr
  运行: ./zAPIBenchServer

  支持 API 列表:
    - 算术运算: add, sub, mul, div
    - 表达式求值: eval (基于 Z.Expression)
    - 哈希计算: md5, sha1, sha256, sha512
    - 对称加密: aes_encrypt, aes_decrypt (模拟 Base64)
    - 编码转换: base64_encode, base64_decode
    - 字符串操作: upper, lower, reverse, echo
    - 工具函数: random, timestamp, sleep
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
  Classes, SysUtils, Variants, DateUtils,
  z_api_hubtool_helper,
  z_api_hubtool_import,
  Z.Core,
  Z.Status,
  Z.Expression,
  Z.OpCode,
  Z.Cipher,
  Z.UnicodeMixedLib,
  Z.Json,
  Z.Parsing,
  Z.PascalStrings,
  Z.UPascalStrings,
  Z.MemoryStream,
  Z.DFE,
  Z.ListEngine;

{ ----------------------------------------------------------------------------
  UTF-8 控制台输出（兼容 Windows/Linux/macOS）
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

{ ----------------------------------------------------------------------------
  数据句柄 JSON 辅助函数
-----------------------------------------------------------------------------}

// 从 API.TDataHandle 读取 UTF-8 字符串并解码为 TUPascalString
function ReadJsonString(h: API.TDataHandle): TUPascalString;
var
  s: string;
begin
  h.SetPos(0);
  if not h.ReadString(s) then
    Result := ''
  else
    Result := UTF8Decode(s);
end;

// 将 TUPascalString 编码为 UTF-8 并写入 API.TDataHandle
procedure WriteJsonString(h: API.TDataHandle; const value: TUPascalString);
var
  s: string;
begin
  s := UTF8Encode(value.Text);
  h.SetPos(0);
  h.SetSize(0);
  h.WriteString(s);
end;

{ ----------------------------------------------------------------------------
  API 回调函数 (cdecl, 运行在 C4 线程池中)
  注意: 所有回调必须快速返回，禁止调用 API_Call/API_Notify 以避免死锁
-----------------------------------------------------------------------------}

// 1. 整数加法: {"a":int, "b":int} -> {"result":int}
procedure add_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  a, b, sum: Integer;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      a := jo.I['a'];
      b := jo.I['b'];
      sum := a + b;
      jo.Clear;
      jo.I['result'] := sum;
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      WriteJsonString(OutHnd, '{"error":"add 失败"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 2. 整数减法: {"a":int, "b":int} -> {"result":int}
procedure sub_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  a, b, diff: Integer;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      a := jo.I['a'];
      b := jo.I['b'];
      diff := a - b;
      jo.Clear;
      jo.I['result'] := diff;
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      WriteJsonString(OutHnd, '{"error":"sub 失败"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 3. 整数乘法: {"a":int, "b":int} -> {"result":int}
procedure mul_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  a, b, prod: Integer;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      a := jo.I['a'];
      b := jo.I['b'];
      prod := a * b;
      jo.Clear;
      jo.I['result'] := prod;
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      WriteJsonString(OutHnd, '{"error":"mul 失败"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 4. 整数除法: {"a":int, "b":int} -> {"result":float} (b 不能为 0)
procedure div_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  a, b: Integer;
  quot: Double;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      a := jo.I['a'];
      b := jo.I['b'];
      if b = 0 then
        raise Exception.Create('除数不能为零');
      quot := a / b;
      jo.Clear;
      jo.F['result'] := quot;
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      on e: Exception do
        WriteJsonString(OutHnd, '{"error":"'+UTF8Encode(e.Message)+'"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 5. 表达式求值: {"expr":string, "vars":object} -> {"result":any}
// 基于 Z.Expression 引擎，支持变量传入
procedure eval_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  expr: string;
  vars: TZ_JsonObject;
  vl: THashVariantList;
  i: Integer;
  resultVal: Variant;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  vl := THashVariantList.Create;
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      expr := jo.S['expr'];
      vars := jo.O['vars'];
      if vars <> nil then
      begin
        for i := 0 to vars.Count - 1 do
          vl[vars.Names[i]] := vars.s[vars.Names[i]];
      end;
      resultVal := EvaluateExpressionValue(True, nil, False, tsPascal, expr, SystemOpRunTime, vl);
      jo.Clear;
      if VarIsStr(resultVal) then
        jo.S['result'] := VarToStr(resultVal)
      else if VarIsNumeric(resultVal) then
        jo.F['result'] := resultVal
      else if VarIsBool(resultVal) then
        jo.B['result'] := resultVal
      else
        jo.S['result'] := VarToStr(resultVal);
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      on e: Exception do
        WriteJsonString(OutHnd, '{"error":"'+UTF8Encode(e.Message)+'"}');
    end;
    if jo <> nil then jo.Free;
  finally
    vl.Free;
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 6. MD5 哈希: {"data":string} -> {"md5":string}
procedure md5_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  data: string;
  md5hex: string;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      data := jo.S['data'];
      md5hex := umlMD5Str(PByte(data), Length(data));
      jo.Clear;
      jo.S['md5'] := md5hex;
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      WriteJsonString(OutHnd, '{"error":"MD5 计算失败"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 7. SHA-1 哈希: {"data":string} -> {"sha1":string}
procedure sha1_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  data: string;
  hash: TSHA1Digest;
  hex: string;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      data := jo.S['data'];
      hash := TCipher.GenerateSHA1Hash(PByte(data), Length(data));
      hex := TCipher.BufferToHex(hash, SizeOf(hash));
      jo.Clear;
      jo.S['sha1'] := hex;
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      WriteJsonString(OutHnd, '{"error":"SHA1 计算失败"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 8. SHA-256 哈希: {"data":string} -> {"sha256":string}
procedure sha256_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  data: string;
  hash: TSHA256Digest;
  hex: string;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      data := jo.S['data'];
      hash := TCipher.GenerateSHA256Hash(PByte(data), Length(data));
      hex := TCipher.BufferToHex(hash, SizeOf(hash));
      jo.Clear;
      jo.S['sha256'] := hex;
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      WriteJsonString(OutHnd, '{"error":"SHA256 计算失败"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 9. SHA-512 哈希: {"data":string} -> {"sha512":string}
procedure sha512_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  data: string;
  hash: TSHA512Digest;
  hex: string;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      data := jo.S['data'];
      hash := TCipher.GenerateSHA512Hash(PByte(data), Length(data));
      hex := TCipher.BufferToHex(hash, SizeOf(hash));
      jo.Clear;
      jo.S['sha512'] := hex;
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      WriteJsonString(OutHnd, '{"error":"SHA512 计算失败"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 10. AES 加密 (模拟 Base64 编码): {"data":string} -> {"cipher":string, "status":"ok"}
// 注意: 仅用于压测演示，非真实 AES 加密
procedure aes_encrypt_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  data: string;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      data := jo.S['data'];
      jo.Clear;
      jo.S['cipher'] := umlEncodeLineBASE64(data);
      jo.S['status'] := 'ok';
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      WriteJsonString(OutHnd, '{"status":"error","error":"模拟加密失败"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 11. AES 解密 (模拟 Base64 解码): {"cipher":string} -> {"plain":string, "status":"ok"}
// 注意: 仅用于压测演示，非真实 AES 解密
procedure aes_decrypt_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  cipher: string;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      cipher := jo.S['cipher'];
      jo.Clear;
      jo.S['plain'] := umlDecodeLineBASE64(cipher);
      jo.S['status'] := 'ok';
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      on e: Exception do
        WriteJsonString(OutHnd, '{"status":"error","error":"'+UTF8Encode(e.Message)+'"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 12. Base64 编码: {"data":string} -> {"base64":string}
procedure base64_encode_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  data: string;
  encoded: string;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      data := jo.S['data'];
      encoded := umlEncodeLineBASE64(data);
      jo.Clear;
      jo.S['base64'] := encoded;
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      WriteJsonString(OutHnd, '{"error":"Base64 编码失败"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 13. Base64 解码: {"base64":string} -> {"decoded":string}
procedure base64_decode_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  encoded: string;
  decoded: string;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      encoded := jo.S['base64'];
      decoded := umlDecodeLineBASE64(encoded);
      jo.Clear;
      jo.S['decoded'] := decoded;
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      WriteJsonString(OutHnd, '{"error":"Base64 解码失败"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 14. 随机整数: {"min":int, "max":int} -> {"value":int}
procedure random_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  minVal, maxVal: Integer;
  rndVal: Integer;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      minVal := jo.I['min'];
      maxVal := jo.I['max'];
      if minVal > maxVal then
        raise Exception.Create('min > max');
      rndVal := umlRandomRange(minVal, maxVal);
      jo.Clear;
      jo.I['value'] := rndVal;
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      on e: Exception do
        WriteJsonString(OutHnd, '{"error":"'+UTF8Encode(e.Message)+'"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 15. 字符串转大写: {"str":string} -> {"result":string}
procedure upper_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  strVal: string;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      strVal := jo.S['str'];
      jo.Clear;
      jo.S['result'] := UpperCase(strVal);
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      WriteJsonString(OutHnd, '{"error":"转大写失败"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 16. 字符串转小写: {"str":string} -> {"result":string}
procedure lower_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  strVal: string;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      strVal := jo.S['str'];
      jo.Clear;
      jo.S['result'] := LowerCase(strVal);
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      WriteJsonString(OutHnd, '{"error":"转小写失败"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 17. 字符串反转: {"str":string} -> {"result":string}
procedure reverse_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  strVal: string;
  rev: string;
  i: Integer;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      strVal := jo.S['str'];
      SetLength(rev, Length(strVal));
      for i := 1 to Length(strVal) do
        rev[i] := strVal[Length(strVal)-i+1];
      jo.Clear;
      jo.S['result'] := rev;
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      WriteJsonString(OutHnd, '{"error":"反转失败"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 18. Unix 时间戳: {} -> {"timestamp":int64}
procedure timestamp_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  ts: Int64;
  res: TUPascalString;
begin
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      ts := DateTimeToUnix(Now);
      jo.I64['timestamp'] := ts;
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      WriteJsonString(OutHnd, '{"error":"获取时间戳失败"}');
    end;
    if jo <> nil then jo.Free;
  finally
    OutHnd.Free;
  end;
end;

// 19. 阻塞等待: {"ms":int} -> {"status":"ok"} (用于模拟耗时操作)
// 注意: 此 API 会阻塞当前线程，压测时会影响整体吞吐量
procedure sleep_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  ms: Integer;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      ms := jo.I['ms'];
      if ms < 0 then ms := 0;
      Sleep(ms);
      jo.Clear;
      jo.S['status'] := 'ok';
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      WriteJsonString(OutHnd, '{"error":"sleep 失败"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

// 20. 回显: {"msg":string} -> {"echo":string}
procedure echo_callback(trigger: Pointer; input: Pointer; output: Pointer); cdecl;
var
  InHnd, OutHnd: API.TDataHandle;
  jo: TZ_JsonObject;
  msg: string;
  res: TUPascalString;
begin
  InHnd := API.TDataHandle.Create(TDataHnd(input), False);
  OutHnd := API.TDataHandle.Create(TDataHnd(output), False);
  try
    jo := nil;
    try
      jo := TZ_JsonObject.Create;
      jo.ParseText(ReadJsonString(InHnd));
      msg := jo.S['msg'];
      jo.Clear;
      jo.S['echo'] := msg;
      res := jo.ToJSONString(False);
      WriteJsonString(OutHnd, res);
    except
      WriteJsonString(OutHnd, '{"error":"回显失败"}');
    end;
    if jo <> nil then jo.Free;
  finally
    InHnd.Free;
    OutHnd.Free;
  end;
end;

{ ----------------------------------------------------------------------------
  主程序
-----------------------------------------------------------------------------}
var
  App: API.TAppHandle;
  i: Integer;
  input_: string;
  apiNames: array[0..19] of string = (
    'add', 'sub', 'mul', 'div', 'eval', 'md5', 'sha1', 'sha256', 'sha512',
    'aes_encrypt', 'aes_decrypt', 'base64_encode', 'base64_decode', 'random',
    'upper', 'lower', 'reverse', 'timestamp', 'sleep', 'echo'
  );
begin
  ConsoleWriteLn('╔══════════════════════════════════════════════════════════════╗');
  ConsoleWriteLn('║       zAPI 压测服务器 (Benchmark Server)  v2.0               ║');
  ConsoleWriteLn('║       基于 Z-framework  &  C4 分布式服务网格                 ║');
  ConsoleWriteLn('╚══════════════════════════════════════════════════════════════╝');
  ConsoleWriteLn('');

  // 初始化加密库（确保 AES 内部状态已初始化）
  InitSysCBCAndDefaultKey(Random(High(Integer)));

  // 创建应用句柄（helper 单元自动加载动态库）
  App := API.TAppHandle.Create('BenchServer', 'zAPI 压测服务器 (20 个内置 API)');
  ConsoleWriteLn('应用句柄创建成功: "BenchServer"');

  // 注册 20 个 API
  App.RegisterCall('add', 'add(a:int, b:int) -> {result:int}  整数加法', nil, @add_callback);
  App.RegisterCall('sub', 'sub(a:int, b:int) -> {result:int}  整数减法', nil, @sub_callback);
  App.RegisterCall('mul', 'mul(a:int, b:int) -> {result:int}  整数乘法', nil, @mul_callback);
  App.RegisterCall('div', 'div(a:int, b:int) -> {result:float}  整数除法（浮点结果，b≠0）', nil, @div_callback);
  App.RegisterCall('eval', 'eval(expr:string, vars:object) -> {result:any}  表达式求值（支持变量）', nil, @eval_callback);
  App.RegisterCall('md5', 'md5(data:string) -> {md5:string}  MD5 哈希（32位十六进制）', nil, @md5_callback);
  App.RegisterCall('sha1', 'sha1(data:string) -> {sha1:string}  SHA-1 哈希（40位十六进制）', nil, @sha1_callback);
  App.RegisterCall('sha256', 'sha256(data:string) -> {sha256:string}  SHA-256 哈希（64位十六进制）', nil, @sha256_callback);
  App.RegisterCall('sha512', 'sha512(data:string) -> {sha512:string}  SHA-512 哈希（128位十六进制）', nil, @sha512_callback);
  App.RegisterCall('aes_encrypt', 'aes_encrypt(data:string, key:string) -> {cipher:string}  AES-128-CBC 加密（输出Base64）', nil, @aes_encrypt_callback);
  App.RegisterCall('aes_decrypt', 'aes_decrypt(cipher:string, key:string) -> {plain:string}  AES-128-CBC 解密', nil, @aes_decrypt_callback);
  App.RegisterCall('base64_encode', 'base64_encode(data:string) -> {base64:string}  Base64 编码', nil, @base64_encode_callback);
  App.RegisterCall('base64_decode', 'base64_decode(base64:string) -> {decoded:string}  Base64 解码', nil, @base64_decode_callback);
  App.RegisterCall('random', 'random(min:int, max:int) -> {value:int}  生成 [min, max] 区间随机整数', nil, @random_callback);
  App.RegisterCall('upper', 'upper(str:string) -> {result:string}  转大写', nil, @upper_callback);
  App.RegisterCall('lower', 'lower(str:string) -> {result:string}  转小写', nil, @lower_callback);
  App.RegisterCall('reverse', 'reverse(str:string) -> {result:string}  字符串反转', nil, @reverse_callback);
  App.RegisterCall('timestamp', 'timestamp() -> {timestamp:int64}  获取当前 Unix 时间戳（秒）', nil, @timestamp_callback);
  App.RegisterCall('sleep', 'sleep(ms:int) -> {status:"ok"}  阻塞等待指定毫秒（模拟耗时）', nil, @sleep_callback);
  App.RegisterCall('echo', 'echo(msg:string) -> {echo:string}  回显输入消息', nil, @echo_callback);

  ConsoleWriteLn('已注册 20 个 API:');
  for i := 0 to 19 do
    ConsoleWriteLn('   - ' + apiNames[i]);
  ConsoleWriteLn('');

  // 准备网络（同时监听 IPC 和 TCP）
  API.ResetPrepare;
  API.PrepareService('ipc:bench_service', 'ipc:bench_service');
  API.PrepareService('0.0.0.0', '0.0.0.0:9898');
  API.PrepareClient('ipc:bench_service', App);
  API.PrepareClient('127.0.0.1:9898', App);

  if not API.PrepareDone then
  begin
    ConsoleWriteLn('网络启动失败，请检查端口/IPC 是否被占用');
    API.Shutdown;
    Halt(1);
  end;

  ConsoleWriteLn('服务已启动，监听地址：');
  ConsoleWriteLn('   IPC   : ipc:bench_service');
  ConsoleWriteLn('   TCP   : 127.0.0.1:9898');
  ConsoleWriteLn('');
  ConsoleWriteLn('提示：输入 exit 停止服务器...');

  repeat
    ReadLn(input_);
  until umlTrimSpace(input_) = 'exit';

  // 清理资源
  ConsoleWriteLn('正在停止服务器...');
  API.ExitMainThread;
  API.Shutdown;
  App.Free;
  ConsoleWriteLn('服务器已停止');
end.
