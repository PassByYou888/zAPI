/*
 * Service.cs - API Hub 服务端（全中文注释）
 * 
 * 嘿！这就是你的“云服务”后台。我们开了一家“计算服务公司”，
 * 提供各种 API 供其他程序（Client1、Client2 等）远程调用。
 * 
 * 我们通过 IPC（进程间通信）暴露自己，任何连接到 ipc:demo_service 的客户端
 * 都能使用我们提供的功能。
 * 
 * 本服务注册了 10 多个 API，涵盖：
 *   - 数学运算（加、减、乘、除）
 *   - 字符串处理（回显、连接、大小写转换）
 *   - 数组统计（求和、平均值）
 *   - 工具（获取当前时间）
 * 
 * 只要启动本服务，其他程序就能通过网络（或 IPC）来调用这些 API，
 * 就像调用本地函数一样简单 —— 这就是 API Hub 的魅力！
 * 
 * 使用方法：
 *   1. 编译运行，等待提示 “Service is running”
 *   2. 输入 exit 可以停止服务
 *   3. 输入 status 查看当前状态
 * 
 * 注意：本服务同时作为服务端和客户端（连接到自己的服务），
 * 这是为了方便内部测试，你完全可以忽略这个细节。
 */

using System;
using System.Threading;
using System.Runtime.InteropServices;
using API_HubTool.Bindings;
using static API_HubTool.Bindings.API;

namespace Service
{
    class Service
    {
        private static volatile bool _退出标志 = false;

        // ================================================================
        // 1. 定义所有 API 回调函数（我们的服务内容）
        // ================================================================

