# JLive

用 SwiftUI 编写的 iPhone 聚合直播应用，参考 [xiaoyaocz/dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live)。

## 当前版本

- 发现：B站、虎牙、斗鱼的真实直播间推荐，平台切换、下拉刷新、分页。
- 搜索：并行搜索多个平台；单个平台失败时保留其他平台的结果。
- 直播间：B站原生 AVPlayer HLS 播放、清晰度和线路切换、故障时自动尝试其他线路、系统全屏控件、错误重试。
- 弹幕：B站实时弹幕，在画面上飘屏（全屏时同样显示，可一键关闭），播放器下方有聊天面板；支持醒目留言和礼物消息，断线后自动重连并轮换服务器。
- 收藏：本地收藏、最近打开的 50 个直播间、通过链接或房间号添加、分享。
- 外观：跟随系统、浅色和深色模式。
- 快捷打开：支持 `jlive://bilibili/5050` 等链接，平台名为 `bilibili`、`huya`、`douyu` 或 `douyin`。
- 虎牙、斗鱼通过应用内 Safari 打开官网观看；抖音提供官网入口和直播间链接收藏。

虎牙 / 斗鱼 / 抖音的原生流解析与弹幕、发送弹幕、账号登录、iCloud 同步和画中画尚未实现。公开接口可能受到平台风控或接口变更影响，无法访问时会显示错误并提供官网入口。收藏中的热度与状态是最近获取的快照。

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
.github/workflows/      自动测试、编译 IPA 与发布
project.yml             XcodeGen 配置，版本号在这里
JLive.xcodeproj/         可直接打开的 Xcode 工程
```

增加平台时实现 `LiveProvider` 并注册到 `LiveService`；要支持弹幕，再实现 `chat(roomID:)` 返回一个 `LiveChatEndpoint`，连接、心跳和重连由 `LiveChatClient` 负责。界面不需要知道各平台的接口字段与签名规则。

## 参考与许可

平台接口、字段映射、WBI 签名流程和弹幕协议参考并改写自 `dart_simple_live` 的 `simple_live_core`，参考版本为 `ba828e6783b176ea5709fcd09f0eb01dfaceeb51`，原作者 Copyright © 2023–2025 xiaoyaocz。JLive 使用独立的 SwiftUI 界面和 Swift 实现。

本项目按 **GPL-3.0-or-later** 分发，完整条款见 [LICENSE](LICENSE)。应用内「我的 → 开源许可」保留来源说明与许可证。
