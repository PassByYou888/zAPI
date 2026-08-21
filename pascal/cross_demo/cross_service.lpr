program cross_service;

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
  SysUtils, Z.Core, // Z 框架核心（线程池、原子操作、时间等）
  Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib, Z.Parsing, Z.Expression, Z.MemoryStream, // TMem64 内存流
  Z.Status, Z.Int128, Z.Geometry2D, Z.Notify, z_api_hubtool_helper, // RAII 封装
  z_api_hubtool_import; // C 绑定

begin
  API_Reset_Prepare();
  API_Prepare_Service2('ipc:cross', 'ipc:cross');
  if API_Prepare_Done() <> 1 then
  begin
    DoStatus('计算服务启动失败');
    API_shutdown();
    DoStatus('3秒后退出');
    TCompute.Sleep(3000);
    exit;
  end;
  DoStatus('计算服务启动成功');
  DoStatus('回车键退出.');
  readln();
  DoStatus('清理线程中.');
  API_shutdown();
end.
