# -*- coding: utf-8 -*-
"""
Core RAII wrappers: DataHandle and App.

These classes manage the lifetime of opaque handles and provide
convenient serialization/deserialization. All methods are thread‑safe
except where noted.

Thread‑safety notes from the Pascal unit:
    - All handle operations (write, read, size, etc.) are thread‑safe as
      long as the same handle is not accessed concurrently from multiple
      threads. Write operations should be serialized per handle.
    - App registration and local call methods are thread‑safe.
    - Callbacks registered via App.register_call / register_notify are
      invoked in background thread‑pool threads. They must not block,
      must not call API_Call/API_Notify, and must not access UI without
      synchronisation.

NEW (2026-08-20): Atomic type support and null‑terminated string methods
    - All atomic write methods return bool (success if full bytes written).
    - All atomic read methods return the value; raise BufferError if
      insufficient bytes are available.
    - write_string_null_terminated() writes UTF‑8 bytes followed by a NUL.
    - read_string_null_terminated() reads until NUL or end of buffer,
      returns decoded string, and moves position to the NUL if found,
      or leaves position unchanged if not found.
    These mirror the Pascal functions API_WriteInt8, API_ReadString, etc.
"""
import ctypes
import struct
from typing import Any, Optional, Callable
from ._native import (
    DataHnd, AppHnd,
    API_Create_DataHnd, API_Free_DataHnd,
    API_WriteBuffer, API_ReadBuffer,
    API_GetSize, API_SetPos,
    API_GetBuffer, API_GetPos,
    API_Create_APPHnd, API_Free_APPHnd,
    API_Reg_Call, API_Reg_Notify,
    API_UnReg,
    API_Local_APP_Call, API_Local_APP_Notify,
    APICallFunc, APINotifyFunc,
)
from .errors import ApiError, RegistrationError
from .serializers import default_serializer, default_deserializer


