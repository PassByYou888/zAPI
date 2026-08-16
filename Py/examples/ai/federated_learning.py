#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

global_model = [0.0, 0.0, 0.0]
app = Server("FederatedService")

@app.expose("submit_update", notify=True)
def submit_update(client_id: str, weights: list):
    print(f"Received update from {client_id}: {weights}")
    for i in range(len(global_model)):
        global_model[i] = (global_model[i] + weights[i]) / 2

@app.expose("get_model")
def get_model() -> list:
    return global_model

if __name__ == "__main__":
    app.start("ipc:federated_service")
    print("Initial model:", app.call("get_model"))
    app.notify("submit_update", "client1", [1.0, 2.0, 3.0])
    print("After update:", app.call("get_model"))
    app.stop()

