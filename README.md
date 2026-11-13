# JLive

用 SwiftUI 编写的 iPhone 聚合直播应用，参考 [xiaoyaocz/dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live)。

## 当前版本

- 发现：B站、虎牙、斗鱼、抖音的真实直播间推荐，平台切换、下拉刷新、分页。
- 搜索：并行搜索 B站、虎牙、斗鱼；单个平台失败时保留其他平台的结果。抖音支持推荐和链接 / 房间号打开，暂不支持关键词搜索。
- 直播间：四个平台原生 AVPlayer HLS 播放。播放器固定在页面顶部，画质、线路和弹幕设置都在播放器内；全屏按钮在右下角，进入横屏时沿用同一个视频层和连接，闲置后隐藏控件。
- 播放控制：播放 / 暂停、静音、手动画中画、连接超时自动换线、错误重试。进入后台时暂停普通播放；开启画中画后继续播放，回到前台恢复用户先前的播放状态。
- 弹幕：四个平台实时弹幕与聊天列表。抖音使用访客连接，支持压缩消息、确认回复、心跳和备用服务器。支持开关、字号、不透明度、速度、显示区域和屏蔽词，设置在小窗和全屏之间共享并保存在本地；B站支持醒目留言和礼物。断线自动重连并轮换服务器。
- 账号：通过 B站官方网页登录，完成后验证登录状态并将凭据保存在系统钥匙串；可在直播间发送最多 30 字的弹幕。退出登录会清理本地凭据与 B站网页数据。
- 收藏：本地收藏、最近打开的 50 个直播间、通过链接或房间号添加、分享。下拉更新收藏的开播状态；支持 JSON 导入导出，导入会验证房间号并合并去重，可通过 iCloud 云盘迁移备份。
- 外观：简洁的直播卡片布局，跟随系统、浅色和深色模式；新增 J + 播放标记图标，包含 iOS 18 及更新版本的深色和着色图标（iOS 17 使用默认图标）。
- 快捷打开：支持 `jlive://bilibili/5050` 等链接，平台名为 `bilibili`、`huya`、`douyu` 或 `douyin`。
- 抖音分享中的临时长房间号会解析为主播的网页房间号，方便长期收藏；各平台保留官网观看入口。

虎牙 / 斗鱼 / 抖音账号与发送弹幕、抖音关键词搜索、自动 iCloud 同步尚未实现。抖音仅支持直播网页链接和数字房间号，暂不解析 `v.douyin.com` 短链接或整段分享文案。备份至 iCloud 云盘是手动文件备份，不是自动同步。公开接口可能受到平台风控或接口变更影响，无法访问时会显示错误并提供官网入口；画质列表仅展示实际可播放的 HLS 流。收藏中的热度与状态是最近一次刷新获取的快照。

## 运行

需要 Xcode 16 或更新版本，iOS 17 或更新版本。项目不依赖 Flutter，也没有外部 Swift 包依赖。

1. 打开 `JLive.xcodeproj`，选择 `JLive` scheme。
2. 选择 iPhone 模拟器后运行。
3. 在真机上运行时，在 Signing & Capabilities 中选择自己的开发团队；必要时修改 Bundle Identifier。

`project.yml` 是 XcodeGen 项目配置，修改项目结构后运行 `xcodegen generate` 重新生成工程。

Debug 构建可以添加启动参数 `--open-room https://live.bilibili.com/5050`，直接打开直播间进行播放调试；再加上 `--muted` 可以静音播放。

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --package-path JLiveCore

env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project JLive.xcodeproj -scheme JLive \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/jlive-build CODE_SIGNING_ALLOWED=NO build
```

核心测试默认使用固定数据，不联网。可设置 `JLIVE_LIVE_TESTS=1` 并添加 `--filter liveHLSAndChat`，验证虎牙 / 斗鱼的实际 HLS 清单和弹幕入房。设置 `JLIVE_DOUYIN_LIVE_TESTS=1` 并添加 `--filter liveDouyinDiscoveryPlaybackAndChat`，验证抖音推荐、HLS 清单和真实弹幕接收；两者都只读取数据，不播放音视频、不发送弹幕。

`JLiveTests` 验证收藏备份、无效导入、状态刷新和抖音推荐 / 搜索分流；`JLiveUITests` 验证主题切换、全屏进出与弹幕设置保留。通过 Xcode 的 Test，或 `xcodebuild test -project JLive.xcodeproj -scheme JLive -destination 'platform=iOS Simulator,name=<本机模拟器名称>'` 运行。界面测试自动使用 `--muted` 并在结束时关闭应用。登录后实际发送弹幕需要在自己的设备上验证，自动测试只验证请求构造，不向直播间发送消息。

抖音实际播放界面测试默认跳过，运行 `xcodebuild test` 时设置 `TEST_RUNNER_JLIVE_DOUYIN_UI_ROOM=<正在直播的网页房间号>` 可启用；它会确认实际播放、静音、弹幕连接和播放器内设置，随后关闭直播间和应用。

图标源绘制脚本为 `scripts/generate-icons.swift`，在仓库根目录运行 `swift scripts/generate-icons.swift` 可重新生成默认、深色、着色图标及应用内标记。

## 自动编译与发布

`.github/workflows/build.yml` 在每次推送到 `main` 时运行：

1. 运行核心测试，编译未签名的 `JLive-<版本号>.ipa`，并挂在这次运行的 Artifacts 里。
2. 如果 `project.yml` 里的 `MARKETING_VERSION` 还没有对应的 `v<版本号>` 标签，就创建 GitHub Release 并附上 IPA。

所以发版只需要改 `project.yml` 里的版本号、运行 `xcodegen generate`，然后提交并推送。更新日志取自上一个版本以来的提交标题，提交信息请用中文，写成读者能看懂的一句话。只改文档的推送不会触发编译。

IPA 没有签名，需要用 AltStore、SideStore、Sideloadly 或 TrollStore 等工具自行签名后安装。

## 结构

```text
JLive/                  SwiftUI 页面、浏览状态、播放与弹幕生命周期、本地记录
JLiveCore/              平台无关的 Swift Package
  Sources/JLiveCore/    数据模型、HTTP 客户端、平台适配器、聚合服务、WBI 签名、弹幕协议与连接
  Tests/               签名、平台映射、聚合部分失败、直播链接、HLS 解析、弹幕编解码与重连测试
JLiveTests/             收藏存储与备份测试
JLiveUITests/           主题与播放器交互测试
scripts/               图标绘制源代码
.github/workflows/      自动测试、编译 IPA 与发布
project.yml             XcodeGen 配置，版本号在这里
JLive.xcodeproj/         可直接打开的 Xcode 工程
```

增加平台时实现 `LiveProvider` 并注册到 `LiveService`；要支持弹幕，再实现 `chat(roomID:)` 返回一个 `LiveChatEndpoint`，连接、心跳和重连由 `LiveChatClient` 负责。界面不需要知道各平台的接口字段与签名规则。

## 参考与许可

平台接口、字段映射、WBI / 抖音签名流程和弹幕协议参考并改写自 `dart_simple_live` 的 `simple_live_core`，参考版本为 `ba828e6783b176ea5709fcd09f0eb01dfaceeb51`，原作者 Copyright © 2023–2025 xiaoyaocz。JLive 使用独立的 SwiftUI 界面和 Swift 实现；抖音签名 JavaScript 保留在 `JLiveCore/Sources/JLiveCore/Resources`，由 JavaScriptCore 执行。

本项目按 **GPL-3.0-or-later** 分发，完整条款见 [LICENSE](LICENSE)。应用内「我的 → 开源许可」保留来源说明与许可证。
