#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

db = {}
app = Server("DBService")

@app.expose("set")
def set(k: str, v: str) -> bool:
    db[k] = v
    return True

@app.expose("get")
def get(k: str) -> str:
    return db.get(k, "")

@app.expose("delete")
def delete(k: str) -> bool:
    if k in db:
        del db[k]
        return True
    return False

@app.expose("keys")
def keys() -> list:
    return list(db.keys())

if __name__ == "__main__":
    app.start("ipc:db_service")
    app.call("set", "name", "Alice")
    app.call("set", "age", "30")
    print("Keys:", app.call("keys"))
    print("name:", app.call("get", "name"))
    app.call("delete", "age")
    print("After delete:", app.call("keys"))
    app.stop()
