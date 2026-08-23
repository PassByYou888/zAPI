//! API Hub Rust Bindings – Dynamic Loading Edition
//!
//! 本库提供了对 API Hub C 动态库的安全 Rust 接口。动态库在运行时加载，
//! 所有函数通过静态 `Api` 结构体中的原始指针访问。
//! RAII 包装器（`DataHandle`、`AppHandle`）提供自动资源管理。
//!
//! # 所有权模型（关键）
//!
//! `DataHandle` 区分**拥有**和**借用**两种句柄。
//! - **拥有**（`new` 或 `from_owned_raw`）：在 `Drop` 时释放句柄。
//!   用于用户创建或从 `call`/`local_call` 返回的句柄。
//! - **借用**（`from_raw`）：在 `Drop` 时**不释放**句柄。
//!   仅用于回调中的 `input` 和 `output` 参数，这些由 C 库拥有。
//!
//! **重要**：借用的句柄仍然可以写入（例如回调中的 `output`）。
//! 开发者必须确保仅在允许写入的句柄上执行写入（如 `output` 用于结果，
//! 而 `input` 是只读的）。
//!
//! # 线程安全（基于 C ABI 规范）
//!
//! **所有函数均为完全线程安全**，可从任意数量的线程并发调用。
//! 这符合底层 C 库的行为。对于同一个 `DataHandle`，写操作（`write`、
//! `set_pos`、`set_size`）应跨线程串行化，但读操作可以安全并发。
//!
//! # 回调约束（关键）
//!
//! 通过 [`reg_call`] 和 [`reg_notify`] 注册的回调在库内部线程池的
//! 后台线程中执行。
//!
//! - **禁止**在回调内部调用 [`call`] 或 [`notify`] —— 这可能造成死锁，
//!   因为回调可能持有内部锁。
//! - **禁止**在回调内部执行长时间阻塞操作（如 `sleep`、重循环、等待事件）。
//! - **禁止**在回调中直接访问 UI 组件或线程局部存储，应通过通道或消息队列
//!   进行同步。
//! - 耗时任务应分流到独立线程或队列，回调需快速返回。
//!
//! # 性能
//!
//! 对于轻量级调用（无大载荷），在典型配置下库可维持约 3000 请求/秒。
//! 同机通信使用 IPC（`ipc:...`）可实现亚毫秒级延迟。
//! 尽可能重用 `DataHandle` 以减少分配开销。
//!
//! # 执行顺序
//!
//! 库**不保证**并发调用的执行顺序。由于负载均衡和多线程，请求可能乱序处理。
//! 若应用依赖特定顺序，需自行实现排序机制（如序列号或串行化）。
//!
//! # 错误诊断
//!
//! 库默认将详细诊断信息打印到控制台（stdout/stderr）。
//! 可通过 `<可执行文件名>.api-tool.ini` 配置文件控制日志行为，
//! 该文件在首次运行时自动生成，也可通过 [`set_option`] 在运行时调整。
//!
//! # 运行时选项（通过 [`set_option`]）
//!
//! 支持的键（不区分大小写，支持别名）：
//! - `"password" / "passwd"`：设置 C4 P2PVM 认证令牌。
//!   服务端和客户端必须匹配。仅影响新建连接。
//! - `"Quiet"`：启用/禁用静默模式（True/False）。抑制调试日志。
//! - `"External_Conf_Auto_Save" / "Conf_Auto_Save"`：退出时自动保存 .ini（True/False）。
//! - `"Wait_Connection_ReadyOk" / "Wait_API_Prepare_Done" / ...`：
//!   控制 [`prepare_done`] 是否阻塞等待所有客户端连接就绪。
//!   设为 False 时客户端稍后自动连接（适用于部署）。
//! - `"Wait_Connection_Timeout" / "Wait_TimeOut"`：最大等待时间（毫秒）。
//! - `"ShowThreadID" / "ShowThread" / "Show_Thread"`：在日志中显示线程 ID。
//! - `"ConsoleOutput" / "Console_Output"`：启用/禁用控制台日志。
//! - `"IPC_Serv_ThreadCount" / "IPC_ThreadCount" / "IPC_Server_ThreadCount"`：
//!   IPC 服务线程池大小。
//! - `"IPC_Serv_MaxQueueLength" / "IPC_MaxQueueLength" / "IPC_Server_MaxQueueLength"`：
//!   IPC 消息队列最大长度。
//! - `"IPC_Serv_MaxMsgSize" / "IPC_MaxMsgSize" / "IPC_Server_MaxMsgSize"`：
//!   IPC 单条消息最大字节数。

#![allow(static_mut_refs)]
#![allow(unused_unsafe)]

use libloading::Library;
use std::ffi::{CString, c_char, c_int, c_void, c_ulonglong};
use std::sync::Once;

// ============================================================================
// 条件调试日志宏（供外部使用）
// ============================================================================

/// 调试日志：当启用 `debug-log` feature 时打印到 stderr。
#[macro_export]
macro_rules! debug_log {
    ($($arg:tt)*) => {
        if cfg!(feature = "debug-log") {
            eprintln!("[DEBUG] {}", format!($($arg)*));
        }
    };
}

