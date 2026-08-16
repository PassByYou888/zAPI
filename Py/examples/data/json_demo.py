#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

app = Server("DataService")

@app.expose("process_user")
def process_user(user: dict) -> dict:
    user["age"] = user.get("age", 0) + 1
    user["processed"] = True
    return user

@app.expose("analyze")
def analyze(nums: list) -> dict:
    return {"count": len(nums), "sum": sum(nums), "avg": sum(nums)/len(nums) if nums else 0}

if __name__ == "__main__":
    app.start("ipc:data_service")
    user = {"name": "Alice", "age": 30}
    print("Updated:", app.call("process_user", user))
    print("Stats:", app.call("analyze", [1,2,3,4,5]))
    app.stop()
