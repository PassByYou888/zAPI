// examples/config_server.rs
use api_hub_rust::*;
use std::collections::HashMap;
use std::ffi::c_void;
use std::io::{self, Write};
use std::sync::{Arc, Mutex, OnceLock};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

static CONFIG: OnceLock<Arc<Mutex<HashMap<String, String>>>> = OnceLock::new();
fn get_config() -> &'static Arc<Mutex<HashMap<String, String>>> {
    CONFIG.get_or_init(|| Arc::new(Mutex::new(HashMap::new())))
}

extern "C" fn set_callback(_trigger: *mut c_void, input: DataHnd) {
    let mut h = unsafe { DataHandle::from_raw(input) };
    let key = h.read_string_null_terminated().unwrap_or_default();
    let val = h.read_string_null_terminated().unwrap_or_default();
    let mut map = get_config().lock().unwrap();
    map.insert(key.clone(), val.clone());
    println!("[Config] set {} = {}", key, val);
}
extern "C" fn get_callback(_trigger: *mut c_void, input: DataHnd, output: DataHnd) {
    let mut h = unsafe { DataHandle::from_raw(input) };
    let key = h.read_string_null_terminated().unwrap_or_default();
    let map = get_config().lock().unwrap();
    let val = map.get(&key).cloned().unwrap_or_default();
    let _ = write_buffer(output, val.as_bytes());
}

fn main() -> Result<()> {
    println!("[Config] 服务端启动中...");
    let app = AppHandle::new("ConfigService", "Config center")?;
    app.register_notify("set", "Set config", std::ptr::null_mut(), set_callback)?;
    app.register_call("get", "Get config", std::ptr::null_mut(), get_callback)?;
    println!("[Config] API 注册完成");

    reset_prepare();
    let listen = "0.0.0.0";
    let physics = "127.0.0.1:9907";
    prepare_service(listen, physics)?;
    prepare_client(physics, app.as_raw())?;
    prepare_done()?;

    // 状态信息由库自动打印到控制台
    println!("[Config] 服务已启动 ({} -> {}), 按 Ctrl+C 或输入 'exit' 退出", listen, physics);

    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();
    ctrlc::set_handler(move || {
        eprintln!("\n[Config] 收到 Ctrl+C 信号，正在退出...");
        r.store(false, Ordering::SeqCst);
    }).expect("设置 Ctrl+C 处理器失败");

    let (tx, rx) = std::sync::mpsc::channel();
    let r2 = running.clone();
    thread::spawn(move || {
        let mut input = String::new();
        while r2.load(Ordering::SeqCst) {
            input.clear();
            if let Ok(bytes) = io::stdin().read_line(&mut input) {
                if bytes == 0 { break; }
                if input.trim() == "exit" || input.trim() == "quit" {
                    eprintln!("[Config] 收到 'exit' 命令，正在退出...");
                    let _ = tx.send(());
                    break;
                }
            }
        }
    });

    while running.load(Ordering::SeqCst) {
        if let Ok(_) = rx.try_recv() {
            running.store(false, Ordering::SeqCst);
            break;
        }
        thread::sleep(Duration::from_millis(100));
    }

    println!("[Config] 正在关闭服务（超时 1 秒）...");
    let shutdown_start = Instant::now();
    let shutdown_timeout = Duration::from_secs(1);
    let handle = thread::spawn(|| { exit_main_thread(); shutdown(); });
    while !handle.is_finished() {
        if shutdown_start.elapsed() > shutdown_timeout {
            eprintln!("[Config] 关闭超时，强制终止进程（退出码 0）");
            let _ = std::io::stdout().flush();
            std::process::exit(0);
        }
        thread::sleep(Duration::from_millis(50));
    }
    let _ = handle.join();
    println!("[Config] 服务已正常停止");
    Ok(())
}