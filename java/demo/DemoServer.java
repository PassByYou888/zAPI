package demo;

import com.apihub.*;

public class DemoServer {
    public static void main(String[] args) {
        System.out.println("=== Java API Hub Server Demo ===");

        // 注册 Shutdown Hook 确保退出时清理（备用）
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            System.out.println("Shutdown hook triggered.");
            ApiHub.exitMainThread();
            ApiHub.shutdown();
        }));

        // 1. 创建应用
        try (AppHandle app = new AppHandle("CalcService", "Calculator")) {
            // 2. 注册 add API
            CallCallback addCallback = (trigger, input, output) -> {
                DataHandle in = DataHandle.wrapInput(input);
                DataHandle out = DataHandle.wrapOutput(output);
                try {
                    int a = in.readInt();
                    int b = in.readInt();
                    int sum = a + b;
                    out.writeInt(sum);
                    System.out.printf("[Server] add(%d, %d) = %d%n", a, b, sum);
                } catch (Exception e) {
                    System.err.println("Add callback error: " + e.getMessage());
                }
            };
            if (!app.registerCall("add", "a+b", addCallback)) {
                System.err.println("Register 'add' failed");
                return;
            }
            System.out.println("Registered 'add' API");

            // 3. 网络准备
            ApiHub.resetPrepare();
            ApiHub.prepareService("ipc:calc_service", "ipc:calc_service");
            ApiHub.prepareClient("ipc:calc_service", app);

            if (!ApiHub.prepareDone()) {
                System.err.println("Prepare failed. Please check console output for errors.");
                return;
            }
            System.out.println("Service started on ipc:calc_service");
            System.out.println("Press Ctrl+C to stop...");

            // 4. 等待退出（可中断循环）
            while (!Thread.currentThread().isInterrupted()) {
                try {
                    Thread.sleep(1000);
                } catch (InterruptedException e) {
                    System.out.println("Interrupted, shutting down...");
                    Thread.currentThread().interrupt(); // 保留中断状态
                    break;
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
            // 确保清理（Shutdown Hook 也会做，但这里双重保障）
            ApiHub.exitMainThread();
            ApiHub.shutdown();
        }
    }
}