/**
 * @file func_service.cpp
 * @brief Service implementation that registers ~13 practical APIs over IPC and TCP.
 *        Includes a SHA3-256 cryptographic hash function (self-contained).
 *
 * This service demonstrates a multi-API server with a command console.
 * It exposes the following call APIs:
 *   - add(a, b)          -> int32_t
 *   - subtract(a, b)     -> int32_t
 *   - multiply(a, b)     -> int32_t
 *   - divide(a, b)       -> double
 *   - to_upper(str)      -> string
 *   - to_lower(str)      -> string
 *   - reverse(str)       -> string
 *   - get_time()         -> string (YYYY-MM-DD HH:MM:SS)
 *   - get_random(min, max) -> int32_t
 *   - echo(msg)          -> string
 *   - sum_array(arr)     -> int32_t
 *   - concat_strings(arr)-> string (space-separated)
 *   - sha3(data)         -> SHA3-256 hex digest (self-contained implementation)
 *
 * ============================================================================
 * INTEGRATION PARADIGM FOR EXTERNAL ALGORITHMS
 * ============================================================================
 * 1. Implement or include the algorithm (here: SHA3-256 in-line).
 * 2. Wrap the pure logic in a callback that reads from TDataHnd and writes back.
 * 3. Register the callback via API_Reg_Call.
 * 4. The client side provides a matching wrapper function.
 * This pattern works for any library: compression, encryption, ML inference, etc.
 * ============================================================================
 */

#include "API_HubTool.h"
#include <iostream>
#include <string>
#include <vector>
#include <cstring>
#include <ctime>
#include <random>
#include <chrono>
#include <thread>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <queue>
#include <sstream>
#include <iomanip>

using namespace std;

// ---------------------------------------------------------------------------
// Global state for command queue (synchronized)
// ---------------------------------------------------------------------------

static atomic<bool> g_bExit(false);
static mutex g_cmdMutex;
static condition_variable g_cv;
static queue<string> g_cmdQueue;

// ---------------------------------------------------------------------------
// SELF-CONTAINED SHA3-256 IMPLEMENTATION (based on Keccak-f[1600])
// Public domain, adapted from https://github.com/gvanas/KeccakCodePackage
// ---------------------------------------------------------------------------

#define KECCAK_ROUNDS 24
#define KECCAK_STATE_SIZE 1600   // 200 bytes

static const uint64_t KeccakRoundConstants[KECCAK_ROUNDS] = {
    0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL,
    0x8000000080008000ULL, 0x000000000000808bULL, 0x0000000080000001ULL,
    0x8000000080008081ULL, 0x8000000000008009ULL, 0x000000000000008aULL,
    0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000000aULL,
    0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL,
    0x8000000000008003ULL, 0x8000000000008002ULL, 0x8000000000000080ULL,
    0x000000000000800aULL, 0x800000008000000aULL, 0x8000000080008081ULL,
    0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL
};

static const unsigned int KeccakRhoOffsets[25] = {
    0, 1, 62, 28, 27, 36, 44, 6, 55, 20,
    3, 10, 43, 25, 39, 41, 45, 15, 21, 8,
    18, 2, 61, 56, 14
};

static inline uint64_t ROL64(uint64_t x, unsigned int n) {
    return (x << n) | (x >> (64 - n));
}

static void KeccakF1600(uint64_t state[25]) {
    int round;
    for (round = 0; round < KECCAK_ROUNDS; ++round) {
        // Theta
        uint64_t C[5], D[5];
        for (int x = 0; x < 5; ++x)
            C[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20];
        for (int x = 0; x < 5; ++x)
            D[x] = C[(x + 4) % 5] ^ ROL64(C[(x + 1) % 5], 1);
        for (int x = 0; x < 5; ++x)
            for (int y = 0; y < 5; ++y)
                state[x + 5 * y] ^= D[x];

        // Rho and Pi
        uint64_t current = state[1];
        for (int t = 0; t < 24; ++t) {
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
            else { x = 0; y = 0; } // should never happen

            uint64_t temp = state[x + 5 * y];
            state[x + 5 * y] = ROL64(current, KeccakRhoOffsets[t]);
            current = temp;
        }

        // Chi
        for (int y = 0; y < 5; ++y) {
            uint64_t temp[5];
            for (int x = 0; x < 5; ++x)
                temp[x] = state[x + 5 * y];
            for (int x = 0; x < 5; ++x)
                state[x + 5 * y] = temp[x] ^ ((~temp[(x + 1) % 5]) & temp[(x + 2) % 5]);
        }

        // Iota
        state[0] ^= KeccakRoundConstants[round];
    }
}

