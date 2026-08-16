package demo;

import com.apihub.*;
import com.sun.jna.Pointer;

import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Random;

/**
 * FuncServer – 功能丰富的服务端，注册 13 个 API。
 * 包含 SHA3-256 纯 Java 实现（自包含，无外部依赖）。
 * 支持 IPC 和 TCP，同时自连以允许本地环回。
 */
public class FuncServer {

    // ============================================================
    // 1. 业务逻辑（纯函数，无序列化）
    // ============================================================

    private static int add(int a, int b) { return a + b; }
    private static int subtract(int a, int b) { return a - b; }
    private static int multiply(int a, int b) { return a * b; }
    private static double divide(int a, int b) { return b == 0 ? 0.0 : (double) a / b; }
    private static String toUpper(String s) { return s.toUpperCase(); }
    private static String toLower(String s) { return s.toLowerCase(); }
    private static String reverse(String s) { return new StringBuilder(s).reverse().toString(); }
    private static String getTime() { return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")); }
    private static int getRandom(int min, int max) { return new Random().nextInt(max - min + 1) + min; }
    private static String echo(String s) { return s; }
    private static int sumArray(int[] arr) { int sum = 0; for (int v : arr) sum += v; return sum; }
    private static String concatStrings(String[] arr) { return String.join(" ", arr); }

    // ============================================================
    // 2. SHA3-256 纯 Java 实现（Keccak-f[1600]）
    // ============================================================

    private static class Sha3 {
        private static final int ROUNDS = 24;
        private static final long[] ROUND_CONSTANTS = {
                0x0000000000000001L, 0x0000000000008082L, 0x800000000000808aL,
                0x8000000080008000L, 0x000000000000808bL, 0x0000000080000001L,
                0x8000000080008081L, 0x8000000000008009L, 0x000000000000008aL,
                0x0000000000000088L, 0x0000000080008009L, 0x000000008000000aL,
                0x000000008000808bL, 0x800000000000008bL, 0x8000000000008089L,
                0x8000000000008003L, 0x8000000000008002L, 0x8000000000000080L,
                0x000000000000800aL, 0x800000008000000aL, 0x8000000080008081L,
                0x8000000000008080L, 0x0000000080000001L, 0x8000000080008008L
        };
        private static final int[] RHO_OFFSETS = {
                0, 1, 62, 28, 27, 36, 44, 6, 55, 20,
                3, 10, 43, 25, 39, 41, 45, 15, 21, 8,
                18, 2, 61, 56, 14
        };

        private static long rotl64(long x, int n) {
            return (x << n) | (x >>> (64 - n));
        }

        private static void keccakF1600(long[] state) {
            for (int round = 0; round < ROUNDS; round++) {
                // Theta
                long[] C = new long[5];
                long[] D = new long[5];
                for (int x = 0; x < 5; x++)
                    C[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20];
                for (int x = 0; x < 5; x++)
                    D[x] = C[(x + 4) % 5] ^ rotl64(C[(x + 1) % 5], 1);
                for (int x = 0; x < 5; x++)
                    for (int y = 0; y < 5; y++)
                        state[x + 5 * y] ^= D[x];

                // Rho and Pi
                long current = state[1];
                for (int t = 0; t < 24; t++) {
                    int x, y;
                    int idx = t + 1;
                    if (idx == 1) { x = 0; y = 1; }
                    else if (idx == 2) { x = 1; y = 0; }
                    else if (idx == 3) { x = 1; y = 1; }
                    else if (idx == 4) { x = 0; y = 2; }
                    else if (idx == 5) { x = 2; y = 0; }
                    else if (idx == 6) { x = 2; y = 1; }
                    else if (idx == 7) { x = 1; y = 2; }
                    else if (idx == 8) { x = 2; y = 2; }
                    else if (idx == 9) { x = 0; y = 3; }
                    else if (idx == 10) { x = 3; y = 0; }
                    else if (idx == 11) { x = 3; y = 1; }
                    else if (idx == 12) { x = 1; y = 3; }
                    else if (idx == 13) { x = 3; y = 2; }
                    else if (idx == 14) { x = 2; y = 3; }
                    else if (idx == 15) { x = 3; y = 3; }
                    else if (idx == 16) { x = 0; y = 4; }
                    else if (idx == 17) { x = 4; y = 0; }
                    else if (idx == 18) { x = 4; y = 1; }
                    else if (idx == 19) { x = 1; y = 4; }
                    else if (idx == 20) { x = 4; y = 2; }
                    else if (idx == 21) { x = 2; y = 4; }
                    else if (idx == 22) { x = 4; y = 3; }
                    else if (idx == 23) { x = 3; y = 4; }
                    else if (idx == 24) { x = 4; y = 4; }
                    else { x = 0; y = 0; }

                    long temp = state[x + 5 * y];
                    state[x + 5 * y] = rotl64(current, RHO_OFFSETS[t]);
                    current = temp;
                }

                // Chi
                for (int y = 0; y < 5; y++) {
                    long[] temp = new long[5];
                    for (int x = 0; x < 5; x++)
                        temp[x] = state[x + 5 * y];
                    for (int x = 0; x < 5; x++)
                        state[x + 5 * y] = temp[x] ^ ((~temp[(x + 1) % 5]) & temp[(x + 2) % 5]);
                }

                // Iota
                state[0] ^= ROUND_CONSTANTS[round];
            }
        }

        public static byte[] hash(byte[] input) {
            long[] state = new long[25];
            int rate = 136; // 1600 - 2*256 = 1088 bits = 136 bytes

            int offset = 0;
            int len = input.length;
            int pos = 0;
            while (len > 0) {
                int chunk = Math.min(len, rate - offset);
                for (int i = 0; i < chunk; i++) {
                    int idx = (offset + i) >>> 3;
                    int shift = 8 * ((offset + i) & 7);
                    state[idx] ^= (long) (input[pos + i] & 0xFF) << shift;
                }
                offset += chunk;
                pos += chunk;
                len -= chunk;
                if (offset == rate) {
                    keccakF1600(state);
                    offset = 0;
                }
            }

            state[offset >>> 3] ^= 0x06L << (8 * (offset & 7));
            state[(rate - 1) >>> 3] ^= 0x80L << (8 * ((rate - 1) & 7));
            keccakF1600(state);

            byte[] hash = new byte[32];
            for (int i = 0; i < 32; i++) {
                hash[i] = (byte) (state[i >>> 3] >>> (8 * (i & 7)));
            }
            return hash;
        }

        public static String hashHex(String input) {
            byte[] hash = hash(input.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (byte b : hash) sb.append(String.format("%02x", b & 0xFF));
            return sb.toString();
        }
    }

    // ============================================================
    // 3. API 回调函数（从 DataHnd 读写）
    // ============================================================

    private static void addCallback(Pointer trigger, Pointer input, Pointer output) {
        try {
            DataHandle in = DataHandle.wrapInput(input);
            DataHandle out = DataHandle.wrapOutput(output);
            int a = in.readInt();
            int b = in.readInt();
            out.writeInt(add(a, b));
        } catch (Exception e) {
            System.err.println("addCallback error: " + e.getMessage());
        }
    }

    private static void subtractCallback(Pointer trigger, Pointer input, Pointer output) {
        try {
            DataHandle in = DataHandle.wrapInput(input);
            DataHandle out = DataHandle.wrapOutput(output);
            int a = in.readInt();
            int b = in.readInt();
            out.writeInt(subtract(a, b));
        } catch (Exception e) {
            System.err.println("subtractCallback error: " + e.getMessage());
        }
    }

    private static void multiplyCallback(Pointer trigger, Pointer input, Pointer output) {
        try {
            DataHandle in = DataHandle.wrapInput(input);
            DataHandle out = DataHandle.wrapOutput(output);
            int a = in.readInt();
            int b = in.readInt();
            out.writeInt(multiply(a, b));
        } catch (Exception e) {
            System.err.println("multiplyCallback error: " + e.getMessage());
        }
    }

    private static void divideCallback(Pointer trigger, Pointer input, Pointer output) {
        try {
            DataHandle in = DataHandle.wrapInput(input);
            DataHandle out = DataHandle.wrapOutput(output);
            int a = in.readInt();
            int b = in.readInt();
            out.writeDouble(divide(a, b));
        } catch (Exception e) {
            System.err.println("divideCallback error: " + e.getMessage());
        }
    }

    private static void toUpperCallback(Pointer trigger, Pointer input, Pointer output) {
        try {
            DataHandle in = DataHandle.wrapInput(input);
            DataHandle out = DataHandle.wrapOutput(output);
            String s = in.readString();
            out.writeString(toUpper(s));
        } catch (Exception e) {
            System.err.println("toUpperCallback error: " + e.getMessage());
        }
    }

    private static void toLowerCallback(Pointer trigger, Pointer input, Pointer output) {
        try {
            DataHandle in = DataHandle.wrapInput(input);
            DataHandle out = DataHandle.wrapOutput(output);
            String s = in.readString();
            out.writeString(toLower(s));
        } catch (Exception e) {
            System.err.println("toLowerCallback error: " + e.getMessage());
        }
    }

    private static void reverseCallback(Pointer trigger, Pointer input, Pointer output) {
        try {
            DataHandle in = DataHandle.wrapInput(input);
            DataHandle out = DataHandle.wrapOutput(output);
            String s = in.readString();
            out.writeString(reverse(s));
        } catch (Exception e) {
            System.err.println("reverseCallback error: " + e.getMessage());
        }
    }

    private static void getTimeCallback(Pointer trigger, Pointer input, Pointer output) {
        try {
            DataHandle out = DataHandle.wrapOutput(output);
            out.writeString(getTime());
        } catch (Exception e) {
            System.err.println("getTimeCallback error: " + e.getMessage());
        }
    }

    private static void getRandomCallback(Pointer trigger, Pointer input, Pointer output) {
        try {
            DataHandle in = DataHandle.wrapInput(input);
            DataHandle out = DataHandle.wrapOutput(output);
            int min = in.readInt();
            int max = in.readInt();
            out.writeInt(getRandom(min, max));
        } catch (Exception e) {
            System.err.println("getRandomCallback error: " + e.getMessage());
        }
    }

    private static void echoCallback(Pointer trigger, Pointer input, Pointer output) {
        try {
            DataHandle in = DataHandle.wrapInput(input);
            DataHandle out = DataHandle.wrapOutput(output);
            String s = in.readString();
            out.writeString(echo(s));
        } catch (Exception e) {
            System.err.println("echoCallback error: " + e.getMessage());
        }
    }

    private static void sumArrayCallback(Pointer trigger, Pointer input, Pointer output) {
        try {
            DataHandle in = DataHandle.wrapInput(input);
            DataHandle out = DataHandle.wrapOutput(output);
            // 数组格式：先读长度，再读每个元素
            int len = in.readInt();
            int[] arr = new int[len];
            for (int i = 0; i < len; i++) arr[i] = in.readInt();
            out.writeInt(sumArray(arr));
        } catch (Exception e) {
            System.err.println("sumArrayCallback error: " + e.getMessage());
        }
    }

    private static void concatStringsCallback(Pointer trigger, Pointer input, Pointer output) {
        try {
            DataHandle in = DataHandle.wrapInput(input);
            DataHandle out = DataHandle.wrapOutput(output);
            int len = in.readInt();
            String[] arr = new String[len];
            for (int i = 0; i < len; i++) arr[i] = in.readString();
            out.writeString(concatStrings(arr));
        } catch (Exception e) {
            System.err.println("concatStringsCallback error: " + e.getMessage());
        }
    }

    private static void sha3Callback(Pointer trigger, Pointer input, Pointer output) {
        try {
            DataHandle in = DataHandle.wrapInput(input);
            DataHandle out = DataHandle.wrapOutput(output);
            String s = in.readString();
            out.writeString(Sha3.hashHex(s));
        } catch (Exception e) {
            System.err.println("sha3Callback error: " + e.getMessage());
        }
    }

    // ============================================================
    // 4. 主程序
    // ============================================================

    public static void main(String[] args) {
        System.out.println("=== Java FuncService (13 APIs) ===");

        // 注册 Shutdown Hook 保证优雅退出
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            System.out.println("Shutdown hook triggered.");
            ApiHub.exitMainThread();
            ApiHub.shutdown();
        }));