// ============================================================================
// 类型定义
// ============================================================================

/// 不透明数据句柄，持有 API 名称和二进制载荷。
/// 通过 `create_data_hnd` 创建，通过 `free_data_hnd` 释放（或通过 `DataHandle` RAII）。
pub type DataHnd = *mut c_void;

/// 不透明应用句柄，分组一组 API。
/// 通过 `create_app_hnd` 创建，通过 `free_app_hnd` 释放（或通过 `AppHandle` RAII）。
pub type AppHnd = *mut c_void;

/// 请求-响应（Call）API 的回调签名。
///
/// # 安全性
///
/// 回调必须是 `extern "C"`，且**禁止**递归调用 [`call`] 或 [`notify`]
/// （死锁风险）。应快速返回；重处理应委托给其他线程。
///
/// # 参数
///
/// - `trigger`：用户提供的指针（注册时传入 [`reg_call`]）。
/// - `input`：  只读数据句柄，包含请求载荷。
/// - `output`： 只写数据句柄，必须写入响应。
pub type APICall = extern "C" fn(*mut c_void, DataHnd, DataHnd);

/// 单向通知（Notify）API 的回调签名。
///
/// 与 [`APICall`] 相同的安全限制——无递归调用，无阻塞。
pub type APINotify = extern "C" fn(*mut c_void, DataHnd);

// ============================================================================
// 错误类型
// ============================================================================

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ApiError {
    NullHandle,
    InvalidApiName,
    InvalidAppName,
    RegistrationFailed,
    UnregisterFailed,
    WriteFailed,
    ReadFailed,
    AllocationFailed,
    PrepareFailed,
    CallFailed,
    LibraryLoadFailed(&'static str),
    SymbolNotFound(&'static str),
    Other(&'static str),
}

impl std::fmt::Display for ApiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}", self)
    }
}

impl std::error::Error for ApiError {}

pub type Result<T> = std::result::Result<T, ApiError>;

// ============================================================================
// 全局 API 函数指针
// ============================================================================

struct Api {
    create_data_hnd: fn(*const c_char) -> DataHnd,
    free_data_hnd: fn(DataHnd),
    get_buffer: fn(DataHnd) -> *mut c_void,
    write_buffer: fn(DataHnd, *const c_void, i64) -> i64,
    read_buffer: fn(DataHnd, *mut c_void, i64) -> i64,
    get_pos: fn(DataHnd) -> i64,
    set_pos: fn(DataHnd, i64),
    get_size: fn(DataHnd) -> i64,
    set_size: fn(DataHnd, i64),

    create_app_hnd: fn(*const c_char, *const c_char) -> AppHnd,
    free_app_hnd: fn(AppHnd),
    reg_call: fn(AppHnd, *const c_char, *const c_char, *mut c_void, APICall) -> c_int,
    reg_notify: fn(AppHnd, *const c_char, *const c_char, *mut c_void, APINotify) -> c_int,
    un_reg: fn(AppHnd, *const c_char) -> c_int,
    local_app_call: fn(AppHnd, DataHnd) -> DataHnd,
    local_app_notify: fn(AppHnd, DataHnd),

    prepare_service: fn(*const c_char, *const c_char) -> c_int,
    prepare_client: fn(*const c_char, AppHnd) -> c_int,
    reset_prepare: fn(),
    prepare_done: fn() -> c_int,
    exit_main_thread: fn(),
    call: fn(*const c_char, DataHnd, c_ulonglong) -> DataHnd,
    notify: fn(*const c_char, DataHnd),
    set_option: fn(*const c_char, *const c_char),
    shutdown: fn(),

    // ====================================================================
    // 新增导出函数（补齐 Pascal 全部接口） – 2026-08-24
    // ====================================================================
    get_status_num: fn() -> c_int,
    get_status: fn() -> *const c_char,
    post_status: fn(*const c_char),
    check_main_thread: fn() -> c_int,
    check_app: fn(*const c_char) -> c_int,
}

static mut API: Option<Api> = None;
static INIT: Once = Once::new();

// ============================================================================
// 库加载
// ============================================================================

#[cfg(target_os = "windows")]
const LIB_NAME: &str = "z_api_hub64.dll";
#[cfg(target_os = "linux")]
const LIB_NAME: &str = "libz_api_hub.so";
#[cfg(target_os = "macos")]
const LIB_NAME: &str = "libz_api_hub.dylib";
#[cfg(any(target_os = "freebsd", target_os = "openbsd", target_os = "netbsd"))]
const LIB_NAME: &str = "libz_api_hub.so";

