Imports System.Runtime.InteropServices
Imports System.Text
Imports ApiHubTool
Imports ApiHubTool.Bindings

Module CrossNode

    ' ========== add 回调 ==========
    Private Sub AddCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
        Try
            Dim hIn = New DataHnd With {.Handle = input}
            Dim hOut = New DataHnd With {.Handle = output}

            Dim a As Integer, b As Integer
            If Not API.ReadInt32(hIn, a) OrElse Not API.ReadInt32(hIn, b) Then
                Return
            End If

            Dim c As Integer = a + b
            API.WriteInt32(hOut, c)

            Console.WriteLine($"[Node] add({a}, {b}) = {c}")
        Catch ex As Exception
            Console.WriteLine($"[Node] add 回调异常: {ex.Message}")
        End Try
    End Sub

    ' ========== inv_seri 回调（逆序回复） ==========
    Private Sub InvSeriCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
        Try
            Dim hIn = New DataHnd With {.Handle = input}
            Dim hOut = New DataHnd With {.Handle = output}

            Dim b As Byte
            Dim w As UShort
            Dim c As UInteger
            Dim u64 As ULong
            Dim s As String
            Dim f As Single

            If Not API.ReadUInt8(hIn, b) Then Return
            If Not API.ReadUInt16(hIn, w) Then Return
            If Not API.ReadUInt32(hIn, c) Then Return
            If Not API.ReadUInt64(hIn, u64) Then Return
            If Not API.ReadStringNullTerminated(hIn, s) Then Return
            If Not API.ReadSingle(hIn, f) Then Return

            ' 逆序写入
            API.WriteSingle(hOut, f)
            API.WriteStringNullTerminated(hOut, s)
            API.WriteUInt64(hOut, u64)
            API.WriteUInt32(hOut, c)
            API.WriteUInt16(hOut, w)
            API.WriteUInt8(hOut, b)

            Console.WriteLine($"[Node] inv_seri 接收: [{b}, {w}, {c}, {u64}, ""{s}"", {f:F2}] 回复: [{f:F2}, ""{s}"", {u64}, {c}, {w}, {b}]")
        Catch ex As Exception
            Console.WriteLine($"[Node] inv_seri 回调异常: {ex.Message}")
        End Try
    End Sub

    Sub Main()
        Console.WriteLine("=== VB.NET CrossNode (Worker Node) ===")

        ' 创建应用，应用名必须为 "demo"
        Dim app = API.API_Create_APPHnd("demo", "VB.NET cross node instance")
        If Not app.IsValid Then
            Console.WriteLine("创建应用失败")
            Return
        End If

        ' 注册 add 和 inv_seri
        Dim addDel As APICallDelegate = AddressOf AddCallback
        Dim invDel As APICallDelegate = AddressOf InvSeriCallback
        GCHandle.Alloc(addDel)
        GCHandle.Alloc(invDel)

        If API.API_Reg_Call(app, "add", "add(int a, int b)", IntPtr.Zero, addDel) <> 1 Then
            Console.WriteLine("注册 add 失败")
            API.API_Free_APPHnd(app)
            Return
        End If
        If API.API_Reg_Call(app, "inv_seri", "inv_seri()", IntPtr.Zero, invDel) <> 1 Then
            Console.WriteLine("注册 inv_seri 失败")
            API.API_Free_APPHnd(app)
            Return
        End If

        Console.WriteLine("已注册 'add' 和 'inv_seri'")

        ' 启用部署模式（不等待所有客户端就绪）
        API.API_SetOption("Wait_Connection_ReadyOk", "False")

        API.API_Reset_Prepare()
        API.API_Prepare_Client("ipc:cross", app)

        If API.API_Prepare_Done() <> 1 Then
            Console.WriteLine("连接服务注册中心失败。请查看控制台输出。")
            API.API_Free_APPHnd(app)
            API.API_shutdown()
            Return
        End If

        Console.WriteLine("节点已就绪，等待请求...")
        Console.WriteLine("按 Enter 退出...")
        Console.ReadLine()

        Console.WriteLine("正在关闭...")
        API.API_Exit_MainThread()
        API.API_Free_APPHnd(app)
        API.API_shutdown()
        Console.WriteLine("已关闭。")
    End Sub

End Module