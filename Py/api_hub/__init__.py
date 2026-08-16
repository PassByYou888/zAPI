# -*- coding: utf-8 -*-
"""
Python bindings for the API Hub dynamic library.

This package exposes the same functionality as the Pascal z_api_hubtool_import
unit, with a Pythonic interface. It allows Python applications to both
expose and consume remote APIs across processes and machines.

Key components:
    - DataHandle: binary payload with an API name (RAII).
    - App: container for registering APIs.
    - Server: decorator‑based server that exposes Python functions.
    - C4: client proxy for calling remote services.
    - set_option: runtime configuration (password, wait‑connection, etc.)

All core functions are fully thread‑safe. Callbacks (registered via App or
Server) execute in background thread‑pool threads. They must not block, and
must not call API_Call/API_Notify to avoid deadlocks. Heavy work must be
offloaded.

For detailed usage, refer to the Pascal documentation.
"""
from .core import DataHandle, App
from .server import Server
from .client import C4
from .errors import ApiError, ConnectionError, TimeoutError, RegistrationError
from ._native import API_SetOption as _API_SetOption

def set_option(option: str, value: str) -> None:
    """
    Dynamically adjust global runtime options of the API Hub framework.

    All changes take effect immediately for subsequent operations (except
    where noted). Unknown options are silently ignored.

    Supported option keys (case‑insensitive, aliases accepted):
        - "password" / "passwd" : Sets C4 P2PVM authentication token.
          Must match on both service and client sides. Affects new connections only.
        - "Quiet" : Enable/disable quiet mode (True/False).
        - "External_Conf_Auto_Save" / "Conf_Auto_Save" : Auto‑save .ini on exit (True/False).
        - "Wait_Connection_ReadyOk" / "Wait_API_Prepare_Done" / ... :
          Controls whether `prepare_done` blocks until all clients are connected.
          When False, clients auto‑connect later (important for deployment).
        - "Wait_Connection_Timeout" / "Wait_TimeOut" : Max wait (ms) when the above is True.
        - "ShowThreadID" / "ShowThread" / "Show_Thread" : Show thread IDs in logs (True/False).
        - "ConsoleOutput" / "Console_Output" : Enable/disable console logging (True/False).
        - "IPC_Serv_ThreadCount" / "IPC_ThreadCount" / "IPC_Server_ThreadCount" :
          Number of threads in the IPC service thread pool.
        - "IPC_Serv_MaxQueueLength" / "IPC_MaxQueueLength" / "IPC_Server_MaxQueueLength" :
          Max IPC queue length.
        - "IPC_Serv_MaxMsgSize" / "IPC_MaxMsgSize" / "IPC_Server_MaxMsgSize" :
          Max IPC message size (bytes).

    For boolean options, accepted values: "True"/"False", "1"/"0", "Yes"/"No".

    This function has no return value.

    Example:
        set_option("password", "my_secret")
        set_option("Wait_Connection_ReadyOk", "False")
    """
    _API_SetOption(option.encode("utf-8"), value.encode("utf-8"))

__all__ = [
    "DataHandle", "App", "Server", "C4",
    "ApiError", "ConnectionError", "TimeoutError", "RegistrationError",
    "set_option",
]