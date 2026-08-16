#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ZAPI Bridge Test Suite – Full Bidirectional Demo
Includes calling PHP webhook and sending notifications.
"""

import json
import urllib.request
import urllib.error
import sys
import time

BRIDGE_URL = "http://127.0.0.1:8080/v1"

def http_post(endpoint, payload):
    url = f"{BRIDGE_URL}{endpoint}"
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read().decode('utf-8'))
            return body
        except:
            return {"code": -1, "error": f"HTTP {e.code}: {e.reason}"}
    except urllib.error.URLError as e:
        return {"code": -1, "error": f"Connection failed: {e.reason}"}

def http_get(endpoint):
    url = f"{BRIDGE_URL}{endpoint}"
    req = urllib.request.Request(url, headers={'Accept': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except urllib.error.URLError as e:
        return {"error": f"Connection failed: {e.reason}"}

def print_result(label, data):
    print(f"\n{label}:")
    print(f"  {json.dumps(data, indent=2)}")

def test_health():
    data = http_get("/health")
    print_result("Health Check", data)
    return data.get("status") == "ok"

def test_invoke():
    payload = {"app": "CalcService", "api": "add", "args": [10, 20], "timeout": 5000}
    data = http_post("/invoke", payload)
    print_result("Invoke CalcService.add", data)
    return data.get("code") == 0 and data.get("result") == 30

def test_notify():
    payload = {"app": "LogService", "api": "log", "args": ["INFO", "Python test notify"]}
    data = http_post("/notify", payload)
    print_result("Notify LogService.log", data)
    return data.get("code") == 0

def test_register_python_hook():
    """Register Python's own webhook (so PHP can call it)."""
    # Python will act as a webhook server on port 9001 (we'll start one)
    payload = {
        "app": "PyApp",
        "api": "echo",
        "callback_url": "http://127.0.0.1:9001/webhook",
        "mode": "call"
    }
    data = http_post("/hooks/register", payload)
    print_result("Register PyApp.echo", data)
    return data.get("code") == 0

def test_register_php_hook():
    """Assume PHP has already registered its webhook (done by client_test.php)."""
    # We just list hooks to verify.
    data = http_get("/hooks/list")
    print_result("Current hooks", data)
    # Check if MyApp.echo exists (registered by PHP)
    hooks = data.get("hooks", [])
    return any(h.get("app") == "MyApp" and h.get("api") == "echo" for h in hooks)

def test_call_php_webhook():
    payload = {"app": "HttpBridge", "api": "echo", "args": ["Hello from Python via Bridge!"], "timeout": 5000}
    data = http_post("/invoke", payload)
    print_result("Call PHP webhook (HttpBridge.echo)", data)
    return data.get("code") == 0

def test_notify_php_webhook():
    payload = {"app": "HttpBridge", "api": "log", "args": ["INFO", "Python says hi via notify"]}
    data = http_post("/notify", payload)
    print_result("Notify PHP webhook (HttpBridge.log)", data)
    return data.get("code") == 0

def main():
    print("=== ZAPI Bridge Full Bidirectional Test ===\n")
    if not test_health():
        print("❌ Bridge not reachable. Start it first.")
        sys.exit(1)
    print("✅ Bridge healthy")

    # ---- Python as client: call existing ZAPI services ----
    test_invoke()
    test_notify()

    # ---- Register Python's own webhook (for PHP to call) ----
    # Note: We must start a Python webhook server (port 9001) before PHP calls it.
    # We'll include a separate server script or start it inline.
    test_register_python_hook()

    # ---- Check if PHP has registered its webhook ----
    if not test_register_php_hook():
        print("⚠️ PHP webhook (MyApp.echo) not found. Run client_test.php first.")

    # ---- Call PHP webhook from Python ----
    test_call_php_webhook()

    # ---- Notify PHP webhook from Python ----
    test_notify_php_webhook()

    print("\n🏁 Test suite completed.")
    print("Check the PHP webhook server terminal for received requests.")

if __name__ == "__main__":
    main()