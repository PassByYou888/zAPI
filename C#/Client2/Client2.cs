/*
 * Client2.cs - API Hub 客户端2（全中文注释）
 * 
 * 嘿！我是 Client2，我提供了三个 API：reverse（反转）、ping（测试）、uppercase（转大写）。
 * 我可以调用 Service 的 API，也可以调用 Client1 的 API。
 * 
 * 我的命令集和 Client1 类似，但目标包含 client1。
 * 
 * 命令列表：
 *   call service add <a> <b>               - 调用 Service.add
 *   ... （同 Client1 的服务命令）
 *   call client1 echo <msg>                - 调用 Client1.echo
 *   call client1 square <num>              - 调用 Client1.square
 *   call client1 greet <name>              - 调用 Client1.greet
 *   call client2 reverse <msg>             - 本地调用自己的 reverse（测试）
 *   call client2 ping                      - 本地调用自己的 ping（测试）
 *   call client2 uppercase <msg>           - 本地调用自己的 uppercase（测试）
 *   status / help / exit
 * 
 * 快来和我交互吧！
 */

using System;
using System.Threading;
using System.Runtime.InteropServices;
using API_HubTool.Bindings;
using static API_HubTool.Bindings.API;

namespace Client2
{
    class Client2
    {
        private static volatile bool _退出标志 = false;
        private static AppHnd _应用句柄;

        // ================================================================
        // 1. 注册自己的 API
        // ================================================================

        /// <summary>
        /// client2_reverse：反转输入字符串
        /// </summary>
        private static void 自身反转回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            string str = ReadString(hInput);
            char[] chars = str.ToCharArray();
            Array.Reverse(chars);
            string reversed = new string(chars);
            WriteString(hOutput, reversed);
        }

