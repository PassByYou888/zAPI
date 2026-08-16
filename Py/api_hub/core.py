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
"""
import ctypes
from typing import Any, Optional, Callable
from ._native import (
    DataHnd, AppHnd,
    API_Create_DataHnd, API_Free_DataHnd,
    API_WriteBuffer, API_ReadBuffer,
    API_GetSize, API_SetPos,
    API_Create_APPHnd, API_Free_APPHnd,
    API_Reg_Call, API_Reg_Notify,
    API_UnReg,  # NEW
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