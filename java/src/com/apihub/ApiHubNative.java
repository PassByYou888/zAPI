package com.apihub;

import com.sun.jna.Library;
import com.sun.jna.Native;
import com.sun.jna.Platform;
import com.sun.jna.Pointer;

/**
 * JNA direct mapping to the C API exported by the API Hub dynamic library.
 * <p>
 * This interface is a 1:1 translation of the Pascal import unit
 * {@code z_api_hubtool_import.pas}. All functions follow the same calling
 * conventions (cdecl), parameter order, and semantics.
 * <p>
 * <b>Library loading:</b> The correct library name is chosen automatically
 * based on the operating system and architecture, matching the Pascal
 * conditional logic.
 * <p>
 * <b>String encoding:</b> All {@code String} parameters are passed as
 * null‑terminated UTF‑8 bytes (JNA does this automatically when using
 * {@code String} with the default mapping).
 * <p>
 * <b>Thread safety:</b> All native functions are fully thread‑safe.
 * <p>
 * <b>Callback context:</b> Callbacks ({@link CallCallback}, {@link NotifyCallback})
 * execute in background threads. Do NOT block or call {@code API_Call}/
 * {@code API_Notify} from within callbacks.
 *
 * @see ApiHub for high‑level wrappers and usage examples.
 */
public interface ApiHubNative extends Library {

    /**
     * Singleton instance – loads the appropriate shared library.
     * <p>
     * The library name is selected exactly as in the Pascal unit:
     * <ul>
     *   <li>Windows 64‑bit: {@code z_api_hub64.dll}</li>
     *   <li>Windows 32‑bit: {@code z_api_hub32.dll}</li>
     *   <li>Linux/BSD: {@code libz_api_hub.so}</li>
     *   <li>macOS: {@code libz_api_hub.dylib}</li>
     * </ul>
     * <p>
     * The library is loaded when this class is first accessed. Ensure the
     * library file is in the system library path or alongside the executable.
     */
    ApiHubNative INSTANCE = Native.load(getLibraryName(), ApiHubNative.class);

    /**
     * Determine the correct library filename for the current platform.
     * @return library name (e.g., "z_api_hub64.dll", "libz_api_hub.so")
     */
    static String getLibraryName() {
        if (Platform.isWindows()) {
            return Platform.is64Bit() ? "z_api_hub64.dll" : "z_api_hub32.dll";
        } else if (Platform.isMac()) {
            return "z_api_hub.dylib";
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

    /**
     * Unregisters a previously registered API from the application.
     * <p>
     * This function removes the API from the local registry immediately and
     * triggers a network update broadcast. The change is propagated to all
     * connected C4 services and clients within approximately 3 seconds
     * (depending on network latency and the C4 update interval). Once
     * propagated, the API will no longer be discoverable or callable by
     * remote peers.
     *
     * @param appHnd   application handle
     * @param apiName  name of the API to unregister (UTF‑8)
     * @return 1 on success, 0 if the API name does not exist
     *
     * @see #API_Reg_Call
     * @see #API_Reg_Notify
     */
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

    /**
     * Dynamically adjusts global runtime options of the API Hub framework.
     * <p>
     * All changes take effect immediately for subsequent operations (except
     * where noted). This function is intended for runtime tuning without
     * restarting the application or modifying the .ini file.
     *
     * @param option  configuration key (UTF‑8, case‑insensitive). Supported keys:
     *                <ul>
     *                  <li>"password" / "passwd" : Sets C4 P2PVM authentication token.
     *                      Must match on both service and client sides.</li>
     *                  <li>"Quiet" : Enable/disable quiet mode (True/False).</li>
     *                  <li>"External_Conf_Auto_Save" / "Conf_Auto_Save" :
     *                      Auto‑save .ini on exit (True/False).</li>
     *                  <li>"Wait_Connection_ReadyOk" / "Wait_API_Prepare_Done" / ... :
     *                      Controls whether {@link #API_Prepare_Done} blocks until
     *                      all clients are connected. When False, clients auto‑connect
     *                      later (important for deployment).</li>
     *                  <li>"Wait_Connection_Timeout" / "Wait_TimeOut" :
     *                      Max wait (ms) when the above is True.</li>
     *                  <li>"ShowThreadID" / "ShowThread" / "Show_Thread" :
     *                      Show thread IDs in logs (True/False).</li>
     *                  <li>"ConsoleOutput" / "Console_Output" :
     *                      Enable/disable console logging (True/False).</li>
     *                  <li>"IPC_Serv_ThreadCount" / "IPC_ThreadCount" / "IPC_Server_ThreadCount" :
     *                      Number of threads in the IPC service thread pool.</li>
     *                  <li>"IPC_Serv_MaxQueueLength" / "IPC_MaxQueueLength" / "IPC_Server_MaxQueueLength" :
     *                      Maximum length of the IPC message queue.</li>
     *                  <li>"IPC_Serv_MaxMsgSize" / "IPC_MaxMsgSize" / "IPC_Server_MaxMsgSize" :
     *                      Maximum size (in bytes) of a single IPC message.</li>
     *                </ul>
     * @param value   new value (UTF‑8). For boolean options, accepted values are
     *                "True"/"False", "1"/"0", "Yes"/"No".
     * @note This function has no return value; unknown options are silently ignored.
     */
    void API_SetOption(String option, String value);

    void API_shutdown();
}