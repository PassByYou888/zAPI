// CrossNode.cpp - Worker node that registers 'add' and 'inv_seri' APIs.
// It connects to the IPC endpoint "ipc:cross" and exposes its services.

#include "API_HubTool.hpp"
#include <iostream>
#include <cstdint>

using namespace z_api_hub;

// ---------- Callback for 'add' ----------
static void __cdecl AddCallback(void* /*trigger*/, void* input, void* output) {
    // Borrow the handles (do not free them)
    DataHandle in(static_cast<TDataHnd>(input), false);
    DataHandle out(static_cast<TDataHnd>(output), false);

    int32_t a, b;
    if (!in.readInt32(&a) || !in.readInt32(&b)) {
        std::cerr << "[Node] add: failed to read parameters." << std::endl;
        return;
    }
    int32_t c = a + b;
    std::cout << "[Node] add(" << a << ", " << b << ") = " << c << std::endl;
    out.writeInt32(c);
}

// ---------- Callback for 'inv_seri' ----------
// Reads a fixed sequence of types and writes them back in reverse order.
static void __cdecl InvSeriCallback(void* /*trigger*/, void* input, void* output) {
    DataHandle in(static_cast<TDataHnd>(input), false);
    DataHandle out(static_cast<TDataHnd>(output), false);

    uint8_t  b;
    uint16_t w;
    uint32_t c;
    uint64_t u64;
    std::string s;
    float    f;

    if (!in.readUInt8(&b) ||
        !in.readUInt16(&w) ||
        !in.readUInt32(&c) ||
        !in.readUInt64(&u64) ||
        !in.readString(&s) ||
        !in.readSingle(&f)) {
        std::cerr << "[Node] inv_seri: failed to read data." << std::endl;
        return;
    }

    std::cout << "[Node] inv_seri received: ["
        << (int)b << ", " << w << ", " << c
        << ", " << u64 << ", \"" << s << "\", " << f << "]" << std::endl;

    // Write back in reverse order
    out.writeSingle(f);
    out.writeString(s);
    out.writeUInt64(u64);
    out.writeUInt32(c);
    out.writeUInt16(w);
    out.writeUInt8(b);

    std::cout << "[Node] inv_seri replied: ["
        << f << ", \"" << s << "\", "
        << u64 << ", " << c << ", " << w << ", " << (int)b << "]" << std::endl;
}

int main() {
    std::cout << "=== Cross Node (Worker) ===" << std::endl;

    // RAII library loader (loads/unloads automatically)
    LibraryLoader loader;

    // Create the application instance
    App app("demo", "C++ worker node");

    // Register the two callbacks (the raw C functions are used)
    if (!API_Reg_Call(app.get(), "add", "add(int,int)", nullptr, AddCallback) ||
        !API_Reg_Call(app.get(), "inv_seri", "inv_seri()", nullptr, InvSeriCallback)) {
        std::cerr << "Failed to register APIs." << std::endl;
        return 1;
    }

    // Deployment mode: do not wait for all clients to be connected
    setOption("Wait_Ready", "False");

    // Connect to the IPC endpoint and expose our application
    resetPrepare();
    int prep = API_Prepare_Client("ipc:cross", app.get());
    if (prep == 0) {
        std::cerr << "API_Prepare_Client failed." << std::endl;
        return 1;
    }

    // Start the framework
    if (API_Prepare_Done() != 1) {
        std::cerr << "API_Prepare_Done failed. Check console output." << std::endl;
        API_shutdown();
        return 1;
    }

    std::cout << "Node registered. Press Enter to exit..." << std::endl;
    std::cin.get();

    // RAII will automatically clean up app and library loader.
    API_Exit_MainThread();
    API_shutdown();
    return 0;
}