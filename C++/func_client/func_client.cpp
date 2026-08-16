/**
 * @file func_client.cpp
 * @brief True concurrent performance test for FuncService.
 *        Each API call runs in its own thread, no serialization.
 *        Measures latency and throughput of 13 remote APIs.
 */

#include "func_client.h"
#include "API_HubTool.h"
#include <iostream>
#include <iomanip>
#include <vector>
#include <string>
#include <thread>
#include <mutex>
#include <chrono>
#include <random>
#include <algorithm>
#include <cmath>
#include <numeric>
#include <atomic>

static int g_default_timeout = 5000;

void set_default_timeout(int timeout_ms) {
    g_default_timeout = timeout_ms;
}

// -------------------------------------------------------------------------
// Serialization helpers (same as before)
// -------------------------------------------------------------------------
static inline void WriteInt(TDataHnd h, int32_t v) {
    API_WriteBuffer(h, &v, sizeof(v));
}
static inline void WriteDouble(TDataHnd h, double v) {
    API_WriteBuffer(h, &v, sizeof(v));
}
static inline void WriteString(TDataHnd h, const std::string& s) {
    int32_t len = (int32_t)s.size();
    WriteInt(h, len);
    if (len > 0) API_WriteBuffer(h, s.data(), len);
}
static inline void WriteIntArray(TDataHnd h, const std::vector<int32_t>& arr) {
    int32_t n = (int32_t)arr.size();
    WriteInt(h, n);
    for (auto v : arr) WriteInt(h, v);
}
static inline void WriteStringArray(TDataHnd h, const std::vector<std::string>& arr) {
    int32_t n = (int32_t)arr.size();
    WriteInt(h, n);
    for (const auto& s : arr) WriteString(h, s);
}
static inline bool ReadInt(TDataHnd h, int32_t& v) {
    return API_ReadBuffer(h, &v, sizeof(v)) == sizeof(v);
}
static inline bool ReadDouble(TDataHnd h, double& v) {
    return API_ReadBuffer(h, &v, sizeof(v)) == sizeof(v);
}
static inline bool ReadString(TDataHnd h, std::string& s) {
    int32_t len;
    if (!ReadInt(h, len)) return false;
    s.resize(len);
    if (len > 0) {
        int64_t read = API_ReadBuffer(h, &s[0], len);
        if (read != len) { s.clear(); return false; }
    }
    return true;
}

// -------------------------------------------------------------------------
// DoCall wrappers (now WITHOUT mutex – library is thread-safe)
// -------------------------------------------------------------------------
static bool DoCallInt(const char* apiName, TDataHnd param, int32_t& result) {
    TDataHnd hResult = API_Call("FuncService", param, g_default_timeout);
    API_Free_DataHnd(param);
    if (!hResult || API_GetSize(hResult) == 0) {
        if (hResult) API_Free_DataHnd(hResult);
        return false;
    }
    bool ok = ReadInt(hResult, result);
    API_Free_DataHnd(hResult);
    return ok;
}
static bool DoCallDouble(const char* apiName, TDataHnd param, double& result) {
    TDataHnd hResult = API_Call("FuncService", param, g_default_timeout);
    API_Free_DataHnd(param);
    if (!hResult || API_GetSize(hResult) == 0) {
        if (hResult) API_Free_DataHnd(hResult);
        return false;
    }
    bool ok = ReadDouble(hResult, result);
    API_Free_DataHnd(hResult);
    return ok;
}
static bool DoCallString(const char* apiName, TDataHnd param, std::string& result) {
    TDataHnd hResult = API_Call("FuncService", param, g_default_timeout);
    API_Free_DataHnd(param);
    if (!hResult || API_GetSize(hResult) == 0) {
        if (hResult) API_Free_DataHnd(hResult);
        return false;
    }
    bool ok = ReadString(hResult, result);
    API_Free_DataHnd(hResult);
    return ok;
}

