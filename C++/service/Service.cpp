/**
 * @file Service.cpp
 * @brief Service-side implementation that provides public APIs over IPC.
 *
 * This service registers three call APIs (add, echo, get_time) and runs
 * a console command loop. It demonstrates the recommended thread model:
 * - All API calls (including callback invocations) must be executed from
 *   the same thread that called API_Prepare_Done().
 * - The library is NOT thread-safe; do not call any API functions from
 *   arbitrary threads.
 * - Callbacks (AddCallback, EchoCallback, GetTimeCallback) are invoked by
 *   the library internally, either on the main thread or on a background
 *   thread pool. Therefore, callbacks must not block or call any other
 *   API functions that could cause deadlocks.
 * - Console input is handled by a separate thread; commands are queued
 *   and processed in the main thread to avoid concurrent API access.
 */

#include <iostream>
#include <string>
#include <cstring>
#include <ctime>
#include <thread>
#include <chrono>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <queue>
#include "API_HubTool.h"

using namespace std;

// ---------------------------------------------------------------------------
// Global state for thread-safe command queue
// ---------------------------------------------------------------------------

/** Flag to signal the main loop to exit. */
static atomic<bool> g_bExit(false);

/** Mutex protecting the command queue. */
static mutex g_cmdMutex;

/** Condition variable to wake the main thread when a command arrives. */
static condition_variable g_cv;

/** Queue of console commands to be processed by the main thread. */
static queue<string> g_cmdQueue;

// ---------------------------------------------------------------------------
// API Callback Implementations
// These are invoked by the library when a remote call arrives.
// IMPORTANT: They run in the library's execution context (main thread or
//            worker threads). They must be non-blocking and must not call
//            other API functions (e.g., API_Call) that could cause deadlock.
//            They also must NOT use any global mutable state without proper
//            synchronization, because they may be called concurrently by
//            multiple threads (depending on the library's internal design).
//            In this example, they are simple and stateless.
// ---------------------------------------------------------------------------

/**
 * @brief Callback for "add" API: reads two integers and writes their sum.
 * @param Trigger  User-supplied pointer (unused here).
 * @param Input    TDataHnd containing the two ints.
 * @param Output   TDataHnd where the result (int) is written.
 *
 * Thread-safety: This callback is called by the library. It is assumed to
 * be invoked in a serialized manner (i.e., not concurrently with itself),
 * but it's still good practice to avoid side effects on shared data.
 */
static void __cdecl AddCallback(void* /*Trigger*/, void* Input, void* Output)
{
    TDataHnd hIn = (TDataHnd)Input;
    TDataHnd hOut = (TDataHnd)Output;

    int a, b;
    if (API_ReadBuffer(hIn, &a, sizeof(int)) != sizeof(int)) return;
    if (API_ReadBuffer(hIn, &b, sizeof(int)) != sizeof(int)) return;

    int sum = a + b;
    API_WriteBuffer(hOut, &sum, sizeof(int));
}

/**
 * @brief Callback for "echo" API: copies input data to output.
 * @param Trigger  Unused.
 * @param Input    TDataHnd containing the data to echo.
 * @param Output   TDataHnd where the copy is written.
 *
 * Uses malloc/free for demonstration; in production, consider using
 * std::vector or direct buffer manipulation to avoid heap fragmentation.
 */
static void __cdecl EchoCallback(void* /*Trigger*/, void* Input, void* Output)
{
    TDataHnd hIn = (TDataHnd)Input;
    TDataHnd hOut = (TDataHnd)Output;

    int64_t size = API_GetSize(hIn);
    if (size > 0) {
        char* buf = (char*)malloc((size_t)size);
        if (!buf) return;
        API_SetPos(hIn, 0);
        API_ReadBuffer(hIn, buf, size);
        API_WriteBuffer(hOut, buf, size);
        free(buf);
    }
}

/**
 * @brief Callback for "get_time" API: returns current time as string.
 * @param Trigger  Unused.
 * @param Input    TDataHnd (ignored).
 * @param Output   TDataHnd where the time string is written.
 *
 * Note: ctime() returns a static buffer; not thread-safe, but in this
 * context the callback is serialized, so it's acceptable.
 */
static void __cdecl GetTimeCallback(void* /*Trigger*/, void* /*Input*/, void* Output)
{
    TDataHnd hOut = (TDataHnd)Output;

    time_t now = time(nullptr);
    char* timeStr = ctime(&now);
    size_t len = strlen(timeStr);
    if (len > 0 && timeStr[len - 1] == '\n') timeStr[len - 1] = '\0';
    API_WriteBuffer(hOut, timeStr, strlen(timeStr) + 1);
}

// ---------------------------------------------------------------------------
// Console Thread
// ---------------------------------------------------------------------------

