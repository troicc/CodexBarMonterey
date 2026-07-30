#!/usr/bin/env python3
import json, pathlib, urllib.request
root = pathlib.Path(__file__).resolve().parents[1]
with urllib.request.urlopen("https://api.github.com/repos/steipete/CodexBar/releases/latest") as response:
    latest = json.load(response)["tag_name"]
path = root / "ENGINE_VERSION"
current = path.read_text().strip()
if latest != current:
    path.write_text(latest + "\n")
    print(f"updated:{current}->{latest}")
else:
    print("unchanged")
