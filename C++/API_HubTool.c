/**
 * @file API_HubTool.c
 * @brief Implementation of the explicit‑linking wrapper for the API Hub library.
 *
 * This file resolves all API functions from the dynamic library at runtime.
 * It uses platform‑specific dynamic loading:
 *   - Windows: LoadLibraryA / GetProcAddress / FreeLibrary
 *   - Linux/macOS: dlopen / dlsym / dlclose
 *
 * The library is loaded from the executable's directory first, then falls back
 * to the system search path. All wrapper functions perform safety checks to
 * prevent crashes when the library is not loaded.
 *
 * Compile with a C compiler (e.g., gcc, cl, clang) and link with appropriate libs:
 *   - Windows: no extra libs (kernel32 is implicit)
 *   - Linux/macOS: link with -ldl
 *
 * @note This file must be compiled with the same calling convention as the
 *       library (__cdecl on Windows, default on others).
 *
 * @see API_HubTool.h for the public interface and usage documentation.
 */

#define _CRT_SECURE_NO_WARNINGS
#include "API_HubTool.h"

#include <stdio.h>     // fprintf, stderr
#include <string.h>    // strrchr, snprintf

 /* ============================================================================
    Platform‑specific includes and definitions
    ============================================================================ */

#ifdef _WIN32
#  include <windows.h>
#  define LIB_HANDLE HMODULE
#  define LOAD_LIBRARY(path) LoadLibraryA(path)
#  define GET_PROC_ADDRESS(handle, name) GetProcAddress(handle, name)
#  define FREE_LIBRARY(handle) FreeLibrary(handle)
#  define GET_EXE_PATH(buf, size) GetModuleFileNameA(GetModuleHandleA(NULL), buf, size)
#  define LIB_EXT "dll"
#  define PATH_SEPARATOR '\\'
#  ifndef PATH_MAX
#    define PATH_MAX 260   /* Windows maximum path length */
#  endif
#else
#  include <dlfcn.h>
#  include <unistd.h>
#  include <limits.h>     /* PATH_MAX is usually defined here */
#  define LIB_HANDLE void*
#  define LOAD_LIBRARY(path) dlopen(path, RTLD_LAZY)
#  define GET_PROC_ADDRESS(handle, name) dlsym(handle, name)
#  define FREE_LIBRARY(handle) dlclose(handle)
#  define GET_EXE_PATH(buf, size) readlink("/proc/self/exe", buf, size - 1)
#  define LIB_EXT "so"
#  define PATH_SEPARATOR '/'
#  ifndef PATH_MAX
#    define PATH_MAX 4096  /* Common Linux path max */
#  endif
#endif

    /* ============================================================================
       Global state
       ============================================================================ */

       /**
        * @brief Handle to the loaded dynamic library (opaque).
        *
        * This is the platform‑specific handle (HMODULE on Windows, void* on POSIX).
        * It is set by API_LoadLibrary() and cleared by API_FreeLibrary().
        */
static LIB_HANDLE g_hDll = NULL;

/**
 * @brief Flag indicating whether the library has been successfully loaded.
 *
 * This is set to 1 after all function pointers are resolved, and cleared to 0
 * when the library is unloaded. All wrapper functions check this flag.
 */
static int g_loaded = 0;

/* ============================================================================
   Function pointer type declarations for each API function.
   These match the signatures in api_hub.dll / .so / .dylib.
   ============================================================================ */

   /** @typedef fnAPI_Create_DataHnd */
typedef TDataHnd(__cdecl* fnAPI_Create_DataHnd)(const char*);
/** @typedef fnAPI_Free_DataHnd */
typedef void(__cdecl* fnAPI_Free_DataHnd)(TDataHnd);
/** @typedef fnAPI_GetBuffer */
typedef void* (__cdecl* fnAPI_GetBuffer)(TDataHnd);
/** @typedef fnAPI_WriteBuffer */
typedef int64_t(__cdecl* fnAPI_WriteBuffer)(TDataHnd, const void*, int64_t);
/** @typedef fnAPI_ReadBuffer */
typedef int64_t(__cdecl* fnAPI_ReadBuffer)(TDataHnd, void*, int64_t);
/** @typedef fnAPI_GetPos */
typedef int64_t(__cdecl* fnAPI_GetPos)(TDataHnd);
/** @typedef fnAPI_SetPos */
typedef void(__cdecl* fnAPI_SetPos)(TDataHnd, int64_t);
/** @typedef fnAPI_GetSize */
typedef int64_t(__cdecl* fnAPI_GetSize)(TDataHnd);
/** @typedef fnAPI_SetSize */
typedef void(__cdecl* fnAPI_SetSize)(TDataHnd, int64_t);

