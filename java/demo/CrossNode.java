package demo;

import com.apihub.ApiHub;
import com.apihub.AppHandle;
import com.apihub.CallCallback;
import com.apihub.DataHandle;
import com.sun.jna.Pointer;

import java.util.Scanner;

/**
 * CrossNode – 无状态工作节点（Worker）。
 * 功能：注册应用 {@code 'demo'}，暴露 {@code 'add'} 和 {@code 'inv_seri'} 两个 Call API。
 * 使用 {@code ApiHub.setOption("Wait_Connection_ReadyOk", "False")} 启用部署模式，
 * 允许节点先于服务启动（自动重连）。
 * 
 * <p>可同时启动多个实例，C4 网格自动负载均衡。</p>
 * 
 * @see CrossService
 * @see CrossCall
 */
public class CrossNode {

    // ========== 回调委托必须保持为静态字段，防止 GC 回收导致 JNA 崩溃 ==========
    private static final CallCallback ADD_CALLBACK = CrossNode::addCallback;
    private static final CallCallback INV_SERI_CALLBACK = CrossNode::invSeriCallback;

    /**
     * 'add' 回调：读取两个 Int32，返回它们的和。
     * 与 Pascal cross_node 中 do_add_Call 完全等价。
     */
    private static void addCallback(Pointer trigger, Pointer input, Pointer output) {
        try {
            DataHandle in = DataHandle.wrapInput(input);
            DataHandle out = DataHandle.wrapOutput(output);

            int a = in.readInt32();  // 读取第一个参数
            int b = in.readInt32();  // 读取第二个参数
            int c = a + b;

            System.out.printf("[Node] add(%d, %d) = %d%n", a, b, c);
            out.writeInt32(c);
        } catch (Exception e) {
            System.err.println("[ERROR] addCallback: " + e.getMessage());
        }
    }

    /**
     * 'inv_seri' 回调：接收 6 种不同类型的参数，反向回复。
     * 数据布局与 Pascal cross_node 中 do_inv_seri_Call 完全等价。
     * 
     * <p>接收顺序：UInt8 → UInt16 → UInt32 → UInt64 → String(NUL) → Single</p>
     * <p>回复顺序：Single → String(NUL) → UInt64 → UInt32 → UInt16 → UInt8</p>
     */
    private static void invSeriCallback(Pointer trigger, Pointer input, Pointer output) {
        try {
            DataHandle in = DataHandle.wrapInput(input);
            DataHandle out = DataHandle.wrapOutput(output);

            // ---------- 按顺序读取（与 Pascal 完全一致） ----------
            int b = in.readUInt8();          // 1 字节
            int w = in.readUInt16();         // 2 字节，小端
            long c = in.readUInt32();        // 4 字节，小端
            long u64 = in.readUInt64();      // 8 字节，小端
            String s = in.readStringNullTerminated(); // UTF-8 + #0
            float f = in.readSingle();       // 4 字节 IEEE 754，小端

            // ---------- 反向写入回复（与 Pascal 完全一致） ----------
            out.writeSingle(f);
            out.writeStringNullTerminated(s);
            out.writeUInt64(u64);
            out.writeUInt32(c);
            out.writeUInt16(w);
            out.writeUInt8(b);

            System.out.printf("[Node] inv_seri 接收: [%d, %d, %d, %d, \"%s\", %.2f] 回复: [%.2f, \"%s\", %d, %d, %d, %d]%n",
                    b, w, c, u64, s, f, f, s, u64, c, w, b);

        } catch (Exception e) {
            System.err.println("[ERROR] invSeriCallback: " + e.getMessage());
        }
    }

    public static void main(String[] args) {
        System.out.println("=== CrossNode (Java) – Worker Node ===");

        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            System.out.println("[Shutdown] Exiting main thread and shutting down.");
            ApiHub.exitMainThread();
            ApiHub.shutdown();
        }));

        try (AppHandle app = new AppHandle("demo", "Java cross node instance")) {

            // ---------- 1. 注册两个 Call API ----------
            if (!app.registerCall("add", "add(int a, int b)", ADD_CALLBACK)) {
                System.err.println("[ERROR] Failed to register 'add'");
                return;
            }
            if (!app.registerCall("inv_seri", "inv_seri()", INV_SERI_CALLBACK)) {
                System.err.println("[ERROR] Failed to register 'inv_seri'");
                return;
            }
            System.out.println("[OK] Registered 'add' and 'inv_seri' under app 'demo'");

            // ---------- 2. 启用部署模式：节点可先于服务启动 ----------
            //    Pascal 中对应 API_SetOption2('Wait_Ready', 'False')
            ApiHub.setOption("Wait_Connection_ReadyOk", "False");

            // ---------- 3. 网络准备：连接到 ipc:cross 并暴露 app ----------
            ApiHub.resetPrepare();
            ApiHub.prepareClient("ipc:cross", app);

            // ---------- 4. 启动网络框架 ----------
            if (!ApiHub.prepareDone()) {
                System.err.println("[ERROR] prepareDone() failed. Check console output.");
                return;
            }

            System.out.println("[OK] Node ready on ipc:cross, waiting for requests...");
            System.out.println("[INFO] Press Enter to stop this node...");

            // ---------- 5. 阻塞保持运行 ----------
            try (Scanner scanner = new Scanner(System.in)) {
                scanner.nextLine();
            }

        } catch (Exception e) {
            System.err.println("[FATAL] Unexpected error: " + e.getMessage());
            e.printStackTrace();
        } finally {
            ApiHub.exitMainThread();
            ApiHub.shutdown();
            System.out.println("[OK] Node shutdown complete.");
        }
    }
}