// SHA3-256: input bytes, output 32-byte hash
static void sha3_256(const uint8_t* input, size_t len, uint8_t hash[32]) {
    uint64_t state[25] = { 0 };
    size_t rate = 136; // 1600 - 2*256 = 1088 bits = 136 bytes

    // Absorb phase
    size_t offset = 0;
    while (len > 0) {
        size_t chunk = (len < rate - offset) ? len : (rate - offset);
        for (size_t i = 0; i < chunk; ++i) {
            state[(offset + i) >> 3] ^= (uint64_t)input[i] << (8 * ((offset + i) & 7));
        }
        offset += chunk;
        len -= chunk;
        input += chunk;
        if (offset == rate) {
            KeccakF1600(state);
            offset = 0;
        }
    }

    // Padding
    state[offset >> 3] ^= (uint64_t)0x06 << (8 * (offset & 7));
    state[(rate - 1) >> 3] ^= (uint64_t)0x80 << (8 * ((rate - 1) & 7));
    KeccakF1600(state);

    // Squeeze phase (truncate to 32 bytes)
    for (size_t i = 0; i < 32; ++i) {
        hash[i] = (uint8_t)(state[i >> 3] >> (8 * (i & 7)));
    }
}

// ---------------------------------------------------------------------------
// Business function: SHA3-256 of a string, returns hex string
// ---------------------------------------------------------------------------
static string Sha3_256_Hex(const string& input) {
    uint8_t hash[32];
    sha3_256((const uint8_t*)input.data(), input.size(), hash);
    ostringstream oss;
    for (int i = 0; i < 32; ++i)
        oss << hex << setw(2) << setfill('0') << (int)hash[i];
    return oss.str();
}

// ---------------------------------------------------------------------------
// Serialization helpers (read/write basic types and containers)
// These are used by callbacks to extract parameters and write results.
// They are stateless and thread-safe (operate only on given TDataHnd).
// ---------------------------------------------------------------------------

static inline void WriteInt(TDataHnd h, int32_t v) {
    API_WriteBuffer(h, &v, sizeof(v));
}

static inline void WriteDouble(TDataHnd h, double v) {
    API_WriteBuffer(h, &v, sizeof(v));
}

static inline void WriteString(TDataHnd h, const string& s) {
    int32_t len = (int32_t)s.size();
    WriteInt(h, len);
    if (len > 0) API_WriteBuffer(h, s.data(), len);
}

static inline void WriteIntArray(TDataHnd h, const vector<int32_t>& arr) {
    int32_t n = (int32_t)arr.size();
    WriteInt(h, n);
    for (auto v : arr) WriteInt(h, v);
}

