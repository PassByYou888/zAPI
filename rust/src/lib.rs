//! API Hub Rust Bindings – Dynamic Loading Edition
//!
//! This crate provides a safe Rust interface to the API Hub C library
//! (`z_api_hub64.dll` on Windows, `libz_api_hub.so` on Linux/BSD,
//! `libz_api_hub.dylib` on macOS). The library is loaded at runtime
//! and all functions are accessed through raw pointers stored in a static
//! `Api` struct. RAII wrappers (`DataHandle`, `AppHandle`) are provided
//! for automatic resource management.
//!
//! # Thread Safety (based on the C ABI specification)
//!
//! **All functions are fully thread‑safe** and can be called concurrently
//! from any number of threads. This matches the behaviour of the underlying
//! C library. For a given `DataHandle`, write operations (`write`, `set_pos`,
//! `set_size`) should be serialised across threads, but read operations are
//! safe concurrently.
//!
//! # Callback Restrictions (CRITICAL)
//!
//! Callbacks registered with [`reg_call`] and [`reg_notify`] are executed
//! in background threads from the library's internal thread pool.
//!
//! - **DO NOT** call [`call`] or [`notify`] from inside a callback – this
//!   may cause deadlocks because the callback may hold internal locks.
//! - **DO NOT** perform long‑blocking operations (e.g., `sleep`, heavy loops,
//!   waiting on events) inside callbacks.
//! - **DO NOT** access UI components or thread‑local storage without proper
//!   synchronisation (e.g., using channels or message queues).
//! - Offload heavy work to a separate thread or queue and return quickly.
//!
//! # Performance
//!
//! For lightweight calls (no heavy payloads), the library can sustain
//! approximately 3000 requests per second in typical configurations.
//! Use IPC (`ipc:...`) for same‑machine communication to achieve
//! sub‑millisecond latencies. Reuse `DataHandle` objects where possible
//! to reduce allocation overhead.
//!
//! # Execution Order
//!
//! The library **does not guarantee** the order of execution for concurrent
//! calls. Requests may be processed out‑of‑order due to load balancing and
//! threading. If your application depends on a specific order, you must
//! implement your own sequencing (e.g., sequence numbers or serialisation).
//!
//! # Error Diagnosis
//!
//! The library prints detailed diagnostic messages to the console (stdout/stderr)
//! by default. You can control logging behaviour via the
//! `<executable>.api-tool.ini` configuration file, which is auto‑generated
//! on first run, or by using [`set_option`] to adjust settings at runtime.
//!
//! # Runtime Options (via [`set_option`])
//!
//! Supported keys (case‑insensitive, aliases accepted):
//! - `"password" / "passwd"` : Sets the C4 P2PVM authentication token.
//!   Must match on both service and client sides. Affects new connections only.
//! - `"Quiet"` : Enable/disable quiet mode (True/False). Suppresses debug logs.
//! - `"External_Conf_Auto_Save" / "Conf_Auto_Save"` : Auto‑save .ini on exit (True/False).
//! - `"Wait_Connection_ReadyOk" / "Wait_API_Prepare_Done" / ...` :
//!   Controls whether [`prepare_done`] blocks until all clients are connected.
//!   When False, clients auto‑connect later (important for deployment).
//! - `"Wait_Connection_Timeout" / "Wait_TimeOut"` : Max wait (ms) when the above is True.
//! - `"ShowThreadID" / "ShowThread" / "Show_Thread"` : Show thread IDs in logs.
//! - `"ConsoleOutput" / "Console_Output"` : Enable/disable console logging.
//! - `"IPC_Serv_ThreadCount" / "IPC_ThreadCount" / "IPC_Server_ThreadCount"` :
//!   Number of threads in the IPC service thread pool.
//! - `"IPC_Serv_MaxQueueLength" / "IPC_MaxQueueLength" / "IPC_Server_MaxQueueLength"` :
//!   Max IPC queue length.
//! - `"IPC_Serv_MaxMsgSize" / "IPC_MaxMsgSize" / "IPC_Server_MaxMsgSize"` :
//!   Max IPC message size (bytes).
//!
//! # Example
//!
//! ```
//! use api_hub::*;
//!
//! // Set a runtime option before starting
//! set_option("Wait_Connection_ReadyOk", "False");
//!
//! // Create an application and register an 'echo' API
//! let app = AppHandle::new("MyApp", "Example application")?;
//! app.register_call("echo", "Echoes input", std::ptr::null_mut(), echo_callback)?;
//!
//! // Prepare network and start the framework
//! reset_prepare();
//! prepare_service("0.0.0.0:9898", "127.0.0.1:9898")?;
//! prepare_client("127.0.0.1:9898", app.as_raw())?;
//! prepare_done()?;
//!
//! // Later, dynamically unregister the 'echo' API
//! app.unregister("echo")?;
//!
//! // Make a remote call
//! let mut data = DataHandle::new("echo")?;
//! data.write(b"Hello, world!")?;
//! let result = call("MyApp", data.as_raw(), 5000)?;
//! // Note: result is always a valid handle; check its size for success.
//! // ...
//! # Ok::<(), ApiError>(())
//! ```

