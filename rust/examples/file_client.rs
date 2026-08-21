// examples/file_client.rs
use api_hub_rust::*;

fn main() -> Result<()> {
    println!("[File] 客户端启动...");
    reset_prepare();
    prepare_client("127.0.0.1:9902", std::ptr::null_mut())?;
    prepare_done()?;

    let file_name = "demo_upload.txt";
    let content = b"Hello, this is a test file for API Hub file transfer demo!";

    // ---------- 上传 ----------
    let mut param = DataHandle::new("upload")?;
    param.write_string_null_terminated(file_name)?;
    param.write(content)?;
    let res = call("FileService", param.as_raw(), 15000)?;
    if get_size(res) == 0 {
        println!("上传失败（超时或错误）");
        return Ok(());
    }
    // 修改点
    let mut resp = unsafe { DataHandle::from_owned_raw(res) };
    let success = resp.read_i32()? != 0;
    if success {
        println!("上传文件 '{}' 成功", file_name);
    } else {
        println!("上传失败（服务端返回错误）");
        return Ok(());
    }

    // ---------- 下载 ----------
    let mut param2 = DataHandle::new("download")?;
    param2.write_string_null_terminated(file_name)?;
    let res2 = call("FileService", param2.as_raw(), 15000)?;
    if get_size(res2) == 0 {
        println!("下载失败（超时或错误）");
        return Ok(());
    }
    // 修改点
    let mut resp2 = unsafe { DataHandle::from_owned_raw(res2) };
    let total = resp2.size() as usize;
    let mut downloaded = vec![0u8; total];
    resp2.read(&mut downloaded)?;
    println!("下载文件 '{}' 成功，大小: {} 字节", file_name, downloaded.len());
    println!("内容: {}", String::from_utf8_lossy(&downloaded));

    exit_main_thread();
    shutdown();
    Ok(())
}