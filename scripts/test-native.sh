#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
out="$repo_root/build/tests"
mkdir -p "$out"
xcrun clang -Wall -Wextra "$repo_root/tests/config_parser_test.c" -o "$out/config_parser_test"
"$out/config_parser_test"
xcrun clang -Wall -Wextra "$repo_root/tests/wheel_raw_tests.c" -o "$out/wheel_raw_tests"
"$out/wheel_raw_tests"
xcrun clang "$repo_root/tests/native_delta_tests.m" -o "$out/native_delta_tests" -framework AppKit
"$out/native_delta_tests"
python3 "$repo_root/tests/check-patch-headers.py"

xcrun clang -Wall -Wextra "$repo_root/tests/frame_control_test.c" -o "$out/frame_control_test"
"$out/frame_control_test"
