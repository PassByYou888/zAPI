// examples/calc_server.rs
use api_hub_rust::*;
use std::ffi::c_void;
use std::io::{self, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

extern "C" fn add_callback(_trigger: *mut c_void, input: DataHnd, output: DataHnd) {
    let mut h = unsafe { DataHandle::from_raw(input) };
    let a = h.read_i32().unwrap_or(0);
    let b = h.read_i32().unwrap_or(0);
    let sum = a + b;
    let _ = write_buffer(output, &sum.to_le_bytes());
    println!("[Calc] add({}, {}) = {}", a, b, sum);
}
extern "C" fn sub_callback(_trigger: *mut c_void, input: DataHnd, output: DataHnd) {
    let mut h = unsafe { DataHandle::from_raw(input) };
    let a = h.read_i32().unwrap_or(0);
    let b = h.read_i32().unwrap_or(0);
    let diff = a - b;
    let _ = write_buffer(output, &diff.to_le_bytes());
    println!("[Calc] sub({}, {}) = {}", a, b, diff);
}
extern "C" fn mul_callback(_trigger: *mut c_void, input: DataHnd, output: DataHnd) {
    let mut h = unsafe { DataHandle::from_raw(input) };
    let a = h.read_i32().unwrap_or(0);
    let b = h.read_i32().unwrap_or(0);
    let prod = a * b;
    let _ = write_buffer(output, &prod.to_le_bytes());
    println!("[Calc] mul({}, {}) = {}", a, b, prod);
}
extern "C" fn div_callback(_trigger: *mut c_void, input: DataHnd, output: DataHnd) {
    let mut h = unsafe { DataHandle::from_raw(input) };
    let a = h.read_i32().unwrap_or(0);
    let b = h.read_i32().unwrap_or(0);
    let quot = if b == 0 { 0 } else { a / b };
    let _ = write_buffer(output, &quot.to_le_bytes());
    println!("[Calc] div({}, {}) = {}", a, b, quot);
}

fn main() -> Result<()> {
    println!("[Calc] 服务端启动中...");
    let app = AppHandle::new("CalcService", "Calculator service")?;
    app.register_call("add", "a+b", std::ptr::null_mut(), add_callback)?;
    app.register_call("sub", "a-b", std::ptr::null_mut(), sub_callback)?;
    app.register_call("mul", "a*b", std::ptr::null_mut(), mul_callback)?;
    app.register_call("div", "a/b", std::ptr::null_mut(), div_callback)?;
    println!("[Calc] API 注册完成");

    reset_prepare();
    let listen = "0.0.0.0";
    let physics = "127.0.0.1:9903";
    prepare_service(listen, physics)?;
    prepare_client(physics, app.as_raw())?;
    prepare_done()?;

    // 状态信息由库自动打印到控制台
    println!("[Calc] 服务已启动 ({} -> {}), 按 Ctrl+C 或输入 'exit' 退出", listen, physics);

    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();
    ctrlc::set_handler(move || {
        eprintln!("\n[Calc] 收到 Ctrl+C 信号，正在退出...");
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
                    eprintln!("[Calc] 收到 'exit' 命令，正在退出...");
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

    println!("[Calc] 正在关闭服务（超时 1 秒）...");
    let shutdown_start = Instant::now();
    let shutdown_timeout = Duration::from_secs(1);
    let handle = thread::spawn(|| { exit_main_thread(); shutdown(); });
    while !handle.is_finished() {
        if shutdown_start.elapsed() > shutdown_timeout {
            eprintln!("[Calc] 关闭超时，强制终止进程（退出码 0）");
            let _ = std::io::stdout().flush();
            std::process::exit(0);
        }
        thread::sleep(Duration::from_millis(50));
    }
    let _ = handle.join();
    println!("[Calc] 服务已正常停止");
    Ok(())
}