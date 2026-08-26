# -*- coding: utf-8 -*-
"""
Low‑level ctypes bindings for the API Hub dynamic library.

All exported functions are loaded from the platform‑specific shared library
(z_api_hub64.dll / libz_api_hub.so / libz_api_hub.dylib) at module import.

=========================== THREAD SAFETY ===========================
All functions are FULLY thread‑safe and can be called concurrently
from any number of threads.

==================== CALLBACK EXECUTION CONTEXT ====================
Callbacks (APICallFunc, APINotifyFunc) are executed in background
threads from the library's internal thread pool. Therefore:
    * Do NOT perform long‑blocking operations inside callbacks.
    * Do NOT call API_Call() or API_Notify() from within a callback
      – this may cause deadlocks.
    * Do NOT access UI components or thread‑local storage without
      proper synchronisation.
    * Offload heavy processing to separate worker threads.

These restrictions exactly mirror those documented in the Pascal unit.
For full details, see the Pascal z_api_hubtool_import.pas.

==================== DYNAMIC UNREGISTRATION =======================
API_UnReg removes an API from the local registry immediately and
triggers an asynchronous network broadcast. Remote peers will stop
seeing this API within ~3 seconds (depending on network latency and
C4 update interval).

==================== RUNTIME OPTIONS =============================
API_SetOption dynamically adjusts global runtime options such as
authentication password, wait‑connection behavior, IPC parameters, etc.
All changes take effect immediately (except where noted).
Unknown options are silently ignored.
"""
import ctypes
import sys
import os

class ApiError(Exception):
    """Raised when the library cannot be loaded or a call fails."""
    pass

def _find_library():
    """Return the correct shared library name for the current platform."""
    if sys.platform == "win32":
        return "z_api_hub64.dll" if ctypes.sizeof(ctypes.c_void_p) == 8 else "z_api_hub32.dll"
    elif sys.platform == "darwin":
        return "libz_api_hub.dylib"
    else:
        return "libz_api_hub.so"  # used on Linux, BSD, and other ELF systems

def _load_library():
    """
    Locate and load the shared library, primarily using the system PATH.
    Fallback to the current working directory if PATH lookup fails.
    """
    lib_name = _find_library()
    is_64bit = ctypes.sizeof(ctypes.c_void_p) == 8

    # ----- Windows specific: add system PATH directories to DLL search path -----
    if sys.platform == "win32":
        # Add all directories from PATH to the DLL search path (Python 3.8+)
        for p in os.environ.get("PATH", "").split(os.pathsep):
            if p and os.path.isdir(p):
                try:
                    os.add_dll_directory(p)
                except Exception:
                    pass

        # Pre-load the IPC dependency library from PATH (only the correct bitness)
        dep_name = "z_ipc_64.dll" if is_64bit else "z_ipc_32.dll"
        for p in os.environ.get("PATH", "").split(os.pathsep):
            if not p:
                continue
            dep_path = os.path.join(p, dep_name)
            if os.path.exists(dep_path):
                try:
                    ctypes.WinDLL(dep_path)
                    # Success, no need to continue
                    break
                except Exception:
                    pass  # ignore individual load failures

    # ----- Attempt to load the main library -----
    # Strategy: first try loading by name (relying on system PATH), then fallback to current directory
    try:
        if sys.platform == "win32":
            lib = ctypes.WinDLL(lib_name, winmode=0)
        else:
            lib = ctypes.CDLL(lib_name)
        print(f"[INFO] Successfully loaded from system PATH: {lib_name}")
        return lib
    except OSError:
        pass  # not found in PATH

    # Fallback: try loading from the current working directory
    cwd_path = os.path.join(os.getcwd(), lib_name)
    if os.path.exists(cwd_path):
        try:
            if sys.platform == "win32":
                lib = ctypes.WinDLL(cwd_path, winmode=0)
            else:
                lib = ctypes.CDLL(cwd_path)
            print(f"[INFO] Successfully loaded from current directory: {cwd_path}")
            return lib
        except OSError:
            pass

    # If we reach here, loading has failed
    raise ApiError(f"Cannot load library: {lib_name}. Ensure it is in the system PATH or current directory.")

# Load the library once at module import
_lib = _load_library()

def _set_func(name, argtypes, restype):
    """Helper to set argument types and return type for an exported function."""
    func = getattr(_lib, name)
    func.argtypes = argtypes
    func.restype = restype
    return func

# Opaque handle types (as defined in the Pascal unit)
DataHnd = ctypes.c_void_p
AppHnd = ctypes.c_void_p

# Callback function prototypes – must match the C calling convention (cdecl)
APICallFunc = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
APINotifyFunc = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p)

