#!/usr/bin/env python3
import json, os
from http.server import BaseHTTPRequestHandler, HTTPServer

MODEL = os.environ.get("EDGE_MODEL_PATH", "/opt/edge-inference/model/model.json")
MANIFEST = os.path.join(os.path.dirname(MODEL), "model-manifest.json")
with open(MODEL) as f:
    model = json.load(f)
with open(MANIFEST) as f:
    manifest = json.load(f)

def predict(data):
    if model.get("format") == "anomalynet-mlp":
        samples = [float(x) for x in data["samples"]]
        if len(samples) != model["window"]:
            raise ValueError("samples must contain %d values" % model["window"])
        x = [(value - model["mean"]) / model["scale"] for value in samples]
        hidden = []
        for weights, bias in zip(model["fc1_weight"], model["fc1_bias"]):
            hidden.append(max(0.0, sum(w * value for w, value in zip(weights, x)) + bias))
        logits = [sum(w * value for w, value in zip(weights, hidden)) + bias
                  for weights, bias in zip(model["fc2_weight"], model["fc2_bias"])]
        peak = max(logits)
        probabilities = [pow(2.718281828459045, value - peak) for value in logits]
        total = sum(probabilities)
        probabilities = [value / total for value in probabilities]
        label = model["classes"][probabilities.index(max(probabilities))]
        return {"classification": label, "probability": max(probabilities),
                "logits": logits, "classes": model["classes"]}
    x = float(data["input"])
    return {"output": model["weight"] * x + model["bias"]}

class Handler(BaseHTTPRequestHandler):
    def send_json(self, code, value):
        body = json.dumps(value).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        if self.path == "/healthz": self.send_json(200, {"ok": True})
        elif self.path == "/ready": self.send_json(200, {"ready": True})
        elif self.path == "/version": self.send_json(200, {"model": model.get("model"), "version": manifest.get("version"), "sha256": manifest.get("sha256"), "format": manifest.get("format")})
        elif self.path == "/metrics": self.send_response(200); self.end_headers(); self.wfile.write(b"edge_inference_ready 1\n")
        else: self.send_json(404, {"error": "not found"})
    def do_POST(self):
        if self.path != "/infer": self.send_json(404, {"error": "not found"}); return
        data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
        try:
            self.send_json(200, predict(data))
        except (KeyError, TypeError, ValueError) as error:
            self.send_json(400, {"error": str(error)})
    def log_message(self, *_): pass

HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
