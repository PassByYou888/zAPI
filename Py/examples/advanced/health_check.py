#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

import time
app = Server("HealthService")

@app.expose("ping")
def ping() -> str:
    return "pong"

@app.expose("status")
def status() -> dict:
    return {"status": "healthy", "uptime": time.time()}

if __name__ == "__main__":
    app.start("ipc:health_service")
    print("Ping:", app.call("ping"))
    print("Status:", app.call("status"))
    app.stop()
