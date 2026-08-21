using API_HubTool.Bindings;
using System;
using System.Runtime.InteropServices;
using static API_HubTool.Bindings.API;

namespace CrossDemo
{
    class CrossNode
    {
        // ---------- 回调委托（必须静态保持存活） ----------
        private static readonly APICallDelegate AddCallbackDelegate = AddCallback;
        private static readonly APICallDelegate InvSeriCallbackDelegate = InvSeriCallback;

        // ---------- add 回调 ----------
        private static void AddCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };

            if (!API_ReadInt32(hInput, out int a) || !API_ReadInt32(hInput, out int b))
            {
                Console.WriteLine("[Node] add 读取参数失败");
                return;
            }
            int c = a + b;
            Console.WriteLine($"[Node] add({a}, {b}) = {c}");

            if (!API_WriteInt32(hOutput, c))
                Console.WriteLine("[Node] add 写入结果失败");
        }

        // ---------- inv_seri 回调 ----------
        private static void InvSeriCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };

            // 按顺序读取基本类型
            if (!API_ReadUInt8(hInput, out byte b) ||
                !API_ReadUInt16(hInput, out ushort w) ||
                !API_ReadUInt32(hInput, out uint c) ||
                !API_ReadUInt64(hInput, out ulong u64))
            {
                Console.WriteLine("[Node] inv_seri 读取基本类型失败");
                return;
            }
            // ⭐ 使用官方 API.ReadString（空终止符协议）
            string s = API_ReadString(hInput);
            if (!API_ReadSingle(hInput, out float f))
            {
                Console.WriteLine("[Node] inv_seri 读取 float 失败");
                return;
            }

            Console.WriteLine($"[Node] inv_seri 接收: [{b}, {w}, {c}, {u64}, \"{s}\", {f}]");

            // 反向顺序写回（使用官方 API.WriteString）
            if (!API_WriteSingle(hOutput, f) ||
                !API_WriteString(hOutput, s) ||
                !API_WriteUInt64(hOutput, u64) ||
                !API_WriteUInt32(hOutput, c) ||
                !API_WriteUInt16(hOutput, w) ||
                !API_WriteUInt8(hOutput, b))
            {
                Console.WriteLine("[Node] inv_seri 写入回复失败");
                return;
            }
            Console.WriteLine($"[Node] inv_seri 回复: [{f}, \"{s}\", {u64}, {c}, {w}, {b}]");
        }

        static void Main()
        {
            Console.WriteLine("=== Cross Node (Worker) ===");

            AppHnd app = API_Create_APPHnd("demo", "C# worker node");
            if (!app.IsValid)
            {
                Console.WriteLine("创建 AppHnd 失败");
                return;
            }

            int r1 = API_Reg_Call(app, "add", "add(int,int)", IntPtr.Zero, AddCallbackDelegate);
            int r2 = API_Reg_Call(app, "inv_seri", "inv_seri()", IntPtr.Zero, InvSeriCallbackDelegate);
            if (r1 != 1 || r2 != 1)
            {
                Console.WriteLine("注册 API 失败");
                API_Free_APPHnd(app);
                return;
            }

            API_SetOption("Wait_Ready", "False");

            API_Reset_Prepare();
            int prep = API_Prepare_Client("ipc:cross", app);
            if (prep == 0)
            {
                Console.WriteLine("API_Prepare_Client 失败");
                API_Free_APPHnd(app);
                return;
            }

            if (API_Prepare_Done() != 1)
            {
                Console.WriteLine("API_Prepare_Done 失败，请检查控制台输出");
                API_Free_APPHnd(app);
                API_shutdown();
                return;
            }

            Console.WriteLine("节点已注册，按 Enter 退出...");
            Console.ReadLine();

            API_Exit_MainThread();
            API_Free_APPHnd(app);
            API_shutdown();
            Console.WriteLine("节点已关闭");
        }
    }
}