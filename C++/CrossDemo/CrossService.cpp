// CrossService.cpp - Coordinator for IPC endpoint "ipc:cross"
// This process only creates the IPC service endpoint; it does not register any API.

#include "API_HubTool.hpp"
#include <iostream>

using namespace z_api_hub;

int main() {
    std::cout << "=== Cross Service (Coordinator) ===" << std::endl;

    // ----------------------------------------------------------------
    // 1. LOAD THE DYNAMIC LIBRARY (RAII)
    //    The LibraryLoader constructor calls API_LoadLibrary().
    //    On destruction, it calls API_FreeLibrary().
    //    This MUST be the first RAII object in scope.
    // ----------------------------------------------------------------
    LibraryLoader loader;

    // 2. Reset any previous preparation
    API_Reset_Prepare();

    // 3. Create the IPC service endpoint
    int ret = API_Prepare_Service("ipc:cross", "ipc:cross");
    if (ret == 0) {
        std::cerr << "API_Prepare_Service failed." << std::endl;
        return 1;
    }

    // 4. Start the framework (blocks until ready)
    if (API_Prepare_Done() != 1) {
        std::cerr << "API_Prepare_Done failed. Check console output." << std::endl;
        API_shutdown();
        return 1;
    }

    std::cout << "IPC service 'ipc:cross' is running. Press Enter to exit..." << std::endl;
    std::cin.get();

    // 5. Clean shutdown
    API_Exit_MainThread();
    API_shutdown();
    return 0;
}