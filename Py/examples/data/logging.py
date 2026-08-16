#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

from datetime import datetime

logs = []
app = Server("LogService")

@app.expose("log", notify=True)
def log(level: str, msg: str):
    ts = datetime.now().isoformat()
    logs.append({"ts": ts, "level": level, "msg": msg})
    print(f"[{ts}] {level}: {msg}")

@app.expose("get_logs")
def get_logs() -> list:
    return logs[-100:]

if __name__ == "__main__":
    app.start("ipc:log_service")
    app.notify("log", "INFO", "Started")
    app.notify("log", "ERROR", "Disk full")
    print("Recent logs:", app.call("get_logs"))
    app.stop()

