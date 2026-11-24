import Foundation
import Observation
import JLiveCore

protocol BilibiliQRTransport: Sendable {
    func generate() async throws -> BilibiliQRLogin.Code
    func poll(key: String) async throws -> BilibiliQRLogin.State
    /// The account the platform signed in once the code was confirmed.
    func credentials() async -> BilibiliCredentials?
}

/// Drives the in-app sign-in page: shows a code and follows it until the viewer confirms it in the Bilibili app.
@MainActor @Observable
final class BilibiliQRLoginModel {
    enum Phase: Equatable { case loading, waiting, scanned, confirming, expired, failed(String), signedIn }
    private(set) var phase = Phase.loading
    private(set) var code: BilibiliQRLogin.Code?
    /// False while there is no code the viewer could still confirm.
    var canConfirm: Bool { code != nil && (phase == .waiting || phase == .scanned) }
    @ObservationIgnored private let transport: any BilibiliQRTransport
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let signIn: @MainActor (BilibiliCredentials) async throws -> Void

    init(transport: (any BilibiliQRTransport)? = nil, interval: Duration = .seconds(2),
         signIn: @escaping @MainActor (BilibiliCredentials) async throws -> Void = { try await BilibiliSession.shared.signIn($0) }) {
        self.transport = transport ?? Self.standardTransport()
        self.interval = interval
        self.signIn = signIn
    }

    private static func standardTransport() -> any BilibiliQRTransport {
        #if DEBUG
        // "--live-qr-login" keeps the fixture room but asks Bilibili for a real code.
        if CommandLine.arguments.contains("--ui-fixtures"), !CommandLine.arguments.contains("--live-qr-login") { return UIFixtures.qrTransport }
        #endif
        return BilibiliQRSession()
    }

    /// Shows a new code and returns once it is confirmed, expired or failed, or the page went away.
    func run() async {
        phase = .loading
        code = nil
        do {
            let code = try await transport.generate()
            try Task.checkCancellation()
            self.code = code
            phase = .waiting
            var failures = 0
            while true {
                try await Task.sleep(for: interval)
                let state: BilibiliQRLogin.State
                do {
                    state = try await transport.poll(key: code.key)
                    failures = 0
                } catch {
                    // Confirming in the Bilibili app puts JLive in the background, where a request can be dropped.
                    try Task.checkCancellation()
                    failures += 1
                    if failures >= 5 { throw error }
                    continue
                }
                try Task.checkCancellation()
                switch state {
                case .waiting: phase = .waiting
                case .scanned: phase = .scanned
                case .expired:
                    phase = .expired
                    return
                case .confirmed:
                    phase = .confirming
                    guard let credentials = await transport.credentials() else { throw LiveError.platform("未能读取登录信息，请重试") }
                    try await signIn(credentials)
                    try Task.checkCancellation()
                    phase = .signedIn
                    return
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}

/// Keeps the sign-in cookies in a session of their own, apart from the app's guest requests.
actor BilibiliQRSession: BilibiliQRTransport {
    private let session: URLSession
    private let storage: HTTPCookieStorage?
    private var hasDeviceID = false

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        storage = configuration.httpCookieStorage
        session = URLSession(configuration: configuration)
    }

    func generate() async throws -> BilibiliQRLogin.Code {
        if !hasDeviceID, let data = try? await json(URL(string: "https://api.bilibili.com/x/frontend/finger/spi")!)["data"], !data["b_3"].string.isEmpty {
            // Sign in and later play with one browser identifier, as a browser would.
            for (name, value) in [("buvid3", data["b_3"].string), ("buvid4", data["b_4"].string)] where !value.isEmpty {
                if let cookie = HTTPCookie(properties: [.domain: ".bilibili.com", .path: "/", .name: name, .value: value]) { storage?.setCookie(cookie) }
            }
            hasDeviceID = true
        }
        return try BilibiliQRLogin.code(from: try await json(BilibiliQRLogin.generateURL))
    }

    func poll(key: String) async throws -> BilibiliQRLogin.State {
        try BilibiliQRLogin.state(from: try await json(try BilibiliQRLogin.pollURL(key: key)))
    }

    func credentials() async -> BilibiliCredentials? { BilibiliSession.credentials(from: storage?.cookies ?? []) }

    private func json(_ url: URL) async throws -> JSONValue {
        var request = URLRequest(url: url)
        request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw LiveError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw LiveError.http(response.statusCode) }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw LiveError.invalidResponse }
        return value
    }
}
