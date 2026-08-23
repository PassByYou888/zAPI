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
    """Locate and load the shared library, searching common paths across platforms."""
    lib_name = _find_library()
    
    # 获取项目根目录和当前模块目录
    module_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(module_dir)          # 通常为项目根目录
    binary_dir = os.path.join(project_root, "..", "Binary")  # 某些项目结构

    # 构建搜索路径列表（优先级从高到低）
    search_paths = [
        module_dir,                # 与 _native.py 同目录
        project_root,              # 项目根目录
        binary_dir,                # 常见二进制目录
        os.getcwd(),               # 当前工作目录
        os.path.dirname(sys.executable),  # Python 解释器目录
        os.environ.get("Z_API_HUB_PATH", ""),  # 自定义环境变量
    ]
    # 移除空路径
    search_paths = [p for p in search_paths if p and os.path.isdir(p)]

    # ----- Windows 特定处理 -----
    if sys.platform == "win32":
        # 将系统 PATH 中的目录加入 DLL 搜索路径（Python 3.8+ 必需）
        for p in os.environ.get("PATH", "").split(os.pathsep):
            if p and os.path.isdir(p):
                try:
                    os.add_dll_directory(p)
                except Exception:
                    pass  # 忽略添加失败

        # 预先加载依赖库（如 z_ipc_64.dll），避免主库加载时找不到依赖
        dep_candidates = ["z_ipc_64.dll", "z_ipc_32.dll"]
        for dep in dep_candidates:
            # 在搜索路径中寻找依赖库
            for base in search_paths:
                dep_path = os.path.join(base, dep)
                if os.path.exists(dep_path):
                    try:
                        ctypes.WinDLL(dep_path)
                        print(f"[INFO] Preloaded dependency: {dep_path}")
                    except Exception as e:
                        print(f"[WARN] Failed to preload {dep_path}: {e}")
                    break

    # ----- 尝试加载主库 -----
    for base in search_paths:
        full_path = os.path.join(base, lib_name)
        if os.path.exists(full_path):
            print(f"[INFO] Attempting to load: {full_path}")
            try:
                if sys.platform == "win32":
                    # winmode=0 使用系统默认搜索顺序（配合 add_dll_directory）
                    lib = ctypes.WinDLL(full_path, winmode=0)
                elif sys.platform == "darwin":
                    # macOS 使用 CDLL
                    lib = ctypes.CDLL(full_path)
                else:
                    # Linux / BSD / 其他 Unix
                    lib = ctypes.CDLL(full_path)
                print(f"[INFO] Successfully loaded from: {full_path}")
                return lib
            except OSError as e:
                print(f"[WARN] Failed to load {full_path}: {e}")
                continue

    # ----- 最后尝试从系统 PATH 中加载（直接使用库名）-----
    print(f"[INFO] Attempting to load from system PATH: {lib_name}")
    try:
        if sys.platform == "win32":
            lib = ctypes.WinDLL(lib_name, winmode=0)
        else:
            lib = ctypes.CDLL(lib_name)
        print(f"[INFO] Successfully loaded from system PATH")
        return lib
    except OSError as e:
        print(f"[ERROR] Cannot load {lib_name} from any path. Last error: {e}")

    # 所有尝试都失败
    raise ApiError(f"Cannot load library: {lib_name}")

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