fn find_library() -> Result<Library> {
    let mut candidates = Vec::new();
    candidates.push(std::path::PathBuf::from(LIB_NAME));
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            candidates.push(dir.join(LIB_NAME));
            if let Some(parent) = dir.parent() {
                if let Some(grand) = parent.parent() {
                    candidates.push(grand.join("Binary").join(LIB_NAME));
                }
                candidates.push(parent.join("Binary").join(LIB_NAME));
            }
        }
    }
    if let Ok(cwd) = std::env::current_dir() {
        candidates.push(cwd.join("..").join("Binary").join(LIB_NAME));
        candidates.push(cwd.join("Binary").join(LIB_NAME));
    }

    debug_log!("Searching for dynamic library, candidate paths:");
    for path in &candidates {
        debug_log!("  {}", path.display());
    }

    for path in candidates {
        if let Ok(lib) = unsafe { Library::new(&path) } {
            debug_log!("Successfully loaded library from: {}", path.display());
            return Ok(lib);
        }
    }
    debug_log!("Trying system path: {}", LIB_NAME);
    unsafe { Library::new(LIB_NAME) }
        .map_err(|_| ApiError::LibraryLoadFailed("Unable to load library from any path"))
}

fn load_api() -> Result<()> {
    let mut err = None;
    INIT.call_once(|| {
        debug_log!("Starting to load API Hub dynamic library...");
        let lib = match find_library() {
            Ok(l) => l,
            Err(e) => {
                debug_log!("Library loading failed: {:?}", e);
                err = Some(e);
                return;
            }
        };

        macro_rules! get_fn {
            ($lib:expr, $name:literal, $ty:ty) => {{
                debug_log!("Resolving symbol: {}", $name);
                let sym = unsafe { $lib.get::<$ty>($name.as_bytes()) };
                match sym {
                    Ok(s) => *s,
                    Err(_) => {
                        debug_log!("Symbol {} not found", $name);
                        err = Some(ApiError::SymbolNotFound($name));
                        return;
                    }
                }
            }};
        }

        let create_data_hnd = get_fn!(lib, "API_Create_DataHnd", fn(*const c_char) -> DataHnd);
        let free_data_hnd = get_fn!(lib, "API_Free_DataHnd", fn(DataHnd));
        let get_buffer = get_fn!(lib, "API_GetBuffer", fn(DataHnd) -> *mut c_void);
        let write_buffer = get_fn!(lib, "API_WriteBuffer", fn(DataHnd, *const c_void, i64) -> i64);
        let read_buffer = get_fn!(lib, "API_ReadBuffer", fn(DataHnd, *mut c_void, i64) -> i64);
        let get_pos = get_fn!(lib, "API_GetPos", fn(DataHnd) -> i64);
        let set_pos = get_fn!(lib, "API_SetPos", fn(DataHnd, i64));
        let get_size = get_fn!(lib, "API_GetSize", fn(DataHnd) -> i64);
        let set_size = get_fn!(lib, "API_SetSize", fn(DataHnd, i64));

        let create_app_hnd = get_fn!(lib, "API_Create_APPHnd", fn(*const c_char, *const c_char) -> AppHnd);
        let free_app_hnd = get_fn!(lib, "API_Free_APPHnd", fn(AppHnd));
        let reg_call = get_fn!(lib, "API_Reg_Call", fn(AppHnd, *const c_char, *const c_char, *mut c_void, APICall) -> c_int);
        let reg_notify = get_fn!(lib, "API_Reg_Notify", fn(AppHnd, *const c_char, *const c_char, *mut c_void, APINotify) -> c_int);
        let un_reg = get_fn!(lib, "API_UnReg", fn(AppHnd, *const c_char) -> c_int);
        let local_app_call = get_fn!(lib, "API_Local_APP_Call", fn(AppHnd, DataHnd) -> DataHnd);
        let local_app_notify = get_fn!(lib, "API_Local_APP_Notify", fn(AppHnd, DataHnd));

        let prepare_service = get_fn!(lib, "API_Prepare_Service", fn(*const c_char, *const c_char) -> c_int);
        let prepare_client = get_fn!(lib, "API_Prepare_Client", fn(*const c_char, AppHnd) -> c_int);
        let reset_prepare = get_fn!(lib, "API_Reset_Prepare", fn());
        let prepare_done = get_fn!(lib, "API_Prepare_Done", fn() -> c_int);
        let exit_main_thread = get_fn!(lib, "API_Exit_MainThread", fn());
        let call = get_fn!(lib, "API_Call", fn(*const c_char, DataHnd, c_ulonglong) -> DataHnd);
        let notify = get_fn!(lib, "API_Notify", fn(*const c_char, DataHnd));
        let set_option = get_fn!(lib, "API_SetOption", fn(*const c_char, *const c_char));
        let shutdown = get_fn!(lib, "API_shutdown", fn());

        // 新增符号加载
        let get_status_num = get_fn!(lib, "API_Get_Status_Num", fn() -> c_int);
        let get_status = get_fn!(lib, "API_Get_Status", fn() -> *const c_char);
        let post_status = get_fn!(lib, "API_Post_Status", fn(*const c_char));
        let check_main_thread = get_fn!(lib, "API_Check_MainThread", fn() -> c_int);
        let check_app = get_fn!(lib, "API_Check_App", fn(*const c_char) -> c_int);

        unsafe {
            API = Some(Api {
                create_data_hnd,
                free_data_hnd,
                get_buffer,
                write_buffer,
                read_buffer,
                get_pos,
                set_pos,
                get_size,
                set_size,
                create_app_hnd,
                free_app_hnd,
                reg_call,
                reg_notify,
                un_reg,
                local_app_call,
                local_app_notify,
                prepare_service,
                prepare_client,
                reset_prepare,
                prepare_done,
                exit_main_thread,
                call,
                notify,
                set_option,
                shutdown,
                get_status_num,
                get_status,
                post_status,
                check_main_thread,
                check_app,
            });
            debug_log!("All API symbols resolved successfully");
        }
        std::mem::forget(lib);
        debug_log!("Library pinned in memory");
    });

    if let Some(e) = err {
        debug_log!("Loading process failed: {:?}", e);
        Err(e)
    } else {
        debug_log!("API loading complete");
        Ok(())
    }
}

