Imports ApiHubTool
Imports ApiHubTool.Bindings

Module CrossService

    Sub Main()
        Console.WriteLine("=== VB.NET CrossService (Service Registry) ===")

        API.API_Reset_Prepare()
        API.API_Prepare_Service("ipc:cross", "ipc:cross")

        If API.API_Prepare_Done() <> 1 Then
            Console.WriteLine("服务启动失败。请查看控制台输出。")
            API.API_shutdown()
            Return
        End If

        Console.WriteLine("服务注册中心已启动 (ipc:cross)")
        Console.WriteLine("按 Enter 退出...")
        Console.ReadLine()

        Console.WriteLine("正在关闭...")
        API.API_Exit_MainThread()
        API.API_shutdown()
        Console.WriteLine("已关闭。")
    End Sub

End Module