import Foundation

/// Bilibili's web QR sign-in: JLive shows the code and the user confirms it in the Bilibili app.
public enum BilibiliQRLogin {
    public struct Code: Sendable, Equatable {
        public let url: URL
        public let key: String
        public init(url: URL, key: String) { self.url = url; self.key = key }

        /// Opens the confirmation page in the Bilibili app's own browser, for signing in on the same phone.
        public var appURL: URL? {
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
            guard let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
            return URL(string: "bilibili://browser?url=" + encoded)
        }
    }

    public enum State: Sendable, Equatable { case waiting, scanned, expired, confirmed }

    public static let generateURL = URL(string: "https://passport.bilibili.com/x/passport-login/web/qrcode/generate")!

    public static func pollURL(key: String) throws -> URL {
        try endpoint("https://passport.bilibili.com/x/passport-login/web/qrcode/poll", ["qrcode_key": key])
    }

    public static func code(from response: JSONValue) throws -> Code {
        let data = response["data"]
        guard Int(response["code"].string) == 0, !data["qrcode_key"].string.isEmpty,
              let url = URL(string: data["url"].string), url.scheme == "https",
              url.host == "bilibili.com" || url.host?.hasSuffix(".bilibili.com") == true else { throw LiveError.invalidResponse }
        return Code(url: url, key: data["qrcode_key"].string)
    }

    public static func state(from response: JSONValue) throws -> State {
        let data = response["data"]
        guard Int(response["code"].string) == 0, let status = Int(data["code"].string) else { throw LiveError.invalidResponse }
        switch status {
        case 0: return .confirmed
        case 86101: return .waiting
        case 86090: return .scanned
        case 86038: return .expired
        default: throw LiveError.platform(data["message"].string.isEmpty ? "B站登录暂时不可用，请稍后重试" : data["message"].string)
        }
    }
}
