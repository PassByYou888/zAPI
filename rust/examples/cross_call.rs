// examples/cross_call.rs
use api_hub_rust::*;
use std::time::{Duration, Instant};
use rand::Rng;

// ========== 远程调用封装（原始二进制） ==========

fn add__(a: i32, b: i32) -> i32 {
    let mut param = match DataHandle::new("add") {
        Ok(h) => h,
        Err(_) => return 0,
    };
    if param.write_int32(a).is_err() || param.write_int32(b).is_err() {
        return 0;
    }
    for attempt in 0..3 {
        let res = match call("demo", param.as_raw(), 15000) {
            Ok(r) => r,
            Err(e) => {
                eprintln!("[add] call 错误 (尝试 {}): {:?}", attempt + 1, e);
                continue;
            }
        };
        let size = get_size(res);
        eprintln!("[add] res ptr: {:p}, size: {} (尝试 {})", res, size, attempt + 1);
        if size > 0 {
            // The returned handle is owned – use from_owned_raw.
            let mut resp = unsafe { DataHandle::from_owned_raw(res) };
            return resp.read_int32().unwrap_or(0);
        }
        // If size is 0, we still need to free the handle (it's owned).
        unsafe { DataHandle::from_owned_raw(res) };
        std::thread::sleep(Duration::from_millis(100));
    }
    0
}

fn inv_seri__() -> String {
    let mut param = match DataHandle::new("inv_seri") {
        Ok(h) => h,
        Err(_) => return "inv_seri 创建句柄失败".to_string(),
    };

    let b: u8 = 200;
    let w: u16 = 0x10;
    let c: u32 = 0x2F;
    let u64: u64 = 0x3F;
    let s = "hello world";
    let f: f32 = 3.14;

    if param.write_uint8(b).is_err()
        || param.write_uint16(w).is_err()
        || param.write_uint32(c).is_err()
        || param.write_uint64(u64).is_err()
        || param.write_string_null_terminated(s).is_err()
        || param.write_single(f).is_err()
    {
        return "inv_seri 写入参数失败".to_string();
    }

    for attempt in 0..3 {
        let res = match call("demo", param.as_raw(), 15000) {
            Ok(r) => r,
            Err(e) => {
                eprintln!("[inv_seri] call 错误 (尝试 {}): {:?}", attempt + 1, e);
                continue;
            }
        };
        let size = get_size(res);
        eprintln!("[inv_seri] res ptr: {:p}, size: {} (尝试 {})", res, size, attempt + 1);
        if size > 0 {
            let mut resp = unsafe { DataHandle::from_owned_raw(res) };
            let f_ret = resp.read_single().unwrap_or(0.0);
            let s_ret = resp.read_string_null_terminated().unwrap_or_default();
            let u64_ret = resp.read_uint64().unwrap_or(0);
            let c_ret = resp.read_uint32().unwrap_or(0);
            let w_ret = resp.read_uint16().unwrap_or(0);
            let b_ret = resp.read_uint8().unwrap_or(0);
            return format!(
                "接收数据序 [{}, {}, {}, {}, \"{}\", {:.2}] = 发送数据序 [{:.2}, \"{}\", {}, {}, {}, {}]",
                b_ret, w_ret, c_ret, u64_ret, s_ret, f_ret,
                f_ret, s_ret, u64_ret, c_ret, w_ret, b_ret
            );
        }
        unsafe { DataHandle::from_owned_raw(res) };
        std::thread::sleep(Duration::from_millis(100));
    }
    "inv_seri 超时或失败（重试 3 次）".to_string()
}

fn main() -> Result<()> {
    println!("=== CrossCall (Rust) – Concurrent Client ===");

    let running = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(true));
    let r = running.clone();
    ctrlc::set_handler(move || {
        eprintln!("\n[Call] 收到 Ctrl+C 信号，正在退出...");
        r.store(false, std::sync::atomic::Ordering::SeqCst);
    }).expect("设置 Ctrl+C 处理器失败");

    reset_prepare();
    prepare_client("ipc:cross", std::ptr::null_mut())?;
    prepare_done()?;
    println!("[OK] Connected to IPC ipc:cross");

    let stop = running.clone();
    let handle = std::thread::spawn(move || {
        let start = Instant::now();
        let duration = Duration::from_secs(10);
        let mut rng = rand::thread_rng();

        println!("[Call] 仿真计算启动（可多开），持续 10 秒...");

        while stop.load(std::sync::atomic::Ordering::SeqCst) && start.elapsed() < duration {
            if rng.gen::<bool>() {
                let a = rng.gen_range(1..i32::MAX);
                let b = rng.gen_range(1..i32::MAX);
                let result = add__(a, b);
                let remaining = duration.as_secs_f64() - start.elapsed().as_secs_f64();
                if result != 0 {
                    println!(
                        "[Call] 计算 \"a({})+b({})\" = 计算结果 {} ({:.2}秒以后退出)",
                        a, b, result, remaining
                    );
                } else {
                    println!(
                        "[Call] add({}, {}) 返回 0（重试后仍失败） ({:.2}秒退出)",
                        a, b, remaining
                    );
                }
            } else {
                let status = inv_seri__();
                let remaining = duration.as_secs_f64() - start.elapsed().as_secs_f64();
                println!("[Call] {} ({:.2}秒退出)", status, remaining);
            }
            std::thread::sleep(Duration::from_millis(1));
        }

        println!("[Call] 工作线程结束");
    });

    while running.load(std::sync::atomic::Ordering::SeqCst) {
        if handle.is_finished() {
            break;
        }
        std::thread::sleep(Duration::from_millis(100));
    }

    let _ = handle.join();

    println!("[OK] 计算完成，清理线程中.");

    exit_main_thread();
    shutdown();
    println!("[OK] Client shutdown complete.");
    Ok(())
}