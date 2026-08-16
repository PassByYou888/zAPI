/*
 * HelloWorld.cs - 超级简单的 API Hub 入门教程（全中文）
 *
 * 嘿，你好！欢迎来到 API Hub 的世界！
 * 这个程序是你能写的最简短的 API Hub 程序。
 * 它就像编程界的 "Hello World"，但更酷 —— 因为它能让你在本地调用自己的 API！
 *
 * 我们只做了 4 件小事：
 * 1. 创建了一个应用（就像开了一家小店）
 * 2. 注册了一个 "加法" 服务（告诉别人我们能算加法）
 * 3. 在本地调用了一次加法（自己给自己算 5+7）
 * 4. 打扫卫生，关门打烊
 *
 * 全程没有网络，全在电脑内部完成，超级安全、简单！
 * 看完这段代码，你就已经学会 API Hub 最核心的用法了。
 * 准备好了吗？让我们开始吧！
 */

using System;
using System.Runtime.InteropServices;
using API_HubTool.Bindings;
using static API_HubTool.Bindings.API;

namespace HelloWorld
{
    class HelloWorld
    {
        // ============================================================
        // 第一步：定义你的 API 服务（回调函数）
        // 这个函数就是你的 "加法计算器"。
        // 它从 input 里读取两个整数，算出和，然后写入 output。
        // ============================================================
        private static void AddCallback(IntPtr trigger, IntPtr input, IntPtr output)
        {
            // 把 C 指针转换成我们熟悉的 C# 句柄
            DataHnd hInput = new DataHnd { Handle = input };
            DataHnd hOutput = new DataHnd { Handle = output };

            // 读取两个 4 字节整数（总共 8 字节）
            byte[] buffer = new byte[8];
            long read = API_ReadBuffer(hInput, buffer, 8);
            if (read != 8) return;  // 防呆：数据不对就退出

            int a = BitConverter.ToInt32(buffer, 0);
            int b = BitConverter.ToInt32(buffer, 4);

            // 计算和
            int sum = a + b;
            byte[] result = BitConverter.GetBytes(sum);

            // 把结果写回去（只要 4 字节）
            API_WriteBuffer(hOutput, result, 4);
        }

        // ============================================================
        // 第二步：主程序 —— 你要做的一切就在这里
        // ============================================================
        static void Main(string[] args)
        {
            Console.WriteLine("=== 🚀 API Hub Hello World（超简单入门）===");
            Console.WriteLine("我们来做一个加法计算器吧！");

            // 1. 创建你的应用（相当于注册一家公司）
            AppHnd app = API_Create_APPHnd("HelloApp", "我的第一个 API Hub 应用");
            Console.WriteLine("✅ 应用已创建！");

            // 2. 注册你的加法服务（告诉框架：当有人叫 "add" 时，就调用 AddCallback）
            APICallDelegate addDelegate = AddCallback;
            GCHandle.Alloc(addDelegate); // 这句话是保护你的回调不被 GC 回收，记住就行
            if (API_Reg_Call(app, "add", "加法服务", IntPtr.Zero, addDelegate) == 1)
                Console.WriteLine("✅ 已注册 'add' 服务！");
            else
                Console.WriteLine("❌ 注册失败，检查一下名字有没有重复？");

            // 3. 现在，我们来调用这个服务（本地调用，不需要网络）
            //    就像在内部打了个电话给 "add" 部门，说："帮我算 5+7"
            DataHnd data = API_Create_DataHnd("add");
            byte[] payload = new byte[8];
            BitConverter.GetBytes(5).CopyTo(payload, 0);
            BitConverter.GetBytes(7).CopyTo(payload, 4);
            API_WriteBuffer(data, payload, 8);

            // 拨号呼叫！
            DataHnd result = API_Local_APP_Call(app, data);
            API_Free_DataHnd(data);  // 用完输入数据要释放（好习惯）

            // 检查结果
            if (result.IsValid && API_GetSize(result) >= 4)
            {
                byte[] resBuf = ReadAllBytes(result);
                int sum = BitConverter.ToInt32(resBuf, 0);
                Console.WriteLine($"📞 调用加法(5, 7) = {sum}  （本地调用成功！）");
                API_Free_DataHnd(result);
            }
            else
            {
                Console.WriteLine("❌ 哎呀，调用失败了，检查一下代码？");
            }

            // 4. 打扫卫生，关闭应用
            API_Free_APPHnd(app);
            API_shutdown();
            Console.WriteLine("🏁 搞定！你已经学会了 API Hub 的基本用法。");
            Console.WriteLine("🎉 太棒了！现在你可以去尝试更多有趣的功能了。");
            Console.WriteLine("按任意键退出...");
            Console.ReadKey();
        }
    }
}