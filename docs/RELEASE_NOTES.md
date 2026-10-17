# COEditor 1.4.1

- 构建、测试和 DMG 打包迁至 GitHub Actions，使用干净 macOS runner，不依赖开发机缓存。
- Wine / D3D11 组件从 CodeWeavers 官方源码重新下载并编译，匹配源码随云端组件 artifact 提供。
- 新增 BUILDINFO.json，记录源码提交、云端构建链接、编译器与安装包哈希。
- 标签构建通过后自动发布；下载核对新附件、确认发布成功后，才删除旧 Release。

游戏配置和应用功能沿用 1.4.0。DMG 仍仅包含管理工具，需要已有的 CrossOver 26.3 补丁环境和 Steam 容器；应用使用 ad-hoc 签名，未经 Apple 公证。云端组件编译不代替真实游戏、Metal 呈现和输入权限验证，也不自动替换本机运行时。

# COEditor 1.4.0

- 移除整套预设与控件锁定，所有参数独立手动调整；旧配置的实际数值保持不变，新配置的画面参数默认跟随游戏。
- D3D11 队列上限可调范围扩展至 1–16；这是允许排队的上限，不会强制积压到指定帧数。
- 新增按游戏限帧（1–1000 FPS）、独立提交节奏控制，以及实际呈现 FPS、帧时间曲线、P95/P99 和 1% Low。
- 移除主窗口底部的重复提示，保留保存结果中的重启提示；README 和配置说明同步更新。

**安装与升级：** 将 DMG 中的 COEditor.app 拖入“应用程序”替换旧版，原有配置保留。DMG 只包含管理工具；需要已有的 CrossOver 26.3 补丁引擎及名为 Steam 的容器。新增帧控制功能还需安装本版匹配的 Wine 驱动，并更新本地 payload/manifest；旧驱动下相关控件保持禁用。首次配置和源码构建见仓库 `docs/BUILDING.md`。

**平台：** Apple Silicon，构建目标 macOS 13+。应用为 ad-hoc 签名，未经 Developer ID 签名或 Apple 公证；不包含 CrossOver 商业组件、Steam、游戏或账号数据。

**验证：** 本地 debug/release 构建、配置迁移与独立调整自测、Steam 库解析、原生输入与帧控制回归、21 文件 Wine 补丁校验。新帧控制此前已通过真实 Metal 探针及 D3D11 队列 5/16 与 ResizeBuffers 检查；这些结果不代表所有游戏的体验或输入延迟已验证。本次 GUI 自动操作通道不可用，未将界面点击测试计为通过。

下载 `.dmg`；`SHA256SUMS` 可用于校验。

# COEditor 1.3.0

首次公开源码及 DMG 发布，将原“CrossOver 调整器”命名为 **COEditor**。

- 支持通用配置、本地 Steam 游戏选择、显示同步、Metal 双/三缓冲与 D3D11 队列设置。
- 鼠标移动与物理滚轮优化可独立切换；预设锁定数值，自定义模式允许逐项调整。
- 保留现有容器、配置及补丁引擎，应用安装在“应用程序”即可。
- 同步公开 Swift 应用、Wine 补丁、D3D11 代理和构建脚本，采用 LGPL-2.1-or-later。

**安装前提：** DMG 只包含管理工具，需要已有的 CrossOver 26.3 补丁引擎及名为 Steam 的容器。首次建立环境请阅读仓库 `docs/BUILDING.md`。不包含商业运行时或 Steam 数据。

**平台：** Apple Silicon，构建目标 macOS 13+，已验证 macOS 27.0.1。应用为 ad-hoc 签名，未经过 Developer ID 签名或 Apple 公证。

**验证：** debug/release 本地构建、Swift 配置与库解析自测、HID 滚轮/位移累计测试、19 文件 Wine 补丁基线及结果校验、D3D11 代理编译、代码签名及 DMG 挂载校验。GUI 自动操作通道不可用，未将界面点击测试计为通过。

下载 `.dmg`；`SHA256SUMS` 可用于校验。应用配置及原运行环境路径保持兼容。
