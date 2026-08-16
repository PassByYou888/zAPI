// HelloWorld.cpp - Minimal demonstration of API Hub explicit-linking wrapper
//
// This program shows the absolute minimum needed to use the API Hub library:
// - Load the dynamic library
// - Create an application handle
// - Register one simple "add" API (returns sum of two integers)
// - Perform a local call to test it
// - Clean up and exit
//
// No network is involved; all calls are local within the same process.
// This is ideal for getting started without any networking setup.

#include <iostream>
#include <cstdint>
#include "API_HubTool.h"

using namespace std;

// ----------------------------------------------------------------------------
// Callback: adds two integers read from Input, writes sum to Output
// ----------------------------------------------------------------------------
static void __cdecl AddCallback(void* /*Trigger*/, void* Input, void* Output)
{
    TDataHnd hInput = (TDataHnd)Input;
    TDataHnd hOutput = (TDataHnd)Output;

    int a = 0, b = 0;
    if (API_ReadBuffer(hInput, &a, sizeof(int)) != sizeof(int)) return;
    if (API_ReadBuffer(hInput, &b, sizeof(int)) != sizeof(int)) return;

    int sum = a + b;
    API_WriteBuffer(hOutput, &sum, sizeof(int));
}

// ----------------------------------------------------------------------------
// Main
// ----------------------------------------------------------------------------
int main()
{
    cout << "=== API Hub Hello World ===" << endl;

    // 1. Load the library (must be done first)
    if (!API_LoadLibrary()) {
        cerr << "Failed to load API Hub library. Ensure api_hub.dll is in the path." << endl;
        return 1;
    }
    cout << "Library loaded." << endl;

    // 2. Create an application context
    TAppHnd app = API_Create_APPHnd("HelloApp", "Minimal demo");
    if (!app) {
        cerr << "Failed to create application." << endl;
        API_FreeLibrary();
        return 1;
    }
    cout << "Application created." << endl;

    // 3. Register a simple call API
    if (!API_Reg_Call(app, "add", "Add two integers", nullptr, AddCallback)) {
        cerr << "Failed to register 'add' API." << endl;
    } else {
        cout << "Registered 'add' API." << endl;
    }

    // 4. Perform a local call (no network needed)
    TDataHnd data = API_Create_DataHnd("add");
    int a = 5, b = 7;
    API_WriteBuffer(data, &a, sizeof(int));
    API_WriteBuffer(data, &b, sizeof(int));

    TDataHnd result = API_Local_APP_Call(app, data);
    API_Free_DataHnd(data);  // we must free the input handle

    if (result && API_GetSize(result) >= sizeof(int)) {
        int sum;
        API_SetPos(result, 0);
        API_ReadBuffer(result, &sum, sizeof(int));
        cout << "Local add(5,7) = " << sum << endl;
        API_Free_DataHnd(result);
    } else {
        cout << "Local call failed." << endl;
    }

    // 5. Clean up
    API_Free_APPHnd(app);
    API_shutdown();          // not strictly needed if we didn't start network, but safe
    API_FreeLibrary();

    cout << "Done." << endl;
    return 0;
}