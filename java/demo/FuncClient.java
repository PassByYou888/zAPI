package demo;

import com.apihub.*;

import java.util.*;
import java.util.concurrent.*;

/**
 * FuncClient – 真正并发的性能压测客户端。
 * 对每个 API 发起指定次数的调用，统计延迟（微秒）及 QPS。
 * 所有调用同时进行（线程数 = 总调用数），无锁，依赖库的线程安全。
 */
public class FuncClient {

    private static final int TOTAL_CALLS = 100;   // 每个 API 的总调用次数
    private static final int TIMEOUT_MS = 5000;

    // 统计结构
    static class Stats {
        double avg, min, max, median, stddev;
        long count;
        double qps;
        double totalSec;
    }

    // 计算统计信息
    private static Stats computeStats(List<Double> times, double elapsedSec) {
        if (times.isEmpty()) return new Stats();
        Collections.sort(times);
        double sum = 0;
        for (double t : times) sum += t;
        double mean = sum / times.size();
        double sqSum = 0;
        for (double t : times) sqSum += (t - mean) * (t - mean);
        double stddev = Math.sqrt(sqSum / times.size());
        double median = times.get(times.size() / 2);
        double qps = times.size() / elapsedSec;
        Stats s = new Stats();
        s.avg = mean / 1000.0;          // 转为毫秒
        s.min = times.get(0) / 1000.0;
        s.max = times.get(times.size() - 1) / 1000.0;
        s.median = median / 1000.0;
        s.stddev = stddev / 1000.0;
        s.count = times.size();
        s.qps = qps;
        s.totalSec = elapsedSec;
        return s;
    }

    // 并发执行一个 API 调用，返回延迟微秒
    private static double measureOneCall(Callable<Void> action) throws Exception {
        long start = System.nanoTime();
        action.call();
        long end = System.nanoTime();
        return (end - start) / 1000.0; // 微秒
    }

    // 针对每个 API 运行压测
    private static Stats benchmark(String name, int totalCalls, Callable<Void> action) throws Exception {
        List<Double> times = Collections.synchronizedList(new ArrayList<>(totalCalls));
        CountDownLatch latch = new CountDownLatch(totalCalls);
        ExecutorService pool = Executors.newFixedThreadPool(totalCalls); // 每个调用一个线程

        long startNano = System.nanoTime();

        for (int i = 0; i < totalCalls; i++) {
            pool.submit(() -> {
                try {
                    double us = measureOneCall(action);
                    times.add(us);
                } catch (Exception e) {
                    // 失败则记录 0，可忽略
                } finally {
                    latch.countDown();
                }
            });
        }

        latch.await(30, TimeUnit.SECONDS);
        pool.shutdownNow();

        long endNano = System.nanoTime();
        double elapsedSec = (endNano - startNano) / 1_000_000_000.0;

        return computeStats(times, elapsedSec);
    }