// -------------------------------------------------------------------------
// Wrapper functions (unchanged)
// -------------------------------------------------------------------------
int32_t func_add(int32_t a, int32_t b) {
    TDataHnd h = API_Create_DataHnd("add");
    WriteInt(h, a); WriteInt(h, b);
    int32_t result = 0;
    DoCallInt("add", h, result);
    return result;
}
int32_t func_subtract(int32_t a, int32_t b) {
    TDataHnd h = API_Create_DataHnd("subtract");
    WriteInt(h, a); WriteInt(h, b);
    int32_t result = 0;
    DoCallInt("subtract", h, result);
    return result;
}
int32_t func_multiply(int32_t a, int32_t b) {
    TDataHnd h = API_Create_DataHnd("multiply");
    WriteInt(h, a); WriteInt(h, b);
    int32_t result = 0;
    DoCallInt("multiply", h, result);
    return result;
}
double func_divide(int32_t a, int32_t b) {
    TDataHnd h = API_Create_DataHnd("divide");
    WriteInt(h, a); WriteInt(h, b);
    double result = 0.0;
    DoCallDouble("divide", h, result);
    return result;
}
std::string func_to_upper(const std::string& s) {
    TDataHnd h = API_Create_DataHnd("to_upper");
    WriteString(h, s);
    std::string result;
    DoCallString("to_upper", h, result);
    return result;
}
std::string func_to_lower(const std::string& s) {
    TDataHnd h = API_Create_DataHnd("to_lower");
    WriteString(h, s);
    std::string result;
    DoCallString("to_lower", h, result);
    return result;
}
std::string func_reverse(const std::string& s) {
    TDataHnd h = API_Create_DataHnd("reverse");
    WriteString(h, s);
    std::string result;
    DoCallString("reverse", h, result);
    return result;
}
std::string func_get_time() {
    TDataHnd h = API_Create_DataHnd("get_time");
    std::string result;
    DoCallString("get_time", h, result);
    return result;
}
int32_t func_get_random(int32_t min, int32_t max) {
    TDataHnd h = API_Create_DataHnd("get_random");
    WriteInt(h, min); WriteInt(h, max);
    int32_t result = 0;
    DoCallInt("get_random", h, result);
    return result;
}
std::string func_echo(const std::string& s) {
    TDataHnd h = API_Create_DataHnd("echo");
    WriteString(h, s);
    std::string result;
    DoCallString("echo", h, result);
    return result;
}
int32_t func_sum_array(const std::vector<int32_t>& arr) {
    TDataHnd h = API_Create_DataHnd("sum_array");
    WriteIntArray(h, arr);
    int32_t result = 0;
    DoCallInt("sum_array", h, result);
    return result;
}
std::string func_concat_strings(const std::vector<std::string>& arr) {
    TDataHnd h = API_Create_DataHnd("concat_strings");
    WriteStringArray(h, arr);
    std::string result;
    DoCallString("concat_strings", h, result);
    return result;
}
std::string func_sha3(const std::string& data) {
    TDataHnd h = API_Create_DataHnd("sha3");
    WriteString(h, data);
    std::string result;
    DoCallString("sha3", h, result);
    return result;
}

// -------------------------------------------------------------------------
// Statistics
// -------------------------------------------------------------------------
struct Stats {
    double avg;
    double min;
    double max;
    double median;
    double stddev;
    size_t count;
    double qps;          // calls per second
    double total_sec;    // total elapsed time
};

static Stats compute_stats(std::vector<double>& times, double elapsed_sec) {
    if (times.empty()) return { 0,0,0,0,0,0,0,0 };
    std::sort(times.begin(), times.end());
    double sum = std::accumulate(times.begin(), times.end(), 0.0);
    double mean = sum / times.size();
    double sq_sum = std::inner_product(times.begin(), times.end(), times.begin(), 0.0);
    double stddev = std::sqrt(sq_sum / times.size() - mean * mean);
    double median = times[times.size() / 2];
    double qps = times.size() / elapsed_sec;
    return { mean, times.front(), times.back(), median, stddev, times.size(), qps, elapsed_sec };
}

// -------------------------------------------------------------------------
// Concurrent benchmark: one thread per call
// -------------------------------------------------------------------------
template<typename Func, typename... Args>
static Stats run_benchmark(const std::string& name, int total_calls, Func func, Args... args) {
    std::vector<double> all_times;
    all_times.reserve(total_calls);
    std::mutex vec_mutex;

    std::vector<std::thread> threads;
    threads.reserve(total_calls);

    auto start_time = std::chrono::high_resolution_clock::now();

    for (int i = 0; i < total_calls; ++i) {
        threads.emplace_back([&, func, args...]() {
            auto start = std::chrono::high_resolution_clock::now();
            func(args...);   // execute the remote call
            auto end = std::chrono::high_resolution_clock::now();
            double us = std::chrono::duration<double, std::micro>(end - start).count();
            std::lock_guard<std::mutex> lock(vec_mutex);
            all_times.push_back(us);
            });
    }

    for (auto& t : threads) t.join();

    auto end_time = std::chrono::high_resolution_clock::now();
    double elapsed_sec = std::chrono::duration<double>(end_time - start_time).count();

    return compute_stats(all_times, elapsed_sec);
}

