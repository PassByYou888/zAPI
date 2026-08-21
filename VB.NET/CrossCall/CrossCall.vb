Imports System.Text
Imports System.Threading
Imports ApiHubTool
Imports ApiHubTool.Bindings

Module CrossCall

    Private _running As Boolean = True

    ' ========== 远程调用封装 ==========

    Private Function Add__(a As Integer, b As Integer) As Integer
        Dim param = API.API_Create_DataHnd("add")
        If Not param.IsValid Then Return 0

        API.WriteInt32(param, a)
        API.WriteInt32(param, b)

        Dim result = API.API_Call("demo", param, 15000)   ' 15秒超时
        API.API_Free_DataHnd(param)

        If Not result.IsValid OrElse API.API_GetSize(result) = 0 Then
            If result.IsValid Then API.API_Free_DataHnd(result)
            Return 0
        End If

        Dim ret As Integer
        If Not API.ReadInt32(result, ret) Then ret = 0
        API.API_Free_DataHnd(result)
        Return ret
    End Function

    Private Function InvSeri__() As String
        Dim param = API.API_Create_DataHnd("inv_seri")
        If Not param.IsValid Then Return "创建句柄失败"

        ' 写入 Pascal 约定的数据
        API.WriteUInt8(param, 200)
        API.WriteUInt16(param, &H10)
        API.WriteUInt32(param, &H2F)
        API.WriteUInt64(param, &H3F)
        API.WriteStringNullTerminated(param, "hello world")
        API.WriteSingle(param, 3.14F)

        Dim result = API.API_Call("demo", param, 15000)
        API.API_Free_DataHnd(param)

        If Not result.IsValid OrElse API.API_GetSize(result) = 0 Then
            If result.IsValid Then API.API_Free_DataHnd(result)
            Return "调用超时或失败"
        End If

        ' 逆序读取
        Dim f As Single
        Dim s As String
        Dim u64 As ULong
        Dim c As UInteger
        Dim w As UShort
        Dim b As Byte

        If Not API.ReadSingle(result, f) Then
            API.API_Free_DataHnd(result)
            Return "读取失败"
        End If
        If Not API.ReadStringNullTerminated(result, s) Then
            API.API_Free_DataHnd(result)
            Return "读取失败"
        End If
        If Not API.ReadUInt64(result, u64) Then Return "读取失败"
        If Not API.ReadUInt32(result, c) Then Return "读取失败"
        If Not API.ReadUInt16(result, w) Then Return "读取失败"
        If Not API.ReadUInt8(result, b) Then Return "读取失败"

        API.API_Free_DataHnd(result)

        Return $"接收数据序 [{b}, {w}, {c}, {u64}, ""{s}"", {f:F2}] = 发送数据序 [{f:F2}, ""{s}"", {u64}, {c}, {w}, {b}]"
    End Function

    ' ========== 工作线程 ==========

    Private Sub DoCompute()
        Dim startTime = DateTime.Now
        Dim duration = TimeSpan.FromSeconds(10)
        Dim rand As New Random()

        Console.WriteLine("仿真计算启动（可多开），持续 10 秒...")

        While _running AndAlso (DateTime.Now - startTime) < duration
            If rand.Next(2) = 0 Then
                Dim a = rand.Next(1, Integer.MaxValue)
                Dim b = rand.Next(1, Integer.MaxValue)
                Dim result = Add__(a, b)
                Dim remaining = (duration - (DateTime.Now - startTime)).TotalSeconds
                If result <> 0 Then
                    Console.WriteLine($"[Call] 计算 ""a({a})+b({b})"" = 计算结果 {result} ({remaining:F2}秒以后退出)")
                Else
                    Console.WriteLine($"[Call] add({a}, {b}) 返回 0（重试后仍失败） ({remaining:F2}秒退出)")
                End If
            Else
                Dim status = InvSeri__()
                Dim remaining = (duration - (DateTime.Now - startTime)).TotalSeconds
                Console.WriteLine($"[Call] {status} ({remaining:F2}秒退出)")
            End If
            Thread.Sleep(1)
        End While

        Console.WriteLine("工作线程结束")
    End Sub

    Sub Main()
        Console.WriteLine("=== VB.NET CrossCall (Concurrent Client) ===")

        API.API_Reset_Prepare()
        API.API_Prepare_Client("ipc:cross", AppHnd.Null)

        If API.API_Prepare_Done() <> 1 Then
            Console.WriteLine("连接服务注册中心失败。请查看控制台输出。")
            API.API_shutdown()
            Return
        End If

        Console.WriteLine("已连接到 ipc:cross")

        ' 启动工作线程
        Dim computeThread As New Thread(AddressOf DoCompute)
        computeThread.Start()

        ' 等待用户按 Enter 提前退出
        Console.WriteLine("按 Enter 提前终止...")
        Console.ReadLine()
        _running = False
        computeThread.Join()

        Console.WriteLine("正在关闭...")
        API.API_Exit_MainThread()
        API.API_shutdown()
        Console.WriteLine("已关闭。")
    End Sub

End Module