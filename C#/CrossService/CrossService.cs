using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Runtime.InteropServices;
using static API_HubTool.Bindings.API;

namespace CrossDemo
{
    class CrossService
    {
        static void Main()
        {
            Console.WriteLine("=== Cross Service (Coordinator) ===");

            // 1. 清空旧配置
            API_Reset_Prepare();

            // 2. 创建 IPC 端点
            int ret = API_Prepare_Service("ipc:cross", "ipc:cross");
            if (ret == 0)
            {
                Console.WriteLine("API_Prepare_Service 失败");
                return;
            }

            // 3. 启动网格（阻塞直到就绪）
            if (API_Prepare_Done() != 1)
            {
                Console.WriteLine("API_Prepare_Done 失败，请检查控制台输出");
                API_shutdown();
                return;
            }

            Console.WriteLine("IPC 服务 ipc:cross 已启动，按 Enter 退出...");
            Console.ReadLine();

            // 4. 清理
            API_Exit_MainThread();
            API_shutdown();
            Console.WriteLine("已关闭");
        }
    }
}