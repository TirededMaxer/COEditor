#!/bin/bash
set -euo pipefail
if [ "$#" -ne 3 ]; then echo 'Usage: build-proxy.sh WINE_SOURCE GENERATED_INCLUDE KERNEL32_IMPORT_LIBRARY' >&2; exit 2; fi
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
wine_source="$(cd "$1" && pwd)"
headers="$(cd "$2" && pwd)"
kernel32="$3"
clang_bin="${PE_CLANG:-$(brew --prefix llvm)/bin/clang}"
link_bin="${PE_LINK:-$(command -v lld-link)}"
mkdir -p "$repo_root/build/proxy"
"$clang_bin" --target=x86_64-w64-windows-gnu -O2 -ffreestanding -fno-stack-protector  -Wno-dll-attribute-on-redeclaration -I "$headers" -I "$wine_source/include/msvcrt" -I "$wine_source/include"  -c "$repo_root/Sources/D3D11Proxy/d3d11_queue_proxy.c" -o "$repo_root/build/proxy/proxy.obj"
"$link_bin" /dll /noentry /nodefaultlib "/out:$repo_root/build/proxy/d3d11.dll"  "$repo_root/build/proxy/proxy.obj" "$kernel32"
printf 'Built: %s\n' "$repo_root/build/proxy/d3d11.dll"
