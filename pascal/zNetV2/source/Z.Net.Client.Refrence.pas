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
 * Z.Net.Client.Refrence
 * 开发参考单元 – 演示如何从 TPeerIO 和 TZNet_Client 派生出自定义网络客户端。
 *
 * 本单元提供两个模板类：
 *   - TClient_PeerIO          : 自定义连接对象，代表与服务器的单条连接。
 *   - TCommunicationFramework_Client_Refrence : 自定义客户端框架，管理连接和通信。
 *
 * 开发者可复制这两个类，填充实际 I/O 操作（如 TCP、UDP、蓝牙、串口等），
 * 从而快速构建自己的网络客户端。
 *
 * 所有方法在此仅为占位，实际使用时应按需重写。
 * 特别关注 Connect、AsyncConnect 系列、Write_IO_Buffer 等核心方法。
 *
 * 本单元同时展示了客户端特有的异步/同步连接模型，适合作为新客户端实现的起点。
 * ****************************************************************************
}
unit Z.Net.Client.Refrence;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses SysUtils, Classes,
  Z.PascalStrings,
  Z.Net, Z.Core, Z.UnicodeMixedLib, Z.MemoryStream,
  Z.Notify;

type
  {
   * TClient_PeerIO
   * 自定义连接对象，代表客户端与服务器的一个会话。
   * 继承自 TPeerIO，需要实现数据收发、连接状态、断开等核心接口。
   * 开发者应在此类中封装具体传输层（如 TcpSocket、WinHTTP 等）的操作。
   *
   * @Example:
   *   var
   *     MyIO: TClient_PeerIO;
   *   begin
   *     // 在客户端连接成功后创建
   *     MyIO := TClient_PeerIO.Create(OwnerFramework, nil);
   *     // 注册命令处理器（若使用 Z.Net 的命令框架）
   *     MyIO.OwnerFramework.RegisterConsole('ping').OnExecute := MyPingHandler;
   *   end;
   }
  TClient_PeerIO = class(TPeerIO)
  public
    procedure CreateAfter; override;
    destructor Destroy; override;

    {
     * 返回当前连接是否有效。
     * 对于客户端，通常检查底层套接字是否已连接且未关闭。
     * 模板中始终返回 True（表示连接一直存在），实际应依据底层句柄状态。
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
     * 模板返回空字符串，实际应返回服务器 IP 地址。
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
   * TCommunicationFramework_Client_Refrence
   * 自定义客户端框架，负责管理连接、启动/停止服务、驱动进度。
   * 继承自 TZNet_Client，是客户端的顶层容器。
   * 开发者需重写 Connect、AsyncConnect 系列、Disconnect 以及事件回调。
   *
   * @Example:
   *   var
   *     Client: TCommunicationFramework_Client_Refrence;
   *   begin
   *     Client := TCommunicationFramework_Client_Refrence.Create;
   *     // 注册业务命令
   *     Client.RegisterConsole('status').OnExecute := MyStatusHandler;
   *     // 阻塞方式连接服务器
   *     if Client.Connect('127.0.0.1', 8080) then
   *     begin
   *       // 发送命令
   *       Client.SendConsoleCmd('hello', 'world');
   *     end;
   *     // 主循环
   *     while Client.Connected do
   *     begin
   *       Client.Progress;   // 驱动连接处理
   *       Sleep(1);
   *     end;
   *     Client.Free;
   *   end;
   *
   * @Note: 异步连接示例见 AsyncConnectC 方法的注释。
   }
  TCommunicationFramework_Client_Refrence = class(TZNet_Client)
  public
    constructor Create; override;
    destructor Destroy; override;

    {
     * 异步连接失败时由框架调用的回调钩子。
     * 派生类可重写此方法以执行自定义失败处理（如重试、记录日志）。
     * 模板调用 inherited，实际可添加额外逻辑。
    }
    procedure TriggerDoConnectFailed; override;

    {
     * 异步连接成功时由框架调用的回调钩子。
     * 派生类可重写此方法以执行自定义成功处理（如发送初始化命令）。
     * 模板调用 inherited。
    }
    procedure TriggerDoConnectFinished; override;

    {
     * 异步连接（C 风格回调）。
     * 启动非阻塞连接，连接结果通过 OnResult 回调返回（参数 State: Boolean）。
     * 若忽略此接口，系统将使用阻塞连接方式。
     * @Param addr: 服务器地址（如 '127.0.0.1' 或 '::1'）。
     * @Param Port: 服务器端口。
     * @Param OnResult: 回调过程，State=True 表示连接成功，False 表示失败。
     * @Example:
     *   Client.AsyncConnectC('127.0.0.1', 8080,
     *     procedure(State: Boolean)
     *     begin
     *       if State then
     *         WriteLn('Connected!')
     *       else
     *         WriteLn('Connect failed.');
     *     end
     *   );
    }
    procedure AsyncConnectC(addr: SystemString; Port: Word; const OnResult: TOnState_C); override;

    {
     * 异步连接（方法风格回调）。
     * 与 AsyncConnectC 相同，但回调是对象方法（of object）。
     * @Param addr: 服务器地址。
     * @Param Port: 服务器端口。
     * @Param OnResult: 方法回调，State 表示结果。
    }
    procedure AsyncConnectM(addr: SystemString; Port: Word; const OnResult: TOnState_M); override;

    {
     * 异步连接（嵌套/匿名风格回调）。
     * 与 AsyncConnectC 相同，但回调是嵌套过程（is nested）或匿名方法（reference）。
     * @Param addr: 服务器地址。
     * @Param Port: 服务器端口。
     * @Param OnResult: 嵌套回调，State 表示结果。
    }
    procedure AsyncConnectP(addr: SystemString; Port: Word; const OnResult: TOnState_P); override;

    {
     * 核心接口：阻塞连接。
     * 必须确保在调用返回时加密协议已完成协商，连接可用。
     * 参考 CrossSocket 或 Indy 的接口实现。
     * @Param addr: 服务器地址。
     * @Param Port: 服务器端口。
     * @Returns: True 表示连接成功且协议就绪，False 表示失败。
     * @Note: 此方法会阻塞当前线程直到连接完成或超时。
    }
    function Connect(addr: SystemString; Port: Word): Boolean; override;

    {
     * 返回当前连接状态。
     * 基于 ClientIO 是否有效且已连接。
     * @Returns: True 表示已连接，False 表示未连接。
    }
    function Connected: Boolean; override;

    {
     * 断开连接。
     * 若当前已连接，则调用 ClientIO.Disconnect 断开。
    }
    procedure Disconnect; override;

    {
     * 返回底层 TPeerIO 实例。
     * 派生类必须实现此方法，返回实际使用的连接对象。
     * 模板返回 nil，实际应返回 TClient_PeerIO 实例。
     * @Returns: 当前连接对象，若未连接则返回 nil。
    }
    function ClientIO: TPeerIO; override;

    {
     * 核心进度驱动 – 框架主循环调用。
     * 模板调用 inherited，实际可添加自己的定时任务或状态更新。
    }
    procedure Progress; override;
  end;

