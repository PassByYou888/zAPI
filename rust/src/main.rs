use api_hub_rust::test_runner::run_all_tests;
use anyhow::Result;

fn main() -> Result<()> {
    #[cfg(feature = "debug-log")]
    eprintln!("[INFO] Debug log enabled.");

    run_all_tests()?;

    println!("测试完成。按 Enter 退出...");
    // 忽略 read_line 的错误，防止因 I/O 错误导致进程异常退出
    let _ = std::io::stdin().read_line(&mut String::new());
    Ok(())
}