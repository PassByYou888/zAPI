package com.apihub;

import com.sun.jna.Pointer;

/**
 * Static entry point for network preparation, remote calls, notifications,
 * and runtime configuration.
 * <p>
 * <b>All methods in this class are fully thread‑safe</b> and can be called
 * concurrently from any thread without external synchronization.
 * <p>
 * <b>Typical lifecycle:</b>
 * <ol>
 *   <li>Create an {@link AppHandle} and register APIs.</li>
 *   <li>Optionally call {@link #setOption} to adjust runtime settings
 *       (e.g., authentication password, wait‑connection behavior).</li>
 *   <li>Call {@link #resetPrepare()} to clear any previous configuration.</li>
 *   <li>Call {@link #prepareService} and/or {@link #prepareClient} as needed.</li>
 *   <li>Call {@link #prepareDone()} to start the framework.</li>
 *   <li>Use {@link #call} or {@link #notify} to communicate.</li>
 *   <li>On shutdown: call {@link #exitMainThread()} then {@link #shutdown()}.</li>
 * </ol>
 * <p>
 * <b>Order of execution not guaranteed:</b> Due to load balancing, concurrent
 * calls may be processed out‑of‑order. If order matters, implement your own
 * sequencing logic.
 * <p>
 * <b>Performance:</b> For lightweight operations, the library sustains
 * ~3000 calls/second over IPC or local TCP. Use IPC for same‑machine
 * low‑latency communication.
 * <p>
 * <b>Error diagnosis:</b> The library prints detailed diagnostic messages
 * to the console by default (stdout/stderr). You can control logging
 * behavior via the {@code <executable>.api-tool.ini} configuration file,
 * which is auto‑generated on first run, or via {@link #setOption}.
 * <p>
 * <b>Runtime options:</b> Use {@link #setOption} to dynamically adjust
 * settings like authentication password, waiting behavior, and IPC parameters
 * without restarting the application.
 *
 * @see AppHandle
 * @see DataHandle
 * @see CallCallback
 * @see NotifyCallback
 */
public class ApiHub {

    /**
     * Clears all previously prepared services and clients.
     * Must be called before preparing a new set.
     */
    public static void resetPrepare() {
        ApiHubNative.INSTANCE.API_Reset_Prepare();
    }

    /**
     * Prepares a service (listener) that will be started when {@link #prepareDone}
     * is called.
     *
     * @param listening local address to bind (e.g., "0.0.0.0:9898" or "ipc:my_svc")
     * @param physics   public address advertised to clients (e.g., "127.0.0.1:9898")
     * @return an internal tag (informational, may be ignored)
     */
    public static int prepareService(String listening, String physics) {
        return ApiHubNative.INSTANCE.API_Prepare_Service(listening, physics);
    }

    /**
     * Prepares a client connection.
     *
     * @param physics address of the remote service (must match the service's
     *                {@code physics} address)
     * @param app     optional application handle to expose (may be {@code null}
     *                if this client only consumes services)
     * @return an internal tag
     */
    public static int prepareClient(String physics, AppHandle app) {
        Pointer appPtr = (app == null) ? null : app.getPointer();
        return ApiHubNative.INSTANCE.API_Prepare_Client(physics, appPtr);
    }

    /**
     * Starts the network framework. This call blocks until all prepared
     * services/clients are initialised. Afterwards, remote calls become possible.
     * <p>
     * The blocking behavior can be controlled via {@link #setOption} with the
     * key {@code "Wait_Connection_ReadyOk"} and {@code "Wait_Connection_Timeout"}.
     *
     * @return {@code true} on success; {@code false} on failure (check console output
     *         for error messages)
     */
    public static boolean prepareDone() {
        return ApiHubNative.INSTANCE.API_Prepare_Done() == 1;
    }

    /**
     * Signals the internal main loop to exit gracefully.
     * Must be followed by {@link #shutdown()} to release resources.
     */
    public static void exitMainThread() {
        ApiHubNative.INSTANCE.API_Exit_MainThread();
    }

    /**
     * Fully shuts down the framework: stops services, disconnects clients,
     * and releases internal resources. After this, you may re‑initialise.
     * <p>
     * It is recommended to call {@link #exitMainThread()} first, though
     * this method internally does that as well.
     */
    public static void shutdown() {
        ApiHubNative.INSTANCE.API_shutdown();
    }

