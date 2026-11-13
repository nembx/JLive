import SwiftUI
import JLiveCore

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AccountStore.self) private var account
    @State private var confirmingClear = false
    @State private var exporting = false
    @State private var importing = false
    @State private var backup: LibraryBackupDocument?
    @State private var message: String?
    @State private var showingLogin = false

    /// Taken from the bundle so the number follows `MARKETING_VERSION` in project.yml.
    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 17) {
                        Image("BrandMark").resizable().frame(width: 62, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 17))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("JLive").font(.title2.bold())
                            Text("简简单单，看你喜欢的直播。 ").font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: "v" + Self.version).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 10)
                }
                Section("偏好设置") {
                    Picker("外观", selection: $library.appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.name).tag($0) }
                    }
                    .accessibilityIdentifier("appearancePicker")
                    Button("清空观看记录", role: .destructive) { confirmingClear = true }
                }
                Section("B站账号") {
                    if account.isLoggedIn {
                        Label(account.name, systemImage: "person.crop.circle")
                        Button("退出登录", role: .destructive) { Task { await account.logout() } }
                    } else {
                        Button("登录 B站") { showingLogin = true }
                    }
                }
                Section("平台接入") {
                    ForEach(LivePlatform.allCases) { platform in
                        HStack {
                            PlatformBadge(platform: platform)
                            Spacer()
                            Text(platform.supportsSearch ? "原生播放 / 弹幕 / 搜索" : "原生播放 / 弹幕 / 推荐")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("收藏备份") {
                    Button("导出收藏") {
                        do { backup = LibraryBackupDocument(data: try library.backup()); exporting = true }
                        catch { message = error.localizedDescription }
                    }
                    Button("导入收藏") { importing = true }
                    Text("导入会合并收藏。备份文件可保存在 iCloud 云盘或分享给另一台设备。")
                        .font(.caption).foregroundStyle(.secondary)
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
            .sheet(isPresented: $showingLogin) { BilibiliLoginView() }
            .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "JLive-收藏") { result in
                if case .failure(let error) = result { message = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_000_000 else {
                        throw LiveError.invalidResponse
                    }
                    try library.restore(Data(contentsOf: url))
                    message = "收藏已导入"
                } catch { message = "导入失败：\(error.localizedDescription)" }
            }
            .alert("收藏备份", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("知道了") { message = nil }
            } message: { Text(message ?? "") }
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
