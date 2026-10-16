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
