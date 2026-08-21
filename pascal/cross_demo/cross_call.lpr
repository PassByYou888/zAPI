program cross_call;

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
  SysUtils, Variants, Z.Core, // Z 框架核心（线程池、原子操作、时间等）
  Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib, Z.Parsing, Z.Expression, Z.MemoryStream, // TMem64 内存流
  Z.Status, Z.Int128, Z.Geometry2D, Z.Notify, z_api_hubtool_helper, // RAII 封装
  z_api_hubtool_import; // C 绑定

function add__(a, b: integer): integer;
var
  send_, return_: TDataHnd;
begin
  Result := 0;
  send_ := API_Create_DataHnd2('add');
  API_WriteInt32(send_, a);
  API_WriteInt32(send_, b);

  return_ := API_Call2('demo', send_, 1000);
  if API_GetSize(return_) > 0 then
    Result := API_ReadInt32(return_);

  API_Free_DataHnd(send_);
  API_Free_DataHnd(return_);
end;

function inv_seri_: string;
var
  b: byte;
  w: word;
  c: cardinal;
  u64: uint64;
  s: string;
  f: single;
  send_, return_: TDataHnd;
begin
  b := 200;
  w := $10;
  c := $2F;
  u64 := $3F;
  s := 'hello world';
  f := 3.14;

  send_ := API_Create_DataHnd2('inv_seri');

  API_WriteUInt8(send_, b);
  API_WriteUInt16(send_, w);
  API_WriteUInt32(send_, c);
  API_WriteUInt64(send_, u64);
  API_WriteString(send_, s);
  API_WriteSingle(send_, f);

  return_ := API_Call2('demo', send_, 1000);
  if API_GetSize(return_) > 0 then
  begin
    f := API_ReadSingle(return_);
    s := API_ReadString(return_);
    u64 := API_ReadUInt64(return_);
    c := API_ReadUInt32(return_);
    w := API_ReadUInt16(return_);
    b := API_ReadUInt8(return_);
    Result := PFormat('接收数据序 [%d, %d, %d, %d, "%s", %.2f] = 发送数据序 [%.2f, "%s", %d, %d, %d, %d] ', [b, w, c, u64, s, f, f, s, u64, c, w, b]);
  end
  else
    Result := '计算超时';

  API_Free_DataHnd(send_);
  API_Free_DataHnd(return_);
end;

var
  app_running: boolean;
procedure Do_Compute;
var
  a, b, c: integer;
  tk: TTimeTick;
begin
  tk := GetTimeTick();
  while app_running and ((GetTimeTick() - tk) < 10 * 1000) do
  begin
    if TMT19937.Rand32 mod 2 = 0 then
    begin
      a := TMT19937.RandomRange(1, $FFFFFFF);
      b := TMT19937.RandomRange(1, $FFFFFFF);
      c := add__(a, b);
      if c <> 0 then
        DoStatus('计算 "a(%d)+b(%d)" = 计算结果 %d (%.2f秒以后退出)', [a, b, c, ((10 * 1000) - (GetTimeTick() - tk)) * 0.001]);
    end
    else
    begin
      DoStatus(inv_seri_() + PFormat('(%.2f秒退出)', [((10 * 1000) - (GetTimeTick() - tk)) * 0.001]));
    end;
  end;
end;

var
  thread_running: boolean;
begin
  API_Reset_Prepare();
  API_Prepare_Client2('ipc:cross', nil);
  API_Prepare_Done();
  DoStatus('计算节点启动成功');

  DoStatus('启动仿真计算(可以多开)');
  app_running := True;
  TCompute.RunC_NP(Do_Compute, @thread_running, nil);

  while thread_running do
    TCompute.Sleep(100);

  DoStatus('清理线程中.');
  API_Exit_MainThread();
  API_shutdown();
end.
