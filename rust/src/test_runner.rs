use crate::*;
use anyhow::Result;
use std::time::{SystemTime, UNIX_EPOCH};

/// 运行所有测试用例
pub fn run_all_tests() -> Result<()> {
    println!("=== API Hub Rust 综合测试 ===");

    test_local_call()?;
    let _app = start_network_service()?;
    test_remote_calls()?;
    test_notification()?;
    test_local_notification()?;

    // ★ 关键：关闭网络框架，否则进程无法退出
    exit_main_thread();
    shutdown();

    Ok(())
}

// ---------- 回调函数 ----------
extern "C" fn add_callback(_trigger: *mut c_void, input: DataHnd, output: DataHnd) {
    let mut a = 0i32;
    let mut b = 0i32;
    unsafe {
        let _ = read_buffer(input, std::slice::from_raw_parts_mut(
            &mut a as *mut _ as *mut u8, 4));
        let _ = read_buffer(input, std::slice::from_raw_parts_mut(
            &mut b as *mut _ as *mut u8, 4));
    }
    let sum = a + b;
    let _ = write_buffer(output, &sum.to_le_bytes());
    println!("[Server] add({}, {}) = {}", a, b, sum);
}

extern "C" fn echo_callback(_trigger: *mut c_void, input: DataHnd, output: DataHnd) {
    unsafe {
        let size = get_size(input);
        if size > 0 {
            let mut buf = vec![0u8; size as usize];
            set_pos(input, 0);
            let _ = read_buffer(input, &mut buf);
            let _ = write_buffer(output, &buf);
        }
    }
}

extern "C" fn get_time_callback(_trigger: *mut c_void, _input: DataHnd, output: DataHnd) {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let secs = now.as_secs();
    let time_str = format!("{}", secs);
    let bytes = time_str.as_bytes();
    let len = bytes.len() as i32;
    let _ = write_buffer(output, &len.to_le_bytes());
    let _ = write_buffer(output, bytes);
}

extern "C" fn print_notify(_trigger: *mut c_void, input: DataHnd) {
    unsafe {
        let mut len_buf = [0u8; 4];
        set_pos(input, 0);
        if read_buffer(input, &mut len_buf).is_err() || len_buf.len() != 4 {
            return;
        }
        let len = i32::from_le_bytes(len_buf) as usize;
        if len == 0 {
            return;
        }
        let mut buf = vec![0u8; len];
        if read_buffer(input, &mut buf).is_err() || buf.len() != len {
            return;
        }
        if let Ok(msg) = String::from_utf8(buf) {
            println!("[Notify] Received: {}", msg);
        }
    }
}

// ---------- 测试函数 ----------
fn test_local_call() -> Result<()> {
    println!("\n-- 本地调用演示 --");
    let app = AppHandle::new("LocalApp", "Local only")?;
    app.register_call("add", "Add", std::ptr::null_mut(), add_callback)?;
    let mut param = DataHandle::new("add")?;
    param.write_i32(5)?;
    param.write_i32(7)?;
    let mut result = app.local_call(&param)?;
    println!("本地 add(5,7) = {}", result.read_i32()?);
    Ok(())
}

fn start_network_service() -> Result<AppHandle> {
    println!("\n-- 启动网络服务 (IPC) --");
    let app = AppHandle::new("TestService", "Network test")?;
    app.register_call("add", "Add", std::ptr::null_mut(), add_callback)?;
    app.register_call("echo", "Echo", std::ptr::null_mut(), echo_callback)?;
    app.register_call("get_time", "Time", std::ptr::null_mut(), get_time_callback)?;
    app.register_notify("print", "Print", std::ptr::null_mut(), print_notify)?;

    reset_prepare();

    let addr = "ipc:test_service";
    println!("准备服务地址: {}", addr);
    prepare_service(addr, addr)?;
    prepare_client(addr, app.as_raw())?;

    prepare_done()?;

    // 状态信息由库自动打印到控制台，无需手动调用 get_status
    println!("服务已启动。查看控制台输出以获取状态信息。");

    std::thread::sleep(std::time::Duration::from_millis(800));
    Ok(app)
}

fn test_remote_calls() -> Result<()> {
    println!("\n-- 远程调用演示 --");

    let tests: Vec<(&str, fn() -> Result<()>)> = vec![
        ("add", test_add),
        ("echo", test_echo),
        ("get_time", test_get_time),
    ];
    for (name, test) in tests {
        println!("\n  测试 {}:", name);
        test()?;
    }
    Ok(())
}

fn test_add() -> Result<()> {
    let mut param = DataHandle::new("add")?;
    param.write_i32(10)?;
    param.write_i32(20)?;
    println!("   发送 add(10,20) ...");
    let res = call("TestService", param.as_raw(), 5000)?;

    let size = get_size(res);
    if size == 0 {
        println!("    调用返回空结果");
        return Ok(());
    }

    let mut resp = unsafe { DataHandle::from_raw(res) };
    let result = resp.read_i32()?;
    println!("    远程 add(10,20) = {}", result);
    Ok(())
}

fn test_echo() -> Result<()> {
    let mut param = DataHandle::new("echo")?;
    param.write_string("Hello from Rust!")?;
    println!("   发送 echo ...");
    let res = call("TestService", param.as_raw(), 5000)?;

    let size = get_size(res);
    if size == 0 {
        println!("    调用返回空结果");
        return Ok(());
    }

    let mut resp = unsafe { DataHandle::from_raw(res) };
    let result = resp.read_string()?;
    println!("    远程 echo -> '{}'", result);
    Ok(())
}

fn test_get_time() -> Result<()> {
    let param = DataHandle::new("get_time")?;
    println!("   发送 get_time ...");
    let res = call("TestService", param.as_raw(), 5000)?;

    let size = get_size(res);
    if size == 0 {
        println!("    调用返回空结果");
        return Ok(());
    }

    let mut resp = unsafe { DataHandle::from_raw(res) };
    let result = resp.read_string()?;
    println!("    远程 get_time -> '{}'", result);
    Ok(())
}

fn test_notification() -> Result<()> {
    println!("\n-- 通知测试 --");
    let mut param = DataHandle::new("print")?;
    param.write_string("Notification from Rust client")?;
    notify("TestService", param.as_raw());
    std::thread::sleep(std::time::Duration::from_millis(500));
    // 状态信息由库自动打印到控制台
    Ok(())
}

fn test_local_notification() -> Result<()> {
    println!("\n-- 本地通知测试 --");
    let app = AppHandle::new("LocalAppNotify", "Local notify")?;
    app.register_notify("print", "Print", std::ptr::null_mut(), print_notify)?;
    let mut param = DataHandle::new("print")?;
    param.write_string("Local notification")?;
    app.local_notify(&param);
    std::thread::sleep(std::time::Duration::from_millis(200));
    Ok(())
}