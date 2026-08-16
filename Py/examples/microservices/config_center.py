#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

config = {}
app = Server("ConfigService")

@app.expose("get")
def get(key: str) -> str:
    return config.get(key, "")

@app.expose("set", notify=True)
def set(key: str, value: str):
    config[key] = value
    print(f"Config updated: {key}={value}")

@app.expose("all")
def all() -> dict:
    return config

if __name__ == "__main__":
    app.start("ipc:config_service")
    app.notify("set", "db_url", "mysql://127.0.0.1/test")
    print("db_url =", app.call("get", "db_url"))
    print("All:", app.call("all"))
    app.stop()

