# COEditor 工作约定

- 默认在 GitHub 托管的干净 runner 上完成编译、测试和 DMG 打包。没有用户明确要求时，不在本机编译，也不依赖本机 Wine 构建目录、SDK 副本或编译缓存。
- 本地项目保留 Git 源码、补丁、测试、资源、脚本及文档；构建产物保存在 Actions artifacts / Releases。不要在项目中保留 build、.build、vendor、work、下载的运行时或编译缓存。
- 本地可执行源码、Shell、YAML 和 Git 的静态检查；通过真实 Actions 结果确认构建成功。
- main / PR 构建只上传 Actions artifacts；v* 标签在两项云端构建成功后自动发布。发布标签必须匹配 Info.plist，并有对应发行说明。
- Release 只保留最新版本；必须先验证新附件的远端哈希和下载内容、确认正式发布，再删除旧 Release。保留 Git 历史与旧标签。
- 本机已安装的 COEditor、CrossOver 运行时、容器、维护 payload 和游戏数据属于使用环境，不属于构建缓存；清理项目时不得删除。