        try (AppHandle app = new AppHandle("FuncService", "Functional service with 13 APIs")) {

            // 注册所有回调
            app.registerCall("add", "Add two integers", FuncServer::addCallback);
            app.registerCall("subtract", "Subtract two integers", FuncServer::subtractCallback);
            app.registerCall("multiply", "Multiply two integers", FuncServer::multiplyCallback);
            app.registerCall("divide", "Divide two integers (returns double)", FuncServer::divideCallback);
            app.registerCall("to_upper", "Convert string to uppercase", FuncServer::toUpperCallback);
            app.registerCall("to_lower", "Convert string to lowercase", FuncServer::toLowerCallback);
            app.registerCall("reverse", "Reverse a string", FuncServer::reverseCallback);
            app.registerCall("get_time", "Get current time", FuncServer::getTimeCallback);
            app.registerCall("get_random", "Get random integer in [min, max]", FuncServer::getRandomCallback);
            app.registerCall("echo", "Echo input string", FuncServer::echoCallback);
            app.registerCall("sum_array", "Sum an array of integers", FuncServer::sumArrayCallback);
            app.registerCall("concat_strings", "Concatenate strings with spaces", FuncServer::concatStringsCallback);
            app.registerCall("sha3", "SHA3-256 hash (hex)", FuncServer::sha3Callback);

            System.out.println("Registered 13 APIs.");

            // 网络准备：IPC + TCP，并自连
            ApiHub.resetPrepare();
            ApiHub.prepareService("ipc:func_service", "ipc:func_service");
            ApiHub.prepareService("0.0.0.0", "127.0.0.1:9899");
            ApiHub.prepareClient("ipc:func_service", app);
            ApiHub.prepareClient("127.0.0.1:9899", app);

            if (!ApiHub.prepareDone()) {
                System.err.println("Prepare failed. Please check console output for errors.");
                return;
            }

            System.out.println("Service started on ipc:func_service and TCP 127.0.0.1:9899");
            System.out.println("Press Ctrl+C to stop...");

            // 可中断循环
            while (!Thread.currentThread().isInterrupted()) {
                try {
                    Thread.sleep(1000);
                } catch (InterruptedException e) {
                    System.out.println("Interrupted, shutting down...");
                    Thread.currentThread().interrupt();
                    break;
                }
                // 状态信息由库直接打印到控制台，无需手动获取
            }
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
            ApiHub.exitMainThread();
            ApiHub.shutdown();
        }
    }
}