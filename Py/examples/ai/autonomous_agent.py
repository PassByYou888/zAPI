#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

app = Server("AgentService")

@app.expose("perceive")
def perceive() -> dict:
    return {"temperature": 25, "humidity": 60, "light": 800}

@app.expose("decide")
def decide(percepts: dict) -> str:
    if percepts["temperature"] > 30:
        return "turn_on_ac"
    elif percepts["light"] < 100:
        return "turn_on_light"
    else:
        return "idle"

@app.expose("act", notify=True)
def act(action: str):
    print(f"Executing action: {action}")

if __name__ == "__main__":
    app.start("ipc:agent_service")
    p = app.call("perceive")
    a = app.call("decide", p)
    app.notify("act", a)
    print(f"Percepts: {p}, Action: {a}")
    app.stop()

