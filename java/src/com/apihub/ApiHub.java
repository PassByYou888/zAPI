package com.apihub;

import com.sun.jna.Pointer;

/**
 * Static entry point for network preparation, remote calls, notifications,
 * runtime configuration, and the new v2.1 status/check APIs.
 * <p>
 * All methods are thread‑safe unless otherwise noted.
 *
 * @see ApiHubNative
 * @see DataHandle
 * @see AppHandle
 */
public class ApiHub {

    // ---------- Network Preparation ----------

    public static void resetPrepare() {
        ApiHubNative.INSTANCE.API_Reset_Prepare();
    }

    public static int prepareService(String listening, String physics) {
        return ApiHubNative.INSTANCE.API_Prepare_Service(listening, physics);
    }

    public static int prepareClient(String physics, AppHandle app) {
        Pointer appPtr = (app == null) ? null : app.getPointer();
        return ApiHubNative.INSTANCE.API_Prepare_Client(physics, appPtr);
    }

    public static boolean prepareDone() {
        return ApiHubNative.INSTANCE.API_Prepare_Done() == 1;
    }

    public static void exitMainThread() {
        ApiHubNative.INSTANCE.API_Exit_MainThread();
    }

    public static void shutdown() {
        ApiHubNative.INSTANCE.API_shutdown();
    }

    // ---------- Remote Calls & Notifications ----------

    public static DataHandle call(String appName, DataHandle param, long timeoutMs) {
        Pointer result = ApiHubNative.INSTANCE.API_Call(appName, param.getPointer(), timeoutMs);
        return new DataHandle(result, true);
    }

    public static void notify(String appName, DataHandle param) {
        ApiHubNative.INSTANCE.API_Notify(appName, param.getPointer());
    }

    // ---------- Runtime Configuration ----------

    public static void setOption(String option, String value) {
        ApiHubNative.INSTANCE.API_SetOption(option, value);
    }

    // ========================================================================
    // v2.1 ADDITIONS – Status & Check API (5 methods)
    // ========================================================================

    /**
     * Checks whether the simulated main thread (C4 event loop) is currently running.
     * <p>
     * <b>Return value:</b> 1 if running, 0 if stopped or not yet started.
     * <p>
     * <b>Thread safety:</b> Fully thread‑safe.
     *
     * @see ApiHubNative#API_Check_MainThread()
     */
    public static int checkMainThread() {
        return ApiHubNative.INSTANCE.API_Check_MainThread();
    }

    /**
     * Checks whether an application with the given name is available on the network.
     * This query is based on a local cache and may be slightly stale (updated
     * periodically via the C4 service mesh broadcast).
     * <p>
     * <b>Use cases:</b> Probe target availability before making a call to avoid
     * unnecessary timeouts. However, note that the actual state may change by
     * the time your call is sent; use this as a hint, not a guarantee.
     * <p>
     * <b>Thread safety:</b> Fully thread‑safe.
     *
     * @param appName application name (UTF‑8, case‑sensitive)
     * @return 1 if at least one instance exists, 0 otherwise.
     * @throws IllegalArgumentException if {@code appName} is null or empty.
     * @see ApiHubNative#API_Check_App(String)
     */
    public static int checkApp(String appName) {
        if (appName == null || appName.isEmpty()) {
            throw new IllegalArgumentException("appName must not be null or empty");
        }
        return ApiHubNative.INSTANCE.API_Check_App(appName);
    }

    /**
     * Returns the number of pending log messages in the internal status queue.
     * <p>
     * The queue is a FIFO buffer that stores the last 1000 messages (older
     * ones are discarded when the queue overflows). Each message is a UTF‑8
     * string emitted by the library (connection status, registration results,
     * errors, etc.).
     * <p>
     * <b>Thread safety:</b> Fully thread‑safe.
     *
     * @return number of messages currently queued.
     * @see ApiHubNative#API_Get_Status_Num()
     */
    public static int getStatusNum() {
        return ApiHubNative.INSTANCE.API_Get_Status_Num();
    }

    /**
     * Retrieves the next log message from the status queue (FIFO order).
     * <p>
     * The returned string is a fresh copy of the internal UTF‑8 data, so it
     * remains valid even after subsequent calls to {@code getStatus()}.
     * If the queue is empty, an empty string is returned.
     * <p>
     * <b>Thread safety:</b> Fully thread‑safe. However, note that while one
     * thread is calling this method, another thread may be appending messages
     * concurrently; this is safe but the ordering of returned messages may be
     * interleaved.
     * <p>
     * <b>Usage example:</b>
     * <pre>{@code
     * while (ApiHub.getStatusNum() > 0) {
     *     String msg = ApiHub.getStatus();
     *     System.out.println("[Library] " + msg);
     * }
     * }</pre>
     *
     * @return the next message string, or an empty string if the queue is empty.
     * @see ApiHubNative#API_Get_Status()
     * @see #getStatusNum()
     */
    public static String getStatus() {
        Pointer ptr = ApiHubNative.INSTANCE.API_Get_Status();
        if (ptr == null) {
            return "";
        }
        // JNA automatically respects the OPTION_STRING_ENCODING set to UTF-8.
        // getString(0) reads until the first null byte.
        return ptr.getString(0);
    }

    /**
     * Injects a custom log message into the internal status queue.
     * <p>
     * This allows you to unify your application logs with the library's own
     * log stream, so they can be consumed via {@link #getStatus()} and
     * monitored together.
     * <p>
     * The message is added at the tail of the FIFO queue; if the queue is full,
     * the oldest message is discarded.
     * <p>
     * <b>Thread safety:</b> Fully thread‑safe.
     *
     * @param status the message to inject (UTF‑8). Must not be null.
     * @throws IllegalArgumentException if {@code status} is null.
     * @see ApiHubNative#API_Post_Status(String)
     */
    public static void postStatus(String status) {
        if (status == null) {
            throw new IllegalArgumentException("status must not be null");
        }
        ApiHubNative.INSTANCE.API_Post_Status(status);
    }
}