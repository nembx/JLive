import SwiftUI
import WebKit
import JLiveCore

struct BilibiliLoginView: View {
    let onSignedIn: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var isChecking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("在 B站官方页面登录后，使用账号可获得的直播画质。登录信息保存在本机，可在播放器设置中退出。")
                    .font(.caption).foregroundStyle(.secondary).padding(16)
                BilibiliLoginPage { credentials in
                    isChecking = true
                    defer { isChecking = false }
                    do {
                        try await BilibiliSession.shared.signIn(credentials)
                        onSignedIn()
                        dismiss()
                        return true
                    } catch {
                        message = error.localizedDescription
                        return false
                    }
                }
                if isChecking { ProgressView("正在确认登录…").padding() }
                if let message { Text(message).font(.caption).foregroundStyle(.red).padding() }
            }
            .navigationTitle("登录 B站").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

private struct BilibiliLoginPage: UIViewRepresentable {
    let onCredentials: (BilibiliCredentials) async -> Bool
    func makeCoordinator() -> Coordinator { Coordinator(onCredentials: onCredentials) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = HTTPClient.userAgent
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: URL(string: "https://passport.bilibili.com/login")!))
        context.coordinator.start(view)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) { coordinator.task?.cancel(); view.stopLoading() }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let onCredentials: (BilibiliCredentials) async -> Bool
        var task: Task<Void, Never>?
        init(onCredentials: @escaping (BilibiliCredentials) async -> Bool) { self.onCredentials = onCredentials }
        func start(_ view: WKWebView) {
            task = Task { [weak view, weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled, let view, let self else { return }
                    let cookies = await view.configuration.websiteDataStore.httpCookieStore.allCookies()
                    if let credentials = BilibiliSession.credentials(from: cookies) {
                        if await self.onCredentials(credentials) { return }
                        try? await Task.sleep(for: .seconds(5))
                    }
                }
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            if navigationAction.targetFrame == nil, ["https", "http"].contains(url.scheme ?? "") {
                webView.load(navigationAction.request)
                return .cancel
            }
            return ["https", "http", "about"].contains(url.scheme ?? "") ? .allow : .cancel
        }
    }
}
