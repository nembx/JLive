# 画质切换诊断记录

核对日期：2026-11-21。以下结论来自公开直播接口、真实媒体头和 Simple Live 源码，不代表所有房间永远具有相同限制。

## 与 Simple Live 的关键差异

Simple Live 用 media_kit/mpv 播放斗鱼桌面 FLV，JLive 原先只接入 AVPlayer/HLS。手机 ratestream 返回 settings 画质列表，但旧代码读 multirates，导致所有房间显示“自动画质”。更关键的是，测试房间的手机 HLS 会将不同档位都回退到同一个超清源，直接改菜单或替换手机接口都不能取得真实多画质。

Simple Live 先以 getH5Play 的发现参数取得 multirates、bit 和 CDN，随后用签名、cdn、rate 请求播放地址。切换请求不携带发现阶段的 ver/iar/ive 等参数。按完整流程复现后，高清和超清确实返回不同 FLV。

B站的 Simple Live 实现允许用户登录，并将登录 Cookie 及同一个浏览器的 buvid 用于播放请求。JLive 此前只用访客身份。本次恢复播放器内可选登录，同时避免将账号 Cookie 与另一套访客设备标识混用。“我的”页不增加平台接入。

## 真实接口验证

| 平台与房间 | 请求 | 实际返回 | 证据 |
| --- | --- | --- | --- |
| B站 545068，访客 | 蓝光 qn=400 | 超清 current_qn=250 | TS 与 fMP4 AVC HLS 都返回 250；WBI 签名仍相同 |
| 斗鱼 36252，手机接口 | rate=0、2、3 | 同一个 `_2000.m3u8` | 主清单 BANDWIDTH=2560000，H.264、1280×720、30 fps |
| 斗鱼 36252，Simple Live 桌面流程 | 高清 rate=2 | `_900.flv`、rate=2 | 已读取 FLV 媒体头 |
| 斗鱼 36252，Simple Live 桌面流程 | 超清 rate=3 | `_2000.flv`、rate=3 | 已读取 FLV 媒体头 |
| 斗鱼 36252，Simple Live 桌面流程 | 原画 rate=0 | 蓝光4M rate=4 | 平台回退，界面应显示蓝光4M |

B站对比了 html5/web、完整协议与格式、AVC/HEVC、访客 Cookie、旧 playUrl 接口和 WBI 签名请求。该房间的访客蓝光请求仍被返回为超清。不能仅由这个结果断言所有房间的限制都由未登录造成，也不能宣称未登录即可解锁蓝光。登录高画质需用户使用自己的账号在应用中验证。

## 实现与回归

- 斗鱼优先使用 Simple Live 桌面取流流程，完整保留画质列表；手机 HLS 作为接口失败时的备用。
- KSPlayer/KSMEPlayer 负责 FLV 解封装与解码，原有 HLS 继续使用 AVPlayer。播放、暂停、静音、重连、横屏和画中画共用播放器界面。
- KSPlayer 固定到最后的源码版本 `be7f60d3`，FFmpegKit 固定为 6.1.4；5.6.2 的预编译包缺少 iOS 真机架构，因此不用于发布。源码渲染需要 Xcode Metal Toolchain，CI 在编译前安装该组件。
- 画质标签使用实际返回档位，并依据 FLV/HLS 的码率后缀与元数据核实，避免把回显的请求值当作切换成功。
- B站可在播放器中通过官网登录，登录信息经确认后保存在本机 Keychain；可在播放器设置中退出。访客观看继续可用。
- B站按 web 端请求完整协议、格式和 AVC/HEVC 编码，纳入原先遗漏的 HEVC HLS 和 FLV 高画质；同档备用线路可以跨格式播放。选择目标档位时核对实际 current_qn，目标缺失则取最近低档，低档不存在时取最近高档。
- 平台回退时展示实际画质和原因；播放器设置保留可用性提示。

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path JLiveCore
env JLIVE_QUALITY_LIVE_TESTS=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path JLiveCore --filter liveDouyuActuallySwitchesDesktopQuality
```

真实斗鱼测试要求高清、超清的实际编号正确、播放路径不同，并读取有效 FLV 头。确定性测试覆盖桌面切换参数、settings、回显与码率不一致、手机备用、新接口签名选择，以及登录后浏览器标识保持一致。原来的 multirates 合成测试没有覆盖手机真实响应，导致问题漏检。

0.7.5 的 iPhone Release 构建已通过；76 项核心测试通过。模拟器也已使用源码播放器播放真实斗鱼 36252，依次切换高清、超清并确认重新进入可播放状态，已导出[真实播放截图](screenshots/player-douyu.png)。该测试用 `JLIVE_UI_LIVE_TESTS=1` 和 `TEST_RUNNER_JLIVE_UI_LIVE_TESTS=1` 启用 `PlayerUITests/testLiveDouyuQualitySwitch`，本次实际执行成功，没有跳过。全屏设置的确定性测试使用本地视频，避免房间突然下播改变测试路径。

参考：[Simple Live 核心实现](https://github.com/xiaoyaocz/dart_simple_live/tree/master/simple_live_core/lib/src)、[Simple Live 播放器](https://github.com/xiaoyaocz/dart_simple_live/tree/master/simple_live_app/lib/modules/live_room/player)、[KSPlayer](https://github.com/kingslay/KSPlayer)、[斗鱼手机直播页](https://m.douyu.com/36252)、[B站直播页](https://live.bilibili.com/545068)。
