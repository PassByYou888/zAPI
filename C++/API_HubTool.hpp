/* @file API_HubTool.hpp
 * @brief Modern C++ RAII wrapper for the API Hub dynamic library.
 *
 * This header provides a lightweight, header‑only, RAII‑based interface
 * to the C API defined in API_HubTool.h. It manages resource lifetime
 * automatically, reducing boilerplate and the risk of memory leaks.
 *
 * All symbols are placed in the namespace z_api_hub to avoid conflicts.
 *
 * -------------------------------------------------------------------------
 * STRING ENCODING – UTF‑8 IS MANDATORY
 * -------------------------------------------------------------------------
 * All string parameters (API names, descriptions, addresses, etc.) passed
 * to the underlying C functions must be UTF‑8 encoded and null‑terminated.
 * When using `std::string`, ensure it contains valid UTF‑8 bytes.
 * The wrapper does not perform encoding conversion; it passes the bytes
 * directly to the library.
 *
 * -------------------------------------------------------------------------
 * QUICK START – TYPICAL USAGE PATTERN
 * -------------------------------------------------------------------------
 *
 * 1. Include this header.
 * 2. Create a z_api_hub::LibraryLoader object (loads/unloads the library).
 * 3. Call z_api_hub::resetPrepare() to ensure a clean internal state.
 * 4. Create a z_api_hub::App with a unique name.
 * 5. Register your callbacks using the raw C function API_Reg_Call().
 * 6. Prepare request data using z_api_hub::DataHandle (write appends).
 * 7. Call App::localCall() for in‑process invocation.
 * 8. Read the result from the returned DataHandle.
 * 9. All resources are automatically freed on destruction.
 *
 * -------------------------------------------------------------------------
 * CRITICAL NOTES (Read before using)
 * -------------------------------------------------------------------------
 * - **Thread Safety**: All wrapper functions are fully thread‑safe.
 *   They can be called concurrently from any thread.
 *
 * - **Callback Context** (⚠️ CRITICAL): The callbacks you register
 *   (TAPI_Call, TAPI_Notify) are **executed in background thread‑pool
 *   threads**. Therefore:
 *     * **DO NOT** block inside callbacks.
 *     * **DO NOT** call API_Call() or API_Notify() from a callback – this
 *       may cause deadlocks. If you need to make a remote call, use a
 *       separate worker thread (e.g., std::async, thread pool) and return
 *       quickly.
 *     * **DO NOT** access UI components without proper synchronization.
 *     * Offload heavy processing to a separate thread.
 *
 * - **Execution Order**: The order of concurrent calls is **not** guaranteed
 *   (see the header for details).
 *
 * - **DataHandle::write()** appends data at the current position. To
 *   overwrite, call seek(0) before writing.
 *
 * - **Handle lifetimes**: DataHandle and App automatically free their
 *   resources on destruction. However, when borrowing a handle in a callback,
 *   do not free it.
 *
 * -------------------------------------------------------------------------
 * COMPLETE EXAMPLE – ADDITION SERVICE
 * -------------------------------------------------------------------------
 * @code
 * #include "API_HubTool.hpp"
 * #include <iostream>
 *
 * static void __cdecl AddCallback(void* trigger, void* input, void* output) {
 *     z_api_hub::DataHandle in(static_cast<TDataHnd>(input), false);  // borrow
 *     z_api_hub::DataHandle out(static_cast<TDataHnd>(output), false);
 *
 *     int a = 0, b = 0;
 *     if (in.read(a) != sizeof(a) || in.read(b) != sizeof(b)) {
 *         std::cerr << "AddCallback: read failed\n";
 *         return;
 *     }
 *     int sum = a + b;
 *     out.write(sum);
 * }
 *
 * int main() {
 *     try {
 *         z_api_hub::LibraryLoader loader;   // loads z_api_hub64.dll
 *         z_api_hub::resetPrepare();         // reset internal state
 *
 *         z_api_hub::App app("HelloApp", "Demo");
 *         if (!API_Reg_Call(app.get(), "add", "Add two ints", nullptr, AddCallback))
 *             throw std::runtime_error("Register failed");
 *
 *         z_api_hub::DataHandle param("add");
 *         param.write(5);   // appends 5
 *         param.write(7);   // appends 7 (position now at 8)
 *
 *         auto result = app.localCall(param);
 *         int sum = 0;
 *         result.read(sum); // reads from position 0
 *         std::cout << "5 + 7 = " << sum << '\n';
 *     }
 *     catch (const std::exception& e) {
 *         std::cerr << "Error: " << e.what() << '\n';
 *         return 1;
 *     }
 *     return 0;
 * }
 * @endcode
 *
 * -------------------------------------------------------------------------
 * DEPENDENCIES
 * -------------------------------------------------------------------------
 * - API_HubTool.h and API_HubTool.c (the C wrapper)
 * - Dynamic library : z_api_hub64.dll (Windows), libz_api_hub.so (Linux), etc.
 * - Link with -ldl on Linux/macOS (not needed on Windows).
 */

