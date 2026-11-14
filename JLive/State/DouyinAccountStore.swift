import Foundation
import Observation
import Security
import WebKit
import JLiveCore

@MainActor @Observable
final class DouyinAccountStore {
    private(set) var isLoggedIn = false
    private(set) var isChecking = false
    private(set) var revision = UUID()
    var error: String?
    @ObservationIgnored private let service: LiveService
    private static let key = "com.nembx.JLive.douyin"

    init(service: LiveService) {
        self.service = service
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, let saved = try? JSONDecoder().decode(DouyinCredentials.self, from: data) {
            Task {
                await service.setDouyinCredentials(saved)
                isLoggedIn = true
                revision = UUID()
            }
        }
    }

    func acceptWebLogin() async -> Bool {
        guard !isChecking else { return false }
        isChecking = true
        error = nil
        defer { isChecking = false }
        do {
            let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
                .filter { ($0.domain == "douyin.com" || $0.domain.hasSuffix(".douyin.com")) && ($0.expiresDate ?? .distantFuture) > Date() }
                .sorted { $0.domain.count > $1.domain.count }
            guard cookies.contains(where: { ["sessionid", "sessionid_ss"].contains($0.name) && !$0.value.isEmpty }) else {
                error = "请在抖音官网完成登录，再点击完成。"
                return false
            }
            var seen = Set<String>()
            let header = cookies.filter { seen.insert($0.name).inserted }.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            let credentials = DouyinCredentials(cookie: header)
            try await service.validateDouyinCredentials(credentials)
            let data = try JSONEncoder().encode(credentials)
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.key]
            let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                status = SecItemAdd(query.merging(attributes, uniquingKeysWith: { _, b in b }) as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw LiveError.platform("系统钥匙串暂时无法保存登录。") }
            await service.setDouyinCredentials(credentials)
            isLoggedIn = true
            revision = UUID()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func logout() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.key] as CFDictionary)
        await service.setDouyinCredentials(nil)
        isLoggedIn = false
        error = nil
        revision = UUID()
        let store = WKWebsiteDataStore.default()
        for cookie in await store.httpCookieStore.allCookies()
            where cookie.domain == "douyin.com" || cookie.domain.hasSuffix(".douyin.com") {
            await store.httpCookieStore.deleteCookie(cookie)
        }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records.filter { $0.displayName == "douyin.com" || $0.displayName.hasSuffix(".douyin.com") })
    }
}
