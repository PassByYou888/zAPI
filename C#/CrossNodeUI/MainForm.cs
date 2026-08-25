using System;
using System.Drawing;
using System.Threading;
using System.Windows.Forms;
using API_HubTool.Bindings;
using static API_HubTool.Bindings.API;

namespace CrossNodeUI
{
    /// <summary>
    /// 跨语言节点 UI 演示窗体 —— 使用同步回调机制优雅更新 UI
    /// 修复：桥接委托阻塞等待，保证句柄有效；改用 API_Reg_Call_Sync
    /// </summary>
    public partial class MainForm : Form
    {
        // ---- UI 控件 ----
        private Button btnStart;
        private Button btnStop;
        private Label lblStatus;
        private ListBox lstLog;
        private System.Windows.Forms.Timer timerRefresh;

        // ---- 运行时状态 ----
        private volatile bool _isRunning = false;
        private AppHnd _appHandle;
        private Thread _workerThread;

        // ---- 回调委托（必须保持存活，防止 GC） ----
        private APICallDelegate _addDelegate;
        private APICallDelegate _invSeriDelegate;

        public MainForm()
        {
            InitializeComponentManual();
            this.FormClosing += MainForm_FormClosing;
        }

        private void InitializeComponentManual()
        {
            this.btnStart = new Button();
            this.btnStop = new Button();
            this.lblStatus = new Label();
            this.lstLog = new ListBox();
            this.timerRefresh = new System.Windows.Forms.Timer();

            // btnStart
            this.btnStart.Location = new Point(12, 12);
            this.btnStart.Size = new Size(100, 30);
            this.btnStart.Text = "启动节点";
            this.btnStart.Click += BtnStart_Click;

            // btnStop
            this.btnStop.Location = new Point(118, 12);
            this.btnStop.Size = new Size(100, 30);
            this.btnStop.Text = "停止节点";
            this.btnStop.Enabled = false;
            this.btnStop.Click += BtnStop_Click;

            // lblStatus
            this.lblStatus.Location = new Point(12, 50);
            this.lblStatus.Size = new Size(400, 25);
            this.lblStatus.Text = "状态: 未启动";

            // lstLog
            this.lstLog.Location = new Point(12, 80);
            this.lstLog.Size = new Size(600, 300);
            this.lstLog.HorizontalScrollbar = true;

            // timerRefresh
            this.timerRefresh.Interval = 500;
            this.timerRefresh.Tick += TimerRefresh_Tick;

            // MainForm
            this.ClientSize = new Size(630, 400);
            this.Controls.Add(this.btnStart);
            this.Controls.Add(this.btnStop);
            this.Controls.Add(this.lblStatus);
            this.Controls.Add(this.lstLog);
            this.Text = "CrossNode UI (C#) - 同步回调版";
            this.StartPosition = FormStartPosition.CenterScreen;

            this.timerRefresh.Enabled = false;
        }

        // ---- 启动按钮 ----
        private void BtnStart_Click(object sender, EventArgs e)
        {
            if (_isRunning) return;
            btnStart.Enabled = false;
            btnStop.Enabled = true;
            _isRunning = true;

            _workerThread = new Thread(WorkerThreadProc);
            _workerThread.IsBackground = true;
            _workerThread.Start();

            timerRefresh.Enabled = true;
        }

        // ---- 停止按钮 ----
        private void BtnStop_Click(object sender, EventArgs e)
        {
            if (!_isRunning) return;
            _isRunning = false;
            btnStop.Enabled = false;
            btnStart.Enabled = true;
            timerRefresh.Enabled = false;
            if (_workerThread != null && _workerThread.IsAlive)
                _workerThread.Join(2000);
            API_Exit_MainThread();
            API_shutdown();
            UpdateStatus("已停止");
            AppendLog("节点已停止");
        }

        // ---- 窗体关闭事件 ----
        private void MainForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            _isRunning = false;
            timerRefresh.Enabled = false;
            if (_workerThread != null && _workerThread.IsAlive)
                _workerThread.Join(2000);
            API_Exit_MainThread();
            API_shutdown();
        }

        // ---- 后台工作线程（负责网络初始化） ----
        private void WorkerThreadProc()
        {
            try
            {
                API_Reset_Prepare();

                _appHandle = API_Create_APPHnd("demo", "C# CrossNode UI");

                // 创建用户回调委托
                _addDelegate = AddCallback;
                _invSeriDelegate = InvSeriCallback;

                // 使用官方同步注册接口（内部已实现阻塞等待）
                int r1 = API_Reg_Call_Sync(_appHandle, "add", "add(int a, int b)", IntPtr.Zero, _addDelegate);
                int r2 = API_Reg_Call_Sync(_appHandle, "inv_seri", "inv_seri()", IntPtr.Zero, _invSeriDelegate);

                this.BeginInvoke(new Action(() =>
                {
                    AppendLog($"API 注册结果: add={r1}, inv_seri={r2}");
                }));

                API_SetOption("Wait_Ready", "False");

                API_Reset_Prepare();
                int prep = API_Prepare_Client("ipc:cross", _appHandle);
                this.BeginInvoke(new Action(() =>
                {
                    AppendLog($"API_Prepare_Client 返回: {prep}");
                }));

                int done = API_Prepare_Done();
                this.BeginInvoke(new Action(() =>
                {
                    AppendLog($"API_Prepare_Done 返回: {done}");
                    if (done == 1)
                        UpdateStatus("运行中 (已连接)");
                    else
                        UpdateStatus("启动失败，查看日志");
                }));

                while (_isRunning)
                {
                    Thread.Sleep(100);
                }

                API_Exit_MainThread();
                API_shutdown();
                this.BeginInvoke(new Action(() =>
                {
                    AppendLog("工作线程正常退出");
                }));
            }
            catch (Exception ex)
            {
                this.BeginInvoke(new Action(() =>
                {
                    AppendLog($"后台线程异常: {ex.Message}");
                }));
            }
        }

