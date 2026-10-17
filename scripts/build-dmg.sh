#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app="$repo_root/build/release/COEditor.app"
[ -d "$app" ] || { echo 'Run scripts/build-app.sh first' >&2; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
codesign --verify --strict "$app"
staging=$(mktemp -d "$repo_root/build/dmg-stage.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/COEditor.app"
ln -s /Applications "$staging/Applications"
cp "$repo_root/LICENSE" "$staging/LICENSE.txt"
cat > "$staging/安装说明.txt" <<'TXT'
COEditor

把 COEditor.app 拖入 Applications（应用程序）。
本工具管理已经配置好的 CrossOver 26.3 补丁环境与 Steam 容器。
DMG 不包含 CrossOver 商业运行时、Steam 或游戏，也不会自动安装补丁引擎。
已有补丁环境的用户可直接替换旧调整器，配置继续保留。

Apple Silicon；构建目标 macOS 13+，实际验证 macOS 27.0.1。
ad-hoc 签名，未进行 Developer ID 签名或 Apple 公证。
如 macOS 拦截，请在“系统设置 → 隐私与安全性”中允许打开。

源码、首次配置和构建说明：
https://github.com/TirededMaxer/COEditor
TXT
output="$repo_root/build/COEditor-$version-macOS-arm64.dmg"
if [ -e "$output" ]; then echo "Output already exists: $output" >&2; exit 1; fi
hdiutil create -volname COEditor -srcfolder "$staging" -ov -format UDZO "$output"
python3 "$repo_root/scripts/write-build-info.py" "$output"
(cd "$repo_root/build" && shasum -a 256 "$(basename "$output")" BUILDINFO.json > SHA256SUMS)
printf 'Built: %s\n' "$output"
