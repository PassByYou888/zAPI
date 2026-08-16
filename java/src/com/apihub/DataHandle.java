package com.apihub;

import com.sun.jna.Memory;
import com.sun.jna.Pointer;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;

/**
 * RAII wrapper for a {@code TDataHnd} (data handle) that automatically
 * releases the native resource when closed.
 * <p>
 * A data handle contains an <b>API name</b> (set at creation) and a
 * <b>binary payload</b>. All read/write operations affect only the payload.
 * The API name is immutable after creation.
 * <p>
 * <b>Ownership:</b> There are two kinds of instances:
 * <ul>
 *   <li><b>Owned</b> – created via {@link #DataHandle(String)}. The wrapper
 *       owns the underlying pointer and will call {@link ApiHubNative#API_Free_DataHnd}
 *       when closed.</li>
 *   <li><b>Borrowed</b> – obtained via {@link #wrapInput(Pointer)} or
 *       {@link #wrapOutput(Pointer)} for pointers passed into callbacks.
 *       These wrappers <b>do not own</b> the pointer and {@link #close()}
 *       will <b>not</b> free it.</li>
 * </ul>
 * <p>
 * <b>Thread safety:</b> The underlying library is fully thread‑safe for all
 * operations. However, for a given {@code DataHandle}, write operations
 * ({@link #write}, {@link #setPos}, {@link #setSize}) must be serialised
 * across threads. Read operations can be concurrent with other reads.
 * <p>
 * <b>Zero‑copy access:</b> Use {@link #getBuffer()} to obtain a direct
 * pointer to the internal buffer – useful for performance but be careful
 * not to write beyond the size returned by {@link #getSize()}.
 * <p>
 * The helper methods ({@link #writeInt}, {@link #readString}, etc.) use
 * <b>little‑endian</b> byte order and UTF‑8 for strings, with a length
 * prefix (4 bytes) for strings. This is a convenience; you may use any
 * binary format you like.
 */
public class DataHandle implements AutoCloseable {

    private final Pointer ptr;
    private final boolean owned;   // true if we own the pointer and must free it
    private boolean closed = false;

    /**
     * Creates a new owned data handle with the given API name.
     * The payload is initially empty (size = 0).
     *
     * @param apiName target API name (case‑sensitive, used for routing)
     * @throws RuntimeException if the underlying library call fails
     */
    public DataHandle(String apiName) {
        this.ptr = ApiHubNative.INSTANCE.API_Create_DataHnd(apiName);
        if (this.ptr == null) {
            throw new RuntimeException("API_Create_DataHnd returned null");
        }
        this.owned = true;
    }

    /**
     * Internal constructor for wrapping a borrowed pointer.
     * The {@code owned} flag determines whether {@link #close()} will free it.
     *
     * @param ptr   native pointer (may be borrowed)
     * @param owned {@code true} if this wrapper should free the pointer
     */
    DataHandle(Pointer ptr, boolean owned) {
        this.ptr = ptr;
        this.owned = owned;
    }

    /**
     * Wraps an {@code input} pointer from a callback as a read‑only handle.
     * The wrapper does <b>not</b> own the pointer; calling {@code close()}
     * has no effect (other than marking the wrapper closed).
     *
     * @param ptr native pointer to the input data
     * @return a new {@code DataHandle} that must not be freed
     */
    public static DataHandle wrapInput(Pointer ptr) {
        return new DataHandle(ptr, false);
    }

    /**
     * Wraps an {@code output} pointer from a callback as a write‑only handle.
     * The wrapper does <b>not</b> own the pointer; calling {@code close()}
     * has no effect.
     *
     * @param ptr native pointer to the output buffer
     * @return a new {@code DataHandle} that must not be freed
     */
    public static DataHandle wrapOutput(Pointer ptr) {
        return new DataHandle(ptr, false);
    }

    /**
     * Returns the underlying native pointer.
     * @return the JNA {@code Pointer} (never {@code null})
     */
    public Pointer getPointer() {
        return ptr;
    }

    // ---------- Basic I/O ----------

