#!/usr/bin/env python3
"""Verify relocated CLI resources, including through an installation symlink."""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

source = pathlib.Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="document-ai-install-") as directory:
    root = pathlib.Path(directory)
    install = root / "libexec"
    install.mkdir()
    binary = install / "google-document-ocr-gateway"
    shutil.copy2(source / binary.name, binary)
    bundles = list(source.glob("*.bundle")) + list(source.glob("*.resources"))
    assert bundles, "No resource bundle was built"
    for bundle in bundles:
        shutil.copytree(bundle, install / bundle.name)
    link = root / "google-document-ocr-gateway"
    link.symlink_to(binary)
    for command in [binary, link]:
        for version, count in [("v1", 42), ("v1beta3", 48)]:
            result = json.loads(subprocess.check_output(
                [str(command), "methods", "--api-version", version], cwd=root
            ))
            assert len(result["data"]) == count
    # Prove discovery loads from the installed bundle, not SwiftPM's build-path fallback.
    snapshot = next(install.rglob("documentai-v1.json"))
    discovery = json.loads(snapshot.read_text())
    discovery.setdefault("methods", {})["installationProbe"] = {
        "id": "documentai.installationProbe", "httpMethod": "GET", "path": "v1/probe"
    }
    snapshot.write_text(json.dumps(discovery))
    for command in [binary, link]:
        result = json.loads(subprocess.check_output([str(command), "methods"], cwd=root))
        assert any(method["id"] == "documentai.installationProbe" for method in result["data"]), str(command)
print("Relocated CLI and symlink load installed resources for both API versions")
