// CrossCall.cpp - Client that calls 'add' and 'inv_seri' concurrently.
// It connects to the IPC endpoint "ipc:cross" and runs a 10-second load test.

#include "API_HubTool.hpp"
#include <iostream>
#include <thread>
#include <chrono>
#include <random>
#include <cstdint>
#include <atomic>
#include <vector>

using namespace z_api_hub;

// ---------- Remote call: add ----------
static int32_t Add(int32_t a, int32_t b) {
    DataHandle param("add");
    param.writeInt32(a);
    param.writeInt32(b);

    TDataHnd rawResult = API_Call("demo", param.get(), 1000);
    if (!rawResult || API_GetSize(rawResult) == 0) {
        if (rawResult) API_Free_DataHnd(rawResult);
        return 0;
    }
    DataHandle result(rawResult, true);   // take ownership
    int32_t c = 0;
    if (!result.readInt32(&c)) c = 0;
    return c;
}

// ---------- Remote call: inv_seri ----------
static std::string InvSeri() {
    // Input data sequence
    uint8_t  b = 200;
    uint16_t w = 0x10;
    uint32_t c = 0x2F;
    uint64_t u64 = 0x3F;
    std::string s = "hello world";
    float    f = 3.14f;

    DataHandle param("inv_seri");
    param.writeUInt8(b);
    param.writeUInt16(w);
    param.writeUInt32(c);
    param.writeUInt64(u64);
    param.writeString(s);
    param.writeSingle(f);

    TDataHnd rawResult = API_Call("demo", param.get(), 1000);
    if (!rawResult || API_GetSize(rawResult) == 0) {
        if (rawResult) API_Free_DataHnd(rawResult);
        return "Timeout or error";
    }
    DataHandle result(rawResult, true);

    // Read back in reverse order
    float    f2;
    std::string s2;
    uint64_t u64_2;
    uint32_t c2;
    uint16_t w2;
    uint8_t  b2;

    if (!result.readSingle(&f2) ||
        !result.readString(&s2) ||
        !result.readUInt64(&u64_2) ||
        !result.readUInt32(&c2) ||
        !result.readUInt16(&w2) ||
        !result.readUInt8(&b2)) {
        return "Failed to read reply";
    }

    char buf[256];
    snprintf(buf, sizeof(buf),
        "Reply: [%d, %d, %d, %llu, \"%s\", %.2f]  Original: [%d, %d, %d, %llu, \"%s\", %.2f]",
        (int)b2, w2, c2, (unsigned long long)u64_2, s2.c_str(), f2,
        (int)b, w, c, (unsigned long long)u64, s.c_str(), f);
    return std::string(buf);
}

int main() {
    std::cout << "=== Cross Call (Client) ===" << std::endl;

    // Load library (RAII)
    LibraryLoader loader;

    // Connect as pure consumer (do not expose any API)
    resetPrepare();
    int prep = API_Prepare_Client("ipc:cross", nullptr);
    if (prep == 0) {
        std::cerr << "API_Prepare_Client failed." << std::endl;
        return 1;
    }

    if (API_Prepare_Done() != 1) {
        std::cerr << "API_Prepare_Done failed. Check console output." << std::endl;
        API_shutdown();
        return 1;
    }

    std::cout << "Connected to ipc:cross. Starting 10-second load test..." << std::endl;

    const int THREADS = 10;
    const int DURATION_SEC = 10;
    std::atomic<bool> stopFlag(false);
    std::vector<std::thread> threads;

    // Launch worker threads
    for (int i = 0; i < THREADS; ++i) {
        threads.emplace_back([i, &stopFlag]() {
            std::mt19937 rng(i + std::random_device{}());
            std::uniform_int_distribution<int> dist(0, 1);
            std::uniform_int_distribution<int> numDist(1, 1000);

            while (!stopFlag.load()) {
                if (dist(rng) == 0) {
                    int a = numDist(rng);
                    int b = numDist(rng);
                    int result = Add(a, b);
                    if (result != 0)
                        std::cout << "[Client " << i << "] add(" << a << "," << b << ") = " << result << std::endl;
                    else
                        std::cout << "[Client " << i << "] add(" << a << "," << b << ") timed out or failed." << std::endl;
                }
                else {
                    std::string msg = InvSeri();
                    std::cout << "[Client " << i << "] " << msg << std::endl;
                }
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
            }
            });
    }

    // Run for DURATION_SEC seconds
    std::this_thread::sleep_for(std::chrono::seconds(DURATION_SEC));
    stopFlag.store(true);

    // Join all threads
    for (auto& t : threads) {
        if (t.joinable()) t.join();
    }

    std::cout << "Load test finished. Press Enter to exit..." << std::endl;
    std::cin.get();

    API_Exit_MainThread();
    API_shutdown();
    return 0;
}