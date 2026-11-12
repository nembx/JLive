import Foundation
import SwiftUI
import JLiveCore

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var name: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor @Observable
final class LibraryStore {
    private(set) var favorites: [LiveRoom] = []
    private(set) var history: [LiveRoom] = []
    private(set) var storageError: String?
    private(set) var isRefreshing = false
    private(set) var refreshMessage: String?
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "jlive.appearance") }
    }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppAppearance(rawValue: defaults.string(forKey: "jlive.appearance") ?? "system") ?? .system
        favorites = load("jlive.favorites")
        history = load("jlive.history")
    }

    func contains(_ room: LiveRoom) -> Bool { favorites.contains { $0.id == room.id } }

    func toggle(_ room: LiveRoom) {
        if contains(room) { favorites.removeAll { $0.id == room.id } }
        else { favorites.insert(room, at: 0) }
        persist(favorites, key: "jlive.favorites")
    }

    func record(_ room: LiveRoom) {
        history.removeAll { $0.id == room.id }
        history.insert(room, at: 0)
        history = Array(history.prefix(50))
        persist(history, key: "jlive.history")
    }

    func enrich(original: LiveRoom, updated: LiveRoom) {
        if let index = favorites.firstIndex(where: { $0.id == original.id }) {
            favorites[index] = updated
            var seen: Set<String> = []
            favorites = favorites.filter { seen.insert($0.id).inserted }
            persist(favorites, key: "jlive.favorites")
        }
        history.removeAll { $0.id == original.id || $0.id == updated.id }
        record(updated)
    }

    func clearHistory() {
        history.removeAll()
        persist(history, key: "jlive.history")
    }

    func refresh(using service: LiveService) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let snapshot = favorites
        var failures = 0
        // Four requests at a time keeps large libraries from flooding the platforms.
        for start in stride(from: 0, to: snapshot.count, by: 4) {
            guard !Task.isCancelled else { return }
            let batch = snapshot[start..<min(start + 4, snapshot.count)]
            let results = await withTaskGroup(of: (String, LiveRoom?).self) { group in
                for room in batch { group.addTask { (room.id, try? await service.detail(room)) } }
                var results: [(String, LiveRoom?)] = []
                for await result in group { results.append(result) }
                return results
            }
            guard !Task.isCancelled else { return }
            for (id, room) in results {
                guard let room else { failures += 1; continue }
                if let index = favorites.firstIndex(where: { $0.id == id }) { favorites[index] = room }
            }
        }
        var seen = Set<String>()
        favorites = favorites.filter { seen.insert($0.id).inserted }
        persist(favorites, key: "jlive.favorites")
        refreshMessage = failures == 0 ? "开播状态已更新" : "已更新，\(failures) 个直播间暂时无法访问"
    }

    func backup() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(LibraryBackup(version: 1, favorites: favorites))
    }

    func restore(_ data: Data) throws {
        guard data.count <= 2_000_000 else { throw LiveError.invalidResponse }
        let backup = try JSONDecoder().decode(LibraryBackup.self, from: data)
        guard backup.version == 1, backup.favorites.count <= 2000 else { throw LiveError.invalidResponse }
        // Validate every room before changing the library, then merge without duplicates.
        for room in backup.favorites { _ = try RoomLinkParser.parse(room.roomID, platform: room.platform) }
        var seen = Set(favorites.map(\.id))
        favorites.append(contentsOf: backup.favorites.filter { seen.insert($0.id).inserted })
        persist(favorites, key: "jlive.favorites")
    }

    private func load(_ key: String) -> [LiveRoom] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do { return try JSONDecoder().decode([LiveRoom].self, from: data) }
        catch { storageError = "本地记录读取失败：\(error.localizedDescription)"; return [] }
    }

    private func persist(_ rooms: [LiveRoom], key: String) {
        do { defaults.set(try JSONEncoder().encode(rooms), forKey: key) }
        catch { storageError = "本地记录保存失败：\(error.localizedDescription)" }
    }
}

private struct LibraryBackup: Codable {
    let version: Int
    let favorites: [LiveRoom]
}