implementation

{ TClient_PeerIO }

procedure TClient_PeerIO.CreateAfter;
{
 * 在构造完成后调用，用于执行额外的初始化。
 * 模板中仅调用 inherited，实际可在连接建立后设置定时器或缓存。
}
begin
  inherited CreateAfter;
end;

destructor TClient_PeerIO.Destroy;
{
 * 析构函数，释放资源。
 * 模板调用 inherited，实际需释放底层句柄和分配的内存。
}
begin
  inherited Destroy;
end;

function TClient_PeerIO.Connected: Boolean;
{
 * 返回连接状态。模板恒为 True，表示始终连接。
 * 实际应检查底层套接字是否有效、是否被对端关闭。
}
begin
  Result := True;
end;

procedure TClient_PeerIO.Disconnect;
{
 * 断开连接。模板为空，实际应关闭底层通信句柄，
 * 并触发框架的断开事件（如调用 DelayFree）。
}
begin
end;

procedure TClient_PeerIO.Write_IO_Buffer(const buff: PByte; const Size: nativeInt);
{
 * 发送数据。模板直接返回，实际需将 buff 指向的 Size 字节数据
 * 通过传输层发送出去。
 * 若发送失败，建议调用 Disconnect。
}
begin
  if not Connected then
      Exit;
end;

procedure TClient_PeerIO.WriteBufferOpen;
{
 * 开始发送缓冲。模板为空，实际可在此处准备发送上下文。
}
begin
end;

procedure TClient_PeerIO.WriteBufferFlush;
{
 * 刷新发送缓冲。模板为空，实际可在此处将累积数据强制写出。
}
begin
end;

procedure TClient_PeerIO.WriteBufferClose;
{
 * 结束发送缓冲。模板为空，实际可在此处清理发送上下文。
}
begin
end;

function TClient_PeerIO.GetPeerIP: SystemString;
{
 * 获取对端 IP。模板返回空字符串，实际应返回服务器 IP 地址。
}
begin
  Result := '';
