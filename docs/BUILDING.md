# 构建与集成

## GitHub Actions 构建（默认）

日常构建在 [Build and release](https://github.com/TirededMaxer/COEditor/actions/workflows/build.yml) 中完成。本地只保留 Git 源码、补丁、资源、测试、脚本与文档，不保留应用副本、DMG、下载的依赖或编译缓存。

- 推送 main、提交 PR 或手动 Run workflow：构建 debug/release 应用，运行配置、库解析、原生输入和帧控制自测，制作并只读挂载校验 DMG。
- 独立 Intel macOS 作业每次下载官方 CrossOver 26.3 源码，校验并应用 21 文件补丁，从空目录编译四个耦合 Wine 组件及 D3D11 代理。完整匹配 Wine 源码、补丁、许可证及来源记录随组件 artifact 一起保存。
- 两项作业均成功后，v* 标签才触发 Release。标签需与 Info.plist 的版本一致。云端先上传草稿，下载比对每个附件，确认正式发布为最新版后才删除旧 Release；Git 标签和历史保留。
- Actions artifacts 保留 7 天；正式 Release 保留最新版。应用 artifact 包含 DMG、SHA256SUMS 和 BUILDINFO.json；后者记录源码提交、构建链接、编译器及 DMG 哈希。
- 不使用 actions/cache、自托管 runner、本地 Wine 对象、预编译导入库或已安装 CrossOver 的开发库。工具来自托管 runner / Homebrew，Wine 源码来自 files.json 中的官方地址。

发布流程：修改 Info.plist 的版本与构建号，更新 CHANGELOG 和对应 RELEASE_NOTES；推送源码并确认 main 构建成功，再推送同一提交的 v版本号 标签。之后由云端打包、验证和发布。本地无需安装 Xcode 或先生成安装包。

原始组件 artifact 用于构建结果与后续运行时适配；不自动安装到本机。它不包含商业 D3DMetal 或完整 CrossOver。真实游戏、画面、输入权限及 Sevoflurane 集成仍需独立实机验证。

以下命令用于说明云端脚本及运行时集成。日常开发直接使用 Actions，不需要准备本地编译树。

## 现有环境

从 1.3 升级到 1.4，需要同时更新 COEditor.app 与匹配的 `winemac.so` / 维护 payload。旧驱动不包含新帧控制功能，界面会禁用对应选项。帧驱动安装完成后，在本机 manifest 写入 `frameControlVersion: 1`；注册新游戏时应用保留这个能力字段。配置、组件备份、运行时与游戏留在原处。应用的 Bundle ID 仍为 `local.crossover.tuner`，命令行可执行文件名仍为 `CrossOverTuner`。

原生应用可独立编译；操作 Steam 容器还需要本节所述的本地运行环境。本项目当前不是通用的 CrossOver 一键安装器。

## Wine 补丁

从 [CodeWeavers 官方页面](https://www.codeweavers.com/crossover/source) 获取 [26.3.0 源码包](https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz)。解包后以 `sources/wine` 为基线，先复制到自己的工作目录，再运行：

```sh
python3 scripts/apply-wine-patch.py /path/to/wine-source
python3 scripts/apply-wine-patch.py /path/to/wine-source --verify
```

脚本先核对 21 个文件的 SHA-256，再 dry-run、应用补丁、校验结果。发现版本不一致或已有改动会停止。补丁包含原生鼠标、小数累计、HID 滚轮、Metal 参数、Steam 辅助进程 Dock 控制及配置读取、帧控制和呈现统计。

修改涉及用户驱动 ABI 与服务端输入分发：`winemac.so`、`win32u.so`、`ntdll.so` 和 `wineserver` 应来自同一套构建。不要单独把驱动塞入任意 Wine 版本。`server_protocol.h` 与 `protocol.def` 已同步保存在补丁中，新增标志不改变请求结构布局。

云端默认调用 scripts/fetch-wine-source.py 和 scripts/build-wine-clean.sh；依赖由 runner / Homebrew 提供。下列参数保留为旧运行时集成参考，不是默认构建流程：

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

打包只包含本项目应用、LICENSE、安装说明及“应用程序”快捷入口，不携带本机容器或运行时。在附件所在目录运行 `shasum -a 256 -c SHA256SUMS` 校验产物。签名、挂载和应用内容由 scripts/verify-dmg.py 检查。

## 旧局部构建工具与实机验证

scripts/build-frame-driver.py 保留为特殊调试工具，不再用于默认构建或发布。仅在明确要求局部调试时使用同 ABI 构建目录；正常构建使用云端完整源码流程：

```sh
python3 scripts/build-frame-driver.py --wine-source /path/to/existing-wine \
  --wine-build /path/to/existing-build --patched-source /path/to/new-patched-wine \
  --output /path/to/new-output
```

已有 Sevoflurane 窗口隐藏集成时，额外传入 `--compat-patch /path/to/sevoflurane-crossover-ui.patch`，保留那三份 Cocoa 修改。该参数使用用户 fork `Tools/crossover-ui/` 中的兼容补丁；不替换应用/helper，不更改输入监控签名。导出 ABI 和组件签名必须校验，再更新本地 payload/manifest；瓶中进程必须先停止。

真实 Metal 验证会短暂打开本地渲染窗口，运行限帧、两档提交节奏以及丢弃 drawable 的回退检查：

```sh
xcrun clang -fblocks -I/path/to/new-patched-wine/dlls/winemac.drv \
  tests/metal_frame_probe.m -o build/metal_frame_probe \
  -framework AppKit -framework QuartzCore -framework Metal -framework CoreVideo
build/metal_frame_probe
```

这验证本机真实 Metal 呈现链路；游戏转换链路与实际游戏体验需要分别验证。
