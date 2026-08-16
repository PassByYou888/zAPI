#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

import time
from collections import defaultdict

LIMIT = 5
PERIOD = 10
calls = defaultdict(list)
app = Server("RateLimitService")

@app.expose("call")
def call(client_id: str) -> dict:
    now = time.time()
    calls[client_id] = [t for t in calls[client_id] if now - t < PERIOD]
    if len(calls[client_id]) >= LIMIT:
        return {"status": "limited", "remaining": 0}
    calls[client_id].append(now)
    return {"status": "ok", "remaining": LIMIT - len(calls[client_id])}

if __name__ == "__main__":
    app.start("ipc:rate_limit_service")
    for _ in range(7):
        print(app.call("call", "client1"))
        time.sleep(1)
    app.stop()
