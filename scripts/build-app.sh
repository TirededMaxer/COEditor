#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_mode="${1:-release}"
case "$build_mode" in release) optimization=-O; c_optimization=-O2;; debug) optimization=-Onone; c_optimization=-O0;; *) echo 'Usage: build-app.sh [release|debug]' >&2; exit 2;; esac
output_dir="$repo_root/build/$build_mode"
rm -rf "$output_dir"
app="$output_dir/COEditor.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$output_dir/modules"
xcrun swiftc "$optimization" -target arm64-apple-macosx13.0 -module-cache-path "$output_dir/modules"  "$repo_root/Sources/COEditor/WheelBridge.swift" "$repo_root/Sources/COEditor/WheelStatusTests.swift" "$repo_root/Sources/COEditor/WindowFocus.swift" "$repo_root/Sources/COEditor/SteamLibrary.swift" "$repo_root/Sources/COEditor/Tuner.swift" "$repo_root/Sources/COEditor/FrameStats.swift"  -o "$output_dir/CrossOverTuner.new" -framework SwiftUI -framework AppKit
mv "$output_dir/CrossOverTuner.new" "$app/Contents/MacOS/CrossOverTuner"
cp "$repo_root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$repo_root/Resources/Tuner.icns" "$app/Contents/Resources/Tuner.icns"
helper="$app/Contents/Resources/COEditor Wheel.app"
mkdir -p "$helper/Contents/MacOS"
xcrun clang "$c_optimization" -Wall -Wextra -Wno-unused-parameter -fobjc-arc -target arm64-apple-macosx13.0 "$repo_root/Sources/WheelBridge/main.m" -o "$helper/Contents/MacOS/COEditorWheel" -framework AppKit -framework IOKit
cp "$repo_root/Resources/WheelInfo.plist" "$helper/Contents/Info.plist"
codesign --force --sign - --identifier local.coeditor.wheel.protocol2 "$helper"
codesign --verify --strict "$helper"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
printf 'Built: %s\n' "$app"
