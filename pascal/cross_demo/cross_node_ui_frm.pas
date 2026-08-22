unit cross_node_ui_frm;

{
  ═══════════════════════════════════════════════════════════════════════════
  cross_node_ui_frm – 跨语言计算节点 UI 示例（高级跳板 + 主线程同步）
  ═══════════════════════════════════════════════════════════════════════════

  本单元展示了 zAPI 框架中两种核心机制的高级用法：

  1.  【对象方法回调桥接（跳板）】
      ──────────────────────────────
      • 使用 API__.API_Reg_Sync_Call_M 将 Pascal 对象方法
        （Tcross_node_ui_form.do_add_Call / do_inv_seri_Call）
        注册为远程 API 回调。
      • 底层通过 API_Reg_Sync_Call_M 将对象方法适配为 cdecl 回调，
        并指定“同步到主线程”模式。
      • 这种“跳板”机制让开发者能以自然的对象方法形式处理远程请求，
        而无需手动编写 cdecl 桥接函数。

  2.  【主线程同步机制（软同步队列）】
      ────────────────────────────────────
      • 注册的回调会在 C 线程池（C4 线程池）中触发，而非主线程。
      • 通过 RegisterSync 系列函数（此处为 Reg_Sync_Call_M），
        回调不会直接在 C 线程池执行，而是将任务排队到主线程的
        软同步队列（TSoft_Synchronize_Tool）中。
      • UI 组件（Memo、Label 等）必须在主线程中访问。
      • 定时器 sysTimer 每隔一定时间（默认 OnTimer 间隔）调用
        API.Sync，该函数会将队列中的任务弹出并在主线程中执行，
        从而安全地更新 UI。
      • 这种“用户态软同步”避免了操作系统内核同步对象的开销，
        适合高频回调场景（但也需注意忙等待的 CPU 消耗）。

  ═══════════════════════════════════════════════════════════════════════════
  架构层次示意
  ═══════════════════════════════════════════════════════════════════════════

     远程客户端
          │
          ▼
   zAPI 核心（C 线程池）
          │
          ▼
   Do_Internal_Sync_Call__  (桥接函数，将对象方法包装为 cdecl)
          │
          ▼
   TSoft_Synchronize_Tool.Synchronize  (将任务入队到主线程队列)
          │
          ▼
   主线程软同步队列 (TSynchronize_Queue___)
          │
          ▼
   API.Sync  (由定时器周期性调用，出队并执行)
          │
          ▼
   对象方法 (do_add_Call / do_inv_seri_Call)  ← 在主线程中执行，安全更新 UI

  ═══════════════════════════════════════════════════════════════════════════
  注意事项
  ═══════════════════════════════════════════════════════════════════════════
  ① 必须定期调用 API.Sync（通常在主循环或定时器中），否则队列任务永远不会执行。
  ② 同步回调虽然安全，但会增加主线程负担，不适合计算密集型任务。
  ③ 若回调执行时间过长，会阻塞主线程，导致 UI 卡顿。
  ④ 如需高吞吐、低延迟，应使用非同步版本（RegisterCall_M），
     但此时不能直接访问 UI，需通过其他同步手段（如 TThread.Queue）。

  ═══════════════════════════════════════════════════════════════════════════
  作者：老张 (qq600585)
  许可：MIT License
}

