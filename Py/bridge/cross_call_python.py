#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json
import urllib.request
import time
import sys

# 强制控制台输出 UTF-8
if sys.platform == "win32":
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

BRIDGE_URL = "http://127.0.0.1:8080/v1"

def http_post(endpoint, payload):
    url = f"{BRIDGE_URL}{endpoint}"
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode('utf-8'))

def http_get(endpoint):
    url = f"{BRIDGE_URL}{endpoint}"
    req = urllib.request.Request(url, headers={'Accept': 'application/json'})
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read().decode('utf-8'))

def register_webhook(app, api, callback_url, mode='call'):
    print(f"Registering {app}.{api} -> {callback_url} (mode={mode})")
    resp = http_post("/hooks/register", {
        "app": app,
        "api": api,
        "callback_url": callback_url,
        "mode": mode
    })
    print("Register response:", json.dumps(resp, indent=2))
    return resp.get('code') == 0

def wait_for_hook(app, api, max_wait=10):
    """等待 hook 注册完成"""
    print(f"Waiting for {app}.{api} to be registered...")
    for i in range(max_wait):
        try:
            hooks = http_get("/hooks/list")
            for h in hooks.get('hooks', []):
                if h.get('app') == app and h.get('api') == api:
                    print(f"  {app}.{api} found after {i+1}s")
                    return True
        except:
            pass
        time.sleep(1)
    return False

# 1. 注册 Python webhook
print("=== Python cross-call script ===")
if not register_webhook("HttpBridge", "py_echo", "http://127.0.0.1:9001/webhook", "call"):
    print("Failed to register py_echo, exiting")
    sys.exit(1)

# 2. 等待 PHP 注册完成
print("Waiting for PHP to register its webhook...")
if not wait_for_hook("HttpBridge", "php_echo", max_wait=15):
    print("PHP webhook not registered within timeout, but will still try call")

# 3. 调用 PHP webhook（带重试）
print("\nCalling PHP webhook (HttpBridge.php_echo) from Python...")
max_retries = 5
for attempt in range(1, max_retries+1):
    try:
        resp = http_post("/invoke", {
            "app": "HttpBridge",
            "api": "php_echo",
            "args": ["Hello from Python!"],
            "timeout": 5000
        })
        if resp.get("code") == 0:
            print("SUCCESS: Result:", json.dumps(resp, indent=2))
            break
        else:
            print(f"Attempt {attempt}/{max_retries} failed: {resp.get('error')}")
            if attempt < max_retries:
                time.sleep(2)
    except Exception as e:
        print(f"Attempt {attempt}/{max_retries} error: {e}")
        if attempt < max_retries:
            time.sleep(2)
else:
    print("All retries failed.")
    sys.exit(1)