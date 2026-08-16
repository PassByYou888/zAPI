// examples/cross_client.rs
use api_hub_rust::*;

fn main() -> Result<()> {
    reset_prepare();
    prepare_client("ipc:func_service", std::ptr::null_mut())?;
    // 也可尝试 TCP: prepare_client("127.0.0.1:9899", std::ptr::null_mut())?;
    prepare_done()?;

    let mut param = DataHandle::new("add")?;
    param.write_i32(100)?;
    param.write_i32(200)?;
    let res = call("FuncService", param.as_raw(), 3000)?;
    if get_size(res) > 0 {
        let mut resp = unsafe { DataHandle::from_raw(res) };
        let sum = resp.read_i32()?;
        println!("add(100,200) = {}", sum);
    } else {
        println!("add 调用失败或超时");
    }

    let mut param2 = DataHandle::new("to_upper")?;
    param2.write_string("hello from rust")?;
    let res2 = call("FuncService", param2.as_raw(), 3000)?;
    if get_size(res2) > 0 {
        let mut resp2 = unsafe { DataHandle::from_raw(res2) };
        let s = resp2.read_string()?;
        println!("to_upper('hello from rust') = '{}'", s);
    } else {
        println!("to_upper 调用失败");
    }

    exit_main_thread();
    shutdown();
    Ok(())
}
