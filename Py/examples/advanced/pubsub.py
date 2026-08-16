#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

subs = {}
app = Server("PubSubService")

@app.expose("subscribe", notify=True)
def subscribe(topic: str, client_id: str):
    subs.setdefault(topic, set()).add(client_id)
    print(f"Subscribed {client_id} to {topic}")

@app.expose("publish", notify=True)
def publish(topic: str, msg: str):
    if topic in subs:
        for cid in subs[topic]:
            print(f"Notifying {cid}: {msg}")

if __name__ == "__main__":
    app.start("ipc:pubsub_service")
    app.notify("subscribe", "weather", "client1")
    app.notify("subscribe", "weather", "client2")
    app.notify("publish", "weather", "Sunny")
    app.notify("publish", "news", "API Hub is great")
    app.stop()

