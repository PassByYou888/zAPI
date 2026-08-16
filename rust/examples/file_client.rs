// examples/file_client.rs
use api_hub_rust::*;

fn write_string_safe(hnd: DataHnd, s: &str) -> Result<usize> {
    let bytes = s.as_bytes();
    let len = bytes.len() as i32;
    let len_bytes = len.to_le_bytes();
    let written = write_buffer(hnd, &len_bytes)?;
    if written != 4 { return Err(ApiError::WriteFailed); }
    if len > 0 {
        let written = write_buffer(hnd, bytes)?;
        if written != bytes.len() { return Err(ApiError::WriteFailed); }
    }
    Ok(4 + bytes.len())
}

fn main() -> Result<()> {
    println!("[File] 客户端启动...");
    reset_prepare();
    prepare_client("127.0.0.1:9902", std::ptr::null_mut())?;
    prepare_done()?;

    let file_name = "demo_upload.txt";
    let content = b"Hello, this is a test file for API Hub file transfer demo!";

    let param = DataHandle::new("upload")?;
    write_string_safe(param.as_raw(), file_name)?;
    write_buffer(param.as_raw(), content)?;
    let res = call("FileService", param.as_raw(), 15000)?;
    if get_size(res) == 0 {
        println!("上传失败（超时或错误）");
        return Ok(());
    }
    let mut resp = unsafe { DataHandle::from_raw(res) };
    let success = resp.read_i32()? != 0;
    if success { println!("上传文件 '{}' 成功", file_name); }
    else { println!("上传失败（服务端返回错误）"); return Ok(()); }

    let param2 = DataHandle::new("download")?;
    write_string_safe(param2.as_raw(), file_name)?;
    let res2 = call("FileService", param2.as_raw(), 15000)?;
    if get_size(res2) == 0 {
        println!("下载失败（超时或错误）");
        return Ok(());
    }
    let mut resp2 = unsafe { DataHandle::from_raw(res2) };
    let total = resp2.size() as usize;
    let mut downloaded = vec![0u8; total];
    resp2.read(&mut downloaded)?;
    println!("下载文件 '{}' 成功，大小: {} 字节", file_name, downloaded.len());
    println!("内容: {}", String::from_utf8_lossy(&downloaded));

    exit_main_thread();
    shutdown();
    Ok(())
}
