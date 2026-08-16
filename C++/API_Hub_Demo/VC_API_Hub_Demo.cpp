// VC_API_Hub_Demo.cpp - Comprehensive demonstration of API Hub explicit-linking wrapper

#include <iostream>
#include <string>
#include <cstring>
#include <vector>
#include <cstdint>
#include <thread>
#include <chrono>
#include "API_HubTool.h"

using namespace std;

// ----------------------------------------------------------------------------
// Callback implementations (must be __cdecl)
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

static void __cdecl ReverseCallback(void* /*Trigger*/, void* Input, void* Output)
{
    TDataHnd hInput = (TDataHnd)Input;
    TDataHnd hOutput = (TDataHnd)Output;

    int64_t size = API_GetSize(hInput);
    if (size <= 0) return;

    vector<char> buffer((size_t)size);
    API_SetPos(hInput, 0);
    int64_t readBytes = API_ReadBuffer(hInput, buffer.data(), size);
    if (readBytes != size) return;

    buffer[size - 1] = '\0';
    size_t len = strlen(buffer.data());
    if (len > 0) {
        for (size_t i = 0; i < len / 2; ++i) {
            swap(buffer[i], buffer[len - 1 - i]);
        }
    }
    API_WriteBuffer(hOutput, buffer.data(), len + 1);
}

struct Point {
    int x;
    int y;
    char label[32];
};

static void __cdecl TransformPointCallback(void* /*Trigger*/, void* Input, void* Output)
{
    TDataHnd hInput = (TDataHnd)Input;
    TDataHnd hOutput = (TDataHnd)Output;

    Point pt;
    if (API_ReadBuffer(hInput, &pt, sizeof(Point)) != sizeof(Point)) return;

    int tmp = pt.x;
    pt.x = pt.y;
    pt.y = tmp;
    string newLabel = "Transformed " + string(pt.label);
    strncpy_s(pt.label, newLabel.c_str(), sizeof(pt.label) - 1);

    API_WriteBuffer(hOutput, &pt, sizeof(Point));
}

static void __cdecl EchoCallback(void* /*Trigger*/, void* Input, void* Output)
{
    TDataHnd hInput = (TDataHnd)Input;
    TDataHnd hOutput = (TDataHnd)Output;

    int64_t size = API_GetSize(hInput);
    if (size > 0) {
        vector<char> buf((size_t)size);
        API_SetPos(hInput, 0);
        API_ReadBuffer(hInput, buf.data(), size);
        API_WriteBuffer(hOutput, buf.data(), size);
    }
}

static void __cdecl PrintNotifyCallback(void* /*Trigger*/, void* Input)
{
    TDataHnd hInput = (TDataHnd)Input;
    char buffer[256] = { 0 };
    int64_t size = API_GetSize(hInput);
    if (size > 0 && size < sizeof(buffer)) {
        API_SetPos(hInput, 0);
        API_ReadBuffer(hInput, buffer, size);
        buffer[size] = '\0';
        cout << "[Notify] Received: " << buffer << endl;
    }
    else {
        cout << "[Notify] Received a notification (size=" << size << ")" << endl;
    }
}

// ----------------------------------------------------------------------------
// Helper functions
// ----------------------------------------------------------------------------

static void DemonstrateDataHandleOperations()
{
    cout << "\n=== Data Handle Operations Demo ===" << endl;

    TDataHnd h = API_Create_DataHnd("test_api");
    if (!h) {
        cerr << "Failed to create data handle" << endl;
        return;
    }

    int numbers[] = { 10, 20, 30 };
    API_WriteBuffer(h, numbers, sizeof(numbers));
    cout << "Wrote 3 integers. Size = " << API_GetSize(h) << ", Pos = " << API_GetPos(h) << endl;

    API_SetPos(h, 0);
    int readNums[3] = { 0 };
    API_ReadBuffer(h, readNums, sizeof(readNums));
    cout << "Read back: " << readNums[0] << ", " << readNums[1] << ", " << readNums[2] << endl;

    API_SetPos(h, API_GetSize(h));
    double pi = 3.14159;
    API_WriteBuffer(h, &pi, sizeof(pi));
    cout << "Appended double. New size = " << API_GetSize(h) << endl;

    API_SetSize(h, 12);
    cout << "Resized to 12 bytes. Size = " << API_GetSize(h) << endl;

    void* raw = API_GetBuffer(h);
    if (raw) {
        cout << "Raw buffer first byte: " << hex << (int)((unsigned char*)raw)[0] << dec << endl;
    }

    API_Free_DataHnd(h);
    cout << "Data handle freed." << endl;
}

