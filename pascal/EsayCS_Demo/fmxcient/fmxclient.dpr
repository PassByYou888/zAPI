program fmxclient;

uses
  System.StartUpCopy,
  FMX.Forms,
  Unit1 in 'Unit1.pas' {Form1},
  z_api_hubtool_helper in '..\..\z_api_hubtool_helper.pas',
  z_api_hubtool_import in '..\..\z_api_hubtool_import.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
