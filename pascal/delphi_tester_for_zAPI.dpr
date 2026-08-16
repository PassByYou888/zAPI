program delphi_tester_for_zAPI;

{$APPTYPE CONSOLE}

{$R *.res}

uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  Classes, SysUtils, DateUtils, SyncObjs,
  z_api_hubtool_helper in 'z_api_hubtool_helper.pas',
  z_api_hubtool_import in 'z_api_hubtool_import.pas';

{ ----------------------------------------------------------------------------
  UTF‑8 Console Output (bypasses console code page issues)
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
  Global Callbacks (cdecl, run in library's thread pool)
-----------------------------------------------------------------------------}

{ * Addition callback: reads two Int32, writes their sum. }
procedure AddCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
var
  A, B, Sum: Integer;
begin
  if API_ReadBuffer(TDataHnd(Input), @A, SizeOf(A)) <> SizeOf(A) then Exit;
  if API_ReadBuffer(TDataHnd(Input), @B, SizeOf(B)) <> SizeOf(B) then Exit;
  Sum := A + B;
  API_WriteBuffer(TDataHnd(Output), @Sum, SizeOf(Sum));
end;

{ * Echo callback: returns the input data unchanged. }
procedure EchoCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
var
  Size: Int64;
  Buf: PByte;
begin
  Size := API_GetSize(TDataHnd(Input));
  if Size > 0 then
  begin
    GetMem(Buf, Size);
    try
      API_SetPos(TDataHnd(Input), 0);
      API_ReadBuffer(TDataHnd(Input), Buf, Size);
      API_WriteBuffer(TDataHnd(Output), Buf, Size);
    finally
      FreeMem(Buf);
    end;
  end;
end;

{ * Notification callback: prints the received UTF‑8 string. }
procedure PrintNotify(Trigger: Pointer; Input: Pointer); cdecl;
var
  Len: Int32;
  Utf8: UTF8String;
  Msg: string;
begin
  if API_ReadBuffer(TDataHnd(Input), @Len, SizeOf(Len)) <> SizeOf(Len) then Exit;
  SetLength(Utf8, Len);
  if Len > 0 then
    if API_ReadBuffer(TDataHnd(Input), @Utf8[1], Len) <> Len then Exit;
  Msg := UTF8Decode(Utf8);
  ConsoleWriteLn('[Notify] Received: ' + Msg);
end;

{ ----------------------------------------------------------------------------
  Helper overloads for type‑safe output of test results
-----------------------------------------------------------------------------}
procedure Report(const Msg: string; const Args: array of const); overload;
begin
  ConsoleWriteLn(Format(Msg, Args));
end;

procedure Report(const Msg: string); overload;
begin
  ConsoleWriteLn(Msg);
end;

procedure ReportPass(const TestName: string);
begin
  ConsoleWriteLn('[PASS] ' + TestName);
end;

procedure ReportFail(const TestName: string);
begin
  ConsoleWriteLn('[FAIL] ' + TestName);
end;

{ ----------------------------------------------------------------------------
  Global variable for concurrency test (used in TConcurrencyThread)
-----------------------------------------------------------------------------}
var
  ConcurrencyTotalCalls: Integer;

{ ----------------------------------------------------------------------------
  Thread class for concurrency test
-----------------------------------------------------------------------------}
type
  TConcurrencyThread = class(TThread)
  private
    FApp: TAppHandle;      // Reference to the application handle
    FThreadIndex: Integer; // Not used, but kept for potential diagnostics
  protected
    procedure Execute; override;
  public
    constructor Create(App: TAppHandle; ThreadIndex: Integer);
  end;

constructor TConcurrencyThread.Create(App: TAppHandle; ThreadIndex: Integer);
begin
  inherited Create(True); // Create suspended? we will start manually
  FApp := App;
  FThreadIndex := ThreadIndex;
  FreeOnTerminate := False; // We will wait for threads
end;

procedure TConcurrencyThread.Execute;
var
  j: Integer;
  Data, Res: TDataHandle;
  Sum: Integer;
begin
  for j := 1 to 100 do  // CALLS_PER_THREAD = 100
  begin
    Data := TDataHandle.Create('add');
    try
      Data.WriteInt32(j).WriteInt32(j*2);
      Res := FApp.LocalCall(Data);
      try
        if Res.ReadInt32(Sum) and (Sum = j + j*2) then
          InterlockedIncrement(ConcurrencyTotalCalls);
      finally Res.Free; end;
    finally Data.Free; end;
  end;
end;

{ ----------------------------------------------------------------------------
  Test: TDataHandle Basics (chained writes, reads, position/size, buffer)
-----------------------------------------------------------------------------}
procedure TestDataHandleBasics;
var
  DH: TDataHandle;
  I8: Int8; U8: UInt8; I16: Int16; U16: UInt16;
  I32: Int32; U32: UInt32; I64: Int64; U64: UInt64;
  Sgl: Single; Dbl: Double; Str: string;
  BufPtr: Pointer;
begin
  Report('=== TDataHandle Basic Operations (Chaining) ===');

  DH := TDataHandle.Create('test_api');
  try
    // Chain writes: all WriteXXX methods return Self
    DH.WriteInt8(-128)
      .WriteUInt8(255)
      .WriteInt16(-32768)
      .WriteUInt16(65535)
      .WriteInt32(-123456789)
      .WriteUInt32(123456789)
      .WriteInt64(-9876543210)
      .WriteUInt64(9876543210)
      .WriteSingle(3.14159)
      .WriteDouble(2.718281828)
      .WriteString('Hello, 世界! 🌍');

    // Reset position to beginning and read back
    DH.SetPos(0);

    if DH.ReadInt8(I8) and DH.ReadUInt8(U8) and DH.ReadInt16(I16) and
       DH.ReadUInt16(U16) and DH.ReadInt32(I32) and DH.ReadUInt32(U32) and
       DH.ReadInt64(I64) and DH.ReadUInt64(U64) and
       DH.ReadSingle(Sgl) and DH.ReadDouble(Dbl) and DH.ReadString(Str) then
    begin
      Report('Int8=%d UInt8=%d Int16=%d UInt16=%d Int32=%d UInt32=%d Int64=%d UInt64=%d',
        [I8, U8, I16, U16, I32, U32, I64, U64]);
      Report('Single=%f Double=%f', [Sgl, Dbl]);
      Report('String: ' + Str);
      ReportPass('All types read/written correctly');
    end
    else
      ReportFail('Read operations failed');

    // Test GetPos / SetPos
    DH.SetPos(4);
    if DH.GetPos = 4 then
      ReportPass('SetPos/GetPos')
    else
      ReportFail('SetPos/GetPos');

    // Test GetSize / SetSize (truncate)
    DH.SetSize(10);
    if DH.GetSize = 10 then
      ReportPass('SetSize (truncate)')
    else
      ReportFail('SetSize');

    // Test GetBuffer (zero‑copy pointer)
    BufPtr := DH.GetBuffer;
    if BufPtr <> nil then
      ReportPass('GetBuffer returns valid pointer')
    else
      ReportFail('GetBuffer returned nil');

  finally
    DH.Free;
  end;
end;

{ ----------------------------------------------------------------------------
  Test: Local Calls and Notifications (no network)
-----------------------------------------------------------------------------}
procedure TestLocalCalls;
var
  App: TAppHandle;
  Data, Res: TDataHandle;
  Sum: Integer; Msg: string;
begin
  Report('=== Local Calls & Notifications ===');

  App := TAppHandle.Create('LocalApp', 'Local test');
  try
    // Register APIs
    if not App.RegisterCall('add', 'Addition', nil, @AddCallback) then
      ReportFail('RegisterCall add');
    if not App.RegisterCall('echo', 'Echo', nil, @EchoCallback) then
      ReportFail('RegisterCall echo');
    if not App.RegisterNotify('print', 'Print', nil, @PrintNotify) then
      ReportFail('RegisterNotify print');

    // Local Call: add
    Data := TDataHandle.Create('add');
    try
      Data.WriteInt32(5).WriteInt32(7);
      Res := App.LocalCall(Data);
      try
        if Res.ReadInt32(Sum) and (Sum = 12) then
          ReportPass('Local add(5,7)=12')
        else
          ReportFail('Local add result wrong');
      finally Res.Free; end;
    finally Data.Free; end;

    // Local Call: echo
    Data := TDataHandle.Create('echo');
    try
      Data.WriteString('Local Echo Test');
      Res := App.LocalCall(Data);
      try
        if Res.ReadString(Msg) and (Msg = 'Local Echo Test') then
          ReportPass('Local echo')
        else
          ReportFail('Local echo result wrong');
      finally Res.Free; end;
    finally Data.Free; end;

    // Local Notify
    Data := TDataHandle.Create('print');
    try
      Data.WriteString('Local notify message');
      App.LocalNotify(Data);
      ReportPass('Local notify sent (see callback output above)');
    finally Data.Free; end;

  finally
    App.Free;
  end;
end;

{ ----------------------------------------------------------------------------
  Test: Remote Network Communication (IPC)
-----------------------------------------------------------------------------}
procedure TestNetworkIPC;
var
  App: TAppHandle;
  Data, Res: TDataHandle;
  Sum: Integer; Msg: string;
begin
  Report('=== Remote IPC Network ===');

  App := TAppHandle.Create('TestService', 'IPC test');
  try
    // Register APIs
    if not App.RegisterCall('add', 'Add', nil, @AddCallback) then
      ReportFail('RegisterCall add');
    if not App.RegisterCall('echo', 'Echo', nil, @EchoCallback) then
      ReportFail('RegisterCall echo');
    if not App.RegisterNotify('print', 'Print', nil, @PrintNotify) then
      ReportFail('RegisterNotify print');

    ResetPrepare;
    PrepareService('ipc:test_svc', 'ipc:test_svc');
    PrepareClient('ipc:test_svc', App);

    if not PrepareDone then
    begin
      ReportFail('PrepareDone failed – check console for errors');
      Exit;
    end;
    ReportPass('PrepareDone succeeded');

    // Remote add
    Data := TDataHandle.Create('add');
    try
      Data.WriteInt32(100).WriteInt32(200);
      Res := CallApp('TestService', Data, 3000);
      try
        if Res.ReadInt32(Sum) and (Sum = 300) then
          ReportPass('Remote add(100,200)=300')
        else
          ReportFail('Remote add result wrong');
      finally Res.Free; end;
    finally Data.Free; end;

    // Remote echo
    Data := TDataHandle.Create('echo');
    try
      Data.WriteString('Hello from network!');
      Res := CallApp('TestService', Data, 3000);
      try
        if Res.ReadString(Msg) and (Msg = 'Hello from network!') then
          ReportPass('Remote echo')
        else
          ReportFail('Remote echo result wrong');
      finally Res.Free; end;
    finally Data.Free; end;

    // Remote notify
    Data := TDataHandle.Create('print');
    try
      Data.WriteString('Network notify');
      NotifyApp('TestService', Data);
      ReportPass('Remote notify sent (see callback output)');
    finally Data.Free; end;

    // Non‑existent API → handle size 0
    Data := TDataHandle.Create('unknown');
    try
      Res := CallApp('TestService', Data, 1000);
      try
        if Res.GetSize = 0 then
          ReportPass('Unknown API returns size 0')
        else
          ReportFail('Unknown API should return size 0');
      finally Res.Free; end;
    finally Data.Free; end;

  finally
    App.Free;
  end;

  ExitMainThread;
  Shutdown;
  ReportPass('Network shutdown complete');
end;

{ ----------------------------------------------------------------------------
  Test: Concurrency (10 threads × 100 calls each)
-----------------------------------------------------------------------------}
procedure TestConcurrency;
const
  THREAD_COUNT = 10;
  CALLS_PER_THREAD = 100;
var
  Threads: array[0..THREAD_COUNT-1] of TConcurrencyThread;
  App: TAppHandle;
  StartTime: TDateTime;
  Elapsed: Double;
  i: Integer;
begin
  Report('=== Concurrency Test (%d threads × %d calls each) ===',
    [THREAD_COUNT, CALLS_PER_THREAD]);

  ConcurrencyTotalCalls := 0;
  App := TAppHandle.Create('ConcurrencyApp', 'Concurrency');
  try
    if not App.RegisterCall('add', 'Add', nil, @AddCallback) then
    begin
      ReportFail('RegisterCall add in concurrency test');
      Exit;
    end;

    StartTime := Now;
    for i := 0 to THREAD_COUNT-1 do
      Threads[i] := TConcurrencyThread.Create(App, i);

    // Start all threads
    for i := 0 to THREAD_COUNT-1 do
      Threads[i].Start;

    // Wait for all threads to finish
    for i := 0 to THREAD_COUNT-1 do
    begin
      Threads[i].WaitFor;
      Threads[i].Free;
    end;

    Elapsed := (Now - StartTime) * SecsPerDay;
    Report('Completed %d calls in %.3f seconds = %.2f calls/sec',
      [ConcurrencyTotalCalls, Elapsed, ConcurrencyTotalCalls / Elapsed]);

    if ConcurrencyTotalCalls = THREAD_COUNT * CALLS_PER_THREAD then
      ReportPass('All concurrent calls succeeded')
    else
      ReportFail('Some calls failed or produced wrong results');

  finally
    App.Free;
  end;
end;

{ ----------------------------------------------------------------------------
  Test: Performance (1000 sequential local calls)
-----------------------------------------------------------------------------}
procedure TestPerformance;
const
  ITERATIONS = 1000;
var
  App: TAppHandle;
  Data, Res: TDataHandle;
  StartTime: TDateTime;
  Elapsed: Double;
  Sum: Integer;
  i: Integer;
  SuccessCount: Integer;
begin
  Report('=== Performance Test (%d sequential local calls) ===', [ITERATIONS]);

  App := TAppHandle.Create('PerfApp', 'Performance');
  try
    if not App.RegisterCall('add', 'Add', nil, @AddCallback) then
    begin
      ReportFail('RegisterCall add in performance test');
      Exit;
    end;

    StartTime := Now;
    SuccessCount := 0;
    for i := 1 to ITERATIONS do
    begin
      Data := TDataHandle.Create('add');
      try
        Data.WriteInt32(i).WriteInt32(i+1);
        Res := App.LocalCall(Data);
        try
          if Res.ReadInt32(Sum) and (Sum = 2*i+1) then
            Inc(SuccessCount);
        finally Res.Free; end;
      finally Data.Free; end;
    end;

    Elapsed := (Now - StartTime) * SecsPerDay;
    Report('Completed %d successful out of %d calls in %.3f seconds = %.2f calls/sec',
      [SuccessCount, ITERATIONS, Elapsed, ITERATIONS / Elapsed]);

    if SuccessCount = ITERATIONS then
      ReportPass('All performance calls correct')
    else
      ReportFail('Some performance calls gave wrong results');

  finally
    App.Free;
  end;
end;

{ ----------------------------------------------------------------------------
  Test: Resource Leak (allocate and free many handles)
-----------------------------------------------------------------------------}
procedure TestResourceLeak;
const
  ALLOC_COUNT = 10000;
var
  i: Integer;
  Handles: array of TDataHandle;
begin
  Report('=== Resource Leak Test (allocate %d handles) ===', [ALLOC_COUNT]);

  SetLength(Handles, ALLOC_COUNT);
  try
    for i := 0 to ALLOC_COUNT-1 do
      Handles[i] := TDataHandle.Create(Format('leak_%d', [i]));
    Report('Successfully created %d handles', [ALLOC_COUNT]);
    ReportPass('All handles allocated');
  finally
    for i := 0 to ALLOC_COUNT-1 do
      Handles[i].Free;
    ReportPass('All handles freed');
  end;
end;

{ ----------------------------------------------------------------------------
  Test: Duplicate Registration Detection
-----------------------------------------------------------------------------}
procedure TestDuplicateRegistration;
var
  App: TAppHandle;
begin
  Report('=== Duplicate Registration Detection ===');

  App := TAppHandle.Create('DupApp', 'Duplicate test');
  try
    if App.RegisterCall('test', 'first', nil, @AddCallback) then
      ReportPass('First registration succeeded')
    else
      ReportFail('First registration should succeed');

    if not App.RegisterCall('test', 'second', nil, @AddCallback) then
      ReportPass('Duplicate registration correctly rejected')
    else
      ReportFail('Duplicate registration should have been rejected');

  finally
    App.Free;
  end;
end;

{ ----------------------------------------------------------------------------
  Test: UTF‑8 Internationalization (Chinese/Emoji)
-----------------------------------------------------------------------------}
procedure TestUTF8International;
var
  App: TAppHandle;
  Data, Res: TDataHandle;
  Sum: Integer;
begin
  Report('=== UTF‑8 Internationalization (Chinese/Emoji) ===');

  App := TAppHandle.Create('中文字符服务', '包含中文描述');
  try
    if not App.RegisterCall('加法', '两数相加', nil, @AddCallback) then
      ReportFail('RegisterCall with Chinese name');
    if not App.RegisterNotify('日志', '中文日志', nil, @PrintNotify) then
      ReportFail('RegisterNotify with Chinese name');

    Data := TDataHandle.Create('加法');
    try
      Data.WriteInt32(8).WriteInt32(9);
      Res := App.LocalCall(Data);
      try
        if Res.ReadInt32(Sum) and (Sum = 17) then
          ReportPass('Chinese API call succeeded: 8+9=17')
        else
          ReportFail('Chinese API call returned wrong result');
      finally Res.Free; end;
    finally Data.Free; end;

    Data := TDataHandle.Create('日志');
    try
      Data.WriteString('测试通知 🎉');
      App.LocalNotify(Data);
      ReportPass('Chinese notification sent (check callback output)');
    finally Data.Free; end;

  finally
    App.Free;
  end;
end;

{ ----------------------------------------------------------------------------
  Main Program
-----------------------------------------------------------------------------}
begin
  ConsoleWriteLn('API Hub Tool Pascal Wrapper – Full Test v2.3');
  ConsoleWriteLn('Author: API Hub Tool Team');
  ConsoleWriteLn;

  try
    TestDataHandleBasics;      ConsoleWriteLn;
    TestLocalCalls;            ConsoleWriteLn;
    TestNetworkIPC;            ConsoleWriteLn;
    TestConcurrency;           ConsoleWriteLn;
    TestPerformance;           ConsoleWriteLn;
    TestResourceLeak;          ConsoleWriteLn;
    TestDuplicateRegistration; ConsoleWriteLn;
    TestUTF8International;     ConsoleWriteLn;

    ConsoleWriteLn('✅ All tests completed. Press Enter to exit...');
  except
    on E: Exception do
      ConsoleWriteLn('❌ Test exception: ' + E.ClassName + ': ' + E.Message);
  end;
  ReadLn;
end.

