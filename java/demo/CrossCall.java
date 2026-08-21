package demo;

import com.apihub.ApiHub;
import com.apihub.DataHandle;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * CrossCall – 并发客户端（Consumer）。
 * 功能：连接到 {@code ipc:cross}，在独立线程中交替调用 {@code 'add'} 和 {@code 'inv_seri'}，
 * 持续 10 秒后自动退出。可同时启动多个实例以模拟负载。
 * 
 * <p>与 Pascal cross_call 中 Do_Compute 的逻辑完全等价。</p>
 * 
 * @see CrossService
 * @see CrossNode
 */
public class CrossCall {

    /** 运行时长（毫秒），与 Pascal 中 10 * 1000 一致 */
    private static final long RUN_DURATION_MS = 10_000L;

    /**
     * 封装 'add' 远程调用。
     * 与 Pascal cross_call 中 add__ 函数完全等价。
     * 
     * @param a 第一个加数
     * @param b 第二个加数
     * @return 计算结果，若超时或失败返回 0
     */
    private static int add__(int a, int b) {
        try (DataHandle send = new DataHandle("add")) {
            send.writeInt32(a);
            send.writeInt32(b);

            try (DataHandle result = ApiHub.call("demo", send, 1000)) {
                if (result.getSize() == 0) {
                    System.err.printf("[Call] add(%d, %d) 超时或失败%n", a, b);
                    return 0;
                }
                return result.readInt32();
            }
        } catch (Exception e) {
            System.err.println("[Call] add 异常: " + e.getMessage());
            return 0;
        }
    }

    /**
     * 封装 'inv_seri' 远程调用。
     * 数据布局与 Pascal cross_call 中 inv_seri_ 函数完全等价。
     * 
     * @return 调试字符串，包含发送和接收的数据对比
     */
    private static String invSeri__() {
        // 固定测试数据（与 Pascal 完全一致）
        int b = 200;
        int w = 0x10;
        long c = 0x2F;
        long u64 = 0x3F;
        String s = "hello world";
        float f = 3.14f;

        try (DataHandle send = new DataHandle("inv_seri")) {
            // ---------- 按顺序写入（与 Pascal 完全一致） ----------
            send.writeUInt8(b);
            send.writeUInt16(w);
            send.writeUInt32(c);
            send.writeUInt64(u64);
            send.writeStringNullTerminated(s);
            send.writeSingle(f);

            try (DataHandle result = ApiHub.call("demo", send, 1000)) {
                if (result.getSize() == 0) {
                    return "inv_seri 超时或失败";
                }

                // ---------- 按反向顺序读取（与 Pascal 完全一致） ----------
                float fRet = result.readSingle();
                String sRet = result.readStringNullTerminated();
                long u64Ret = result.readUInt64();
                long cRet = result.readUInt32();
                int wRet = result.readUInt16();
                int bRet = result.readUInt8();

                return String.format(
                        "接收数据序 [%d, %d, %d, %d, \"%s\", %.2f] = 发送数据序 [%.2f, \"%s\", %d, %d, %d, %d]",
                        bRet, wRet, cRet, u64Ret, sRet, fRet,
                        fRet, sRet, u64Ret, cRet, wRet, bRet
                );
            }
        } catch (Exception e) {
            return "inv_seri 异常: " + e.getMessage();
        }
    }

    /**
     * 工作线程的主循环，与 Pascal cross_call 中 Do_Compute 完全等价。
     * 
     * @param running 运行标志，用于控制循环退出
     * @param latch   CountDownLatch，在循环结束后 countDown()
     */
    private static void doCompute(AtomicBoolean running, CountDownLatch latch) {
        long startTime = System.currentTimeMillis();
        try {
            while (running.get() && (System.currentTimeMillis() - startTime) < RUN_DURATION_MS) {
                // 与 Pascal 中 TMT19937.Rand32 mod 2 等价：随机选择调用 add 或 inv_seri
                if (ThreadLocalRandom.current().nextBoolean()) {
                    int a = ThreadLocalRandom.current().nextInt(1, Integer.MAX_VALUE);
                    int b = ThreadLocalRandom.current().nextInt(1, Integer.MAX_VALUE);
                    int result = add__(a, b);
                    if (result != 0) {
                        long remaining = RUN_DURATION_MS - (System.currentTimeMillis() - startTime);
                        System.out.printf("[Call] 计算 \"a(%d)+b(%d)\" = 计算结果 %d (%.2f秒以后退出)%n",
                                a, b, result, remaining / 1000.0);
                    }
                } else {
                    String status = invSeri__();
                    long remaining = RUN_DURATION_MS - (System.currentTimeMillis() - startTime);
                    System.out.printf("[Call] %s (%.2f秒退出)%n", status, remaining / 1000.0);
                }

                // 与 Pascal 中 TCompute.Sleep(1) 等价：避免 CPU 空转
                Thread.sleep(1);
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            System.err.println("[Call] 工作线程被中断");
        } finally {
            latch.countDown();
        }
    }

    public static void main(String[] args) throws InterruptedException {
        System.out.println("=== CrossCall (Java) – Concurrent Client ===");

        // ---------- 1. 连接服务（纯消费，不暴露 API） ----------
        ApiHub.resetPrepare();
        ApiHub.prepareClient("ipc:cross", null);

        if (!ApiHub.prepareDone()) {
            System.err.println("[ERROR] prepareDone() failed. Check console output.");
            return;
        }
        System.out.println("[OK] Connected to ipc:cross");

        // ---------- 2. 启动工作线程（与 Pascal TCompute.RunC_NP 等价） ----------
        AtomicBoolean running = new AtomicBoolean(true);
        CountDownLatch latch = new CountDownLatch(1);
        ExecutorService executor = Executors.newSingleThreadExecutor();
        executor.submit(() -> doCompute(running, latch));

        System.out.printf("[INFO] 仿真计算启动（可多开），持续 %d 秒...%n", RUN_DURATION_MS / 1000);

        // ---------- 3. 等待工作线程结束（与 Pascal while thread_running do Sleep(100) 等价） ----------
        // 等待 10 秒后，设置停止标志，并等待线程真正退出
        Thread.sleep(RUN_DURATION_MS + 500); // 多等 500ms 确保最后一次循环完成
        running.set(false);
        latch.await(5, TimeUnit.SECONDS);

        // ---------- 4. 清理资源 ----------
        executor.shutdownNow();
        if (!executor.awaitTermination(2, TimeUnit.SECONDS)) {
            System.err.println("[WARN] 工作线程未能及时终止，强制关闭");
        }

        System.out.println("[OK] 计算完成，清理线程中.");

        ApiHub.exitMainThread();
        ApiHub.shutdown();
        System.out.println("[OK] Client shutdown complete.");
    }
}