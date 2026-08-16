Imports System.Runtime.InteropServices
Imports System.Threading
Imports ApiHubTool

Module Service

    Private _exitFlag As Boolean = False

    Private Sub AddCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
        Dim hIn = New DataHnd With {.Handle = input}
        Dim hOut = New DataHnd With {.Handle = output}
        Dim buf = API.ReadAllBytes(hIn)
        If buf.Length >= 8 Then
            Dim a = BitConverter.ToInt32(buf, 0)
            Dim b = BitConverter.ToInt32(buf, 4)
            Dim sum = a + b
            API.API_WriteBuffer(hOut, BitConverter.GetBytes(sum), 4)
            Console.WriteLine($"[Service] add({a},{b}) = {sum}")
        End If
    End Sub

    Sub Main()
        Console.WriteLine("=== VB.NET Service ===")

        Dim app = API.API_Create_APPHnd("ServiceApp", "Demo Service")
        If Not app.IsValid Then
            Console.WriteLine("创建应用失败")
            Return
        End If

        Dim addDel As APICallDelegate = AddressOf AddCallback
        GCHandle.Alloc(addDel)
        API.API_Reg_Call(app, "add", "Addition", IntPtr.Zero, addDel)

        API.API_Reset_Prepare()
        API.API_Prepare_Service("ipc:demo_service", "ipc:demo_service")
        API.API_Prepare_Client("ipc:demo_service", app)

        If API.API_Prepare_Done() <> 1 Then
            Console.WriteLine("启动失败")
            API.API_Free_APPHnd(app)
            API.API_shutdown()
            Return
        End If

        Console.WriteLine("服务已启动，按 Enter 退出...")
        Console.ReadLine()

        API.API_Exit_MainThread()
        API.API_Free_APPHnd(app)
        API.API_shutdown()
    End Sub

End Module