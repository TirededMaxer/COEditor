# 第三方来源与许可

- Wine / CodeWeavers：补丁基于 [CrossOver 26.3.0 官方 FOSS 源码](https://www.codeweavers.com/crossover/source)，Wine 版本 `11.0-8726-g2e2f5fca349`。上游头部版权声明保留，Wine 使用 LGPL-2.1-or-later。补丁的逐文件输入/输出 SHA-256 见 `patches/wine-26.3/files.json`。
- Swift 应用、D3D11 代理和辅助脚本按本项目 LGPL-2.1-or-later 发布；源码仓库不包含 Apple SDK、CrossOver 商业 DLL、Steam 或游戏文件。
- Steam 本地二进制格式的独立实现参考：[xPaw/SteamAppInfo](https://github.com/xPaw/SteamAppInfo/blob/master/README.md)、[SteamKit KeyValue](https://github.com/SteamRE/SteamKit/blob/master/SteamKit2/SteamKit2/Types/KeyValue.cs)。没有把这些项目的实现源码复制进应用。
- Metal drawable 范围依据 [Apple CAMetalLayer.maximumDrawableCount](https://developer.apple.com/documentation/quartzcore/cametallayer/maximumdrawablecount) 和本地 SDK。
- 图标由 `Resources/generate-icon.swift` 使用 AppKit 和系统 SF Symbol `slider.horizontal.3` 生成；系统符号及 Apple 框架相关权利属于 Apple，项目许可证不重新授予这些第三方权利。
- CrossOver、Steam、Sevoflurane 等名称属于各自项目或权利人。本项目不授予商业 CrossOver 的使用许可。

- 实际呈现统计使用 Apple `MTLDrawable.presentedTime` / `addPresentedHandler`，提交节奏使用 CoreVideo 刷新周期和呈现反馈；不携带 Apple 框架。

- Sevoflurane UI 兼容性补丁固定取自本机已安装 build 65 对应源码 `Tools/crossover-ui/sevoflurane-crossover-ui.patch`，合并到 Wine 补丁中保留 Steam 窗口/托盘隐藏策略；Sevoflurane 原项目使用 MIT License，保留声明见 `third_party/Sevoflurane-LICENSE.txt`；合并后的 Wine 库仍使用 LGPL-2.1-or-later，来源提交在 `patches/wine-26.3/files.json` 记录。
