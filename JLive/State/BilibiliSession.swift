import Foundation
import Observation
import Security
import WebKit
import JLiveCore

@MainActor @Observable
final class BilibiliSession {
    static let shared = BilibiliSession()
    private static let keychainService = "com.nembx.JLive.bilibili.playback"
    private var credentials: BilibiliCredentials?
    var isLoggedIn: Bool { credentials != nil }

    private init() {
        var query = Self.keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            credentials = try? JSONDecoder().decode(BilibiliCredentials.self, from: data)
        }
    }

    func apply(to service: LiveService) async { await service.setBilibiliCredentials(credentials) }

    func signIn(_ credentials: BilibiliCredentials) async throws {
        let response = try await HTTPClient().get(URL(string: "https://api.bilibili.com/x/web-interface/nav")!,
            headers: ["Cookie": credentials.cookie, "Referer": "https://live.bilibili.com/"])
        guard case .bool(true) = response["data"]["isLogin"] else { throw LiveError.platform("未能确认 B站登录，请重新登录") }
        let data = try JSONEncoder().encode(credentials)
        let status = SecItemUpdate(Self.keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = Self.keychainQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw LiveError.platform("未能保存登录，请重试") }
        } else if status != errSecSuccess { throw LiveError.platform("未能保存登录，请重试") }
        self.credentials = credentials
    }

    func signOut() {
        SecItemDelete(Self.keychainQuery as CFDictionary)
        credentials = nil
    }

    nonisolated static func credentials(from cookies: [HTTPCookie]) -> BilibiliCredentials? {
        let valid = cookies.filter { $0.domain == "bilibili.com" || $0.domain.hasSuffix(".bilibili.com") }
        let values = Dictionary(valid.map { ($0.name, $0.value) }, uniquingKeysWith: { a, _ in a })
        guard let session = values["SESSDATA"], !session.isEmpty,
              let csrf = values["bili_jct"], !csrf.isEmpty,
              let uid = values["DedeUserID"].flatMap(Int.init), uid > 0 else { return nil }
        let cookie = values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";") + ";"
        return BilibiliCredentials(cookie: cookie, csrf: csrf, uid: uid)
    }

    private static var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "playback"]
    }
}
