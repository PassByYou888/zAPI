# -*- coding: utf-8 -*-
"""
Server: expose Python functions as remote APIs.

This module provides a decorator‑based server that registers APIs
and starts a C4 service. All exposed functions are called in background
threads – see the threading restrictions below.

========================= THREADING RESTRICTIONS =========================
Callbacks (your exposed functions) are executed in the library's internal
thread pool. Therefore:
    - Do NOT block (e.g., no sleep, no waiting on events).
    - Do NOT call API_Call or API_Notify inside them – this may deadlock.
    - Do NOT access UI components without synchronisation.
    - Offload heavy work to separate threads and return quickly.

These restrictions are identical to those in the Pascal unit.

The server uses a simple JSON‑based serialization with base64 for bytes.
"""
import json
import ctypes
import inspect
import base64
from typing import Any, Callable, Optional, Union, List

from .core import App, DataHandle
from ._native import (
    API_Reset_Prepare, API_Prepare_Service, API_Prepare_Client,
    API_Prepare_Done, API_Call, API_Notify, API_Exit_MainThread, API_shutdown,
    API_Free_DataHnd, API_Create_DataHnd,
    API_WriteBuffer, API_ReadBuffer, API_GetSize, API_SetPos,
)
from .errors import ApiError, ConnectionError

# ----------------------------------------------------------------------
# Internal serialization helpers (JSON with base64 for bytes)
# ----------------------------------------------------------------------
def _convert_to_serializable(obj):
    """Recursively convert objects to JSON‑serializable form, encoding bytes as base64."""
    if isinstance(obj, bytes):
        return {"__bytes__": base64.b64encode(obj).decode("ascii")}
    elif isinstance(obj, list):
        return [_convert_to_serializable(item) for item in obj]
    elif isinstance(obj, dict):
        return {k: _convert_to_serializable(v) for k, v in obj.items()}
    else:
        return obj

