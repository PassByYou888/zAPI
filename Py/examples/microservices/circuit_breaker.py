#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

import random, time
app = Server("FaultyService")

@app.expose("unstable")
def unstable() -> str:
    if random.random() < 0.4:
        raise RuntimeError("Service temporarily unavailable")
    return "Success"

if __name__ == "__main__":
    app.start("ipc:circuit_service")
    for _ in range(10):
        try:
            print(app.call("unstable"))
        except Exception as e:
            print(f"Error: {e}")
        time.sleep(0.5)
    app.stop()
