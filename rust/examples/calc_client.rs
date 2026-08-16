// examples/calc_client.rs
use api_hub_rust::*;

fn main() -> Result<()> {
    reset_prepare();
    prepare_client("127.0.0.1:9903", std::ptr::null_mut())?;
    prepare_done()?;

    macro_rules! call_calc {
        ($api:expr, $a:expr, $b:expr) => {{
            let mut param = DataHandle::new($api)?;
            param.write_i32($a)?;
            param.write_i32($b)?;
            let res = call("CalcService", param.as_raw(), 3000)?;
            let size = get_size(res);
            if size == 0 {
                println!("调用 {}({}, {}) 超时或失败", $api, $a, $b);
            } else {
                let mut resp = unsafe { DataHandle::from_raw(res) };
                let result = resp.read_i32()?;
                println!("{}({}, {}) = {}", $api, $a, $b, result);
            }
            Ok::<_, ApiError>(())
        }};
    }

    call_calc!("add", 10, 5)?;
    call_calc!("sub", 10, 5)?;
    call_calc!("mul", 10, 5)?;
    call_calc!("div", 10, 5)?;

    exit_main_thread();
    shutdown();
    Ok(())
}
