Imports System.Runtime.InteropServices
Imports ApiHubTool

Module HelloWorld

    Private Sub AddCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
        Dim hInput = New DataHnd With {.Handle = input}
        Dim hOutput = New DataHnd With {.Handle = output}
        Dim buf = API.ReadAllBytes(hInput)
        If buf.Length >= 8 Then
            Dim a = BitConverter.ToInt32(buf, 0)
            Dim b = BitConverter.ToInt32(buf, 4)
            Dim sum = a + b
            API.API_WriteBuffer(hOutput, BitConverter.GetBytes(sum), 4)
        End If
    End Sub

    Sub Main()
        Console.WriteLine("=== VB.NET HelloWorld ===")

        Dim app = API.API_Create_APPHnd("HelloApp", "My first VB.NET app")
        If Not app.IsValid Then
            Console.WriteLine("创建应用失败")
            Return
        End If

        Dim addDel As APICallDelegate = AddressOf AddCallback
        GCHandle.Alloc(addDel)

        If API.API_Reg_Call(app, "add", "Addition", IntPtr.Zero, addDel) <> 1 Then
            Console.WriteLine("注册失败")
            API.API_Free_APPHnd(app)
            Return
        End If

        Dim param = API.API_Create_DataHnd("add")
        Dim payload(7) As Byte
        BitConverter.GetBytes(5).CopyTo(payload, 0)
        BitConverter.GetBytes(7).CopyTo(payload, 4)
        API.API_WriteBuffer(param, payload, 8)

        Dim result = API.API_Local_APP_Call(app, param)
        API.API_Free_DataHnd(param)

        If result.IsValid AndAlso API.API_GetSize(result) >= 4 Then
            Dim sum = BitConverter.ToInt32(API.ReadAllBytes(result), 0)
            Console.WriteLine($"5 + 7 = {sum}")
            API.API_Free_DataHnd(result)
        Else
            Console.WriteLine("调用失败")
        End If

        API.API_Free_APPHnd(app)
        API.API_shutdown()
        Console.WriteLine("完成。按任意键退出...")
        Console.ReadKey()
    End Sub

End Module