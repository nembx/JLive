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
    static var service: LiveService { LiveService(providers: [FixtureProvider()]) }
    @MainActor static func library() -> LibraryStore {
        let suite = "jlive-ui-fixtures"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = LibraryStore(defaults: defaults)
        for room in rooms.reversed() { store.toggle(room) }
        store.record(rooms[1])
        store.record(rooms[0])
        return store
    }
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
}
#endif