    /**
     * Writes raw bytes at the current position. The buffer is automatically
     * enlarged if needed. The position advances by {@code data.length}.
     *
     * @param data bytes to write
     * @return number of bytes actually written (usually equals {@code data.length})
     * @throws IllegalStateException if the handle is already closed
     * @see ApiHubNative#API_WriteBuffer
     */
    public long write(byte[] data) {
        checkNotClosed();
        try (Memory mem = new Memory(data.length)) {
            mem.write(0, data, 0, data.length);
            return ApiHubNative.INSTANCE.API_WriteBuffer(ptr, mem, data.length);
        }
    }

    /**
     * Reads up to {@code length} bytes from the current position.
     * The position advances by the number of bytes read.
     *
     * @param length maximum number of bytes to read
     * @return a byte array containing the actually read data (may be shorter)
     * @throws IllegalStateException if the handle is closed
     * @see ApiHubNative#API_ReadBuffer
     */
    public byte[] read(int length) {
        checkNotClosed();
        try (Memory mem = new Memory(length)) {
            long read = ApiHubNative.INSTANCE.API_ReadBuffer(ptr, mem, length);
            return mem.getByteArray(0, (int) read);
        }
    }

    // ---------- Convenience methods for primitive types (little‑endian) ----------

    /**
     * Writes an {@code int} in little‑endian order.
     */
    public long writeInt(int v) {
        byte[] b = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(v).array();
        return write(b);
    }

    /**
     * Reads an {@code int} in little‑endian order.
     */
    public int readInt() {
        byte[] b = read(4);
        return ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN).getInt();
    }

    /**
     * Writes a {@code double} in little‑endian order.
     */
    public long writeDouble(double v) {
        byte[] b = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putDouble(v).array();
        return write(b);
    }

    /**
     * Reads a {@code double} in little‑endian order.
     */
    public double readDouble() {
        byte[] b = read(8);
        return ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN).getDouble();
    }

    // ---------- String helpers (UTF‑8, length‑prefixed) ----------

    /**
     * Writes a UTF‑8 string with a 4‑byte length prefix (int, little‑endian).
     */
    public long writeString(String s) {
        byte[] bytes = s.getBytes(StandardCharsets.UTF_8);
        long len = writeInt(bytes.length);
        len += write(bytes);
        return len;
    }

    /**
     * Reads a UTF‑8 string that was written with a 4‑byte length prefix.
     */
    public String readString() {
        int len = readInt();
        byte[] data = read(len);
        return new String(data, StandardCharsets.UTF_8);
    }

    // ---------- Position and size ----------

    public long getPos() {
        checkNotClosed();
        return ApiHubNative.INSTANCE.API_GetPos(ptr);
    }

    public void setPos(long pos) {
        checkNotClosed();
        ApiHubNative.INSTANCE.API_SetPos(ptr, pos);
    }

    public long getSize() {
        checkNotClosed();
        return ApiHubNative.INSTANCE.API_GetSize(ptr);
    }

    public void setSize(long size) {
        checkNotClosed();
        ApiHubNative.INSTANCE.API_SetSize(ptr, size);
    }

    // ---------- Zero‑copy access ----------

    /**
     * Returns a direct pointer to the internal buffer.
     * This pointer is valid until the handle is freed or the buffer is resized.
     * <b>Do not free this pointer</b> – it is owned by the handle.
     * <p>
     * You may read and write through this pointer, but you <b>must not</b>
     * exceed the size returned by {@link #getSize()}.
     */
    public Pointer getBuffer() {
        checkNotClosed();
        return ApiHubNative.INSTANCE.API_GetBuffer(ptr);
    }

    // ---------- Resource management ----------

    /**
     * Closes the handle and frees the native memory <b>only if</b> this
     * wrapper owns the pointer. Borrowed wrappers (from callbacks) do nothing.
     * <p>
     * It is safe to call this method multiple times; subsequent calls have
     * no effect.
     */
    @Override
    public void close() {
        if (!closed && owned && ptr != null) {
            ApiHubNative.INSTANCE.API_Free_DataHnd(ptr);
            closed = true;
        } else {
            closed = true; // mark as closed even for borrowed
        }
    }

    private void checkNotClosed() {
        if (closed) {
            throw new IllegalStateException("DataHandle is already closed");
        }
    }
}