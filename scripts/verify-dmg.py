#!/usr/bin/env python3
"""Mount the DMG read-only and compare its entire application bundle."""
import hashlib
import plistlib
import subprocess
import tempfile
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
source = repo / "build/release/COEditor.app"
version = plistlib.loads((source / "Contents/Info.plist").read_bytes())["CFBundleShortVersionString"]
dmg = repo / f"build/COEditor-{version}-macOS-arm64.dmg"
subprocess.run(["hdiutil", "verify", str(dmg)], check=True)
with tempfile.TemporaryDirectory(prefix="coeditor-dmg-") as temporary:
    mount = Path(temporary) / "volume"
    subprocess.run(["hdiutil", "attach", str(dmg), "-readonly", "-nobrowse", "-mountpoint", str(mount)], check=True)
    try:
        app = mount / "COEditor.app"
        subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
        source_files = {p.relative_to(source) for p in source.rglob("*") if p.is_file()}
        mounted_files = {p.relative_to(app) for p in app.rglob("*") if p.is_file()}
        assert source_files == mounted_files, "Unexpected bundle contents"
        for relative in source_files:
            assert hashlib.sha256((source / relative).read_bytes()).digest() == hashlib.sha256((app / relative).read_bytes()).digest(), str(relative)
        assert (mount / "Applications").readlink() == Path("/Applications")
    finally:
        subprocess.run(["hdiutil", "detach", str(mount)], check=True)
subprocess.run(["shasum", "-a", "256", "-c", "SHA256SUMS"], cwd=repo / "build", check=True)
print("PASS: DMG signature, full bundle, Applications shortcut and checksums")
