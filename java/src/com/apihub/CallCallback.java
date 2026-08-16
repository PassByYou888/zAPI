package com.apihub;

import com.sun.jna.Callback;
import com.sun.jna.Pointer;

/**
 * Callback interface for request‑response (Call) APIs.
 * <p>
 * Must be declared with the {@code cdecl} calling convention (JNA does this
 * automatically when extending {@code Callback}).
 * <p>
 * <b>CRITICAL CONTEXT:</b> This callback is invoked on a background thread
 * from the library's internal thread pool. Therefore:
 * <ul>
 *   <li><b>DO NOT</b> perform long‑blocking operations.</li>
 *   <li><b>DO NOT</b> call {@link ApiHub#call} or {@link ApiHub#notify}
 *       from inside this callback – this may cause deadlocks.</li>
 *   <li><b>DO NOT</b> access UI components without proper synchronisation.</li>
 *   <li><b>DO</b> offload heavy processing or remote calls to a separate
 *       worker queue and return quickly.</li>
 * </ul>
 * <p>
 * The {@code input} and {@code output} pointers are <b>borrowed</b> from
 * the library – they must NOT be freed by the caller. Use
 * {@link DataHandle#wrapInput(Pointer)} and
 * {@link DataHandle#wrapOutput(Pointer)} for safe read/write access.
 * <p>
 * Exceptions thrown inside the callback are caught and logged by the
 * library but are <b>not</b> propagated back to the caller. Handle errors
 * explicitly within the callback if you need to signal failure.
 *
 * @see NotifyCallback
 */
public interface CallCallback extends Callback {
    void invoke(Pointer trigger, Pointer input, Pointer output);
}