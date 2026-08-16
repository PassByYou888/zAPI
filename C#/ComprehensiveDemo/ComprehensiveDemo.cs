/*
 * ComprehensiveDemo.cs - 综合演示程序，全面展示 API Hub 框架的各种功能。
 *
 * 本程序模拟了一个真实业务系统，注册了多种类型的 API，包括：
 * - 用户管理（注册、查询）
 * - 订单管理（创建、查询状态）
 * - 文件操作（上传、下载）
 * - 数据统计（获取统计信息）
 * - 工具类（计算平均值、字符串连接、获取服务器时间、回显、反转）
 * - 通知（日志记录、打印）
 *
 * 程序同时作为服务端和客户端，通过 TCP 自调用，演示了：
 * - 远程调用（带超时）
 * - 本地调用
 * - 通知发送
 * - 多种数据类型的序列化（整数、字符串、字节数组、结构化数据）
 * - 错误处理和状态信息输出
 *
 * 所有注释和输出消息均为中文，便于初学者快速理解。
 */

using System;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;
using API_HubTool.Bindings;
using static API_HubTool.Bindings.API;

#pragma warning disable 0649 // 忽略结构体字段未赋值警告（仅用于序列化模板）

namespace ComprehensiveDemo
{
    /// <summary>
    /// 定义一个简单的点结构，用于演示结构体序列化
    /// </summary>
    struct Point
    {
        public int x, y;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string label;
    }

    /// <summary>
    /// 用户信息结构（用于用户注册和查询）
    /// </summary>
    struct UserInfo
    {
        public int id;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string name;
        public int age;
    }