#![allow(static_mut_refs)]
#![allow(unused_unsafe)]

use libloading::Library;
use std::ffi::{CStr, CString, c_char, c_int, c_void, c_ulonglong};
use std::sync::Once;

// ============================================================================
// Conditional debug logging macro (exported for external use)
// ============================================================================

/// Debug log: prints to stderr when `debug-log` feature is enabled.
#[macro_export]
macro_rules! debug_log {
    ($($arg:tt)*) => {
        if cfg!(feature = "debug-log") {
            eprintln!("[DEBUG] {}", format!($($arg)*));
        }
    };
}

// ============================================================================
// Type Definitions
// ============================================================================

/// Opaque handle to a data buffer that holds an API name and its binary payload.
/// Created with `create_data_hnd`, freed with `free_data_hnd` (or via `DataHandle` RAII).
pub type DataHnd = *mut c_void;

/// Opaque handle to an application context that groups a set of APIs.
/// Created with `create_app_hnd`, freed with `free_app_hnd` (or via `AppHandle` RAII).
pub type AppHnd = *mut c_void;

/// Callback signature for request‑response (call) APIs.
///
/// # Safety
///
/// The callback must be `extern "C"` and must **not** call [`call`] or [`notify`]
/// recursively (deadlock risk). It should return quickly; heavy processing
/// should be delegated to another thread.
///
/// # Parameters
///
/// - `trigger`: user‑supplied pointer (as given to [`reg_call`]).
/// - `input`:   read‑only data handle containing the request payload.
/// - `output`:  write‑only data handle where the response must be written.
pub type APICall = extern "C" fn(*mut c_void, DataHnd, DataHnd);

/// Callback signature for one‑way notification (notify) APIs.
///
/// Same safety restrictions as [`APICall`] – no recursive calls, no blocking.
pub type APINotify = extern "C" fn(*mut c_void, DataHnd);

// ============================================================================
// Error Types
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
// Global API Function Pointers
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
    un_reg: fn(AppHnd, *const c_char) -> c_int,                          // NEW
    local_app_call: fn(AppHnd, DataHnd) -> DataHnd,
    local_app_notify: fn(AppHnd, DataHnd),

    prepare_service: fn(*const c_char, *const c_char) -> c_int,
    prepare_client: fn(*const c_char, AppHnd) -> c_int,
    reset_prepare: fn(),
    prepare_done: fn() -> c_int,
    exit_main_thread: fn(),
    call: fn(*const c_char, DataHnd, c_ulonglong) -> DataHnd,
    notify: fn(*const c_char, DataHnd),
    set_option: fn(*const c_char, *const c_char),                        // NEW
    shutdown: fn(),
}

static mut API: Option<Api> = None;
static INIT: Once = Once::new();

