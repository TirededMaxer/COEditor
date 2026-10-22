# COEditor

macOS 上的 CrossOver 游戏调整器：用原生界面管理鼠标输入、实体滚轮、Metal 显示同步、缓冲数量、D3D11 队列、限帧、提交节奏和实际呈现统计。

此项目来自一套经过实际游戏验证的 CrossOver 26.3 / Steam 环境。包含 **Swift 应用源码、Wine 补丁、D3D11 转发代理和构建脚本**。这是独立社区项目，与 CodeWeavers、Valve 无隶属关系。

## 下载与安装

在 [Releases](https://github.com/TirededMaxer/COEditor/releases) 下载 `COEditor-1.5.2-macOS-arm64.dmg`，打开后把 **COEditor.app** 拖入“应用程序”。

**当前 DMG 是管理工具，需要已经准备好的本地补丁引擎与 Steam 容器；它不会自动下载安装 CrossOver 或替你完成 Wine 构建。** 从 1.3 升级时，限帧、提交节奏和呈现统计还需要更新匹配的 Wine 驱动与本地维护清单；仅替换应用不会给旧驱动增加这些功能。 首次从源码建立补丁环境，请阅读 [构建与集成](docs/BUILDING.md)。本仓库不分发 CrossOver 商业运行时、Steam 客户端、游戏或账号数据。

- 应用构建目标：Apple Silicon，macOS 13+；实际验证平台为 macOS 27.0.1。
- 补丁基线：CrossOver 26.3.0，Wine `11.0-8726-g2e2f5fca349`；其他引擎版本需移植和验证。
- 当前界面管理名为 `Steam` 的容器；路径相对于当前用户主目录解析。
- 可配合 Sevoflurane 管理 Steam 前端，Sevoflurane 本身不包含在本项目中。

## 功能

- **通用与游戏配置**：通用值作为回退；按游戏主程序名覆盖。添加游戏会读取本地 Steam 库、安装清单与 `appinfo.vdf`，列出 Windows 启动程序供选择。
- **鼠标移动优化**：将经过 macOS 处理的相对位移送到 Windows 原始输入路径，保留小数累计，改善原来异常的灵敏度。
- **实体滚轮优化**：直接读取 HID 滚轮刻度，按 Windows 每格 120 单位转换，抑制对应的原生平滑重复事件；触控板手势保留原生路径。
- **画面设置**：D3DMetal 的显示同步、Metal 缓冲数量 2 / 3；64 位 D3D11 游戏可注册代理以调整设备队列上限。
- **限帧与提交节奏**：按 EXE 设置 1–1000 FPS 上限、均衡／低延迟呈现反馈；新选项默认关闭。
- **实际呈现统计**：查看真正上屏的 FPS、帧时间曲线、P95/P99 和 1% Low；不将提交 FPS 当成显示 FPS。
- **手动调整**：不提供整套预设。每个参数独立调整；勾选“跟随游戏”时使用游戏本身的设置。旧配置中的实际参数保持原值。
- **本地维护**：校验组件、恢复缺失或已知旧版本、保留未知变化；保存配置时保留备份。

保存后需要重启相应游戏。不同游戏、图形后端和反作弊策略需要分别验证；配置项可设置不代表所有游戏都已完成兼容性验证。

## 使用

1. 选择“通用”设置默认值，或通过“添加游戏…”选择 Steam 容器中已经安装的游戏与启动程序。
2. 按需逐项调整；参数不会自动组合，也不会因原来选过预设而锁定。
3. 点击“保存设置”，完全退出并重启对应游戏。游戏运行期间修改配置，不会立即改变本次运行的参数；正常修改不需要重启 Steam 或 Sevoflurane。
4. 开启“实际呈现帧时间统计”并重启游戏后，点击“查看统计…”查看对应游戏的呈现数据。

| 参数 | 可调范围 | 含义 |
| --- | --- | --- |
| 显示同步 | 跟随游戏／强制开启／强制关闭 | 控制 Metal 显示同步 |
| Metal 缓冲数量 | 跟随游戏／2／3 | 可轮换的画面缓冲数量；不改变画质 |
| D3D11 队列上限 | 跟随游戏／1–16 | 允许提前排队的最大帧数，不会强制排满 |
| 按游戏限帧 | 关闭／1–1000 FPS | 给对应进程增加限帧上限，不会提高低于上限的帧率 |
| 提交节奏 | 关闭／均衡／低延迟 | 单独控制呈现反馈等待，不会联动缓冲或队列数值 |
| 实际呈现统计 | 关闭／开启 | 查看真正上屏的 FPS、帧间隔与 P95/P99、1% Low |

队列与缓冲调低可能减少排队延迟，也可能增加等待、影响帧率或稳定性；调高提供更多周转余量，实际积压时可能增加延迟。其他限帧和提交控制也会影响队列是否排满。建议固定其他设置，每次只改一个参数再比较。统计描述呈现节奏，不等于输入到显示的总延迟。

Metal 设置适用于补丁中的 D3DMetal 路径；不会自动改变 DXVK / DXMT 的呈现行为。队列代理仅支持已注册的 x86-64 D3D11 程序，保留原始 D3DMetal DLL 并转发其三个设备创建导出。Steam 客户端相关进程跳过游戏画面覆盖。

帧率上限输入框不会在打开或切回应用时自动获得输入焦点；点击后可编辑，按回车或 Esc 结束编辑。

## 独立滚轮读取器（1.5.3）

1.5 的 Wine 驱动从独立 **COEditor Wheel.app** 接收滚轮，权限不再由 Sevoflurane 或它的后台程序承担。从同一 Release 下载 `COEditor-Wine-26.3-x86_64.tar.gz` 并按 [集成说明](docs/BUILDING.md) 安装匹配的 1.5 Wine 组件，再在 COEditor 点击“设置滚轮组件…”，确认组件路径与权限用途；在系统“隐私与安全性 → 输入监控”允许 **COEditor Wheel**。如 macOS 要求重启组件，按系统提示操作。

组件安装在 `~/Library/Application Support/CrossOver/CustomRuntimes/.tuner-support/Wheel/COEditor Wheel.app`。它没有操作窗口或 Dock 图标。系统仅保留一个按需唤起入口，**不在登录时启动进程，也不在空闲时常驻**：启用滚轮优化的游戏启动后通过本地 socket 登记，launchd 唤起读取器；多个游戏共用一个读取器，最后一个使用它的程序退出约 1 秒后，读取器退出。进程崩溃同样会自动清理；切换前后台不会被误判为游戏退出。Steam 客户端、Overlay 和 Wine 系统工具不登记需求。

Sevoflurane 更新不会替换读取器，COEditor 更新也保留校验通过的协议 2 组件及其签名。1.5.1 的常驻协议 1 会迁移到按需协议 2，移除旧启动项；组件代码本身升级可能需要重新授权。通信 socket 位于 `~/Library/Application Support/COEditor/wheel.sock`，目录和 socket 仅当前用户可用。读取器验证 PID、进程创建时间和已配置 Wine 引擎的执行路径，只向已登记的前台进程发布物理滚轮。

读取器只处理实体设备的相对滚轮元素，不处理键盘和鼠标移动；物理报告写入仅当前用户可读的固定大小内存环，标记前台进程。Wine 只消费发给自身的事件。切换前后台不重新打开 HID 设备，设备热插拔由同一个管理器处理；授权失败会每秒复查，设备打开失败也会重试。读取器心跳超过 250 ms 即停止使用；实际投递成功后才抑制原生/Mos 副本，首次副本短暂等待 16 ms 以覆盖两条路径的到达顺序。触控板带手势阶段的事件保留原生路径。

“输入”区域每两秒检查组件安装和启动入口，并刷新运行中的读取器权限、程序、设备及报告计数。未安装时明确显示“未安装”；安装不完整、文件校验失败、入口未注册、驱动不匹配、权限缺失、设备打开失败或状态过期时显示橙色警告及对应原因。安装正常且待命或读取器就绪时显示绿色对勾；待命表示安装与启动入口正常，权限和设备会在游戏唤起后检查。这表示物理读取端状态，不等于游戏已接收。游戏日志中的 `[CXWheelBridge] physical delivery confirmed` 才表示该进程已投递物理刻度。权限缺失、设备不存在、读取器退出时会显示对应状态与原生回退，不再用文件校验结果代替输入运行状态。游戏的优化开关仍在启动时读取，普通参数修改保存后只需重启游戏。

旧版日志中的 `[CXWheelHID] Input Monitoring permission required` 属于 1.4 驱动；只替换编辑器无法升级 Wine。COEditor 不修改 TCC 数据库，也不放宽任何应用的代码签名要求。

## 云端构建与发布

应用、DMG 以及 Wine / D3D11 组件由 [GitHub Actions](https://github.com/TirededMaxer/COEditor/actions/workflows/build.yml) 从源码构建。本地只保留源码及相关文件。

- 推送 main、提交 PR 或手动运行工作流，会执行干净构建、测试、DMG 签名和挂载校验，并上传 Actions artifacts。
- 推送与应用版本一致的 v* 标签，两项构建成功后自动发布新版。附件会从 GitHub 下载比对，确认新 Release 成功后再删除旧 Release。
- 每次从官方地址下载匹配 Wine 源码；不使用本机 CrossOver 开发库、编译缓存或预先构建的 Wine 目录。
- DMG 附带 SHA256SUMS 与 BUILDINFO.json，可追溯源码提交、构建运行及工具链。Wine 组件附件同时保留对应 Wine 源码。
- Actions artifacts 保留 7 天，Release 只保留最新版。工作流、手动触发和运行时集成见 [构建说明](docs/BUILDING.md)。

应用使用 ad-hoc 签名；公开 DMG 未经 Developer ID 签名或 Apple 公证，macOS 可能要求在“隐私与安全性”中手动允许打开。

## 目录

```text
Sources/COEditor/       原生应用与 Steam 库解析器
Sources/WheelBridge/    独立物理滚轮读取器与跨架构共享协议
Sources/D3D11Proxy/     游戏侧 D3D11 转发代理
Sources/LegacySteam/    旧 Windows Steam 启动入口与 CEF 方案的辅助源码
patches/wine-26.3/      完整 Wine 改动、逐文件基线及结果哈希
Resources/             应用元数据、图标与图标生成源码
tests/                 配置、输入与 D3D11 渲染回归程序
scripts/               构建、补丁校验、维护服务和 DMG 打包
docs/                  集成步骤、配置、验证范围与来源
examples/              不含个人信息的配置示例
```

## 更新 CrossOver

应用和配置放在应用程序目录及用户 Application Support 中；补丁引擎保留在 `CustomRuntimes/Steam-Optimized-26.3`，不覆盖原装 CrossOver.app。自动维护服务保持容器指向这套已验证引擎。因此更新 CrossOver 主程序后可以继续使用已有引擎，**不等于把补丁自动移植到新版 Wine**。切换新版引擎前需重新构建和测试。

## 许可证与贡献

项目使用 [LGPL-2.1-or-later](LICENSE)，上游文件的版权声明和原有许可保留。Wine 基线由 [CodeWeavers 官方源码页面](https://www.codeweavers.com/crossover/source) 提供；[第三方说明](docs/THIRD_PARTY.md) 列出来源。CrossOver 商业组件继续遵循其原有许可。

提交问题时请说明 CrossOver / macOS 版本、游戏、图形后端及复现步骤；请勿上传 Steam 账号数据或整份容器。贡献说明见 [CONTRIBUTING.md](CONTRIBUTING.md)。
