#!/bin/bash
# Complete source build on a clean Intel macOS runner; no installed CrossOver needed.
set -euo pipefail
if [ "$#" -ne 2 ]; then echo 'Usage: build-wine-clean.sh WINE_SOURCE NEW_BUILD_DIRECTORY' >&2; exit 2; fi
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
wine_source="$(cd "$1" && pwd)"
[ ! -e "$2" ] || { echo 'Build directory must not exist' >&2; exit 1; }
mkdir -p "$2"
wine_build="$(cd "$2" && pwd)"
python3 "$repo_root/scripts/apply-wine-patch.py" "$wine_source"
(
  cd "$wine_build"
  "$wine_source/configure" --enable-win64 --host=x86_64-apple-darwin \
    --without-x --without-wayland --without-alsa --without-pulse \
    --without-dbus --without-gstreamer --without-unwind --with-vulkan \
    CC=clang CXX=clang++ OBJC=clang \
    "CPPFLAGS=-I$(brew --prefix molten-vk)/include" \
    "LDFLAGS=-L$(brew --prefix molten-vk)/lib"
)
"$repo_root/scripts/build-wine.sh" "$wine_source" "$wine_build"
make -C "$wine_build" -j "${JOBS:-4}" include/d3d11.h include/dxgi.h dlls/kernel32/x86_64-windows/libkernel32.a dlls/user32/x86_64-windows/libuser32.a
PE_CLANG="$(command -v clang)" PE_LINK="$(command -v lld-link)" \
  "$repo_root/scripts/build-proxy.sh" "$wine_source" "$wine_build/include" \
  "$wine_build/dlls/kernel32/x86_64-windows/libkernel32.a"
# Build the real D3D11 rendering probe in the cloud as well; it is not shipped in the DMG.
clang --target=x86_64-w64-windows-gnu -O2 -ffreestanding -fno-stack-protector \
  -Wno-dll-attribute-on-redeclaration -I "$wine_build/include" -I "$wine_source/include/msvcrt" -I "$wine_source/include" \
  -c "$repo_root/tests/d3d11_tuner_regression.c" -o "$repo_root/build/proxy/probe.obj"
lld-link /entry:mainCRTStartup /subsystem:windows /nodefaultlib \
  "/out:$repo_root/build/proxy/coeditor-probe.exe" "$repo_root/build/proxy/probe.obj" \
  "$wine_build/dlls/kernel32/x86_64-windows/libkernel32.a" "$wine_build/dlls/user32/x86_64-windows/libuser32.a"
clang --target=x86_64-w64-windows-gnu -O2 -ffreestanding -fno-stack-protector \
  -Wno-dll-attribute-on-redeclaration -I "$wine_build/include" -I "$wine_source/include/msvcrt" -I "$wine_source/include" \
  -c "$repo_root/tests/wheel_input_probe.c" -o "$repo_root/build/proxy/wheel-probe.obj"
lld-link /entry:mainCRTStartup /subsystem:windows /nodefaultlib \
  "/out:$repo_root/build/proxy/wheel-input-probe.exe" "$repo_root/build/proxy/wheel-probe.obj" \
  "$wine_build/dlls/kernel32/x86_64-windows/libkernel32.a" "$wine_build/dlls/user32/x86_64-windows/libuser32.a"
components="$repo_root/build/wine-components"
mkdir -p "$components"
for name in ntdll win32u; do
  cp "$wine_build/dlls/$name/$name.so" "$components/"
done
cp "$wine_build/dlls/winemac.drv/winemac.so" "$components/"
cp "$wine_build/server/wineserver" "$components/"
cp "$repo_root/build/proxy/d3d11.dll" "$components/"
cp "$repo_root/build/proxy/coeditor-probe.exe" "$components/"
cp "$repo_root/build/proxy/wheel-input-probe.exe" "$components/"
for name in ntdll.so win32u.so winemac.so wineserver; do
  codesign --force --sign - "$components/$name"
  codesign --verify --strict "$components/$name"
  file "$components/$name"
done
cp "$repo_root/LICENSE" "$components/"
cp "$repo_root/third_party/Sevoflurane-LICENSE.txt" "$components/"
cp "$repo_root/third_party/Sevoflurane-LICENSE.txt" "$wine_source/COPYING.sevoflurane"
cp "$wine_source/coeditor-source.json" "$components/"
cp "$repo_root/patches/wine-26.3/"* "$components/"
# Keep the exact corresponding source with these cloud-only component artifacts.
tar -C "$wine_source" -czf "$components/wine-source.tar.gz" .
printf '%s\n' "${GITHUB_SHA:-unknown}" > "$components/SOURCE_COMMIT"
tar -C "$components" -czf "$repo_root/build/COEditor-Wine-26.3-x86_64.tar.gz" .
