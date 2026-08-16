#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

import os

CHUNK = 1024
app = Server("FileService")

@app.expose("upload")
def upload(name: str, chunks: list) -> bool:
    with open(name, "wb") as f:
        for c in chunks:
            f.write(c)
    return True

@app.expose("download")
def download(name: str) -> list:
    if not os.path.exists(name):
        return []
    chunks = []
    with open(name, "rb") as f:
        while True:
            d = f.read(CHUNK)
            if not d:
                break
            chunks.append(d)
    return chunks

if __name__ == "__main__":
    app.start("ipc:file_service")
    data = b"Hello " * 100
    chunks = [data[i:i+CHUNK] for i in range(0, len(data), CHUNK)]
    app.call("upload", "test.dat", chunks)
    down = app.call("download", "test.dat")
    if down is None:
        print("[FAIL] Download failed")
    else:
        print(f"[OK] Downloaded {sum(len(c) for c in down)} bytes")
    app.stop()