def _convert_from_serializable(obj):
    """Recursively convert JSON data back to Python objects, decoding base64 bytes."""
    if isinstance(obj, dict):
        if len(obj) == 1 and "__bytes__" in obj:
            try:
                return base64.b64decode(obj["__bytes__"])
            except Exception:
                return obj
        else:
            return {k: _convert_from_serializable(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [_convert_from_serializable(item) for item in obj]
    else:
        return obj

def _read_json(hnd):
    """Read and deserialize the entire payload from a DataHandle as JSON."""
    size = API_GetSize(hnd.raw)
    if size == 0:
        return None
    buf = (ctypes.c_byte * size)()
    API_SetPos(hnd.raw, 0)
    API_ReadBuffer(hnd.raw, buf, size)
    raw = bytes(buf)
    # Remove any trailing null (the library may add one)
    null = raw.find(b'\x00')
    if null != -1:
        raw = raw[:null]
    try:
        data = json.loads(raw.decode("utf-8"))
        return _convert_from_serializable(data)
    except Exception:
        return None

def _write_json(hnd, obj):
    """Serialize an object as JSON and write it to a DataHandle (null‑terminated)."""
    serializable = _convert_to_serializable(obj)
    data = json.dumps(serializable, ensure_ascii=False).encode("utf-8") + b'\x00'
    API_WriteBuffer(hnd.raw, data, len(data))


class Server:
    """
    Server that registers APIs via decorators and starts a C4 service.

    All exposed functions are executed in background threads – please
    read the threading restrictions at the top of this module.

    Usage:
        server = Server("MyApp")
        @server.expose("add")
        def add(a, b): return a + b
        server.start("ipc:my_service")
        # ... later
        server.stop()

    The server automatically registers itself as a client to the same
    endpoint, allowing the application to be discovered.
    """

    def __init__(self, app_name: str, description: str = ""):
        """
        Create a new server with the given application name.

        Args:
            app_name: Unique application name (case‑sensitive).
            description: Optional description.
        """
        self._app = App(app_name, description)
        self._running = False

    def expose(self, api_name: str, notify: bool = False, description: str = ""):
        """
        Decorator to register a function as a remote API.

        Args:
            api_name: Name of the API (case‑sensitive).
            notify: If True, register as a notification (no return value).
            description: Optional description.

        The decorated function will be called with arguments deserialized
        from JSON. For Call APIs, the return value is serialized back.
        Errors are caught and returned as a JSON object with "__error__".
        """
        def decorator(func: Callable):
            if notify:
                def _notify_adapter(trigger, inp):
                    try:
                        data = _read_json(inp)
                        sig = inspect.signature(func)
                        params = list(sig.parameters.values())
                        # Call the user function with appropriate arguments
                        if data is None:
                            func()
                        elif len(params) == 1:
                            if isinstance(data, list) and len(data) == 1:
                                func(data[0])
                            else:
                                func(data)
                        else:
                            if isinstance(data, list):
                                if len(data) == len(params):
                                    func(*data)
                                else:
                                    func(data)
                            elif isinstance(data, dict):
                                func(**data)
                            else:
                                func(data)
                    except Exception:
                        # Notifications have no reply; ignore errors
                        pass
                self._app.register_notify(api_name, _notify_adapter, description)
            else:
                def _call_adapter(trigger, inp, out):
                    try:
                        data = _read_json(inp)
                        sig = inspect.signature(func)
                        params = list(sig.parameters.values())
                        if data is None:
                            result = func()
                        elif len(params) == 1:
                            if isinstance(data, list) and len(data) == 1:
                                result = func(data[0])
                            else:
                                result = func(data)
                        else:
                            if isinstance(data, list):
                                if len(data) == len(params):
                                    result = func(*data)
                                else:
                                    result = func(data)
                            elif isinstance(data, dict):
                                result = func(**data)
                            else:
                                result = func(data)
                        _write_json(out, result)
                    except Exception as e:
                        # Return error object to caller
                        error_obj = {"__error__": str(e), "__type__": type(e).__name__}
                        _write_json(out, error_obj)
                self._app.register_call(api_name, _call_adapter, description)
            return func
        return decorator

    def start(self, addr: str, public_addr: Optional[str] = None):
        """
        Start the C4 service and bind to a single address.

        Args:
            addr: Local binding address (e.g., "0.0.0.0:9898" or "ipc:my_service").
            public_addr: Public address advertised to clients. Defaults to `addr`.

        Raises:
            ConnectionError: If the service fails to start.

        Example:
            server.start("0.0.0.0:9898")                # TCP service
            server.start("ipc:my_service")              # IPC service
            server.start("0.0.0.0:9898", "10.0.0.1:9898")  # with public address
        """
        if self._running:
            return
        public_addr = public_addr or addr
        API_Reset_Prepare()
        API_Prepare_Service(addr.encode("utf-8"), public_addr.encode("utf-8"))
        # Also prepare a client to register our app with the service
        API_Prepare_Client(addr.encode("utf-8"), self._app.raw)
        ret = API_Prepare_Done()
        if ret != 1:
            # The library prints detailed error messages to console.
            # We raise a generic error and suggest checking console output.
            raise ConnectionError(
                f"Server start failed. Check console output for details. "
                f"(Return code: {ret})"
            )
        self._running = True
        print(f"[OK] Server '{self._app.name}' started on {addr}")

    def start_multi(self, addresses: Union[str, List[str]], public_addrs: Optional[Union[str, List[str]]] = None):
        """
        Start the C4 service on one or multiple addresses simultaneously.
        This is an additive extension over start() – it does not modify the
        existing start() behaviour, so existing code remains unaffected.

        This method allows the server to listen on several endpoints at once,
        which is useful for:
            - Mixed networks: TCP for remote clients and IPC for local clients.
            - Multi-homed hosts: listening on multiple network interfaces.
            - High availability: exposing the same application on several ports.

        Internally it calls API_Reset_Prepare() once, then prepares all services
        and clients in one batch, and finally API_Prepare_Done().

        Args:
            addresses: A single address string, or a list of address strings
                       to bind to. Each address follows the same format as in
                       start(): e.g., "0.0.0.0:9898", "127.0.0.1:9899",
                       "ipc:my_service".
            public_addrs: Optional. Can be:
                          - None (default): each listening address is also
                            used as its own public address.
                          - A single string: all listening addresses will
                            advertise this same public address.
                          - A list of strings: must have the same length as
                            `addresses`, providing a one-to-one mapping.

        Raises:
            ValueError: If public_addrs length does not match addresses length.
            RuntimeError: If the server is already running.
            ConnectionError: If the network preparation fails.

        Example:
            # 1. Listen on a single TCP port (same as server.start()):
            server.start_multi("0.0.0.0:9898")

            # 2. Listen on two TCP ports with different public addresses:
            server.start_multi(
                ["0.0.0.0:9898", "0.0.0.0:9899"],
                public_addrs=["external-ip:9898", "external-ip:9899"]
            )

            # 3. Mixed TCP and IPC:
            server.start_multi(
                ["0.0.0.0:9898", "ipc:my_service"],
                public_addrs="127.0.0.1:9898"   # both use the same public address
            )

            # 4. Multiple IPC services with different names:
            server.start_multi(
                ["ipc:srv1", "ipc:srv2"],
                public_addrs=["ipc:srv1", "ipc:srv2"]
            )
        """
        if self._running:
            raise RuntimeError("Server already running. Call stop() first.")

        # Normalize addresses to a list
        if isinstance(addresses, str):
            addr_list = [addresses]
        else:
            addr_list = list(addresses)

        # Normalize public_addrs
        if public_addrs is None:
            pub_list = addr_list[:]  # use the listening address as public
        elif isinstance(public_addrs, str):
            pub_list = [public_addrs] * len(addr_list)
        else:
            pub_list = list(public_addrs)
            if len(pub_list) != len(addr_list):
                raise ValueError(
                    f"public_addrs length ({len(pub_list)}) must match "
                    f"addresses length ({len(addr_list)})"
                )

        # Reset network preparation and prepare all services/clients
        API_Reset_Prepare()
        for listen, pub in zip(addr_list, pub_list):
            API_Prepare_Service(listen.encode('utf-8'), pub.encode('utf-8'))
            API_Prepare_Client(pub.encode('utf-8'), self._app.raw)

        ret = API_Prepare_Done()
        if ret != 1:
            raise ConnectionError(
                f"Server start_multi failed. Check console output for details. "
                f"(Return code: {ret})"
            )
        self._running = True
        print(f"[OK] Server '{self._app.name}' started on {addr_list}")

    def notify(self, api_name: str, *args):
        """
        Send a notification to the remote service (or to our own app).

        This is a convenience method that constructs a DataHandle and
        sends it via API_Notify.

        Args:
            api_name: API name to invoke.
            *args: Positional arguments to send as the payload.
        """
        if not self._running:
            raise RuntimeError("Server not started")
        req = API_Create_DataHnd(api_name.encode("utf-8"))
        _write_json(DataHandle._from_raw(req, owned=False), list(args) if args else None)
        API_Notify(self._app.name.encode("utf-8"), req)
        API_Free_DataHnd(req)

    def call(self, api_name: str, *args, timeout: int = 5000) -> Any:
        """
        Synchronous remote call to the server's own API (or any remote app).

        Args:
            api_name: API name to call.
            *args: Positional arguments to send.
            timeout: Timeout in milliseconds.

        Returns:
            The deserialised result.

        Raises:
            RuntimeError: If an error is returned from the remote side.
            TimeoutError: If the call times out.
        """
        if not self._running:
            raise RuntimeError("Server not started")
        req = API_Create_DataHnd(api_name.encode("utf-8"))
        _write_json(DataHandle._from_raw(req, owned=False), list(args) if args else None)
        resp = API_Call(self._app.name.encode("utf-8"), req, timeout)
        API_Free_DataHnd(req)
        if not resp:
            raise ApiError("Call returned null handle")
        try:
            result = _read_json(DataHandle._from_raw(resp, owned=False))
            if isinstance(result, dict) and "__error__" in result:
                raise RuntimeError(result["__error__"])
            return result
        finally:
            API_Free_DataHnd(resp)

    def stop(self):
        """Shut down the server gracefully."""
        if not self._running:
            return
        self._running = False
        API_Exit_MainThread()
        API_shutdown()
        self._app.free()
        print("[OK] Server stopped")