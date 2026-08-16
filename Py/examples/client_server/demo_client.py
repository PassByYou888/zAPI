#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
API Hub 客户端演示
调用远程服务：
  - add(10, 20) -> 30
  - log("INFO", "Hello from client")
"""

from api_hub import C4
import time

def main():
    # 连接到服务端（IPC 地址必须一致）
    client = C4("DemoService", "ipc:demo_service", timeout=3000)

    # ---------- 同步调用 ----------
    result = client.add(10, 20)
    print(f"📞 10 + 20 = {int(result)}")

    # ---------- 发送通知（参数打包为列表） ----------
    client.notify("log", ["INFO", "Client started successfully"])
    client.notify("log", ["DEBUG", "This is a debug message"])

    # 等待通知发送完成（IPC 是异步的，需要给底层一点时间）
    time.sleep(1.0)

    # 关闭客户端（全局）
    C4.shutdown()
    print("✅ 客户端执行完毕")

if __name__ == "__main__":
    main()