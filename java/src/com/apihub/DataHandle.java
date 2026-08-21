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
 * <b>Cross‑language compatibility note (2026-08-21 hardening):</b>
 * <ul>
 *   <li>For strings, use {@link #writeStringNullTerminated(String)} and
 *       {@link #readStringNullTerminated()} to match the Pascal
 *       {@code API_WriteString} / {@code API_ReadString} contract (UTF‑8 + NUL).</li>
 *   <li>The legacy {@link #writeString(String)} and {@link #readString()}
 *       methods use a 4‑byte length prefix and are <b>NOT</b> compatible with
 *       other language bindings. They are retained for internal Java‑only
 *       protocols but marked deprecated.</li>
 *   <li>All atomic writes now roll back the cursor on partial failure,
 *       preventing stream corruption (defensive fix for W-01).</li>
 *   <li>All reads from native memory include explicit {@code null} checks
 *       and length caps (defensive fixes for F-01 and W-02).</li>
 * </ul>
 *
 * @see ApiHubNative
 * @see ApiHub
 */
public class DataHandle implements AutoCloseable {

    // ========== Security & Stability Constants (Added 2026-08-21) ==========
    private static final long MAX_STRING_SCAN = 64 * 1024 * 1024; // 64 MB
    private static final int MAX_STRING_LENGTH = 64 * 1024 * 1024; // 64 MB

    private final Pointer ptr;
    private final boolean owned;
    private boolean closed = false;

    public DataHandle(String apiName) {
        this.ptr = ApiHubNative.INSTANCE.API_Create_DataHnd(apiName);
        if (this.ptr == null) {
            throw new RuntimeException("API_Create_DataHnd returned null");
        }
        this.owned = true;
    }

    DataHandle(Pointer ptr, boolean owned) {
        this.ptr = ptr;
        this.owned = owned;
    }

    public static DataHandle wrapInput(Pointer ptr) {
        return new DataHandle(ptr, false);
    }

    public static DataHandle wrapOutput(Pointer ptr) {
        return new DataHandle(ptr, false);
    }

    public Pointer getPointer() {
        return ptr;
    }

    // ---------- Basic I/O ----------

    public long write(byte[] data) {
        checkNotClosed();
        if (data == null || data.length == 0) return 0;
        try (Memory mem = new Memory(data.length)) {
            mem.write(0, data, 0, data.length);
            return ApiHubNative.INSTANCE.API_WriteBuffer(ptr, mem, data.length);
        }
    }

    public byte[] read(int length) {
        checkNotClosed();
        if (length <= 0) return new byte[0];
        // Defensive: cap length to prevent malicious OOM (though C layer also limits)
        int safeLen = Math.min(length, MAX_STRING_LENGTH);
        try (Memory mem = new Memory(safeLen)) {
            long read = ApiHubNative.INSTANCE.API_ReadBuffer(ptr, mem, safeLen);
            if (read <= 0) return new byte[0];
            return mem.getByteArray(0, (int) read);
        }
    }

    // ---------- Convenience methods for primitive types (little‑endian) ----------

    public long writeInt(int v) {
        byte[] b = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(v).array();
        return write(b);
    }

    public int readInt() {
        byte[] b = read(4);
        if (b.length < 4) return 0;
        return ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN).getInt();
    }

    public long writeDouble(double v) {
        byte[] b = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putDouble(v).array();
        return write(b);
    }

    public double readDouble() {
        byte[] b = read(8);
        if (b.length < 8) return 0.0;
        return ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN).getDouble();
    }

    // ---------- DEPRECATED: Length‑prefixed strings (Java‑only, NOT cross‑language) ----------

    /**
     * @deprecated This method uses a 4‑byte length prefix (Little‑Endian), which is
     *             <b>INCOMPATIBLE</b> with the Pascal {@code API_WriteString} contract
     *             (which uses NUL termination). For cross‑language communication,
     *             use {@link #writeStringNullTerminated(String)} instead.
     *             Retained only for legacy Java‑internal protocols.
     */
    @Deprecated
    public long writeString(String s) {
        checkNotClosed();
        if (s == null) s = ""; // defensive null guard
        byte[] bytes = s.getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_STRING_LENGTH) {
            // Truncate silently to prevent OOM, as this is a deprecated path
            byte[] truncated = new byte[MAX_STRING_LENGTH];
            System.arraycopy(bytes, 0, truncated, 0, MAX_STRING_LENGTH);
            bytes = truncated;
        }
        long len = writeInt(bytes.length);
        len += write(bytes);
        return len;
    }

    /**
     * @deprecated This method reads a 4‑byte length prefix (Little‑Endian), which is
     *             <b>INCOMPATIBLE</b> with the Pascal {@code API_ReadString} contract
     *             (which reads until NUL). For cross‑language communication,
     *             use {@link #readStringNullTerminated()} instead.
     */
    @Deprecated
    public String readString() {
        checkNotClosed();
        int len = readInt();
        // Defensive: reject maliciously huge or negative lengths
        if (len <= 0 || len > MAX_STRING_LENGTH) {
            return "";
        }
        byte[] data = read(len);
        if (data.length < len) {
            // Underflow: not enough bytes in buffer, return what we got or empty
            return new String(data, StandardCharsets.UTF_8);
        }
        return new String(data, StandardCharsets.UTF_8);
    }

    // ========================================================================
    // RECOMMENDED CROSS‑LANGUAGE ATOMIC API (Pascal‑compatible)
    // ========================================================================

    // ---------- Write helpers (all return true if full bytes written) ----------

    public boolean writeInt8(byte value) {
        long before = getPos();
        long written = write(new byte[]{value});
        if (written != 1) { setPos(before); return false; }
        return true;
    }

    public boolean writeUInt8(int value) {
        long before = getPos();
        long written = write(new byte[]{(byte)(value & 0xFF)});
        if (written != 1) { setPos(before); return false; }
        return true;
    }

    public boolean writeInt16(short value) {
        long before = getPos();
        byte[] b = ByteBuffer.allocate(2).order(ByteOrder.LITTLE_ENDIAN).putShort(value).array();
        long written = write(b);
        if (written != 2) { setPos(before); return false; }
        return true;
    }

    public boolean writeUInt16(int value) {
        long before = getPos();
        byte[] b = ByteBuffer.allocate(2).order(ByteOrder.LITTLE_ENDIAN).putShort((short)(value & 0xFFFF)).array();
        long written = write(b);
        if (written != 2) { setPos(before); return false; }
        return true;
    }

    public boolean writeInt32(int value) {
        long before = getPos();
        long written = writeInt(value);
        if (written != 4) { setPos(before); return false; }
        return true;
    }

    public boolean writeUInt32(long value) {
        long before = getPos();
        byte[] b = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt((int)(value & 0xFFFFFFFFL)).array();
        long written = write(b);
        if (written != 4) { setPos(before); return false; }
        return true;
    }

    public boolean writeInt64(long value) {
        long before = getPos();
        byte[] b = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putLong(value).array();
        long written = write(b);
        if (written != 8) { setPos(before); return false; }
        return true;
    }

    public boolean writeUInt64(long value) {
        return writeInt64(value); // same binary layout
    }

    public boolean writeSingle(float value) {
        long before = getPos();
        byte[] b = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putFloat(value).array();
        long written = write(b);
        if (written != 4) { setPos(before); return false; }
        return true;
    }

    public boolean writeDouble2(double value) {
        long before = getPos();
        long written = writeDouble(value);
        if (written != 8) { setPos(before); return false; }
        return true;
    }

    /**
     * Writes a UTF‑8 encoded Pascal string, followed by a null terminator (#0).
     * This matches the standard "UTF‑8 + #0" format used across all language
     * bindings (Pascal {@code API_WriteString} contract).
     * The position is advanced by Length(UTF8String(Value)) + 1 bytes.
     *
     * @param value the string to write
     * @return true if the string (including the trailing null) was fully written
     */
    public boolean writeStringNullTerminated(String value) {
        checkNotClosed();
        if (value == null) value = "";
        byte[] utf8 = value.getBytes(StandardCharsets.UTF_8);
        if (utf8.length > MAX_STRING_LENGTH) {
            // Truncate to safe limit instead of crashing or silently corrupting
            byte[] truncated = new byte[MAX_STRING_LENGTH];
            System.arraycopy(utf8, 0, truncated, 0, MAX_STRING_LENGTH);
            utf8 = truncated;
        }
        long before = getPos();
        long written = write(utf8);
        if (written != utf8.length) {
            setPos(before);
            return false;
        }
        // Write the null terminator and roll back on failure
        if (!writeUInt8(0)) {
            setPos(before);
            return false;
        }
        return true;
    }

    // ---------- Read helpers (return 0 / 0.0 / empty string on underflow) ----------

    public byte readInt8() {
        byte[] b = read(1);
        return b.length == 1 ? b[0] : 0;
    }

    public int readUInt8() {
        byte[] b = read(1);
        return b.length == 1 ? (b[0] & 0xFF) : 0;
    }

    public short readInt16() {
        byte[] b = read(2);
        if (b.length < 2) return 0;
        return ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN).getShort();
    }

    public int readUInt16() {
        byte[] b = read(2);
        if (b.length < 2) return 0;
        return ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN).getShort() & 0xFFFF;
    }

    public int readInt32() {
        return readInt();
    }

    public long readUInt32() {
        byte[] b = read(4);
        if (b.length < 4) return 0;
        return ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN).getInt() & 0xFFFFFFFFL;
    }

    public long readInt64() {
        byte[] b = read(8);
        if (b.length < 8) return 0;
        return ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN).getLong();
    }

    public long readUInt64() {
        return readInt64();
    }

    public float readSingle() {
        byte[] b = read(4);
        if (b.length < 4) return 0.0f;
        return ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN).getFloat();
    }

    public double readDouble2() {
        return readDouble();
    }

    /**
     * Reads a UTF‑8 encoded string terminated by a null byte (#0) from the current
     * position. The read position is advanced to the byte <b>after</b> the null
     * terminator, matching the Pascal {@code API_ReadString} behavior.
     * <p>
     * <b>Hardened (2026-08-21):</b> If the underlying buffer pointer is null,
     * or if the scan exceeds {@value #MAX_STRING_SCAN} bytes without finding a NUL,
     * the method safely returns an empty string without throwing an exception
     * and without modifying the current position.
     *
     * @return the decoded string (may be empty)
     */
    public String readStringNullTerminated() {
        checkNotClosed();
        long pos = getPos();
        long size = getSize();

        // Boundary check
        if (pos >= size) {
            return "";
        }

        // ========== F-01 FIX: Defensive null check on native buffer ==========
        Pointer buf = getBuffer();
        if (buf == null) {
            // Native buffer is invalid; cannot read. Return empty, position unchanged.
            return "";
        }

        long end = pos;
        boolean foundNul = false;

        // ========== W-02 FIX: Scan with upper bound to prevent infinite loops ==========
        while (end < size && (end - pos) <= MAX_STRING_SCAN) {
            if (buf.getByte(end) == 0) {
                foundNul = true;
                break;
            }
            end++;
        }

        // If we hit the scan limit or reached end without finding NUL, abort safely
        if (!foundNul) {
            // Position unchanged to avoid corrupting subsequent reads
            return "";
        }

        int length = (int)(end - pos);
        // ========== W-02 FIX: Guard against insane length values ==========
        if (length < 0 || length > MAX_STRING_LENGTH) {
            return "";
        }

        byte[] data = new byte[length];
        buf.read(pos, data, 0, length);

        // Advance position to right after the NUL terminator
        setPos(end + 1);

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

    public Pointer getBuffer() {
        checkNotClosed();
        return ApiHubNative.INSTANCE.API_GetBuffer(ptr);
    }

    // ---------- Resource management ----------

    @Override
    public void close() {
        if (!closed && owned && ptr != null) {
            ApiHubNative.INSTANCE.API_Free_DataHnd(ptr);
            closed = true;
        } else {
            closed = true;
        }
    }

    private void checkNotClosed() {
        if (closed) {
            throw new IllegalStateException("DataHandle is already closed");
        }
    }
}