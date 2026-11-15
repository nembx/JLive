import Foundation
import Security
import WebKit

/// Versions up to 0.5.0 offered Bilibili and Douyin login. JLive no longer uses accounts,
/// so the sessions those versions saved are removed once instead of staying on the device.
enum LegacyAccountCleanup {
    @MainActor static func run(defaults: UserDefaults = .standard) {
        let done = "jlive.legacyAccountsRemoved"
        guard !defaults.bool(forKey: done) else { return }
        for service in ["com.nembx.JLive.bilibili", "com.nembx.JLive.douyin"] {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
        }
        Task {
            // The login pages were the only web content JLive loaded into this store.
            let store = WKWebsiteDataStore.default()
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            let records = await store.dataRecords(ofTypes: types)
            await store.removeData(ofTypes: types, for: records.filter {
                $0.displayName.hasSuffix("bilibili.com") || $0.displayName.hasSuffix("douyin.com")
            })
            defaults.set(true, forKey: done)
        }
    }
}
