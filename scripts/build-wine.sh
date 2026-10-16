#!/bin/bash
# Build the coupled Unix modules in an already configured CrossOver 26.3 Wine tree.
set -euo pipefail
if [ "$#" -ne 2 ]; then echo 'Usage: build-wine.sh WINE_SOURCE WINE_BUILD' >&2; exit 2; fi
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$repo_root/scripts/apply-wine-patch.py" "$1" --verify
make -C "$2" -j "${JOBS:-6}" server/wineserver dlls/ntdll/ntdll.so dlls/win32u/win32u.so dlls/winemac.drv/winemac.so