# ----------------------------------------------------------------------
# Data Handle Operations – see Pascal section 4
# ----------------------------------------------------------------------
API_Create_DataHnd = _set_func("API_Create_DataHnd", [ctypes.c_char_p], DataHnd)
API_Free_DataHnd = _set_func("API_Free_DataHnd", [DataHnd], None)
API_GetBuffer = _set_func("API_GetBuffer", [DataHnd], ctypes.c_void_p)
API_WriteBuffer = _set_func("API_WriteBuffer", [DataHnd, ctypes.c_void_p, ctypes.c_int64], ctypes.c_int64)
API_ReadBuffer = _set_func("API_ReadBuffer", [DataHnd, ctypes.c_void_p, ctypes.c_int64], ctypes.c_int64)
API_GetPos = _set_func("API_GetPos", [DataHnd], ctypes.c_int64)
API_SetPos = _set_func("API_SetPos", [DataHnd, ctypes.c_int64], None)
API_GetSize = _set_func("API_GetSize", [DataHnd], ctypes.c_int64)
API_SetSize = _set_func("API_SetSize", [DataHnd, ctypes.c_int64], None)

# ----------------------------------------------------------------------
# Application Handle Operations – see Pascal section 5
# ----------------------------------------------------------------------
API_Create_APPHnd = _set_func("API_Create_APPHnd", [ctypes.c_char_p, ctypes.c_char_p], AppHnd)
API_Free_APPHnd = _set_func("API_Free_APPHnd", [AppHnd], None)
API_Reg_Call = _set_func("API_Reg_Call", [AppHnd, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, APICallFunc], ctypes.c_int)
API_Reg_Notify = _set_func("API_Reg_Notify", [AppHnd, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, APINotifyFunc], ctypes.c_int)
API_UnReg = _set_func("API_UnReg", [AppHnd, ctypes.c_char_p], ctypes.c_int)     # dynamic unregistration
API_Local_APP_Call = _set_func("API_Local_APP_Call", [AppHnd, DataHnd], DataHnd)
API_Local_APP_Notify = _set_func("API_Local_APP_Notify", [AppHnd, DataHnd], None)

# ----------------------------------------------------------------------
# Network Preparation and Communication – see Pascal sections 8 & 9
# ----------------------------------------------------------------------
API_Prepare_Service = _set_func("API_Prepare_Service", [ctypes.c_char_p, ctypes.c_char_p], ctypes.c_int)
API_Prepare_Client = _set_func("API_Prepare_Client", [ctypes.c_char_p, AppHnd], ctypes.c_int)
API_Reset_Prepare = _set_func("API_Reset_Prepare", [], None)
API_Prepare_Done = _set_func("API_Prepare_Done", [], ctypes.c_int)
API_Exit_MainThread = _set_func("API_Exit_MainThread", [], None)
API_Call = _set_func("API_Call", [ctypes.c_char_p, DataHnd, ctypes.c_uint64], DataHnd)
API_Notify = _set_func("API_Notify", [ctypes.c_char_p, DataHnd], None)
API_SetOption = _set_func("API_SetOption", [ctypes.c_char_p, ctypes.c_char_p], None)
API_shutdown = _set_func("API_shutdown", [], None)

# ======================================================================
# 新增导出函数（补齐 Pascal 全部接口）
# ======================================================================

# ---- 状态与诊断 ----
API_Get_Status_Num = _set_func(
    "API_Get_Status_Num",
    [],
    ctypes.c_int
)
"""
int API_Get_Status_Num()
返回待读取的日志消息数量（FIFO 队列）。
线程安全：是。
"""

API_Get_Status = _set_func(
    "API_Get_Status",
    [],
    ctypes.c_char_p
)
"""
const char* API_Get_Status()
从队列中取出一条日志消息（UTF‑8 编码，以 NUL 结尾）。
返回的指针指向内部静态缓冲区，数据在下次调用前有效。
若队列为空，返回空字符串（仅 NUL）。
调用者不得释放返回的指针，应尽快复制内容。
线程安全：是。
"""

API_Post_Status = _set_func(
    "API_Post_Status",
    [ctypes.c_char_p],
    None
)
"""
void API_Post_Status(const char* status)
向状态队列中写入一条自定义日志消息。
@param status: UTF‑8 编码、NUL 结尾的字符串。
线程安全：是。
"""

API_Check_MainThread = _set_func(
    "API_Check_MainThread",
    [],
    ctypes.c_int
)
"""
int API_Check_MainThread()
检查模拟主线程（C4 事件循环）是否正在运行。
返回 1 表示运行中，0 表示已停止或未启动。
线程安全：是。
"""

API_Check_App = _set_func(
    "API_Check_App",
    [ctypes.c_char_p],
    ctypes.c_int
)
"""
int API_Check_App(const char* appName)
检查网络中是否存在名为 appName 的应用（区分大小写）。
基于本地缓存查询，不保证实时性。
返回 1 存在，0 不存在。
@param appName: UTF‑8 编码、NUL 结尾的应用名。
线程安全：是。
"""