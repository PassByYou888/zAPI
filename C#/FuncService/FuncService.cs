/*
 * FuncService.cs - 功能丰富的服务端，注册 13 个 API，支持 IPC 和 TCP。
 * 
 * 包含：加、减、乘、除、转大写、转小写、反转、获取时间、随机数、回显、
 * 数组求和、数组连接、SHA3-256 哈希（纯 C# 实现，跨平台）。
 * 
 * 本服务同时作为客户端连接自身，以实现本地环回。
 * 控制台输入 'exit' 可退出。
 */

using System;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;
using API_HubTool.Bindings;
using static API_HubTool.Bindings.API;

namespace FuncService
{
    class FuncService
    {
        private static volatile bool _exitFlag = false;

        // ============================================================
        // 0. 自包含 SHA3-256 实现（基于 Keccak-f[1600]）
        //    完全托管代码，无系统依赖。
        // ============================================================

        private static class Sha3
        {
            private const int ROUNDS = 24;
            private static readonly ulong[] ROUND_CONSTANTS = {
                0x0000000000000001UL, 0x0000000000008082UL, 0x800000000000808aUL,
                0x8000000080008000UL, 0x000000000000808bUL, 0x0000000080000001UL,
                0x8000000080008081UL, 0x8000000000008009UL, 0x000000000000008aUL,
                0x0000000000000088UL, 0x0000000080008009UL, 0x000000008000000aUL,
                0x000000008000808bUL, 0x800000000000008bUL, 0x8000000000008089UL,
                0x8000000000008003UL, 0x8000000000008002UL, 0x8000000000000080UL,
                0x000000000000800aUL, 0x800000008000000aUL, 0x8000000080008081UL,
                0x8000000000008080UL, 0x0000000080000001UL, 0x8000000080008008UL
            };
            private static readonly int[] RHO_OFFSETS = {
                0, 1, 62, 28, 27, 36, 44, 6, 55, 20,
                3, 10, 43, 25, 39, 41, 45, 15, 21, 8,
                18, 2, 61, 56, 14
            };

            private static ulong Rotl64(ulong x, int shift) => (x << shift) | (x >> (64 - shift));

            private static void KeccakF1600(ulong[] state)
            {
                for (int round = 0; round < ROUNDS; round++)
                {
                    // Theta
                    ulong[] C = new ulong[5];
                    ulong[] D = new ulong[5];
                    for (int x = 0; x < 5; x++)
                        C[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20];
                    for (int x = 0; x < 5; x++)
                        D[x] = C[(x + 4) % 5] ^ Rotl64(C[(x + 1) % 5], 1);
                    for (int x = 0; x < 5; x++)
                        for (int y = 0; y < 5; y++)
                            state[x + 5 * y] ^= D[x];

                    // Rho and Pi
                    ulong current = state[1];
                    for (int t = 0; t < 24; t++)
                    {
                        int x, y;
                        int idx = t + 1;
                        // Precomputed mapping for idx 1..24 to (x,y)
                        if (idx == 1) { x = 0; y = 1; }
                        else if (idx == 2) { x = 1; y = 0; }
                        else if (idx == 3) { x = 1; y = 1; }
                        else if (idx == 4) { x = 0; y = 2; }
                        else if (idx == 5) { x = 2; y = 0; }
                        else if (idx == 6) { x = 2; y = 1; }
                        else if (idx == 7) { x = 1; y = 2; }
                        else if (idx == 8) { x = 2; y = 2; }
                        else if (idx == 9) { x = 0; y = 3; }
                        else if (idx == 10) { x = 3; y = 0; }
                        else if (idx == 11) { x = 3; y = 1; }
                        else if (idx == 12) { x = 1; y = 3; }
                        else if (idx == 13) { x = 3; y = 2; }
                        else if (idx == 14) { x = 2; y = 3; }
                        else if (idx == 15) { x = 3; y = 3; }
                        else if (idx == 16) { x = 0; y = 4; }
                        else if (idx == 17) { x = 4; y = 0; }
                        else if (idx == 18) { x = 4; y = 1; }
                        else if (idx == 19) { x = 1; y = 4; }
                        else if (idx == 20) { x = 4; y = 2; }
                        else if (idx == 21) { x = 2; y = 4; }
                        else if (idx == 22) { x = 4; y = 3; }
                        else if (idx == 23) { x = 3; y = 4; }
                        else if (idx == 24) { x = 4; y = 4; }
                        else { x = 0; y = 0; }

                        ulong temp = state[x + 5 * y];
                        state[x + 5 * y] = Rotl64(current, RHO_OFFSETS[t]);
                        current = temp;
                    }

                    // Chi
                    for (int y = 0; y < 5; y++)
                    {
                        ulong[] temp = new ulong[5];
                        for (int x = 0; x < 5; x++)
                            temp[x] = state[x + 5 * y];
                        for (int x = 0; x < 5; x++)
                            state[x + 5 * y] = temp[x] ^ ((~temp[(x + 1) % 5]) & temp[(x + 2) % 5]);
                    }

                    // Iota
                    state[0] ^= ROUND_CONSTANTS[round];
                }
            }