// ============================================================================
// Library Loading
// ============================================================================

#[cfg(target_os = "windows")]
const LIB_NAME: &str = "z_api_hub64.dll";
#[cfg(target_os = "linux")]
const LIB_NAME: &str = "z_api_hub.so";
#[cfg(target_os = "macos")]
const LIB_NAME: &str = "z_api_hub.dylib";
// BSD support (the library name is the same as on Linux)
#[cfg(any(target_os = "freebsd", target_os = "openbsd", target_os = "netbsd"))]
const LIB_NAME: &str = "z_api_hub.so";

/// Attempt to load the library from a set of candidate paths.
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
        let un_reg = get_fn!(lib, "API_UnReg", fn(AppHnd, *const c_char) -> c_int);  // NEW
        let local_app_call = get_fn!(lib, "API_Local_APP_Call", fn(AppHnd, DataHnd) -> DataHnd);
        let local_app_notify = get_fn!(lib, "API_Local_APP_Notify", fn(AppHnd, DataHnd));

        let prepare_service = get_fn!(lib, "API_Prepare_Service", fn(*const c_char, *const c_char) -> c_int);
        let prepare_client = get_fn!(lib, "API_Prepare_Client", fn(*const c_char, AppHnd) -> c_int);
        let reset_prepare = get_fn!(lib, "API_Reset_Prepare", fn());
        let prepare_done = get_fn!(lib, "API_Prepare_Done", fn() -> c_int);
        let exit_main_thread = get_fn!(lib, "API_Exit_MainThread", fn());
        let call = get_fn!(lib, "API_Call", fn(*const c_char, DataHnd, c_ulonglong) -> DataHnd);
        let notify = get_fn!(lib, "API_Notify", fn(*const c_char, DataHnd));
        let set_option = get_fn!(lib, "API_SetOption", fn(*const c_char, *const c_char));  // NEW
        let shutdown = get_fn!(lib, "API_shutdown", fn());

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
// Public API Functions (with logging)
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

/// Unregisters a previously registered API from the application.
///
/// The API is **immediately** removed from the local registry and a network
/// broadcast is triggered. Remote peers will stop seeing this API within
/// approximately 3 seconds (depending on network latency and the C4 update
/// interval). During that short window, remote calls may still be attempted;
/// they will fail gracefully (the remote side will receive a "not found" error).
///
/// Use this function to dynamically unload plugins, temporarily disable
/// services, or adjust exposed functionality at runtime without restarting
/// the application.
///
/// # Arguments
/// * `app`    - application handle
/// * `api_name` - name of the API to unregister (UTF‑8)
///
/// # Returns
/// `Ok(())` if the API was found and unregistered, or an `ApiError::UnregisterFailed`
/// if the API name does not exist.
///
/// # Thread safety
/// This function is thread‑safe.
///
/// # Example
/// ```
/// # use api_hub::*;
/// # let app = AppHandle::new("MyApp", "")?;
/// app.unregister("temp_api")?;
/// # Ok::<(), ApiError>(())
/// ```
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

/// Note: The return value is a service tag (tag seed); 0 is a valid tag and does not indicate failure.
pub fn prepare_service(listening: &str, physics: &str) -> Result<c_int> {
    debug_log!("prepare_service: listening='{}', physics='{}'", listening, physics);
    let c1 = CString::new(listening).map_err(|_| ApiError::InvalidApiName)?;
    let c2 = CString::new(physics).map_err(|_| ApiError::InvalidApiName)?;
    let ret = (api().prepare_service)(c1.as_ptr(), c2.as_ptr());
    debug_log!("prepare_service returned tag: {}", ret);
    Ok(ret)
}

/// Note: The return value is a client tag; 0 is valid and not an error.
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

