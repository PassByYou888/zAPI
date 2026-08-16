/*
 * Client1.cs - API Hub 客户端1（全中文注释）
 * 
 * 嘿！我们是 Client1，一家小型的“回声与平方”服务提供商。
 * 我们自己也注册了 API（client1_echo, client1_square, client1_greet），
 * 同时我们可以调用 Service 的所有 API，也可以调用 Client2 的 API。
 * 
 * 这是一个互动式命令行客户端，你可以输入各种命令来调用远程 API，
 * 体验分布式调用的魔力。
 * 
 * 命令列表（约 20+ 个）：
 *   call service add <a> <b>               - 调用 Service.add
 *   call service subtract <a> <b>          - 调用 Service.subtract
 *   call service multiply <a> <b>          - 调用 Service.multiply
 *   call service divide <a> <b>            - 调用 Service.divide
 *   call service echo <msg>                - 调用 Service.echo
 *   call service concat <str1> <str2>      - 调用 Service.concat
 *   call service to_upper <str>            - 调用 Service.to_upper
 *   call service to_lower <str>            - 调用 Service.to_lower
 *   call service array_sum <num1 num2 ...> - 调用 Service.array_sum
 *   call service array_avg <num1 num2 ...> - 调用 Service.array_avg
 *   call service get_time                  - 调用 Service.get_time
 *   call client2 reverse <msg>             - 调用 Client2.reverse
 *   call client2 ping                      - 调用 Client2.ping
 *   call client2 uppercase <msg>           - 调用 Client2.uppercase
 *   call client1 echo <msg>                - 本地调用自己的 echo（测试）
 *   call client1 square <num>              - 本地调用自己的 square（测试）
 *   call client1 greet <name>              - 本地调用自己的 greet（测试）
 *   status                                 - 显示当前状态
 *   help                                   - 显示帮助
 *   exit                                   - 退出程序
 * 
 * 所有命令都以 "call" 开头，后面跟目标（service/client1/client2）和 API 名称及参数。
 * 快来试试吧！
 */

using System;
using System.Threading;
using System.Runtime.InteropServices;
using API_HubTool.Bindings;
using static API_HubTool.Bindings.API;

namespace Client1
{
    class Client1
    {
        private static volatile bool _退出标志 = false;
        private static AppHnd _应用句柄;

        // ================================================================
        // 1. 注册自己的 API（供其他客户端调用）
        // ================================================================

