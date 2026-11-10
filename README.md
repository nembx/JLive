# JLive

用 SwiftUI 编写的 iPhone 聚合直播应用，参考 [xiaoyaocz/dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live)。

## 当前版本

- 发现：B站、虎牙、斗鱼的真实直播间推荐，平台切换、下拉刷新、分页。
- 搜索：并行搜索多个平台；单个平台失败时保留其他平台的结果。
- 直播间：B站原生 AVPlayer HLS 播放、清晰度和线路切换、故障时自动尝试其他线路、系统全屏控件、错误重试。
- 收藏：本地收藏、最近打开的 50 个直播间、通过链接或房间号添加、分享。
- 外观：跟随系统、浅色和深色模式。
- 快捷打开：支持 `jlive://bilibili/5050` 等链接，平台名为 `bilibili`、`huya`、`douyu` 或 `douyin`。
- 虎牙、斗鱼通过应用内 Safari 打开官网观看；抖音提供官网入口和直播间链接收藏。

虎牙 / 斗鱼 / 抖音的原生流解析、弹幕、账号登录、iCloud 同步和画中画尚未实现。公开接口可能受到平台风控或接口变更影响，无法访问时会显示错误并提供官网入口。收藏中的热度与状态是最近获取的快照。

## 运行

需要 Xcode 16 或更新版本，iOS 17 或更新版本。项目不依赖 Flutter，也没有外部 Swift 包依赖。

1. 打开 `JLive.xcodeproj`，选择 `JLive` scheme。
2. 选择 iPhone 模拟器后运行。
3. 在真机上运行时，在 Signing & Capabilities 中选择自己的开发团队；必要时修改 Bundle Identifier。

`project.yml` 是 XcodeGen 项目配置，修改项目结构后运行 `xcodegen generate` 重新生成工程。

Debug 构建可以添加启动参数 `--open-room https://live.bilibili.com/5050`，直接打开直播间进行播放调试。

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --package-path JLiveCore

env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project JLive.xcodeproj -scheme JLive \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/jlive-build CODE_SIGNING_ALLOWED=NO build
```

## 结构

```text
JLive/                  SwiftUI 页面、浏览状态、播放生命周期与本地记录
JLiveCore/              平台无关的 Swift Package
  Sources/JLiveCore/    数据模型、HTTP 客户端、平台适配器、聚合服务、WBI 签名
  Tests/               签名、平台映射、聚合部分失败、直播链接与 HLS 解析测试
project.yml             XcodeGen 配置
JLive.xcodeproj/         可直接打开的 Xcode 工程
```

增加平台时实现 `LiveProvider` 并注册到 `LiveService`。界面不需要知道各平台的接口字段与签名规则。

## 参考与许可

平台接口、字段映射和 WBI 签名流程参考并改写自 `dart_simple_live` 的 `simple_live_core`，参考版本为 `ba828e6783b176ea5709fcd09f0eb01dfaceeb51`，原作者 Copyright © 2023–2025 xiaoyaocz。JLive 使用独立的 SwiftUI 界面和 Swift 实现。

本项目按 **GPL-3.0-or-later** 分发，完整条款见 [LICENSE](LICENSE)。应用内「我的 → 开源许可」保留来源说明与许可证。