/// Performs a remote (or local) call to the specified application.
///
/// **Important**: The returned handle is **never `null`**. If the call times out
/// or fails, the handle will have size 0 (check with `get_size`). The caller
/// must always free the returned handle (via `DataHandle` or `free_data_hnd`).
///
/// This function is fully thread‑safe.
pub fn call(app_name: &str, param: DataHnd, timeout_ms: u64) -> Result<DataHnd> {
    debug_log!("call: app='{}', param={:p}, timeout={}", app_name, param, timeout_ms);
    let cname = CString::new(app_name).map_err(|_| ApiError::InvalidApiName)?;
    let ptr = (api().call)(cname.as_ptr(), param, timeout_ms);
    // The C ABI guarantees that ptr is never null; this check is defensive.
    if ptr.is_null() {
        debug_log!("call returned null (should not happen per spec)");
        Err(ApiError::CallFailed)
    } else {
        debug_log!("call succeeded: {:p}", ptr);
        Ok(ptr)
    }
}

/// Sends a one‑way notification to the specified application.
///
/// This function returns immediately and does not wait for a response.
/// Delivery is best‑effort. It is thread‑safe.
pub fn notify(app_name: &str, param: DataHnd) {
    debug_log!("notify: app='{}', param={:p}", app_name, param);
    let cname = CString::new(app_name).unwrap_or_default();
    (api().notify)(cname.as_ptr(), param);
}

/// Dynamically adjusts global runtime options of the API Hub framework.
///
/// All changes take effect immediately for subsequent operations (except where
/// noted). This function is intended for runtime tuning without restarting the
/// application or modifying the .ini file. Unknown options are silently ignored.
///
/// # Supported Options
///
/// | Option key (case‑insensitive) | Aliases | Value type | Description |
/// |-------------------------------|---------|------------|-------------|
/// | `"password"` | `"passwd"` | String | Sets the C4 P2PVM authentication token. Must match on both service and client sides. Affects new connections only. |
/// | `"Quiet"` | - | Boolean | Enable/disable quiet mode (True/False). Suppresses debug logs. |
/// | `"External_Conf_Auto_Save"` | `"Conf_Auto_Save"` | Boolean | Auto‑save .ini on exit (True/False). Default True. |
/// | `"Wait_Connection_ReadyOk"` | `"Wait_API_Prepare_Done"`, `"API_Prepare_Done_Wait"`, `"WaitConnect"`, `"Wait_Ready"`, `"WaitReady"` | Boolean | Controls whether `prepare_done` blocks until all clients are connected. When False, clients auto‑connect later (important for deployment). |
/// | `"Wait_Connection_Timeout"` | `"Wait_TimeOut"`, `"API_Prepare_Done_TimeOut"`, `"WaitTimeOut"` | Integer (ms) | Max wait time when `Wait_Connection_ReadyOk` is True. Default 30000. |
/// | `"ShowThreadID"` | `"ShowThread"`, `"Show_Thread"` | Boolean | Show thread IDs in logs. |
/// | `"ConsoleOutput"` | `"Console_Output"` | Boolean | Enable/disable console logging. |
/// | `"IPC_Serv_ThreadCount"` | `"IPC_ThreadCount"`, `"IPC_Server_ThreadCount"` | Integer | Number of threads in the IPC service thread pool. |
/// | `"IPC_Serv_MaxQueueLength"` | `"IPC_MaxQueueLength"`, `"IPC_Server_MaxQueueLength"` | Integer | Max IPC queue length. |
/// | `"IPC_Serv_MaxMsgSize"` | `"IPC_MaxMsgSize"`, `"IPC_Server_MaxMsgSize"` | Integer (bytes) | Max IPC message size. |
///
/// For boolean options, accepted values: `"True"`/`"False"`, `"1"`/`"0"`, `"Yes"`/`"No"`.
///
/// # Thread safety
/// This function is thread‑safe.
///
/// # Example
/// ```
/// # use api_hub::set_option;
/// set_option("password", "my_secret_token");
/// set_option("Wait_Connection_ReadyOk", "False");
/// set_option("Quiet", "True");
/// ```
pub fn set_option(option: &str, value: &str) {
    debug_log!("set_option: option='{}', value='{}'", option, value);
    let copt = CString::new(option).unwrap_or_default();
    let cval = CString::new(value).unwrap_or_default();
    (api().set_option)(copt.as_ptr(), cval.as_ptr());
}

