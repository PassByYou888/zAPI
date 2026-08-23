Imports System
Imports System.Drawing
Imports System.Threading
Imports System.Windows.Forms
Imports ApiHubTool.Bindings

Namespace CrossNodeUI

    Public Class MainForm
        Inherits Form

        ' ---- UI 控件 ----
        Private WithEvents btnStart As Button
        Private WithEvents btnStop As Button
        Private lblStatus As Label
        Private lstLog As ListBox
        Private WithEvents timerRefresh As System.Windows.Forms.Timer

        ' ---- 运行时状态 ----
        Private _isRunning As Boolean = False
        Private _appHandle As AppHnd
        Private _workerThread As Thread

        ' ---- 回调委托（必须保持存活，防止 GC） ----
        Private _addDelegate As APICallDelegate
        Private _invSeriDelegate As APICallDelegate

        Public Sub New()
            InitializeComponentManual()
            AddHandler Me.FormClosing, AddressOf MainForm_FormClosing
        End Sub

        Private Sub InitializeComponentManual()
            Me.btnStart = New Button()
            Me.btnStop = New Button()
            Me.lblStatus = New Label()
            Me.lstLog = New ListBox()
            Me.timerRefresh = New System.Windows.Forms.Timer()

            ' btnStart
            Me.btnStart.Location = New Point(12, 12)
            Me.btnStart.Size = New Size(100, 30)
            Me.btnStart.Text = "启动节点"
            AddHandler Me.btnStart.Click, AddressOf BtnStart_Click

            ' btnStop
            Me.btnStop.Location = New Point(118, 12)
            Me.btnStop.Size = New Size(100, 30)
            Me.btnStop.Text = "停止节点"
            Me.btnStop.Enabled = False
            AddHandler Me.btnStop.Click, AddressOf BtnStop_Click

            ' lblStatus
            Me.lblStatus.Location = New Point(12, 50)
            Me.lblStatus.Size = New Size(400, 25)
            Me.lblStatus.Text = "状态: 未启动"

            ' lstLog
            Me.lstLog.Location = New Point(12, 80)
            Me.lstLog.Size = New Size(600, 300)
            Me.lstLog.HorizontalScrollbar = True

            ' timerRefresh
            Me.timerRefresh.Interval = 500
            AddHandler Me.timerRefresh.Tick, AddressOf TimerRefresh_Tick

            ' MainForm
            Me.ClientSize = New Size(630, 400)
            Me.Controls.Add(Me.btnStart)
            Me.Controls.Add(Me.btnStop)
            Me.Controls.Add(Me.lblStatus)
            Me.Controls.Add(Me.lstLog)
            Me.Text = "CrossNode UI (VB.NET)"
            Me.StartPosition = FormStartPosition.CenterScreen

            Me.timerRefresh.Enabled = False
        End Sub

        ' ---- 启动按钮 ----
        Private Sub BtnStart_Click(sender As Object, e As EventArgs)
            If _isRunning Then Return
            btnStart.Enabled = False
            btnStop.Enabled = True
            _isRunning = True

            _workerThread = New Thread(AddressOf WorkerThreadProc)
            _workerThread.IsBackground = True
            _workerThread.Start()

            timerRefresh.Enabled = True
        End Sub

        ' ---- 停止按钮 ----
        Private Sub BtnStop_Click(sender As Object, e As EventArgs)
            If Not _isRunning Then Return
            _isRunning = False
            btnStop.Enabled = False
            btnStart.Enabled = True
            timerRefresh.Enabled = False
            If _workerThread IsNot Nothing AndAlso _workerThread.IsAlive Then
                _workerThread.Join(2000)
            End If
            API.API_Exit_MainThread()
            API.API_shutdown()
            UpdateStatus("已停止")
            AppendLog("节点已停止")
        End Sub

        ' ---- 窗体关闭事件 ----
        Private Sub MainForm_FormClosing(sender As Object, e As FormClosingEventArgs)
            _isRunning = False
            timerRefresh.Enabled = False
            If _workerThread IsNot Nothing AndAlso _workerThread.IsAlive Then
                _workerThread.Join(2000)
            End If
            API.API_Exit_MainThread()
            API.API_shutdown()
        End Sub

        ' ---- 后台工作线程 ----
        Private Sub WorkerThreadProc()
            Try
                API.API_Reset_Prepare()

                _appHandle = API.API_Create_APPHnd("demo", "VB.NET CrossNode UI")

                _addDelegate = AddressOf AddCallback
                _invSeriDelegate = AddressOf InvSeriCallback

                Dim r1 As Integer = API.API_Reg_Call(_appHandle, "add", "add(int a, int b)", IntPtr.Zero, _addDelegate)
                Dim r2 As Integer = API.API_Reg_Call(_appHandle, "inv_seri", "inv_seri()", IntPtr.Zero, _invSeriDelegate)

                Me.BeginInvoke(Sub()
                                   AppendLog($"API 注册结果: add={r1}, inv_seri={r2}")
                               End Sub)

                API.API_SetOption("Wait_Connection_ReadyOk", "False")

                API.API_Reset_Prepare()
                Dim prep As Integer = API.API_Prepare_Client("ipc:cross", _appHandle)
                Me.BeginInvoke(Sub()
                                   AppendLog($"API_Prepare_Client 返回: {prep}")
                               End Sub)

                Dim done As Integer = API.API_Prepare_Done()
                Me.BeginInvoke(Sub()
                                   AppendLog($"API_Prepare_Done 返回: {done}")
                                   If done = 1 Then
                                       UpdateStatus("运行中 (已连接)")
                                   Else
                                       UpdateStatus("启动失败，查看日志")
                                   End If
                               End Sub)

                While _isRunning
                    Thread.Sleep(100)
                End While

                API.API_Exit_MainThread()
                API.API_shutdown()
                Me.BeginInvoke(Sub()
                                   AppendLog("工作线程正常退出")
                               End Sub)

            Catch ex As Exception
                Me.BeginInvoke(Sub()
                                   AppendLog($"后台线程异常: {ex.Message}")
                               End Sub)
            End Try
        End Sub

        ' ---- 加法回调（在 C 线程池中执行） ----
        Private Sub AddCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
            Dim hInput As DataHnd = New DataHnd With {.Handle = input}
            Dim hOutput As DataHnd = New DataHnd With {.Handle = output}

            Dim a As Integer, b As Integer
            If API.ReadInt32(hInput, a) AndAlso API.ReadInt32(hInput, b) Then
                Dim c As Integer = a + b
                API.WriteInt32(hOutput, c)
                Me.BeginInvoke(Sub()
                                   AppendLog($"收到加法请求: {a}+{b}={c}")
                               End Sub)
                API.API_Post_Status($"加法计算: {a}+{b}={c}")
            Else
                Me.BeginInvoke(Sub()
                                   AppendLog("加法参数读取失败")
                               End Sub)
            End If
        End Sub

        ' ---- 序列化反转回调 ----
        Private Sub InvSeriCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
            Dim hInput As DataHnd = New DataHnd With {.Handle = input}
            Dim hOutput As DataHnd = New DataHnd With {.Handle = output}

            Dim b As Byte = 0
            Dim w As UShort = 0
            Dim c As UInteger = 0
            Dim u64 As ULong = 0
            Dim s As String = ""
            Dim f As Single = 0.0F

            If API.ReadUInt8(hInput, b) AndAlso
               API.ReadUInt16(hInput, w) AndAlso
               API.ReadUInt32(hInput, c) AndAlso
               API.ReadUInt64(hInput, u64) AndAlso
               API.ReadStringNullTerminated(hInput, s) AndAlso
               API.ReadSingle(hInput, f) Then

                API.WriteSingle(hOutput, f)
                API.WriteStringNullTerminated(hOutput, s)
                API.WriteUInt64(hOutput, u64)
                API.WriteUInt32(hOutput, c)
                API.WriteUInt16(hOutput, w)
                API.WriteUInt8(hOutput, b)

                Me.BeginInvoke(Sub()
                                   AppendLog($"inv_seri 接收: [{b}, {w}, {c}, {u64}, ""{s}"", {f}] -> 反向响应")
                               End Sub)
                API.API_Post_Status($"inv_seri 处理完成")
            Else
                Me.BeginInvoke(Sub()
                                   AppendLog("inv_seri 读取基本类型失败")
                               End Sub)
            End If
        End Sub

        ' ---- 定时器刷新 ----
        Private Sub TimerRefresh_Tick(sender As Object, e As EventArgs)
            Dim count As Integer = API.API_Get_Status_Num()
            For i As Integer = 1 To count
                Dim msg As String = API.API_Get_Status()
                If Not String.IsNullOrEmpty(msg) Then
                    AppendLog("[库] " & msg)
                End If
            Next

            Dim mainThreadRunning As Boolean = API.API_Check_MainThread()
            Dim appExists As Boolean = API.API_Check_App("demo")

            Dim status As String = $"主线程: {If(mainThreadRunning, "运行", "停止")} | 应用 'demo': {If(appExists, "在线", "离线")}"
            UpdateStatus(status)
        End Sub

        ' ---- 辅助：更新状态 ----
        Private Sub UpdateStatus(text As String)
            If lblStatus.InvokeRequired Then
                lblStatus.BeginInvoke(Sub() lblStatus.Text = text)
            Else
                lblStatus.Text = text
            End If
        End Sub

        ' ---- 辅助：追加日志 ----
        Private Sub AppendLog(text As String)
            If lstLog.InvokeRequired Then
                lstLog.BeginInvoke(Sub()
                                       lstLog.Items.Add($"[{DateTime.Now:HH:mm:ss.fff}] {text}")
                                       lstLog.SelectedIndex = lstLog.Items.Count - 1
                                       lstLog.ClearSelected()
                                   End Sub)
            Else
                lstLog.Items.Add($"[{DateTime.Now:HH:mm:ss.fff}] {text}")
                lstLog.SelectedIndex = lstLog.Items.Count - 1
                lstLog.ClearSelected()
            End If
        End Sub

    End Class

End Namespace