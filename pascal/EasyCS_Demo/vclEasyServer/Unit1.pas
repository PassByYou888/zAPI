unit Unit1;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,

  z_api_hubtool_helper, z_api_hubtool_import,

  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls;

type
  TForm1 = class(TForm)
    Button1: TButton;
    Memo1: TMemo;
    Button2: TButton;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

procedure AddCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
procedure jsonceshiCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;

var
  Form1: TForm1;
  App: API.TAppHandle = nil;

implementation

{$R *.dfm}
// 加法回调（cdecl，在后台线程执行）

procedure AddCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
var
  A, B, Sum: Integer;
begin
  if API_ReadBuffer(TDataHnd(Input), @A, SizeOf(A)) <> SizeOf(A) then
    Exit;
  if API_ReadBuffer(TDataHnd(Input), @B, SizeOf(B)) <> SizeOf(B) then
    Exit;

  Sum := A + B;
  API_WriteBuffer(TDataHnd(Output), @Sum, SizeOf(Sum));
end;

procedure jsonceshiCallback(Trigger: Pointer; Input, Output: Pointer); cdecl;
var
  InData, OutData: API.TDataHandle;
  ainstr,aoutstr: string;
begin
  try
    InData := API.TDataHandle.Create(Input);
    OutData := API.TDataHandle.Create(Output);
    InData.ReadString(ainstr); //ainstr为收到的字符串

    //这里省略业务处理（将ainstr转换为json，然后处理完毕后，再组装一个json，再将它转换为字符串），假设最后处理完毕的字符串为aoutstr
    aoutstr:='返回数据：' + ainstr;

    OutData.WriteString(aoutstr); //ainstr为返回给客户端调用此函数的结果字符串
  finally
    InData.Free;
    OutData.Free;
  end;
end;

procedure TForm1.Button1Click(Sender: TObject);
begin
  // 1. 创建应用（RAII，自动释放）
  App := API.TAppHandle.Create('CalcService', '这是一个ceshi用的Demo');

  // 2. 注册 API:add
  if not App.RegisterCall('add', '计算a + b的和', nil, @AddCallback) then
  begin
    Memo1.Lines.Add('add注册失败');
  end;
  // 2. 注册 API:jsonceshi
  if not App.RegisterCall('jsonceshi', '测试输入一个json字符串，返回一个json字符串', nil, @jsonceshiCallback) then
  begin
    Memo1.Lines.Add('jsonceshi注册失败');
  end;

  // 3. 准备网络（IPC 模式）
  API.ResetPrepare;

  // 第3个参数如果为 nil，则充当纯消费者(不对外提供服务)。
  API.PrepareService('ipc:calc_service', 'ipc:calc_service', App);

  if not API.PrepareDone then
  begin
    Memo1.Lines.Add('网络启动失败');
  end;

  Memo1.Lines.Add('服务已启动...');
  Memo1.Lines.Add('APP名称：CalcService');
  Memo1.Lines.Add('可调用函数名1：add【计算a + b的和】');
  Memo1.Lines.Add('可调用函数名1：jsonceshi【测试输入一个json字符串，返回一个json字符串】');

  Button1.Enabled := False;

end;

procedure TForm1.Button2Click(Sender: TObject);
begin
  // 4. 清理（RAII 会自动释放 App，但我们手动调用网络停止）
  API.ExitMainThread;
  API.Shutdown;
  if App <> nil then
    Freeandnil(App); // 非必须，但显式释放更清晰

  Button1.Enabled := true;
end;

end.