fn api() -> &'static Api {
    load_api().expect("API Hub library failed to load");
    unsafe { API.as_ref().unwrap() }
}

// ============================================================================
// 公有 API 函数（带日志）
// ============================================================================

pub fn create_data_hnd(api_name: &str) -> Result<DataHnd> {
    debug_log!("create_data_hnd: {}", api_name);
    let cname = CString::new(api_name).map_err(|_| ApiError::InvalidApiName)?;
    let ptr = (api().create_data_hnd)(cname.as_ptr());
    if ptr.is_null() {
        debug_log!("create_data_hnd returned null");
        Err(ApiError::NullHandle)
    } else {
        debug_log!("create_data_hnd succeeded: {:p}", ptr);
        Ok(ptr)
    }
}

pub fn free_data_hnd(hnd: DataHnd) {
    debug_log!("free_data_hnd: {:p}", hnd);
    if !hnd.is_null() {
        (api().free_data_hnd)(hnd);
    }
}

pub fn write_buffer(hnd: DataHnd, data: &[u8]) -> Result<usize> {
    debug_log!("write_buffer: hnd={:p}, len={}", hnd, data.len());
    let written = (api().write_buffer)(hnd, data.as_ptr() as *const c_void, data.len() as i64);
    if written < 0 {
        debug_log!("write_buffer failed");
        Err(ApiError::WriteFailed)
    } else {
        debug_log!("write_buffer wrote {} bytes", written);
        Ok(written as usize)
    }
}

pub fn read_buffer(hnd: DataHnd, buf: &mut [u8]) -> Result<usize> {
    debug_log!("read_buffer: hnd={:p}, len={}", hnd, buf.len());
    let read = (api().read_buffer)(hnd, buf.as_mut_ptr() as *mut c_void, buf.len() as i64);
    if read < 0 {
        debug_log!("read_buffer failed");
        Err(ApiError::ReadFailed)
    } else {
        debug_log!("read_buffer read {} bytes", read);
        Ok(read as usize)
    }
}

pub fn get_pos(hnd: DataHnd) -> i64 {
    (api().get_pos)(hnd)
}

pub fn set_pos(hnd: DataHnd, pos: i64) {
    (api().set_pos)(hnd, pos)
}

pub fn get_size(hnd: DataHnd) -> i64 {
    (api().get_size)(hnd)
}

pub fn set_size(hnd: DataHnd, size: i64) {
    (api().set_size)(hnd, size)
}

pub fn create_app_hnd(name: &str, desc: &str) -> Result<AppHnd> {
    debug_log!("create_app_hnd: name='{}', desc='{}'", name, desc);
    let cname = CString::new(name).map_err(|_| ApiError::InvalidAppName)?;
    let cdesc = CString::new(desc).map_err(|_| ApiError::InvalidAppName)?;
    let ptr = (api().create_app_hnd)(cname.as_ptr(), cdesc.as_ptr());
    if ptr.is_null() {
        debug_log!("create_app_hnd returned null");
        Err(ApiError::NullHandle)
    } else {
        debug_log!("create_app_hnd succeeded: {:p}", ptr);
        Ok(ptr)
    }
}

pub fn free_app_hnd(hnd: AppHnd) {
    debug_log!("free_app_hnd: {:p}", hnd);
    if !hnd.is_null() {
        (api().free_app_hnd)(hnd);
    }
}

pub fn reg_call(app: AppHnd, api_name: &str, desc: &str, trigger: *mut c_void, callback: APICall) -> Result<()> {
    debug_log!("reg_call: app={:p}, api='{}'", app, api_name);
    let cname = CString::new(api_name).map_err(|_| ApiError::InvalidApiName)?;
    let cdesc = CString::new(desc).map_err(|_| ApiError::InvalidApiName)?;
    let ret = (api().reg_call)(app, cname.as_ptr(), cdesc.as_ptr(), trigger, callback);
    if ret == 0 {
        debug_log!("reg_call failed");
        Err(ApiError::RegistrationFailed)
    } else {
        debug_log!("reg_call succeeded");
        Ok(())
    }
}

pub fn reg_notify(app: AppHnd, api_name: &str, desc: &str, trigger: *mut c_void, callback: APINotify) -> Result<()> {
    debug_log!("reg_notify: app={:p}, api='{}'", app, api_name);
    let cname = CString::new(api_name).map_err(|_| ApiError::InvalidApiName)?;
    let cdesc = CString::new(desc).map_err(|_| ApiError::InvalidApiName)?;
    let ret = (api().reg_notify)(app, cname.as_ptr(), cdesc.as_ptr(), trigger, callback);
    if ret == 0 {
        debug_log!("reg_notify failed");
        Err(ApiError::RegistrationFailed)
    } else {
        debug_log!("reg_notify succeeded");
        Ok(())
    }
}

