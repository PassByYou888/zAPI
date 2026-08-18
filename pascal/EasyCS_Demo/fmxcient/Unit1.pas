unit Unit1;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.Controls.Presentation, FMX.StdCtrls, FMX.Memo.Types, FMX.ScrollBox,
  FMX.Memo;

type
  TForm1 = class(TForm)
    Button1: TButton;
    Button2: TButton;
    Memo1: TMemo;
    Button3: TButton;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.fmx}

uses z_api_hubtool_helper;

procedure TForm1.Button1Click(Sender: TObject);
begin
  // 1. 连接到服务（纯消费端，不暴露 API）

  ResetPrepare;
  PrepareClient('ipc:calc_service', nil); // App 如果为 nil，则充当纯消费者(不对外提供服务)。

  if PrepareDone then
  begin
    Button1.Enabled := false;
    Button2.Enabled := true;
    Button3.Enabled := true;
    Memo1.Lines.Add('连接到服务成功:ipc:calc_service');
  end
end;

procedure TForm1.Button2Click(Sender: TObject);
begin

  TThread.CreateAnonymousThread(
    procedure
    var
      Data, Res: TDataHandle;
      Sum: Integer;
    begin
      // 2. 构造请求（RAII 自动释放）
      Data := TDataHandle.Create('add');
      Data.WriteInt32(10).WriteInt32(20); // 链式写入
      // 3. 远程调用（超时 3000ms）
      Res := CallApp('CalcService', Data, 3000);
      try
        if Res.GetSize = 0 then
          TThread.Synchronize(nil,
            procedure
            begin
              Memo1.Lines.Add('调用超时或失败');
            end)
        else if Res.ReadInt32(Sum) then
          TThread.Synchronize(nil,
            procedure
            begin
              Memo1.Lines.Add(Format('10 + 20 = %d', [Sum]));
            end)
        else
          TThread.Synchronize(nil,
            procedure
            begin
              Memo1.Lines.Add('读取结果失败');
            end);
      finally
        Res.Free;
      end;

    end).Start;

end;

procedure TForm1.Button3Click(Sender: TObject);
begin
  // 4. 清理
  z_api_hubtool_helper.ExitMainThread;
  z_api_hubtool_helper.Shutdown;
  Button1.Enabled := true;
  Button2.Enabled := false;
  Button3.Enabled := false;
end;

end.



// TThread.CreateAnonymousThread(
// procedure
// begin
// TThread.Synchronize(nil,
// procedure
// begin
//
// end);
// end).Start;