/**
 * @brief Thread function that reads user input from the console.
 *
 * It runs continuously until g_bExit is set to true.
 * Commands are pushed to the command queue with mutex protection,
 * and the main thread is notified via a condition variable.
 *
 * This thread does NOT call any API functions, ensuring that all
 * API calls remain on the main thread (as required by the library).
 */
static void ConsoleThread()
{
    string line;
    while (!g_bExit) {
        cout << "Service> ";
        getline(cin, line);

        if (line == "exit") {
            g_bExit = true;         // Signal main loop to exit
            break;
        }

        // Queue the command for the main thread
        {
            lock_guard<mutex> lock(g_cmdMutex);
            g_cmdQueue.push(line);
        }
        g_cv.notify_one();          // Wake up the main thread
    }
}

// ---------------------------------------------------------------------------
// Command Processing (runs on main thread)
// ---------------------------------------------------------------------------

/**
 * @brief Process a single command received from the console.
 *
 * This function is executed only on the main thread, so it is safe to
 * call any API functions (if needed). Currently, it only handles "status".
 *
 * @param cmd  The command string.
 * @param app  The application handle (not used here, but kept for extensibility).
 */
static void ProcessCommand(const string& cmd, TAppHnd /*app*/)
{
    if (cmd == "status") {
        cout << "[Service] Status: running." << endl;
    }
    else {
        cout << "[Service] Unknown command: " << cmd << endl;
    }
}

// ---------------------------------------------------------------------------
// Main Program
// ---------------------------------------------------------------------------

int main()
{
    cout << "=== API Hub Service ===" << endl;

    // 1. Load the dynamic library. Must be done before any other API call.
    if (!API_LoadLibrary()) {
        cerr << "Failed to load API Hub library." << endl;
        return 1;
    }

    // 2. Create an application context. This app will expose its APIs.
    TAppHnd app = API_Create_APPHnd("ServiceApp", "Public service");
    if (!app) {
        cerr << "Failed to create application." << endl;
        API_FreeLibrary();
        return 1;
    }

    // 3. Register three call APIs.
    //    The callbacks will be invoked by the library when remote calls arrive.
    API_Reg_Call(app, "add", "Add two ints", nullptr, AddCallback);
    API_Reg_Call(app, "echo", "Echo input", nullptr, EchoCallback);
    API_Reg_Call(app, "get_time", "Get current time", nullptr, GetTimeCallback);
    cout << "Registered APIs: add, echo, get_time" << endl;

    // 4. Prepare network connections. We use IPC for fast local communication.
    //    The service listens on "ipc:demo_service" and also connects as a client
    //    to itself, so that local calls are routed internally.
    API_Reset_Prepare();
    API_Prepare_Service("ipc:demo_service", "ipc:demo_service");
    API_Prepare_Client("ipc:demo_service", app);

    // 5. Start the framework. This call blocks until the network layer is ready.
    //    After this point, the library's main loop is running in the background,
    //    and callbacks may be invoked on this same thread (or worker threads).
    cout << "Starting service..." << endl;
    if (API_Prepare_Done() != 1) {
        cerr << "Prepare_Done failed." << endl;
        // Note: API_Get_Status() is no longer available; check console output for errors.
        API_Free_APPHnd(app);
        API_shutdown();
        API_FreeLibrary();
        return 1;
    }

    cout << "Service is running." << endl;
    cout << "Type 'exit' to stop the service." << endl;

    // 6. Start the console input thread.
    //    All API calls remain on the main thread; the console thread only
    //    queues commands, which are processed in the main loop below.
    thread consoleThread(ConsoleThread);

    // 7. Main event loop.
    //    - Process queued console commands.
    //    - Sleep briefly to avoid busy-waiting.
    //    This loop runs until g_bExit is set to true.
    while (!g_bExit) {
        // Check for console commands (protected by mutex)
        string cmd;
        {
            lock_guard<mutex> lock(g_cmdMutex);
            if (!g_cmdQueue.empty()) {
                cmd = g_cmdQueue.front();
                g_cmdQueue.pop();
            }
        }

        if (!cmd.empty()) {
            ProcessCommand(cmd, app);   // Process command on main thread
        }

        // Status messages are printed to console automatically.
        // No need to call API_Get_Status().

        // Sleep to reduce CPU usage. The condition variable could be used
        // to wake immediately on new commands, but a short sleep is fine.
        this_thread::sleep_for(chrono::milliseconds(100));
    }

    // 8. Wait for the console thread to finish.
    if (consoleThread.joinable())
        consoleThread.join();

    // 9. Graceful shutdown.
    //    - Signal the library's main thread to exit.
    //    - Free the application handle.
    //    - Shut down the entire framework.
    //    - Unload the library.
    cout << "Shutting down service..." << endl;
    API_Exit_MainThread();          // Tell the library to stop its internal loop
    API_Free_APPHnd(app);           // Release app resources
    API_shutdown();                 // Stop all services and clients
    API_FreeLibrary();              // Unload the DLL

    cout << "Service stopped." << endl;
    return 0;
}