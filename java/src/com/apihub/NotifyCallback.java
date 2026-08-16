package com.apihub;

import com.sun.jna.Callback;
import com.sun.jna.Pointer;

/**
 * Callback interface for one‑way notification (Notify) APIs.
 * <p>
 * Same threading and safety restrictions as {@link CallCallback}.
 * No output is produced.
 */
public interface NotifyCallback extends Callback {
    void invoke(Pointer trigger, Pointer input);
}