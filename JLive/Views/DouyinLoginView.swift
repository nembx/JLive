import SwiftUI
import WebKit
import JLiveCore

struct DouyinLoginView: View {
    @Environment(DouyinAccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(account.error ?? "在抖音官网完成登录后，点击完成。登录仅用于直播搜索。")
                    .font(.caption).foregroundStyle(account.error == nil ? Color.secondary : .red)
                    .padding(JLiveLayout.cardInset).frame(maxWidth: .infinity, alignment: .leading)
                DouyinLoginWebView()
            }
            .navigationTitle("登录抖音").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(account.isChecking).accessibilityIdentifier("cancelDouyinLogin")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(account.isChecking ? "验证中…" : "完成") {
                        Task { if await account.acceptWebLogin() { dismiss() } }
                    }.disabled(account.isChecking)
                }
            }
        }
        .interactiveDismissDisabled(account.isChecking)
        .onAppear { account.error = nil }
    }
}

private struct DouyinLoginWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.customUserAgent = DouyinCredentials.userAgent
        web.load(URLRequest(url: URL(string: "https://www.douyin.com/")!))
        return web
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: ()) {
        view.pauseAllMediaPlayback(completionHandler: nil)
        view.stopLoading()
    }
}
