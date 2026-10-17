#!/usr/bin/env python3
"""Fetch a fresh official Wine source tree; never use a local build cache."""
import argparse
import copy
import hashlib
import json
import shutil
import tarfile
import tempfile
import urllib.request
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("destination", type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
metadata = json.loads((repo / "patches/wine-26.3/files.json").read_text())
destination = args.destination.resolve()
if destination.exists():
    parser.error("destination must not exist")
with tempfile.TemporaryDirectory(prefix="coeditor-source-") as temporary:
    archive = Path(temporary) / "source.tar.gz"
    print("Downloading " + metadata["source"], flush=True)
    with urllib.request.urlopen(metadata["source"], timeout=120) as response, archive.open("wb") as output:
        shutil.copyfileobj(response, output)
    digest = hashlib.file_digest(archive.open("rb"), "sha256").hexdigest()
    with tarfile.open(archive) as tar:
        members = tar.getmembers()
        configure = next((m for m in members if m.isfile() and m.name.endswith("/wine/configure")), None)
        if configure is None:
            raise SystemExit("Official archive does not contain sources/wine/configure")
        prefix = configure.name.removesuffix("configure")
        selected = []
        for member in members:
            if member.name.startswith(prefix) and member.name != prefix:
                item = copy.copy(member)
                item.name = member.name[len(prefix):]
                if item.islnk() and item.linkname.startswith(prefix):
                    item.linkname = item.linkname[len(prefix):]
                selected.append(item)
        destination.mkdir(parents=True)
        tar.extractall(destination, members=selected, filter="data")
(destination / "coeditor-source.json").write_text(json.dumps({
    "url": metadata["source"], "archive_sha256": digest, "base": metadata["base"]
}, indent=2) + "\n")
print(f"Fetched {metadata['base']} (archive SHA-256 {digest})")
