program EsayClient;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  z_api_hubtool_helper;   // RAII 封装（推荐）

var
  Data, Res: TDataHandle;
  Sum: Integer;
begin
  // 1. 连接到服务（纯消费端，不暴露 API）
  ResetPrepare;
  PrepareClient('ipc:calc_service', nil);  //App 如果为 nil，则充当纯消费者(不对外提供服务)。

  if not PrepareDone then
  begin
    Writeln('连接失败');
    Halt(1);
  end;

  // 2. 构造请求（RAII 自动释放）
  Data := TDataHandle.Create('add');
  Data.WriteInt32(10).WriteInt32(20);   // 链式写入

  // 3. 远程调用（超时 3000ms）
  Res := CallApp('CalcService', Data, 3000);
  try
    if Res.GetSize = 0 then
      Writeln('调用超时或失败')
    else if Res.ReadInt32(Sum) then
      Writeln(Format('10 + 20 = %d', [Sum]))
    else
      Writeln('读取结果失败');
  finally
    Res.Free;
  end;
  Readln;

  // 4. 清理
  ExitMainThread;
  Shutdown;
end.
