#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

app = Server("EchoService")

@app.expose("echo")
def echo(msg: str) -> str:
    return f"Echo: {msg}"

if __name__ == "__main__":
    app.start("ipc:echo_service")
    print(app.call("echo", "Hello from Python"))
    app.stop()
