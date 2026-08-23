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

# ---- 新增状态与诊断函数 ----
def get_status_num() -> int:
    """
    返回日志队列中待读取的消息数量。

    线程安全：是。

    Returns:
        int: 当前队列中的消息条数。
    """
    from ._native import API_Get_Status_Num
    return API_Get_Status_Num()

def get_status() -> str:
    """
    从日志队列中取出一条消息（FIFO 顺序）。

    返回的字符串是内部缓冲区的副本，即使后续调用也不会受影响。
    若队列为空，返回空字符串。

    线程安全：是。

    Returns:
        str: 日志内容（UTF‑8 解码后的字符串）。
    """
    from ._native import API_Get_Status
    ptr = API_Get_Status()
    if not ptr:
        return ""
    # 读取到 NUL 为止
    end = 0
    while ptr[end] != 0:
        end += 1
    return ptr[:end].decode("utf-8")

def post_status(status: str) -> None:
    """
    向日志队列中注入一条自定义消息。

    消息会被追加到队列尾部，与其他库日志一同通过 get_status() 读取。

    线程安全：是。

    Args:
        status: 要写入的日志内容（将自动编码为 UTF‑8）。
    """
    from ._native import API_Post_Status
    API_Post_Status(status.encode("utf-8"))

def check_main_thread() -> bool:
    """
    检查模拟主线程（C4 事件循环）是否正在运行。

    该线程在 API_Prepare_Done() 成功后启动，在 API_Exit_MainThread() 或
    API_shutdown() 后停止。

    线程安全：是。

    Returns:
        bool: True 表示正在运行，False 表示已停止。
    """
    from ._native import API_Check_MainThread
    return API_Check_MainThread() != 0

def check_app(app_name: str) -> bool:
    """
    检查网络中是否存在指定的应用。

    该查询基于本地缓存，可能略有过时（通常 < 3 秒）。
    适用于快速探测目标是否在线，但不应作为严格的前置条件。

    线程安全：是。

    Args:
        app_name: 应用名称（区分大小写）。

    Returns:
        bool: True 表示存在至少一个实例，False 表示不存在。
    """
    from ._native import API_Check_App
    return API_Check_App(app_name.encode("utf-8")) != 0

__all__ = [
    "DataHandle", "App", "Server", "C4",
    "ApiError", "ConnectionError", "TimeoutError", "RegistrationError",
    "set_option",
    # 新增诊断函数
    "get_status_num", "get_status", "post_status",
    "check_main_thread", "check_app",
]