            public static byte[] Hash(byte[] input)
            {
                ulong[] state = new ulong[25];
                int rate = 136; // 1600 - 2*256 = 1088 bits = 136 bytes

                // Absorb
                int offset = 0;
                int len = input.Length;
                int pos = 0;
                while (len > 0)
                {
                    int chunk = Math.Min(len, rate - offset);
                    for (int i = 0; i < chunk; i++)
                    {
                        int idx = (offset + i) >> 3;
                        int shift = 8 * ((offset + i) & 7);
                        state[idx] ^= (ulong)input[pos + i] << shift;
                    }
                    offset += chunk;
                    pos += chunk;
                    len -= chunk;
                    if (offset == rate)
                    {
                        KeccakF1600(state);
                        offset = 0;
                    }
                }

                // Padding
                state[offset >> 3] ^= 0x06UL << (8 * (offset & 7));
                state[(rate - 1) >> 3] ^= 0x80UL << (8 * ((rate - 1) & 7));
                KeccakF1600(state);

                // Squeeze (truncate to 32 bytes)
                byte[] hash = new byte[32];
                for (int i = 0; i < 32; i++)
                {
                    hash[i] = (byte)(state[i >> 3] >> (8 * (i & 7)));
                }
                return hash;
            }
        }

        // ============================================================
        // 1. 业务逻辑（纯函数，无序列化）
        // ============================================================

        private static int Add(int a, int b) => a + b;
        private static int Subtract(int a, int b) => a - b;
        private static int Multiply(int a, int b) => a * b;
        private static double Divide(int a, int b) => b == 0 ? 0.0 : (double)a / b;
        private static string ToUpper(string s) => s.ToUpperInvariant();
        private static string ToLower(string s) => s.ToLowerInvariant();
        private static string Reverse(string s)
        {
            char[] arr = s.ToCharArray();
            Array.Reverse(arr);
            return new string(arr);
        }
        private static string GetTime() => DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
        private static int GetRandom(int min, int max)
        {
            var rand = new Random();
            return rand.Next(min, max + 1);
        }
        private static string Echo(string s) => s;
        private static int SumArray(int[] arr)
        {
            int sum = 0;
            foreach (int v in arr) sum += v;
            return sum;
        }
        private static string ConcatStrings(string[] arr) => string.Join(" ", arr);

        // SHA3-256 使用自实现
        private static string Sha3Hex(string input)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(input);
            byte[] hash = Sha3.Hash(bytes);
            return BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
        }

        // ============================================================
        // 2. API 回调函数（从 DataHnd 读写），均包含异常保护
        // ============================================================

