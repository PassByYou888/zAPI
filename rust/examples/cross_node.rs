// examples/cross_node.rs
use api_hub_rust::*;
use std::ffi::c_void;
use std::io::{self, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

extern "C" fn add_callback(_trigger: *mut c_void, input: DataHnd, output: DataHnd) {
    // Borrowed handles – do NOT free them.
    let mut h_in = unsafe { DataHandle::from_raw(input) };
    let mut h_out = unsafe { DataHandle::from_raw(output) };
    match (h_in.read_int32(), h_in.read_int32()) {
        (Ok(a), Ok(b)) => {
            let c = a.wrapping_add(b);
            println!("[Node] add({}, {}) = {}", a, b, c);
            if let Err(e) = h_out.write_int32(c) {
                eprintln!("[Node] add: 写入结果失败: {:?}", e);
            }
        }
        _ => eprintln!("[Node] add: 读取参数失败"),
    }
    // No mem::forget needed – from_raw yields borrowed handles which do NOT free on drop.
}

extern "C" fn inv_seri_callback(_trigger: *mut c_void, input: DataHnd, output: DataHnd) {
    let mut h_in = unsafe { DataHandle::from_raw(input) };
    let mut h_out = unsafe { DataHandle::from_raw(output) };

    let b = h_in.read_uint8().unwrap_or(0);
    let w = h_in.read_uint16().unwrap_or(0);
    let c = h_in.read_uint32().unwrap_or(0);
    let u64 = h_in.read_uint64().unwrap_or(0);
    let s = h_in.read_string_null_terminated().unwrap_or_default();
    let f = h_in.read_single().unwrap_or(0.0);

    let mut ok = true;
    if let Err(e) = h_out.write_single(f) {
        eprintln!("[Node] inv_seri: 写入 single 失败: {:?}", e);
        ok = false;
    }
    if let Err(e) = h_out.write_string_null_terminated(&s) {
        eprintln!("[Node] inv_seri: 写入 string 失败: {:?}", e);
        ok = false;
    }
    if let Err(e) = h_out.write_uint64(u64) {
        eprintln!("[Node] inv_seri: 写入 uint64 失败: {:?}", e);
        ok = false;
    }
    if let Err(e) = h_out.write_uint32(c) {
        eprintln!("[Node] inv_seri: 写入 uint32 失败: {:?}", e);
        ok = false;
    }
    if let Err(e) = h_out.write_uint16(w) {
        eprintln!("[Node] inv_seri: 写入 uint16 失败: {:?}", e);
        ok = false;
    }
    if let Err(e) = h_out.write_uint8(b) {
        eprintln!("[Node] inv_seri: 写入 uint8 失败: {:?}", e);
        ok = false;
    }

    if ok {
        println!(
            "[Node] inv_seri 接收: [{}, {}, {}, {}, \"{}\", {:.2}] 回复: [{:.2}, \"{}\", {}, {}, {}, {}]",
            b, w, c, u64, s, f, f, s, u64, c, w, b
        );
    } else {
        eprintln!("[Node] inv_seri: 写入过程中出现错误，回复可能不完整");
    }
}

fn main() -> Result<()> {
    println!("=== CrossNode (Rust) – Worker Node ===");

    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();
    ctrlc::set_handler(move || {
        eprintln!("\n[Node] 收到 Ctrl+C 信号，正在退出...");
        r.store(false, Ordering::SeqCst);
    }).expect("设置 Ctrl+C 处理器失败");

    let app = AppHandle::new("demo", "Rust cross node instance")?;

    app.register_call("add", "add(int a, int b)", std::ptr::null_mut(), add_callback)?;
    app.register_call("inv_seri", "inv_seri()", std::ptr::null_mut(), inv_seri_callback)?;
    println!("[OK] Registered 'add' and 'inv_seri' under app 'demo'");

    set_option("Wait_Connection_ReadyOk", "False");

    reset_prepare();
    prepare_client("ipc:cross", app.as_raw())?;
    prepare_done()?;
    println!("[OK] Node ready on IPC ipc:cross, waiting for requests...");
    println!("[INFO] Press Enter or Ctrl+C to stop this node...");

    let (tx, rx) = std::sync::mpsc::channel();
    let r2 = running.clone();
    thread::spawn(move || {
        let mut input = String::new();
        while r2.load(Ordering::SeqCst) {
            input.clear();
            if let Ok(bytes) = io::stdin().read_line(&mut input) {
                if bytes == 0 { break; }
                if input.trim() == "exit" || input.trim() == "quit" {
                    eprintln!("[Node] 收到 'exit' 命令，正在退出...");
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

    println!("[Node] 正在关闭...");
    let shutdown_start = Instant::now();
    let shutdown_timeout = Duration::from_secs(1);
    let handle = thread::spawn(|| { exit_main_thread(); shutdown(); });
    while !handle.is_finished() {
        if shutdown_start.elapsed() > shutdown_timeout {
            eprintln!("[Node] 关闭超时，强制终止进程（退出码 0）");
            let _ = std::io::stdout().flush();
            std::process::exit(0);
        }
        thread::sleep(Duration::from_millis(50));
    }
    let _ = handle.join();
    println!("[Node] 已正常停止");
    Ok(())
}