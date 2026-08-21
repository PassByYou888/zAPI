/**
 * @file API_HubTool.h
 * @brief C explicit‑linking wrapper – strictly matches Pascal export table.
 *
 * Only the 25 functions marked as 'external' in z_api_hubtool_import.pas
 * are resolved from the dynamic library. All helper functions are implemented
 * in the C wrapper itself, using API_WriteBuffer / API_ReadBuffer.
 *
 * @section export_table Exported Functions (25 total)
 * 1  API_shutdown
 * 2  API_SetOption
 * 3  API_Notify
 * 4  API_Call
 * 5  API_Exit_MainThread
 * 6  API_Prepare_Done
 * 7  API_Reset_Prepare
 * 8  API_Prepare_Client
 * 9  API_Prepare_Service
 * 10 API_Local_APP_Notify
 * 11 API_Local_APP_Call
 * 12 API_UnReg
 * 13 API_Reg_Notify
 * 14 API_Reg_Call
 * 15 API_Free_APPHnd
 * 16 API_Create_APPHnd
 * 17 API_SetSize
 * 18 API_GetSize
 * 19 API_SetPos
 * 20 API_GetPos
 * 21 API_ReadBuffer
 * 22 API_WriteBuffer
 * 23 API_GetBuffer
 * 24 API_Free_DataHnd
 * 25 API_Create_DataHnd
 */

#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

    /* ============================================================================
       Opaque handle types
       ============================================================================ */
    typedef void* TDataHnd;
    typedef void* TAppHnd;

    /* ============================================================================
       Callback types
       ============================================================================ */
    typedef void(__cdecl* TAPI_Call)(void* Trigger, void* Input, void* Output);
    typedef void(__cdecl* TAPI_Notify)(void* Trigger, void* Input);

    /* ============================================================================
       Library loading / unloading
       ============================================================================ */
    int  API_LoadLibrary(void);
    void API_FreeLibrary(void);

    /* ============================================================================
       25 EXPORTED FUNCTIONS (matches Pascal external declarations)
       ============================================================================ */

       /* ----- Data Handle ----- */
    TDataHnd API_Create_DataHnd(const char* APIName);
    void     API_Free_DataHnd(TDataHnd Hnd);
    void* API_GetBuffer(TDataHnd Hnd);
    int64_t  API_WriteBuffer(TDataHnd Hnd, const void* Buff, int64_t Size);
    int64_t  API_ReadBuffer(TDataHnd Hnd, void* Buff, int64_t Size);
    int64_t  API_GetPos(TDataHnd Hnd);
    void     API_SetPos(TDataHnd Hnd, int64_t Pos_);
    int64_t  API_GetSize(TDataHnd Hnd);
    void     API_SetSize(TDataHnd Hnd, int64_t Size_);

    /* ----- Application Handle ----- */
    TAppHnd  API_Create_APPHnd(const char* appName, const char* Desc);
    void     API_Free_APPHnd(TAppHnd appHnd);
    int      API_Reg_Call(TAppHnd appHnd, const char* APIName, const char* Desc,
        void* Trigger, TAPI_Call OnCall);
    int      API_Reg_Notify(TAppHnd appHnd, const char* APIName, const char* Desc,
        void* Trigger, TAPI_Notify OnNotify);
    int      API_UnReg(TAppHnd appHnd, const char* APIName);
    TDataHnd API_Local_APP_Call(TAppHnd appHnd, TDataHnd Param);
    void     API_Local_APP_Notify(TAppHnd appHnd, TDataHnd Param);

    /* ----- Network ----- */
    int      API_Prepare_Service(const char* ListeningAddr_, const char* PhysicsAddr_);
    int      API_Prepare_Client(const char* PhysicsAddr_, TAppHnd appHnd);
    void     API_Reset_Prepare(void);
    int      API_Prepare_Done(void);
    void     API_Exit_MainThread(void);
    TDataHnd API_Call(const char* appName, TDataHnd Param, uint64_t Timeout_);
    void     API_Notify(const char* appName, TDataHnd Param);
    void     API_SetOption(const char* Option, const char* Value);
    void     API_shutdown(void);

    /* ============================================================================
       HELPER FUNCTIONS – implemented in C, NOT exported from DLL
       These mirror the Pascal implementations in z_api_hubtool_import.pas
       ============================================================================ */

       /* ----- Atomic write helpers (return 1 on success, 0 on failure) ----- */
    int API_WriteInt8(TDataHnd Hnd, int8_t  Value);
    int API_WriteUInt8(TDataHnd Hnd, uint8_t Value);
    int API_WriteInt16(TDataHnd Hnd, int16_t Value);
    int API_WriteUInt16(TDataHnd Hnd, uint16_t Value);
    int API_WriteInt32(TDataHnd Hnd, int32_t Value);
    int API_WriteUInt32(TDataHnd Hnd, uint32_t Value);
    int API_WriteInt64(TDataHnd Hnd, int64_t Value);
    int API_WriteUInt64(TDataHnd Hnd, uint64_t Value);
    int API_WriteSingle(TDataHnd Hnd, float   Value);
    int API_WriteDouble(TDataHnd Hnd, double  Value);

    /**
     * @brief Writes UTF‑8 string followed by null terminator (#0).
     *        Matches Pascal's API_WriteString exactly.
     * @param Hnd   Data handle.
     * @param Value Null‑terminated UTF‑8 string (may be empty).
     * @return 1 if full string + null was written, 0 otherwise.
     */
    int API_WriteString(TDataHnd Hnd, const char* Value);

    /* ----- Atomic read helpers (return 1 on success, 0 on failure) ----- */
    int API_ReadInt8(TDataHnd Hnd, int8_t* pValue);
    int API_ReadUInt8(TDataHnd Hnd, uint8_t* pValue);
    int API_ReadInt16(TDataHnd Hnd, int16_t* pValue);
    int API_ReadUInt16(TDataHnd Hnd, uint16_t* pValue);
    int API_ReadInt32(TDataHnd Hnd, int32_t* pValue);
    int API_ReadUInt32(TDataHnd Hnd, uint32_t* pValue);
    int API_ReadInt64(TDataHnd Hnd, int64_t* pValue);
    int API_ReadUInt64(TDataHnd Hnd, uint64_t* pValue);
    int API_ReadSingle(TDataHnd Hnd, float* pValue);
    int API_ReadDouble(TDataHnd Hnd, double* pValue);

    /**
     * @brief Reads a null‑terminated UTF‑8 string from current position.
     *        Matches Pascal's API_ReadString exactly.
     *        Position is advanced past the null terminator.
     * @param Hnd     Data handle.
     * @param pBuf    Output buffer (must be at least bufSize bytes).
     * @param bufSize Size of output buffer.
     * @return 1 if null terminator found and string copied, 0 otherwise.
     * @note If buffer is too small, returns 0 and position is NOT advanced.
     *       If successful, position is advanced past the null.
     */
    int API_ReadString(TDataHnd Hnd, char* pBuf, size_t bufSize);

#ifdef __cplusplus
}
#endif