    /// <summary>
    /// 订单信息结构（用于创建订单和查询状态）
    /// </summary>
    struct OrderInfo
    {
        public int orderId;
        public double amount;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 16)]
        public string status; // "待处理", "已发货", "已送达"
    }

    class ComprehensiveDemo
    {
        // ---- 所有 API 回调函数 ----

        /// <summary>
        /// 加法：读取两个整数，返回它们的和
        /// </summary>
        private static void AddCallback(IntPtr trigger, IntPtr input, IntPtr output)
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
        /// 反转字符串：输入字符串，返回反转后的结果
        /// </summary>
        private static void ReverseCallback(IntPtr trigger, IntPtr input, IntPtr output)
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
        /// 变换点：交换点的 x 和 y 坐标，并在标签前添加 "已变换 "
        /// </summary>
        private static void TransformPointCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] buf = ReadAllBytes(hInput);
            if (buf.Length < 4 + 4 + 32) return;
            int x = BitConverter.ToInt32(buf, 0);
            int y = BitConverter.ToInt32(buf, 4);
            string label = Encoding.UTF8.GetString(buf, 8, 32).TrimEnd('\0');
            // 交换坐标
            int tmp = x; x = y; y = tmp;
            label = "已变换 " + label;
            // 写回序列化结构
            byte[] outBuf = new byte[4 + 4 + 32];
            BitConverter.GetBytes(x).CopyTo(outBuf, 0);
            BitConverter.GetBytes(y).CopyTo(outBuf, 4);
            byte[] labelBytes = Encoding.UTF8.GetBytes(label.PadRight(32, '\0'));
            Array.Copy(labelBytes, 0, outBuf, 8, 32);
            API_WriteBuffer(hOutput, outBuf, outBuf.Length);
        }

        /// <summary>
        /// 回显：原样返回输入的数据（二进制）
        /// </summary>
        private static void EchoCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] data = ReadAllBytes(hInput);
            API_WriteBuffer(hOutput, data, data.Length);
        }

        /// <summary>
        /// 打印通知：接收一个字符串，输出到控制台
        /// </summary>
        private static void PrintNotifyCallback(IntPtr trigger, IntPtr input)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            string msg = ReadString(hInput);
            Console.WriteLine($"[通知] 收到打印消息: {msg}");
        }

        // ---- 新增 API 回调（模拟业务功能） ----

        /// <summary>
        /// 用户注册：接收 UserInfo 结构，返回注册成功后的用户 ID（模拟）
        /// </summary>
        private static void RegisterUserCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] buf = ReadAllBytes(hInput);
            if (buf.Length < 4 + 32 + 4) return; // id+name+age
            int id = BitConverter.ToInt32(buf, 0);
            string name = Encoding.UTF8.GetString(buf, 4, 32).TrimEnd('\0');
            int age = BitConverter.ToInt32(buf, 36);
            // 模拟注册：打印信息，返回相同的 id（表示成功）
            Console.WriteLine($"[模拟] 注册用户: ID={id}, 姓名={name}, 年龄={age}");
            // 返回成功码（这里返回 id 表示成功）
            API_WriteBuffer(hOutput, BitConverter.GetBytes(id), 4);
        }

        /// <summary>
        /// 用户查询：接收用户 ID，返回对应的 UserInfo（模拟）
        /// </summary>
        private static void GetUserInfoCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] buf = ReadAllBytes(hInput);
            if (buf.Length < 4) return;
            int id = BitConverter.ToInt32(buf, 0);
            // 模拟查询，构造一个虚拟用户
            UserInfo user = new UserInfo
            {
                id = id,
                name = "张三",
                age = 25
            };
            // 序列化为字节数组（简化：固定大小）
            byte[] outBuf = new byte[4 + 32 + 4];
            BitConverter.GetBytes(user.id).CopyTo(outBuf, 0);
            byte[] nameBytes = Encoding.UTF8.GetBytes(user.name.PadRight(32, '\0'));
            Array.Copy(nameBytes, 0, outBuf, 4, 32);
            BitConverter.GetBytes(user.age).CopyTo(outBuf, 36);
            API_WriteBuffer(hOutput, outBuf, outBuf.Length);
        }

        /// <summary>
        /// 创建订单：接收 OrderInfo，返回创建后的订单 ID（模拟）
        /// </summary>
        private static void CreateOrderCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] buf = ReadAllBytes(hInput);
            if (buf.Length < 4 + 8 + 16) return;
            int orderId = BitConverter.ToInt32(buf, 0);
            double amount = BitConverter.ToDouble(buf, 4);
            string status = Encoding.UTF8.GetString(buf, 12, 16).TrimEnd('\0');
            Console.WriteLine($"[模拟] 创建订单: ID={orderId}, 金额={amount}, 状态={status}");
            // 返回订单 ID（模拟创建成功）
            API_WriteBuffer(hOutput, BitConverter.GetBytes(orderId), 4);
        }

        /// <summary>
        /// 查询订单状态：接收订单 ID，返回 OrderInfo（模拟）
        /// </summary>
        private static void GetOrderStatusCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] buf = ReadAllBytes(hInput);
            if (buf.Length < 4) return;
            int orderId = BitConverter.ToInt32(buf, 0);
            // 模拟查询
            OrderInfo order = new OrderInfo
            {
                orderId = orderId,
                amount = 99.99,
                status = "已发货"
            };
            byte[] outBuf = new byte[4 + 8 + 16];
            BitConverter.GetBytes(order.orderId).CopyTo(outBuf, 0);
            BitConverter.GetBytes(order.amount).CopyTo(outBuf, 4);
            byte[] statusBytes = Encoding.UTF8.GetBytes(order.status.PadRight(16, '\0'));
            Array.Copy(statusBytes, 0, outBuf, 12, 16);
            API_WriteBuffer(hOutput, outBuf, outBuf.Length);
        }

        /// <summary>
        /// 上传文件：接收文件名（字符串）和文件内容（字节数组），返回上传状态（0失败，1成功）
        /// </summary>
        private static void UploadFileCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            // 简单的序列化：先读取文件名（以 null 结尾），再读取剩余字节作为内容
            byte[] all = ReadAllBytes(hInput);
            int nameEnd = Array.IndexOf(all, (byte)0);
            if (nameEnd < 0) return;
            string fileName = Encoding.UTF8.GetString(all, 0, nameEnd);
            byte[] content = new byte[all.Length - nameEnd - 1];
            Array.Copy(all, nameEnd + 1, content, 0, content.Length);
            Console.WriteLine($"[模拟] 上传文件: {fileName}, 大小={content.Length} 字节");
            // 模拟成功
            int success = 1;
            API_WriteBuffer(hOutput, BitConverter.GetBytes(success), 4);
        }

        /// <summary>
        /// 下载文件：接收文件名，返回文件内容（模拟）
        /// </summary>
        private static void DownloadFileCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            string fileName = ReadString(hInput);
            Console.WriteLine($"[模拟] 下载文件: {fileName}");
            // 模拟返回一些内容
            byte[] content = Encoding.UTF8.GetBytes($"这是文件 {fileName} 的内容");
            API_WriteBuffer(hOutput, content, content.Length);
        }

        /// <summary>
        /// 获取统计数据：无输入，返回一个包含统计信息的字符串（模拟）
        /// </summary>
        private static void GetStatisticsCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hOutput = new DataHnd { Handle = output };
            string stats = "总用户数: 100, 总订单数: 200, 在线用户: 15";
            WriteString(hOutput, stats);
        }

        /// <summary>
        /// 计算平均值：接收一个 double 数组（字节流），返回平均值
        /// </summary>
        private static void AverageCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            byte[] data = ReadAllBytes(hInput);
            if (data.Length < 8) return;
            // 简单格式：前4字节为元素个数，后面是 double 数组
            int count = BitConverter.ToInt32(data, 0);
            if (count == 0) { API_WriteBuffer(hOutput, BitConverter.GetBytes(0.0), 8); return; }
            double sum = 0;
            for (int i = 0; i < count; i++)
            {
                double val = BitConverter.ToDouble(data, 4 + i * 8);
                sum += val;
            }
            double avg = sum / count;
            API_WriteBuffer(hOutput, BitConverter.GetBytes(avg), 8);
        }

        /// <summary>
        /// 字符串连接：接收两个字符串，返回连接后的结果
        /// </summary>
        private static void ConcatCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };
            // 简单格式：两个字符串以 null 分隔
            byte[] all = ReadAllBytes(hInput);
            int sep = Array.IndexOf(all, (byte)0);
            if (sep < 0) return;
            string s1 = Encoding.UTF8.GetString(all, 0, sep);
            string s2 = Encoding.UTF8.GetString(all, sep + 1, all.Length - sep - 1);
            string result = s1 + s2;
            WriteString(hOutput, result);
        }

        /// <summary>
        /// 获取服务器时间：返回当前时间字符串
        /// </summary>
        private static void GetServerTimeCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            DataHnd hOutput = new DataHnd { Handle = output };
            string now = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
            WriteString(hOutput, now);
        }

        /// <summary>
        /// 日志记录通知：接收日志消息并输出到控制台（模拟写入日志文件）
        /// </summary>
        private static void LogNotifyCallback(IntPtr trigger, IntPtr input)
        {
            DataHnd hInput = new DataHnd { Handle = input };
            string msg = ReadString(hInput);
            Console.WriteLine($"[日志] {DateTime.Now:yyyy-MM-dd HH:mm:ss} - {msg}");
        }

        // ---- 辅助函数：打印状态消息（已移除，改用控制台） ----
        private static void PrintStatus()
        {
            // 状态信息由库自动输出到控制台，无需额外处理
        }

        static void Main()
        {
            Console.WriteLine("=== API Hub 综合演示（C#）===");

            // 1. 创建应用句柄
            AppHnd app = API_Create_APPHnd("DemoApp", "综合演示应用");
            if (!app.IsValid)
            {
                Console.WriteLine("创建应用失败。");
                return;
            }

            // 2. 注册所有 API（共 14 个）
            // 委托变量，防止被 GC 回收
            APICallDelegate addDel = AddCallback;
            APICallDelegate revDel = ReverseCallback;
            APICallDelegate transDel = TransformPointCallback;
            APICallDelegate echoDel = EchoCallback;
            APICallDelegate regUserDel = RegisterUserCallback;
            APICallDelegate getUserDel = GetUserInfoCallback;
            APICallDelegate createOrderDel = CreateOrderCallback;
            APICallDelegate getOrderDel = GetOrderStatusCallback;
            APICallDelegate uploadDel = UploadFileCallback;
            APICallDelegate downloadDel = DownloadFileCallback;
            APICallDelegate statsDel = GetStatisticsCallback;
            APICallDelegate avgDel = AverageCallback;
            APICallDelegate concatDel = ConcatCallback;
            APICallDelegate timeDel = GetServerTimeCallback;
            APINotifyDelegate printDel = PrintNotifyCallback;
            APINotifyDelegate logDel = LogNotifyCallback;

            // 固定委托（防止 GC）
            GCHandle.Alloc(addDel);
            GCHandle.Alloc(revDel);
            GCHandle.Alloc(transDel);
            GCHandle.Alloc(echoDel);
            GCHandle.Alloc(regUserDel);
            GCHandle.Alloc(getUserDel);
            GCHandle.Alloc(createOrderDel);
            GCHandle.Alloc(getOrderDel);
            GCHandle.Alloc(uploadDel);
            GCHandle.Alloc(downloadDel);
            GCHandle.Alloc(statsDel);
            GCHandle.Alloc(avgDel);
            GCHandle.Alloc(concatDel);
            GCHandle.Alloc(timeDel);
            GCHandle.Alloc(printDel);
            GCHandle.Alloc(logDel);

            // 注册 Call 类型 API
            API_Reg_Call(app, "add", "整数加法", IntPtr.Zero, addDel);
            API_Reg_Call(app, "reverse", "反转字符串", IntPtr.Zero, revDel);
            API_Reg_Call(app, "transform", "变换点坐标", IntPtr.Zero, transDel);
            API_Reg_Call(app, "echo", "二进制回显", IntPtr.Zero, echoDel);
            API_Reg_Call(app, "register_user", "用户注册", IntPtr.Zero, regUserDel);
            API_Reg_Call(app, "get_user", "获取用户信息", IntPtr.Zero, getUserDel);
            API_Reg_Call(app, "create_order", "创建订单", IntPtr.Zero, createOrderDel);
            API_Reg_Call(app, "get_order_status", "查询订单状态", IntPtr.Zero, getOrderDel);
            API_Reg_Call(app, "upload_file", "上传文件", IntPtr.Zero, uploadDel);
            API_Reg_Call(app, "download_file", "下载文件", IntPtr.Zero, downloadDel);
            API_Reg_Call(app, "get_stats", "获取统计数据", IntPtr.Zero, statsDel);
            API_Reg_Call(app, "average", "计算平均值", IntPtr.Zero, avgDel);
            API_Reg_Call(app, "concat", "字符串连接", IntPtr.Zero, concatDel);
            API_Reg_Call(app, "get_time", "获取服务器时间", IntPtr.Zero, timeDel);

            // 注册 Notify 类型 API
            API_Reg_Notify(app, "print", "打印通知", IntPtr.Zero, printDel);
            API_Reg_Notify(app, "log", "日志记录", IntPtr.Zero, logDel);

            Console.WriteLine("已注册所有 API（共 14 个 Call API + 2 个 Notify API）。");

            // 3. 网络准备（TCP 自连接）
            API_Reset_Prepare();
            API_Prepare_Service("127.0.0.1", "127.0.0.1:9898");
            API_Prepare_Client("127.0.0.1:9898", app);

            if (API_Prepare_Done() != 1)
            {
                Console.WriteLine("框架启动失败。错误信息请查看控制台输出。");
                API_Free_APPHnd(app);
                API_shutdown();
                return;
            }
            Console.WriteLine("框架已启动。等待 1.5 秒让服务注册...");
            Thread.Sleep(1500);

            // ============================================================
            // 远程调用演示（全部调用自己的 API）
            // ============================================================
            Console.WriteLine("\n=== 远程调用演示 ===");

            // 1. 加法
            DataHnd data = API_Create_DataHnd("add");
            try
            {
                byte[] payload = new byte[8];
                BitConverter.GetBytes(100).CopyTo(payload, 0);
                BitConverter.GetBytes(200).CopyTo(payload, 4);
                API_WriteBuffer(data, payload, 8);
                DataHnd result = API_Call("DemoApp", data, 10000);
                API_Free_DataHnd(data); // 释放输入
                data = DataHnd.Null;    // 防止重复释放
                if (result.IsValid && API_GetSize(result) >= 4)
                {
                    int sum = BitConverter.ToInt32(ReadAllBytes(result), 0);
                    Console.WriteLine($"加法(100,200) = {sum}");
                    API_Free_DataHnd(result);
                }
                else Console.WriteLine("加法调用失败或超时。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            // 2. 反转字符串
            data = API_Create_DataHnd("reverse");
            try
            {
                WriteString(data, "Hello World!");
                DataHnd result = API_Call("DemoApp", data, 10000);
                API_Free_DataHnd(data);
                data = DataHnd.Null;
                if (result.IsValid)
                {
                    string reversed = ReadString(result);
                    Console.WriteLine($"反转('Hello World!') = '{reversed}'");
                    API_Free_DataHnd(result);
                }
                else Console.WriteLine("反转调用失败。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            // 3. 变换点
            data = API_Create_DataHnd("transform");
            try
            {
                byte[] ptBuf = new byte[4 + 4 + 32];
                BitConverter.GetBytes(10).CopyTo(ptBuf, 0);
                BitConverter.GetBytes(20).CopyTo(ptBuf, 4);
                byte[] lbl = Encoding.UTF8.GetBytes("Original\0");
                Array.Copy(lbl, 0, ptBuf, 8, Math.Min(lbl.Length, 32));
                API_WriteBuffer(data, ptBuf, ptBuf.Length);
                DataHnd result = API_Call("DemoApp", data, 10000);
                API_Free_DataHnd(data);
                data = DataHnd.Null;
                if (result.IsValid && API_GetSize(result) >= 4 + 4 + 32)
                {
                    byte[] outBuf = ReadAllBytes(result);
                    int x = BitConverter.ToInt32(outBuf, 0);
                    int y = BitConverter.ToInt32(outBuf, 4);
                    string label = Encoding.UTF8.GetString(outBuf, 8, 32).TrimEnd('\0');
                    Console.WriteLine($"变换点(10,20,'Original') -> ({x},{y},'{label}')");
                    API_Free_DataHnd(result);
                }
                else Console.WriteLine("变换点调用失败。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            // 4. 回显二进制
            data = API_Create_DataHnd("echo");
            try
            {
                byte[] echoData = { 1, 2, 3, 4, 5 };
                API_WriteBuffer(data, echoData, echoData.Length);
                DataHnd result = API_Call("DemoApp", data, 10000);
                API_Free_DataHnd(data);
                data = DataHnd.Null;
                if (result.IsValid && API_GetSize(result) == echoData.Length)
                {
                    byte[] echoed = ReadAllBytes(result);
                    Console.WriteLine($"回显([1,2,3,4,5]) -> [{string.Join(",", echoed)}]");
                    API_Free_DataHnd(result);
                }
                else Console.WriteLine("回显调用失败。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            // 5. 用户注册
            data = API_Create_DataHnd("register_user");
            try
            {
                UserInfo user = new UserInfo { id = 123, name = "李四", age = 30 };
                byte[] buf = new byte[4 + 32 + 4];
                BitConverter.GetBytes(user.id).CopyTo(buf, 0);
                byte[] nameBytes = Encoding.UTF8.GetBytes(user.name.PadRight(32, '\0'));
                Array.Copy(nameBytes, 0, buf, 4, 32);
                BitConverter.GetBytes(user.age).CopyTo(buf, 36);
                API_WriteBuffer(data, buf, buf.Length);
                DataHnd result = API_Call("DemoApp", data, 10000);
                API_Free_DataHnd(data);
                data = DataHnd.Null;
                if (result.IsValid && API_GetSize(result) >= 4)
                {
                    int returnedId = BitConverter.ToInt32(ReadAllBytes(result), 0);
                    Console.WriteLine($"用户注册返回 ID: {returnedId}");
                    API_Free_DataHnd(result);
                }
                else Console.WriteLine("用户注册失败。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            // 6. 用户查询
            data = API_Create_DataHnd("get_user");
            try
            {
                API_WriteBuffer(data, BitConverter.GetBytes(123), 4);
                DataHnd result = API_Call("DemoApp", data, 10000);
                API_Free_DataHnd(data);
                data = DataHnd.Null;
                if (result.IsValid && API_GetSize(result) >= 4 + 32 + 4)
                {
                    byte[] outBuf = ReadAllBytes(result);
                    int id = BitConverter.ToInt32(outBuf, 0);
                    string name = Encoding.UTF8.GetString(outBuf, 4, 32).TrimEnd('\0');
                    int age = BitConverter.ToInt32(outBuf, 36);
                    Console.WriteLine($"查询用户: ID={id}, 姓名={name}, 年龄={age}");
                    API_Free_DataHnd(result);
                }
                else Console.WriteLine("用户查询失败。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            // 7. 创建订单
            data = API_Create_DataHnd("create_order");
            try
            {
                OrderInfo order = new OrderInfo { orderId = 1001, amount = 199.99, status = "待处理" };
                byte[] buf = new byte[4 + 8 + 16];
                BitConverter.GetBytes(order.orderId).CopyTo(buf, 0);
                BitConverter.GetBytes(order.amount).CopyTo(buf, 4);
                byte[] statusBytes = Encoding.UTF8.GetBytes(order.status.PadRight(16, '\0'));
                Array.Copy(statusBytes, 0, buf, 12, 16);
                API_WriteBuffer(data, buf, buf.Length);
                DataHnd result = API_Call("DemoApp", data, 10000);
                API_Free_DataHnd(data);
                data = DataHnd.Null;
                if (result.IsValid && API_GetSize(result) >= 4)
                {
                    int orderId = BitConverter.ToInt32(ReadAllBytes(result), 0);
                    Console.WriteLine($"创建订单返回 ID: {orderId}");
                    API_Free_DataHnd(result);
                }
                else Console.WriteLine("创建订单失败。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            // 8. 查询订单状态
            data = API_Create_DataHnd("get_order_status");
            try
            {
                API_WriteBuffer(data, BitConverter.GetBytes(1001), 4);
                DataHnd result = API_Call("DemoApp", data, 10000);
                API_Free_DataHnd(data);
                data = DataHnd.Null;
                if (result.IsValid && API_GetSize(result) >= 4 + 8 + 16)
                {
                    byte[] outBuf = ReadAllBytes(result);
                    int oid = BitConverter.ToInt32(outBuf, 0);
                    double amt = BitConverter.ToDouble(outBuf, 4);
                    string status = Encoding.UTF8.GetString(outBuf, 12, 16).TrimEnd('\0');
                    Console.WriteLine($"订单状态: ID={oid}, 金额={amt:F2}, 状态={status}");
                    API_Free_DataHnd(result);
                }
                else Console.WriteLine("查询订单状态失败。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            // 9. 上传文件
            data = API_Create_DataHnd("upload_file");
            try
            {
                string fileName = "report.txt";
                byte[] content = Encoding.UTF8.GetBytes("这是文件内容...");
                // 构造载荷：文件名 + null + 文件内容
                byte[] nameBytes = Encoding.UTF8.GetBytes(fileName + "\0");
                byte[] payload = new byte[nameBytes.Length + content.Length];
                Array.Copy(nameBytes, 0, payload, 0, nameBytes.Length);
                Array.Copy(content, 0, payload, nameBytes.Length, content.Length);
                API_WriteBuffer(data, payload, payload.Length);
                DataHnd result = API_Call("DemoApp", data, 10000);
                API_Free_DataHnd(data);
                data = DataHnd.Null;
                if (result.IsValid && API_GetSize(result) >= 4)
                {
                    int success = BitConverter.ToInt32(ReadAllBytes(result), 0);
                    Console.WriteLine($"上传文件结果: {(success == 1 ? "成功" : "失败")}");
                    API_Free_DataHnd(result);
                }
                else Console.WriteLine("上传文件失败。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            // 10. 下载文件
            data = API_Create_DataHnd("download_file");
            try
            {
                WriteString(data, "report.txt");
                DataHnd result = API_Call("DemoApp", data, 10000);
                API_Free_DataHnd(data);
                data = DataHnd.Null;
                if (result.IsValid)
                {
                    string content = ReadString(result);
                    Console.WriteLine($"下载文件内容: {content}");
                    API_Free_DataHnd(result);
                }
                else Console.WriteLine("下载文件失败。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            // 11. 获取统计数据
            data = API_Create_DataHnd("get_stats");
            try
            {
                // 无输入参数
                DataHnd result = API_Call("DemoApp", data, 10000);
                API_Free_DataHnd(data);
                data = DataHnd.Null;
                if (result.IsValid)
                {
                    string stats = ReadString(result);
                    Console.WriteLine($"统计数据: {stats}");
                    API_Free_DataHnd(result);
                }
                else Console.WriteLine("获取统计数据失败。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            // 12. 计算平均值
            data = API_Create_DataHnd("average");
            try
            {
                double[] numbers = { 10.5, 20.3, 30.7, 40.2 };
                int count = numbers.Length;
                byte[] payload = new byte[4 + count * 8];
                BitConverter.GetBytes(count).CopyTo(payload, 0);
                for (int i = 0; i < count; i++)
                    BitConverter.GetBytes(numbers[i]).CopyTo(payload, 4 + i * 8);
                API_WriteBuffer(data, payload, payload.Length);
                DataHnd result = API_Call("DemoApp", data, 10000);
                API_Free_DataHnd(data);
                data = DataHnd.Null;
                if (result.IsValid && API_GetSize(result) >= 8)
                {
                    double avg = BitConverter.ToDouble(ReadAllBytes(result), 0);
                    Console.WriteLine($"平均值({string.Join(",", numbers)}) = {avg:F2}");
                    API_Free_DataHnd(result);
                }
                else Console.WriteLine("计算平均值失败。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            // 13. 字符串连接
            data = API_Create_DataHnd("concat");
            try
            {
                string s1 = "Hello, ";
                string s2 = "World!";
                byte[] payload = new byte[s1.Length + s2.Length + 2]; // 两个 null 分隔
                byte[] b1 = Encoding.UTF8.GetBytes(s1 + "\0");
                byte[] b2 = Encoding.UTF8.GetBytes(s2 + "\0");
                Array.Copy(b1, 0, payload, 0, b1.Length);
                Array.Copy(b2, 0, payload, b1.Length, b2.Length);
                API_WriteBuffer(data, payload, payload.Length);
                DataHnd result = API_Call("DemoApp", data, 10000);
                API_Free_DataHnd(data);
                data = DataHnd.Null;
                if (result.IsValid)
                {
                    string concat = ReadString(result);
                    Console.WriteLine($"连接('{s1}', '{s2}') = '{concat}'");
                    API_Free_DataHnd(result);
                }
                else Console.WriteLine("字符串连接失败。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            // 14. 获取服务器时间
            data = API_Create_DataHnd("get_time");
            try
            {
                DataHnd result = API_Call("DemoApp", data, 10000);
                API_Free_DataHnd(data);
                data = DataHnd.Null;
                if (result.IsValid)
                {
                    string time = ReadString(result);
                    Console.WriteLine($"服务器时间: {time}");
                    API_Free_DataHnd(result);
                }
                else Console.WriteLine("获取时间失败。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            // ---- 通知演示 ----
            Console.WriteLine("\n=== 通知演示 ===");
            data = API_Create_DataHnd("print");
            try
            {
                WriteString(data, "这是打印通知消息！");
                API_Notify("DemoApp", data);
                API_Free_DataHnd(data);
                data = DataHnd.Null;
                Console.WriteLine("已发送打印通知。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            data = API_Create_DataHnd("log");
            try
            {
                WriteString(data, "用户登录成功");
                API_Notify("DemoApp", data);
                API_Free_DataHnd(data);
                data = DataHnd.Null;
                Console.WriteLine("已发送日志通知。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            // ---- 本地调用演示 ----
            Console.WriteLine("\n=== 本地调用演示 ===");
            data = API_Create_DataHnd("add");
            try
            {
                byte[] localPayload = new byte[8];
                BitConverter.GetBytes(5).CopyTo(localPayload, 0);
                BitConverter.GetBytes(7).CopyTo(localPayload, 4);
                API_WriteBuffer(data, localPayload, 8);
                DataHnd result = API_Local_APP_Call(app, data);
                API_Free_DataHnd(data);
                data = DataHnd.Null;
                if (result.IsValid)
                {
                    int sum = BitConverter.ToInt32(ReadAllBytes(result), 0);
                    Console.WriteLine($"本地加法(5,7) = {sum}");
                    API_Free_DataHnd(result);
                }
                else Console.WriteLine("本地加法失败。");
            }
            finally
            {
                if (data.IsValid) API_Free_DataHnd(data);
            }

            // ---- 输出状态日志（已由控制台输出） ----
            Console.WriteLine("\n=== 状态日志 ===");
            Console.WriteLine("状态信息已由库输出到控制台。");

            // ---- 清理关闭 ----
            Console.WriteLine("\n正在关闭...");
            API_Exit_MainThread();
            API_Free_APPHnd(app);
            API_shutdown();
            Console.WriteLine("演示结束。");
        }
    }
}
#pragma warning restore 0649