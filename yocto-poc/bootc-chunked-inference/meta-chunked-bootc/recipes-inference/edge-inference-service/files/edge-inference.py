#!/usr/bin/env python3
import json, os
from http.server import BaseHTTPRequestHandler, HTTPServer

MODEL = os.environ.get("EDGE_MODEL_PATH", "/opt/edge-inference/model/model.json")
MANIFEST = os.path.join(os.path.dirname(MODEL), "model-manifest.json")
with open(MODEL) as f:
    model = json.load(f)
with open(MANIFEST) as f:
    manifest = json.load(f)

class Handler(BaseHTTPRequestHandler):
    def send_json(self, code, value):
        body = json.dumps(value).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        if self.path == "/healthz": self.send_json(200, {"ok": True})
        elif self.path == "/ready": self.send_json(200, {"ready": True})
        elif self.path == "/version": self.send_json(200, {"model": model.get("model"), "version": manifest.get("version"), "sha256": manifest.get("sha256")})
        elif self.path == "/metrics": self.send_response(200); self.end_headers(); self.wfile.write(b"edge_inference_ready 1\n")
        else: self.send_json(404, {"error": "not found"})
    def do_POST(self):
        if self.path != "/infer": self.send_json(404, {"error": "not found"}); return
        data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
        x = float(data["input"]); self.send_json(200, {"output": model["weight"] * x + model["bias"]})
    def log_message(self, *_): pass

HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
