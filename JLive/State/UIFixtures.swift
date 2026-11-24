#if DEBUG
import Foundation
import JLiveCore

/// Isolated data for navigation tests; never uses the user's library or live audio.
enum UIFixtures {
    static let rooms = [
        LiveRoom(platform: .bilibili, roomID: "1", title: "一起看游戏直播", streamer: "主播一", isLive: true),
        LiveRoom(platform: .bilibili, roomID: "2", title: "音乐与生活，每天都有新的精彩等你发现", streamer: "主播二", isLive: false),
        LiveRoom(platform: .bilibili, roomID: "3", title: "等待更新的直播间", streamer: "主播三")
    ]
    /// Saved as offline. The fixture platform reports it live, like a streamer who started after the last visit.
    static let startedRoom = LiveRoom(platform: .bilibili, roomID: "4", title: "刚刚开播的直播间", streamer: "主播四", isLive: false)
    static var service: LiveService { LiveService(providers: [FixtureProvider()]) }
    static var qrTransport: any BilibiliQRTransport { FixtureQRTransport() }
    @MainActor static func library() -> LibraryStore {
        let suite = "jlive-ui-fixtures"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = LibraryStore(defaults: defaults)
        for room in (rooms + [startedRoom]).reversed() { store.toggle(room) }
        store.record(rooms[1])
        store.record(rooms[0])
        return store
    }
}

/// A sign-in code that is never confirmed, so the page can be checked without reaching Bilibili.
private struct FixtureQRTransport: BilibiliQRTransport {
    func generate() async throws -> BilibiliQRLogin.Code {
        BilibiliQRLogin.Code(url: URL(string: "https://account.bilibili.com/h5/account-h5/auth/scan-web?navhide=1&callback=close&qrcode_key=fixture&from=")!, key: "fixture")
    }
    func poll(key: String) async throws -> BilibiliQRLogin.State {
        CommandLine.arguments.contains("--fixture-qr-expired") ? .expired : .waiting
    }
    func credentials() async -> BilibiliCredentials? { nil }
}

private actor FixtureProvider: LiveProvider {
    nonisolated let platform = LivePlatform.bilibili
    private var requests = 0

    /// The first card's popularity is the request number, so a test can tell a cached list from a new one.
    func recommendations(page: Int) async throws -> RoomPage {
        requests += 1
        let request = requests
        // Later requests take long enough for a test to look at the page while one is running.
        if request > 1 { try await Task.sleep(for: .milliseconds(800)) }
        var rooms = UIFixtures.rooms
        rooms[0].viewerCount = request
        return RoomPage(rooms: rooms, hasMore: false)
    }
    func search(keyword: String, page: Int) async throws -> RoomPage { RoomPage(rooms: UIFixtures.rooms, hasMore: false) }
    func categories() async throws -> [LiveCategoryGroup] {
        [LiveCategoryGroup(id: "2", name: "网游", children: [
            LiveCategory(platform: .bilibili, categoryID: "86", parentID: "2", name: "英雄联盟"),
            LiveCategory(platform: .bilibili, categoryID: "240", parentID: "2", name: "单机游戏")
        ]), LiveCategoryGroup(id: "3", name: "音乐", children: [
            LiveCategory(platform: .bilibili, categoryID: "235", parentID: "3", name: "放松音乐")
        ])]
    }
    /// Every category has rooms of its own, so a test can tell which category a list belongs to.
    func categoryRooms(category: LiveCategory, page: Int) async throws -> RoomPage {
        RoomPage(rooms: [LiveRoom(platform: .bilibili, roomID: "\(category.categoryID)\(page)", title: "\(category.name) · 第\(page)页", streamer: "分区主播", category: category.name, isLive: true)], hasMore: page < 2)
    }
    func detail(room: LiveRoom) async throws -> LiveRoom {
        var room = room
        if room.id == UIFixtures.startedRoom.id { room.isLive = true }
        return room
    }
    func playback(roomID: String, quality: Int?) async throws -> PlaybackInfo {
        var lines: [StreamLine] = []
        if let index = CommandLine.arguments.firstIndex(of: "--fixture-video"),
           CommandLine.arguments.indices.contains(index + 1) {
            lines = [StreamLine(url: URL(fileURLWithPath: CommandLine.arguments[index + 1]))]
        }
        if CommandLine.arguments.contains("--fixture-quality-switch") {
            if quality != nil { try await Task.sleep(for: .milliseconds(800)) }
            let actual = CommandLine.arguments.contains("--fixture-quality-fallback") ? 250 : (quality ?? 250)
            let notice = CommandLine.arguments.contains("--fixture-quality-notice") ? "平台当前仅提供超清" : nil
            return PlaybackInfo(lines: lines, qualities: [StreamQuality(id: 10000, name: "原画"), StreamQuality(id: 400, name: "蓝光"), StreamQuality(id: 250, name: "超清")], currentQuality: actual, headers: [:], qualityNotice: notice)
        }
        return PlaybackInfo(lines: lines, qualities: [StreamQuality(id: 0, name: "原画")], currentQuality: 0, headers: [:])
    }
}
#endif
