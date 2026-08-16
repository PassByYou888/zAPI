program zAPIBenchClient;

{
  项目: zAPI 压测客户端 (Benchmark Client)
  功能: 对 BenchServer 进行 20 API 并发压测，统计各 API 延迟分布和吞吐量
  编译: fpc zAPIBenchClient.lpr
  运行: ./zAPIBenchClient

  压测配置:
    - 默认 50 并发线程，每线程 100 次调用
    - 轮询调用 20 个 API，确保覆盖所有接口
    - 统计平均/最小/最大延迟 (微秒级)

  高延迟原因分析 (实测平均 ~175ms, 理论应 <1ms):
    1. 服务端 JSON 序列化/反序列化开销
       - 每个请求/响应都经过 TZ_JsonObject 解析和生成
       - 涉及 UTF-8 编解码和内存分配

    2. 服务端日志输出 (ConsoleWriteLn)
       - 高并发下控制台 I/O 成为严重瓶颈
       - 每次调用至少输出一次日志

    3. sleep API 的累积影响
       - sleep 回调中执行 Sleep(1~10ms)
       - 虽然单次很小，但 250 次调用累积达 250~2500ms

    4. C4 线程池调度开销
       - 回调在 C4 线程池中执行，存在上下文切换

    5. TDataHandle 的多次底层读写
       - ReadJsonString/WriteJsonString 涉及多次 Handle 操作

    优化建议:
      - 生产环境关闭服务端 ConsoleWriteLn
      - 使用二进制协议替代 JSON 序列化
      - 使用更轻量的序列化方式 (如 MessagePack)
      - 增加 C4 线程池大小
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
  Classes, SysUtils, Variants, DateUtils, SyncObjs, z_api_hubtool_helper, z_api_hubtool_import, Z.Core, Z.Status, Z.UnicodeMixedLib, Z.Json, Z.PascalStrings, Z.UPascalStrings;

 { ----------------------------------------------------------------------------
  配置参数
-----------------------------------------------------------------------------}
const
  DEFAULT_THREADS = 50;          // 并发线程数 (可调整)
  DEFAULT_CALLS_PER_THREAD = 20; // 每个线程调用次数
  TIMEOUT_MS = 10000;             // 远程调用超时 (毫秒)
  SERVER_APP = 'BenchServer';    // 目标服务器应用名
  SERVER_ENDPOINT = 'ipc:bench_service'; // 服务器地址 (IPC 或 TCP)

type
  TAPIStats = record
    Name: string;                // API 名称
    TotalCalls: integer;         // 总调用数
    SuccessCalls: integer;       // 成功数
    TotalTime: int64;            // 总耗时 (微秒)
    MinTime: int64;              // 最小耗时 (微秒)
    MaxTime: int64;              // 最大耗时 (微秒)
  end;
  PAPIStats = ^TAPIStats;

var
  Stats: array[0..19] of TAPIStats;  // 20 个 API 的统计
  StatsLock: TCriticalSection;       // 统计锁
  Running: boolean;                  // 运行标志
  GlobalCallCounter: int64;          // 全局调用计数器
  GlobalCallCounterLock: TCriticalSection;

{ ----------------------------------------------------------------------------
  UTF-8 控制台输出 (兼容 Windows/Linux/macOS)
-----------------------------------------------------------------------------}
function ToUTF8(const S: string): utf8string;
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
  UTF8Str: utf8string;
  {$IFDEF MSWINDOWS}
  WStr: unicodestring;
  Written: DWORD;
  {$ENDIF}
begin
  if not IsConsole then Exit;
  UTF8Str := ToUTF8(S);
  {$IFDEF MSWINDOWS}
  WStr := UTF8Decode(UTF8Str);
  WriteConsoleW(GetStdHandle(STD_OUTPUT_HANDLE),
    pwidechar(WStr), Length(WStr), Written, nil);
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
  远程调用辅助函数
-----------------------------------------------------------------------------}
function DoRemoteCall(const AppName, APIName, RequestJSON: string; out ResponseJSON: string; out ErrorMsg: string): boolean;
var
  HndData, HndRes: TDataHandle;