static inline void WriteStringArray(TDataHnd h, const vector<string>& arr) {
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

static inline bool ReadString(TDataHnd h, string& s) {
    int32_t len;
    if (!ReadInt(h, len)) return false;
    s.resize(len);
    if (len > 0) {
        int64_t read = API_ReadBuffer(h, &s[0], len);
        if (read != len) { s.clear(); return false; }
    }
    return true;
}

static inline bool ReadIntArray(TDataHnd h, vector<int32_t>& arr) {
    int32_t n;
    if (!ReadInt(h, n)) return false;
    arr.resize(n);
    for (int i = 0; i < n; ++i) {
        if (!ReadInt(h, arr[i])) { arr.clear(); return false; }
    }
    return true;
}

static inline bool ReadStringArray(TDataHnd h, vector<string>& arr) {
    int32_t n;
    if (!ReadInt(h, n)) return false;
    arr.resize(n);
    for (int i = 0; i < n; ++i) {
        if (!ReadString(h, arr[i])) { arr.clear(); return false; }
    }
    return true;
}

// ---------------------------------------------------------------------------
// Core business logic (pure functions, no serialization)
// These are the actual implementations of the APIs.
// They are thread-safe (stateless or use only local data).
// ---------------------------------------------------------------------------

static int32_t Add(int32_t a, int32_t b) { return a + b; }
static int32_t Subtract(int32_t a, int32_t b) { return a - b; }
static int32_t Multiply(int32_t a, int32_t b) { return a * b; }
static double Divide(int32_t a, int32_t b) {
    if (b == 0) { cerr << "Divide by zero!" << endl; return 0.0; }
    return static_cast<double>(a) / b;
}
static string ToUpper(const string& s) {
    string r = s;
    for (auto& c : r) c = toupper(static_cast<unsigned char>(c));
    return r;
}
static string ToLower(const string& s) {
    string r = s;
    for (auto& c : r) c = tolower(static_cast<unsigned char>(c));
    return r;
}
static string ReverseString(const string& s) {
    return string(s.rbegin(), s.rend());
}
static string GetCurrentTime() {
    auto now = chrono::system_clock::now();
    time_t t = chrono::system_clock::to_time_t(now);
    tm tm;
#ifdef _WIN32
    localtime_s(&tm, &t);
#else
    localtime_r(&t, &tm);
#endif
    ostringstream oss;
    oss << put_time(&tm, "%Y-%m-%d %H:%M:%S");
    return oss.str();
}
static int32_t GetRandom(int32_t min, int32_t max) {
    static random_device rd;
    static mt19937 gen(rd());
    uniform_int_distribution<int32_t> dist(min, max);
    return dist(gen);
}
static string Echo(const string& s) { return s; }
static int32_t SumArray(const vector<int32_t>& arr) {
    int32_t sum = 0;
    for (auto v : arr) sum += v;
    return sum;
}
static string ConcatStrings(const vector<string>& arr) {
    ostringstream oss;
    for (size_t i = 0; i < arr.size(); ++i) {
        if (i) oss << ' ';
        oss << arr[i];
    }
    return oss.str();
}

// ---------------------------------------------------------------------------
// API Callback Functions (invoked by the library)
// These extract parameters from TDataHnd, call the business logic,
// and write the result back to the output handle.
//
// CRITICAL THREADING NOTES:
// - These callbacks are executed by the library. They may be called on
//   the main thread or on internal worker threads.
// - They must NOT block (no sleep, no waiting for locks that might be held
//   by the main thread, no I/O that could block indefinitely).
// - They must NOT call any API functions that could block (e.g., API_Call)
//   because that could lead to deadlock if the callback is running on the
//   same thread that processes network events.
// - They should not access shared mutable state without proper locking;
//   if they do, use mutexes or other synchronization primitives.
// - In this example, all callbacks are stateless and only operate on
//   the provided TDataHnd objects, so they are thread-safe.
// ---------------------------------------------------------------------------

static void __cdecl AddCallback(void* /*Trigger*/, void* Input, void* Output) {
    TDataHnd hIn = (TDataHnd)Input, hOut = (TDataHnd)Output;
    int32_t a, b;
    if (!ReadInt(hIn, a) || !ReadInt(hIn, b)) return;
    int32_t result = Add(a, b);
    WriteInt(hOut, result);
}

static void __cdecl SubtractCallback(void* /*Trigger*/, void* Input, void* Output) {
    TDataHnd hIn = (TDataHnd)Input, hOut = (TDataHnd)Output;
    int32_t a, b;
    if (!ReadInt(hIn, a) || !ReadInt(hIn, b)) return;
    int32_t result = Subtract(a, b);
    WriteInt(hOut, result);
}

static void __cdecl MultiplyCallback(void* /*Trigger*/, void* Input, void* Output) {
    TDataHnd hIn = (TDataHnd)Input, hOut = (TDataHnd)Output;
    int32_t a, b;
    if (!ReadInt(hIn, a) || !ReadInt(hIn, b)) return;
    int32_t result = Multiply(a, b);
    WriteInt(hOut, result);
}

static void __cdecl DivideCallback(void* /*Trigger*/, void* Input, void* Output) {
    TDataHnd hIn = (TDataHnd)Input, hOut = (TDataHnd)Output;
    int32_t a, b;
    if (!ReadInt(hIn, a) || !ReadInt(hIn, b)) return;
    double result = Divide(a, b);
    WriteDouble(hOut, result);
}

static void __cdecl ToUpperCallback(void* /*Trigger*/, void* Input, void* Output) {
    TDataHnd hIn = (TDataHnd)Input, hOut = (TDataHnd)Output;
    string s;
    if (!ReadString(hIn, s)) return;
    string result = ToUpper(s);
    WriteString(hOut, result);
}

static void __cdecl ToLowerCallback(void* /*Trigger*/, void* Input, void* Output) {
    TDataHnd hIn = (TDataHnd)Input, hOut = (TDataHnd)Output;
    string s;
    if (!ReadString(hIn, s)) return;
    string result = ToLower(s);
    WriteString(hOut, result);
}

static void __cdecl ReverseCallback(void* /*Trigger*/, void* Input, void* Output) {
    TDataHnd hIn = (TDataHnd)Input, hOut = (TDataHnd)Output;
    string s;
    if (!ReadString(hIn, s)) return;
    string result = ReverseString(s);
    WriteString(hOut, result);
}

static void __cdecl GetTimeCallback(void* /*Trigger*/, void* /*Input*/, void* Output) {
    TDataHnd hOut = (TDataHnd)Output;
    string result = GetCurrentTime();
    WriteString(hOut, result);
}

static void __cdecl GetRandomCallback(void* /*Trigger*/, void* Input, void* Output) {
    TDataHnd hIn = (TDataHnd)Input, hOut = (TDataHnd)Output;
    int32_t min, max;
    if (!ReadInt(hIn, min) || !ReadInt(hIn, max)) return;
    int32_t result = GetRandom(min, max);
    WriteInt(hOut, result);
}

static void __cdecl EchoCallback(void* /*Trigger*/, void* Input, void* Output) {
    TDataHnd hIn = (TDataHnd)Input, hOut = (TDataHnd)Output;
    string s;
    if (!ReadString(hIn, s)) return;
    string result = Echo(s);
    WriteString(hOut, result);
}

static void __cdecl SumArrayCallback(void* /*Trigger*/, void* Input, void* Output) {
    TDataHnd hIn = (TDataHnd)Input, hOut = (TDataHnd)Output;
    vector<int32_t> arr;
    if (!ReadIntArray(hIn, arr)) return;
    int32_t result = SumArray(arr);
    WriteInt(hOut, result);
}

static void __cdecl ConcatStringsCallback(void* /*Trigger*/, void* Input, void* Output) {
    TDataHnd hIn = (TDataHnd)Input, hOut = (TDataHnd)Output;
    vector<string> arr;
    if (!ReadStringArray(hIn, arr)) return;
    string result = ConcatStrings(arr);
    WriteString(hOut, result);
}

// ---------------------------------------------------------------------------
// SHA3 Callback
// ---------------------------------------------------------------------------
static void __cdecl Sha3Callback(void* /*Trigger*/, void* Input, void* Output) {
    TDataHnd hIn = (TDataHnd)Input, hOut = (TDataHnd)Output;
    string input;
    if (!ReadString(hIn, input)) return;
    string result = Sha3_256_Hex(input);
    WriteString(hOut, result);
}

// ---------------------------------------------------------------------------
// Console thread (reads user commands)
// ---------------------------------------------------------------------------

/**
 * @brief Thread function that reads commands from stdin.
 *
 * This thread does NOT call any API_HubTool functions.
 * It simply pushes commands into a thread-safe queue and notifies
 * the main thread via a condition variable.
 * This separation ensures that all API calls remain on the main thread.
 */
static void ConsoleThread() {
    string line;
    while (!g_bExit) {
        cout << "FuncService> ";
        getline(cin, line);
        if (line == "exit") {
            g_bExit = true;
            break;
        }
        {
            lock_guard<mutex> lock(g_cmdMutex);
            g_cmdQueue.push(line);
        }
        g_cv.notify_one();   // wake up the main thread
    }
}

/**
 * @brief Process a command on the main thread.
 *
 * Since this function is called only from the main thread,
 * it is safe to call any API functions here (if needed).
 * Currently it handles only "status".
 *
 * @param cmd  The command string.
 * @param app  The application handle (unused).
 */
static void ProcessCommand(const string& cmd, TAppHnd /*app*/) {
    if (cmd == "status") {
        cout << "[Service] Status: running." << endl;
    }
    else {
        cout << "Unknown command: " << cmd << endl;
    }
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

int main() {
    cout << "=== API Hub FuncService ===" << endl;

    // 1. Load the dynamic library. Must be called before any other API.
    if (!API_LoadLibrary()) {
        cerr << "Failed to load API Hub library." << endl;
        return 1;
    }

    // 2. Create an application context that will expose the APIs.
    TAppHnd app = API_Create_APPHnd("FuncService", "Functional service with 13 APIs");
    if (!app) {
        cerr << "Failed to create application." << endl;
        API_FreeLibrary();
        return 1;
    }

    // 3. Register all call APIs with detailed C-style signature descriptions.
    //    The callbacks will be invoked by the library when a remote call arrives.
    API_Reg_Call(app, "add", "int32_t add(int32_t a, int32_t b) - Add two integers", nullptr, AddCallback);
    API_Reg_Call(app, "subtract", "int32_t subtract(int32_t a, int32_t b) - Subtract b from a", nullptr, SubtractCallback);
    API_Reg_Call(app, "multiply", "int32_t multiply(int32_t a, int32_t b) - Multiply two integers", nullptr, MultiplyCallback);
    API_Reg_Call(app, "divide", "double divide(int32_t a, int32_t b) - Divide a by b (returns double)", nullptr, DivideCallback);
    API_Reg_Call(app, "to_upper", "char* to_upper(const char* str) - Convert string to uppercase", nullptr, ToUpperCallback);
    API_Reg_Call(app, "to_lower", "char* to_lower(const char* str) - Convert string to lowercase", nullptr, ToLowerCallback);
    API_Reg_Call(app, "reverse", "char* reverse(const char* str) - Reverse a string", nullptr, ReverseCallback);
    API_Reg_Call(app, "get_time", "char* get_time() - Get current time as 'YYYY-MM-DD HH:MM:SS'", nullptr, GetTimeCallback);
    API_Reg_Call(app, "get_random", "int32_t get_random(int32_t min, int32_t max) - Get random integer in [min, max]", nullptr, GetRandomCallback);
    API_Reg_Call(app, "echo", "char* echo(const char* msg) - Echo input string", nullptr, EchoCallback);
    API_Reg_Call(app, "sum_array", "int32_t sum_array(const int32_t* arr, int32_t count) - Sum an array of integers", nullptr, SumArrayCallback);
    API_Reg_Call(app, "concat_strings", "char* concat_strings(const char* arr[], int32_t count) - Concatenate strings with spaces", nullptr, ConcatStringsCallback);
    // New SHA3 API
    API_Reg_Call(app, "sha3", "char* sha3(const char* data) - SHA3-256 hash (hex)", nullptr, Sha3Callback);

    cout << "Registered 13 APIs." << endl;

    // 4. Prepare network endpoints: IPC and TCP services,
    //    and also connect as a client to ourselves to allow local calls.
    API_Reset_Prepare();
    API_Prepare_Service("ipc:func_service", "ipc:func_service");
    API_Prepare_Service("0.0.0.0", "127.0.0.1:9899");
    API_Prepare_Client("ipc:func_service", app);
    API_Prepare_Client("127.0.0.1:9899", app);

    // 5. Start the framework. This call blocks until the network is ready.
    cout << "Starting service..." << endl;
    if (API_Prepare_Done() != 1) {
        cerr << "Prepare_Done failed." << endl;
        // Note: API_Get_Status() is no longer available; check console output.
        API_Free_APPHnd(app);
        API_shutdown();
        API_FreeLibrary();
        return 1;
    }

    cout << "Service is running." << endl;
    cout << "Type 'exit' to stop." << endl;

    // 6. Start the console input thread.
    //    This thread does not call any API functions.
    thread consoleThread(ConsoleThread);

    // 7. Main event loop (runs on the same thread as API_Prepare_Done).
    //    - Process queued commands.
    //    - Sleep briefly to avoid busy-waiting.
    //    All API functions (if any) are called only from this thread.
    while (!g_bExit) {
        string cmd;
        {
            lock_guard<mutex> lock(g_cmdMutex);
            if (!g_cmdQueue.empty()) {
                cmd = g_cmdQueue.front();
                g_cmdQueue.pop();
            }
        }
        if (!cmd.empty()) {
            ProcessCommand(cmd, app);
        }

        // Status messages are printed to console automatically.

        this_thread::sleep_for(chrono::milliseconds(100));
    }

    // 8. Wait for console thread to finish.
    if (consoleThread.joinable())
        consoleThread.join();

    // 9. Graceful shutdown.
    cout << "Shutting down..." << endl;
    API_Exit_MainThread();      // Signal the library to stop its internal loop
    API_Free_APPHnd(app);       // Release application resources
    API_shutdown();             // Stop all services and clients
    API_FreeLibrary();          // Unload the dynamic library

    cout << "Service stopped." << endl;
    return 0;
}