/** @typedef fnAPI_Create_APPHnd */
typedef TAppHnd(__cdecl* fnAPI_Create_APPHnd)(const char*, const char*);
/** @typedef fnAPI_Free_APPHnd */
typedef void(__cdecl* fnAPI_Free_APPHnd)(TAppHnd);
/** @typedef fnAPI_Reg_Call */
typedef int(__cdecl* fnAPI_Reg_Call)(TAppHnd, const char*, const char*, void*, TAPI_Call);
/** @typedef fnAPI_Reg_Notify */
typedef int(__cdecl* fnAPI_Reg_Notify)(TAppHnd, const char*, const char*, void*, TAPI_Notify);
/** @typedef fnAPI_UnReg */
typedef int(__cdecl* fnAPI_UnReg)(TAppHnd, const char*);
/** @typedef fnAPI_Local_APP_Call */
typedef TDataHnd(__cdecl* fnAPI_Local_APP_Call)(TAppHnd, TDataHnd);
/** @typedef fnAPI_Local_APP_Notify */
typedef void(__cdecl* fnAPI_Local_APP_Notify)(TAppHnd, TDataHnd);

/** @typedef fnAPI_Prepare_Service */
typedef int(__cdecl* fnAPI_Prepare_Service)(const char*, const char*);
/** @typedef fnAPI_Prepare_Client */
typedef int(__cdecl* fnAPI_Prepare_Client)(const char*, TAppHnd);
/** @typedef fnAPI_Reset_Prepare */
typedef void(__cdecl* fnAPI_Reset_Prepare)(void);
/** @typedef fnAPI_Prepare_Done */
typedef int(__cdecl* fnAPI_Prepare_Done)(void);
/** @typedef fnAPI_Exit_MainThread */
typedef void(__cdecl* fnAPI_Exit_MainThread)(void);
/** @typedef fnAPI_Call */
typedef TDataHnd(__cdecl* fnAPI_Call)(const char*, TDataHnd, uint64_t);
/** @typedef fnAPI_Notify */
typedef void(__cdecl* fnAPI_Notify)(const char*, TDataHnd);
/** @typedef fnAPI_SetOption */
typedef void(__cdecl* fnAPI_SetOption)(const char*, const char*);
/** @typedef fnAPI_shutdown */
typedef void(__cdecl* fnAPI_shutdown)(void);

/* ============================================================================
   Static function pointers (resolved at runtime).
   Naming convention: pAPI_ + function name (without "API_" prefix).
   ============================================================================ */

static fnAPI_Create_DataHnd   pAPI_Create_DataHnd = NULL;
static fnAPI_Free_DataHnd     pAPI_Free_DataHnd = NULL;
static fnAPI_GetBuffer        pAPI_GetBuffer = NULL;
static fnAPI_WriteBuffer      pAPI_WriteBuffer = NULL;
static fnAPI_ReadBuffer       pAPI_ReadBuffer = NULL;
static fnAPI_GetPos           pAPI_GetPos = NULL;
static fnAPI_SetPos           pAPI_SetPos = NULL;
static fnAPI_GetSize          pAPI_GetSize = NULL;
static fnAPI_SetSize          pAPI_SetSize = NULL;
static fnAPI_Create_APPHnd    pAPI_Create_APPHnd = NULL;
static fnAPI_Free_APPHnd      pAPI_Free_APPHnd = NULL;
static fnAPI_Reg_Call         pAPI_Reg_Call = NULL;
static fnAPI_Reg_Notify       pAPI_Reg_Notify = NULL;
static fnAPI_UnReg            pAPI_UnReg = NULL;
static fnAPI_Local_APP_Call   pAPI_Local_APP_Call = NULL;
static fnAPI_Local_APP_Notify pAPI_Local_APP_Notify = NULL;
static fnAPI_Prepare_Service  pAPI_Prepare_Service = NULL;
static fnAPI_Prepare_Client   pAPI_Prepare_Client = NULL;
static fnAPI_Reset_Prepare    pAPI_Reset_Prepare = NULL;
static fnAPI_Prepare_Done     pAPI_Prepare_Done = NULL;
static fnAPI_Exit_MainThread  pAPI_Exit_MainThread = NULL;
static fnAPI_Call             pAPI_Call = NULL;
static fnAPI_Notify           pAPI_Notify = NULL;
static fnAPI_SetOption        pAPI_SetOption = NULL;
static fnAPI_shutdown         pAPI_shutdown = NULL;