class DataHandle:
    """
    RAII wrapper for a TDataHnd.

    This handle holds an API name and its binary payload. It supports
    automatic serialization/deserialization using user‑supplied or
    default (JSON + pickle) serializers.

    The handle must be freed – either explicitly via free(), by using it
    as a context manager, or implicitly when garbage‑collected.

    Important:
        - The underlying handle is never nil (API_Create_DataHnd always
          succeeds).
        - The returned handle from API_Call must also be freed, even
          if its size is 0.
        - For zero‑copy access, use the raw attribute to get the ctypes
          handle, but then you are responsible for correct usage.

    Thread‑safety: Read‑only operations (size, get_pos) are safe from
    multiple threads. Write operations (write, set_pos, set_size) must
    be serialized for the same handle. Different handles can be used
    concurrently without issue.
    """

    def __init__(self, api_name: str, data: Any = None, serializer=None):
        """
        Create a new DataHandle with the given API name.

        Args:
            api_name: API name (case‑sensitive, used for routing).
            data: Optional initial payload (will be serialized immediately).
            serializer: Callable that converts objects to bytes.
                        Defaults to JSON with pickle fallback.
        """
        self._hnd = API_Create_DataHnd(api_name.encode("utf-8"))
        if not self._hnd:
            raise ApiError("Failed to create DataHandle")
        self._owned = True
        self._serializer = serializer or default_serializer
        self._deserializer = None
        if data is not None:
            self.write(data)

    @classmethod
    def _from_raw(cls, hnd: DataHnd, owned: bool = True):
        """
        Internal factory: wrap an existing raw handle.

        Used in callbacks and local calls to avoid double‑free.
        When owned=False, the caller retains ownership and must free
        the handle externally (e.g., the library owns the handle).
        """
        obj = cls.__new__(cls)
        obj._hnd = hnd
        obj._owned = owned
        obj._serializer = default_serializer
        obj._deserializer = default_deserializer
        return obj

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.free()

    def __del__(self):
        self.free()

    def free(self):
        """Free the underlying handle if owned. Idempotent."""
        if self._owned and self._hnd:
            API_Free_DataHnd(self._hnd)
            self._hnd = None

    @property
    def raw(self) -> DataHnd:
        """Return the raw ctypes handle for low‑level calls."""
        return self._hnd

    def write(self, obj: Any) -> int:
        """
        Serialize and write an object at the current position.

        The buffer is automatically extended if needed.

        Returns:
            int: Number of bytes written (usually the full serialized length).
        """
        data = self._serializer(obj)
        return API_WriteBuffer(self._hnd, data, len(data))

    def read(self, deserializer=None) -> Any:
        """
        Read the entire buffer from position 0, deserialize it,
        and reset the position to 0.

        Args:
            deserializer: Optional callable that converts bytes to object.
                          Defaults to the global default (JSON + pickle).

        Returns:
            The deserialized object, or None if the buffer is empty.
        """
        size = API_GetSize(self._hnd)
        if size == 0:
            return None
        buf = (ctypes.c_byte * size)()
        API_SetPos(self._hnd, 0)
        API_ReadBuffer(self._hnd, buf, size)
        raw = bytes(buf)
        des = deserializer or self._deserializer or default_deserializer
        return des(raw)

    @property
    def size(self) -> int:
        """Current buffer size in bytes."""
        return API_GetSize(self._hnd)

    # ========================================================================
    # NEW: Atomic types and null‑terminated string support (Pascal‑compatible)
    # Added 2026-08-20, matching z_api_hubtool_import.pas exactly.
    # All writes return True if the full number of bytes was written.
    # All reads return the value; if insufficient bytes, raises BufferError.
    # ========================================================================

    # ---------- Write helpers (little‑endian) ----------

    def write_int8(self, value: int) -> bool:
        """Write a signed 8‑bit integer (1 byte)."""
        return self._write_pack('<b', value) == 1

    def write_uint8(self, value: int) -> bool:
        """Write an unsigned 8‑bit integer (1 byte)."""
        return self._write_pack('<B', value) == 1

    def write_int16(self, value: int) -> bool:
        """Write a signed 16‑bit integer (2 bytes, little‑endian)."""
        return self._write_pack('<h', value) == 2

    def write_uint16(self, value: int) -> bool:
        """Write an unsigned 16‑bit integer (2 bytes, little‑endian)."""
        return self._write_pack('<H', value) == 2

    def write_int32(self, value: int) -> bool:
        """Write a signed 32‑bit integer (4 bytes, little‑endian)."""
        return self._write_pack('<i', value) == 4

    def write_uint32(self, value: int) -> bool:
        """Write an unsigned 32‑bit integer (4 bytes, little‑endian)."""
        return self._write_pack('<I', value) == 4

    def write_int64(self, value: int) -> bool:
        """Write a signed 64‑bit integer (8 bytes, little‑endian)."""
        return self._write_pack('<q', value) == 8

    def write_uint64(self, value: int) -> bool:
        """Write an unsigned 64‑bit integer (8 bytes, little‑endian)."""
        return self._write_pack('<Q', value) == 8

    def write_single(self, value: float) -> bool:
        """Write a 32‑bit IEEE 754 single‑precision float (4 bytes, little‑endian)."""
        return self._write_pack('<f', value) == 4

    def write_double(self, value: float) -> bool:
        """Write a 64‑bit IEEE 754 double‑precision float (8 bytes, little‑endian)."""
        return self._write_pack('<d', value) == 8

    def write_string_null_terminated(self, value: str) -> bool:
        """
        Write a UTF‑8 encoded string followed by a null terminator (#0).

        This matches Pascal's API_WriteString. The position is advanced by
        len(UTF‑8 bytes) + 1.

        Returns:
            True if the entire string and the terminating null were written.
        """
        utf8 = value.encode('utf-8')
        written = self._write_bytes(utf8)
        if written != len(utf8):
            return False
        # append NUL
        return self._write_pack('<B', 0) == 1

    def _write_pack(self, fmt: str, value) -> int:
        """Pack a value using struct.pack and write it."""
        data = struct.pack(fmt, value)
        return self._write_bytes(data)

    def _write_bytes(self, data: bytes) -> int:
        """Write raw bytes, return number of bytes actually written."""
        if not data:
            return 0
        return API_WriteBuffer(self._hnd, data, len(data))

    # ---------- Read helpers (little‑endian) ----------

    def read_int8(self) -> int:
        """Read a signed 8‑bit integer (1 byte)."""
        return self._read_unpack('<b')

    def read_uint8(self) -> int:
        """Read an unsigned 8‑bit integer (1 byte)."""
        return self._read_unpack('<B')

    def read_int16(self) -> int:
        """Read a signed 16‑bit integer (2 bytes, little‑endian)."""
        return self._read_unpack('<h')

    def read_uint16(self) -> int:
        """Read an unsigned 16‑bit integer (2 bytes, little‑endian)."""
        return self._read_unpack('<H')

    def read_int32(self) -> int:
        """Read a signed 32‑bit integer (4 bytes, little‑endian)."""
        return self._read_unpack('<i')

    def read_uint32(self) -> int:
        """Read an unsigned 32‑bit integer (4 bytes, little‑endian)."""
        return self._read_unpack('<I')

    def read_int64(self) -> int:
        """Read a signed 64‑bit integer (8 bytes, little‑endian)."""
        return self._read_unpack('<q')

    def read_uint64(self) -> int:
        """Read an unsigned 64‑bit integer (8 bytes, little‑endian)."""
        return self._read_unpack('<Q')

    def read_single(self) -> float:
        """Read a 32‑bit IEEE 754 single‑precision float (4 bytes, little‑endian)."""
        return self._read_unpack('<f')

    def read_double(self) -> float:
        """Read a 64‑bit IEEE 754 double‑precision float (8 bytes, little‑endian)."""
        return self._read_unpack('<d')

    def read_string_null_terminated(self) -> str:
        """
        Read a UTF‑8 string terminated by a null byte (#0) from the current position.

        The position is advanced to the byte **after** the null terminator,
        matching Pascal's API_ReadString behavior.

        If no null is found before the end of the buffer, the position remains
        unchanged and an empty string is returned.

        Returns:
            The decoded string (may be empty if the first byte is 0 or at end).
        """
        pos = API_GetPos(self._hnd)
        size = API_GetSize(self._hnd)
        if pos >= size:
            return ""   # position already at end, no data

        ptr = API_GetBuffer(self._hnd)
        if not ptr:
            raise BufferError("DataHandle buffer is invalid")

        # Scan for null
        end = pos
        cptr = ctypes.cast(ptr, ctypes.POINTER(ctypes.c_byte))
        while end < size and cptr[end] != 0:
            end += 1

        if end == size:
            # No null terminator found: position unchanged, return empty.
            return ""

        # Read bytes from pos to end-1 (excluding null)
        raw = bytes(cptr[pos:end])
        # Advance position to after the null
        API_SetPos(self._hnd, end + 1)
        return raw.decode('utf-8')

    def _read_unpack(self, fmt: str):
        """Read the required number of bytes and unpack with struct."""
        size = struct.calcsize(fmt)
        data = self._read_bytes(size)
        if len(data) != size:
            raise BufferError(f"Not enough data to read {fmt} (needed {size} bytes, got {len(data)})")
        return struct.unpack(fmt, data)[0]

    def _read_bytes(self, n: int) -> bytes:
        """Read exactly n bytes from current position, advancing position."""
        if n <= 0:
            return b''
        buf = (ctypes.c_byte * n)()
        read = API_ReadBuffer(self._hnd, buf, n)
        if read != n:
            # Not enough data; we still return what we read, but caller must handle
            # For atomic reads we raise an error, but this helper just returns bytes.
            return bytes(buf)[:read]
        return bytes(buf)