        /// <summary>
        /// 加法：读取两个 int，返回和
        /// </summary>
        private static void 加法回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] buf = ReadAllBytes(hInput);
            if (buf.Length < 8) return;
            int a = BitConverter.ToInt32(buf, 0);
            int b = BitConverter.ToInt32(buf, 4);
            int sum = a + b;
            API_WriteBuffer(hOutput, BitConverter.GetBytes(sum), 4);
        }

        /// <summary>
        /// 减法：读取两个 int，返回 a-b
        /// </summary>
        private static void 减法回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] buf = ReadAllBytes(hInput);
            if (buf.Length < 8) return;
            int a = BitConverter.ToInt32(buf, 0);
            int b = BitConverter.ToInt32(buf, 4);
            int diff = a - b;
            API_WriteBuffer(hOutput, BitConverter.GetBytes(diff), 4);
        }

        /// <summary>
        /// 乘法：读取两个 int，返回积
        /// </summary>
        private static void 乘法回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] buf = ReadAllBytes(hInput);
            if (buf.Length < 8) return;
            int a = BitConverter.ToInt32(buf, 0);
            int b = BitConverter.ToInt32(buf, 4);
            int product = a * b;
            API_WriteBuffer(hOutput, BitConverter.GetBytes(product), 4);
        }

        /// <summary>
        /// 除法：读取两个 int，返回 a/b（若 b=0，返回 0 并输出警告）
        /// </summary>
        private static void 除法回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] buf = ReadAllBytes(hInput);
            if (buf.Length < 8) return;
            int a = BitConverter.ToInt32(buf, 0);
            int b = BitConverter.ToInt32(buf, 4);
            if (b == 0)
            {
                Console.WriteLine("[服务警告] 除零错误，返回 0");
                API_WriteBuffer(hOutput, BitConverter.GetBytes(0), 4);
                return;
            }
            int quotient = a / b;
            API_WriteBuffer(hOutput, BitConverter.GetBytes(quotient), 4);
        }

        /// <summary>
        /// 回显：原样返回输入字符串（二进制）
        /// </summary>
        private static void 回显回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] data = ReadAllBytes(hInput);
            API_WriteBuffer(hOutput, data, data.Length);
        }

        /// <summary>
        /// 字符串连接：读取两个以 null 分隔的字符串，返回拼接结果
        /// </summary>
        private static void 连接回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] all = ReadAllBytes(hInput);
            int sep = Array.IndexOf(all, (byte)0);
            if (sep < 0) return;
            string s1 = System.Text.Encoding.UTF8.GetString(all, 0, sep);
            string s2 = System.Text.Encoding.UTF8.GetString(all, sep + 1, all.Length - sep - 1);
            string result = s1 + s2;
            WriteString(hOutput, result);
        }

        /// <summary>
        /// 转大写：输入字符串，返回全大写
        /// </summary>
        private static void 转大写回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            string str = ReadString(hInput);
            WriteString(hOutput, str.ToUpper());
        }

        /// <summary>
        /// 转小写：输入字符串，返回全小写
        /// </summary>
        private static void 转小写回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            string str = ReadString(hInput);
            WriteString(hOutput, str.ToLower());
        }

        /// <summary>
        /// 数组求和：输入为 4 字节长度 + int 数组，返回总和
        /// </summary>
        private static void 数组求和回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] data = ReadAllBytes(hInput);
            if (data.Length < 4) return;
            int count = BitConverter.ToInt32(data, 0);
            if (count == 0) { API_WriteBuffer(hOutput, BitConverter.GetBytes(0), 4); return; }
            if (data.Length < 4 + count * 4) return;
            int sum = 0;
            for (int i = 0; i < count; i++)
                sum += BitConverter.ToInt32(data, 4 + i * 4);
            API_WriteBuffer(hOutput, BitConverter.GetBytes(sum), 4);
        }

        /// <summary>
        /// 数组平均值：输入为 4 字节长度 + int 数组，返回 double 平均值
        /// </summary>
        private static void 数组平均值回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] data = ReadAllBytes(hInput);
            if (data.Length < 4) return;
            int count = BitConverter.ToInt32(data, 0);
            if (count == 0) { API_WriteBuffer(hOutput, BitConverter.GetBytes(0.0), 8); return; }
            if (data.Length < 4 + count * 4) return;
            long sum = 0;
            for (int i = 0; i < count; i++)
                sum += BitConverter.ToInt32(data, 4 + i * 4);
            double avg = (double)sum / count;
            API_WriteBuffer(hOutput, BitConverter.GetBytes(avg), 8);
        }

        /// <summary>
        /// 获取当前时间：返回 “yyyy-MM-dd HH:mm:ss” 字符串
        /// </summary>
        private static void 获取时间回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hOutput = new DataHnd { Handle = output };
            string now = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
            WriteString(hOutput, now);
        }

        // ================================================================
        // 辅助函数：打印状态消息（从框架内部获取日志）——已移除，改用控制台输出
        // ================================================================

        // ================================================================
        // 主程序
        // ================================================================
        static void Main()
        {
            Console.WriteLine("=== 🚀 API Hub 服务端（C#）===");
            Console.WriteLine("欢迎来到强大的分布式 API 服务！");
            Console.WriteLine("我们提供加法、减法、乘法、除法、回显、连接、大小写转换、数组统计、时间等 10+ 个 API。");
            Console.WriteLine("任何连接到 ipc:demo_service 的客户端都可以调用它们，就像调用本地函数一样简单！");
            Console.WriteLine();

            // 1. 创建应用程序句柄（相当于开公司）
            AppHnd app = API_Create_APPHnd("ServiceApp", "公共计算服务");
            if (!app.IsValid)
            {
                Console.WriteLine("❌ 创建应用失败。");
                return;
            }
            Console.WriteLine("✅ 应用句柄创建成功。");

            // 2. 注册所有 API（招聘员工）
            APICallDelegate 加 = 加法回调;
            APICallDelegate 减 = 减法回调;
            APICallDelegate 乘 = 乘法回调;
            APICallDelegate 除 = 除法回调;
            APICallDelegate 回 = 回显回调;
            APICallDelegate 连 = 连接回调;
            APICallDelegate 大写 = 转大写回调;
            APICallDelegate 小写 = 转小写回调;
            APICallDelegate 数组和 = 数组求和回调;
            APICallDelegate 数组均 = 数组平均值回调;
            APICallDelegate 时间 = 获取时间回调;

            // 固定委托（防止被 .NET GC 回收，这是关键！）
            GCHandle.Alloc(加); GCHandle.Alloc(减); GCHandle.Alloc(乘); GCHandle.Alloc(除);
            GCHandle.Alloc(回); GCHandle.Alloc(连); GCHandle.Alloc(大写); GCHandle.Alloc(小写);
            GCHandle.Alloc(数组和); GCHandle.Alloc(数组均); GCHandle.Alloc(时间);

            // 注册 Call 型 API（请求-响应）
            API_Reg_Call(app, "add", "整数加法", IntPtr.Zero, 加);
            API_Reg_Call(app, "subtract", "整数减法", IntPtr.Zero, 减);
            API_Reg_Call(app, "multiply", "整数乘法", IntPtr.Zero, 乘);
            API_Reg_Call(app, "divide", "整数除法", IntPtr.Zero, 除);
            API_Reg_Call(app, "echo", "二进制回显", IntPtr.Zero, 回);
            API_Reg_Call(app, "concat", "连接两个字符串", IntPtr.Zero, 连);
            API_Reg_Call(app, "to_upper", "转大写", IntPtr.Zero, 大写);
            API_Reg_Call(app, "to_lower", "转小写", IntPtr.Zero, 小写);
            API_Reg_Call(app, "array_sum", "整数数组求和", IntPtr.Zero, 数组和);
            API_Reg_Call(app, "array_avg", "整数数组平均值", IntPtr.Zero, 数组均);
            API_Reg_Call(app, "get_time", "获取当前时间", IntPtr.Zero, 时间);

            Console.WriteLine("✅ 已注册 11 个 API 服务。");
            Console.WriteLine("   可用 API 列表：add, subtract, multiply, divide, echo, concat,");
            Console.WriteLine("   to_upper, to_lower, array_sum, array_avg, get_time");

            // 3. 网络准备（启动 IPC 服务，并自我连接以便内部测试）
            API_Reset_Prepare();
            API_Prepare_Service("ipc:demo_service", "ipc:demo_service");
            API_Prepare_Client("ipc:demo_service", app);  // 自我连接，让本应用也注册到服务

            Console.WriteLine("正在启动服务框架...");
            if (API_Prepare_Done() != 1)
            {
                Console.WriteLine("❌ 框架启动失败。错误信息请查看控制台输出。");
                API_Free_APPHnd(app);
                API_shutdown();
                return;
            }
            Console.WriteLine("✅ 服务已启动，正在监听 ipc:demo_service");
            Console.WriteLine("输入 'exit' 停止服务，输入 'status' 查看状态。");
            Console.WriteLine();

            // 4. 控制台输入线程（允许管理员交互）
            Thread inputThread = new Thread(() =>
            {
                while (!_退出标志)
                {
                    Console.Write("服务> ");
                    string line = Console.ReadLine();
                    if (line == "exit")
                    {
                        _退出标志 = true;
                        break;
                    }
                    else if (line == "status")
                    {
                        Console.WriteLine("[服务] 运行中，已注册 11 个 API。");
                    }
                    else if (line == "help")
                    {
                        Console.WriteLine("可用命令：exit, status, help");
                    }
                    else
                    {
                        Console.WriteLine($"未知命令：{line}，输入 help 查看帮助。");
                    }
                }
            });
            inputThread.Start();

            // 5. 主循环——状态由库输出到控制台，无需额外处理
            while (!_退出标志)
            {
                Thread.Sleep(100);
            }

            // 6. 清理
            inputThread.Join();
            Console.WriteLine("正在关闭服务...");
            API_Exit_MainThread();
            API_Free_APPHnd(app);
            API_shutdown();
            Console.WriteLine("服务已停止。谢谢使用！");
        }
    }
}