/* ============================================================================
   Internal helper macros
   ============================================================================ */

   /**
    * @def RESOLVE(func)
    * @brief Resolves a function pointer from the DLL.
    *
    * This macro uses the function name (without "API_" prefix) to construct
    * the variable name `pAPI_` + func (e.g., pAPI_Create_DataHnd) and the
    * type name `fnAPI_` + func (e.g., fnAPI_Create_DataHnd). It fetches the
    * address from the DLL using platform‑specific API.
    *
    * On failure, it prints an error to stderr and returns 0 from the calling
    * function (which is API_LoadLibrary).
    *
    * @param func  The function name without "API_" prefix (e.g., Create_DataHnd).
    */
#define RESOLVE(func) \
    pAPI_##func = (fnAPI_##func)GET_PROC_ADDRESS(g_hDll, "API_" #func); \
    if (!pAPI_##func) { \
        fprintf(stderr, "API_HubTool: Failed to resolve API_" #func "\n"); \
        return 0; \
    }

    /**
     * @def ZERO(func)
     * @brief Sets a function pointer to NULL.
     *
     * Used during library unloading to clear all resolved pointers.
     */
#define ZERO(func) pAPI_##func = NULL

     /* ============================================================================
        Helper function: get executable directory path (cross‑platform)
        ============================================================================ */

        /**
         * @brief Retrieves the full path of the current executable and returns its
         *        directory (without trailing slash).
         *
         * On Windows, uses GetModuleFileNameA. On Linux, uses readlink("/proc/self/exe").
         * The result is stored in the provided buffer.
         *
         * @param buf   Output buffer to store the directory (must be at least PATH_MAX).
         * @param size  Size of the buffer.
         * @return 1 on success, 0 on failure.
         *
         * @note This function is called only once during library loading.
         */
static int GetExeDirectory(char* buf, size_t size)
{
    char fullPath[PATH_MAX];
    if (GET_EXE_PATH(fullPath, sizeof(fullPath)) == 0) {
        return 0;
    }
    /* Find the last directory separator (handle both / and \) */
    char* lastSep = strrchr(fullPath, '/');
    if (!lastSep) {
        lastSep = strrchr(fullPath, '\\');  // Windows fallback
    }
    if (lastSep) {
        *lastSep = '\0';                     // terminate at the directory
        strncpy(buf, fullPath, size - 1);
        buf[size - 1] = '\0';
        return 1;
    }
    return 0;
}

/* ============================================================================
   Library loading / unloading
   ============================================================================ */

   /**
    * @brief Loads the dynamic library and resolves all function pointers.
    *
    * On Windows, looks for "api_hub.dll".
    * On Linux, looks for "libapi_hub.so".
    * On macOS, looks for "libapi_hub.dylib".
    *
    * The function first attempts to load from the executable's directory,
    * then falls back to the system search path.
    *
    * @return 1 on success, 0 on failure.
    *
    * @note This function is called by the user; it sets g_loaded to 1 on success.
    */
int API_LoadLibrary(void)
{
    if (g_loaded) return 1;   // already loaded

    char exeDir[PATH_MAX] = { 0 };
    char dllPath[PATH_MAX] = { 0 };

#ifdef _WIN32
#ifdef _WIN64
    const char* dllName = "z_api_hub64.dll";
#else
    const char* dllName = "z_api_hub32.dll";
#endif
#elif defined(__APPLE__)
    const char* dllName = "z_api_hub.dylib";
#else
    const char* dllName = "z_api_hub.so";
#endif

    /* First, try to load from the executable directory */
    if (GetExeDirectory(exeDir, sizeof(exeDir))) {
        snprintf(dllPath, sizeof(dllPath), "%s%c%s", exeDir, PATH_SEPARATOR, dllName);
        g_hDll = LOAD_LIBRARY(dllPath);
    }

    /* If that fails, try system path (just the library name) */
    if (!g_hDll) {
        g_hDll = LOAD_LIBRARY(dllName);
        if (!g_hDll) {
            fprintf(stderr, "API_HubTool: Failed to load %s from %s or system path\n",
                dllName, dllPath);
            return 0;
        }
    }

    /* Resolve all API functions using the RESOLVE macro */
    RESOLVE(Create_DataHnd);
    RESOLVE(Free_DataHnd);
    RESOLVE(GetBuffer);
    RESOLVE(WriteBuffer);
    RESOLVE(ReadBuffer);
    RESOLVE(GetPos);
    RESOLVE(SetPos);
    RESOLVE(GetSize);
    RESOLVE(SetSize);
    RESOLVE(Create_APPHnd);
    RESOLVE(Free_APPHnd);
    RESOLVE(Reg_Call);
    RESOLVE(Reg_Notify);
    RESOLVE(UnReg);
    RESOLVE(Local_APP_Call);
    RESOLVE(Local_APP_Notify);
    RESOLVE(Prepare_Service);
    RESOLVE(Prepare_Client);
    RESOLVE(Reset_Prepare);
    RESOLVE(Prepare_Done);
    RESOLVE(Exit_MainThread);
    RESOLVE(Call);
    RESOLVE(Notify);
    RESOLVE(SetOption);
    RESOLVE(shutdown);

    g_loaded = 1;
    return 1;
}

/**
 * @brief Unloads the dynamic library and resets all function pointers.
 *
 * This function frees the library handle (if any) and clears all resolved
 * function pointers to prevent accidental use after unload. It also sets
 * g_loaded to 0.
 */
void API_FreeLibrary(void)
{
    if (g_hDll) {
        FREE_LIBRARY(g_hDll);
        g_hDll = NULL;
    }
    /* Clear all function pointers to NULL */
    ZERO(Create_DataHnd);
    ZERO(Free_DataHnd);
    ZERO(GetBuffer);
    ZERO(WriteBuffer);
    ZERO(ReadBuffer);
    ZERO(GetPos);
    ZERO(SetPos);
    ZERO(GetSize);
    ZERO(SetSize);
    ZERO(Create_APPHnd);
    ZERO(Free_APPHnd);
    ZERO(Reg_Call);
    ZERO(Reg_Notify);
    ZERO(UnReg);
    ZERO(Local_APP_Call);
    ZERO(Local_APP_Notify);
    ZERO(Prepare_Service);
    ZERO(Prepare_Client);
    ZERO(Reset_Prepare);
    ZERO(Prepare_Done);
    ZERO(Exit_MainThread);
    ZERO(Call);
    ZERO(Notify);
    ZERO(SetOption);
    ZERO(shutdown);
    g_loaded = 0;
}

/* ============================================================================
   Safety check macros for wrapper functions
   ============================================================================ */

   /**
    * @def CHECK_LOADED_RET(func, ret)
    * @brief Checks if the library is loaded and the function pointer is non‑NULL.
    *        If not, prints an error and returns @p ret.
    * @param func  The name of the function (without "API_" prefix).
    * @param ret   The value to return on failure.
    */
#define CHECK_LOADED_RET(func, ret) \
    if (!g_loaded || !pAPI_##func) { \
        fprintf(stderr, "API_HubTool: " #func " called without library loaded\n"); \
        return ret; \
    }

    /**
     * @def CHECK_LOADED_VOID(func)
     * @brief Similar to CHECK_LOADED_RET but for void functions.
     */
#define CHECK_LOADED_VOID(func) \
    if (!g_loaded || !pAPI_##func) { \
        fprintf(stderr, "API_HubTool: " #func " called without library loaded\n"); \
        return; \
    }

     /* ============================================================================
        Wrapper implementations (all function forwarders)
        ============================================================================ */

        /* ----- Data handle operations ----- */
TDataHnd API_Create_DataHnd(const char* APIName) {
    CHECK_LOADED_RET(Create_DataHnd, NULL);
    return pAPI_Create_DataHnd(APIName);
}
void API_Free_DataHnd(TDataHnd Hnd) {
    CHECK_LOADED_VOID(Free_DataHnd);
    pAPI_Free_DataHnd(Hnd);
}
void* API_GetBuffer(TDataHnd Hnd) {
    CHECK_LOADED_RET(GetBuffer, NULL);
    return pAPI_GetBuffer(Hnd);
}
int64_t API_WriteBuffer(TDataHnd Hnd, const void* Buff, int64_t Size) {
    CHECK_LOADED_RET(WriteBuffer, 0);
    return pAPI_WriteBuffer(Hnd, Buff, Size);
}
int64_t API_ReadBuffer(TDataHnd Hnd, void* Buff, int64_t Size) {
    CHECK_LOADED_RET(ReadBuffer, 0);
    return pAPI_ReadBuffer(Hnd, Buff, Size);
}
int64_t API_GetPos(TDataHnd Hnd) {
    CHECK_LOADED_RET(GetPos, 0);
    return pAPI_GetPos(Hnd);
}
void API_SetPos(TDataHnd Hnd, int64_t Pos_) {
    CHECK_LOADED_VOID(SetPos);
    pAPI_SetPos(Hnd, Pos_);
}
int64_t API_GetSize(TDataHnd Hnd) {
    CHECK_LOADED_RET(GetSize, 0);
    return pAPI_GetSize(Hnd);
}
void API_SetSize(TDataHnd Hnd, int64_t Size_) {
    CHECK_LOADED_VOID(SetSize);
    pAPI_SetSize(Hnd, Size_);
}

/* ----- Application handle operations ----- */
TAppHnd API_Create_APPHnd(const char* appName, const char* Desc) {
    CHECK_LOADED_RET(Create_APPHnd, NULL);
    return pAPI_Create_APPHnd(appName, Desc);
}
void API_Free_APPHnd(TAppHnd appHnd) {
    CHECK_LOADED_VOID(Free_APPHnd);
    pAPI_Free_APPHnd(appHnd);
}
int API_Reg_Call(TAppHnd appHnd, const char* APIName, const char* Desc,
    void* Trigger, TAPI_Call OnCall) {
    CHECK_LOADED_RET(Reg_Call, 0);
    return pAPI_Reg_Call(appHnd, APIName, Desc, Trigger, OnCall);
}
int API_Reg_Notify(TAppHnd appHnd, const char* APIName, const char* Desc,
    void* Trigger, TAPI_Notify OnNotify) {
    CHECK_LOADED_RET(Reg_Notify, 0);
    return pAPI_Reg_Notify(appHnd, APIName, Desc, Trigger, OnNotify);
}
int API_UnReg(TAppHnd appHnd, const char* APIName) {
    CHECK_LOADED_RET(UnReg, 0);
    return pAPI_UnReg(appHnd, APIName);
}
TDataHnd API_Local_APP_Call(TAppHnd appHnd, TDataHnd Param) {
    CHECK_LOADED_RET(Local_APP_Call, NULL);
    return pAPI_Local_APP_Call(appHnd, Param);
}
void API_Local_APP_Notify(TAppHnd appHnd, TDataHnd Param) {
    CHECK_LOADED_VOID(Local_APP_Notify);
    pAPI_Local_APP_Notify(appHnd, Param);
}

/* ----- Network preparation and communication ----- */
int API_Prepare_Service(const char* ListeningAddr_, const char* PhysicsAddr_) {
    CHECK_LOADED_RET(Prepare_Service, 0);
    return pAPI_Prepare_Service(ListeningAddr_, PhysicsAddr_);
}
int API_Prepare_Client(const char* PhysicsAddr_, TAppHnd appHnd) {
    CHECK_LOADED_RET(Prepare_Client, 0);
    return pAPI_Prepare_Client(PhysicsAddr_, appHnd);
}
void API_Reset_Prepare(void) {
    CHECK_LOADED_VOID(Reset_Prepare);
    pAPI_Reset_Prepare();
}
int API_Prepare_Done(void) {
    CHECK_LOADED_RET(Prepare_Done, 0);
    return pAPI_Prepare_Done();
}
void API_Exit_MainThread(void) {
    CHECK_LOADED_VOID(Exit_MainThread);
    pAPI_Exit_MainThread();
}
TDataHnd API_Call(const char* appName, TDataHnd Param, uint64_t Timeout_) {
    CHECK_LOADED_RET(Call, NULL);
    return pAPI_Call(appName, Param, Timeout_);
}
void API_Notify(const char* appName, TDataHnd Param) {
    CHECK_LOADED_VOID(Notify);
    pAPI_Notify(appName, Param);
}
void API_SetOption(const char* Option, const char* Value) {
    CHECK_LOADED_VOID(SetOption);
    pAPI_SetOption(Option, Value);
}
void API_shutdown(void) {
    CHECK_LOADED_VOID(shutdown);
    pAPI_shutdown();
}