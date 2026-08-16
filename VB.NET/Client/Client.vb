Imports ApiHubTool

Module Client

    Sub Main()
        Console.WriteLine("=== VB.NET Client ===")

        API.API_Reset_Prepare()
        API.API_Prepare_Client("ipc:demo_service", AppHnd.Null)

        If API.API_Prepare_Done() <> 1 Then
            Console.WriteLine("连接失败")
            API.API_shutdown()
            Return
        End If

        Dim param = API.API_Create_DataHnd("add")
        Dim payload(7) As Byte
        BitConverter.GetBytes(10).CopyTo(payload, 0)
        BitConverter.GetBytes(20).CopyTo(payload, 4)
        API.API_WriteBuffer(param, payload, 8)

        Dim result = API.API_Call("ServiceApp", param, 3000)
        API.API_Free_DataHnd(param)

        If result.IsValid AndAlso API.API_GetSize(result) >= 4 Then
            Dim sum = BitConverter.ToInt32(API.ReadAllBytes(result), 0)
            Console.WriteLine($"10 + 20 = {sum}")
            API.API_Free_DataHnd(result)
        Else
            Console.WriteLine("调用超时或失败")
        End If

        API.API_Exit_MainThread()
        API.API_shutdown()
    End Sub

End Module