pub fn un_reg(app: AppHnd, api_name: &str) -> Result<()> {
    debug_log!("un_reg: app={:p}, api='{}'", app, api_name);
    let cname = CString::new(api_name).map_err(|_| ApiError::InvalidApiName)?;
    let ret = (api().un_reg)(app, cname.as_ptr());
    if ret == 0 {
        debug_log!("un_reg failed: API not found");
        Err(ApiError::UnregisterFailed)
    } else {
        debug_log!("un_reg succeeded");
        Ok(())
    }
}

pub fn local_app_call(app: AppHnd, param: DataHnd) -> Result<DataHnd> {
    debug_log!("local_app_call: app={:p}, param={:p}", app, param);
    let ptr = (api().local_app_call)(app, param);
    if ptr.is_null() {
        debug_log!("local_app_call returned null");
        Err(ApiError::NullHandle)
    } else {
        debug_log!("local_app_call succeeded: {:p}", ptr);
        Ok(ptr)
    }
}

pub fn local_app_notify(app: AppHnd, param: DataHnd) {
    debug_log!("local_app_notify: app={:p}, param={:p}", app, param);
    (api().local_app_notify)(app, param);
}

pub fn reset_prepare() {
    debug_log!("reset_prepare");
    (api().reset_prepare)();
}

pub fn prepare_service(listening: &str, physics: &str) -> Result<c_int> {
    debug_log!("prepare_service: listening='{}', physics='{}'", listening, physics);
    let c1 = CString::new(listening).map_err(|_| ApiError::InvalidApiName)?;
    let c2 = CString::new(physics).map_err(|_| ApiError::InvalidApiName)?;
    let ret = (api().prepare_service)(c1.as_ptr(), c2.as_ptr());
    debug_log!("prepare_service returned tag: {}", ret);
    Ok(ret)
}

pub fn prepare_client(physics: &str, app: AppHnd) -> Result<c_int> {
    debug_log!("prepare_client: physics='{}', app={:p}", physics, app);
    let c = CString::new(physics).map_err(|_| ApiError::InvalidApiName)?;
    let ret = (api().prepare_client)(c.as_ptr(), app);
    debug_log!("prepare_client returned tag: {}", ret);
    Ok(ret)
}

pub fn prepare_done() -> Result<()> {
    debug_log!("prepare_done starting");
    let ret = (api().prepare_done)();
    debug_log!("prepare_done returned: {}", ret);
    if ret == 1 {
        Ok(())
    } else {
        debug_log!("prepare_done failed");
        Err(ApiError::PrepareFailed)
    }
}

pub fn exit_main_thread() {
    debug_log!("exit_main_thread");
    (api().exit_main_thread)();
}

pub fn call(app_name: &str, param: DataHnd, timeout_ms: u64) -> Result<DataHnd> {
    debug_log!("call: app='{}', param={:p}, timeout={}", app_name, param, timeout_ms);
    let cname = CString::new(app_name).map_err(|_| ApiError::InvalidApiName)?;
    let ptr = (api().call)(cname.as_ptr(), param, timeout_ms);
    if ptr.is_null() {
        debug_log!("call returned null (should not happen per spec)");
        Err(ApiError::CallFailed)
    } else {
        debug_log!("call succeeded: {:p}", ptr);
        Ok(ptr)
    }
}

pub fn notify(app_name: &str, param: DataHnd) {
    debug_log!("notify: app='{}', param={:p}", app_name, param);
    let cname = CString::new(app_name).unwrap_or_default();
    (api().notify)(cname.as_ptr(), param);
}

pub fn set_option(option: &str, value: &str) {
    debug_log!("set_option: option='{}', value='{}'", option, value);
    let copt = CString::new(option).unwrap_or_default();
    let cval = CString::new(value).unwrap_or_default();
    (api().set_option)(copt.as_ptr(), cval.as_ptr());
}

pub fn shutdown() {
    debug_log!("shutdown");
    (api().shutdown)();
}

// ============================================================================
// 新增诊断与状态函数（补齐 Pascal 全部接口）
// 以下函数均提供中文注释
// ============================================================================

/// 返回内部状态队列中待读取的日志消息数量。
///
/// 此函数**线程安全**，可与 [`get_status`] 和 [`post_status`] 并发调用。
///
/// # 示例
/// ```
/// use api_hub_rust::{get_status_num, get_status};
/// let count = get_status_num().unwrap();
/// for _ in 0..count {
///     if let Ok(msg) = get_status() {
///         println!("日志: {}", msg);
///     }
/// }
/// ```
pub fn get_status_num() -> Result<i32> {
    debug_log!("get_status_num");
    Ok((api().get_status_num)())
}

