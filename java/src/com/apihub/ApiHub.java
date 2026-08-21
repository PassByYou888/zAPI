package com.apihub;

import com.sun.jna.Pointer;

/**
 * Static entry point for network preparation, remote calls, notifications,
 * and runtime configuration.
 */
public class ApiHub {

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

    public static DataHandle call(String appName, DataHandle param, long timeoutMs) {
        Pointer result = ApiHubNative.INSTANCE.API_Call(appName, param.getPointer(), timeoutMs);
        return new DataHandle(result, true);
    }

    public static void notify(String appName, DataHandle param) {
        ApiHubNative.INSTANCE.API_Notify(appName, param.getPointer());
    }

    public static void setOption(String option, String value) {
        ApiHubNative.INSTANCE.API_SetOption(option, value);
    }
}