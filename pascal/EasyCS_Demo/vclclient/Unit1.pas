unit Unit1;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,

  System.SyncObjs,

  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls;

type
  TForm1 = class(TForm)
    Button1: TButton;
    Button2: TButton;
    Memo1: TMemo;
    Button3: TButton;
    Button4: TButton;
    Text5: TLabel;
    Button5: TButton;
    Button6: TButton;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure Button4Click(Sender: TObject);
    procedure Button5Click(Sender: TObject);
    procedure Button6Click(Sender: TObject);
  private
    { Private declarations }
    k0, k1, k2, k3: integer;
    stopcs: integer; // 停止测试
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

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
    Button4.Enabled := true;
    Button5.Enabled := true;
    Memo1.Lines.Add('连接到服务成功:ipc:calc_service');
  end
end;

procedure TForm1.Button2Click(Sender: TObject);
begin

  TThread.CreateAnonymousThread(
    procedure
    var
      Data, Res: TDataHandle;
      Sum: integer;
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
        Data.Free;
      end;

    end).Start;

end;

procedure TForm1.Button3Click(Sender: TObject);
begin
  if Button4.caption = '停止测试' then
  begin
    Button4Click(Sender);
    sleep(1000);
  end;

  // 4. 清理
  z_api_hubtool_helper.ExitMainThread;
  z_api_hubtool_helper.Shutdown;
  Button1.Enabled := true;
  Button2.Enabled := false;
  Button3.Enabled := false;
  Button4.Enabled := false;
  Button5.Enabled := false;
end;

procedure TForm1.Button4Click(Sender: TObject);
var
  i: integer;
  n1: Cardinal;
begin
  if Button4.caption = '停止测试' then
  begin
    stopcs := 1;
    n1 := TThread.GetTickCount;
    Button4.caption := '并发测试';
    exit;
  end
  else
  begin
    stopcs := 0;
    k0 := 0;
    k1 := 0;
    k2 := 0;
    k3 := 0;
    n1 := TThread.GetTickCount;
    Button4.caption := '停止测试';
  end;
  Randomize;
  for i := 1 to 1000 do // 开启的线程数量
  begin
    TThread.CreateAnonymousThread( // 创建一个单线程，完成一个没有界面交互的任务
      procedure
      var
        n: Cardinal;
        Data, Res: TDataHandle;
        Sum: integer;
      begin // 线程里的一些代码。
        while true do
        begin
          TInterlocked.increment(k0); // 总的提交次数
          n := TThread.GetTickCount;
          // Randomize; // 初始化内置的随机数生成器
          // 2. 构造请求（RAII 自动释放）
          Data := TDataHandle.Create('add');
          Data.WriteInt32(10).WriteInt32(20); // 链式写入
          // 3. 远程调用（超时 3000ms）
          Res := CallApp('CalcService', Data, 3000);
          try
            if Res.GetSize = 0 then
              TInterlocked.increment(k2)
              // TThread.Synchronize(nil,
              // procedure
              // begin
              // Memo1.Lines.Add('调用超时或失败');
              // end)
            else if Res.ReadInt32(Sum) then // 如果查询成功
              TInterlocked.increment(k1)
              // TThread.Synchronize(nil,
              // procedure
              // begin
              // Memo1.Lines.Add(Format('10 + 20 = %d', [Sum]));
              // end)
            else
              TInterlocked.increment(k2);
            // TThread.Synchronize(nil,
            // procedure
            // begin
            // Memo1.Lines.Add('读取结果失败');
            // end);
          finally
            Res.Free;
            Data.Free;
          end;

          if k0 mod 1000 = 0 then // 每执行1000次刷新一次界面，否则刷新不过来
            TThread.Synchronize(nil,
              procedure // 处理界面交互代码写这里
              begin
                Text5.caption := '总次数' + (k0).ToString + '---成功' + (k1).ToString + '---失败' + (k2).ToString + Format('耗时:%f秒', [(TThread.GetTickCount - n) / 1000]) +
                  Format('总耗时:%f秒', [(TThread.GetTickCount - n1) / 1000]) + Format('并发:%d次/秒', [round(k1 / ((TThread.GetTickCount - n1) / 1000))]);
              end);

          if stopcs = 1 then // 停止测试
            exit;
        end;

      end).Start;

    // sleep(random(1000))
  end;

end;

procedure TForm1.Button5Click(Sender: TObject);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      Data, Res: TDataHandle;
      astr: string;
      astringlist:Tstringlist;
    begin
      // 2. 构造请求（RAII 自动释放）
      Data := TDataHandle.Create('jsonceshi');
      astringlist:=Tstringlist.Create;
      astringlist.LoadFromFile('abigstring.txt',TEncoding.UTF8);//导入一个大的测试文件(我测试过100兆的文件)
      Data.WriteString(astringlist.Text);
      astringlist.Free;
      // 3. 远程调用（超时 3000ms）
      Res := CallApp('CalcService', Data, 10000);
      try
        if Res.GetSize = 0 then
          TThread.Synchronize(nil,
            procedure
            begin
              Memo1.Lines.Add('调用超时或失败');
            end)
        else if Res.ReadString(astr) then
          TThread.Synchronize(nil,
            procedure
            begin
              Memo1.Lines.Add(Format('服务端jsonceshi函数返回：%s', [astr]));
            end)
        else
          TThread.Synchronize(nil,
            procedure
            begin
              Memo1.Lines.Add('读取结果失败');
            end);
      finally
        astr:='';//释放占用内存
        Res.Free;
        Data.Free;
      end;

    end).Start;
end;

procedure TForm1.Button6Click(Sender: TObject);
begin
  Memo1.Clear;
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
