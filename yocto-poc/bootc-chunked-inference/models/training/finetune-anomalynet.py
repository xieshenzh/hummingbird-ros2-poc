#!/usr/bin/env python3
"""Fine-tune the published edge AnomalyNet and export a bootc model release.

Training is intentionally outside BitBake. The script starts from the
Apache-2.0 model published at eoinedge/AnomalyNet, fine-tunes it on the
published heater-anomaly-windows dataset, and exports a small JSON model that
the target's dependency-free service can execute. The JSON contains the
actual trained weights, not a mock formula.

Host dependencies: torch, datasets. The target image only needs Python 3.
"""

import argparse
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen

import torch
import torch.nn as nn
from datasets import load_dataset

WINDOW = 32
MEAN = 50.0
SCALE = 20.0
CLASSES = ["normal", "anomaly"]
MODEL_URL = "https://huggingface.co/eoinedge/AnomalyNet/resolve/main/anomaly_net.pt"


class AnomalyNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(WINDOW, 24)
        self.fc2 = nn.Linear(24, 2)

    def forward(self, x):
        return self.fc2(torch.relu(self.fc1(x)))


def load_base(path):
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(urlopen(MODEL_URL, timeout=60).read())
    model = AnomalyNet()
    model.load_state_dict(torch.load(path, map_location="cpu", weights_only=True))
    return model


def tensors(split):
    columns = [[float(row["t%d" % i]) for i in range(WINDOW)] for row in split]
    labels = [int(row["label"]) for row in split]
    return ((torch.tensor(columns, dtype=torch.float32) - MEAN) / SCALE,
            torch.tensor(labels, dtype=torch.long))


def evaluate(model, x, y):
    model.eval()
    with torch.no_grad():
        return float((model(x).argmax(1) == y).float().mean())


def export(model, version, output, metrics):
    state = model.state_dict()
    artifact = {
        "model": "AnomalyNet", "format": "anomalynet-mlp", "window": WINDOW,
        "mean": MEAN, "scale": SCALE, "classes": CLASSES,
        "fc1_weight": state["fc1.weight"].tolist(),
        "fc1_bias": state["fc1.bias"].tolist(),
        "fc2_weight": state["fc2.weight"].tolist(),
        "fc2_bias": state["fc2.bias"].tolist(),
    }
    output.mkdir(parents=True, exist_ok=True)
    model_path = output / "model.json"
    model_path.write_text(json.dumps(artifact, sort_keys=True, separators=(",", ":")) + "\n")
    digest = hashlib.sha256(model_path.read_bytes()).hexdigest()
    manifest = {"version": version, "format": "json-anomalynet",
                "model": "eoinedge/AnomalyNet", "sha256": digest,
                "window": WINDOW, "classes": CLASSES, "metrics": metrics}
    (output / "model-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (output / "checksums.txt").write_text("%s  model.json\n" % digest)
    print("wrote %s (%d bytes)" % (model_path, model_path.stat().st_size))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", default="anomalynet-v1")
    parser.add_argument("--output", type=Path, default=Path("models/anomalynet-v1"))
    parser.add_argument("--recipe-files", type=Path,
                        default=Path("meta-chunked-bootc/recipes-inference/edge-inference-model/files"))
    parser.add_argument("--base-state", type=Path, default=Path("artifacts/anomaly_net.pt"))
    parser.add_argument("--dataset", default="eoinedge/heater-anomaly-windows")
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--lr", type=float, default=1e-4)
    parser.add_argument("--batch-size", type=int, default=128)
    args = parser.parse_args()

    dataset = load_dataset(args.dataset)
    train_x, train_y = tensors(dataset["train"])
    test_x, test_y = tensors(dataset["test"])
    model = load_base(args.base_state)
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
    for epoch in range(args.epochs):
        model.train()
        order = torch.randperm(len(train_y))
        for start in range(0, len(order), args.batch_size):
            index = order[start:start + args.batch_size]
            optimizer.zero_grad()
            loss = nn.functional.cross_entropy(model(train_x[index]), train_y[index])
            loss.backward()
            optimizer.step()
        print("epoch %d/%d: test_accuracy=%.4f" %
              (epoch + 1, args.epochs, evaluate(model, test_x, test_y)))
    metrics = {"test_accuracy": evaluate(model, test_x, test_y)}
    export(model, args.version, args.output, metrics)
    recipe_release = args.recipe_files / args.version
    recipe_release.mkdir(parents=True, exist_ok=True)
    for name in ("model.json", "model-manifest.json"):
        (recipe_release / name).write_bytes((args.output / name).read_bytes())
    print("synced BitBake release to %s" % recipe_release)


if __name__ == "__main__":
    main()
