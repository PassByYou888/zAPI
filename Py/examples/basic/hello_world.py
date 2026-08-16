#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

app = Server("HelloApp")

@app.expose("greet")
def greet(name: str) -> str:
    return f"Hello, {name}!"

if __name__ == "__main__":
    app.start("ipc:hello_service")
    print(app.call("greet", "World"))
    app.stop()
