// examples/pubsub_server.rs
use api_hub_rust::*;
use std::ffi::c_void;
use std::io::{self, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

extern "C" fn subscribe_callback(_trigger: *mut c_void, input: DataHnd) {
    let mut h = unsafe { DataHandle::from_raw(input) };
    let topic = h.read_string_null_terminated().unwrap_or_default();
    let client = h.read_string_null_terminated().unwrap_or_default();
    println!("[PubSub] {} 订阅了 {}", client, topic);
}
extern "C" fn publish_callback(_trigger: *mut c_void, input: DataHnd) {
    let mut h = unsafe { DataHandle::from_raw(input) };
    let topic = h.read_string_null_terminated().unwrap_or_default();
    let msg = h.read_string_null_terminated().unwrap_or_default();
    println!("[PubSub] 发布到 {}: {}", topic, msg);
}

fn main() -> Result<()> {
    println!("[PubSub] 服务端启动中...");
    let app = AppHandle::new("PubSubService", "Publish/Subscribe")?;
    app.register_notify("subscribe", "Subscribe to topic", std::ptr::null_mut(), subscribe_callback)?;
    app.register_notify("publish", "Publish message", std::ptr::null_mut(), publish_callback)?;
    println!("[PubSub] API 注册完成");

    reset_prepare();
    let listen = "0.0.0.0";
    let physics = "127.0.0.1:9906";
    prepare_service(listen, physics)?;
    prepare_client(physics, app.as_raw())?;
    prepare_done()?;

    // 状态信息由库自动打印到控制台
    println!("[PubSub] 服务已启动 ({} -> {}), 按 Ctrl+C 或输入 'exit' 退出", listen, physics);

    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();
    ctrlc::set_handler(move || {
        eprintln!("\n[PubSub] 收到 Ctrl+C 信号，正在退出...");
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
                    eprintln!("[PubSub] 收到 'exit' 命令，正在退出...");
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

    println!("[PubSub] 正在关闭服务（超时 1 秒）...");
    let shutdown_start = Instant::now();
    let shutdown_timeout = Duration::from_secs(1);
    let handle = thread::spawn(|| { exit_main_thread(); shutdown(); });
    while !handle.is_finished() {
        if shutdown_start.elapsed() > shutdown_timeout {
            eprintln!("[PubSub] 关闭超时，强制终止进程（退出码 0）");
            let _ = std::io::stdout().flush();
            std::process::exit(0);
        }
        thread::sleep(Duration::from_millis(50));
    }
    let _ = handle.join();
    println!("[PubSub] 服务已正常停止");
    Ok(())
}