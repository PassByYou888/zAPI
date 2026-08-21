using System;
using System.Threading;
using System.Threading.Tasks;
using API_HubTool.Bindings;
using static API_HubTool.Bindings.API;

namespace CrossDemo
{
    class CrossCall
    {
        // ---------- add 远程调用 ----------
        private static int Add(int a, int b)
        {
            DataHnd send = API_Create_DataHnd("add");
            if (!API_WriteInt32(send, a) || !API_WriteInt32(send, b))
            {
                API_Free_DataHnd(send);
                return 0;
            }

            DataHnd result = API_Call("demo", send, 1000);
            API_Free_DataHnd(send);

            if (API_GetSize(result) == 0)
            {
                API_Free_DataHnd(result);
                return 0;
            }
            if (!API_ReadInt32(result, out int c))
                c = 0;
            API_Free_DataHnd(result);
            return c;
        }

        // ---------- inv_seri 远程调用 ----------
        private static string InvSeri()
        {
            // 构造输入数据
            byte b = 200;
            ushort w = 0x10;
            uint c = 0x2F;
            ulong u64 = 0x3F;
            string s = "hello world";
            float f = 3.14f;

            DataHnd send = API_Create_DataHnd("inv_seri");
            if (!API_WriteUInt8(send, b) ||
                !API_WriteUInt16(send, w) ||
                !API_WriteUInt32(send, c) ||
                !API_WriteUInt64(send, u64))
            {
                API_Free_DataHnd(send);
                return "写入基本类型失败";
            }
            // ⭐ 使用官方 API.WriteString（空终止符协议）
            if (!API_WriteString(send, s))
            {
                API_Free_DataHnd(send);
                return "写入字符串失败";
            }
            if (!API_WriteSingle(send, f))
            {
                API_Free_DataHnd(send);
                return "写入 float 失败";
            }

            DataHnd result = API_Call("demo", send, 1000);
            API_Free_DataHnd(send);

            if (API_GetSize(result) == 0)
            {
                API_Free_DataHnd(result);
                return "超时";
            }

            // 按逆序读取（使用官方 API.ReadString）
            if (!API_ReadSingle(result, out float f2))
            {
                API_Free_DataHnd(result);
                return "读取 float 失败";
            }
            string s2 = API_ReadString(result);    // ⭐ 自动读取到 #0
            if (!API_ReadUInt64(result, out ulong u64_2) ||
                !API_ReadUInt32(result, out uint c2) ||
                !API_ReadUInt16(result, out ushort w2) ||
                !API_ReadUInt8(result, out byte b2))
            {
                API_Free_DataHnd(result);
                return "读取基本类型失败";
            }
            API_Free_DataHnd(result);

            return $"接收逆序: [{b2}, {w2}, {c2}, {u64_2}, \"{s2}\", {f2}]  原始: [{b}, {w}, {c}, {u64}, \"{s}\", {f}]";
        }

        static void Main()
        {
            Console.WriteLine("=== Cross Call (Client) ===");

            // 连接服务端点（纯消费，不暴露 API）
            API_Reset_Prepare();
            int prep = API_Prepare_Client("ipc:cross", AppHnd.Null);
            if (prep == 0)
            {
                Console.WriteLine("API_Prepare_Client 失败");
                return;
            }

            if (API_Prepare_Done() != 1)
            {
                Console.WriteLine("API_Prepare_Done 失败，请检查控制台输出");
                API_shutdown();
                return;
            }

            Console.WriteLine("已连接到 ipc:cross，开始负载测试（10秒）");

            CancellationTokenSource cts = new CancellationTokenSource();
            cts.CancelAfter(TimeSpan.FromSeconds(10));

            // 使用 Parallel.For，检查外部 CancellationToken
            Parallel.For(0, 10, (i, state) =>
            {
                var rand = new Random(i + Environment.TickCount);
                while (!cts.Token.IsCancellationRequested)
                {
                    if (rand.Next(2) == 0)
                    {
                        int a = rand.Next(1, 1000);
                        int b = rand.Next(1, 1000);
                        int result = Add(a, b);
                        if (result != 0)
                            Console.WriteLine($"[Client {i}] add({a},{b}) = {result}");
                        else
                            Console.WriteLine($"[Client {i}] add({a},{b}) 超时或失败");
                    }
                    else
                    {
                        string msg = InvSeri();
                        Console.WriteLine($"[Client {i}] {msg}");
                    }
                    Thread.Sleep(50);
                }
            });

            Console.WriteLine("负载测试结束，按 Enter 退出...");
            Console.ReadLine();

            API_Exit_MainThread();
            API_shutdown();
        }
    }
}