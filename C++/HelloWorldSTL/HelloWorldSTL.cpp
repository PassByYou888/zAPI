#include "API_HubTool.hpp"
#include <iostream>

// ============================================================================
// RAII (Resource Acquisition Is Initialization) explained:
// 
// RAII is a C++ programming technique where resource acquisition (e.g.,
// allocating memory, opening a file, loading a library, creating a handle)
// is performed in a constructor, and resource release (freeing, closing)
// is performed in the destructor. This ensures that resources are properly
// released when the object goes out of scope, even if an exception is thrown.
// 
// In this example, the following RAII classes are used:
//   - z_api_hub::LibraryLoader : loads the dynamic library on construction,
//     unloads it on destruction.
//   - z_api_hub::DataHandle    : creates and manages TDataHnd; frees it
//     automatically when destroyed.
//   - z_api_hub::App           : creates and manages TAppHnd; frees it
//     automatically when destroyed.
//
// You never need to manually call API_Free_DataHnd or API_Free_APPHnd.
// ============================================================================

// Callback for the "add" API ¨C must be __cdecl.
// This function is invoked by the library when a call arrives (locally or remotely).
static void __cdecl AddCallback(void* /*trigger*/, void* input, void* output) {
    // Borrow the input and output handles without taking ownership.
    // The second parameter 'false' means we do not own them, so they won't be freed.
    z_api_hub::DataHandle in(static_cast<TDataHnd>(input), false);
    z_api_hub::DataHandle out(static_cast<TDataHnd>(output), false);

    int a = 0, b = 0;
    // Read two integers sequentially. The read() method reads from the current position.
    // Since the localCall/API_Call resets the position to 0 before calling the callback,
    // we can read directly without seeking.
    if (in.read(a) != sizeof(a)) {
        std::cerr << "read a failed\n";
        return;
    }
    if (in.read(b) != sizeof(b)) {
        std::cerr << "read b failed\n";
        return;
    }

    int sum = a + b;
    out.write(sum);  // Write the result (appends at current position, but it's initially at 0).

    std::cout << "[Server] AddCallback: " << a << " + " << b << " = " << sum << '\n';
}

int main() {
    std::cout << "=== RAII Network Test (Self-Call via IPC) ===" << std::endl;

    try {
        // --------------------------------------------------------------------
        // 1. Load the dynamic library using RAII.
        //    The constructor calls API_LoadLibrary(). If it fails, an exception is thrown.
        //    When 'loader' goes out of scope (at the end of main or during stack unwinding),
        //    its destructor will call API_FreeLibrary() automatically.
        // --------------------------------------------------------------------
        z_api_hub::LibraryLoader loader;
        std::cout << "Library loaded.\n";

        // --------------------------------------------------------------------
        // 2. Reset the internal preparation state.
        //    This ensures a clean state before we set up services/clients.
        // --------------------------------------------------------------------
        z_api_hub::resetPrepare();
        std::cout << "ResetPrepare called.\n";

        // --------------------------------------------------------------------
        // 3. Create an application context (RAII).
        //    Constructor: API_Create_APPHnd("HelloApp", "Demo").
        //    Destructor:  API_Free_APPHnd().
        // --------------------------------------------------------------------
        z_api_hub::App app("HelloApp", "Demo");
        std::cout << "App created: " << app.name() << '\n';

        // Register our "add" API using the raw C function.
        // The callback is AddCallback, which is a static __cdecl function.
        if (!API_Reg_Call(app.get(), "add", "Add two ints", nullptr, AddCallback)) {
            std::cerr << "Register failed\n";
            return 1;
        }
        std::cout << "Registered 'add'.\n";

        // --------------------------------------------------------------------
        // 4. Prepare the network layer.
        //    We are both a service (listening on IPC) and a client (connecting to ourselves).
        //    This allows us to call our own API via the network stack, simulating
        //    a distributed environment.
        // --------------------------------------------------------------------
        API_Prepare_Service("ipc:hello_service", "ipc:hello_service");  // Listen on IPC.
        API_Prepare_Client("ipc:hello_service", app.get());            // Connect to the same IPC service,
        // exposing our app so it can be found.
        std::cout << "Network prepared (IPC).\n";

        // --------------------------------------------------------------------
        // 5. Start the framework.
        //    API_Prepare_Done() blocks until the network is fully initialized.
        //    It returns 1 on success, 0 on failure.
        // --------------------------------------------------------------------
        if (API_Prepare_Done() != 1) {
            std::cerr << "Prepare_Done failed.\n";
            return 1;
        }
        std::cout << "Network started.\n";

        // --------------------------------------------------------------------
        // 6. Build the request parameters.
        //    Create a DataHandle for the "add" API and write two integers.
        //    The DataHandle is RAII; it will be freed automatically when it goes
        //    out of scope (at the end of the try block).
        // --------------------------------------------------------------------
        z_api_hub::DataHandle param("add");
        param.write(5);   // Append int 5
        param.write(7);   // Append int 7 (position now at 8)
        std::cout << "Written parameters (5, 7).\n";

        // --------------------------------------------------------------------
        // 7. Perform a remote call via the network.
        //    API_Call() synchronously calls the "add" API registered under application "HelloApp".
        //    It clones the input handle internally, so we must still free 'param'
        //    (which the RAII destructor will do).
        //    The timeout is 5000 ms (5 seconds).
        //    It returns a raw TDataHnd (or NULL on severe error).
        // --------------------------------------------------------------------
        TDataHnd rawResult = API_Call("HelloApp", param.get(), 5000);

        // param goes out of scope at the end of the try block, but we need to
        // check the result before that.

        if (!rawResult || API_GetSize(rawResult) == 0) {
            std::cerr << "Remote call failed or timeout.\n";
            // If rawResult is non-NULL but size 0, we still need to free it,
            // but we'll just return and let the RAII destructors handle cleanup.
            // However, we must not leak the handle. We can wrap it in a DataHandle
            // to ensure it's freed, but we are about to exit. For safety, we can
            // explicitly free it here or use a local RAII wrapper.
            if (rawResult) API_Free_DataHnd(rawResult);
            return 1;
        }

        // --------------------------------------------------------------------
        // 8. Take ownership of the result handle and read the result.
        //    We wrap the raw handle in a DataHandle with ownership (true) so that
        //    it will be automatically freed when 'result' goes out of scope.
        // --------------------------------------------------------------------
        z_api_hub::DataHandle result(rawResult, true);  // Now we own it.
        int sum = 0;
        result.read(sum);  // Read the integer written by the callback.
        std::cout << "5 + 7 = " << sum << '\n';

        // --------------------------------------------------------------------
        // 9. Gracefully shut down the network.
        //    API_Exit_MainThread() signals the internal main thread to exit.
        //    API_shutdown() stops all services/clients and releases internal resources.
        // --------------------------------------------------------------------
        API_Exit_MainThread();
        API_shutdown();
        std::cout << "Network shutdown.\n";

    }
    catch (const std::exception& e) {
        // If any RAII constructor or other operation throws, catch it here.
        std::cerr << "Exception: " << e.what() << '\n';
        return 1;
    }

    // All RAII objects (loader, app, param, result) are destroyed here,
    // automatically freeing all resources.

    std::cout << "Done.\n";
    return 0;
}