        /// <summary>
        /// client2_ping：返回 “Pong！” 字符串
        /// </summary>
        private static void 自身Ping回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hOutput = new DataHnd { Handle = output };
            WriteString(hOutput, "Pong！来自 Client2 的响应");
        }

        /// <summary>
        /// client2_uppercase：将输入字符串转大写
        /// </summary>
        private static void 自身转大写回调(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            string str = ReadString(hInput);
            WriteString(hOutput, str.ToUpper());
        }

        // ================================================================
        // 2. 调用远程 API 的辅助函数
        // ================================================================

        // ---- 调用 Service 的 API（与 Client1 完全一样，此处省略重复代码，但为了完整性，全部复制一份）
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

        // ---- 调用 Client1 的 API ----
        private static void 调用Client1回显(string msg)
        {
            DataHnd data = API_Create_DataHnd("client1_echo");
            WriteString(data, msg);
            DataHnd result = API_Call("Client1", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid)
            {
                string echoed = ReadString(result);
                Console.WriteLine($"✅ Client1.echo 回复：{echoed}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Client1.echo 失败（Client1 可能未运行）。");
        }

        private static void 调用Client1平方(int n)
        {
            DataHnd data = API_Create_DataHnd("client1_square");
            API_WriteBuffer(data, BitConverter.GetBytes(n), 4);
            DataHnd result = API_Call("Client1", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid && API_GetSize(result) >= 4)
            {
                int square = BitConverter.ToInt32(ReadAllBytes(result), 0);
                Console.WriteLine($"✅ Client1.square({n}) = {square}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Client1.square 失败（Client1 可能未运行）。");
        }

        private static void 调用Client1问候(string name)
        {
            DataHnd data = API_Create_DataHnd("client1_greet");
            WriteString(data, name);
            DataHnd result = API_Call("Client1", data, 3000);
            API_Free_DataHnd(data);
            if (result.IsValid)
            {
                string greeting = ReadString(result);
                Console.WriteLine($"✅ Client1.greet 回复：{greeting}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ Client1.greet 失败（Client1 可能未运行）。");
        }

        // ---- 本地调用自己的 API ----
        private static void 本地调用自身反转(string msg)
        {
            DataHnd data = API_Create_DataHnd("client2_reverse");
            WriteString(data, msg);
            DataHnd result = API_Local_APP_Call(_应用句柄, data);
            API_Free_DataHnd(data);
            if (result.IsValid)
            {
                string reversed = ReadString(result);
                Console.WriteLine($"✅ 本地 client2_reverse 回复：{reversed}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ 本地 client2_reverse 失败。");
        }

        private static void 本地调用自身Ping()
        {
            DataHnd data = API_Create_DataHnd("client2_ping");
            DataHnd result = API_Local_APP_Call(_应用句柄, data);
            API_Free_DataHnd(data);
            if (result.IsValid)
            {
                string pong = ReadString(result);
                Console.WriteLine($"✅ 本地 client2_ping 回复：{pong}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ 本地 client2_ping 失败。");
        }

        private static void 本地调用自身转大写(string msg)
        {
            DataHnd data = API_Create_DataHnd("client2_uppercase");
            WriteString(data, msg);
            DataHnd result = API_Local_APP_Call(_应用句柄, data);
            API_Free_DataHnd(data);
            if (result.IsValid)
            {
                string upper = ReadString(result);
                Console.WriteLine($"✅ 本地 client2_uppercase 回复：{upper}");
                API_Free_DataHnd(result);
            }
            else Console.WriteLine("❌ 本地 client2_uppercase 失败。");
        }

        // ================================================================
        // 3. 命令解析
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
                Console.WriteLine("Client2 运行中，已注册 API: client2_reverse, client2_ping, client2_uppercase");
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
                // 与 Client1 完全一样的服务调用，此处复制所有分支
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
                    string s1 = parts[3];
                    string s2 = parts[4];
                    调用服务连接(s1, s2);
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
            else if (target == "client1")
            {
                if (api == "echo" && parts.Length >= 4)
                {
                    string msg = string.Join(" ", parts, 3, parts.Length - 3);
                    调用Client1回显(msg);
                }
                else if (api == "square" && parts.Length == 4)
                {
                    int n = int.Parse(parts[3]);
                    调用Client1平方(n);
                }
                else if (api == "greet" && parts.Length >= 4)
                {
                    string name = string.Join(" ", parts, 3, parts.Length - 3);
                    调用Client1问候(name);
                }
                else
                {
                    Console.WriteLine($"未知 Client1 API：{api}，输入 help 查看支持的命令。");
                }
            }
            else if (target == "client2")
            {
                // 本地调用自己的 API
                if (api == "reverse" && parts.Length >= 4)
                {
                    string msg = string.Join(" ", parts, 3, parts.Length - 3);
                    本地调用自身反转(msg);
                }
                else if (api == "ping" && parts.Length == 3)
                {
                    本地调用自身Ping();
                }
                else if (api == "uppercase" && parts.Length >= 4)
                {
                    string msg = string.Join(" ", parts, 3, parts.Length - 3);
                    本地调用自身转大写(msg);
                }
                else
                {
                    Console.WriteLine($"未知 Client2 API：{api}，输入 help 查看支持的命令。");
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

【调用 Client1 的 API】
  call client1 echo <msg>                - 回显
  call client1 square <num>              - 计算平方
  call client1 greet <name>              - 问候

【调用自己的 API（本地调用）】
  call client2 reverse <msg>             - 反转字符串（本地）
  call client2 ping                      - 测试连通性（本地）
  call client2 uppercase <msg>           - 转大写（本地）

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
            Console.WriteLine("=== 🎉 API Hub 客户端2（C#）===");
            Console.WriteLine("你好！我是 Client2，我提供了三个 API：reverse, ping, uppercase。");
            Console.WriteLine("同时，我可以调用 Service 和 Client1 的 API。");
            Console.WriteLine("输入 'help' 查看所有命令，输入 'exit' 退出。");
            Console.WriteLine();

            // 1. 创建应用句柄
            _应用句柄 = API_Create_APPHnd("Client2", "客户端2 - 反转与Ping服务");
            if (!_应用句柄.IsValid)
            {
                Console.WriteLine("❌ 创建应用失败。");
                return;
            }
            Console.WriteLine("✅ 应用句柄创建成功。");

            // 2. 注册自己的 API
            APICallDelegate 反转 = 自身反转回调;
            APICallDelegate 平 = 自身Ping回调;
            APICallDelegate 大写 = 自身转大写回调;
            GCHandle.Alloc(反转); GCHandle.Alloc(平); GCHandle.Alloc(大写);

            API_Reg_Call(_应用句柄, "client2_reverse", "反转字符串", IntPtr.Zero, 反转);
            API_Reg_Call(_应用句柄, "client2_ping", "测试连通性", IntPtr.Zero, 平);
            API_Reg_Call(_应用句柄, "client2_uppercase", "转大写", IntPtr.Zero, 大写);
            Console.WriteLine("✅ 已注册自身 API：client2_reverse, client2_ping, client2_uppercase");

            // 3. 连接到服务
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

            // 4. 输入线程
            Thread inputThread = new Thread(() =>
            {
                while (!_退出标志)
                {
                    Console.Write("Client2> ");
                    string line = Console.ReadLine();
                    if (line == null) continue;
                    处理命令(line);
                }
            });
            inputThread.Start();

            // 5. 主循环——状态消息已由库输出到控制台，无需额外处理
            while (!_退出标志)
            {
                // 简单等待，不阻塞CPU
                Thread.Sleep(100);
            }

            // 6. 清理
            inputThread.Join();
            Console.WriteLine("Client2 正在关闭...");
            API_Exit_MainThread();
            API_Free_APPHnd(_应用句柄);
            API_shutdown();
            Console.WriteLine("Client2 已退出。再见！");
        }
    }
}