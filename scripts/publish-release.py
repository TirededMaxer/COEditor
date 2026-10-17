#!/usr/bin/env python3
"""Publish cloud artifacts only after verification; remove predecessors last."""
import argparse
import hashlib
import json
import os
import plistlib
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


def gh(*args):
    return subprocess.check_output(["gh", *args])


def api(repository, endpoint, *args):
    return json.loads(gh("api", f"repos/{repository}/{endpoint}", *args))


def verify_assets(repository, release, directory, names):
    assets = {asset["name"]: asset for asset in release["assets"]}
    if set(assets) != set(names):
        raise RuntimeError("Release asset list does not match build outputs")
    for name in names:
        asset = assets[name]
        local = (directory / name).read_bytes()
        digest = hashlib.sha256(local).hexdigest()
        if asset["state"] != "uploaded" or asset["size"] != len(local) or asset.get("digest") != "sha256:" + digest:
            raise RuntimeError("Incomplete or mismatched remote asset: " + name)
        downloaded = gh("api", f"repos/{repository}/releases/assets/{asset['id']}", "-H", "Accept: application/octet-stream")
        if downloaded != local:
            raise RuntimeError("Downloaded asset does not match: " + name)


def publish(repository, tag, directory):
    version = plistlib.loads((REPO / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
    commit = os.environ["GITHUB_SHA"]
    if tag != "v" + version:
        raise RuntimeError("Tag must match Resources/Info.plist")
    info = json.loads((directory / "BUILDINFO.json").read_text())
    if info["commit"] != commit or info["builder"] != "GitHub Actions":
        raise RuntimeError("Artifacts must come from this cloud commit")
    names = [f"COEditor-{version}-macOS-arm64.dmg", "SHA256SUMS", "BUILDINFO.json"]
    subprocess.run(["sha256sum", "-c", "SHA256SUMS"], cwd=directory, check=True)
    existing = api(repository, "releases?per_page=100")
    current = next((r for r in existing if r["tag_name"] == tag), None)
    if current and not current["draft"]:
        raise RuntimeError("This version is already published; use a new version")
    notes = (REPO / "docs/RELEASE_NOTES.md").read_text()
    heading = f"# COEditor {version}\n"
    if heading not in notes:
        raise RuntimeError("Missing release notes for " + version)
    body = heading + notes.split(heading, 1)[1].split("\n# COEditor ", 1)[0]
    body += f"\n云端构建：{info['workflow_run']}。编译器与来源见 BUILDINFO.json。\n"
    with tempfile.TemporaryDirectory() as temporary:
        notes_file = Path(temporary) / "release.md"
        notes_file.write_text(body)
        if current is None:
            gh("release", "create", tag, "--repo", repository, "--verify-tag", "--title", "COEditor " + version, "--notes-file", str(notes_file), "--draft")
        else:
            gh("release", "edit", tag, "--repo", repository, "--notes-file", str(notes_file))
        gh("release", "upload", tag, "--repo", repository, "--clobber", *[str(directory / name) for name in names])
    release = next(r for r in api(repository, "releases?per_page=100") if r["tag_name"] == tag)
    verify_assets(repository, release, directory, names)
    published = api(repository, f"releases/{release['id']}", "--method", "PATCH", "-F", "draft=false", "-f", "make_latest=true")
    if published["draft"] or api(repository, "releases/latest")["id"] != release["id"]:
        raise RuntimeError("New release was not confirmed as latest; old releases preserved")
    # Deletion is deliberately last, after a full remote download and publish check.
    for old in existing:
        if old["id"] != release["id"] and not old["draft"]:
            gh("release", "delete", old["tag_name"], "--repo", repository, "--yes")
    print(published["html_url"])
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as output:
            output.write(f"Published [{tag}]({published['html_url']}); remote assets verified; older releases removed.\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--directory", type=Path, required=True)
    arguments = parser.parse_args()
    publish(os.environ["GITHUB_REPOSITORY"], arguments.tag, arguments.directory.resolve())
