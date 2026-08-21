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

    // -------------------- Data Handle Operations --------------------
    Pointer API_Create_DataHnd(String apiName);

    void API_Free_DataHnd(Pointer hnd);

    Pointer API_GetBuffer(Pointer hnd);

    long API_WriteBuffer(Pointer hnd, Pointer buff, long size);

    long API_ReadBuffer(Pointer hnd, Pointer buff, long size);

    long API_GetPos(Pointer hnd);

    void API_SetPos(Pointer hnd, long pos);

    long API_GetSize(Pointer hnd);

    void API_SetSize(Pointer hnd, long size);

    // -------------------- Application Handle Operations --------------------
    Pointer API_Create_APPHnd(String appName, String desc);

    void API_Free_APPHnd(Pointer appHnd);

    int API_Reg_Call(Pointer appHnd, String apiName, String desc,
                     Pointer trigger, CallCallback callback);

    int API_Reg_Notify(Pointer appHnd, String apiName, String desc,
                       Pointer trigger, NotifyCallback callback);

    int API_UnReg(Pointer appHnd, String apiName);

    Pointer API_Local_APP_Call(Pointer appHnd, Pointer param);

    void API_Local_APP_Notify(Pointer appHnd, Pointer param);

    // -------------------- Network Preparation & Control --------------------
    int API_Prepare_Service(String listeningAddr, String physicsAddr);

    int API_Prepare_Client(String physicsAddr, Pointer appHnd);

    void API_Reset_Prepare();

    int API_Prepare_Done();

    void API_Exit_MainThread();

    Pointer API_Call(String appName, Pointer param, long timeout);

    void API_Notify(String appName, Pointer param);

    void API_SetOption(String option, String value);

    void API_shutdown();
}