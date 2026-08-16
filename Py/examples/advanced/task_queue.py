#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

queue = []
app = Server("QueueService")

@app.expose("push", notify=True)
def push(task: dict):
    queue.append(task)
    print(f"Task added: {task}")

@app.expose("pop")
def pop() -> dict:
    return queue.pop(0) if queue else None

@app.expose("size")
def size() -> int:
    return len(queue)

if __name__ == "__main__":
    app.start("ipc:queue_service")
    app.notify("push", {"type": "email", "to": "alice@example.com"})
    app.notify("push", {"type": "sms", "to": "+123456"})
    print("Queue size:", app.call("size"))
    print("Pop:", app.call("pop"))
    print("Size after pop:", app.call("size"))
    app.stop()

