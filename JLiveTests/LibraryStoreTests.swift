import XCTest
import JLiveCore
@testable import JLive

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testQualityPreferencesFollowTheNetworkAndPersistIndependently() {
        let suite = "jlive-quality-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(defaults: defaults)
        XCTAssertEqual(store.preferredQuality(for: .cellular), .high)
        XCTAssertEqual(store.preferredQuality(for: .wifi), .original)
        store.cellularQuality = .standard
        store.wifiQuality = .blueRay
        let restored = LibraryStore(defaults: defaults)
        XCTAssertEqual(restored.preferredQuality(for: .cellular), .standard)
        XCTAssertEqual(restored.preferredQuality(for: .wifi), .blueRay)
    }

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

    func testTwoFavoriteFiltersKeepEveryRoomVisible() {
        let store = makeStore()
        let live = LiveRoom(platform: .bilibili, roomID: "1", title: "直播中", streamer: "A", isLive: true)
        let offline = LiveRoom(platform: .bilibili, roomID: "2", title: "未开播", streamer: "B", isLive: false)
        let unknown = room("3")
        [live, offline, unknown].forEach { store.toggle($0) }
        XCTAssertEqual(store.favorites(matching: .live), [live])
        XCTAssertEqual(store.favorites(matching: .offline), [unknown, offline])
        XCTAssertEqual(store.favorites(matching: .live).count + store.favorites(matching: .offline).count, 3)
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

    func testStatusesAreRequestedWhenThePageIsShownAndAgainOnceTheyAreOld() async {
        var date = Date(timeIntervalSince1970: 0)
        let provider = StatusProvider()
        let service = LiveService(providers: [provider])
        let store = makeStore(now: { date })
        store.toggle(saved("1"))
        await store.refreshIfStale(using: service)
        XCTAssertEqual(store.favorites(matching: .live).map(\.roomID), ["1"], "打开收藏页时不用下拉就更新开播状态")
        await store.refreshIfStale(using: service)
        var calls = await provider.calls
        XCTAssertEqual(calls, 1, "刚更新过的状态不重复请求")
        date += LibraryStore.statusLifetime + 1
        await store.refreshIfStale(using: service)
        calls = await provider.calls
        XCTAssertEqual(calls, 2, "状态过期后重新请求")
        await store.refresh(using: service)
        calls = await provider.calls
        XCTAssertEqual(calls, 3, "下拉刷新总是重新请求")
    }

    func testRefreshCoversTheWholeLibraryWhenThePageCancelsItsTask() async {
        let provider = StatusProvider()
        let service = LiveService(providers: [provider])
        let store = makeStore()
        // More than one batch of four requests.
        for id in 1...6 { store.toggle(saved(String(id))) }
        await provider.hold()
        let page = Task { await store.refresh(using: service) }
        while await provider.waiting < 4 { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(store.isRefreshing)
        // SwiftUI cancels the page's task when the page is left.
        page.cancel()
        await provider.release()
        await page.value
        XCTAssertEqual(store.favorites(matching: .live).count, 6, "页面取消任务后仍然更新全部收藏")
        XCTAssertFalse(store.isRefreshing)
    }

    func testOverlappingRefreshesShareOnePass() async {
        let provider = StatusProvider()
        let service = LiveService(providers: [provider])
        let store = makeStore()
        store.toggle(saved("1"))
        await provider.hold()
        let automatic = Task { await store.refreshIfStale(using: service) }
        while await provider.waiting < 1 { try? await Task.sleep(for: .milliseconds(5)) }
        // The viewer pulls while the automatic update is still running.
        let pulled = Task { await store.refresh(using: service) }
        for _ in 1...3 { await Task.yield() }
        await provider.release()
        await automatic.value
        await pulled.value
        let calls = await provider.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.favorites.first?.isLive, true)
    }

    func testAnUpdateThatLearnsNothingKeepsTheStatusesAndIsTriedAgain() async {
        let provider = StatusProvider()
        let service = LiveService(providers: [provider])
        let store = makeStore()
        store.toggle(saved("1"))
        await provider.setFailing(true)
        await store.refreshIfStale(using: service)
        XCTAssertEqual(store.favorites, [saved("1")])
        XCTAssertEqual(store.refreshMessage, "暂时无法更新开播状态")
        await provider.setFailing(false)
        await store.refreshIfStale(using: service)
        XCTAssertEqual(store.favorites.first?.isLive, true, "失败的更新不算数，再次显示页面时重试")
    }

    func testImportedFavoritesAreCheckedOnTheNextVisit() async throws {
        let provider = StatusProvider()
        let service = LiveService(providers: [provider])
        let store = makeStore()
        store.toggle(saved("1"))
        await store.refreshIfStale(using: service)
        let other = makeStore()
        other.toggle(saved("2"))
        try store.restore(other.backup())
        await store.refreshIfStale(using: service)
        XCTAssertEqual(store.favorites(matching: .live).count, 2, "导入的开播状态来自备份，需要重新查询")
    }

    private func makeStore(now: @escaping () -> Date = Date.init) -> LibraryStore {
        LibraryStore(defaults: UserDefaults(suiteName: "jlive-tests-\(UUID())")!, now: now)
    }
    private func room(_ id: String) -> LiveRoom { LiveRoom(platform: .bilibili, roomID: id, title: "直播", streamer: "主播") }
    /// A favorite saved while its streamer was offline.
    private func saved(_ id: String) -> LiveRoom { LiveRoom(platform: .bilibili, roomID: id, title: "直播", streamer: "主播", isLive: false) }
}

/// Reports every room as live, so a test can see which favorites were asked about.
private actor StatusProvider: LiveProvider {
    nonisolated let platform = LivePlatform.bilibili
    private(set) var calls = 0
    private var failing = false
    private var holding = false
    private var gates: [CheckedContinuation<Void, Never>] = []
    var waiting: Int { gates.count }

    func setFailing(_ value: Bool) { failing = value }
    func hold() { holding = true }
    func release() {
        holding = false
        gates.forEach { $0.resume() }
        gates = []
    }

    func recommendations(page: Int) async throws -> RoomPage { RoomPage(rooms: [], hasMore: false) }
    func search(keyword: String, page: Int) async throws -> RoomPage { try await recommendations(page: page) }
    func detail(room: LiveRoom) async throws -> LiveRoom {
        calls += 1
        if holding { await withCheckedContinuation { gates.append($0) } }
        if failing { throw LiveError.http(503) }
        var room = room
        room.isLive = true
        return room
    }
}

private struct DetailProvider: LiveProvider {
    let platform = LivePlatform.bilibili
    func recommendations(page: Int) async throws -> RoomPage { RoomPage(rooms: [], hasMore: false) }
    func search(keyword: String, page: Int) async throws -> RoomPage { try await recommendations(page: page) }
    func detail(room: LiveRoom) async throws -> LiveRoom {
        LiveRoom(platform: .bilibili, roomID: "10042", title: "已更新", streamer: "主播", isLive: true)
    }
}
