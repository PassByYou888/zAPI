program Squence_Cli;

{$APPTYPE CONSOLE}

{$R *.res}


uses
{$IFDEF UNIX}
  cthreads,
{$ENDIF}
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  SysUtils,
  Z.Core, // Z 框架核心（线程池、原子操作、时间等）
  Z.PascalStrings,
  Z.UPascalStrings,
  Z.UnicodeMixedLib,
  Z.Parsing,
  Z.Expression,
  Z.MemoryStream, // TMem64 内存流
  Z.Status,
  Z.Int128,
  Z.Geometry2D,
  Z.Notify,
  z_api_hubtool_helper in '..\z_api_hubtool_helper.pas', // RAII 封装
  z_api_hubtool_import in '..\z_api_hubtool_import.pas'; // C 绑定

const
  Debug_Log = False;
  SEQUENCE_SERVER_APP = 'sequence_test'; // 服务端应用名称（必须匹配）
  SEQUENCE_TIMEOUT_MS = 5000; // BeginData 超时（毫秒）

  { -----------------------------------------------------------------------------
    1. 开始一个新会话：调用服务端的 BeginData API
    返回一个会话 ID（服务端对象的指针值），后续发送数据需携带此 ID
    ----------------------------------------------------------------------------- }
function SequenceBegin(var SessionID: UInt64): Boolean;
var
  Param, Res: TDataHandle; // RAII 句柄，自动释放
begin
  Result := False;
  SessionID := 0;

  Param := TDataHandle.Create('BeginData'); // 创建请求句柄（API 名必须 UTF-8）
  try
    // 同步调用服务端，超时 5000ms，返回结果句柄
    Res := CallApp(SEQUENCE_SERVER_APP, Param, SEQUENCE_TIMEOUT_MS);
    try
      // 结果至少 8 字节（UInt64）
      if Res.GetSize >= 8 then
        begin
          Res.SetPos(0);
          Result := Res.ReadUInt64(SessionID); // 读取会话 ID
        end;
    finally
        Res.Free; // 释放结果句柄（即使大小为 0 也必须释放）
    end;
  finally
      Param.Free; // 释放请求句柄
  end;
end;

{ -----------------------------------------------------------------------------
  2. 发送一个数据块：使用 Notify（单向通知，不等待响应）
  参数：会话 ID、块索引、数据指针、数据大小
  ----------------------------------------------------------------------------- }
procedure SequenceData(SessionID: UInt64; Index: Int64; const Data: Pointer; Size: Int64);
var
  Param: TDataHandle;
begin
  Param := TDataHandle.Create('Data');
  try
    Param.WriteUInt64(SessionID); // 1) 会话 ID（8 字节）
    Param.WriteInt64(Index); // 2) 块索引（8 字节）
    Param.WriteBuffer(Data^, Size); // 3) 实际数据（任意大小）
    // 单向通知：发送后立即返回，不等待服务端确认
    NotifyApp(SEQUENCE_SERVER_APP, Param);
  finally
      Param.Free;
  end;
end;

{ -----------------------------------------------------------------------------
  3. 结束会话：发送 EndData 通知，告知服务端总块数
  服务端收到后将在后台线程中等待所有块到达，然后排序并处理
  ----------------------------------------------------------------------------- }
procedure SequenceEnd(SessionID: UInt64; TotalCount: Int64);
var
  Param: TDataHandle;
begin
  Param := TDataHandle.Create('EndData');
  try
    Param.WriteUInt64(SessionID); // 会话 ID
    Param.WriteInt64(TotalCount); // 总块数（服务端将据此判断是否收齐）
    NotifyApp(SEQUENCE_SERVER_APP, Param);
  finally
      Param.Free;
  end;
end;

{ -----------------------------------------------------------------------------
  4. 测试函数：生成 10MB 随机数据，分块发送到服务端
  simulate_bad = True 时，不发送 EndData，模拟网络断线或客户端崩溃
  ----------------------------------------------------------------------------- }
function Test_BigData(simulate_bad: Boolean): Boolean;
var
  m64: TMem64; // 内存流，存储测试数据
  siz: Int64; // 每块大小（1536 字节）
  SessionID: UInt64;
  i: Int64;
begin
  Result := False;
  m64 := TMem64.Create;
  m64.Size := 1024 * 1024 * 10; // 10 MB
  MT19937Rand32(MaxInt, m64.Memory, m64.Size div 4); // 填充随机数据

  if not simulate_bad then
      DoStatus('远程会响应,源数据指纹:%s', [umlMD5ToStr(m64.ToMD5).Text]);

  m64.Position := 0;
  siz := 1536; // 每块 1536 字节（可调整）
  i := 0;
  SessionID := 0;

  try
    // 4.1 开始会话，获取 SessionID
    if not SequenceBegin(SessionID) then
        Exit;

    // 4.2 循环发送数据块
    while m64.Position + siz < m64.Size do
      begin
        SequenceData(SessionID, i, m64.PosAsPtr, siz);
        if Debug_Log then
            DoStatus('发送的缓冲区索引 %d 指纹: %s', [i, umlMD5ToStr(m64.PosAsPtr, siz).Text]);
        m64.Position := m64.Position + siz;
        Inc(i);
      end;

    // 4.3 处理最后一个可能不足 siz 的块
    siz := m64.Size - m64.Position;
    if siz > 0 then
      begin
        SequenceData(SessionID, i, m64.PosAsPtr, siz);
        if Debug_Log then
            DoStatus('发送的缓冲区索引 %d 指纹: %s', [i, umlMD5ToStr(m64.PosAsPtr, siz).Text]);
        m64.Position := m64.Position + siz;
        Inc(i);
      end;

    // 4.4 如果不是模拟坏情况，则发送 EndData 通知服务端处理
    if not simulate_bad then
        SequenceEnd(SessionID, i);
  finally
      DisposeObject(m64);
  end;

  if simulate_bad then
      DoStatus('脏数据发送完毕,模拟断线等情况丢失的数据,等待远程自动回收.')
  else
      DoStatus('所有非序列化数据已经发送完毕.');
  Result := True;
end;

{ -----------------------------------------------------------------------------
  5. 键盘监听线程（用于手动退出程序）
  ----------------------------------------------------------------------------- }
var
  is_Running: Boolean;

procedure Key_Listen();
var
  s: string;
begin
  DoStatus('input exit do exit.');
  repeat
    readln(s);
    s := umlLowerCase(s).TrimChar(#32#9);
  until s = 'exit';
end;

{ -----------------------------------------------------------------------------
  6. 主程序
  ----------------------------------------------------------------------------- }
var
  tk: TTimeTick;

begin
  try
    // 6.1 连接到服务端（纯消费者，不暴露 API）
    PrepareClient('ipc:demo', nil);

    if not PrepareDone() then
        Exit;

    // 6.2 启动键盘监听线程
    TCompute.RunC_NP(Key_Listen, @is_Running, nil);

    // 6.3 主循环：每 5 秒执行一次 Test_BigData
    tk := GetTimeTick();
    while is_Running do
      begin
        Z.Core.Check_Soft_Thread_Synchronize(10); // 处理线程同步
        if GetTimeTick() - tk > 2000 then
          begin
            // 随机决定是否模拟坏情况（约 50% 概率）
            if not Test_BigData((TMT19937.Rand32 mod 2) = 0) then
                Exit;
            tk := GetTimeTick();
          end;
      end;

  finally
      Shutdown(); // 关闭 zAPI 框架
  end;

end.