/// Gracefully shuts down the entire API Hub framework.
///
/// This function stops all services, disconnects clients, and releases resources.
/// After shutdown, the library can be re‑initialised by calling preparation functions again.
pub fn shutdown() {
    debug_log!("shutdown");
    (api().shutdown)();
}

// ============================================================================
// RAII Wrappers
// ============================================================================

/// RAII wrapper for a data handle. Automatically frees the handle on drop.
pub struct DataHandle(DataHnd);

impl DataHandle {
    /// Creates a new data handle with the given API name.
    pub fn new(api_name: &str) -> Result<Self> {
        let ptr = create_data_hnd(api_name)?;
        Ok(DataHandle(ptr))
    }

    /// Wraps an existing raw handle without taking ownership.
    /// The caller is responsible for ensuring the handle is valid.
    pub unsafe fn from_raw(ptr: DataHnd) -> Self {
        DataHandle(ptr)
    }

    /// Returns the raw handle (borrowed).
    pub fn as_raw(&self) -> DataHnd {
        self.0
    }

    /// Writes data to the handle's buffer at the current position.
    pub fn write(&mut self, data: &[u8]) -> Result<usize> {
        write_buffer(self.0, data)
    }

    /// Reads data from the handle's buffer into the provided slice.
    pub fn read(&mut self, buf: &mut [u8]) -> Result<usize> {
        read_buffer(self.0, buf)
    }

    pub fn pos(&self) -> i64 {
        get_pos(self.0)
    }

    pub fn set_pos(&self, pos: i64) {
        set_pos(self.0, pos)
    }

    pub fn size(&self) -> i64 {
        get_size(self.0)
    }

    pub fn set_size(&self, size: i64) {
        set_size(self.0, size)
    }

    pub fn buffer(&self) -> *mut c_void {
        (api().get_buffer)(self.0)
    }

    // Convenience typed helpers
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

    /// Writes a string as a length‑prefixed (i32) UTF‑8 byte sequence.
    pub fn write_string(&mut self, s: &str) -> Result<()> {
        let bytes = s.as_bytes();
        self.write_i32(bytes.len() as i32)?;
        self.write(bytes)?;
        Ok(())
    }

    /// Reads a length‑prefixed string.
    pub fn read_string(&mut self) -> Result<String> {
        let len = self.read_i32()?;
        if len < 0 {
            return Err(ApiError::ReadFailed);
        }
        let mut buf = vec![0u8; len as usize];
        self.read(&mut buf)?;
        String::from_utf8(buf).map_err(|_| ApiError::ReadFailed)
    }
}

impl Drop for DataHandle {
    fn drop(&mut self) {
        if !self.0.is_null() {
            free_data_hnd(self.0);
        }
    }
}

unsafe impl Send for DataHandle {}
unsafe impl Sync for DataHandle {}

/// RAII wrapper for an application handle. Automatically frees the handle on drop.
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

    /// Unregisters a previously registered API from this application.
    ///
    /// This method wraps [`un_reg`]. See its documentation for details on
    /// immediate local removal and asynchronous network broadcast.
    ///
    /// # Example
    /// ```
    /// # use api_hub::*;
    /// # let app = AppHandle::new("MyApp", "")?;
    /// app.unregister("old_api")?;
    /// # Ok::<(), ApiError>(())
    /// ```
    pub fn unregister(&self, api_name: &str) -> Result<()> {
        un_reg(self.0, api_name)
    }

    pub fn local_call(&self, param: &DataHandle) -> Result<DataHandle> {
        let ptr = local_app_call(self.0, param.as_raw())?;
        Ok(unsafe { DataHandle::from_raw(ptr) })
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
// Test Runner Module (exported)
// ============================================================================

pub mod test_runner;