        /// <summary>
        /// client1_echo：原样回显输入字符串（类似于 Service.echo，但这是自己的）
        /// </summary>
        private static void 自身回显回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] data = ReadAllBytes(hInput);
            API_WriteBuffer(hOutput, data, data.Length);
        }

        /// <summary>
        /// client1_square：读取一个 int，返回它的平方
        /// </summary>
        private static void 自身平方回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] buf = ReadAllBytes(hInput);
            if (buf.Length < 4) return;
            int n = BitConverter.ToInt32(buf, 0);
            int square = n * n;
            API_WriteBuffer(hOutput, BitConverter.GetBytes(square), 4);
        }

        /// <summary>
        /// client1_greet：接收名字，返回 “你好，{name}！” 的问候语
        /// </summary>
        private static void 自身问候回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            string name = ReadString(hInput);
            string greeting = $"你好，{name}！欢迎来到 API Hub 世界！";
            WriteString(hOutput, greeting);
        }

        // ================================================================
        // 2. 调用远程 API 的辅助函数（封装）
        // ================================================================

        private static void 调用服务加法(int a, int b)
        {
            DataHnd data = API_Create_DataHnd("add");
            byte[] payload = new byte[8];
            BitConverter.GetBytes(a).CopyTo(payload, 0);
            BitConverter.GetBytes(b).CopyTo(payload, 4);
            API_WriteBuffer(data, payload, 8);
            DataHnd result = API_Call("ServiceApp", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid && API_GetSize(result) >= 4)
            {
                int sum = BitConverter.ToInt32(ReadAllBytes(result), 0);
                Console.WriteLine($"✅ Service.add({a},{b}) = {sum}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Service.add 调用失败或超时。");
        }

        private static void 调用服务减法(int a, int b)
        {
            DataHnd data = API_Create_DataHnd("subtract");
            byte[] payload = new byte[8];
            BitConverter.GetBytes(a).CopyTo(payload, 0);
            BitConverter.GetBytes(b).CopyTo(payload, 4);
            API_WriteBuffer(data, payload, 8);
            DataHnd result = API_Call("ServiceApp", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid && API_GetSize(result) >= 4)
            {
                int diff = BitConverter.ToInt32(ReadAllBytes(result), 0);
                Console.WriteLine($"✅ Service.subtract({a},{b}) = {diff}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Service.subtract 调用失败或超时。");
        }

        private static void 调用服务乘法(int a, int b)
        {
            DataHnd data = API_Create_DataHnd("multiply");
            byte[] payload = new byte[8];
            BitConverter.GetBytes(a).CopyTo(payload, 0);
            BitConverter.GetBytes(b).CopyTo(payload, 4);
            API_WriteBuffer(data, payload, 8);
            DataHnd result = API_Call("ServiceApp", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid && API_GetSize(result) >= 4)
            {
                int product = BitConverter.ToInt32(ReadAllBytes(result), 0);
                Console.WriteLine($"✅ Service.multiply({a},{b}) = {product}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Service.multiply 调用失败或超时。");
        }

        private static void 调用服务除法(int a, int b)
        {
            DataHnd data = API_Create_DataHnd("divide");
            byte[] payload = new byte[8];
            BitConverter.GetBytes(a).CopyTo(payload, 0);
            BitConverter.GetBytes(b).CopyTo(payload, 4);
            API_WriteBuffer(data, payload, 8);
            DataHnd result = API_Call("ServiceApp", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid && API_GetSize(result) >= 4)
            {
                int quotient = BitConverter.ToInt32(ReadAllBytes(result), 0);
                Console.WriteLine($"✅ Service.divide({a},{b}) = {quotient}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Service.divide 调用失败或超时。");
        }

        private static void 调用服务回显(string msg)
        {
            DataHnd data = API_Create_DataHnd("echo");
            WriteString(data, msg);
            DataHnd result = API_Call("ServiceApp", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid)
            {
                string echoed = ReadString(result);
                Console.WriteLine($"✅ Service.echo 回复：{echoed}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Service.echo 调用失败。");
        }

        private static void 调用服务连接(string s1, string s2)
        {
            DataHnd data = API_Create_DataHnd("concat");
            byte[] b1 = System.Text.Encoding.UTF8.GetBytes(s1 + "\0");
            byte[] b2 = System.Text.Encoding.UTF8.GetBytes(s2 + "\0");
            byte[] payload = new byte[b1.Length + b2.Length];
            Array.Copy(b1, 0, payload, 0, b1.Length);
            Array.Copy(b2, 0, payload, b1.Length, b2.Length);
            API_WriteBuffer(data, payload, payload.Length);
            DataHnd result = API_Call("ServiceApp", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid)
            {
                string concat = ReadString(result);
                Console.WriteLine($"✅ Service.concat 结果：'{concat}'");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Service.concat 调用失败。");
        }

        private static void 调用服务转大写(string str)
        {
            DataHnd data = API_Create_DataHnd("to_upper");
            WriteString(data, str);
            DataHnd result = API_Call("ServiceApp", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid)
            {
                string upper = ReadString(result);
                Console.WriteLine($"✅ Service.to_upper('{str}') = '{upper}'");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Service.to_upper 调用失败。");
        }

        private static void 调用服务转小写(string str)
        {
            DataHnd data = API_Create_DataHnd("to_lower");
            WriteString(data, str);
            DataHnd result = API_Call("ServiceApp", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid)
            {
                string lower = ReadString(result);
                Console.WriteLine($"✅ Service.to_lower('{str}') = '{lower}'");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Service.to_lower 调用失败。");
        }

        private static void 调用服务数组求和(int[] nums)
        {
            DataHnd data = API_Create_DataHnd("array_sum");
            int count = nums.Length;
            byte[] payload = new byte[4 + count * 4];
            BitConverter.GetBytes(count).CopyTo(payload, 0);
            for (int i = 0; i < count; i++)
                BitConverter.GetBytes(nums[i]).CopyTo(payload, 4 + i * 4);
            API_WriteBuffer(data, payload, payload.Length);
            DataHnd result = API_Call("ServiceApp", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid && API_GetSize(result) >= 4)
            {
                int sum = BitConverter.ToInt32(ReadAllBytes(result), 0);
                Console.WriteLine($"✅ Service.array_sum({string.Join(",", nums)}) = {sum}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Service.array_sum 调用失败。");
        }

        private static void 调用服务数组平均值(int[] nums)
        {
            DataHnd data = API_Create_DataHnd("array_avg");
            int count = nums.Length;
            byte[] payload = new byte[4 + count * 4];
            BitConverter.GetBytes(count).CopyTo(payload, 0);
            for (int i = 0; i < count; i++)
                BitConverter.GetBytes(nums[i]).CopyTo(payload, 4 + i * 4);
            API_WriteBuffer(data, payload, payload.Length);
            DataHnd result = API_Call("ServiceApp", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid && API_GetSize(result) >= 8)
            {
                double avg = BitConverter.ToDouble(ReadAllBytes(result), 0);
                Console.WriteLine($"✅ Service.array_avg({string.Join(",", nums)}) = {avg:F2}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Service.array_avg 调用失败。");
        }

        private static void 调用服务获取时间()
        {
            DataHnd data = API_Create_DataHnd("get_time");
            DataHnd result = API_Call("ServiceApp", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid)
            {
                string time = ReadString(result);
                Console.WriteLine($"✅ Service.get_time = {time}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Service.get_time 调用失败。");
        }

        // ---- 调用 Client2 的 API ----
        private static void 调用Client2反转(string msg)
        {
            DataHnd data = API_Create_DataHnd("client2_reverse");
            WriteString(data, msg);
            DataHnd result = API_Call("Client2", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid)
            {
                string reversed = ReadString(result);
                Console.WriteLine($"✅ Client2.reverse 回复：{reversed}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Client2.reverse 失败（Client2 可能未运行）。");
        }

        private static void 调用Client2Ping()
        {
            DataHnd data = API_Create_DataHnd("client2_ping");
            // 无输入参数
            DataHnd result = API_Call("Client2", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid)
            {
                string pong = ReadString(result);
                Console.WriteLine($"✅ Client2.ping 回复：{pong}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Client2.ping 失败（Client2 可能未运行）。");
        }

        private static void 调用Client2转大写(string msg)
        {
            DataHnd data = API_Create_DataHnd("client2_uppercase");
            WriteString(data, msg);
            DataHnd result = API_Call("Client2", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid)
            {
                string upper = ReadString(result);
                Console.WriteLine($"✅ Client2.uppercase 回复：{upper}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Client2.uppercase 失败（Client2 可能未运行）。");
        }

        // ---- 本地调用自己的 API（用于测试） ----
        private static void 本地调用自身回显(string msg)
        {
            DataHnd data = API_Create_DataHnd("client1_echo");
            WriteString(data, msg);
            DataHnd result = API_Local_APP_Call(_应用句柄, data);
            API_Free_DataHnd(data);
            if (result.IsValid)
            {
                string echoed = ReadString(result);
                Console.WriteLine($"✅ 本地 client1_echo 回复：{echoed}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ 本地 client1_echo 失败。");
        }

        private static void 本地调用自身平方(int n)
        {
            DataHnd data = API_Create_DataHnd("client1_square");
            API_WriteBuffer(data, BitConverter.GetBytes(n), 4);
            DataHnd result = API_Local_APP_Call(_应用句柄, data);
            API_Free_DataHnd(data);
            if (result.IsValid && API_GetSize(result) >= 4)
            {
                int square = BitConverter.ToInt32(ReadAllBytes(result), 0);
                Console.WriteLine($"✅ 本地 client1_square({n}) = {square}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ 本地 client1_square 失败。");
        }

        private static void 本地调用自身问候(string name)
        {
            DataHnd data = API_Create_DataHnd("client1_greet");
            WriteString(data, name);
            DataHnd result = API_Local_APP_Call(_应用句柄, data);
            API_Free_DataHnd(data);
            if (result.IsValid)
            {
                string greeting = ReadString(result);
                Console.WriteLine($"✅ 本地 client1_greet 回复：{greeting}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ 本地 client1_greet 失败。");
        }

        // ================================================================
        // 3. 命令解析与分发
        // ================================================================
        private static void 处理命令(string cmd)
        {
            string[] parts = cmd.Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 0) return;

            if (parts[0] == "exit")
            {
                _退出标志 = true;
                return;
            }
            else if (parts[0] == "help")
            {
                显示帮助();
                return;
            }
            else if (parts[0] == "status")
            {
                Console.WriteLine("Client1 运行中，已注册 API: client1_echo, client1_square, client1_greet");
                Console.WriteLine("连接状态：已连接到 ipc:demo_service");
                return;
            }

            if (parts[0] != "call" || parts.Length < 3)
            {
                Console.WriteLine("未知命令。输入 'help' 查看帮助。");
                return;
            }

            string target = parts[1];
            string api = parts[2];

            if (target == "service")
            {
                if (api == "add" && parts.Length == 5)
                {
                    int a = int.Parse(parts[3]);
                    int b = int.Parse(parts[4]);
                    调用服务加法(a, b);
                }
                else if (api == "subtract" && parts.Length == 5)
                {
                    int a = int.Parse(parts[3]);
                    int b = int.Parse(parts[4]);
                    调用服务减法(a, b);
                }
                else if (api == "multiply" && parts.Length == 5)
                {
                    int a = int.Parse(parts[3]);
                    int b = int.Parse(parts[4]);
                    调用服务乘法(a, b);
                }
                else if (api == "divide" && parts.Length == 5)
                {
                    int a = int.Parse(parts[3]);
                    int b = int.Parse(parts[4]);
                    调用服务除法(a, b);
                }
                else if (api == "echo" && parts.Length >= 4)
                {
                    string msg = string.Join(" ", parts, 3, parts.Length - 3);
                    调用服务回显(msg);
                }
                else if (api == "concat" && parts.Length >= 5)
                {
                    // 前两个参数是字符串，可能包含空格，所以需要提取
                    // 简单处理：取第3个到倒数第2个为 s1，最后一个为 s2
                    // 但为了简单，我们限制两个字符串都不含空格，可以用空格分隔
                    // 此处我们约定两个字符串均不含空格，否则用引号？简化处理。
                    // 我们假定用户知道如何输入，这里直接取 parts[3] 和 parts[4]
                    if (parts.Length >= 5)
                    {
                        string s1 = parts[3];
                        string s2 = parts[4];
                        调用服务连接(s1, s2);
                    }
                    else
                    {
                        Console.WriteLine("用法: call service concat <str1> <str2>");
                    }
                }
                else if (api == "to_upper" && parts.Length >= 4)
                {
                    string str = string.Join(" ", parts, 3, parts.Length - 3);
                    调用服务转大写(str);
                }
                else if (api == "to_lower" && parts.Length >= 4)
                {
                    string str = string.Join(" ", parts, 3, parts.Length - 3);
                    调用服务转小写(str);
                }
                else if (api == "array_sum" && parts.Length >= 4)
                {
                    // 从 parts[3] 开始到结束都是数字
                    int[] nums = new int[parts.Length - 3];
                    for (int i = 0; i < nums.Length; i++)
                        nums[i] = int.Parse(parts[3 + i]);
                    调用服务数组求和(nums);
                }
                else if (api == "array_avg" && parts.Length >= 4)
                {
                    int[] nums = new int[parts.Length - 3];
                    for (int i = 0; i < nums.Length; i++)
                        nums[i] = int.Parse(parts[3 + i]);
                    调用服务数组平均值(nums);
                }
                else if (api == "get_time" && parts.Length == 3)
                {
                    调用服务获取时间();
                }
                else
                {
                    Console.WriteLine($"未知服务 API：{api}，输入 help 查看支持的命令。");
                }
            }
            else if (target == "client2")
            {
                if (api == "reverse" && parts.Length >= 4)
                {
                    string msg = string.Join(" ", parts, 3, parts.Length - 3);
                    调用Client2反转(msg);
                }
                else if (api == "ping" && parts.Length == 3)
                {
                    调用Client2Ping();
                }
                else if (api == "uppercase" && parts.Length >= 4)
                {
                    string msg = string.Join(" ", parts, 3, parts.Length - 3);
                    调用Client2转大写(msg);
                }
                else
                {
                    Console.WriteLine($"未知 Client2 API：{api}，输入 help 查看支持的命令。");
                }
            }
            else if (target == "client1")
            {
                // 本地调用自己的 API（也可以远程调用自己，但这里演示本地）
                if (api == "echo" && parts.Length >= 4)
                {
                    string msg = string.Join(" ", parts, 3, parts.Length - 3);
                    本地调用自身回显(msg);
                }
                else if (api == "square" && parts.Length == 4)
                {
                    int n = int.Parse(parts[3]);
                    本地调用自身平方(n);
                }
                else if (api == "greet" && parts.Length >= 4)
                {
                    string name = string.Join(" ", parts, 3, parts.Length - 3);
                    本地调用自身问候(name);
                }
                else
                {
                    Console.WriteLine($"未知 Client1 API：{api}，输入 help 查看支持的命令。");
                }
            }
            else
            {
                Console.WriteLine($"未知目标：{target}，输入 help 查看可用目标。");
            }
        }

        private static void 显示帮助()
        {
            Console.WriteLine(@"
可用的命令（命令均以 'call' 开头，目标 + API + 参数）：

【调用 Service 的 API】
  call service add <a> <b>               - 加法
  call service subtract <a> <b>          - 减法
  call service multiply <a> <b>          - 乘法
  call service divide <a> <b>            - 除法
  call service echo <msg>                - 回显
  call service concat <str1> <str2>      - 连接两个字符串
  call service to_upper <str>            - 转大写
  call service to_lower <str>            - 转小写
  call service array_sum <n1 n2 ...>     - 整数数组求和
  call service array_avg <n1 n2 ...>     - 整数数组平均值
  call service get_time                  - 获取当前时间

【调用 Client2 的 API】
  call client2 reverse <msg>             - 反转字符串
  call client2 ping                      - 测试连通性
  call client2 uppercase <msg>           - 转大写

【调用自己的 API（本地调用）】
  call client1 echo <msg>                - 回显（本地）
  call client1 square <num>              - 计算平方（本地）
  call client1 greet <name>              - 问候（本地）

【系统命令】
  status                                 - 显示状态
  help                                   - 显示本帮助
  exit                                   - 退出程序

提示：字符串参数如果有空格，请用引号括起来（简化版未实现，建议用单词）。
");
        }

        // ================================================================
        // 4. 主程序
        // ================================================================
        static void Main()
        {
            Console.WriteLine("=== 🎉 API Hub 客户端1（C#）===");
            Console.WriteLine("你好！我是 Client1，我提供了三个 API：echo, square, greet。");
            Console.WriteLine("同时，我可以调用 Service 和 Client2 的 API。");
            Console.WriteLine("输入 'help' 查看所有命令，输入 'exit' 退出。");
            Console.WriteLine();

            // 1. 创建应用句柄
            _应用句柄 = API_Create_APPHnd("Client1", "客户端1 - 回声与平方服务");
            if (!_应用句柄.IsValid)
            {
                Console.WriteLine("❌ 创建应用失败。");
                return;
            }
            Console.WriteLine("✅ 应用句柄创建成功。");

            // 2. 注册自己的 API
            APICallDelegate 回显 = 自身回显回调;
            APICallDelegate 平方 = 自身平方回调;
            APICallDelegate 问候 = 自身问候回调;
            GCHandle.Alloc(回显); GCHandle.Alloc(平方); GCHandle.Alloc(问候);

            API_Reg_Call(_应用句柄, "client1_echo", "回显输入", IntPtr.Zero, 回显);
            API_Reg_Call(_应用句柄, "client1_square", "计算平方", IntPtr.Zero, 平方);
            API_Reg_Call(_应用句柄, "client1_greet", "问候语", IntPtr.Zero, 问候);
            Console.WriteLine("✅ 已注册自身 API：client1_echo, client1_square, client1_greet");

            // 3. 连接到服务（IPC）
            API_Reset_Prepare();
            API_Prepare_Client("ipc:demo_service", _应用句柄);

            Console.WriteLine("正在连接服务...");
            if (API_Prepare_Done() != 1)
            {
                Console.WriteLine("❌ 连接失败。错误信息请查看控制台输出。");
                API_Free_APPHnd(_应用句柄);
                API_shutdown();
                return;
            }
            Console.WriteLine("✅ 已连接到服务 ipc:demo_service");
            Console.WriteLine("现在你可以输入命令了！");

            // 4. 控制台输入线程
            Thread inputThread = new Thread(() =>
            {
                while (!_退出标志)
                {
                    Console.Write("Client1> ");
                    string line = Console.ReadLine();
                    if (line == null) continue;
                    处理命令(line);
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
            Console.WriteLine("Client1 正在关闭...");
            API_Exit_MainThread();
            API_Free_APPHnd(_应用句柄);
            API_shutdown();
            Console.WriteLine("Client1 已退出。再见！");
        }
    }
}