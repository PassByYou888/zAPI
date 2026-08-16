/*
 * FuncClient.cs - Functional client providing 13 wrapper functions and performing
 * **truly concurrent** performance benchmarking.
 *
 * This version removes all mutex locks to allow API_Call to be called by
 * multiple threads simultaneously. According to the official documentation,
 * all exported functions are fully thread-safe.
 * This test leverages that property to measure true concurrent throughput.
 *
 * Performance test: true multi-threaded concurrency, measuring latency
 * (microseconds) and QPS (calls per second).
 */

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Runtime.InteropServices;
using API_HubTool.Bindings;
using static API_HubTool.Bindings.API;

namespace FuncClient
{
    class FuncClient
    {
        private static int _defaultTimeout = 5000;

        // ============================================================
        // 1. Serialisation helpers (matching the server)
        // ============================================================

        private static void WriteInt(DataHnd h, int v)
        {
            byte[] b = BitConverter.GetBytes(v);
            API_WriteBuffer(h, b, 4);
        }
        private static void WriteDouble(DataHnd h, double v)
        {
            byte[] b = BitConverter.GetBytes(v);
            API_WriteBuffer(h, b, 8);
        }
        private static void WriteString(DataHnd h, string s)
        {
            byte[] bytes = System.Text.Encoding.UTF8.GetBytes(s);
            WriteInt(h, bytes.Length);
            API_WriteBuffer(h, bytes, bytes.Length);
        }
        private static void WriteIntArray(DataHnd h, int[] arr)
        {
            WriteInt(h, arr.Length);
            foreach (int v in arr) WriteInt(h, v);
        }
        private static void WriteStringArray(DataHnd h, string[] arr)
        {
            WriteInt(h, arr.Length);
            foreach (string s in arr) WriteString(h, s);
        }

        private static bool ReadInt(DataHnd h, out int v)
        {
            byte[] buf = new byte[4];
            if (API_ReadBuffer(h, buf, 4) != 4) { v = 0; return false; }
            v = BitConverter.ToInt32(buf, 0);
            return true;
        }
        private static bool ReadDouble(DataHnd h, out double v)
        {
            byte[] buf = new byte[8];
            if (API_ReadBuffer(h, buf, 8) != 8) { v = 0; return false; }
            v = BitConverter.ToDouble(buf, 0);
            return true;
        }
        private static bool ReadString(DataHnd h, out string s)
        {
            if (!ReadInt(h, out int len)) { s = null; return false; }
            byte[] buf = new byte[len];
            if (API_ReadBuffer(h, buf, len) != len) { s = null; return false; }
            s = System.Text.Encoding.UTF8.GetString(buf);
            return true;
        }

        // ============================================================
        // 2. Remote call wrappers (lock-free, fully concurrent)
        // ============================================================

        // ⚡ According to official docs, API_Call is fully thread-safe.
        // No locks are needed – true concurrency is achieved naturally.
        private static bool DoCallInt(string api, DataHnd param, out int result)
        {
            DataHnd hResult = API_Call("FuncService", param, (ulong)_defaultTimeout);
            API_Free_DataHnd(param);
            if (!hResult.IsValid || API_GetSize(hResult) == 0)
            {
                if (hResult.IsValid) API_Free_DataHnd(hResult);
                result = 0;
                return false;
            }
            bool ok = ReadInt(hResult, out result);
            API_Free_DataHnd(hResult);
            return ok;
        }

        private static bool DoCallDouble(string api, DataHnd param, out double result)
        {
            DataHnd hResult = API_Call("FuncService", param, (ulong)_defaultTimeout);
            API_Free_DataHnd(param);
            if (!hResult.IsValid || API_GetSize(hResult) == 0)
            {
                if (hResult.IsValid) API_Free_DataHnd(hResult);
                result = 0;
                return false;
            }
            bool ok = ReadDouble(hResult, out result);
            API_Free_DataHnd(hResult);
            return ok;
        }

        private static bool DoCallString(string api, DataHnd param, out string result)
        {
            DataHnd hResult = API_Call("FuncService", param, (ulong)_defaultTimeout);
            API_Free_DataHnd(param);
            if (!hResult.IsValid || API_GetSize(hResult) == 0)
            {
                if (hResult.IsValid) API_Free_DataHnd(hResult);
                result = null;
                return false;
            }
            bool ok = ReadString(hResult, out result);
            API_Free_DataHnd(hResult);
            return ok;
        }

        // ============================================================
        // 3. 13 wrapper functions (unchanged)
        // ============================================================

        public static int FuncAdd(int a, int b)
        {
            DataHnd h = API_Create_DataHnd("add");
            WriteInt(h, a);
            WriteInt(h, b);
            DoCallInt("add", h, out int result);
            return result;
        }

