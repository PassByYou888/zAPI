# -*- coding: utf-8 -*-
"""
C4 Client: proxy for remote API calls.

This module provides a high‑level client that connects to a C4 service
and exposes remote APIs as Python methods via __getattr__.

Thread safety:
    - API_Call() is fully thread‑safe; you can call it from multiple threads.
    - The registered callbacks (if any) run in background threads, so avoid
      blocking operations and calls to API_Call/API_Notify inside them.

The client uses a shared global preparation state. Only one C4 instance
should be created per process; subsequent calls will reuse the existing
connection.
"""
from typing import Any, Optional
from ._native import (
    API_Reset_Prepare, API_Prepare_Client, API_Prepare_Done,
    API_Call, API_Notify, API_Exit_MainThread, API_shutdown,
)
from .core import DataHandle
from .errors import ApiError, ConnectionError, TimeoutError
from .serializers import default_serializer, default_deserializer


class C4:
    """
    Client that connects to a remote API Hub service and provides
    dynamic method dispatch for remote calls.

    Usage:
        client = C4("ServiceApp", "ipc:demo_service")
        result = client.add(10, 20)   # Calls remote 'add' API
        client.notify("log", "message")

    The client is designed as a singleton: only one global connection
    is prepared. Creating multiple C4 instances with different endpoints
    will cause the latter to ignore the new endpoint and reuse the
    first one. This matches the underlying C4 design where preparation
    is done once per process.

    Thread safety: All methods are thread‑safe.
    """
    _global_initialized = False

    def __init__(self, app_name: str, endpoint: str, timeout: int = 5000,
                 serializer=None, deserializer=None):
        """
        Initialize the client and connect to the remote service.

        Args:
            app_name: Name of the remote application to call.
            endpoint: Network address (e.g., "127.0.0.1:9898" or "ipc:my_service").
            timeout: Default timeout in milliseconds for remote calls (0 = infinite).
            serializer: Optional serialization function.
            deserializer: Optional deserialization function.
        """
        self._app_name = app_name
        self._endpoint = endpoint
        self._timeout = timeout
        self._serializer = serializer or default_serializer
        self._deserializer = deserializer or default_deserializer
        self._connect()

    def _connect(self):
        """Prepare and start the global client connection if not already done."""
        if not C4._global_initialized:
            API_Reset_Prepare()
            API_Prepare_Client(self._endpoint.encode("utf-8"), None)
            ret = API_Prepare_Done()
            if ret != 1:
                # The library prints detailed error messages to console.
                raise ConnectionError(
                    f"Connect to {self._endpoint} failed. Check console output for details. "
                    f"(Return code: {ret})"
                )
            C4._global_initialized = True

    def __getattr__(self, api_name: str):
        """
        Dynamic method for remote calls.

        Example: client.add(5, 7) will call the remote API 'add'.

        The method will serialise its arguments (as a list or dict) and
        deserialise the response. If only one argument is provided and
        it is not a tuple, it is passed as‑is (the serialiser handles it).

        Returns:
            The deserialised result from the remote call.

        Raises:
            TimeoutError: If the call times out.
            ApiError: For other errors (e.g., application not found).
        """
        def _call(*args, **kwargs):
            if len(args) == 1 and not kwargs:
                param_data = args[0]
            else:
                param_data = args if not kwargs else (args, kwargs)
            data = DataHandle(api_name, param_data, self._serializer)
            h_res = API_Call(self._app_name.encode("utf-8"), data.raw, self._timeout)
            data.free()
            if not h_res:
                raise ApiError(f"Call to {api_name} returned null handle")
            result_hnd = DataHandle._from_raw(h_res, owned=True)
            try:
                result = result_hnd.read(self._deserializer)
            finally:
                result_hnd.free()
            return result
        return _call

    def notify(self, api_name: str, data: Any):
        """
        Send a one‑way notification to the remote application.

        The data is serialised and sent as a fire‑and‑forget message.
        No response is expected.

        Args:
            api_name: API name to invoke.
            data: Payload to send (will be serialised).
        """
        hnd = DataHandle(api_name, data, self._serializer)
        API_Notify(self._app_name.encode("utf-8"), hnd.raw)
        hnd.free()

    @classmethod
    def shutdown(cls):
        """Gracefully shut down the global C4 connection and release resources."""
        if cls._global_initialized:
            API_Exit_MainThread()
            API_shutdown()
            cls._global_initialized = False