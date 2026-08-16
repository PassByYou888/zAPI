#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
多线程 Python Webhook 服务器（更快）
"""
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
import socketserver

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/webhook':
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode('utf-8'))
                print(f"[Python Webhook] Received: {data}")
                response = {"status": "ok", "received": data}
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(response).encode('utf-8'))
            except Exception as e:
                print(f"[Python Webhook] Error: {e}")
                self.send_response(400)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # 减少日志开销

class ThreadingHTTPServer(socketserver.ThreadingMixIn, HTTPServer):
    daemon_threads = True

def run_server(port=9001):
    server = ThreadingHTTPServer(('', port), WebhookHandler)
    print(f"[Python Webhook] Listening on port {port} (multi-threaded)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[Python Webhook] Shutting down...")
        server.shutdown()

if __name__ == "__main__":
    run_server()