// examples/echo_client.rs
use api_hub_rust::*;

fn main() -> Result<()> {
    reset_prepare();
    prepare_client("127.0.0.1:9904", std::ptr::null_mut())?;
    prepare_done()?;

    let msg = "Hello from Rust echo client!";
    let mut param = DataHandle::new("echo")?;
    param.write_string(msg)?;
    let res = call("EchoService", param.as_raw(), 3000)?;
    let size = get_size(res);
    if size == 0 {
        println!("回显调用超时或失败");
    } else {
        let mut resp = unsafe { DataHandle::from_raw(res) };
        let reply = resp.read_string()?;
        println!("原始: {}\n回显: {}", msg, reply);
    }

    exit_main_thread();
    shutdown();
    Ok(())
}