begin
  Result := False;
  ResponseJSON := '';
  ErrorMsg := '';

  HndData := TDataHandle.Create(APIName);
  try
    HndData.WriteString(RequestJSON);
    HndRes := CallApp(AppName, HndData, TIMEOUT_MS);
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
  各 API 调用封装 (随机生成参数)
-----------------------------------------------------------------------------}
function CallAdd(out outVal: integer): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  a, b: integer;
begin
  Result := False;
  a := Random(100);
  b := Random(100);
  Req := Format('{"a":%d,"b":%d}', [a, b]);

  if DoRemoteCall(SERVER_APP, 'add', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('result') then
      begin
        outVal := jo.I['result'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallSub(out outVal: integer): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  a, b: integer;
begin
  Result := False;
  a := Random(100);
  b := Random(100);
  Req := Format('{"a":%d,"b":%d}', [a, b]);

  if DoRemoteCall(SERVER_APP, 'sub', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('result') then
      begin
        outVal := jo.I['result'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallMul(out outVal: integer): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  a, b: integer;
begin
  Result := False;
  a := Random(100);
  b := Random(100);
  Req := Format('{"a":%d,"b":%d}', [a, b]);

  if DoRemoteCall(SERVER_APP, 'mul', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('result') then
      begin
        outVal := jo.I['result'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallDiv(out outVal: double): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  a, b: integer;
begin
  Result := False;
  a := Random(100) + 1;
  b := Random(10) + 1;
  Req := Format('{"a":%d,"b":%d}', [a, b]);

  if DoRemoteCall(SERVER_APP, 'div', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('result') then
      begin
        outVal := jo.F['result'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallEval(out outVal: string): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
begin
  Result := False;
  Req := '{"expr":"' + IntToStr(Random(100)) + '+' + IntToStr(Random(100)) + '*2"}';

  if DoRemoteCall(SERVER_APP, 'eval', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('result') then
      begin
        outVal := jo.S['result'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallMD5(out outVal: string): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  Data: string;
begin
  Result := False;
  Data := 'test_' + IntToStr(Random(9999));
  Req := Format('{"data":"%s"}', [Data]);

  if DoRemoteCall(SERVER_APP, 'md5', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('md5') then
      begin
        outVal := jo.S['md5'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallSHA1(out outVal: string): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  Data: string;
begin
  Result := False;
  Data := 'test_' + IntToStr(Random(9999));
  Req := Format('{"data":"%s"}', [Data]);

  if DoRemoteCall(SERVER_APP, 'sha1', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('sha1') then
      begin
        outVal := jo.S['sha1'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallSHA256(out outVal: string): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  Data: string;
begin
  Result := False;
  Data := 'test_' + IntToStr(Random(9999));
  Req := Format('{"data":"%s"}', [Data]);

  if DoRemoteCall(SERVER_APP, 'sha256', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('sha256') then
      begin
        outVal := jo.S['sha256'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallSHA512(out outVal: string): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  Data: string;
begin
  Result := False;
  Data := 'test_' + IntToStr(Random(9999));
  Req := Format('{"data":"%s"}', [Data]);

  if DoRemoteCall(SERVER_APP, 'sha512', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('sha512') then
      begin
        outVal := jo.S['sha512'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallAESEncrypt(out outVal: string): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  Data, key: string;
begin
  Result := False;
  Data := 'secret_' + IntToStr(Random(999));
  key := 'key_' + IntToStr(Random(999));
  Req := Format('{"data":"%s","key":"%s"}', [Data, key]);

  if DoRemoteCall(SERVER_APP, 'aes_encrypt', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('cipher') then
      begin
        outVal := jo.S['cipher'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallAESDecrypt(out outVal: string): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  cipher, key: string;
begin
  Result := False;
  cipher := 'c2VjcmV0Xyc=';
  key := 'key_123';
  Req := Format('{"cipher":"%s","key":"%s"}', [cipher, key]);

  if DoRemoteCall(SERVER_APP, 'aes_decrypt', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('plain') then
      begin
        outVal := jo.S['plain'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallBase64Encode(out outVal: string): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  Data: string;
begin
  Result := False;
  Data := 'data_' + IntToStr(Random(999));
  Req := Format('{"data":"%s"}', [Data]);

  if DoRemoteCall(SERVER_APP, 'base64_encode', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('base64') then
      begin
        outVal := jo.S['base64'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallBase64Decode(out outVal: string): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  encoded: string;
begin
  Result := False;
  encoded := 'aGVsbG8=';
  Req := Format('{"base64":"%s"}', [encoded]);

  if DoRemoteCall(SERVER_APP, 'base64_decode', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('decoded') then
      begin
        outVal := jo.S['decoded'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallRandom(out outVal: integer): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  minVal, maxVal: integer;
begin
  Result := False;
  minVal := 1;
  maxVal := 1000;
  Req := Format('{"min":%d,"max":%d}', [minVal, maxVal]);

  if DoRemoteCall(SERVER_APP, 'random', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('value') then
      begin
        outVal := jo.I['value'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallUpper(out outVal: string): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  str: string;
begin
  Result := False;
  str := 'hello_' + IntToStr(Random(999));
  Req := Format('{"str":"%s"}', [str]);

  if DoRemoteCall(SERVER_APP, 'upper', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('result') then
      begin
        outVal := jo.S['result'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallLower(out outVal: string): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  str: string;
begin
  Result := False;
  str := 'HELLO_' + IntToStr(Random(999));
  Req := Format('{"str":"%s"}', [str]);

  if DoRemoteCall(SERVER_APP, 'lower', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('result') then
      begin
        outVal := jo.S['result'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallReverse(out outVal: string): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  str: string;
begin
  Result := False;
  str := 'reverse_' + IntToStr(Random(999));
  Req := Format('{"str":"%s"}', [str]);

  if DoRemoteCall(SERVER_APP, 'reverse', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('result') then
      begin
        outVal := jo.S['result'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallTimestamp(out outVal: int64): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
begin
  Result := False;
  Req := '{}';

  if DoRemoteCall(SERVER_APP, 'timestamp', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('timestamp') then
      begin
        outVal := jo.I64['timestamp'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallSleep(out outVal: string): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  ms: integer;
begin
  Result := False;
  ms := Random(10) + 1;
  Req := Format('{"ms":%d}', [ms]);

  if DoRemoteCall(SERVER_APP, 'sleep', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('status') then
      begin
        outVal := jo.S['status'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

function CallEcho(out outVal: string): boolean;
var
  Req, Resp, Err: string;
  jo: TZ_JsonObject;
  msg: string;
begin
  Result := False;
  msg := 'echo_' + IntToStr(Random(999));
  Req := Format('{"msg":"%s"}', [msg]);

  if DoRemoteCall(SERVER_APP, 'echo', Req, Resp, Err) then
  begin
    jo := TZ_JsonObject.Create;
    try
      jo.ParseText(Resp);
      if jo.Exists('echo') then
      begin
        outVal := jo.S['echo'];
        Result := True;
      end;
    finally
      jo.Free;
    end;
  end;
end;

{ ----------------------------------------------------------------------------
  工作线程
-----------------------------------------------------------------------------}
type
  TWorkerThread = class(TThread)
  private
    FThreadIndex: integer;
    FCallsPerThread: integer;
    FCompletedCalls: integer;
  public
    constructor Create(ThreadIndex, CallsPerThread: integer);
    procedure Execute; override;
  end;

constructor TWorkerThread.Create(ThreadIndex, CallsPerThread: integer);
begin
  inherited Create(False);
  FThreadIndex := ThreadIndex;
  FCallsPerThread := CallsPerThread;
  FCompletedCalls := 0;
  FreeOnTerminate := False;
end;

procedure TWorkerThread.Execute;
var
  i, idx: integer;
  StartTime, EndTime: int64;
  Elapsed: int64;
  Success: boolean;
  tmpInt: integer;
  tmpFloat: double;
  tmpStr: string;
  tmpInt64: int64;
begin
  for i := 1 to FCallsPerThread do
  begin
    if not Running then Break;

    // 轮询调用 20 个 API (0-19)
    idx := (i - 1) mod 20;

    StartTime := GetTickCount64 * 1000; // 微秒

    Success := False;
    case idx of
      0: Success := CallAdd(tmpInt);
      1: Success := CallSub(tmpInt);
      2: Success := CallMul(tmpInt);
      3: Success := CallDiv(tmpFloat);
      4: Success := CallEval(tmpStr);
      5: Success := CallMD5(tmpStr);
      6: Success := CallSHA1(tmpStr);
      7: Success := CallSHA256(tmpStr);
      8: Success := CallSHA512(tmpStr);
      9: Success := CallAESEncrypt(tmpStr);
      10: Success := CallAESDecrypt(tmpStr);
      11: Success := CallBase64Encode(tmpStr);
      12: Success := CallBase64Decode(tmpStr);
      13: Success := CallRandom(tmpInt);
      14: Success := CallUpper(tmpStr);
      15: Success := CallLower(tmpStr);
      16: Success := CallReverse(tmpStr);
      17: Success := CallTimestamp(tmpInt64);
      18: Success := CallSleep(tmpStr);
      19: Success := CallEcho(tmpStr);
    end;

    EndTime := GetTickCount64 * 1000;
    Elapsed := EndTime - StartTime;

    // 更新统计 (线程安全)
    StatsLock.Enter;
    try
      with Stats[idx] do
      begin
        Inc(TotalCalls);
        if Success then
        begin
          Inc(SuccessCalls);
          TotalTime := TotalTime + Elapsed;
          if (MinTime = 0) or (Elapsed < MinTime) then MinTime := Elapsed;
          if Elapsed > MaxTime then MaxTime := Elapsed;
        end;
      end;
    finally
      StatsLock.Leave;
    end;

    // 更新全局计数器 (线程安全)
    GlobalCallCounterLock.Enter;
    try
      Inc(GlobalCallCounter);
    finally
      GlobalCallCounterLock.Leave;
    end;

    Inc(FCompletedCalls);
    if i mod 10 = 0 then Sleep(0);
  end;
end;

{ ----------------------------------------------------------------------------
  主程序
-----------------------------------------------------------------------------}
var
  i: integer;
  ThreadCount, CallsPerThread: integer;
  Threads: array of TWorkerThread;
  StartTime, EndTime: TDateTime;
  TotalCalls, TotalSuccess: integer;
  TotalElapsed: int64;
  QPS: double;
  input_: string;

  apiNames: array[0..19] of string = ('add', 'sub', 'mul', 'div', 'eval', 'md5', 'sha1', 'sha256', 'sha512', 'aes_encrypt', 'aes_decrypt', 'base64_encode', 'base64_decode', 'random', 'upper', 'lower', 'reverse', 'timestamp', 'sleep', 'echo');

begin
  Randomize;

  ConsoleWriteLn('╔══════════════════════════════════════════════════════════════╗');
  ConsoleWriteLn('║       zAPI 压测客户端 (Benchmark Client)  v2.0               ║');
  ConsoleWriteLn('║       对 BenchServer 进行 20 API 并发压测                    ║');
  ConsoleWriteLn('╚══════════════════════════════════════════════════════════════╝');
  ConsoleWriteLn('');

  ThreadCount := DEFAULT_THREADS;
  CallsPerThread := DEFAULT_CALLS_PER_THREAD;

  ConsoleWriteLn('压测配置:');
  ConsoleWriteLn('   目标服务  : ' + SERVER_APP + ' @ ' + SERVER_ENDPOINT);
  ConsoleWriteLn('   并发线程数: ' + IntToStr(ThreadCount));
  ConsoleWriteLn('   每线程调用: ' + IntToStr(CallsPerThread));
  ConsoleWriteLn('   总调用次数: ' + IntToStr(ThreadCount * CallsPerThread));
  ConsoleWriteLn('');

  ConsoleWriteLn('高延迟原因分析 (仅供参考):');
  ConsoleWriteLn('   1. 服务端 JSON 序列化/反序列化 (TZ_JsonObject)');
  ConsoleWriteLn('   2. 服务端控制台日志输出 (ConsoleWriteLn)');
  ConsoleWriteLn('   3. sleep API 的累积阻塞 (1-10ms/次)');
  ConsoleWriteLn('   4. C4 线程池调度和上下文切换开销');
  ConsoleWriteLn('   5. TDataHandle 多次底层读写操作');
  ConsoleWriteLn('');
  ConsoleWriteLn('优化建议:');
  ConsoleWriteLn('   - 生产环境关闭服务端 ConsoleWriteLn');
  ConsoleWriteLn('   - 使用二进制协议替代 JSON 序列化');
  ConsoleWriteLn('   - 增加 C4 线程池大小');
  ConsoleWriteLn('   - 使用更轻量的序列化方式 (如 MessagePack)');
  ConsoleWriteLn('');

  // 初始化统计锁
  StatsLock := TCriticalSection.Create;
  GlobalCallCounterLock := TCriticalSection.Create;
  for i := 0 to 19 do
  begin
    Stats[i].Name := apiNames[i];
    Stats[i].TotalCalls := 0;
    Stats[i].SuccessCalls := 0;
    Stats[i].TotalTime := 0;
    Stats[i].MinTime := 0;
    Stats[i].MaxTime := 0;
  end;

  // 连接服务器
  ResetPrepare;
  PrepareClient(SERVER_ENDPOINT, nil);

  if not PrepareDone then
  begin
    ConsoleWriteLn('连接服务器失败，请确保 BenchServer 已启动');
    Shutdown;
    Halt(1);
  end;

  ConsoleWriteLn('已连接到 ' + SERVER_ENDPOINT);
  ConsoleWriteLn('');

  // 预热 (确保连接就绪)
  ConsoleWriteLn('预热中...');
  CallAdd(i);
  CallSub(i);
  CallMul(i);

  ConsoleWriteLn('开始压测...');
  ConsoleWriteLn('');

  Running := True;
  GlobalCallCounter := 0;
  StartTime := Now;

  // 创建并启动工作线程
  SetLength(Threads, ThreadCount);
  for i := 0 to ThreadCount - 1 do
    Threads[i] := TWorkerThread.Create(i, CallsPerThread);

  // 等待所有线程完成
  for i := 0 to ThreadCount - 1 do
  begin
    Threads[i].WaitFor;
    Threads[i].Free;
  end;

  EndTime := Now;
  Running := False;

  // 汇总统计
  TotalCalls := 0;
  TotalSuccess := 0;
  TotalElapsed := 0;
  for i := 0 to 19 do
  begin
    TotalCalls := TotalCalls + Stats[i].TotalCalls;
    TotalSuccess := TotalSuccess + Stats[i].SuccessCalls;
    TotalElapsed := TotalElapsed + Stats[i].TotalTime;
  end;

  if TotalElapsed > 0 then
    QPS := TotalSuccess / (TotalElapsed / 1000000)
  else
    QPS := 0;

  // 输出结果
  ConsoleWriteLn('');
  ConsoleWriteLn('压测结果汇总');
  ConsoleWriteLn('  总调用数    : ' + IntToStr(TotalCalls));
  ConsoleWriteLn('  成功数      : ' + IntToStr(TotalSuccess));
  ConsoleWriteLn('  失败数      : ' + IntToStr(TotalCalls - TotalSuccess));
  ConsoleWriteLn('  成功率      : ' + Format('%.2f%%', [(TotalSuccess / TotalCalls) * 100]));
  ConsoleWriteLn('  总耗时      : ' + Format('%.2f 秒', [(EndTime - StartTime) * SecsPerDay]));
  ConsoleWriteLn('  吞吐量 (QPS): ' + Format('%.2f', [QPS]));
  ConsoleWriteLn('');

  ConsoleWriteLn('各 API 详细统计:');
  ConsoleWriteLn('  API 名称           调用数   成功数  平均(μs)  最小(μs)  最大(μs)');
  ConsoleWriteLn('  --------------------------------------------------------------');
  for i := 0 to 19 do
  begin
    with Stats[i] do
    begin
      if SuccessCalls > 0 then
        ConsoleWriteLn(Format('  %-18s %8d %8d %10d %10d %10d', [Name, TotalCalls, SuccessCalls, TotalTime div SuccessCalls, MinTime, MaxTime]))
      else
        ConsoleWriteLn(Format('  %-18s %8d %8d %10s %10s %10s', [Name, TotalCalls, SuccessCalls, 'N/A', 'N/A', 'N/A']));
    end;
  end;

  ConsoleWriteLn('');

  ConsoleWriteLn('正在清理...');
  ExitMainThread;
  Shutdown;
  StatsLock.Free;
  GlobalCallCounterLock.Free;
  ConsoleWriteLn('压测完成！');
end.
