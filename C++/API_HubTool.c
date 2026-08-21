/**
 * @file API_HubTool.c
 * @brief Implementation – resolves ONLY the 25 exported functions.
 *
 * All helper functions (WriteInt8, ReadString, etc.) are implemented
 * using API_WriteBuffer / API_ReadBuffer, matching Pascal semantics.
 */

#define _CRT_SECURE_NO_WARNINGS
#include "API_HubTool.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

 /* ============================================================================
    Platform‑specific dynamic loading
    ============================================================================ */
#ifdef _WIN32
#  include <windows.h>
#  define LIB_HANDLE HMODULE
#  define LOAD_LIBRARY(path) LoadLibraryA(path)
#  define GET_PROC_ADDRESS(handle, name) GetProcAddress(handle, name)
#  define FREE_LIBRARY(handle) FreeLibrary(handle)
#  define GET_EXE_PATH(buf, size) GetModuleFileNameA(GetModuleHandleA(NULL), buf, size)
#  define PATH_SEPARATOR '\\'
#  ifndef PATH_MAX
#    define PATH_MAX 260
#  endif
#else
#  include <dlfcn.h>
#  include <unistd.h>
#  include <limits.h>
#  define LIB_HANDLE void*
#  define LOAD_LIBRARY(path) dlopen(path, RTLD_LAZY)
#  define GET_PROC_ADDRESS(handle, name) dlsym(handle, name)
#  define FREE_LIBRARY(handle) dlclose(handle)
#  define GET_EXE_PATH(buf, size) readlink("/proc/self/exe", buf, size - 1)
#  define PATH_SEPARATOR '/'
#  ifndef PATH_MAX
#    define PATH_MAX 4096
#  endif
#endif

    /* ============================================================================
       Global state
       ============================================================================ */
static LIB_HANDLE g_hDll = NULL;
static int g_loaded = 0;

/* ============================================================================
   Function pointer types for the 25 exported functions
   ============================================================================ */
typedef TDataHnd(__cdecl* fnAPI_Create_DataHnd) (const char*);
typedef void(__cdecl* fnAPI_Free_DataHnd)   (TDataHnd);
typedef void* (__cdecl* fnAPI_GetBuffer)      (TDataHnd);
typedef int64_t(__cdecl* fnAPI_WriteBuffer)    (TDataHnd, const void*, int64_t);
typedef int64_t(__cdecl* fnAPI_ReadBuffer)     (TDataHnd, void*, int64_t);
typedef int64_t(__cdecl* fnAPI_GetPos)         (TDataHnd);
typedef void(__cdecl* fnAPI_SetPos)         (TDataHnd, int64_t);
typedef int64_t(__cdecl* fnAPI_GetSize)        (TDataHnd);
typedef void(__cdecl* fnAPI_SetSize)        (TDataHnd, int64_t);

typedef TAppHnd(__cdecl* fnAPI_Create_APPHnd)  (const char*, const char*);
typedef void(__cdecl* fnAPI_Free_APPHnd)    (TAppHnd);
typedef int(__cdecl* fnAPI_Reg_Call)       (TAppHnd, const char*, const char*, void*, TAPI_Call);
typedef int(__cdecl* fnAPI_Reg_Notify)     (TAppHnd, const char*, const char*, void*, TAPI_Notify);
typedef int(__cdecl* fnAPI_UnReg)          (TAppHnd, const char*);
typedef TDataHnd(__cdecl* fnAPI_Local_APP_Call) (TAppHnd, TDataHnd);
typedef void(__cdecl* fnAPI_Local_APP_Notify)(TAppHnd, TDataHnd);

typedef int(__cdecl* fnAPI_Prepare_Service)(const char*, const char*);
typedef int(__cdecl* fnAPI_Prepare_Client) (const char*, TAppHnd);
typedef void(__cdecl* fnAPI_Reset_Prepare)  (void);
typedef int(__cdecl* fnAPI_Prepare_Done)   (void);
typedef void(__cdecl* fnAPI_Exit_MainThread)(void);
typedef TDataHnd(__cdecl* fnAPI_Call)           (const char*, TDataHnd, uint64_t);
typedef void(__cdecl* fnAPI_Notify)         (const char*, TDataHnd);
typedef void(__cdecl* fnAPI_SetOption)      (const char*, const char*);
typedef void(__cdecl* fnAPI_shutdown)       (void);

