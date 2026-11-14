import XCTest
import JLiveCore
@testable import JLive

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testBackupMergesWithoutRemovingOrDuplicatingFavorites() throws {
        let first = makeStore()
        let second = makeStore()
        let a = room("42"), b = room("43")
        first.toggle(a)
        second.toggle(a)
        second.toggle(b)
        try first.restore(second.backup())
        XCTAssertEqual(first.favorites.map(\.roomID), ["42", "43"])
        try first.restore(second.backup())
        XCTAssertEqual(first.favorites.count, 2)
    }

    func testInvalidImportLeavesFavoritesIntact() throws {
        let store = makeStore()
        let original = room("42")
        store.toggle(original)
        let invalid = Data(#"{"version":1,"favorites":[{"platform":"bilibili","roomID":"bad/path","title":"坏数据","streamer":"","viewerCount":0,"category":""}]}"#.utf8)
        XCTAssertThrowsError(try store.restore(invalid))
        XCTAssertEqual(store.favorites, [original])
        XCTAssertThrowsError(try store.restore(Data(repeating: 0, count: 2_000_001)))
        XCTAssertEqual(store.favorites, [original])
    }

    func testRefreshCanonicalizesRoomAndPreservesHistory() async {
        let store = makeStore()
        let alias = room("42")
        let canonical = room("10042")
        store.toggle(alias)
        store.toggle(canonical)
        store.record(alias)
        let service = LiveService(providers: [DetailProvider()])
        await store.refresh(using: service)
        XCTAssertEqual(store.favorites.map(\.roomID), ["10042"])
        XCTAssertEqual(store.favorites.first?.isLive, true)
        XCTAssertEqual(store.history.map(\.roomID), ["42"])
        XCTAssertFalse(store.isRefreshing)
    }

    func testFavoriteFiltersKeepUnknownStatusOnlyInAll() {
        let store = makeStore()
        let live = LiveRoom(platform: .bilibili, roomID: "1", title: "直播中", streamer: "A", isLive: true)
        let offline = LiveRoom(platform: .bilibili, roomID: "2", title: "未开播", streamer: "B", isLive: false)
        let unknown = room("3")
        [live, offline, unknown].forEach { store.toggle($0) }
        XCTAssertEqual(store.favorites(matching: .live), [live])
        XCTAssertEqual(store.favorites(matching: .offline), [offline])
        XCTAssertEqual(store.favorites(matching: .all).count, 3)
        XCTAssertTrue(store.favorites(matching: .all).contains(unknown))
    }

    func testHistoryOrdersDeduplicatesAndClearsWithoutChangingFavorites() {
        let store = makeStore()
        let a = room("1"), b = room("2")
        store.toggle(a)
        store.record(a)
        store.record(b)
        store.record(a)
        XCTAssertEqual(store.history, [a, b])
        store.clearHistory()
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertEqual(store.favorites, [a])
    }

    private func makeStore() -> LibraryStore {
        LibraryStore(defaults: UserDefaults(suiteName: "jlive-tests-\(UUID())")!)
    }
    private func room(_ id: String) -> LiveRoom { LiveRoom(platform: .bilibili, roomID: id, title: "直播", streamer: "主播") }
}

private struct DetailProvider: LiveProvider {
    let platform = LivePlatform.bilibili
    func recommendations(page: Int) async throws -> RoomPage { RoomPage(rooms: [], hasMore: false) }
    func search(keyword: String, page: Int) async throws -> RoomPage { try await recommendations(page: page) }
    func detail(room: LiveRoom) async throws -> LiveRoom {
        LiveRoom(platform: .bilibili, roomID: "10042", title: "已更新", streamer: "主播", isLive: true)
    }
}