class App:
    """
    RAII wrapper for a TAppHnd.

    An application is a logical container for APIs. It can register
    multiple Call and Notify APIs. The handle must be freed; the
    destructor will free it automatically.

    All registration and local call methods are thread‑safe.

    CRITICAL: The registered callback functions are executed in
    background thread‑pool threads. They MUST NOT block, MUST NOT call
    API_Call or API_Notify, and MUST NOT access UI without proper
    synchronisation. Heavy processing must be offloaded to separate
    threads. These restrictions exactly mirror those documented in the
    Pascal unit.

    Dynamic Unregistration:
        Use `unregister()` to remove a previously registered API. The
        API is immediately removed from the local registry and a network
        broadcast is triggered. Remote peers will stop seeing this API
        within approximately 3 seconds (depending on network latency
        and the C4 update interval). During that short window, remote
        calls may still be attempted; they will fail gracefully.

    Example:
        app = App("MyApp")
        app.register_call("echo", lambda trig, inp, out: out.write(inp.read()))
        # ... later, unregister the API
        app.unregister("echo")
    """

    def __init__(self, name: str, description: str = ""):
        """
        Create a new application context.

        Args:
            name: Unique application name (case‑sensitive, used for routing).
            description: Human‑readable description (optional).
        """
        self._name = name
        self._hnd = API_Create_APPHnd(name.encode("utf-8"), description.encode("utf-8"))
        if not self._hnd:
            raise ApiError(f"Failed to create App '{name}'")
        self._callbacks = []  # keep references to prevent GC of callback objects

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.free()

    def __del__(self):
        self.free()

    def free(self):
        """Free the application handle and release all registered APIs."""
        if self._hnd:
            API_Free_APPHnd(self._hnd)
            self._hnd = None
            self._callbacks.clear()

    @property
    def raw(self) -> AppHnd:
        """Raw ctypes handle for low‑level use."""
        return self._hnd

    @property
    def name(self) -> str:
        """Application name."""
        return self._name

    def register_call(self, api_name: str, func: Callable, description: str = ""):
        """
        Register a request‑response (Call) API.

        The callback function must have the signature:
            (trigger: Any, input_handle: DataHandle, output_handle: DataHandle) -> None
        It will be invoked in a background thread.

        Args:
            api_name: Unique API name (case‑sensitive, within this app).
            func: Python callable implementing the API.
            description: Optional description.

        Raises:
            RegistrationError: If the API name is already registered.
        """
        if not self._hnd:
            raise ApiError("App already freed")
        def _c_call(trig, inp, out):
            h_in = DataHandle._from_raw(inp, owned=False)
            h_out = DataHandle._from_raw(out, owned=False)
            func(trig, h_in, h_out)
        c_func = APICallFunc(_c_call)
        self._callbacks.append(c_func)  # keep alive
        ret = API_Reg_Call(self._hnd, api_name.encode("utf-8"), description.encode("utf-8"),
                           ctypes.c_void_p(0), c_func)
        if ret != 1:
            raise RegistrationError(f"Failed to register Call API '{api_name}'")

    def register_notify(self, api_name: str, func: Callable, description: str = ""):
        """
        Register a one‑way notification (Notify) API.

        The callback function must have the signature:
            (trigger: Any, input_handle: DataHandle) -> None
        It will be invoked in a background thread.

        Args:
            api_name: Unique API name (case‑sensitive).
            func: Python callable implementing the notification handler.
            description: Optional description.

        Raises:
            RegistrationError: If the API name is already registered.
        """
        if not self._hnd:
            raise ApiError("App already freed")
        def _c_notify(trig, inp):
            h_in = DataHandle._from_raw(inp, owned=False)
            func(trig, h_in)
        c_func = APINotifyFunc(_c_notify)
        self._callbacks.append(c_func)  # keep alive
        ret = API_Reg_Notify(self._hnd, api_name.encode("utf-8"), description.encode("utf-8"),
                             ctypes.c_void_p(0), c_func)
        if ret != 1:
            raise RegistrationError(f"Failed to register Notify API '{api_name}'")

    def unregister(self, api_name: str) -> bool:
        """
        Unregister a previously registered API from this application.

        The API is **immediately** removed from the local registry and a
        network broadcast is triggered. Remote peers will stop seeing this
        API within approximately 3 seconds (depending on network latency
        and the C4 update interval). During that short window, remote calls
        may still be attempted; they will fail gracefully (the remote side
        receives a "not found" error).

        Use this function to dynamically unload plugins, temporarily disable
        services, or adjust exposed functionality at runtime without
        restarting the application.

        Args:
            api_name: Name of the API to unregister (UTF‑8, case‑sensitive).

        Returns:
            True if the API was found and unregistered, False otherwise
            (e.g., the API name does not exist).

        Thread‑safe.
        """
        if not self._hnd:
            return False
        ret = API_UnReg(self._hnd, api_name.encode("utf-8"))
        return ret == 1

    def local_call(self, param: DataHandle) -> DataHandle:
        """
        Execute a Call API locally (bypassing the network).

        The input handle is not modified; the caller still owns it and
        must free it. The returned handle is owned by the caller and
        must be freed.

        Args:
            param: DataHandle with the API name and payload.

        Returns:
            DataHandle containing the result (owned). The handle size
            will be 0 if the API was not found or an error occurred.

        Raises:
            ApiError: If the call fails at the low‑level.
        """
        if not self._hnd:
            raise ApiError("App already freed")
        h_res = API_Local_APP_Call(self._hnd, param.raw)
        if not h_res:
            raise ApiError("Local call failed")
        return DataHandle._from_raw(h_res, owned=True)

    def local_notify(self, param: DataHandle):
        """
        Send a notification locally (no result).

        The input handle is not freed by this call; the caller must
        free it separately.
        """
        if not self._hnd:
            raise ApiError("App already freed")
        API_Local_APP_Notify(self._hnd, param.raw)