// ----------------------------------------------------------------------------
// Main
// ----------------------------------------------------------------------------

int main()
{
    cout << "=== API Hub Comprehensive Demo ===" << endl;

    if (!API_LoadLibrary()) {
        cerr << "Failed to load api_hub library. Ensure api_hub.dll is in the path." << endl;
        return 1;
    }
    cout << "Library loaded successfully." << endl;

    DemonstrateDataHandleOperations();

    TAppHnd app = API_Create_APPHnd("DemoApp", "Comprehensive demo application");
    if (!app) {
        cerr << "Failed to create application handle." << endl;
        API_FreeLibrary();
        return 1;
    }
    cout << "Application handle created." << endl;

    cout << "\n=== Registering APIs ===" << endl;
    int regResult = 0;

    regResult = API_Reg_Call(app, "add", "Add two integers", nullptr, AddCallback);
    cout << "Register 'add': " << (regResult ? "Success" : "Failed") << endl;

    regResult = API_Reg_Call(app, "reverse", "Reverse a string", nullptr, ReverseCallback);
    cout << "Register 'reverse': " << (regResult ? "Success" : "Failed") << endl;

    regResult = API_Reg_Call(app, "transform", "Transform a Point structure", nullptr, TransformPointCallback);
    cout << "Register 'transform': " << (regResult ? "Success" : "Failed") << endl;

    regResult = API_Reg_Call(app, "echo", "Echo input data", nullptr, EchoCallback);
    cout << "Register 'echo': " << (regResult ? "Success" : "Failed") << endl;

    regResult = API_Reg_Notify(app, "print", "Print notification", nullptr, PrintNotifyCallback);
    cout << "Register 'print' (notify): " << (regResult ? "Success" : "Failed") << endl;

    // --- Network preparation (use TCP for better reliability) ---
    cout << "\n=== Preparing Network (TCP) ===" << endl;
    API_Reset_Prepare();
    API_Prepare_Service("127.0.0.1", "127.0.0.1:9898");
    API_Prepare_Client("127.0.0.1:9898", app);

    // --- Start framework ---
    cout << "\n=== Starting Framework ===" << endl;
    if (API_Prepare_Done() != 1) {
        cerr << "API_Prepare_Done failed. Check console output for errors." << endl;
        API_Free_APPHnd(app);
        API_shutdown();
        API_FreeLibrary();
        return 1;
    }
    cout << "Framework started successfully." << endl;

    // Wait for application registration to propagate (1.5 seconds)
    this_thread::sleep_for(chrono::milliseconds(1500));

    // --- Remote calls (with 10-second timeout) ---
    cout << "\n=== Remote API Calls ===" << endl;

    // add
    {
        TDataHnd data = API_Create_DataHnd("add");
        int a = 100, b = 200;
        API_WriteBuffer(data, &a, sizeof(int));
        API_WriteBuffer(data, &b, sizeof(int));

        TDataHnd result = API_Call("DemoApp", data, 10000);
        API_Free_DataHnd(data);

        if (result && API_GetSize(result) >= sizeof(int)) {
            int sum;
            API_SetPos(result, 0);
            API_ReadBuffer(result, &sum, sizeof(int));
            cout << "add(100,200) = " << sum << endl;
            API_Free_DataHnd(result);
        }
        else {
            cout << "add call failed or timed out." << endl;
        }
    }

    // reverse
    {
        TDataHnd data = API_Create_DataHnd("reverse");
        const char* msg = "Hello World!";
        API_WriteBuffer(data, msg, strlen(msg) + 1);

        TDataHnd result = API_Call("DemoApp", data, 10000);
        API_Free_DataHnd(data);

        if (result && API_GetSize(result) > 0) {
            int64_t sz = API_GetSize(result);
            vector<char> buf((size_t)sz + 1);
            API_SetPos(result, 0);
            API_ReadBuffer(result, buf.data(), sz);
            buf[sz] = '\0';
            cout << "reverse('Hello World!') = '" << buf.data() << "'" << endl;
            API_Free_DataHnd(result);
        }
        else {
            cout << "reverse call failed or timed out." << endl;
        }
    }

    // transform
    {
        TDataHnd data = API_Create_DataHnd("transform");
        Point pt = { 10, 20, "Original" };
        API_WriteBuffer(data, &pt, sizeof(Point));

        TDataHnd result = API_Call("DemoApp", data, 10000);
        API_Free_DataHnd(data);

        if (result && API_GetSize(result) >= sizeof(Point)) {
            Point transformed;
            API_SetPos(result, 0);
            API_ReadBuffer(result, &transformed, sizeof(Point));
            cout << "transform(10,20,'Original') -> ("
                << transformed.x << "," << transformed.y << ",'"
                << transformed.label << "')" << endl;
            API_Free_DataHnd(result);
        }
        else {
            cout << "transform call failed or timed out." << endl;
        }
    }

    // echo
    {
        TDataHnd data = API_Create_DataHnd("echo");
        int binaryData[] = { 1, 2, 3, 4, 5 };
        API_WriteBuffer(data, binaryData, sizeof(binaryData));

        TDataHnd result = API_Call("DemoApp", data, 10000);
        API_Free_DataHnd(data);

        if (result && API_GetSize(result) == sizeof(binaryData)) {
            int echoed[5] = { 0 };
            API_SetPos(result, 0);
            API_ReadBuffer(result, echoed, sizeof(echoed));
            cout << "echo([1,2,3,4,5]) -> [";
            for (int i = 0; i < 5; ++i) cout << (i ? "," : "") << echoed[i];
            cout << "]" << endl;
            API_Free_DataHnd(result);
        }
        else {
            cout << "echo call failed or size mismatch." << endl;
        }
    }

    // notify
    {
        TDataHnd data = API_Create_DataHnd("print");
        const char* note = "Hello from notification!";
        API_WriteBuffer(data, note, strlen(note) + 1);
        API_Notify("DemoApp", data);
        API_Free_DataHnd(data);
        cout << "Notification sent." << endl;
    }

    // --- Local calls ---
    cout << "\n=== Local API Calls ===" << endl;

    {
        TDataHnd data = API_Create_DataHnd("add");
        int a = 5, b = 7;
        API_WriteBuffer(data, &a, sizeof(int));
        API_WriteBuffer(data, &b, sizeof(int));

        TDataHnd result = API_Local_APP_Call(app, data);
        API_Free_DataHnd(data);
        if (result && API_GetSize(result) >= sizeof(int)) {
            int sum;
            API_SetPos(result, 0);
            API_ReadBuffer(result, &sum, sizeof(int));
            cout << "Local add(5,7) = " << sum << endl;
            API_Free_DataHnd(result);
        }
    }

    {
        TDataHnd data = API_Create_DataHnd("print");
        const char* localNote = "Local notification";
        API_WriteBuffer(data, localNote, strlen(localNote) + 1);
        API_Local_APP_Notify(app, data);
        API_Free_DataHnd(data);
        cout << "Local notification sent." << endl;
    }

    // --- Status log (no longer available; messages are printed to console) ---
    cout << "\n=== Status Log ===" << endl;
    cout << "Status messages are printed to console by the library." << endl;

    this_thread::sleep_for(chrono::milliseconds(500));

    // --- Shutdown ---
    cout << "\n=== Shutting Down ===" << endl;
    API_Exit_MainThread();
    API_Free_APPHnd(app);
    API_shutdown();
    API_FreeLibrary();

    cout << "Demo completed successfully." << endl;
    return 0;
}