        public static int FuncSubtract(int a, int b)
        {
            DataHnd h = API_Create_DataHnd("subtract");
            WriteInt(h, a);
            WriteInt(h, b);
            DoCallInt("subtract", h, out int result);
            return result;
        }

        public static int FuncMultiply(int a, int b)
        {
            DataHnd h = API_Create_DataHnd("multiply");
            WriteInt(h, a);
            WriteInt(h, b);
            DoCallInt("multiply", h, out int result);
            return result;
        }

        public static double FuncDivide(int a, int b)
        {
            DataHnd h = API_Create_DataHnd("divide");
            WriteInt(h, a);
            WriteInt(h, b);
            DoCallDouble("divide", h, out double result);
            return result;
        }

        public static string FuncToUpper(string s)
        {
            DataHnd h = API_Create_DataHnd("to_upper");
            WriteString(h, s);
            DoCallString("to_upper", h, out string result);
            return result;
        }

        public static string FuncToLower(string s)
        {
            DataHnd h = API_Create_DataHnd("to_lower");
            WriteString(h, s);
            DoCallString("to_lower", h, out string result);
            return result;
        }

        public static string FuncReverse(string s)
        {
            DataHnd h = API_Create_DataHnd("reverse");
            WriteString(h, s);
            DoCallString("reverse", h, out string result);
            return result;
        }

        public static string FuncGetTime()
        {
            DataHnd h = API_Create_DataHnd("get_time");
            DoCallString("get_time", h, out string result);
            return result;
        }

        public static int FuncGetRandom(int min, int max)
        {
            DataHnd h = API_Create_DataHnd("get_random");
            WriteInt(h, min);
            WriteInt(h, max);
            DoCallInt("get_random", h, out int result);
            return result;
        }

        public static string FuncEcho(string s)
        {
            DataHnd h = API_Create_DataHnd("echo");
            WriteString(h, s);
            DoCallString("echo", h, out string result);
            return result;
        }

        public static int FuncSumArray(int[] arr)
        {
            DataHnd h = API_Create_DataHnd("sum_array");
            WriteIntArray(h, arr);
            DoCallInt("sum_array", h, out int result);
            return result;
        }

        public static string FuncConcatStrings(string[] arr)
        {
            DataHnd h = API_Create_DataHnd("concat_strings");
            WriteStringArray(h, arr);
            DoCallString("concat_strings", h, out string result);
            return result;
        }

        public static string FuncSha3(string data)
        {
            DataHnd h = API_Create_DataHnd("sha3");
            WriteString(h, data);
            DoCallString("sha3", h, out string result);
            return result;
        }

        // ============================================================
        // 4. Performance test framework (true concurrency)
        // ============================================================

        private struct Stats
        {
            public double Avg, Min, Max, Median, StdDev;
            public int Count;
            public double Qps;
            public double TotalSec;
        }

        private static Stats ComputeStats(List<double> times, double totalSec)
        {
            if (times.Count == 0) return new Stats();
            times.Sort();
            double sum = 0;
            foreach (double t in times) sum += t;
            double mean = sum / times.Count;
            double sqSum = 0;
            foreach (double t in times) sqSum += (t - mean) * (t - mean);
            double stddev = Math.Sqrt(sqSum / times.Count);
            double median = times[times.Count / 2];
            double qps = times.Count / totalSec;
            return new Stats
            {
                Avg = mean,
                Min = times[0],
                Max = times[times.Count - 1],
                Median = median,
                StdDev = stddev,
                Count = times.Count,
                Qps = qps,
                TotalSec = totalSec
            };
        }

        private static Stats RunBenchmark(string name, int threads, int totalCalls, Action action)
        {
            var allTimes = new List<double>();
            var lockObj = new object();
            int callsPerThread = totalCalls / threads;
            int remainder = totalCalls % threads;
            var workers = new Thread[threads];
            var startTime = Stopwatch.StartNew();

            for (int i = 0; i < threads; i++)
            {
                int n = callsPerThread + (i < remainder ? 1 : 0);
                workers[i] = new Thread(() =>
                {
                    var local = new List<double>(n);
                    for (int j = 0; j < n; j++)
                    {
                        var sw = Stopwatch.StartNew();
                        action();
                        sw.Stop();
                        local.Add(sw.Elapsed.TotalMicroseconds);
                    }
                    lock (lockObj) allTimes.AddRange(local);
                });
                workers[i].Start();
            }

            foreach (var t in workers) t.Join();
            startTime.Stop();
            double elapsedSec = startTime.Elapsed.TotalSeconds;

            return ComputeStats(allTimes, elapsedSec);
        }