        // 辅助序列化（无变化）
        private static void WriteInt(DataHnd h, int v)
        {
            byte[] b = BitConverter.GetBytes(v);
            API_WriteBuffer(h, b, 4);
        }
        private static void WriteDouble(DataHnd h, double v)
        {
            byte[] b = BitConverter.GetBytes(v);
            API_WriteBuffer(h, b, 8);
        }
        private static void WriteString(DataHnd h, string s)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(s);
            WriteInt(h, bytes.Length);
            API_WriteBuffer(h, bytes, bytes.Length);
        }
        private static void WriteIntArray(DataHnd h, int[] arr)
        {
            WriteInt(h, arr.Length);
            foreach (int v in arr) WriteInt(h, v);
        }
        private static void WriteStringArray(DataHnd h, string[] arr)
        {
            WriteInt(h, arr.Length);
            foreach (string s in arr) WriteString(h, s);
        }

        private static bool ReadInt(DataHnd h, out int v)
        {
            byte[] buf = new byte[4];
            if (API_ReadBuffer(h, buf, 4) != 4) { v = 0; return false; }
            v = BitConverter.ToInt32(buf, 0);
            return true;
        }
        private static bool ReadDouble(DataHnd h, out double v)
        {
            byte[] buf = new byte[8];
            if (API_ReadBuffer(h, buf, 8) != 8) { v = 0; return false; }
            v = BitConverter.ToDouble(buf, 0);
            return true;
        }
        private static bool ReadString(DataHnd h, out string s)
        {
            if (!ReadInt(h, out int len)) { s = null; return false; }
            byte[] buf = new byte[len];
            if (API_ReadBuffer(h, buf, len) != len) { s = null; return false; }
            s = Encoding.UTF8.GetString(buf);
            return true;
        }
        private static bool ReadIntArray(DataHnd h, out int[] arr)
        {
            if (!ReadInt(h, out int count)) { arr = null; return false; }
            arr = new int[count];
            for (int i = 0; i < count; i++)
            {
                if (!ReadInt(h, out arr[i])) { arr = null; return false; }
            }
            return true;
        }
        private static bool ReadStringArray(DataHnd h, out string[] arr)
        {
            if (!ReadInt(h, out int count)) { arr = null; return false; }
            arr = new string[count];
            for (int i = 0; i < count; i++)
            {
                if (!ReadString(h, out arr[i])) { arr = null; return false; }
            }
            return true;
        }

        // ---- 各 API 回调（加上 try-catch） ----
        private static void AddCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            try
            {
                DataHnd hIn = new DataHnd { Handle = input };
                DataHnd hOut = new DataHnd { Handle = output };
                if (!ReadInt(hIn, out int a) || !ReadInt(hIn, out int b)) return;
                int result = Add(a, b);
                WriteInt(hOut, result);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[AddCallback 异常] {ex.Message}");
            }
        }

        private static void SubtractCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            try
            {
                DataHnd hIn = new DataHnd { Handle = input };
                DataHnd hOut = new DataHnd { Handle = output };
                if (!ReadInt(hIn, out int a) || !ReadInt(hIn, out int b)) return;
                int result = Subtract(a, b);
                WriteInt(hOut, result);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SubtractCallback 异常] {ex.Message}");
            }
        }

        private static void MultiplyCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            try
            {
                DataHnd hIn = new DataHnd { Handle = input };
                DataHnd hOut = new DataHnd { Handle = output };
                if (!ReadInt(hIn, out int a) || !ReadInt(hIn, out int b)) return;
                int result = Multiply(a, b);
                WriteInt(hOut, result);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[MultiplyCallback 异常] {ex.Message}");
            }
        }

        private static void DivideCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            try
            {
                DataHnd hIn = new DataHnd { Handle = input };
                DataHnd hOut = new DataHnd { Handle = output };
                if (!ReadInt(hIn, out int a) || !ReadInt(hIn, out int b)) return;
                double result = Divide(a, b);
                WriteDouble(hOut, result);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[DivideCallback 异常] {ex.Message}");
            }
        }

        private static void ToUpperCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            try
            {
                DataHnd hIn = new DataHnd { Handle = input };
                DataHnd hOut = new DataHnd { Handle = output };
                if (!ReadString(hIn, out string s)) return;
                string result = ToUpper(s);
                WriteString(hOut, result);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[ToUpperCallback 异常] {ex.Message}");
            }
        }

        private static void ToLowerCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            try
            {
                DataHnd hIn = new DataHnd { Handle = input };
                DataHnd hOut = new DataHnd { Handle = output };
                if (!ReadString(hIn, out string s)) return;
                string result = ToLower(s);
                WriteString(hOut, result);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[ToLowerCallback 异常] {ex.Message}");
            }
        }

        private static void ReverseCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            try
            {
                DataHnd hIn = new DataHnd { Handle = input };
                DataHnd hOut = new DataHnd { Handle = output };
                if (!ReadString(hIn, out string s)) return;
                string result = Reverse(s);
                WriteString(hOut, result);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[ReverseCallback 异常] {ex.Message}");
            }
        }

        private static void GetTimeCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            try
            {
                DataHnd hOut = new DataHnd { Handle = output };
                string result = GetTime();
                WriteString(hOut, result);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[GetTimeCallback 异常] {ex.Message}");
            }
        }

        private static void GetRandomCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            try
            {
                DataHnd hIn = new DataHnd { Handle = input };
                DataHnd hOut = new DataHnd { Handle = output };
                if (!ReadInt(hIn, out int min) || !ReadInt(hIn, out int max)) return;
                int result = GetRandom(min, max);
                WriteInt(hOut, result);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[GetRandomCallback 异常] {ex.Message}");
            }
        }

        private static void EchoCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            try
            {
                DataHnd hIn = new DataHnd { Handle = input };
                DataHnd hOut = new DataHnd { Handle = output };
                if (!ReadString(hIn, out string s)) return;
                string result = Echo(s);
                WriteString(hOut, result);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[EchoCallback 异常] {ex.Message}");
            }
        }

        private static void SumArrayCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            try
            {
                DataHnd hIn = new DataHnd { Handle = input };
                DataHnd hOut = new DataHnd { Handle = output };
                if (!ReadIntArray(hIn, out int[] arr)) return;
                int result = SumArray(arr);
                WriteInt(hOut, result);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SumArrayCallback 异常] {ex.Message}");
            }
        }

        private static void ConcatStringsCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            try
            {
                DataHnd hIn = new DataHnd { Handle = input };
                DataHnd hOut = new DataHnd { Handle = output };
                if (!ReadStringArray(hIn, out string[] arr)) return;
                string result = ConcatStrings(arr);
                WriteString(hOut, result);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[ConcatStringsCallback 异常] {ex.Message}");
            }
        }

        // SHA3 回调
        private static void Sha3Callback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            try
            {
                DataHnd hIn = new DataHnd { Handle = input };
                DataHnd hOut = new DataHnd { Handle = output };
                if (!ReadString(hIn, out string s)) return;
                string result = Sha3Hex(s);
                WriteString(hOut, result);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Sha3Callback 异常] {ex.Message}");
                DataHnd hOut = new DataHnd { Handle = output };
                WriteString(hOut, ""); // 写入空字符串避免客户端永久等待
            }
        }

        // ============================================================
        // 3. 主程序
        // ============================================================
        static void Main()
        {
            Console.WriteLine("=== FuncService (C#) ===");

            // 创建应用句柄
            AppHnd app = API_Create_APPHnd("FuncService", "功能服务（13个API）");
            if (!app.IsValid)
            {
                Console.WriteLine("创建应用失败。");
                return;
            }
            Console.WriteLine("应用已创建。");

            // 注册 13 个 API
            APICallDelegate addDel = AddCallback;
            APICallDelegate subDel = SubtractCallback;
            APICallDelegate mulDel = MultiplyCallback;
            APICallDelegate divDel = DivideCallback;
            APICallDelegate upperDel = ToUpperCallback;
            APICallDelegate lowerDel = ToLowerCallback;
            APICallDelegate revDel = ReverseCallback;
            APICallDelegate timeDel = GetTimeCallback;
            APICallDelegate randDel = GetRandomCallback;
            APICallDelegate echoDel = EchoCallback;
            APICallDelegate sumArrDel = SumArrayCallback;
            APICallDelegate concatDel = ConcatStringsCallback;
            APICallDelegate sha3Del = Sha3Callback;

            GCHandle.Alloc(addDel); GCHandle.Alloc(subDel); GCHandle.Alloc(mulDel);
            GCHandle.Alloc(divDel); GCHandle.Alloc(upperDel); GCHandle.Alloc(lowerDel);
            GCHandle.Alloc(revDel); GCHandle.Alloc(timeDel); GCHandle.Alloc(randDel);
            GCHandle.Alloc(echoDel); GCHandle.Alloc(sumArrDel); GCHandle.Alloc(concatDel);
            GCHandle.Alloc(sha3Del);

            API_Reg_Call(app, "add", "int32_t add(int32_t a, int32_t b) - Add two integers", IntPtr.Zero, addDel);
            API_Reg_Call(app, "subtract", "int32_t subtract(int32_t a, int32_t b) - Subtract b from a", IntPtr.Zero, subDel);
            API_Reg_Call(app, "multiply", "int32_t multiply(int32_t a, int32_t b) - Multiply two integers", IntPtr.Zero, mulDel);
            API_Reg_Call(app, "divide", "double divide(int32_t a, int32_t b) - Divide a by b (returns double)", IntPtr.Zero, divDel);
            API_Reg_Call(app, "to_upper", "char* to_upper(const char* str) - Convert string to uppercase", IntPtr.Zero, upperDel);
            API_Reg_Call(app, "to_lower", "char* to_lower(const char* str) - Convert string to lowercase", IntPtr.Zero, lowerDel);
            API_Reg_Call(app, "reverse", "char* reverse(const char* str) - Reverse a string", IntPtr.Zero, revDel);
            API_Reg_Call(app, "get_time", "char* get_time() - Get current time as 'YYYY-MM-DD HH:MM:SS'", IntPtr.Zero, timeDel);
            API_Reg_Call(app, "get_random", "int32_t get_random(int32_t min, int32_t max) - Get random integer in [min, max]", IntPtr.Zero, randDel);
            API_Reg_Call(app, "echo", "char* echo(const char* msg) - Echo input string", IntPtr.Zero, echoDel);
            API_Reg_Call(app, "sum_array", "int32_t sum_array(const int32_t* arr, int32_t count) - Sum an array of integers", IntPtr.Zero, sumArrDel);
            API_Reg_Call(app, "concat_strings", "char* concat_strings(const char* arr[], int32_t count) - Concatenate strings with spaces", IntPtr.Zero, concatDel);
            API_Reg_Call(app, "sha3", "char* sha3(const char* data) - SHA3-256 hash (hex)", IntPtr.Zero, sha3Del);

            Console.WriteLine("已注册 13 个 API。");

            // 网络准备
            API_Reset_Prepare();
            API_Prepare_Service("ipc:func_service", "ipc:func_service");
            API_Prepare_Service("0.0.0.0", "127.0.0.1:9899");
            API_Prepare_Client("ipc:func_service", app);
            API_Prepare_Client("127.0.0.1:9899", app);

            Console.WriteLine("正在启动服务...");
            if (API_Prepare_Done() != 1)
            {
                Console.WriteLine("启动失败。错误信息请查看控制台输出。");
                API_Free_APPHnd(app);
                API_shutdown();
                return;
            }

            Console.WriteLine("服务已启动。输入 'exit' 停止。");

            // 控制台输入线程
            Thread inputThread = new Thread(() =>
            {
                while (!_exitFlag)
                {
                    Console.Write("FuncService> ");
                    string line = Console.ReadLine();
                    if (line == "exit")
                    {
                        _exitFlag = true;
                        break;
                    }
                    else if (line == "status")
                    {
                        Console.WriteLine("[Service] 运行中。");
                    }
                }
            });
            inputThread.Start();

            // 主循环——状态由库输出，无需额外处理
            while (!_exitFlag)
            {
                Thread.Sleep(100);
            }

            inputThread.Join();

            Console.WriteLine("正在关闭...");
            API_Exit_MainThread();
            API_Free_APPHnd(app);
            API_shutdown();
            Console.WriteLine("服务已停止。");
        }
    }
}