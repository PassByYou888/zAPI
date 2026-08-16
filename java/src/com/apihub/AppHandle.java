package com.apihub;

import com.sun.jna.Pointer;

/**
 * RAII wrapper for an application handle ({@code TAppHnd}).
 * <p>
 * An application is a container for a set of APIs. It has a unique name
 * that is used for network routing. The handle is created with
 * {@link #AppHandle(String, String)} and must be closed via {@link #close()}
 * (or try‑with‑resources) to release native resources.
 * <p>
 * <b>Thread safety:</b> The underlying library functions are thread‑safe,
 * but you must not close the handle while other threads are using it.
 * <p>
 * When a client connection is prepared with this app handle, all registered
 * APIs are automatically advertised to the network.
 * <p>
 * <b>Dynamic unregistration:</b> Use {@link #unregister(String)} to remove
 * a previously registered API. The API is immediately removed from the local
 * registry and a network broadcast is triggered. Remote peers will stop
 * seeing this API within approximately 3 seconds (depending on network
 * conditions). During that short window, remote calls may still be attempted;
 * they will fail gracefully.
 */
public class AppHandle implements AutoCloseable {

    private final Pointer ptr;
    private boolean closed = false;

    /**
     * Creates a new application context.
     *
     * @param appName unique, case‑sensitive application name
     * @param desc    optional human‑readable description
     * @throws RuntimeException if the native call fails
     */
    public AppHandle(String appName, String desc) {
        this.ptr = ApiHubNative.INSTANCE.API_Create_APPHnd(appName, desc);
        if (this.ptr == null) {
            throw new RuntimeException("API_Create_APPHnd returned null");
        }
    }

    /**
     * Returns the native pointer.
     */
    public Pointer getPointer() {
        return ptr;
    }

    /**
     * Registers a request‑response API.
     *
     * @param apiName  unique API name inside this application
     * @param desc     optional description
     * @param callback the implementation (must be kept alive by the caller)
     * @return {@code true} if successful, {@code false} if the name already exists
     * @see CallCallback for threading and safety restrictions
     */
    public boolean registerCall(String apiName, String desc, CallCallback callback) {
        checkNotClosed();
        return ApiHubNative.INSTANCE.API_Reg_Call(ptr, apiName, desc, null, callback) == 1;
    }

    /**
     * Registers a one‑way notification API.
     *
     * @param apiName  unique API name
     * @param desc     optional description
     * @param callback the implementation (must be kept alive)
     * @return {@code true} if successful, {@code false} if the name already exists
     * @see NotifyCallback
     */
    public boolean registerNotify(String apiName, String desc, NotifyCallback callback) {
        checkNotClosed();
        return ApiHubNative.INSTANCE.API_Reg_Notify(ptr, apiName, desc, null, callback) == 1;
    }

    /**
     * Unregisters a previously registered API from this application.
     * <p>
     * The API is <b>immediately</b> removed from the local registry and a
     * network broadcast is triggered. Remote peers will stop seeing this API
     * within approximately 3 seconds (depending on network latency and the
     * C4 update interval). During that short window, remote calls may still
     * be attempted; they will fail gracefully (the remote side will receive
     * a "not found" error).
     * <p>
     * Use this function to dynamically unload plugins, temporarily disable
     * services, or adjust exposed functionality at runtime without restarting
     * the application.
     *
     * @param apiName the name of the API to unregister (UTF‑8)
     * @return {@code true} if the API was found and unregistered,
     *         {@code false} if the API name does not exist
     * @throws IllegalStateException if the handle is closed
     * @see #registerCall
     * @see #registerNotify
     */
    public boolean unregister(String apiName) {
        checkNotClosed();
        return ApiHubNative.INSTANCE.API_UnReg(ptr, apiName) == 1;
    }

    /**
     * Synchronously calls a registered API <b>locally</b> (bypassing the network).
     * Useful for testing or internal use.
     *
     * @param param input data handle (owned by the caller; will not be freed)
     * @return a new <b>owned</b> {@code DataHandle} containing the result,
     *         or a handle with size 0 if the API was not found.
     * @throws IllegalStateException if the handle is closed
     */
    public DataHandle localCall(DataHandle param) {
        checkNotClosed();
        Pointer resultPtr = ApiHubNative.INSTANCE.API_Local_APP_Call(ptr, param.getPointer());
        return new DataHandle(resultPtr, true);
    }

    /**
     * Sends a notification locally (no response).
     *
     * @param param input data handle (owned by the caller)
     */
    public void localNotify(DataHandle param) {
        checkNotClosed();
        ApiHubNative.INSTANCE.API_Local_APP_Notify(ptr, param.getPointer());
    }

    /**
     * Releases the native resources. After this call, the handle must not be used.
     */
    @Override
    public void close() {
        if (!closed && ptr != null) {
            ApiHubNative.INSTANCE.API_Free_APPHnd(ptr);
            closed = true;
        }
    }

    private void checkNotClosed() {
        if (closed) {
            throw new IllegalStateException("AppHandle is already closed");
        }
    }
}