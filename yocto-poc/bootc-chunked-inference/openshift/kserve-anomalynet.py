#!/usr/bin/env python3
"""Dependency-free KServe v2 HTTP adapter for a JSON AnomalyNet release."""

import json
import math
import os
from http.server import BaseHTTPRequestHandler, HTTPServer


MODEL_DIR = os.environ.get("ANOMALYNET_MODEL_DIR", "/mnt/models")
with open(os.path.join(MODEL_DIR, "model.json"), encoding="utf-8") as stream:
    model = json.load(stream)
with open(os.path.join(MODEL_DIR, "model-manifest.json"), encoding="utf-8") as stream:
    manifest = json.load(stream)


def predict(samples):
    if len(samples) != model["window"]:
        raise ValueError("samples must contain %d values" % model["window"])
    normalized = [(float(value) - model["mean"]) / model["scale"] for value in samples]
    hidden = []
    for weights, bias in zip(model["fc1_weight"], model["fc1_bias"]):
        hidden.append(max(0.0, sum(w * value for w, value in zip(weights, normalized)) + bias))
    logits = [sum(w * value for w, value in zip(weights, hidden)) + bias
              for weights, bias in zip(model["fc2_weight"], model["fc2_bias"])]
    peak = max(logits)
    probabilities = [math.exp(value - peak) for value in logits]
    total = sum(probabilities)
    probabilities = [value / total for value in probabilities]
    index = probabilities.index(max(probabilities))
    return {
        "classification": model["classes"][index],
        "probability": probabilities[index],
        "logits": logits,
        "classes": model["classes"],
    }


class Handler(BaseHTTPRequestHandler):
    def send_json(self, code, value):
        body = json.dumps(value).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/healthz", "/v2/health/live"):
            self.send_json(200, {"ok": True})
        elif self.path in ("/ready", "/v2/health/ready"):
            self.send_json(200, {"ready": True})
        elif self.path == "/version":
            self.send_json(200, {"model": model.get("model"), "version": manifest.get("version"),
                                 "sha256": manifest.get("sha256"), "format": manifest.get("format")})
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        if not self.path.endswith("/infer"):
            self.send_json(404, {"error": "not found"})
            return
        try:
            request = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
            if "samples" in request:
                result = predict(request["samples"])
            else:
                values = request["inputs"][0]["data"]
                result = predict(values)
            self.send_json(200, result)
        except (KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError) as error:
            self.send_json(400, {"error": str(error)})

    def log_message(self, *_):
        pass


HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
