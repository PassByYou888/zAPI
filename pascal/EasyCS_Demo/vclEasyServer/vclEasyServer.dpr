program vclEasyServer;

uses
  Vcl.Forms,
  Unit1 in 'Unit1.pas' {Form1},
  z_api_hubtool_helper in '..\..\z_api_hubtool_helper.pas',
  z_api_hubtool_import in '..\..\z_api_hubtool_import.pas';

{$R *.res}

begin
  ReportMemoryLeaksOnShutdown := True; // 只要有内存泄漏就会报
  // ReportMemoryLeaksOnShutdown := DebugHook<>0; //在真正的debug时，闭关窗口会报内存泄漏

  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
