# 构建与集成

## 现有环境

已经使用本项目补丁的用户，只需替换 COEditor.app。配置、组件备份、运行时与游戏留在原处。应用的 Bundle ID 仍为 `local.crossover.tuner`，命令行可执行文件名仍为 `CrossOverTuner`。

原生应用可独立编译；操作 Steam 容器还需要本节所述的本地运行环境。本项目当前不是通用的 CrossOver 一键安装器。

## Wine 补丁

从 [CodeWeavers 官方页面](https://www.codeweavers.com/crossover/source) 获取 [26.3.0 源码包](https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz)。解包后以 `sources/wine` 为基线，先复制到自己的工作目录，再运行：

```sh
python3 scripts/apply-wine-patch.py /path/to/wine-source
python3 scripts/apply-wine-patch.py /path/to/wine-source --verify
```

脚本先核对 19 个文件的 SHA-256，再 dry-run、应用补丁、校验结果。发现版本不一致或已有改动会停止。补丁包含原生鼠标、小数累计、HID 滚轮、Metal 参数、Steam 辅助进程 Dock 控制及配置读取。

修改涉及用户驱动 ABI 与服务端输入分发：`winemac.so`、`win32u.so`、`ntdll.so` 和 `wineserver` 应来自同一套构建。不要单独把驱动塞入任意 Wine 版本。`server_protocol.h` 与 `protocol.def` 已同步保存在补丁中，新增标志不改变请求结构布局。

在 macOS 上准备 CrossOver 的 Wine 构建依赖（Xcode、Bison / Flex、LLVM 及对应依赖库）。下面是本项目使用的配置参数，不是适用于所有机器的依赖安装脚本：

```sh
mkdir -p build/wine
cd build/wine
/path/to/wine-source/configure \
  --enable-win64 --without-x --without-wayland --without-alsa --without-pulse \
  --without-dbus --without-gstreamer --without-unwind \
  --host=x86_64-apple-darwin \
  'CC=clang -arch x86_64' 'CXX=clang++ -arch x86_64' 'OBJC=clang -arch x86_64' \
  LDFLAGS=-L/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64
```

返回仓库根目录运行 `./scripts/build-wine.sh /path/to/wine-source /path/to/wine-build`。干净构建还需按官方构建文档补齐目标需要的工具和依赖；仓库中没有这些第三方二进制。

## D3D11 代理

需要 LLVM 的 PE 目标、`lld-link`，以及对应 Wine 源码生成的 Windows 头文件和 kernel32 导入库。

```sh
make -C /path/to/wine-build include/d3d11.h include/dxgi.h \
  dlls/kernel32/x86_64-windows/libkernel32.a
./scripts/build-proxy.sh /path/to/wine-source /path/to/wine-build/include \
  /path/to/wine-build/dlls/kernel32/x86_64-windows/libkernel32.a
```

`PE_CLANG` / `PE_LINK` 可覆盖默认工具路径。输出为 `build/proxy/d3d11.dll`，不替换原版 D3DMetal DLL。代理设置 `IDXGIDevice1::SetMaximumFrameLatency`；Metal 池数量由 Wine 补丁控制，两者是不同参数。

## 本地运行时布局

以下以 `~/Library/Application Support/CrossOver` 为根目录。先退出该容器中的程序，并为容器配置和将替换的文件建立本地备份。

1. 从自己合法安装的 CrossOver 26.3 复制 `Contents/SharedSupport/CrossOver` 到 `CustomRuntimes/Steam-Optimized-26.3`，保留链接和权限；保留原装 CrossOver.app。
2. 将构建结果放到副本：`dlls/{ntdll,win32u,winemac.drv}/*.so` 对应 `lib/wine/x86_64-unix/{ntdll,win32u,winemac}.so`；`server/wineserver` 对应 `CrossOver-Hosted Application/wineserver`。
3. 在 `.tuner-support/Payload/` 保存这些本地组件备份，以及构建的代理（为兼容当前应用，文件名为 `d3d11-cs2.dll`，实际支持其他注册游戏）。本地生成 `.tuner-support/manifest.json`，结构见下文。商业 DLL 可在本地备份，但不要发布。
4. 容器名称当前固定为 `Steam`。在 `Bottles/Steam/cxbottle.conf` 的 `[EnvironmentVariables]` 内设置 `CX_ROOT` 为副本绝对路径；`CX_D3D11_REAL_DLL` 为该副本 `lib64/apple_gptk/wine/x86_64-windows/d3d11.dll` 的 Wine `Z:` 路径；`CX_HIDE_STEAM_DOCK="1"`。
5. 将 `examples/cx-tuner.ini` 复制到容器的 `drive_c/.cx-tuner.ini`，按需修改。先用应用的 `--verify` 检查，再打开界面。添加游戏会注册该主程序的 `native,builtin` D3D11 覆盖并安装代理；已有不同 DLL 或覆盖时会保留并提示。

manifest 是本机生成的组件清单，绝不能把示例哈希原样当成安装配置：

```json
{
  "runtime": "Steam-Optimized-26.3",
  "baseVersion": "26.3",
  "components": [
    {
      "target": "CustomRuntimes/Steam-Optimized-26.3/lib/wine/x86_64-unix/winemac.so",
      "payload": "Payload/winemac.so",
      "sha256": "<该本地组件的 SHA-256>",
      "allowedBefore": [],
      "optional": false
    }
  ]
}
```

对其他已构建组件逐项建立记录。`target` 相对于 CrossOver 根目录，或是外部游戏文件的绝对路径；`payload` 相对于 `.tuner-support`。只有本地明确验证过的旧哈希才可放入 `allowedBefore`。游戏代理记录可设 `optional=true`，游戏目录删除后维护服务会跳过。

## 自动维护

```sh
python3 scripts/install-maintenance.py --app /Applications/COEditor.app
'/Applications/COEditor.app/Contents/MacOS/CrossOverTuner' --verify
```

脚本更新当前用户的 `local.crossover.tuner-maintenance` LaunchAgent，监听原版 CrossOver 与 Steam 容器配置变化。`--maintain` 会修复已知状态；`--verify` 只检查。

## 输入权限

HID 滚轮需要为**实际启动游戏的入口**授予 macOS 输入监控权限。Sevoflurane 与原来的 Steam.app 是不同入口，旧授权未必覆盖新入口。设置开关不会代替系统授权，COEditor 自身不需要新增辅助功能权限。没有权限时补丁回退到普通事件；不需要改动 Mos 的全局设置。

## 旧 Steam 辅助源码

`Sources/LegacySteam` 保留原 Windows Steam 启动入口用过的源码，默认不构建、不安装。`compat_shim.c` 会先载入本机原 `cxcompatdb.vendor.so` 再选择性调整 CEF 参数，`host_shim.m` 用于旧启动器的 WineLoader 入口。该 CEF 方案没有显著解决客户端卡顿；实际改善来自 Sevoflurane 前端。新的集成不要求启用这些辅助组件，也不提供修改签名权限的自动脚本。

## DMG

```sh
./scripts/build-app.sh
./scripts/build-dmg.sh
```

打包只包含本项目应用、LICENSE、安装说明及“应用程序”快捷入口，不携带本机容器或运行时。通过 `shasum -a 256 -c build/SHA256SUMS` 校验产物。
