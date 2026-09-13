#!/usr/bin/env python3
"""Compare vendored API methods, parameters and schemas with Google's current API."""
import json
import pathlib
import urllib.request

root = pathlib.Path(__file__).resolve().parents[2]
base = root / "Sources/AppCore/Resources"

def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.load(response)

def methods(resource):
    result = {method["id"]: method for method in resource.get("methods", {}).values()}
    for child in resource.get("resources", {}).values():
        result.update(methods(child))
    return result

index = fetch("https://discovery.googleapis.com/discovery/v1/apis?name=documentai")
versions = {item["version"] for item in index["items"]}
assert versions == {"v1", "v1beta3"}, f"API version coverage changed: {versions}"
for item in sorted(index["items"], key=lambda item: item["version"]):
    version = item["version"]
    current = fetch(item["discoveryRestUrl"])
    bundled = json.loads((base / f"documentai-{version}.json").read_text())
    assert methods(current) == methods(bundled), f"{version} method metadata changed"
    assert current["schemas"] == bundled["schemas"], f"{version} schemas changed"
    assert current["parameters"] == bundled["parameters"], f"{version} global parameters changed"
    print(f"{version}: {len(methods(current))} methods and {len(current['schemas'])} schemas match Google revision {current['revision']}")