// Helper to print stats (convert microseconds to milliseconds)
static void print_stats(const std::string& name, const Stats& s) {
    std::cout << std::left << std::setw(18) << name
        << std::right << std::setw(10) << std::fixed << std::setprecision(3) << (s.avg / 1000.0)
        << std::setw(10) << (s.min / 1000.0)
        << std::setw(10) << (s.max / 1000.0)
        << std::setw(10) << (s.median / 1000.0)
        << std::setw(10) << (s.stddev / 1000.0)
        << std::setw(10) << s.count
        << std::setw(12) << std::setprecision(2) << s.qps
        << std::setw(10) << std::setprecision(3) << s.total_sec
        << std::endl;
}

// -------------------------------------------------------------------------
// Main
// -------------------------------------------------------------------------
int main() {
    std::cout << "============================================================\n";
    std::cout << "  FuncClient True Concurrent Performance Test\n";
    std::cout << "  Each call runs in its own thread (no serialization)\n";
    std::cout << "  Times in milliseconds (ms), QPS = calls per second\n";
    std::cout << "============================================================\n\n";

    if (!API_LoadLibrary()) {
        std::cerr << "Failed to load API Hub library." << std::endl;
        return 1;
    }

    TAppHnd app = API_Create_APPHnd("FuncClient", "Concurrent test client");
    if (!app) {
        std::cerr << "Failed to create application handle." << std::endl;
        API_FreeLibrary();
        return 1;
    }

    API_Reset_Prepare();
    API_Prepare_Client("ipc:func_service", app);
    // Optionally also connect via TCP:
    API_Prepare_Client("127.0.0.1:9899", app);

    std::cout << "Connecting to FuncService..." << std::endl;
    if (API_Prepare_Done() != 1) {
        std::cerr << "Failed to connect." << std::endl;
        // Note: API_Get_Status() is no longer available; check console output.
        API_Free_APPHnd(app);
        API_shutdown();
        API_FreeLibrary();
        return 1;
    }
    std::cout << "Connected.\n" << std::endl;

    // Warm-up: single call to ensure everything is ready
    func_add(1, 2);

    set_default_timeout(5000);

    const int TOTAL_CALLS = 100;  // adjust as needed – each call creates a thread

    std::cout << std::left << std::setw(18) << "API"
        << std::right << std::setw(10) << "Avg(ms)"
        << std::setw(10) << "Min(ms)"
        << std::setw(10) << "Max(ms)"
        << std::setw(10) << "Median(ms)"
        << std::setw(10) << "StdDev(ms)"
        << std::setw(10) << "Calls"
        << std::setw(12) << "QPS"
        << std::setw(10) << "Total(s)"
        << std::endl;
    std::cout << std::string(100, '-') << std::endl;

    std::vector<int32_t> int_arr = { 1,2,3,4,5,6,7,8,9,10 };
    std::vector<std::string> str_arr = { "Hello", "world", "from", "client", "test" };

    Stats s;

    s = run_benchmark("add", TOTAL_CALLS, func_add, 10, 20);
    print_stats("add", s);

    s = run_benchmark("subtract", TOTAL_CALLS, func_subtract, 50, 30);
    print_stats("subtract", s);

    s = run_benchmark("multiply", TOTAL_CALLS, func_multiply, 6, 7);
    print_stats("multiply", s);

    s = run_benchmark("divide", TOTAL_CALLS, func_divide, 10, 3);
    print_stats("divide", s);

    s = run_benchmark("to_upper", TOTAL_CALLS, func_to_upper, std::string("hello"));
    print_stats("to_upper", s);

    s = run_benchmark("to_lower", TOTAL_CALLS, func_to_lower, std::string("WORLD"));
    print_stats("to_lower", s);

    s = run_benchmark("reverse", TOTAL_CALLS, func_reverse, std::string("abcdef"));
    print_stats("reverse", s);

    s = run_benchmark("get_time", TOTAL_CALLS, func_get_time);
    print_stats("get_time", s);

    s = run_benchmark("get_random", TOTAL_CALLS, func_get_random, 1, 100);
    print_stats("get_random", s);

    s = run_benchmark("echo", TOTAL_CALLS, func_echo, std::string("Hello from client"));
    print_stats("echo", s);

    s = run_benchmark("sum_array", TOTAL_CALLS, func_sum_array, int_arr);
    print_stats("sum_array", s);

    s = run_benchmark("concat_strings", TOTAL_CALLS, func_concat_strings, str_arr);
    print_stats("concat_strings", s);

    s = run_benchmark("sha3", TOTAL_CALLS, func_sha3, std::string("The quick brown fox jumps over the lazy dog"));
    print_stats("sha3", s);

    std::cout << "\nAll benchmarks completed.\n";

    API_Exit_MainThread();
    API_Free_APPHnd(app);
    API_shutdown();
    API_FreeLibrary();

    return 0;
}