/// 从状态队列中取出一条日志消息（FIFO 顺序）。
///
/// 返回的字符串是内部缓冲区的副本，后续调用不会影响其有效性。
/// 若队列为空，返回空字符串。
///
/// 此函数**线程安全**。
///
/// # 重要
/// - 消息长度超过 64 KB 会被截断。
/// - 内部队列最多容纳 1000 条消息，超出时丢弃旧消息。
///
/// # 示例
/// ```
/// use api_hub_rust::get_status;
/// if let Ok(msg) = get_status() {
///     println!("日志消息: {}", msg);
/// }
/// ```
pub fn get_status() -> Result<String> {
    debug_log!("get_status");
    let ptr = (api().get_status)();
    if ptr.is_null() {
        return Ok(String::new());
    }
    // 将 *const c_char 转换为 *const u8，以正确构造 &[u8]
    let ptr_u8 = ptr as *const u8;
    let mut len = 0;
    while unsafe { *ptr_u8.add(len) } != 0 {
        len += 1;
    }
    let slice = unsafe { std::slice::from_raw_parts(ptr_u8, len) };
    match std::str::from_utf8(slice) {
        Ok(s) => Ok(s.to_string()),
        Err(_) => {
            debug_log!("get_status: 无效 UTF‑8，以损失性方式返回原始字节");
            Ok(String::from_utf8_lossy(slice).into_owned())
        }
    }
}

/// 向内部状态队列中注入一条自定义日志消息。
///
/// 消息将追加到队列尾部，可通过 [`get_status`] 以 FIFO 顺序读取。
/// 适用于将外部日志与库自身的诊断信息合并。
///
/// 此函数**线程安全**。
///
/// # 示例
/// ```
/// use api_hub_rust::post_status;
/// post_status("来自 Rust 客户端的自定义消息").unwrap();
/// ```
pub fn post_status(status: &str) -> Result<()> {
    debug_log!("post_status: {}", status);
    let cstr = CString::new(status).map_err(|_| ApiError::InvalidApiName)?;
    (api().post_status)(cstr.as_ptr());
    Ok(())
}

/// 检查模拟主线程（C4 事件循环）是否正在运行。
///
/// 主线程在 [`prepare_done`] 成功后启动，在 [`exit_main_thread`] 或 [`shutdown`]
/// 调用后停止。
///
/// 此函数**线程安全**。
///
/// # 返回值
/// - `true` 表示主线程正在运行。
/// - `false` 表示已停止或尚未启动。
///
/// # 示例
/// ```
/// use api_hub_rust::check_main_thread;
/// if check_main_thread() {
///     println!("网络层已激活。");
/// } else {
///     println!("网络层未运行。");
/// }
/// ```
pub fn check_main_thread() -> bool {
    debug_log!("check_main_thread");
    (api().check_main_thread)() != 0
}

/// 检查网络中是否存在指定名称的应用。
///
/// 该查询基于本地缓存，可能略有过时（通常不超过 3 秒）。
/// 适用于快速探测目标是否在线，但不应用作严格的先决条件。
///
/// 应用名称**区分大小写**。
///
/// 此函数**线程安全**。
///
/// # 返回值
/// - `true` 表示存在至少一个实例。
/// - `false` 表示本地未知（可能离线或尚未发现）。
///
/// # 示例
/// ```
/// use api_hub_rust::check_app;
/// if check_app("CalcService") {
///     println!("CalcService 可用。");
/// } else {
///     println!("未找到 CalcService（或尚未发现）。");
/// }
/// ```
pub fn check_app(app_name: &str) -> bool {
    debug_log!("check_app: {}", app_name);
    let cstr = CString::new(app_name).unwrap_or_default();
    (api().check_app)(cstr.as_ptr()) != 0
}

// ============================================================================
// RAII 包装器
// ============================================================================

/// 数据句柄的 RAII 包装器。
///
/// # 所有权
/// - `owned = true`：在 `Drop` 时释放句柄。
/// - `owned = false`：在 `Drop` 时**不释放**句柄（借用）。
///
/// 详见模块级文档的所有权说明。
pub struct DataHandle {
    ptr: DataHnd,
    owned: bool,
}

impl DataHandle {
    /// 使用给定的 API 名称创建新的拥有型数据句柄。
    pub fn new(api_name: &str) -> Result<Self> {
        let ptr = create_data_hnd(api_name)?;
        Ok(DataHandle { ptr, owned: true })
    }

    /// 包装一个已有的原始句柄，**不获取所有权**（借用）。
    /// 调用者必须确保句柄在包装器生命周期内有效。
    /// 这是回调中 `input` 和 `output` 参数的正确构造方式。
    pub unsafe fn from_raw(ptr: DataHnd) -> Self {
        DataHandle { ptr, owned: false }
    }

    /// 包装一个已有的原始句柄，**获取所有权**。
    /// 包装器在析构时会释放句柄。这是 `call` 或 `local_app_call`
    /// 返回句柄的正确构造方式。
    pub unsafe fn from_owned_raw(ptr: DataHnd) -> Self {
        DataHandle { ptr, owned: true }
    }

    /// 返回原始句柄（借用）。
    pub fn as_raw(&self) -> DataHnd {
        self.ptr
    }

