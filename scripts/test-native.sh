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

xcrun clang -Wall -Wextra "$repo_root/tests/wheel_bridge_test.c" -o "$out/wheel_bridge_test"
"$out/wheel_bridge_test"

python3 - "$repo_root" "$out" <<'PY_HEADER'
import sys
from pathlib import Path
repo,out=map(Path,sys.argv[1:])
patch=(repo/'patches/wine-26.3/coeditor.patch').read_text()
part=patch.split('+++ b/dlls/winemac.drv/sevo_ui_policy.h\n',1)[1].split('--- ',1)[0]
(out/'sevo_ui_policy.h').write_text(''.join(line[1:] for line in part.splitlines(True) if line.startswith('+')))
PY_HEADER
xcrun clang -Wall -Wextra -I "$out" "$repo_root/tests/sevo_ui_policy_test.c" -o "$out/sevo_ui_policy_test"
"$out/sevo_ui_policy_test"

xcrun clang -Wall -Wextra "$repo_root/tests/wheel_lease_client.c" -o "$out/wheel_lease_client"
python3 "$repo_root/tests/test-wheel-lifecycle.py" --app "$repo_root/build/release/COEditor.app" --client "$out/wheel_lease_client"
