package demo;

import com.apihub.*;

public class DemoClient {
    public static void main(String[] args) {
        System.out.println("=== Java API Hub Client Demo ===");

        // 1. 连接服务（纯消费，不暴露 API）
        ApiHub.resetPrepare();
        ApiHub.prepareClient("ipc:calc_service", null);
        if (!ApiHub.prepareDone()) {
            System.err.println("Connect failed. Please check console output for errors.");
            return;
        }
        System.out.println("Connected to ipc:calc_service");

        // 2. 构造参数
        try (DataHandle param = new DataHandle("add")) {
            param.writeInt(10);
            param.writeInt(20);

            // 3. 远程调用
            try (DataHandle result = ApiHub.call("CalcService", param, 3000)) {
                if (result.getSize() == 0) {
                    System.err.println("Call timed out or failed");
                } else {
                    int sum = result.readInt();
                    System.out.println("10 + 20 = " + sum);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
            ApiHub.exitMainThread();
            ApiHub.shutdown();
        }
    }
}