end;

function TClient_PeerIO.WriteBuffer_is_NULL: Boolean;
{
 * 检查发送队列是否为空。模板恒为 True，表示无待发数据。
 * 实际应检查内部发送队列的长度。
}
begin
  Result := True;
end;

procedure TClient_PeerIO.Progress;
{
 * 核心进度方法。模板调用 inherited 执行基类处理，然后调用
 * Process_Send_Buffer 驱动发送队列。
 * 实际应在此处添加接收数据的轮询，并将收到的数据传入
 * Process_Receive_Buffer 或 Write_Physics_Fragment。
}
begin
  inherited Progress;
  Process_Send_Buffer();  // 处理发送队列中的命令
end;

{ TCommunicationFramework_Client_Refrence }

constructor TCommunicationFramework_Client_Refrence.Create;
{
 * 构造函数。模板调用 inherited，实际可在此处初始化自定义属性。
}
begin
  inherited Create;
end;

destructor TCommunicationFramework_Client_Refrence.Destroy;
{
 * 析构函数。模板先调用 Disconnect 断开连接，再调用 inherited。
 * 确保资源被释放。
}
begin
  Disconnect;
  inherited Destroy;
end;

procedure TCommunicationFramework_Client_Refrence.TriggerDoConnectFailed;
{
 * 异步连接失败时的回调钩子。
 * 模板调用 inherited，实际可重写以添加重试逻辑或错误日志。
}
begin
  inherited TriggerDoConnectFailed;
end;

procedure TCommunicationFramework_Client_Refrence.TriggerDoConnectFinished;
{
 * 异步连接成功时的回调钩子。
 * 模板调用 inherited，实际可重写以发送初始数据或更新状态。
}
begin
  inherited TriggerDoConnectFinished;
end;

procedure TCommunicationFramework_Client_Refrence.AsyncConnectC(addr: SystemString; Port: Word; const OnResult: TOnState_C);
{
 * 异步连接（C 风格）。模板直接 inherited，实际应实现非阻塞连接逻辑，
 * 在连接完成或失败时调用 OnResult。
 * 通常由底层传输层异步事件触发。
}
begin
  inherited;  // 若基类无实现，则此处为空，需重写
end;

procedure TCommunicationFramework_Client_Refrence.AsyncConnectM(addr: SystemString; Port: Word; const OnResult: TOnState_M);
{
 * 异步连接（方法风格）。同 AsyncConnectC。
}
begin
  inherited;
end;

procedure TCommunicationFramework_Client_Refrence.AsyncConnectP(addr: SystemString; Port: Word; const OnResult: TOnState_P);
{
 * 异步连接（嵌套风格）。同 AsyncConnectC。
}
begin
  inherited;
end;

function TCommunicationFramework_Client_Refrence.Connect(addr: SystemString; Port: Word): Boolean;
{
 * 阻塞连接。模板始终返回 False，实际应：
 *   1. 创建底层套接字并连接 addr:Port。
 *   2. 若连接成功，创建 TClient_PeerIO 实例并关联。
 *   3. 执行加密协议握手（若有）。
 *   4. 返回 True 表示连接成功且协议就绪。
 *   5. 若失败，返回 False。
}
begin
  Result := False;
end;

function TCommunicationFramework_Client_Refrence.Connected: Boolean;
{
 * 返回连接状态。基于 ClientIO 是否存在且已连接。
 * 模板检查 ClientIO <> nil and ClientIO.Connected。
}
begin
  Result := (ClientIO <> nil) and (ClientIO.Connected);
end;

procedure TCommunicationFramework_Client_Refrence.Disconnect;
{
 * 断开连接。若已连接，则调用 ClientIO.Disconnect。
 * 模板实现正确，无需修改。
}
begin
  if Connected then
      ClientIO.Disconnect;
end;

function TCommunicationFramework_Client_Refrence.ClientIO: TPeerIO;
{
 * 返回底层连接对象。模板返回 nil，实际应返回 TClient_PeerIO 实例。
 * 此方法被 Connected、Disconnect、Progress 等调用。
}
begin
  Result := nil;
end;

procedure TCommunicationFramework_Client_Refrence.Progress;
{
 * 驱动客户端进度。模板调用 inherited，实际可添加：
 *   1. 处理自定义消息队列。
 *   2. 执行心跳或超时检测。
 *   3. 处理外部事件。
}
begin
  inherited Progress;
end;

initialization
finalization
end.
 
