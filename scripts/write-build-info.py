#!/usr/bin/env python3
"""Record cloud provenance alongside the DMG, without local environment paths."""
import hashlib
import json
import os
import plistlib
import subprocess
import sys
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
dmg = Path(sys.argv[1]).resolve()
info = plistlib.loads((repo / "Resources/Info.plist").read_bytes())
commit = os.environ.get("GITHUB_SHA") or subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
run = os.environ.get("GITHUB_RUN_ID")
repository = os.environ.get("GITHUB_REPOSITORY", "TirededMaxer/COEditor")
data = {
    "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
    "commit": commit, "builder": "GitHub Actions" if run else "manual",
    "workflow_run": f"https://github.com/{repository}/actions/runs/{run}" if run else None,
    "runner": os.environ.get("RUNNER_OS"), "architecture": os.environ.get("RUNNER_ARCH"),
    "swift": subprocess.check_output(["xcrun", "swiftc", "--version"], text=True).strip(),
    "dmg": dmg.name, "dmg_sha256": hashlib.sha256(dmg.read_bytes()).hexdigest()
}
(dmg.parent / "BUILDINFO.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
