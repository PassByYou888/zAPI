package com.apihub;

import com.sun.jna.Library;
import com.sun.jna.Native;
import com.sun.jna.Platform;
import com.sun.jna.Pointer;

import java.util.HashMap;
import java.util.Map;

/**
 * JNA direct mapping to the C API exported by the API Hub dynamic library.
 * <p>
 * This interface is a 1:1 translation of the Pascal import unit
 * {@code z_api_hubtool_import.pas}. All functions follow the same calling
 * conventions (cdecl), parameter order, and semantics.
 * <p>
 * <b>String encoding:</b> All {@code String} parameters are encoded as
 * UTF‑8, enforced by the {@code OPTION_STRING_ENCODING} option passed to
 * {@link Native#load(String, Class, Map)}. This matches the Pascal requirement.
 * <p>
 * <b>Version 2.1 additions:</b> Added five status and check functions:
 * {@link #API_Check_MainThread()}, {@link #API_Check_App(String)},
 * {@link #API_Get_Status_Num()}, {@link #API_Get_Status()},
 * {@link #API_Post_Status(String)}.
 */
public interface ApiHubNative extends Library {

    /**
     * Singleton instance – loads the appropriate shared library with UTF‑8 encoding.
     */
    ApiHubNative INSTANCE = Native.load(
        getLibraryName(),
        ApiHubNative.class,
        new HashMap<String, Object>() {{
            put(Library.OPTION_STRING_ENCODING, "UTF-8");
        }}
    );

    /**
     * Determine the correct library filename for the current platform.
     * @return library name (e.g., "z_api_hub64.dll", "libz_api_hub.so")
     */
    static String getLibraryName() {
        if (Platform.isWindows()) {
            return Platform.is64Bit() ? "z_api_hub64.dll" : "z_api_hub32.dll";
        } else if (Platform.isMac()) {
            return "libz_api_hub.dylib";
        } else { // Linux, BSD, and other ELF systems
            return "libz_api_hub.so";
        }
    }

    // -------------------- Data Handle Operations (9 functions) --------------------
    Pointer API_Create_DataHnd(String apiName);
    void API_Free_DataHnd(Pointer hnd);
    Pointer API_GetBuffer(Pointer hnd);
    long API_WriteBuffer(Pointer hnd, Pointer buff, long size);
    long API_ReadBuffer(Pointer hnd, Pointer buff, long size);
    long API_GetPos(Pointer hnd);
    void API_SetPos(Pointer hnd, long pos);
    long API_GetSize(Pointer hnd);
    void API_SetSize(Pointer hnd, long size);

    // -------------------- Application Handle Operations (7 functions) --------------------
    Pointer API_Create_APPHnd(String appName, String desc);
    void API_Free_APPHnd(Pointer appHnd);
    int API_Reg_Call(Pointer appHnd, String apiName, String desc,
                     Pointer trigger, CallCallback callback);
    int API_Reg_Notify(Pointer appHnd, String apiName, String desc,
                       Pointer trigger, NotifyCallback callback);
    int API_UnReg(Pointer appHnd, String apiName);
    Pointer API_Local_APP_Call(Pointer appHnd, Pointer param);
    void API_Local_APP_Notify(Pointer appHnd, Pointer param);

    // -------------------- Network Preparation & Remote Calls (9 functions) --------------------
    int API_Prepare_Service(String listeningAddr, String physicsAddr);
    int API_Prepare_Client(String physicsAddr, Pointer appHnd);
    void API_Reset_Prepare();
    int API_Prepare_Done();
    void API_Exit_MainThread();
    Pointer API_Call(String appName, Pointer param, long timeout);
    void API_Notify(String appName, Pointer param);
    void API_SetOption(String option, String value);
    void API_shutdown();

    // ========================================================================
    // v2.1 ADDITIONS – Status & Check API (5 functions)
    // ========================================================================

    /**
     * Checks whether the simulated main thread (C4 event loop) is currently running.
     * @return 1 if running, 0 if stopped or not yet started.
     */
    int API_Check_MainThread();

    /**
     * Checks whether an application with the given name is available on the network.
     * This query is based on a local cache and may be slightly stale.
     * @param appName application name (UTF‑8, case‑sensitive)
     * @return 1 if at least one instance exists, 0 otherwise.
     */
    int API_Check_App(String appName);

    /**
     * Returns the number of pending log messages in the internal status queue.
     * @return number of messages.
     */
    int API_Get_Status_Num();

    /**
     * Retrieves the next log message from the status queue (FIFO order).
     * The returned pointer points to a static internal buffer; the data is
     * valid until the next call to this function.
     * The message is UTF‑8 encoded and null‑terminated.
     * <p>
     * <b>Important:</b> The caller must NOT free the returned pointer.
     * Use {@link ApiHub#getStatus()} to safely copy the string into Java memory.
     *
     * @return pointer to the message string, or {@code null} if no message is available.
     */
    Pointer API_Get_Status();

    /**
     * Injects a custom log message into the internal status queue.
     * @param status the message to add (UTF‑8, null‑terminated).
     */
    void API_Post_Status(String status);
}