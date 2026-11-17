#!/usr/bin/env python3
"""Small guest-local device simulator used by Phase 5 VM tests.

The agent deliberately has no cluster dependency.  A VM may provide
``edge.device-id=`` and ``edge.temperature=`` on its kernel command line;
otherwise stable defaults are used.  The current state is written under
/run/edge-device so a health probe can verify identity, sensor input, and the
bootc deployment without changing the immutable /usr tree.
"""
import json
import os
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

STATE_DIR = "/run/edge-device"


def cmdline_value(name, default):
    try:
        cmdline = open("/proc/cmdline", encoding="utf-8").read().split()
    except OSError:
        cmdline = []
    prefix = name + "="
    for value in cmdline:
        if value.startswith(prefix):
            return value[len(prefix):]
    return default


def config_value(path, key, default):
    try:
        with open(path, encoding="utf-8") as source:
            value = json.load(source).get(key, default)
            return str(value)
    except (OSError, ValueError, TypeError):
        return default


def state():
    device_id = cmdline_value(
        "edge.device-id",
        os.environ.get(
            "EDGE_DEVICE_ID",
            config_value("/etc/edge-device/identity", "device_id", "edge-unknown"),
        ),
    )
    raw_temperature = cmdline_value(
        "edge.temperature",
        os.environ.get(
            "EDGE_TEMPERATURE",
            config_value("/etc/edge-device/sensor.json", "temperature_c", "25.0"),
        ),
    )
    try:
        temperature = float(raw_temperature)
    except ValueError:
        temperature = 25.0
    return {
        "device_id": device_id,
        "temperature_c": temperature,
        "sensor": "simulated",
        "bootc_status": "/run/ostree-booted",
        "timestamp_unix": int(time.time()),
    }


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ("/healthz", "/status"):
            self.send_error(404)
            return
        payload = json.dumps(state(), sort_keys=True).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_args):
        return


def main():
    os.makedirs(STATE_DIR, mode=0o755, exist_ok=True)
    with open(os.path.join(STATE_DIR, "status.json"), "w", encoding="utf-8") as output:
        json.dump(state(), output, sort_keys=True)
        output.write("\n")
    HTTPServer(("0.0.0.0", 8090), Handler).serve_forever()


if __name__ == "__main__":
    main()
