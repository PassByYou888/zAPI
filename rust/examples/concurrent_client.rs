// examples/concurrent_client.rs
use api_hub_rust::*;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Instant;

fn main() -> Result<()> {
    reset_prepare();
    prepare_client("127.0.0.1:9903", std::ptr::null_mut())?;
    prepare_done()?;

    const THREADS: usize = 20;
    const CALLS_PER_THREAD: usize = 50;
    let total = THREADS * CALLS_PER_THREAD;

    let counter = Arc::new(AtomicUsize::new(0));
    let start = Instant::now();

    let mut handles = vec![];
    for _ in 0..THREADS {
        let counter = counter.clone();
        handles.push(std::thread::spawn(move || {
            for _ in 0..CALLS_PER_THREAD {
                let mut param = DataHandle::new("add").unwrap();
                param.write_i32(1).unwrap();
                param.write_i32(2).unwrap();
                let res = call("CalcService", param.as_raw(), 3000).unwrap();
                if get_size(res) > 0 {
                    counter.fetch_add(1, Ordering::SeqCst);
                }
                // 修改点：使用 from_owned_raw 确保释放
                unsafe { DataHandle::from_owned_raw(res) };
            }
        }));
    }

    for h in handles { h.join().unwrap(); }

    let elapsed = start.elapsed();
    let qps = total as f64 / elapsed.as_secs_f64();
    println!("成功调用: {} / {}", counter.load(Ordering::SeqCst), total);
    println!("总耗时: {:.2?}", elapsed);
    println!("QPS: {:.2}", qps);

    exit_main_thread();
    shutdown();
    Ok(())
}