        // ---- 加法回调（将在主线程执行，因使用了同步注册） ----
        private void AddCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };

            // 重置位置到开头（安全起见）
            API_SetPos(hInput, 0);
            API_SetPos(hOutput, 0);

            long size = API_GetSize(hInput);
            if (size < 8)
            {
                AppendLog($"加法参数大小异常: {size} 字节 (期望至少8)");
                return;
            }

            if (API_ReadInt32(hInput, out int a) && API_ReadInt32(hInput, out int b))
            {
                int c = a + b;
                API_WriteInt32(hOutput, c);
                AppendLog($"收到加法请求: {a}+{b}={c}");
                API_Post_Status($"加法计算: {a}+{b}={c}");
            }
            else
            {
                AppendLog($"加法参数读取失败 (大小={size})");
                // 可选：打印调试信息
            }
        }

        // ---- 序列化反转回调（将在主线程执行） ----
        private void InvSeriCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };

            API_SetPos(hInput, 0);
            API_SetPos(hOutput, 0);

            long size = API_GetSize(hInput);
            if (size < 1 + 2 + 4 + 8 + 1 + 4) // 最小20字节
            {
                AppendLog($"inv_seri 参数大小异常: {size} 字节 (期望至少20)");
                return;
            }

            if (API_ReadUInt8(hInput, out byte b) &&
                API_ReadUInt16(hInput, out ushort w) &&
                API_ReadUInt32(hInput, out uint c) &&
                API_ReadUInt64(hInput, out ulong u64))
            {
                string s = API_ReadString(hInput);
                if (API_ReadSingle(hInput, out float f))
                {
                    API_WriteSingle(hOutput, f);
                    API_WriteString(hOutput, s);
                    API_WriteUInt64(hOutput, u64);
                    API_WriteUInt32(hOutput, c);
                    API_WriteUInt16(hOutput, w);
                    API_WriteUInt8(hOutput, b);

                    AppendLog($"inv_seri 接收: [{b}, {w}, {c}, {u64}, \"{s}\", {f}] -> 反向响应");
                    API_Post_Status($"inv_seri 处理完成");
                }
                else
                {
                    AppendLog("inv_seri 读取 float 失败");
                }
            }
            else
            {
                AppendLog($"inv_seri 读取基本类型失败 (大小={size})");
            }
        }

        // ---- 定时器刷新（运行在 UI 线程） ----
        private void TimerRefresh_Tick(object sender, EventArgs e)
        {
            // 1. 驱动同步回调队列 —— 所有通过 Sync 注册的回调将在此处执行
            ProcessSyncQueue();

            // 2. 拉取库内部日志并显示
            int count = API_Get_Status_Num();
            for (int i = 0; i < count; i++)
            {
                string msg = API_Get_Status();
                if (!string.IsNullOrEmpty(msg))
                    AppendLog("[库] " + msg);
            }

            // 3. 更新状态显示
            int mainThreadRunning = API_Check_MainThread();
            int appExists = API_Check_App("demo");
            string status = $"主线程: {(mainThreadRunning == 1 ? "运行" : "停止")} | 应用 'demo': {(appExists == 1 ? "在线" : "离线")}";
            UpdateStatus(status);
        }

        // ---- 辅助：更新状态标签（线程安全） ----
        private void UpdateStatus(string text)
        {
            if (lblStatus.InvokeRequired)
                lblStatus.BeginInvoke(new Action(() => { lblStatus.Text = text; }));
            else
                lblStatus.Text = text;
        }

        // ---- 辅助：追加日志（线程安全） ----
        private void AppendLog(string text)
        {
            if (lstLog.InvokeRequired)
            {
                lstLog.BeginInvoke(new Action(() =>
                {
                    lstLog.Items.Add($"[{DateTime.Now:HH:mm:ss.fff}] {text}");
                    lstLog.SelectedIndex = lstLog.Items.Count - 1;
                    lstLog.ClearSelected();
                }));
            }
            else
            {
                lstLog.Items.Add($"[{DateTime.Now:HH:mm:ss.fff}] {text}");
                lstLog.SelectedIndex = lstLog.Items.Count - 1;
                lstLog.ClearSelected();
            }
        }
    }
}