#pragma once

#include "API_HubTool.h"
#include <string>
#include <stdexcept>
#include <utility>   // for std::move

    namespace z_api_hub {

    // ----------------------------------------------------------------------------
    //  ApiError – exception thrown on any API failure
    // ----------------------------------------------------------------------------
    /**
     * @brief Exception class for API Hub operations.
     *
     * All constructors and methods in this wrapper throw ApiError when the
     * underlying C function returns an error or a null handle.
     */
    class ApiError : public std::runtime_error {
    public:
        explicit ApiError(const std::string& msg) : std::runtime_error(msg) {}
    };

    // ----------------------------------------------------------------------------
    //  LibraryLoader – RAII for loading/unloading the dynamic library
    // ----------------------------------------------------------------------------
    /**
     * @brief Automatically loads the library on construction and unloads on destruction.
     *
     * Usage:
     * @code
     * z_api_hub::LibraryLoader loader;  // loads z_api_hub64.dll
     * // ... use library ...
     * // destructor calls API_FreeLibrary()
     * @endcode
     *
     * @note Must be the first RAII object created; its lifetime should cover
     *       all other API_HubTool usage.
     */
    class LibraryLoader {
    public:
        LibraryLoader() {
            if (!API_LoadLibrary())
                throw ApiError("API_LoadLibrary failed");
        }
        ~LibraryLoader() { API_FreeLibrary(); }

        // non-copyable, movable (default)
        LibraryLoader(const LibraryLoader&) = delete;
        LibraryLoader& operator=(const LibraryLoader&) = delete;
        LibraryLoader(LibraryLoader&&) = default;
        LibraryLoader& operator=(LibraryLoader&&) = default;
    };

    // ----------------------------------------------------------------------------
    //  DataHandle – RAII wrapper for TDataHnd
    // ----------------------------------------------------------------------------
    /**
     * @brief Manages the lifetime of a TDataHnd and provides easy read/write access.
     *
     * A DataHandle encapsulates a binary buffer that holds an API name and payload.
     * It supports:
     *   - Creation via API name (calls API_Create_DataHnd). The API name must be
     *     UTF‑8 encoded (passed as std::string).
     *   - Wrapping an existing handle (with or without ownership).
     *   - Move semantics (copy is disabled).
     *   - write() / read() for trivially copyable types (appends/reads from current position).
     *   - seek(), pos(), size(), buffer() for low‑level control.
     *
     * @note write() appends data at the current position. To overwrite from the start,
     *       call seek(0) before writing.
     * @note The input handle passed to callbacks is borrowed; use DataHandle(h, false)
     *       to avoid freeing it.
     *
     * @code
     * DataHandle param("add");
     * param.write(5);
     * param.write(7);
     * // now size = 8, position = 8
     * @endcode
     */
    class DataHandle {
    public:
        /**
         * @brief Creates a new data handle for the given API name.
         * @param apiName The API name (UTF‑8, used for routing when calling).
         * @throws ApiError if API_Create_DataHnd returns NULL.
         */
        explicit DataHandle(const std::string& apiName)
            : h_(API_Create_DataHnd(apiName.c_str())), owned_(true) {
            if (!h_) throw ApiError("DataHandle: API_Create_DataHnd failed");
        }

        /**
         * @brief Wraps an existing TDataHnd, optionally taking ownership.
         * @param h            The existing handle.
         * @param takeOwnership If true, the handle will be freed on destruction.
         *                       Use false for borrowed handles (e.g., in callbacks).
         */
        explicit DataHandle(TDataHnd h, bool takeOwnership) noexcept
            : h_(h), owned_(takeOwnership) {
        }

        // Move semantics (copy disabled)
        DataHandle(DataHandle&& other) noexcept
            : h_(other.h_), owned_(other.owned_) {
            other.h_ = nullptr;
            other.owned_ = false;
        }

        DataHandle& operator=(DataHandle&& other) noexcept {
            if (this != &other) {
                reset();
                h_ = other.h_;
                owned_ = other.owned_;
                other.h_ = nullptr;
                other.owned_ = false;
            }
            return *this;
        }

        DataHandle(const DataHandle&) = delete;
        DataHandle& operator=(const DataHandle&) = delete;

        /// Destructor – calls reset() to free the handle if owned.
        ~DataHandle() { reset(); }

        /**
         * @brief Releases ownership of the handle without freeing it.
         * @return The raw TDataHnd. The caller is responsible for freeing it.
         */
        TDataHnd release() noexcept {
            owned_ = false;
            TDataHnd tmp = h_;
            h_ = nullptr;
            return tmp;
        }

        /// Returns the raw handle.
        TDataHnd get() const noexcept { return h_; }

        /// Returns true if the internal handle is not null.
        explicit operator bool() const noexcept { return h_ != nullptr; }

        /**
         * @brief Frees the handle if owned, and sets it to null.
         */
        void reset() {
            if (owned_ && h_) {
                API_Free_DataHnd(h_);
            }
            h_ = nullptr;
            owned_ = false;
        }

        // ---------- I/O operations (position-sensitive) ----------

        /**
         * @brief Appends len bytes from data at the current position.
         * @param data Pointer to the source data.
         * @param len  Number of bytes to write.
         * @return The number of bytes actually written (should equal len).
         * @throws ApiError if handle is null or write fails.
         *
         * @note This advances the internal position by len.
         */
        size_t write(const void* data, size_t len) {
            if (!h_) throw ApiError("DataHandle: write on null");
            int64_t written = API_WriteBuffer(h_, data, static_cast<int64_t>(len));
            if (written < 0) throw ApiError("DataHandle: write failed");
            return static_cast<size_t>(written);
        }

        /**
         * @brief Writes a trivially copyable value (overload).
         * @tparam T A trivially copyable type.
         * @param value The value to append.
         * @return Number of bytes written (sizeof(T)).
         */
        template<typename T>
        size_t write(const T& value) {
            static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");
            return write(&value, sizeof(T));
        }

        /**
         * @brief Reads up to len bytes from the current position into data.
         * @param data Destination buffer.
         * @param len  Maximum bytes to read.
         * @return The actual number of bytes read (may be less if end of buffer).
         * @throws ApiError if handle is null or read fails.
         *
         * @note This advances the internal position by the number of bytes read.
         */
        size_t read(void* data, size_t len) {
            if (!h_) throw ApiError("DataHandle: read on null");
            int64_t readBytes = API_ReadBuffer(h_, data, static_cast<int64_t>(len));
            if (readBytes < 0) throw ApiError("DataHandle: read failed");
            return static_cast<size_t>(readBytes);
        }

        /**
         * @brief Reads a trivially copyable value (overload).
         * @tparam T A trivially copyable type.
         * @param value Output parameter to store the read value.
         * @return Number of bytes read (should be sizeof(T)).
         */
        template<typename T>
        size_t read(T& value) {
            static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");
            return read(&value, sizeof(T));
        }

        // ---------- Position and size management ----------

        /// Sets the internal read/write position.
        void seek(int64_t pos) { if (h_) API_SetPos(h_, pos); }

        /// Returns the current position.
        int64_t pos() const { return h_ ? API_GetPos(h_) : 0; }

        /// Returns the total size of the buffer.
        int64_t size() const { return h_ ? API_GetSize(h_) : 0; }

        /// Returns a pointer to the raw buffer (read‑only, do not free).
        const void* buffer() const { return h_ ? API_GetBuffer(h_) : nullptr; }

    private:
        TDataHnd h_ = nullptr;
        bool owned_ = true;
    };

    // ----------------------------------------------------------------------------
    //  App – RAII wrapper for TAppHnd
    // ----------------------------------------------------------------------------
    /**
     * @brief Manages an application context (TAppHnd) and provides local call capability.
     *
     * An App represents a logical service that can register APIs. The handle is
     * automatically freed on destruction.
     *
     * @note The registration of callbacks is still done via the raw C function
     *       API_Reg_Call() because it requires a __cdecl function pointer. This
     *       wrapper does not hide that to keep the interface clean and flexible.
     *
     * @code
     * App app("MyService", "My service description");
     * // register callbacks using API_Reg_Call(app.get(), ...)
     * @endcode
     */
    class App {
    public:
        /**
         * @brief Creates an application with the given name and optional description.
         * @param name Unique application name (case‑sensitive, UTF‑8).
         * @param desc Optional description (UTF‑8, can be empty).
         * @throws ApiError if API_Create_APPHnd returns NULL.
         */
        explicit App(const std::string& name, const std::string& desc = "")
            : h_(API_Create_APPHnd(name.c_str(), desc.c_str())), appName_(name) {
            if (!h_) throw ApiError("App: API_Create_APPHnd failed");
        }

        /// Destructor – frees the application handle.
        ~App() { if (h_) API_Free_APPHnd(h_); }

        // Move semantics (copy disabled)
        App(App&& other) noexcept
            : h_(other.h_), appName_(std::move(other.appName_)) {
            other.h_ = nullptr;
        }

        App& operator=(App&& other) noexcept {
            if (this != &other) {
                if (h_) API_Free_APPHnd(h_);
                h_ = other.h_;
                other.h_ = nullptr;
                appName_ = std::move(other.appName_);
            }
            return *this;
        }

        App(const App&) = delete;
        App& operator=(const App&) = delete;

        /// Returns the raw TAppHnd.
        TAppHnd get() const noexcept { return h_; }

        /// Returns the application name.
        const std::string& name() const noexcept { return appName_; }

        /**
         * @brief Unregisters a previously registered API from this application.
         *
         * The API is immediately removed from the local registry and a network
         * broadcast is triggered. Remote peers will stop seeing this API within
         * approximately 3 seconds (depending on network latency and the C4
         * update interval). During that short window, remote calls may still
         * be attempted; they will fail gracefully (the remote side will receive
         * a "not found" error).
         *
         * @param apiName The name of the API to unregister (UTF‑8).
         * @return True if the API was found and unregistered, False otherwise.
         *
         * @see RegisterCall, RegisterNotify
         *
         * @code
         * if (app.unregister("add")) {
         *     std::cout << "API 'add' unregistered, broadcast in progress.\n";
         * }
         * @endcode
         */
        bool unregister(const std::string& apiName) {
            if (!h_) throw ApiError("App::unregister: app null");
            return API_UnReg(h_, apiName.c_str()) == 1;
        }

        /**
         * @brief Performs a local (in‑process) call to an API registered in this app.
         * @param param The input DataHandle (contains API name and parameters).
         * @return A new DataHandle containing the result (owned by caller).
         * @throws ApiError if app is null or the call fails.
         *
         * @note This bypasses the network and invokes the callback directly.
         *       It resets the position of the input handle internally.
         */
        DataHandle localCall(const DataHandle& param) const {
            if (!h_) throw ApiError("App::localCall: app null");
            TDataHnd result = API_Local_APP_Call(h_, param.get());
            if (!result) throw ApiError("App::localCall failed");
            return DataHandle(result, true);
        }

    private:
        TAppHnd h_ = nullptr;
        std::string appName_;
    };

    // ----------------------------------------------------------------------------
    //  Free functions – wrappers for global C functions
    // ----------------------------------------------------------------------------

    /**
     * @brief Resets the internal preparation state.
     * @see API_Reset_Prepare
     *
     * Call this before preparing services/clients, or to ensure a clean state
     * before registering callbacks.
     */
    inline void resetPrepare() { API_Reset_Prepare(); }

    /**
     * @brief Dynamically adjusts global runtime options.
     * @see API_SetOption for the list of supported options.
     *
     * This is a direct wrapper around the C function.
     *
     * @param option Configuration key (UTF‑8, case‑insensitive).
     * @param value  New value (UTF‑8).
     *
     * @code
     * z_api_hub::setOption("password", "my_secret");
     * z_api_hub::setOption("Wait_Connection_ReadyOk", "False");
     * @endcode
     */
    inline void setOption(const std::string& option, const std::string& value) {
        API_SetOption(option.c_str(), value.c_str());
    }

} // namespace z_api_hub