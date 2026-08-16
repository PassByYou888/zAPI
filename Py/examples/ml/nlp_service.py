#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

app = Server("NLPService")

@app.expose("sentiment")
def sentiment(text: str) -> dict:
    words = text.split()
    positive = sum(1 for w in words if w.lower() in ["good", "great", "excellent"])
    negative = sum(1 for w in words if w.lower() in ["bad", "terrible", "awful"])
    return {"positive": positive, "negative": negative, "neutral": len(words)-positive-negative}

@app.expose("translate", notify=True)
def translate(text: str, target_lang: str):
    print(f"Translating '{text}' to {target_lang} (simulated)")

if __name__ == "__main__":
    app.start("ipc:nlp_service")
    print("Sentiment:", app.call("sentiment", "Great product, but bad support"))
    app.notify("translate", "Hello", "es")
    app.stop()

