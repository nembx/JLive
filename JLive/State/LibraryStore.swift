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
