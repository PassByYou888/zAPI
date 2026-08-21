package demo;

import com.apihub.ApiHub;

import java.util.Scanner;

/**
 * CrossService – 服务注册中心（信标）。
 * 功能：创建 IPC 端点 {@code ipc:cross}，作为 C4 服务网格的控制平面。
 * 不注册任何业务 API。节点和客户端通过此端点发现彼此。
 * 
 * <p>启动顺序：先启动本服务，再启动节点和客户端。</p>
 * 
 * @see CrossNode
 * @see CrossCall
 */
public class CrossService {

    public static void main(String[] args) {
        System.out.println("=== CrossService (Java) – Service Registry ===");

        // 注册 Shutdown Hook 确保 Ctrl+C 时优雅释放资源
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            System.out.println("[Shutdown] Exiting main thread and shutting down.");
            ApiHub.exitMainThread();
            ApiHub.shutdown();
        }));

        try {
            // 1. 清空之前的网络配置
            ApiHub.resetPrepare();

            // 2. 创建 IPC 服务端点，公布地址与监听地址一致
            //    监听地址 "ipc:cross" 表示绑定到命名管道（Windows）或 Unix 域套接字（Linux/macOS）
            ApiHub.prepareService("ipc:cross", "ipc:cross");

            // 3. 启动 C4 网络框架，阻塞直到服务就绪
            if (!ApiHub.prepareDone()) {
                System.err.println("[ERROR] prepareDone() failed. Check console output for details.");
                return;
            }

            System.out.println("[OK] Service registry ready on ipc:cross");
            System.out.println("[INFO] Press Enter to stop the service...");

            // 4. 阻塞等待用户输入，保持服务运行
            try (Scanner scanner = new Scanner(System.in)) {
                scanner.nextLine();
            }

        } catch (Exception e) {
            System.err.println("[FATAL] Unexpected error: " + e.getMessage());
            e.printStackTrace();
        } finally {
            // 5. 显式清理（ShutdownHook 也会做，但这里双重保障）
            ApiHub.exitMainThread();
            ApiHub.shutdown();
            System.out.println("[OK] Service shutdown complete.");
        }
    }
}