        private static void PrintStats(string name, Stats s)
        {
            Console.WriteLine($"{name,-18} {s.Avg,10:F3} {s.Min,10:F3} {s.Max,10:F3} {s.Median,10:F3} {s.StdDev,10:F3} {s.Count,10} {s.Qps,12:F2} {s.TotalSec,10:F3}");
        }

        // ============================================================
        // 5. Main program
        // ============================================================

        static void Main()
        {
            // ===== Configurable parameters =====
            const int THREADS = 100;         // concurrent threads
            const int TOTAL_CALLS = 1000;    // total calls per API
            // =================================

            Console.WriteLine("=== FuncClient True Concurrent Performance Test (C#) ===");
            Console.WriteLine($"Threads: {THREADS}, Total calls per API: {TOTAL_CALLS}");
            Console.WriteLine("⚠️  This test relies on the library's thread-safety.");
            Console.WriteLine("   All exported functions are fully thread-safe.");
            Console.WriteLine("   No locks are used – true concurrency is measured.");
            Console.WriteLine("Latency unit: microseconds (μs)\n");

            AppHnd app = API_Create_APPHnd("FuncClient", "Performance test client");
            if (!app.IsValid)
            {
                Console.WriteLine("Failed to create application handle.");
                return;
            }

            API_Reset_Prepare();
            API_Prepare_Client("ipc:func_service", app);
            API_Prepare_Client("127.0.0.1:9899", app);

            Console.WriteLine("Connecting to FuncService...");
            if (API_Prepare_Done() != 1)
            {
                Console.WriteLine("Connection failed. Please check console output for errors.");
                API_Free_APPHnd(app);
                API_shutdown();
                return;
            }
            Console.WriteLine("Connected.\n");

            // Warm-up (eliminate JIT and network initialisation overhead)
            Console.WriteLine("Warming up...");
            FuncAdd(1, 2);
            Console.WriteLine("Warm-up complete.\n");

            int[] intArr = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
            string[] strArr = { "Hello", "world", "from", "client", "test" };

            Console.WriteLine($"{"API",-18} {"Avg(μs)",10} {"Min(μs)",10} {"Max(μs)",10} {"Median(μs)",10} {"StdDev(μs)",10} {"Calls",10} {"QPS",12} {"Total(s)",10}");
            Console.WriteLine(new string('-', 110));

            Stats s;

            s = RunBenchmark("add", THREADS, TOTAL_CALLS, () => FuncAdd(10, 20));
            PrintStats("add", s);

            s = RunBenchmark("subtract", THREADS, TOTAL_CALLS, () => FuncSubtract(50, 30));
            PrintStats("subtract", s);

            s = RunBenchmark("multiply", THREADS, TOTAL_CALLS, () => FuncMultiply(6, 7));
            PrintStats("multiply", s);

            s = RunBenchmark("divide", THREADS, TOTAL_CALLS, () => FuncDivide(10, 3));
            PrintStats("divide", s);

            s = RunBenchmark("to_upper", THREADS, TOTAL_CALLS, () => FuncToUpper("hello"));
            PrintStats("to_upper", s);

            s = RunBenchmark("to_lower", THREADS, TOTAL_CALLS, () => FuncToLower("WORLD"));
            PrintStats("to_lower", s);

            s = RunBenchmark("reverse", THREADS, TOTAL_CALLS, () => FuncReverse("abcdef"));
            PrintStats("reverse", s);

            s = RunBenchmark("get_time", THREADS, TOTAL_CALLS, () => FuncGetTime());
            PrintStats("get_time", s);

            s = RunBenchmark("get_random", THREADS, TOTAL_CALLS, () => FuncGetRandom(1, 100));
            PrintStats("get_random", s);

            s = RunBenchmark("echo", THREADS, TOTAL_CALLS, () => FuncEcho("Hello from client"));
            PrintStats("echo", s);

            s = RunBenchmark("sum_array", THREADS, TOTAL_CALLS, () => FuncSumArray(intArr));
            PrintStats("sum_array", s);

            s = RunBenchmark("concat_strings", THREADS, TOTAL_CALLS, () => FuncConcatStrings(strArr));
            PrintStats("concat_strings", s);

            s = RunBenchmark("sha3", THREADS, TOTAL_CALLS, () => FuncSha3("The quick brown fox jumps over the lazy dog"));
            PrintStats("sha3", s);

            Console.WriteLine("\nAll benchmarks completed. Shutting down...");
            API_Exit_MainThread();
            API_Free_APPHnd(app);
            API_shutdown();
        }
    }
}