    /// 向句柄缓冲区写入原始字节（当前位置）。
    /// 允许在拥有型和借用型句柄上使用。
    pub fn write(&mut self, data: &[u8]) -> Result<usize> {
        write_buffer(self.ptr, data)
    }

    /// 从句柄缓冲区读取原始字节到提供的切片中。
    pub fn read(&mut self, buf: &mut [u8]) -> Result<usize> {
        read_buffer(self.ptr, buf)
    }

    pub fn pos(&self) -> i64 {
        get_pos(self.ptr)
    }

    /// 设置读写位置。允许在拥有型和借用型句柄上使用。
    pub fn set_pos(&self, pos: i64) {
        set_pos(self.ptr, pos)
    }

    pub fn size(&self) -> i64 {
        get_size(self.ptr)
    }

    /// 设置缓冲区大小。允许在拥有型和借用型句柄上使用。
    pub fn set_size(&self, size: i64) {
        set_size(self.ptr, size)
    }

    pub fn buffer(&self) -> *mut c_void {
        (api().get_buffer)(self.ptr)
    }

    // ----- 便捷类型辅助（已有）-----
    pub fn write_i32(&mut self, v: i32) -> Result<()> {
        self.write(&v.to_le_bytes())?;
        Ok(())
    }

    pub fn read_i32(&mut self) -> Result<i32> {
        let mut b = [0u8; 4];
        self.read(&mut b)?;
        Ok(i32::from_le_bytes(b))
    }

    pub fn write_i64(&mut self, v: i64) -> Result<()> {
        self.write(&v.to_le_bytes())?;
        Ok(())
    }

    pub fn read_i64(&mut self) -> Result<i64> {
        let mut b = [0u8; 8];
        self.read(&mut b)?;
        Ok(i64::from_le_bytes(b))
    }

    pub fn write_f64(&mut self, v: f64) -> Result<()> {
        self.write(&v.to_le_bytes())?;
        Ok(())
    }

    pub fn read_f64(&mut self) -> Result<f64> {
        let mut b = [0u8; 8];
        self.read(&mut b)?;
        Ok(f64::from_le_bytes(b))
    }

    pub fn write_string(&mut self, s: &str) -> Result<()> {
        let bytes = s.as_bytes();
        self.write_i32(bytes.len() as i32)?;
        self.write(bytes)?;
        Ok(())
    }

    pub fn read_string(&mut self) -> Result<String> {
        let len = self.read_i32()?;
        if len < 0 {
            return Err(ApiError::ReadFailed);
        }
        let mut buf = vec![0u8; len as usize];
        self.read(&mut buf)?;
        String::from_utf8(buf).map_err(|_| ApiError::ReadFailed)
    }

    // ========================================================================
    // 原子类型辅助（兼容 Pascal，小端序）
    // 所有写方法均允许在拥有型和借用型句柄上使用。
    // ========================================================================

    pub fn write_int8(&mut self, v: i8) -> Result<()> {
        let written = self.write(&[v as u8])?;
        if written == 1 { Ok(()) } else { Err(ApiError::WriteFailed) }
    }

    pub fn write_uint8(&mut self, v: u8) -> Result<()> {
        let written = self.write(&[v])?;
        if written == 1 { Ok(()) } else { Err(ApiError::WriteFailed) }
    }

    pub fn write_int16(&mut self, v: i16) -> Result<()> {
        let written = self.write(&v.to_le_bytes())?;
        if written == 2 { Ok(()) } else { Err(ApiError::WriteFailed) }
    }

    pub fn write_uint16(&mut self, v: u16) -> Result<()> {
        let written = self.write(&v.to_le_bytes())?;
        if written == 2 { Ok(()) } else { Err(ApiError::WriteFailed) }
    }

    pub fn write_int32(&mut self, v: i32) -> Result<()> {
        self.write_i32(v)
    }

    pub fn write_uint32(&mut self, v: u32) -> Result<()> {
        let written = self.write(&v.to_le_bytes())?;
        if written == 4 { Ok(()) } else { Err(ApiError::WriteFailed) }
    }

    pub fn write_int64(&mut self, v: i64) -> Result<()> {
        self.write_i64(v)
    }

    pub fn write_uint64(&mut self, v: u64) -> Result<()> {
        let written = self.write(&v.to_le_bytes())?;
        if written == 8 { Ok(()) } else { Err(ApiError::WriteFailed) }
    }

    pub fn write_single(&mut self, v: f32) -> Result<()> {
        let written = self.write(&v.to_le_bytes())?;
        if written == 4 { Ok(()) } else { Err(ApiError::WriteFailed) }
    }

    pub fn write_double(&mut self, v: f64) -> Result<()> {
        self.write_f64(v)
    }

    pub fn write_string_null_terminated(&mut self, s: &str) -> Result<()> {
        let bytes = s.as_bytes();
        let written = self.write(bytes)?;
        if written != bytes.len() {
            return Err(ApiError::WriteFailed);
        }
        let nwritten = self.write(&[0])?;
        if nwritten == 1 {
            Ok(())
        } else {
            Err(ApiError::WriteFailed)
        }
    }

