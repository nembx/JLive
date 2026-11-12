import Foundation
import Observation
import Security
import WebKit
import JLiveCore

@MainActor @Observable
final class AccountStore {
    private(set) var name: String = ""
    private(set) var credentials: BilibiliCredentials?
    private(set) var isChecking = false
    var error: String?
    var isLoggedIn: Bool { credentials != nil }
    @ObservationIgnored private let service: LiveService
    private static let key = "com.nembx.JLive.bilibili"

    init(service: LiveService) {
        self.service = service
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
           let saved = try? JSONDecoder().decode(SavedAccount.self, from: data) {
            credentials = saved.credentials
            name = saved.name
            Task { await service.setBilibiliCredentials(saved.credentials) }
        }
    }

    /// Read the login performed on Bilibili's own website and validate it before storing.
    func acceptWebLogin() async -> Bool {
        guard !isChecking else { return false }
        isChecking = true
        error = nil
        defer { isChecking = false }
        do {
            let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
                .filter { $0.domain == "bilibili.com" || $0.domain.hasSuffix(".bilibili.com") }
            func value(_ key: String) -> String { cookies.first { $0.name == key }?.value ?? "" }
            let csrf = value("bili_jct"), session = value("SESSDATA")
            guard !csrf.isEmpty, !session.isEmpty, let uid = Int(value("DedeUserID")) else {
                error = "请在网页上完成登录，再点击完成。"
                return false
            }
            var seen = Set<String>()
            let header = cookies.filter { seen.insert($0.name).inserted }.map { "\($0.name)=\($0.value);" }.joined()
            let credentials = BilibiliCredentials(cookie: header, csrf: csrf, uid: uid)
            let response = try await HTTPClient().get(URL(string: "https://api.bilibili.com/x/web-interface/nav")!, headers: ["Cookie": header, "Referer": "https://www.bilibili.com/"])
            guard response["code"].int == 0, response["data"]["mid"].int == uid else { throw LiveError.platform("登录已失效，请重新登录。") }
            let name = response["data"]["uname"].string
            let data = try JSONEncoder().encode(SavedAccount(name: name, credentials: credentials))
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.key]
            let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound { status = SecItemAdd(query.merging(attributes, uniquingKeysWith: { _, b in b }) as CFDictionary, nil) }
            guard status == errSecSuccess else { throw LiveError.platform("系统钥匙串暂时无法保存登录。") }
            await service.setBilibiliCredentials(credentials)
            self.credentials = credentials
            self.name = name
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func logout() async {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.key] as CFDictionary)
        credentials = nil
        name = ""
        await service.setBilibiliCredentials(nil)
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records.filter { $0.displayName.contains("bilibili.com") })
    }
}

private struct SavedAccount: Codable {
    let name: String
    let credentials: BilibiliCredentials
}
