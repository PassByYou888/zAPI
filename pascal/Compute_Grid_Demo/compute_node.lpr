program compute_node;

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

procedure do_exp_Call(Trigger: Pointer; Input: Pointer; Output: TDataHnd); cdecl;
var
  exp: TPascalString;
  tmp: TPascalString;
begin
  exp := API_ReadString(input);
  tmp := VarToStr(EvaluateExpressionValue(tsC, exp));
  DoStatus('收到计算请求 "%s" = 计算结果 "%s"', [exp.Text, tmp.Text]);
  API_WriteString(Output, tmp);
end;

var
  app: TAppHnd;
begin
  app := API_Create_APPHnd2('pas', 'pascal语言实现的api');
  API_Reg_Call2(app, 'exp', 'exp("expression")', nil, do_exp_Call);

  API_SetOption2('Wait_Ready', 'False'); //启动部署模式:计算节点启动没有先后顺序,可以先启动节点,然后再启动服务器
  API_Reset_Prepare();
  API_Prepare_Client2('ipc:compute_grid', app);
  API_Prepare_Done();
  DoStatus('计算节点启动成功');
  DoStatus('回车键退出.');
  readln();
  DoStatus('清理线程中.');
  API_Free_APPHnd(app);
  API_shutdown();
end.