    /**
     * Performs a synchronous remote (or local) call.
     * <p>
     * The method blocks until a response is received or the timeout expires.
     * The input handle is cloned internally; the caller still owns and must
     * free the original.
     *
     * @param appName   target application name (case‑sensitive)
     * @param param     input data handle (must contain the API name and payload)
     * @param timeoutMs maximum wait time in milliseconds (0 = infinite, use sparingly)
     * @return a new <b>owned</b> {@code DataHandle} containing the result.
     *         The handle is never {@code null}; if the call times out or fails,
     *         the handle size will be 0. <b>Must be freed</b> by the caller.
     */
    public static DataHandle call(String appName, DataHandle param, long timeoutMs) {
        Pointer result = ApiHubNative.INSTANCE.API_Call(appName, param.getPointer(), timeoutMs);
        return new DataHandle(result, true);
    }

    /**
     * Sends a one‑way notification. Returns immediately; delivery is best‑effort.
     *
     * @param appName target application name
     * @param param   input data handle (caller still owns and must free it)
     */
    public static void notify(String appName, DataHandle param) {
        ApiHubNative.INSTANCE.API_Notify(appName, param.getPointer());
    }

    /**
     * Dynamically adjusts global runtime options of the API Hub framework.
     * <p>
     * All changes take effect immediately for subsequent operations (except
     * where noted). This function is intended for runtime tuning without
     * restarting the application or modifying the .ini file. Unknown options
     * are silently ignored.
     * <p>
     * <b>Supported options (case‑insensitive, aliases accepted):</b>
     * <ul>
     *   <li><b>"password" / "passwd"</b> – Sets the C4 P2PVM authentication token.
     *       Must match on both service and client sides for successful handshake.
     *       Affects <i>new</i> connections only.</li>
     *   <li><b>"Quiet"</b> – Enable/disable quiet mode (True/False). Suppresses
     *       most debug logs.</li>
     *   <li><b>"External_Conf_Auto_Save" / "Conf_Auto_Save"</b> – Auto‑save
     *       configuration to .ini on exit (True/False). Default is True.</li>
     *   <li><b>"Wait_Connection_ReadyOk" / "Wait_API_Prepare_Done" / ...</b> –
     *       Controls whether {@link #prepareDone} blocks until all prepared clients
     *       have connected. When False, clients auto‑connect later (important for
     *       deployment scenarios).</li>
     *   <li><b>"Wait_Connection_Timeout" / "Wait_TimeOut"</b> – Max wait time (ms)
     *       when the above is True. Default 30000.</li>
     *   <li><b>"ShowThreadID" / "ShowThread" / "Show_Thread"</b> – Show thread IDs
     *       in log messages (True/False).</li>
     *   <li><b>"ConsoleOutput" / "Console_Output"</b> – Enable/disable console
     *       logging (True/False).</li>
     *   <li><b>"IPC_Serv_ThreadCount" / "IPC_ThreadCount" / "IPC_Server_ThreadCount"</b>
     *       – Number of threads in the IPC service thread pool.</li>
     *   <li><b>"IPC_Serv_MaxQueueLength" / "IPC_MaxQueueLength" / "IPC_Server_MaxQueueLength"</b>
     *       – Maximum IPC message queue length.</li>
     *   <li><b>"IPC_Serv_MaxMsgSize" / "IPC_MaxMsgSize" / "IPC_Server_MaxMsgSize"</b>
     *       – Maximum IPC message size (bytes).</li>
     * </ul>
     * <p>
     * For boolean options, accepted values: "True"/"False", "1"/"0", "Yes"/"No".
     *
     * @param option configuration key (UTF‑8)
     * @param value  new value (UTF‑8)
     *
     * @see #prepareDone
     *
     * @example
     * <pre>
     * // Set authentication password before starting
     * ApiHub.setOption("password", "my_secret_token");
     * // Allow clients to connect later (don't block Prepare_Done)
     * ApiHub.setOption("Wait_Connection_ReadyOk", "False");
     * // Enable quiet mode to reduce logs
     * ApiHub.setOption("Quiet", "True");
     * </pre>
     */
    public static void setOption(String option, String value) {
        ApiHubNative.INSTANCE.API_SetOption(option, value);
    }
}