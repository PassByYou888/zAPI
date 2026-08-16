// examples/pubsub_client.rs
use api_hub_rust::*;

fn main() -> Result<()> {
    reset_prepare();
    prepare_client("127.0.0.1:9906", std::ptr::null_mut())?;
    prepare_done()?;

    let mut sub = DataHandle::new("subscribe")?;
    sub.write_string("weather")?;
    sub.write_string("client1")?;
    notify("PubSubService", sub.as_raw());

    let mut pub_msg = DataHandle::new("publish")?;
    pub_msg.write_string("weather")?;
    pub_msg.write_string("Sunny day!")?;
    notify("PubSubService", pub_msg.as_raw());

    std::thread::sleep(std::time::Duration::from_millis(500));
    exit_main_thread();
    shutdown();
    Ok(())
}
