(*
MIT License

Copyright (c) 2026 by.LaoZhang qq600585

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*)
{
  * ****************************************************************************
  * Z.Net.Server.Refrence
  * 开发参考单元 – 演示如何从 TPeerIO 和 TZNet_Server 派生出自定义网络服务。
  *
  * 本单元提供两个模板类：
  *   - TServer_PeerIO          : 自定义连接对象，代表一个客户端连接。
  *   - TCommunicationFramework_Server_Refrence : 自定义服务框架，管理所有连接。
  *
  * 开发者可复制这两个类，填充实际 I/O 操作（如 TCP、UDP、蓝牙、串口等），
  * 从而快速构建自己的网络服务端。
  *
  * 所有方法在此仅为占位，实际使用时应按需重写。
  * 特别关注 Write_IO_Buffer、StartService、StopService 等核心方法。
  *
  * 本单元同时展示了框架的基本调用约定，适合作为新服务实现的起点。
  * ****************************************************************************
}
unit Z.Net.Server.Refrence;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses SysUtils, Classes,
  Z.PascalStrings,
  Z.Net, Z.Core, Z.UnicodeMixedLib, Z.MemoryStream, Z.DFE;

type
  {
    * TServer_PeerIO
    * 自定义连接对象，代表一个客户端会话。
    * 继承自 TPeerIO，需要实现数据收发、连接状态、断开等核心接口。
    * 开发者应在此类中封装具体传输层（如 TcpSocket、WinHTTP、蓝牙等）的操作。
    *
    * @Example:
    *   var
    *     MyIO: TServer_PeerIO;
    *   begin
    *     // 在服务端 OnAccept 或 OnConnect 事件中创建
    *     MyIO := TServer_PeerIO.Create(OwnerFramework, nil);
    *     // 注册命令处理器（若使用 Z.Net 的命令框架）
    *     MyIO.OwnerFramework.RegisterConsole('echo').OnExecute := MyEchoHandler;
    *   end;
  }
  TServer_PeerIO = class(TPeerIO)
  public
    procedure CreateAfter; override;
    destructor Destroy; override;

    {
      * 返回当前连接是否有效。
      * 对于持久连接（如 TCP），通常检查底层套接字状态。
      * 模板中始终返回 True（表示连接一直存在），实际应依据底层句柄判断。
      * @Returns: True 表示连接可用，False 表示已断开。
    }
    function Connected: Boolean; override;

    {
      * 主动断开连接。
      * 应在此方法中释放底层资源、关闭句柄，并通知框架。
      * 模板中为空，实际需调用底层关闭函数。
    }
    procedure Disconnect; override;

    {
      * 核心发送接口 – 框架将待发送数据通过此方法传递给派生类。
      * 参数 buff 指向数据缓冲区，Size 为字节数。
      * 派生类应在此处将数据写入实际传输通道（如 socket.Send）。
      * 注意：此方法可能被多次调用，每次发送一块数据。
      * 若发送失败，应调用 Disconnect 断开。
    }
    procedure Write_IO_Buffer(const buff: PByte; const Size: nativeInt); override;

    {
      * 发送缓冲开始 – 框架在批量发送数据前调用。
      * 可用于锁定发送资源、开始事务等。
      * 模板中为空，实际可在此执行 BeginSend 等操作。
    }
    procedure WriteBufferOpen; override;

    {
      * 发送缓冲刷新 – 框架在每块数据发送完毕后调用。
      * 用于将累积数据强制提交（如 flush 缓冲区）。
      * 模板中为空，实际可调用 Flush。
    }
    procedure WriteBufferFlush; override;

    {
      * 发送缓冲结束 – 框架在一次完整发送流程后调用。
      * 可用于释放锁、结束事务等。
      * 模板中为空。
    }
    procedure WriteBufferClose; override;

    {
      * 获取对端 IP 地址（字符串形式）。
      * 用于日志、统计和身份识别。
      * 模板返回空字符串，实际应返回客户端地址（如 '192.168.1.100'）。
    }
    function GetPeerIP: SystemString; override;

    {
      * 检查发送缓冲区是否为空。
      * 框架调用此方法判断是否还有待发送数据，用于优化忙等待。
      * 若返回 True，表示当前没有待发送数据，框架可进入空闲状态。
      * 若实现异步发送，此方法应反映真实队列状态。
      * 模板始终返回 True（空）。
    }
    function WriteBuffer_is_NULL: Boolean; override;

    {
      * 核心进度驱动方法 – 框架主循环会定期调用。
      * 派生类可在此处处理接收数据、心跳、超时检测等。
      * 模板中调用了 inherited 并执行 Process_Send_Buffer() 以驱动发送队列。
      * 实际应添加底层接收数据读取和触发 Process_Receive_Buffer 的逻辑。
    }
    procedure Progress; override;
  end;

  {
    * TCommunicationFramework_Server_Refrence
    * 自定义服务框架，负责管理所有连接、启动/停止服务、驱动进度。
    * 继承自 TZNet_Server，是服务端的顶层容器。
    * 开发者需重写 StartService、StopService 以及事件处理。
    *
    * @Example:
    *   var
    *     Server: TCommunicationFramework_Server_Refrence;
    *   begin
    *     Server := TCommunicationFramework_Server_Refrence.Create;
    *     // 注册业务命令
    *     Server.RegisterConsole('status').OnExecute := MyStatusHandler;
    *     // 启动服务（例如 TCP 监听 0.0.0.0:8080）
    *     Server.StartService('0.0.0.0', 8080);
    *     // 主循环
    *     while True do
    *     begin
    *       Server.Progress;   // 驱动所有连接处理
    *       Sleep(1);
    *     end;
    *     Server.Free;
    *   end;
  }
  TCommunicationFramework_Server_Refrence = class(TZNet_Server)
  private
  protected
  public
    constructor Create; override;
    destructor Destroy; override;

    {
      * 启动服务 – 开始监听或建立服务端。
      * Host 为地址（如 '0.0.0.0' 或 '::'），Port 为端口。
      * 返回值表示启动是否成功。
      * 模板始终返回 False，实际应在此创建监听套接字、绑定端口。
    }
    function StartService(Host: SystemString; Port: Word): Boolean; override;

    {
      * 停止服务 – 停止监听，并断开所有连接。
      * 模板为空，实际应关闭监听句柄，并调用 Disconnect 断开所有客户端。
    }
    procedure StopService; override;

    {
      * 核心进度驱动 – 框架主循环调用。
      * 模板调用 inherited，实际应添加自己的定时任务或状态更新。
    }
    procedure Progress; override;

    {
      * 同步阻塞发送控制台命令（不推荐在服务端使用）。
      * 此方法会阻塞当前线程直到收到响应或超时，容易导致死锁。
      * 模板直接抛出异常，提示不支持。
    }
    function WaitSendConsoleCmd(p_io: TPeerIO; const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString; override;

    {
      * 同步阻塞发送流命令（不推荐在服务端使用）。
      * 同 WaitSendConsoleCmd，不支持阻塞调用。
      * 模板抛出异常。
    }
    procedure WaitSendStreamCmd(p_io: TPeerIO; const Cmd: SystemString; StreamData, ResultData: TDFE; TimeOut_: TTimeTick); override;
  end;

implementation

{ TServer_PeerIO }

procedure TServer_PeerIO.CreateAfter;
{
  * 在构造完成后调用，用于执行额外的初始化。
  * 模板中仅调用 inherited，实际可在连接建立后设置定时器或缓存。
}
begin
  inherited CreateAfter;
end;

destructor TServer_PeerIO.Destroy;
{
  * 析构函数，释放资源。
  * 模板调用 inherited，实际需释放底层句柄和分配的内存。
}
begin
  inherited Destroy;
end;

function TServer_PeerIO.Connected: Boolean;
{
  * 返回连接状态。模板恒为 True，表示始终连接。
  * 实际应检查底层套接字是否有效、是否被对端关闭。
}
begin
  Result := True;
end;

procedure TServer_PeerIO.Disconnect;
{
  * 断开连接。模板为空，实际应关闭底层通信句柄，
  * 并触发框架的断开事件（如调用 DelayFree）。
}
begin
end;

procedure TServer_PeerIO.Write_IO_Buffer(const buff: PByte; const Size: nativeInt);
{
  * 发送数据。模板直接返回，实际需将 buff 指向的 Size 字节数据
  * 通过传输层发送出去。
  * 若发送失败，建议调用 Disconnect。
}
begin
  if not Connected then
      Exit;
end;

procedure TServer_PeerIO.WriteBufferOpen;
{
  * 开始发送缓冲。模板为空，实际可在此处准备发送上下文。
}
begin
end;

procedure TServer_PeerIO.WriteBufferFlush;
{
  * 刷新发送缓冲。模板为空，实际可在此处将累积数据强制写出。
}
begin
end;

procedure TServer_PeerIO.WriteBufferClose;
{
  * 结束发送缓冲。模板为空，实际可在此处清理发送上下文。
}
begin
end;

function TServer_PeerIO.GetPeerIP: SystemString;
{
  * 获取对端 IP。模板返回空字符串，实际应返回客户端 IP 地址。
}
begin
  Result := '';
end;

function TServer_PeerIO.WriteBuffer_is_NULL: Boolean;
{
  * 检查发送队列是否为空。模板恒为 True，表示无待发数据。
  * 实际应检查内部发送队列的长度。
}
begin
  Result := True;
end;

procedure TServer_PeerIO.Progress;
{
  * 核心进度方法。模板调用 inherited 执行基类处理，然后调用
  * Process_Send_Buffer 驱动发送队列。
  * 实际应在此处添加接收数据的轮询，并将收到的数据传入
  * Process_Receive_Buffer 或 Write_Physics_Fragment。
}
begin
  inherited Progress;
  Process_Send_Buffer(); // 处理发送队列中的命令
end;

{ TCommunicationFramework_Server_Refrence }

constructor TCommunicationFramework_Server_Refrence.Create;
{
  * 构造函数。模板调用 inherited，实际可在此处初始化自定义属性。
}
begin
  inherited Create;
end;

destructor TCommunicationFramework_Server_Refrence.Destroy;
{
  * 析构函数。模板先调用 StopService 停止服务，再调用 inherited。
  * 确保所有连接被释放。
}
begin
  StopService;
  inherited Destroy;
end;

function TCommunicationFramework_Server_Refrence.StartService(Host: SystemString; Port: Word): Boolean;
{
  * 启动服务。模板始终返回 False，实际应在此处：
  *   1. 创建监听套接字，绑定 Host:Port。
  *   2. 开始监听。
  *   3. 启动接收线程或设置异步回调。
  *   4. 返回 True 表示成功。
  *   5. 若失败，应抛出异常或返回 False。
}
begin
  Result := False;
end;

procedure TCommunicationFramework_Server_Refrence.StopService;
{
  * 停止服务。模板为空，实际应：
  *   1. 关闭监听套接字。
  *   2. 遍历所有连接，调用 TPeerIO.Disconnect 断开。
  *   3. 等待所有线程结束。
}
begin
end;

procedure TCommunicationFramework_Server_Refrence.Progress;
{
  * 驱动服务进度。模板仅调用 inherited，实际可：
  *   1. 调用 inherited 驱动基类处理。
  *   2. 执行自定义定时任务（如统计、健康检查）。
  *   3. 处理外部事件。
}
begin
  inherited Progress;
end;

function TCommunicationFramework_Server_Refrence.WaitSendConsoleCmd(p_io: TPeerIO;
  const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString;
{
  * 阻塞等待控制台命令响应。服务端通常不应使用阻塞调用，因此模板直接抛出异常。
  * 若确实需要，可重写为异步等待，但强烈建议避免。
}
begin
  Result := '';
  RaiseInfo('WaitSend no Suppport');
end;

procedure TCommunicationFramework_Server_Refrence.WaitSendStreamCmd(p_io: TPeerIO;
  const Cmd: SystemString; StreamData, ResultData: TDFE; TimeOut_: TTimeTick);
{
  * 阻塞等待流命令响应。同 WaitSendConsoleCmd，服务端不支持阻塞调用。
  * 模板抛出异常。
}
begin
  RaiseInfo('WaitSend no Suppport');
end;

initialization
finalization
end.

 
