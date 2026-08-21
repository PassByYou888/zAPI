// examples/log_client.rs
use api_hub_rust::*;

fn main() -> Result<()> {
    reset_prepare();
    prepare_client("127.0.0.1:9905", std::ptr::null_mut())?;
    prepare_done()?;

    let mut param = DataHandle::new("log")?;
    param.write_string_null_terminated("INFO")?;
    param.write_string_null_terminated("Hello from Rust log client!")?;
    notify("LogService", param.as_raw());

    let mut param2 = DataHandle::new("log")?;
    param2.write_string_null_terminated("ERROR")?;
    param2.write_string_null_terminated("Something went wrong!")?;
    notify("LogService", param2.as_raw());

    std::thread::sleep(std::time::Duration::from_millis(500));
    exit_main_thread();
    shutdown();
    Ok(())
}