    // ----- 原子读取 -----

    pub fn read_int8(&mut self) -> Result<i8> {
        let mut b = [0u8; 1];
        let n = self.read(&mut b)?;
        if n == 1 { Ok(b[0] as i8) } else { Err(ApiError::ReadFailed) }
    }

    pub fn read_uint8(&mut self) -> Result<u8> {
        let mut b = [0u8; 1];
        let n = self.read(&mut b)?;
        if n == 1 { Ok(b[0]) } else { Err(ApiError::ReadFailed) }
    }

    pub fn read_int16(&mut self) -> Result<i16> {
        let mut b = [0u8; 2];
        let n = self.read(&mut b)?;
        if n == 2 { Ok(i16::from_le_bytes(b)) } else { Err(ApiError::ReadFailed) }
    }

    pub fn read_uint16(&mut self) -> Result<u16> {
        let mut b = [0u8; 2];
        let n = self.read(&mut b)?;
        if n == 2 { Ok(u16::from_le_bytes(b)) } else { Err(ApiError::ReadFailed) }
    }

    pub fn read_int32(&mut self) -> Result<i32> {
        self.read_i32()
    }

    pub fn read_uint32(&mut self) -> Result<u32> {
        let mut b = [0u8; 4];
        let n = self.read(&mut b)?;
        if n == 4 { Ok(u32::from_le_bytes(b)) } else { Err(ApiError::ReadFailed) }
    }

    pub fn read_int64(&mut self) -> Result<i64> {
        self.read_i64()
    }

    pub fn read_uint64(&mut self) -> Result<u64> {
        let mut b = [0u8; 8];
        let n = self.read(&mut b)?;
        if n == 8 { Ok(u64::from_le_bytes(b)) } else { Err(ApiError::ReadFailed) }
    }

    pub fn read_single(&mut self) -> Result<f32> {
        let mut b = [0u8; 4];
        let n = self.read(&mut b)?;
        if n == 4 { Ok(f32::from_le_bytes(b)) } else { Err(ApiError::ReadFailed) }
    }

    pub fn read_double(&mut self) -> Result<f64> {
        self.read_f64()
    }

    pub fn read_string_null_terminated(&mut self) -> Result<String> {
        let size = self.size();
        let pos = self.pos();
        if pos >= size {
            return Ok(String::new());
        }
        let remaining = (size - pos) as usize;
        let mut buf = vec![0u8; remaining];
        let n = self.read(&mut buf)?;
        if n == 0 {
            return Ok(String::new());
        }
        if let Some(nul_offset) = buf[0..n].iter().position(|&b| b == 0) {
            let string_bytes = &buf[0..nul_offset];
            self.set_pos(pos + nul_offset as i64 + 1);
            Ok(String::from_utf8_lossy(string_bytes).into_owned())
        } else {
            self.set_pos(pos);
            Err(ApiError::ReadFailed)
        }
    }
}

impl Drop for DataHandle {
    fn drop(&mut self) {
        if self.owned && !self.ptr.is_null() {
            debug_log!("DataHandle drop: freeing owned ptr {:p}", self.ptr);
            free_data_hnd(self.ptr);
        } else if !self.owned && !self.ptr.is_null() {
            debug_log!("DataHandle drop: borrowed ptr {:p} NOT freed", self.ptr);
        }
    }
}

unsafe impl Send for DataHandle {}
unsafe impl Sync for DataHandle {}

/// 应用句柄的 RAII 包装器。析构时自动释放句柄。
pub struct AppHandle(AppHnd);

impl AppHandle {
    pub fn new(name: &str, desc: &str) -> Result<Self> {
        let ptr = create_app_hnd(name, desc)?;
        Ok(AppHandle(ptr))
    }

    pub fn as_raw(&self) -> AppHnd {
        self.0
    }

    pub fn register_call(
        &self,
        api_name: &str,
        desc: &str,
        trigger: *mut c_void,
        callback: APICall,
    ) -> Result<()> {
        reg_call(self.0, api_name, desc, trigger, callback)
    }

    pub fn register_notify(
        &self,
        api_name: &str,
        desc: &str,
        trigger: *mut c_void,
        callback: APINotify,
    ) -> Result<()> {
        reg_notify(self.0, api_name, desc, trigger, callback)
    }

    pub fn unregister(&self, api_name: &str) -> Result<()> {
        un_reg(self.0, api_name)
    }

    pub fn local_call(&self, param: &DataHandle) -> Result<DataHandle> {
        let ptr = local_app_call(self.0, param.as_raw())?;
        Ok(unsafe { DataHandle::from_owned_raw(ptr) })
    }

    pub fn local_notify(&self, param: &DataHandle) {
        local_app_notify(self.0, param.as_raw());
    }
}

impl Drop for AppHandle {
    fn drop(&mut self) {
        if !self.0.is_null() {
            free_app_hnd(self.0);
        }
    }
}

unsafe impl Send for AppHandle {}
unsafe impl Sync for AppHandle {}

// ============================================================================
// 测试运行器模块（导出）
// ============================================================================

pub mod test_runner;