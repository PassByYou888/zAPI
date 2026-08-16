#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

app = Server("CalcService")

@app.expose("add")
def add(a: int, b: int) -> int:
    return a + b

@app.expose("sub")
def sub(a: int, b: int) -> int:
    return a - b

@app.expose("mul")
def mul(a: int, b: int) -> int:
    return a * b

@app.expose("div")
def div(a: int, b: int) -> float:
    if b == 0:
        raise ValueError("Division by zero")
    return a / b

if __name__ == "__main__":
    app.start("ipc:calc_service")
    print(f"10+5={app.call('add', 10, 5)}")
    print(f"10-5={app.call('sub', 10, 5)}")
    print(f"10*5={app.call('mul', 10, 5)}")
    print(f"10/5={app.call('div', 10, 5):.2f}")
    app.stop()