{$mode delphi}{$H+}
{$modeswitch advancedrecords}
{$CODEPAGE UTF8}
{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  z_api_hubtool_helper, z_api_hubtool_import;

type

  { Tcross_node_ui_form }

  Tcross_node_ui_form = class(TForm)
    info_Label: TLabel;
    Memo: TMemo;
    sysTimer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure sysTimerTimer(Sender: TObject);
  private

  public
    { 这两个方法将作为远程 API 的回调，由主线程安全地执行。
      注意：它们被注册为“同步到主线程”版本，因此不会在 C 线程池中执行。 }
    procedure do_add_Call(Input: TDataHnd; Output: TDataHnd);
    procedure do_inv_seri_Call(Input: TDataHnd; Output: TDataHnd);
  end;

  { TBoot_Th – 后台启动线程
    负责初始化 zAPI 网络并注册 API。
    由于 zAPI 网络启动可能阻塞，放在独立线程中避免 UI 卡顿。 }
  TBoot_Th = class(TThread)
  public
    procedure Execute; override;
  end;

var
  cross_node_ui_form: Tcross_node_ui_form;

implementation

{$R *.lfm}

{ TBoot_Th.Execute – 后台线程中初始化 zAPI 网络并注册 API }
procedure TBoot_Th.Execute;
var
  app: TAppHnd;
begin
  FreeOnTerminate := True;

  // 清空之前的所有网络准备状态
  API.ResetPrepare;

  // 创建应用句柄（应用名 'demo' 需与服务端和其他节点一致）
  app := API__.API_Create_APPHnd2('demo', 'cross app inst');

  { 关键：使用 API_Reg_Sync_Call_M 注册对象方法回调（同步到主线程版本）
    参数说明：
      - app          : 应用句柄
      - 'add'        : API 名称（客户端调用时使用）
      - 'add(int a, int b)' : 描述（仅用于文档）
      - cross_node_ui_form.do_add_Call : 对象方法（TAPI_Call_M 类型）
    底层效果：
      ① 将对象方法转换为 cdecl 桥接函数（Do_Internal_Sync_Call__）
      ② 桥接函数内部调用 Soft_Sync.Synchronize，将实际任务排队到主线程
      ③ 主线程需定期调用 API.Sync 出队执行
  }
  API__.API_Reg_Sync_Call_M(app, 'add', 'add(int a, int b)', cross_node_ui_form.do_add_Call);
  API__.API_Reg_Sync_Call_M(app, 'inv_seri', 'inv_seri()', cross_node_ui_form.do_inv_seri_Call);

  // 启用部署模式：不等待服务端就绪，允许节点先于服务启动（自动重连）
  API__.API_SetOption2('Wait_Ready', 'False');

  // 重置网络准备状态（再次调用确保配置干净）
  API__.API_Reset_Prepare();

  // 准备客户端连接，暴露 app 应用
  API__.API_Prepare_Client2('ipc:cross', app);

  // 启动网络框架（阻塞直到初始化完成）
  API__.API_Prepare_Done();
end;

{ Tcross_node_ui_form.do_add_Call – 加法回调（主线程执行） }
procedure Tcross_node_ui_form.do_add_Call(Input: TDataHnd; Output: TDataHnd);
var
  a, b, c: integer;
begin
  // 从输入句柄读取两个整数
  a := API__.API_ReadInt32(Input);
  b := API__.API_ReadInt32(Input);
  c := a + b;

  // 此处安全地更新 UI（因为已同步到主线程）
  Memo.Lines.Add(Format('收到计算请求 "a(%d)+b(%d)" = 计算结果 "%d"', [a, b, c]));

  // 将结果写入输出句柄
  API__.API_WriteInt32(Output, c);
end;

{ Tcross_node_ui_form.do_inv_seri_Call – 序列化反转回调（主线程执行） }
procedure Tcross_node_ui_form.do_inv_seri_Call(Input: TDataHnd; Output: TDataHnd);
var
  b: byte;
  w: word;
  c: cardinal;
  u64: uint64;
  s: string;
  f: single;
begin
  // 按顺序读取各种类型（客户端写入顺序：b, w, c, u64, s, f）
  b := API__.API_ReadUInt8(Input);
  w := API__.API_ReadUInt16(Input);
  c := API__.API_ReadUInt32(Input);
  u64 := API__.API_ReadUInt64(Input);
  s := API__.API_ReadString(Input);
  f := API__.API_ReadSingle(Input);

  // 反向写入响应（验证序列化/反序列化正确性）
  API__.API_WriteSingle(Output, f);
  API__.API_WriteString(Output, s);
  API__.API_WriteUInt64(Output, u64);
  API__.API_WriteUInt32(Output, c);
  API__.API_WriteUInt16(Output, w);
  API__.API_WriteUInt8(Output, b);

  // 安全更新 UI（主线程）
  Memo.Lines.Add(Format('接收数据序 [%d, %d, %d, %d, "%s", %.2f] = 发送数据序 [%.2f, "%s", %d, %d, %d, %d] ',
    [b, w, c, u64, s, f, f, s, u64, c, w, b]));
end;

{ sysTimerTimer – 定时器事件，驱动主线程同步队列 }
procedure Tcross_node_ui_form.sysTimerTimer(Sender: TObject);
begin
  { 关键：每次定时器触发时调用 API.Sync
    作用：从软同步队列中取出所有等待的任务，并在主线程中执行它们。
    若不调用，则所有同步回调将永久阻塞（死等）。 }
  API.Sync;
end;

{ FormCreate – 窗体创建时启动后台初始化线程 }
procedure Tcross_node_ui_form.FormCreate(Sender: TObject);
begin
  // 创建后台线程，负责启动 zAPI 网络（避免阻塞 UI 线程）
  TBoot_Th.Create(False);
end;

{ FormDestroy – 窗体销毁时关闭 zAPI 框架 }
procedure Tcross_node_ui_form.FormDestroy(Sender: TObject);
begin
  // 安全关闭网络，释放资源
  API__.API_shutdown;
end;

end.