/* ============================================================================
   Static function pointers for the 25 exports
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
   Helper macros
   ============================================================================ */
#define RESOLVE(func) \
    pAPI_##func = (fnAPI_##func)GET_PROC_ADDRESS(g_hDll, "API_" #func); \
    if (!pAPI_##func) { \
        fprintf(stderr, "API_HubTool: Failed to resolve API_" #func "\n"); \
        return 0; \
    }

#define ZERO(func) pAPI_##func = NULL

#define CHECK_LOADED_RET(func, ret) \
    if (!g_loaded || !pAPI_##func) { \
        fprintf(stderr, "API_HubTool: " #func " called without library loaded\n"); \
        return ret; \
    }

#define CHECK_LOADED_VOID(func) \
    if (!g_loaded || !pAPI_##func) { \
        fprintf(stderr, "API_HubTool: " #func " called without library loaded\n"); \
        return; \
    }

   /* ============================================================================
      Helper: get executable directory
      ============================================================================ */
static int GetExeDirectory(char* buf, size_t size) {
    char fullPath[PATH_MAX];
    if (GET_EXE_PATH(fullPath, sizeof(fullPath)) == 0) return 0;
    char* lastSep = strrchr(fullPath, '/');
    if (!lastSep) lastSep = strrchr(fullPath, '\\');
    if (lastSep) {
        *lastSep = '\0';
        strncpy(buf, fullPath, size - 1);
        buf[size - 1] = '\0';
        return 1;
    }
    return 0;
}

/* ============================================================================
   Library loading / unloading
   ============================================================================ */
int API_LoadLibrary(void) {
    if (g_loaded) return 1;

    char exeDir[PATH_MAX] = { 0 };
    char dllPath[PATH_MAX] = { 0 };

#ifdef _WIN32
#  ifdef _WIN64
    const char* dllName = "z_api_hub64.dll";
#  else
    const char* dllName = "z_api_hub32.dll";
#  endif
#elif defined(__APPLE__)
    const char* dllName = "libz_api_hub.dylib";
#else
    const char* dllName = "libz_api_hub.so";
#endif

    if (GetExeDirectory(exeDir, sizeof(exeDir))) {
        snprintf(dllPath, sizeof(dllPath), "%s%c%s", exeDir, PATH_SEPARATOR, dllName);
        g_hDll = LOAD_LIBRARY(dllPath);
    }
    if (!g_hDll) {
        g_hDll = LOAD_LIBRARY(dllName);
        if (!g_hDll) {
            fprintf(stderr, "API_HubTool: Failed to load %s\n", dllName);
            return 0;
        }
    }

    /* ---- Resolve ONLY the 25 exported functions ---- */
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

void API_FreeLibrary(void) {
    if (g_hDll) {
        FREE_LIBRARY(g_hDll);
        g_hDll = NULL;
    }
    /* Clear all function pointers */
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
   25 EXPORTED FUNCTIONS – forwarders to resolved pointers
   ============================================================================ */

TDataHnd API_Create_DataHnd(const char* APIName) {
    if (APIName == NULL) { fprintf(stderr, "API_Create_DataHnd: NULL APIName\n"); return NULL; }
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

TAppHnd API_Create_APPHnd(const char* appName, const char* Desc) {
    if (appName == NULL) { fprintf(stderr, "API_Create_APPHnd: NULL appName\n"); return NULL; }
    CHECK_LOADED_RET(Create_APPHnd, NULL);
    return pAPI_Create_APPHnd(appName, Desc);
}

void API_Free_APPHnd(TAppHnd appHnd) {
    CHECK_LOADED_VOID(Free_APPHnd);
    pAPI_Free_APPHnd(appHnd);
}

int API_Reg_Call(TAppHnd appHnd, const char* APIName, const char* Desc,
    void* Trigger, TAPI_Call OnCall) {
    if (APIName == NULL) { fprintf(stderr, "API_Reg_Call: NULL APIName\n"); return 0; }
    CHECK_LOADED_RET(Reg_Call, 0);
    return pAPI_Reg_Call(appHnd, APIName, Desc, Trigger, OnCall);
}

int API_Reg_Notify(TAppHnd appHnd, const char* APIName, const char* Desc,
    void* Trigger, TAPI_Notify OnNotify) {
    if (APIName == NULL) { fprintf(stderr, "API_Reg_Notify: NULL APIName\n"); return 0; }
    CHECK_LOADED_RET(Reg_Notify, 0);
    return pAPI_Reg_Notify(appHnd, APIName, Desc, Trigger, OnNotify);
}

int API_UnReg(TAppHnd appHnd, const char* APIName) {
    if (APIName == NULL) { fprintf(stderr, "API_UnReg: NULL APIName\n"); return 0; }
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

int API_Prepare_Service(const char* ListeningAddr_, const char* PhysicsAddr_) {
    if (ListeningAddr_ == NULL || PhysicsAddr_ == NULL) {
        fprintf(stderr, "API_Prepare_Service: NULL address\n"); return 0;
    }
    CHECK_LOADED_RET(Prepare_Service, 0);
    return pAPI_Prepare_Service(ListeningAddr_, PhysicsAddr_);
}

int API_Prepare_Client(const char* PhysicsAddr_, TAppHnd appHnd) {
    if (PhysicsAddr_ == NULL) { fprintf(stderr, "API_Prepare_Client: NULL PhysicsAddr_\n"); return 0; }
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
    if (appName == NULL) { fprintf(stderr, "API_Call: NULL appName\n"); return NULL; }
    CHECK_LOADED_RET(Call, NULL);
    return pAPI_Call(appName, Param, Timeout_);
}

void API_Notify(const char* appName, TDataHnd Param) {
    if (appName == NULL) { fprintf(stderr, "API_Notify: NULL appName\n"); return; }
    CHECK_LOADED_VOID(Notify);
    pAPI_Notify(appName, Param);
}

void API_SetOption(const char* Option, const char* Value) {
    if (Option == NULL || Value == NULL) { fprintf(stderr, "API_SetOption: NULL argument\n"); return; }
    CHECK_LOADED_VOID(SetOption);
    pAPI_SetOption(Option, Value);
}

void API_shutdown(void) {
    CHECK_LOADED_VOID(shutdown);
    pAPI_shutdown();
}

/* ============================================================================
   HELPER FUNCTIONS – implemented using API_WriteBuffer / API_ReadBuffer
   Match Pascal implementations exactly
   ============================================================================ */

   /* ----- Write helpers (little-endian, return 1 on success) ----- */
int API_WriteInt8(TDataHnd Hnd, int8_t Value) {
    CHECK_LOADED_RET(WriteBuffer, 0);
    return (pAPI_WriteBuffer(Hnd, &Value, 1) == 1) ? 1 : 0;
}
int API_WriteUInt8(TDataHnd Hnd, uint8_t Value) {
    CHECK_LOADED_RET(WriteBuffer, 0);
    return (pAPI_WriteBuffer(Hnd, &Value, 1) == 1) ? 1 : 0;
}
int API_WriteInt16(TDataHnd Hnd, int16_t Value) {
    CHECK_LOADED_RET(WriteBuffer, 0);
    return (pAPI_WriteBuffer(Hnd, &Value, 2) == 2) ? 1 : 0;
}
int API_WriteUInt16(TDataHnd Hnd, uint16_t Value) {
    CHECK_LOADED_RET(WriteBuffer, 0);
    return (pAPI_WriteBuffer(Hnd, &Value, 2) == 2) ? 1 : 0;
}
int API_WriteInt32(TDataHnd Hnd, int32_t Value) {
    CHECK_LOADED_RET(WriteBuffer, 0);
    return (pAPI_WriteBuffer(Hnd, &Value, 4) == 4) ? 1 : 0;
}
int API_WriteUInt32(TDataHnd Hnd, uint32_t Value) {
    CHECK_LOADED_RET(WriteBuffer, 0);
    return (pAPI_WriteBuffer(Hnd, &Value, 4) == 4) ? 1 : 0;
}
int API_WriteInt64(TDataHnd Hnd, int64_t Value) {
    CHECK_LOADED_RET(WriteBuffer, 0);
    return (pAPI_WriteBuffer(Hnd, &Value, 8) == 8) ? 1 : 0;
}
int API_WriteUInt64(TDataHnd Hnd, uint64_t Value) {
    CHECK_LOADED_RET(WriteBuffer, 0);
    return (pAPI_WriteBuffer(Hnd, &Value, 8) == 8) ? 1 : 0;
}
int API_WriteSingle(TDataHnd Hnd, float Value) {
    CHECK_LOADED_RET(WriteBuffer, 0);
    return (pAPI_WriteBuffer(Hnd, &Value, 4) == 4) ? 1 : 0;
}
int API_WriteDouble(TDataHnd Hnd, double Value) {
    CHECK_LOADED_RET(WriteBuffer, 0);
    return (pAPI_WriteBuffer(Hnd, &Value, 8) == 8) ? 1 : 0;
}

int API_WriteString(TDataHnd Hnd, const char* Value) {
    if (Value == NULL) return 0;
    CHECK_LOADED_RET(WriteBuffer, 0);
    size_t len = strlen(Value);
    // 1. Write UTF-8 content
    if (pAPI_WriteBuffer(Hnd, Value, (int64_t)len) != (int64_t)len) return 0;
    // 2. Write null terminator (#0)
    char nul = 0;
    return (pAPI_WriteBuffer(Hnd, &nul, 1) == 1) ? 1 : 0;
}

/* ----- Read helpers (return 1 on success) ----- */
int API_ReadInt8(TDataHnd Hnd, int8_t* pValue) {
    CHECK_LOADED_RET(ReadBuffer, 0);
    return (pAPI_ReadBuffer(Hnd, pValue, 1) == 1) ? 1 : 0;
}
int API_ReadUInt8(TDataHnd Hnd, uint8_t* pValue) {
    CHECK_LOADED_RET(ReadBuffer, 0);
    return (pAPI_ReadBuffer(Hnd, pValue, 1) == 1) ? 1 : 0;
}
int API_ReadInt16(TDataHnd Hnd, int16_t* pValue) {
    CHECK_LOADED_RET(ReadBuffer, 0);
    return (pAPI_ReadBuffer(Hnd, pValue, 2) == 2) ? 1 : 0;
}
int API_ReadUInt16(TDataHnd Hnd, uint16_t* pValue) {
    CHECK_LOADED_RET(ReadBuffer, 0);
    return (pAPI_ReadBuffer(Hnd, pValue, 2) == 2) ? 1 : 0;
}
int API_ReadInt32(TDataHnd Hnd, int32_t* pValue) {
    CHECK_LOADED_RET(ReadBuffer, 0);
    return (pAPI_ReadBuffer(Hnd, pValue, 4) == 4) ? 1 : 0;
}
int API_ReadUInt32(TDataHnd Hnd, uint32_t* pValue) {
    CHECK_LOADED_RET(ReadBuffer, 0);
    return (pAPI_ReadBuffer(Hnd, pValue, 4) == 4) ? 1 : 0;
}
int API_ReadInt64(TDataHnd Hnd, int64_t* pValue) {
    CHECK_LOADED_RET(ReadBuffer, 0);
    return (pAPI_ReadBuffer(Hnd, pValue, 8) == 8) ? 1 : 0;
}
int API_ReadUInt64(TDataHnd Hnd, uint64_t* pValue) {
    CHECK_LOADED_RET(ReadBuffer, 0);
    return (pAPI_ReadBuffer(Hnd, pValue, 8) == 8) ? 1 : 0;
}
int API_ReadSingle(TDataHnd Hnd, float* pValue) {
    CHECK_LOADED_RET(ReadBuffer, 0);
    return (pAPI_ReadBuffer(Hnd, pValue, 4) == 4) ? 1 : 0;
}
int API_ReadDouble(TDataHnd Hnd, double* pValue) {
    CHECK_LOADED_RET(ReadBuffer, 0);
    return (pAPI_ReadBuffer(Hnd, pValue, 8) == 8) ? 1 : 0;
}

int API_ReadString(TDataHnd Hnd, char* pBuf, size_t bufSize) {
    if (pBuf == NULL || bufSize == 0) return 0;
    CHECK_LOADED_RET(ReadBuffer, 0);

    int64_t start = pAPI_GetPos(Hnd);
    int64_t size = pAPI_GetSize(Hnd);
    if (start >= size) { *pBuf = '\0'; return 0; }

    const unsigned char* raw = (const unsigned char*)pAPI_GetBuffer(Hnd);
    if (!raw) { *pBuf = '\0'; return 0; }

    const unsigned char* p = raw + start;
    int64_t len = 0;
    while (start + len < size && p[len] != 0) {
        len++;
    }
    if (start + len >= size) { *pBuf = '\0'; return 0; }

    size_t copyLen = (len < (int64_t)bufSize - 1) ? (size_t)len : (bufSize - 1);
    memcpy(pBuf, p, copyLen);
    pBuf[copyLen] = '\0';

    pAPI_SetPos(Hnd, start + len + 1);
    return 1;
}