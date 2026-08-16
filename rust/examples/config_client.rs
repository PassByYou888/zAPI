// examples/config_client.rs
use api_hub_rust::*;

fn main() -> Result<()> {
    reset_prepare();
    prepare_client("127.0.0.1:9907", std::ptr::null_mut())?;
    prepare_done()?;

    let mut set_param = DataHandle::new("set")?;
    set_param.write_string("db_url")?;
    set_param.write_string("postgres://localhost:5432")?;
    notify("ConfigService", set_param.as_raw());

    let mut get_param = DataHandle::new("get")?;
    get_param.write_string("db_url")?;
    let res = call("ConfigService", get_param.as_raw(), 3000)?;
    if get_size(res) == 0 {
        println!("获取配置失败");
    } else {
        let mut resp = unsafe { DataHandle::from_raw(res) };
        let val = resp.read_string()?;
        println!("db_url = {}", val);
    }

    exit_main_thread();
    shutdown();
    Ok(())
}
