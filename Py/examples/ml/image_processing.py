#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

app = Server("ImageService")

@app.expose("grayscale")
def grayscale(img: bytes) -> bytes:
    return img

if __name__ == "__main__":
    app.start("ipc:image_service")
    with open(__file__, "rb") as f:
        sample = f.read(1024)
    result = app.call("grayscale", sample)
    print(f"Processed {len(result)} bytes")
    app.stop()
