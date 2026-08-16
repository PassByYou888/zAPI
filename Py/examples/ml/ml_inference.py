#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

weights = [0.5, 1.2, -0.3]
app = Server("MLService")

@app.expose("predict")
def predict(features: list) -> float:
    if len(features) != 3:
        raise ValueError("Need 3 features")
    return sum(w*x for w,x in zip(weights, features))

@app.expose("train", notify=True)
def train(dataset: list):
    print(f"Training on {len(dataset)} samples...")

if __name__ == "__main__":
    app.start("ipc:ml_service")
    sample = [1.0, 2.5, -1.0]
    print(f"Prediction: {app.call('predict', sample):.4f}")
    app.notify("train", [{"x": [1,2,3], "y": 10}])
    app.stop()

