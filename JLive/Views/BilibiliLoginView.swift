import SwiftUI
import WebKit

struct BilibiliLoginView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = account.error { Text(error).font(.caption).foregroundStyle(.red).padding(12) }
                LoginWebView()
            }
            .navigationTitle("登录 B站").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(account.isChecking ? "验证中…" : "完成") {
                        Task { if await account.acceptWebLogin() { dismiss() } }
                    }.disabled(account.isChecking)
                }
            }
        }.onAppear { account.error = nil }
    }
}

private struct LoginWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.load(URLRequest(url: URL(string: "https://passport.bilibili.com/login")!))
        return web
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: ()) { view.stopLoading() }
}
