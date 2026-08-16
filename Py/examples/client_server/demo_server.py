#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
API Hub 服务端演示
暴露两个 API：
  - add(a, b) -> int        (Call)
  - log(level, msg) -> None (Notify)
"""

from api_hub import Server

# 创建应用
app = Server("DemoService", "A demo service for Python")

# ---------- Call API ----------
@app.expose("add")
def add(a: int, b: int) -> int:
    """简单的加法"""
    return a + b

# ---------- Notify API ----------
@app.expose("log", notify=True)
def log(level: str, msg: str):
    """接收日志通知并打印（强制刷新输出缓冲）"""
    print(f"[LOG] {level}: {msg}", flush=True)

if __name__ == "__main__":
    # 启动服务（使用 IPC，同机通信）
    app.start("ipc:demo_service")
    print("✅ 服务已启动，按 Ctrl+C 退出...", flush=True)
    try:
        import time
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n⏹️ 正在停止服务...", flush=True)
    finally:
        app.stop()
        print("🛑 服务已停止", flush=True)