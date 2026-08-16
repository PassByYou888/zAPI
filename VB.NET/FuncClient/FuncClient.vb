Imports ApiHubTool
Imports System.Text
Imports System.Threading
Imports System.Diagnostics
Imports System.Runtime.InteropServices

Namespace FuncClient

    Module FuncClient

        Private Const TOTAL_CALLS As Integer = 100   ' 每个 API 调用次数
        Private Const TIMEOUT_MS As Integer = 5000

        ' ============================================================
        ' 序列化辅助
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

        ' ============================================================
        ' 远程调用封装
        ' ============================================================

        Private Function DoCallInt(apiName As String, param As DataHnd, ByRef result As Integer) As Boolean
            Dim hResult = API.API_Call("FuncService", param, TIMEOUT_MS)
            API.API_Free_DataHnd(param)
            If Not hResult.IsValid OrElse API.API_GetSize(hResult) = 0 Then
                If hResult.IsValid Then
                    API.API_Free_DataHnd(hResult)
                End If
                Return False
            End If
            Dim ok = ReadInt(hResult, result)
            API.API_Free_DataHnd(hResult)
            Return ok
        End Function

        Private Function DoCallDouble(apiName As String, param As DataHnd, ByRef result As Double) As Boolean
            Dim hResult = API.API_Call("FuncService", param, TIMEOUT_MS)
            API.API_Free_DataHnd(param)
            If Not hResult.IsValid OrElse API.API_GetSize(hResult) = 0 Then
                If hResult.IsValid Then
                    API.API_Free_DataHnd(hResult)
                End If
                Return False
            End If
            Dim ok = ReadDouble(hResult, result)
            API.API_Free_DataHnd(hResult)
            Return ok
        End Function

        Private Function DoCallString(apiName As String, param As DataHnd, ByRef result As String) As Boolean
            Dim hResult = API.API_Call("FuncService", param, TIMEOUT_MS)
            API.API_Free_DataHnd(param)
            If Not hResult.IsValid OrElse API.API_GetSize(hResult) = 0 Then
                If hResult.IsValid Then
                    API.API_Free_DataHnd(hResult)
                End If
                Return False
            End If
            Dim ok = ReadString(hResult, result)
            API.API_Free_DataHnd(hResult)
            Return ok
        End Function

        ' ============================================================
        ' 12 个包装函数（不含 SHA3）
        ' ============================================================

        Public Function FuncAdd(a As Integer, b As Integer) As Integer
            Dim h = API.API_Create_DataHnd("add")
            WriteInt(h, a) : WriteInt(h, b)
            Dim result As Integer
            DoCallInt("add", h, result)
            Return result
        End Function

        Public Function FuncSubtract(a As Integer, b As Integer) As Integer
            Dim h = API.API_Create_DataHnd("subtract")
            WriteInt(h, a) : WriteInt(h, b)
            Dim result As Integer
            DoCallInt("subtract", h, result)
            Return result
        End Function

        Public Function FuncMultiply(a As Integer, b As Integer) As Integer
            Dim h = API.API_Create_DataHnd("multiply")
            WriteInt(h, a) : WriteInt(h, b)
            Dim result As Integer
            DoCallInt("multiply", h, result)
            Return result
        End Function

        Public Function FuncDivide(a As Integer, b As Integer) As Double
            Dim h = API.API_Create_DataHnd("divide")
            WriteInt(h, a) : WriteInt(h, b)
            Dim result As Double
            DoCallDouble("divide", h, result)
            Return result
        End Function

        Public Function FuncToUpper(s As String) As String
            Dim h = API.API_Create_DataHnd("to_upper")
            WriteString(h, s)
            Dim result As String
            DoCallString("to_upper", h, result)
            Return result
        End Function

        Public Function FuncToLower(s As String) As String
            Dim h = API.API_Create_DataHnd("to_lower")
            WriteString(h, s)
            Dim result As String
            DoCallString("to_lower", h, result)
            Return result
        End Function

        Public Function FuncReverse(s As String) As String
            Dim h = API.API_Create_DataHnd("reverse")
            WriteString(h, s)
            Dim result As String
            DoCallString("reverse", h, result)
            Return result
        End Function

        Public Function FuncGetTime() As String
            Dim h = API.API_Create_DataHnd("get_time")
            Dim result As String
            DoCallString("get_time", h, result)
            Return result
        End Function

        Public Function FuncGetRandom(min As Integer, max As Integer) As Integer
            Dim h = API.API_Create_DataHnd("get_random")
            WriteInt(h, min) : WriteInt(h, max)
            Dim result As Integer
            DoCallInt("get_random", h, result)
            Return result
        End Function

        Public Function FuncEcho(s As String) As String
            Dim h = API.API_Create_DataHnd("echo")
            WriteString(h, s)
            Dim result As String
            DoCallString("echo", h, result)
            Return result
        End Function

        Public Function FuncSumArray(arr As Integer()) As Integer
            Dim h = API.API_Create_DataHnd("sum_array")
            WriteIntArray(h, arr)
            Dim result As Integer
            DoCallInt("sum_array", h, result)
            Return result
        End Function

        Public Function FuncConcatStrings(arr As String()) As String
            Dim h = API.API_Create_DataHnd("concat_strings")
            WriteStringArray(h, arr)
            Dim result As String
            DoCallString("concat_strings", h, result)
            Return result
        End Function

        ' ============================================================
        ' 压测框架
        ' ============================================================

        Private Structure Stats
            Public Avg As Double
            Public Min As Double
            Public Max As Double
            Public Median As Double
            Public StdDev As Double
            Public Count As Integer
            Public Qps As Double
            Public TotalSec As Double
        End Structure

        Private Function ComputeStats(times As List(Of Double), elapsedSec As Double) As Stats
            If times.Count = 0 Then Return New Stats()
            times.Sort()
            Dim sum = times.Sum()
            Dim mean = sum / times.Count
            Dim sqSum = times.Select(Function(t) (t - mean) ^ 2).Sum()
            Dim stddev = Math.Sqrt(sqSum / times.Count)
            Dim median = times(times.Count \ 2)
            Dim qps = times.Count / elapsedSec
            Return New Stats With {
                .Avg = mean / 1000.0,
                .Min = times(0) / 1000.0,
                .Max = times(times.Count - 1) / 1000.0,
                .Median = median / 1000.0,
                .StdDev = stddev / 1000.0,
                .Count = times.Count,
                .Qps = qps,
                .TotalSec = elapsedSec
            }
        End Function

        Private Function RunBenchmark(name As String, totalCalls As Integer, action As Action) As Stats
            Dim allTimes As New List(Of Double)()
            Dim lockObj As New Object()
            Dim threads(totalCalls - 1) As Thread
            Dim startTime = Stopwatch.StartNew()

            For i As Integer = 0 To totalCalls - 1
                threads(i) = New Thread(Sub()
                                            Dim sw = Stopwatch.StartNew()
                                            action()
                                            sw.Stop()
                                            SyncLock lockObj
                                                allTimes.Add(sw.Elapsed.TotalMicroseconds)
                                            End SyncLock
                                        End Sub)
                threads(i).Start()
            Next

            For Each t In threads
                t.Join()
            Next

            startTime.Stop()
            Dim elapsedSec = startTime.Elapsed.TotalSeconds
            Return ComputeStats(allTimes, elapsedSec)
        End Function

        Private Sub PrintStats(name As String, s As Stats)
            Console.WriteLine($"{name,-18} {s.Avg,10:F3} {s.Min,10:F3} {s.Max,10:F3} {s.Median,10:F3} {s.StdDev,10:F3} {s.Count,10} {s.Qps,12:F2} {s.TotalSec,10:F3}")
        End Sub

        ' ============================================================
        ' 主程序
        ' ============================================================

        Sub Main()
            Console.WriteLine("=== VB.NET FuncClient 真正并发压测 ===")
            Console.WriteLine($"线程数/API: {TOTAL_CALLS}, 总调用数/API: {TOTAL_CALLS}")
            Console.WriteLine($"延迟单位：毫秒 (ms), QPS = 调用数/秒")
            Console.WriteLine()

            API.API_Reset_Prepare()
            API.API_Prepare_Client("ipc:func_service", AppHnd.Null)
            API.API_Prepare_Client("127.0.0.1:9899", AppHnd.Null)

            If API.API_Prepare_Done() <> 1 Then
                Console.WriteLine("连接失败。请查看控制台输出以获取详细错误信息。")
                API.API_shutdown()
                Return
            End If
            Console.WriteLine("已连接到 FuncService。")
            Console.WriteLine()

            FuncAdd(1, 2)
            Console.WriteLine("预热完成。")
            Console.WriteLine()

            Console.WriteLine($"{"API",-18} {"Avg(ms)",10} {"Min(ms)",10} {"Max(ms)",10} {"Median(ms)",10} {"StdDev(ms)",10} {"Calls",10} {"QPS",12} {"Total(s)",10}")
            Console.WriteLine(New String("-"c, 110))

            Dim intArr As Integer() = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
            Dim strArr As String() = {"Hello", "world", "from", "client", "test"}

            Dim s As Stats

            s = RunBenchmark("add", TOTAL_CALLS, Sub() FuncAdd(10, 20))
            PrintStats("add", s)

            s = RunBenchmark("subtract", TOTAL_CALLS, Sub() FuncSubtract(50, 30))
            PrintStats("subtract", s)

            s = RunBenchmark("multiply", TOTAL_CALLS, Sub() FuncMultiply(6, 7))
            PrintStats("multiply", s)

            s = RunBenchmark("divide", TOTAL_CALLS, Sub() FuncDivide(10, 3))
            PrintStats("divide", s)

            s = RunBenchmark("to_upper", TOTAL_CALLS, Sub() FuncToUpper("hello"))
            PrintStats("to_upper", s)

            s = RunBenchmark("to_lower", TOTAL_CALLS, Sub() FuncToLower("WORLD"))
            PrintStats("to_lower", s)

            s = RunBenchmark("reverse", TOTAL_CALLS, Sub() FuncReverse("abcdef"))
            PrintStats("reverse", s)

            s = RunBenchmark("get_time", TOTAL_CALLS, Sub() FuncGetTime())
            PrintStats("get_time", s)

            s = RunBenchmark("get_random", TOTAL_CALLS, Sub() FuncGetRandom(1, 100))
            PrintStats("get_random", s)

            s = RunBenchmark("echo", TOTAL_CALLS, Sub() FuncEcho("Hello from client"))
            PrintStats("echo", s)

            s = RunBenchmark("sum_array", TOTAL_CALLS, Sub() FuncSumArray(intArr))
            PrintStats("sum_array", s)

            s = RunBenchmark("concat_strings", TOTAL_CALLS, Sub() FuncConcatStrings(strArr))
            PrintStats("concat_strings", s)

            Console.WriteLine()
            Console.WriteLine("所有压测完成。正在关闭...")
            API.API_Exit_MainThread()
            API.API_shutdown()
        End Sub

    End Module

End Namespace