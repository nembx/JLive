import SwiftUI
import JLiveCore

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var confirmingClear = false

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 17) {
                        Image(systemName: "play.rectangle.on.rectangle.fill").font(.system(size: 27))
                            .foregroundStyle(.black).frame(width: 62, height: 62)
                            .background(JLiveTheme.lime, in: RoundedRectangle(cornerRadius: 17))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("JLive").font(.title2.bold())
                            Text("简简单单，看你喜欢的直播。 ").font(.caption).foregroundStyle(.secondary)
                            Text("v0.1.0").font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 10)
                }
                Section("偏好设置") {
                    Picker("外观", selection: $library.appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.name).tag($0) }
                    }
                    Button("清空观看记录", role: .destructive) { confirmingClear = true }
                }
                Section("平台接入") {
                    ForEach(LivePlatform.allCases) { platform in
                        HStack {
                            PlatformBadge(platform: platform)
                            Spacer()
                            Text(platform == .bilibili ? "原生播放 / 搜索" : (platform.supportsDiscovery ? "浏览 / 搜索 / 官网观看" : "官网观看 / 链接收藏"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("关于") {
                    Link("项目源码", destination: URL(string: "https://github.com/nembx/JLive")!)
                    Link("参考项目 · Simple Live", destination: URL(string: "https://github.com/xiaoyaocz/dart_simple_live")!)
                    NavigationLink("开源许可 · GPL v3") { LicenseView() }
                    Text("JLive 使用公开的平台接口，接口变化可能影响使用。收藏与观看记录保存在这台设备上。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = library.storageError {
                    Section("本地存储") { Text(error).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("我的")
            .confirmationDialog("清空所有观看记录？", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("清空记录", role: .destructive) { library.clearHistory() }
            }
        }
    }
}

private struct LicenseView: View {
    private var license: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "https://www.gnu.org/licenses/gpl-3.0.html" }
        return text
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("直播平台适配与 WBI 签名参考并改写自 xiaoyaocz/dart_simple_live（Copyright © 2023–2025 xiaoyaocz）。JLive 的 SwiftUI 界面和 Swift 核心是本项目的实现。按 GPL-3.0-or-later 许可分发，可依许可修改与再分发，不提供担保。")
                    .font(.subheadline)
                Text(license).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            }.padding(20)
        }
        .navigationTitle("开源许可").navigationBarTitleDisplayMode(.inline)
    }
}