    public static void main(String[] args) throws Exception {
        System.out.println("=== Java FuncClient – True Concurrent Performance Test ===");
        System.out.printf("Threads per API: %d, total calls per API: %d\n", TOTAL_CALLS, TOTAL_CALLS);
        System.out.println("Times in milliseconds (ms), QPS = calls/sec\n");

        // 连接服务（纯消费）
        ApiHub.resetPrepare();
        ApiHub.prepareClient("ipc:func_service", null);
        ApiHub.prepareClient("127.0.0.1:9899", null);
        if (!ApiHub.prepareDone()) {
            System.err.println("Connect failed. Please check console output for errors.");
            return;
        }
        System.out.println("Connected to FuncService.");

        // 预热
        try (DataHandle h = new DataHandle("add")) {
            h.writeInt(1);
            h.writeInt(2);
            try (DataHandle res = ApiHub.call("FuncService", h, TIMEOUT_MS)) {
                // ignore
            }
        }
        System.out.println("Warm-up done.\n");

        // 准备测试数据
        int[] intArr = {1,2,3,4,5,6,7,8,9,10};
        String[] strArr = {"Hello", "world", "from", "client", "test"};

        System.out.printf("%-18s %10s %10s %10s %10s %10s %10s %12s %10s\n",
                "API", "Avg(ms)", "Min(ms)", "Max(ms)", "Median(ms)", "StdDev(ms)", "Calls", "QPS", "Total(s)");
        System.out.println("----------------------------------------------------------------------------------------------------------------------");

        // 定义各个 API 的调用动作
        Map<String, Callable<Void>> actions = new LinkedHashMap<>();
        actions.put("add", () -> { try (DataHandle p = new DataHandle("add")) { p.writeInt(10); p.writeInt(20); try (DataHandle r = ApiHub.call("FuncService", p, TIMEOUT_MS)) { r.readInt(); } } return null; });
        actions.put("subtract", () -> { try (DataHandle p = new DataHandle("subtract")) { p.writeInt(50); p.writeInt(30); try (DataHandle r = ApiHub.call("FuncService", p, TIMEOUT_MS)) { r.readInt(); } } return null; });
        actions.put("multiply", () -> { try (DataHandle p = new DataHandle("multiply")) { p.writeInt(6); p.writeInt(7); try (DataHandle r = ApiHub.call("FuncService", p, TIMEOUT_MS)) { r.readInt(); } } return null; });
        actions.put("divide", () -> { try (DataHandle p = new DataHandle("divide")) { p.writeInt(10); p.writeInt(3); try (DataHandle r = ApiHub.call("FuncService", p, TIMEOUT_MS)) { r.readDouble(); } } return null; });
        actions.put("to_upper", () -> { try (DataHandle p = new DataHandle("to_upper")) { p.writeString("hello"); try (DataHandle r = ApiHub.call("FuncService", p, TIMEOUT_MS)) { r.readString(); } } return null; });
        actions.put("to_lower", () -> { try (DataHandle p = new DataHandle("to_lower")) { p.writeString("WORLD"); try (DataHandle r = ApiHub.call("FuncService", p, TIMEOUT_MS)) { r.readString(); } } return null; });
        actions.put("reverse", () -> { try (DataHandle p = new DataHandle("reverse")) { p.writeString("abcdef"); try (DataHandle r = ApiHub.call("FuncService", p, TIMEOUT_MS)) { r.readString(); } } return null; });
        actions.put("get_time", () -> { try (DataHandle p = new DataHandle("get_time")) { try (DataHandle r = ApiHub.call("FuncService", p, TIMEOUT_MS)) { r.readString(); } } return null; });
        actions.put("get_random", () -> { try (DataHandle p = new DataHandle("get_random")) { p.writeInt(1); p.writeInt(100); try (DataHandle r = ApiHub.call("FuncService", p, TIMEOUT_MS)) { r.readInt(); } } return null; });
        actions.put("echo", () -> { try (DataHandle p = new DataHandle("echo")) { p.writeString("Hello from client"); try (DataHandle r = ApiHub.call("FuncService", p, TIMEOUT_MS)) { r.readString(); } } return null; });
        actions.put("sum_array", () -> { try (DataHandle p = new DataHandle("sum_array")) { p.writeInt(intArr.length); for (int v : intArr) p.writeInt(v); try (DataHandle r = ApiHub.call("FuncService", p, TIMEOUT_MS)) { r.readInt(); } } return null; });
        actions.put("concat_strings", () -> { try (DataHandle p = new DataHandle("concat_strings")) { p.writeInt(strArr.length); for (String s : strArr) p.writeString(s); try (DataHandle r = ApiHub.call("FuncService", p, TIMEOUT_MS)) { r.readString(); } } return null; });
        actions.put("sha3", () -> { try (DataHandle p = new DataHandle("sha3")) { p.writeString("The quick brown fox jumps over the lazy dog"); try (DataHandle r = ApiHub.call("FuncService", p, TIMEOUT_MS)) { r.readString(); } } return null; });

        for (Map.Entry<String, Callable<Void>> entry : actions.entrySet()) {
            String name = entry.getKey();
            Stats s = benchmark(name, TOTAL_CALLS, entry.getValue());
            System.out.printf("%-18s %10.3f %10.3f %10.3f %10.3f %10.3f %10d %12.2f %10.3f\n",
                    name, s.avg, s.min, s.max, s.median, s.stddev, s.count, s.qps, s.totalSec);
        }

        System.out.println("\nBenchmark completed. Shutting down...");
        ApiHub.exitMainThread();
        ApiHub.shutdown();
    }
}