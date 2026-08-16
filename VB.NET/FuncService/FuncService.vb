Imports ApiHubTool
Imports System.Runtime.InteropServices
Imports System.Text
Imports System.Threading

Namespace FuncService

    Module FuncService

        Private _exitFlag As Boolean = False

        ' ============================================================
        ' 1. 业务逻辑（纯函数）
        ' ============================================================

        Private Function Add(a As Integer, b As Integer) As Integer
            Return a + b
        End Function

        Private Function Subtract(a As Integer, b As Integer) As Integer
            Return a - b
        End Function

        Private Function Multiply(a As Integer, b As Integer) As Integer
            Return a * b
        End Function

        Private Function Divide(a As Integer, b As Integer) As Double
            Return If(b = 0, 0.0, CDbl(a) / b)
        End Function

        Private Function ToUpper(s As String) As String
            Return s.ToUpperInvariant()
        End Function

        Private Function ToLower(s As String) As String
            Return s.ToLowerInvariant()
        End Function

        Private Function Reverse(s As String) As String
            Dim arr = s.ToCharArray()
            Array.Reverse(arr)
            Return New String(arr)
        End Function

        Private Function GetTime() As String
            Return DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss")
        End Function

        Private Function GetRandom(min As Integer, max As Integer) As Integer
            Static rand As New Random()
            Return rand.Next(min, max + 1)
        End Function

        Private Function Echo(s As String) As String
            Return s
        End Function

        Private Function SumArray(arr As Integer()) As Integer
            Dim sum As Integer = 0
            For Each v In arr
                sum += v
            Next
            Return sum
        End Function

        Private Function ConcatStrings(arr As String()) As String
            Return String.Join(" ", arr)
        End Function

        ' ============================================================
        ' 2. 序列化辅助
        ' ============================================================

        Private Sub WriteInt(h As DataHnd, v As Integer)
            Dim b = BitConverter.GetBytes(v)
            API.API_WriteBuffer(h, b, 4)
        End Sub

        Private Sub WriteDouble(h As DataHnd, v As Double)
            Dim b = BitConverter.GetBytes(v)
            API.API_WriteBuffer(h, b, 8)
        End Sub

        Private Sub WriteString(h As DataHnd, s As String)
            Dim bytes = Encoding.UTF8.GetBytes(s)
            WriteInt(h, bytes.Length)
            API.API_WriteBuffer(h, bytes, bytes.Length)
        End Sub

        Private Sub WriteIntArray(h As DataHnd, arr As Integer())
            WriteInt(h, arr.Length)
            For Each v In arr
                WriteInt(h, v)
            Next
        End Sub

        Private Sub WriteStringArray(h As DataHnd, arr As String())
            WriteInt(h, arr.Length)
            For Each s In arr
                WriteString(h, s)
            Next
        End Sub

        Private Function ReadInt(h As DataHnd, ByRef v As Integer) As Boolean
            Dim b(3) As Byte
            If API.API_ReadBuffer(h, b, 4) <> 4 Then
                Return False
            End If
            v = BitConverter.ToInt32(b, 0)
            Return True
        End Function

        Private Function ReadDouble(h As DataHnd, ByRef v As Double) As Boolean
            Dim b(7) As Byte
            If API.API_ReadBuffer(h, b, 8) <> 8 Then
                Return False
            End If
            v = BitConverter.ToDouble(b, 0)
            Return True
        End Function

        Private Function ReadString(h As DataHnd, ByRef s As String) As Boolean
            Dim len As Integer
            If Not ReadInt(h, len) Then
                Return False
            End If
            Dim b(len - 1) As Byte
            If API.API_ReadBuffer(h, b, len) <> len Then
                Return False
            End If
            s = Encoding.UTF8.GetString(b)
            Return True
        End Function

        Private Function ReadIntArray(h As DataHnd, ByRef arr As Integer()) As Boolean
            Dim count As Integer
            If Not ReadInt(h, count) Then
                Return False
            End If
            ReDim arr(count - 1)
            For i As Integer = 0 To count - 1
                If Not ReadInt(h, arr(i)) Then
                    Return False
                End If
            Next
            Return True
        End Function

        Private Function ReadStringArray(h As DataHnd, ByRef arr As String()) As Boolean
            Dim count As Integer
            If Not ReadInt(h, count) Then
                Return False
            End If
            ReDim arr(count - 1)
            For i As Integer = 0 To count - 1
                If Not ReadString(h, arr(i)) Then
                    Return False
                End If
            Next
            Return True
        End Function

        ' ============================================================
        ' 3. API 回调
        ' ============================================================

        Private Sub AddCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
            Try
                Dim hIn = New DataHnd With {.Handle = input}
                Dim hOut = New DataHnd With {.Handle = output}
                Dim a As Integer, b As Integer
                If Not ReadInt(hIn, a) OrElse Not ReadInt(hIn, b) Then
                    Return
                End If
                WriteInt(hOut, Add(a, b))
            Catch ex As Exception
                Console.WriteLine($"[AddCallback] {ex.Message}")
            End Try
        End Sub

        Private Sub SubtractCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
            Try
                Dim hIn = New DataHnd With {.Handle = input}
                Dim hOut = New DataHnd With {.Handle = output}
                Dim a As Integer, b As Integer
                If Not ReadInt(hIn, a) OrElse Not ReadInt(hIn, b) Then
                    Return
                End If
                WriteInt(hOut, Subtract(a, b))
            Catch ex As Exception
                Console.WriteLine($"[SubtractCallback] {ex.Message}")
            End Try
        End Sub

        Private Sub MultiplyCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
            Try
                Dim hIn = New DataHnd With {.Handle = input}
                Dim hOut = New DataHnd With {.Handle = output}
                Dim a As Integer, b As Integer
                If Not ReadInt(hIn, a) OrElse Not ReadInt(hIn, b) Then
                    Return
                End If
                WriteInt(hOut, Multiply(a, b))
            Catch ex As Exception
                Console.WriteLine($"[MultiplyCallback] {ex.Message}")
            End Try
        End Sub

        Private Sub DivideCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
            Try
                Dim hIn = New DataHnd With {.Handle = input}
                Dim hOut = New DataHnd With {.Handle = output}
                Dim a As Integer, b As Integer
                If Not ReadInt(hIn, a) OrElse Not ReadInt(hIn, b) Then
                    Return
                End If
                WriteDouble(hOut, Divide(a, b))
            Catch ex As Exception
                Console.WriteLine($"[DivideCallback] {ex.Message}")
            End Try
        End Sub

        Private Sub ToUpperCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
            Try
                Dim hIn = New DataHnd With {.Handle = input}
                Dim hOut = New DataHnd With {.Handle = output}
                Dim s As String
                If Not ReadString(hIn, s) Then
                    Return
                End If
                WriteString(hOut, ToUpper(s))
            Catch ex As Exception
                Console.WriteLine($"[ToUpperCallback] {ex.Message}")
            End Try
        End Sub

        Private Sub ToLowerCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
            Try
                Dim hIn = New DataHnd With {.Handle = input}
                Dim hOut = New DataHnd With {.Handle = output}
                Dim s As String
                If Not ReadString(hIn, s) Then
                    Return
                End If
                WriteString(hOut, ToLower(s))
            Catch ex As Exception
                Console.WriteLine($"[ToLowerCallback] {ex.Message}")
            End Try
        End Sub

        Private Sub ReverseCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
            Try
                Dim hIn = New DataHnd With {.Handle = input}
                Dim hOut = New DataHnd With {.Handle = output}
                Dim s As String
                If Not ReadString(hIn, s) Then
                    Return
                End If
                WriteString(hOut, Reverse(s))
            Catch ex As Exception
                Console.WriteLine($"[ReverseCallback] {ex.Message}")
            End Try
        End Sub

        Private Sub GetTimeCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
            Try
                Dim hOut = New DataHnd With {.Handle = output}
                WriteString(hOut, GetTime())
            Catch ex As Exception
                Console.WriteLine($"[GetTimeCallback] {ex.Message}")
            End Try
        End Sub

        Private Sub GetRandomCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
            Try
                Dim hIn = New DataHnd With {.Handle = input}
                Dim hOut = New DataHnd With {.Handle = output}
                Dim min As Integer, max As Integer
                If Not ReadInt(hIn, min) OrElse Not ReadInt(hIn, max) Then
                    Return
                End If
                WriteInt(hOut, GetRandom(min, max))
            Catch ex As Exception
                Console.WriteLine($"[GetRandomCallback] {ex.Message}")
            End Try
        End Sub

        Private Sub EchoCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
            Try
                Dim hIn = New DataHnd With {.Handle = input}
                Dim hOut = New DataHnd With {.Handle = output}
                Dim s As String
                If Not ReadString(hIn, s) Then
                    Return
                End If
                WriteString(hOut, Echo(s))
            Catch ex As Exception
                Console.WriteLine($"[EchoCallback] {ex.Message}")
            End Try
        End Sub

        Private Sub SumArrayCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
            Try
                Dim hIn = New DataHnd With {.Handle = input}
                Dim hOut = New DataHnd With {.Handle = output}
                Dim arr As Integer()
                If Not ReadIntArray(hIn, arr) Then
                    Return
                End If
                WriteInt(hOut, SumArray(arr))
            Catch ex As Exception
                Console.WriteLine($"[SumArrayCallback] {ex.Message}")
            End Try
        End Sub

        Private Sub ConcatStringsCallback(trigger As IntPtr, input As IntPtr, output As IntPtr)
            Try
                Dim hIn = New DataHnd With {.Handle = input}
                Dim hOut = New DataHnd With {.Handle = output}
                Dim arr As String()
                If Not ReadStringArray(hIn, arr) Then
                    Return
                End If
                WriteString(hOut, ConcatStrings(arr))
            Catch ex As Exception
                Console.WriteLine($"[ConcatStringsCallback] {ex.Message}")
            End Try
        End Sub

        ' ============================================================
        ' 4. 主程序
        ' ============================================================

        Sub Main()
            Console.WriteLine("=== VB.NET FuncService (12 APIs) ===")

            Dim app = API.API_Create_APPHnd("FuncService", "功能服务（12个API）")
            If Not app.IsValid Then
                Console.WriteLine("创建应用失败")
                Return
            End If
            Console.WriteLine("应用已创建。")

            Dim addDel As APICallDelegate = AddressOf AddCallback
            Dim subDel As APICallDelegate = AddressOf SubtractCallback
            Dim mulDel As APICallDelegate = AddressOf MultiplyCallback
            Dim divDel As APICallDelegate = AddressOf DivideCallback
            Dim upperDel As APICallDelegate = AddressOf ToUpperCallback
            Dim lowerDel As APICallDelegate = AddressOf ToLowerCallback
            Dim revDel As APICallDelegate = AddressOf ReverseCallback
            Dim timeDel As APICallDelegate = AddressOf GetTimeCallback
            Dim randDel As APICallDelegate = AddressOf GetRandomCallback
            Dim echoDel As APICallDelegate = AddressOf EchoCallback
            Dim sumArrDel As APICallDelegate = AddressOf SumArrayCallback
            Dim concatDel As APICallDelegate = AddressOf ConcatStringsCallback

            GCHandle.Alloc(addDel) : GCHandle.Alloc(subDel) : GCHandle.Alloc(mulDel)
            GCHandle.Alloc(divDel) : GCHandle.Alloc(upperDel) : GCHandle.Alloc(lowerDel)
            GCHandle.Alloc(revDel) : GCHandle.Alloc(timeDel) : GCHandle.Alloc(randDel)
            GCHandle.Alloc(echoDel) : GCHandle.Alloc(sumArrDel) : GCHandle.Alloc(concatDel)

            API.API_Reg_Call(app, "add", "int32_t add(int32_t a, int32_t b)", IntPtr.Zero, addDel)
            API.API_Reg_Call(app, "subtract", "int32_t subtract(int32_t a, int32_t b)", IntPtr.Zero, subDel)
            API.API_Reg_Call(app, "multiply", "int32_t multiply(int32_t a, int32_t b)", IntPtr.Zero, mulDel)
            API.API_Reg_Call(app, "divide", "double divide(int32_t a, int32_t b)", IntPtr.Zero, divDel)
            API.API_Reg_Call(app, "to_upper", "char* to_upper(const char* str)", IntPtr.Zero, upperDel)
            API.API_Reg_Call(app, "to_lower", "char* to_lower(const char* str)", IntPtr.Zero, lowerDel)
            API.API_Reg_Call(app, "reverse", "char* reverse(const char* str)", IntPtr.Zero, revDel)
            API.API_Reg_Call(app, "get_time", "char* get_time()", IntPtr.Zero, timeDel)
            API.API_Reg_Call(app, "get_random", "int32_t get_random(int32_t min, int32_t max)", IntPtr.Zero, randDel)
            API.API_Reg_Call(app, "echo", "char* echo(const char* msg)", IntPtr.Zero, echoDel)
            API.API_Reg_Call(app, "sum_array", "int32_t sum_array(const int32_t* arr, int32_t count)", IntPtr.Zero, sumArrDel)
            API.API_Reg_Call(app, "concat_strings", "char* concat_strings(const char* arr[], int32_t count)", IntPtr.Zero, concatDel)

            Console.WriteLine("已注册 12 个 API（不含 SHA3）。")

            API.API_Reset_Prepare()
            API.API_Prepare_Service("ipc:func_service", "ipc:func_service")
            API.API_Prepare_Service("0.0.0.0", "127.0.0.1:9899")
            API.API_Prepare_Client("ipc:func_service", app)
            API.API_Prepare_Client("127.0.0.1:9899", app)

            Console.WriteLine("正在启动服务...")
            If API.API_Prepare_Done() <> 1 Then
                Console.WriteLine("启动失败。请查看控制台输出以获取详细错误信息。")
                API.API_Free_APPHnd(app)
                API.API_shutdown()
                Return
            End If

            Console.WriteLine("服务已启动。输入 'exit' 停止。")

            Dim inputThread As New Thread(Sub()
                                              While Not _exitFlag
                                                  Console.Write("FuncService> ")
                                                  Dim line = Console.ReadLine()
                                                  If line = "exit" Then
                                                      _exitFlag = True
                                                      Exit While
                                                  ElseIf line = "status" Then
                                                      Console.WriteLine("[Service] 运行中。")
                                                  End If
                                              End While
                                          End Sub)
            inputThread.Start()

            While Not _exitFlag
                Thread.Sleep(100)
            End While

            inputThread.Join()

            Console.WriteLine("正在关闭...")
            API.API_Exit_MainThread()
            API.API_Free_APPHnd(app)
            API.API_shutdown()
            Console.WriteLine("服务已停止。")
        End Sub

    End Module

End Namespace