import SwiftUI
import WebKit
import CoreImage.CIFilterBuiltins
import JLiveCore

/// Signs in to Bilibili inside the app: confirm a code in the Bilibili app, with the website as a fallback.
struct BilibiliLoginView: View {
    let onSignedIn: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var login = BilibiliQRLoginModel()
    @State private var attempt = 0
    @State private var qrImage: UIImage?
    @State private var appMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if verticalSizeClass == .compact {
                        // Landscape, e.g. opened from the full-screen player: the code sits beside the actions.
                        HStack(alignment: .center, spacing: 28) {
                            codeCard
                            VStack(spacing: 18) { heading; actions }
                        }
                    } else {
                        VStack(spacing: 22) { heading; codeCard; actions }
                    }
                }
                .padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .background(JLiveTheme.background)
            .navigationTitle("登录 B站").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            // Runs again when the page returns from the website sign-in, with a new code.
            .task(id: attempt) { await login.run() }
            .onChange(of: login.code, initial: true) { _, code in qrImage = code.flatMap { Self.qrImage($0.url.absoluteString) } }
            .onChange(of: login.phase) { _, phase in if phase == .signedIn { finish() } }
        }
        .tint(JLiveTheme.accent)
    }

    private var heading: some View {
        Text("用哔哩哔哩 App 确认登录").font(.title3.bold()).multilineTextAlignment(.center)
    }

    private var codeCard: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(.white)
                if let qrImage {
                    Image(uiImage: qrImage).interpolation(.none).resizable().scaledToFit().padding(16)
                        .opacity(login.canConfirm ? 1 : 0.06)
                        .accessibilityLabel("B站登录二维码").accessibilityIdentifier("bilibiliLoginCode")
                }
                // The card stays white in dark mode so the code can be scanned; its text is always dark.
                Group {
                    switch login.phase {
                    case .loading: ProgressView().tint(.gray)
                    case .confirming, .signedIn: ProgressView().tint(.gray)
                    case .expired: cardNotice("二维码已过期", action: "刷新二维码")
                    case .failed(let message): cardNotice(message, action: "重试")
                    case .waiting, .scanned: EmptyView()
                    }
                }
                .padding(18)
            }
            .frame(width: 216, height: 216)
            .shadow(color: .black.opacity(0.08), radius: 14, y: 4)
            Label(status.text, systemImage: status.symbol).font(.subheadline.weight(.medium))
                .foregroundStyle(login.phase == .scanned ? JLiveTheme.accent : Color.secondary)
                .accessibilityIdentifier("bilibiliLoginStatus")
        }
    }

    private func cardNotice(_ message: String, action: String) -> some View {
        VStack(spacing: 12) {
            Text(message).font(.subheadline.weight(.medium)).foregroundStyle(.black)
                .multilineTextAlignment(.center).lineLimit(4).minimumScaleFactor(0.8)
            Button(action) { attempt += 1 }.buttonStyle(.borderedProminent).tint(JLiveTheme.color(.bilibili))
        }
    }

    private var status: (text: String, symbol: String) {
        switch login.phase {
        case .loading: ("正在获取二维码…", "qrcode")
        case .waiting: ("等待确认", "qrcode.viewfinder")
        case .scanned: ("已扫码，请在哔哩哔哩 App 中确认", "checkmark.circle.fill")
        case .confirming, .signedIn: ("正在确认登录…", "person.crop.circle.badge.checkmark")
        case .expired: ("二维码已过期", "clock.arrow.circlepath")
        case .failed: ("暂时无法获取登录状态", "exclamationmark.triangle")
        }
    }

    private var actions: some View {
        VStack(spacing: 14) {
            Button(action: openBilibiliApp) {
                Label("打开哔哩哔哩 App 确认", systemImage: "arrow.up.forward.app")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent).tint(JLiveTheme.color(.bilibili)).disabled(!login.canConfirm)
            .accessibilityIdentifier("bilibiliLoginOpenApp")
            if let appMessage {
                Text(appMessage).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("bilibiliLoginAppMessage")
            }
            Text("确认后回到 JLive 即可完成登录。也可以用另一台设备上的哔哩哔哩 App 扫描二维码。")
                .font(.footnote).foregroundStyle(.secondary)
            NavigationLink("改用网页登录（短信或密码）") { BilibiliWebLoginView(onSignedIn: finish) }
                .font(.subheadline.weight(.medium)).frame(minHeight: 44)
            Text("登录信息只保存在本机，可在播放器设置中退出。").font(.caption).foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
    }

    private func openBilibiliApp() {
        guard let url = login.code?.appURL else { return }
        appMessage = nil
        Task {
            if await !UIApplication.shared.open(url) { appMessage = "没有找到哔哩哔哩 App。可以用另一台设备扫码，或改用网页登录。" }
        }
    }

    private func finish() {
        onSignedIn()
        dismiss()
    }

    private static func qrImage(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Bilibili's own sign-in page, for viewers who would rather use a text message or password.
private struct BilibiliWebLoginView: View {
    let onSignedIn: () -> Void
    @State private var message: String?
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 0) {
            BilibiliLoginPage { credentials in
                isChecking = true
                defer { isChecking = false }
                do {
                    try await BilibiliSession.shared.signIn(credentials)
                    onSignedIn()
                    return true
                } catch {
                    message = error.localizedDescription
                    return false
                }
            }
            if isChecking { ProgressView("正在确认登录…").padding() }
            if let message { Text(message).font(.caption).foregroundStyle(.red).padding() }
        }
        .navigationTitle("网页登录").navigationBarTitleDisplayMode(.inline)
    }
}

private struct BilibiliLoginPage: UIViewRepresentable {
    let onCredentials: (BilibiliCredentials) async -> Bool
    func makeCoordinator() -> Coordinator { Coordinator(onCredentials: onCredentials) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: URL(string: "https://passport.bilibili.com/h5-app/passport/login")!))
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
