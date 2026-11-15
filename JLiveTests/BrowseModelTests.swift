import XCTest
import JLiveCore
@testable import JLive

@MainActor
final class BrowseModelTests: XCTestCase {
    func testDouyinRecommendationsAndPaginationAppearInBrowse() async {
        let provider = BrowseProvider(platform: .douyin)
        let model = BrowseModel(service: LiveService(providers: [provider]))
        model.selectedPlatform = .douyin
        await model.load(isSearch: false)
        XCTAssertEqual(model.rooms.map(\.roomID), ["1"])
        XCTAssertTrue(model.hasMore)
        await model.loadMore(isSearch: false)
        XCTAssertEqual(model.rooms.map(\.roomID), ["1", "2"])
        XCTAssertFalse(model.hasMore)
        XCTAssertTrue(model.issues.isEmpty)
    }

    func testCombinedSearchSkipsDouyinWhichNeedsAnAccount() async {
        let bili = BrowseProvider(platform: .bilibili)
        let douyin = BrowseProvider(platform: .douyin)
        let model = BrowseModel(service: LiveService(providers: [bili, douyin]))
        model.keyword = "主播"
        await model.load(isSearch: true)
        XCTAssertEqual(model.rooms.map(\.platform), [.bilibili])
        let calls = await douyin.searches
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(model.issues.isEmpty)
    }

    func testSelectingDouyinSearchClearsEarlierResultsWithoutRequest() async {
        let bili = BrowseProvider(platform: .bilibili)
        let douyin = BrowseProvider(platform: .douyin)
        let model = BrowseModel(service: LiveService(providers: [bili, douyin]))
        model.keyword = "主播"
        await model.loadIfNeeded(isSearch: true)
        XCTAssertFalse(model.rooms.isEmpty)
        model.selectedPlatform = .douyin
        await model.loadIfNeeded(isSearch: true)
        XCTAssertTrue(model.rooms.isEmpty)
        XCTAssertFalse(model.isLoading)
        let calls = await douyin.searches
        XCTAssertEqual(calls, 0)
    }

    func testReturningToALoadedListDoesNotRequestItAgainUntilItExpires() async {
        var date = Date(timeIntervalSince1970: 0)
        let bili = BrowseProvider(platform: .bilibili)
        let huya = BrowseProvider(platform: .huya)
        let model = BrowseModel(service: LiveService(providers: [bili, huya]), now: { date })
        model.selectedPlatform = .bilibili
        await model.loadIfNeeded(isSearch: false)
        await model.loadMore(isSearch: false)
        // Coming back from another tab or a live room runs the page task again.
        await model.loadIfNeeded(isSearch: false)
        var calls = await bili.recommendationCalls
        XCTAssertEqual(calls, 2, "第一页和加载更多各一次")

        model.selectedPlatform = .huya
        await model.loadIfNeeded(isSearch: false)
        XCTAssertEqual(model.rooms.map(\.platform), [.huya])
        model.selectedPlatform = .bilibili
        await model.loadIfNeeded(isSearch: false)
        XCTAssertEqual(model.rooms.map(\.roomID), ["1", "2"], "切回平台时保留已加载的分页")
        XCTAssertFalse(model.hasMore)
        calls = await bili.recommendationCalls
        XCTAssertEqual(calls, 2)

        date += BrowseModel.cacheLifetime + 1
        await model.loadIfNeeded(isSearch: false)
        calls = await bili.recommendationCalls
        XCTAssertEqual(calls, 3, "过期后重新请求")
        XCTAssertEqual(model.rooms.first?.title, "直播3")
    }

    func testExpiredPlatformCacheStaysVisibleWhileItIsUpdated() async {
        var date = Date(timeIntervalSince1970: 0)
        let bili = BrowseProvider(platform: .bilibili)
        let huya = BrowseProvider(platform: .huya)
        let model = BrowseModel(service: LiveService(providers: [bili, huya]), now: { date })
        model.selectedPlatform = .bilibili
        await model.loadIfNeeded(isSearch: false)
        model.selectedPlatform = .huya
        await model.loadIfNeeded(isSearch: false)

        date += BrowseModel.cacheLifetime + 1
        await bili.hold()
        model.selectedPlatform = .bilibili
        let update = Task { await model.loadIfNeeded(isSearch: false) }
        while await !bili.isWaiting { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(model.rooms.map(\.platform), [.bilibili])
        XCTAssertEqual(model.rooms.first?.title, "直播1", "过期缓存先显示，更新期间不清空")
        await bili.release()
        await update.value
        XCTAssertEqual(model.rooms.first?.title, "直播2")
    }

    func testRefreshKeepsTheListOnScreenAndFinishesWhenTheGestureIsCancelled() async {
        let provider = BrowseProvider(platform: .bilibili)
        let model = BrowseModel(service: LiveService(providers: [provider]))
        await model.loadIfNeeded(isSearch: false)
        XCTAssertEqual(model.rooms.first?.title, "直播1")

        await provider.hold()
        let refresh = Task { await model.refresh(isSearch: false) }
        while await !provider.isWaiting { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(model.rooms.first?.title, "直播1", "刷新期间保留原列表")
        XCTAssertTrue(model.isRefreshing)
        // SwiftUI cancels the refresh action when the page re-renders during the pull.
        refresh.cancel()
        await provider.release()
        await refresh.value
        XCTAssertEqual(model.rooms.first?.title, "直播2")
        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertFalse(model.isLoading)
    }

    func testFailedRefreshKeepsTheListAndFailuresAreNotCached() async {
        let provider = BrowseProvider(platform: .bilibili)
        let model = BrowseModel(service: LiveService(providers: [provider]))
        await model.loadIfNeeded(isSearch: false)
        await provider.setFailing(true)
        await model.refresh(isSearch: false)
        XCTAssertEqual(model.rooms.first?.title, "直播1")
        XCTAssertEqual(model.issues.map(\.platform), [.bilibili])

        let empty = BrowseModel(service: LiveService(providers: [provider]))
        await empty.loadIfNeeded(isSearch: false)
        XCTAssertTrue(empty.rooms.isEmpty)
        XCTAssertTrue(empty.hasLoaded)
        XCTAssertEqual(empty.issues.count, 1)
        await provider.setFailing(false)
        await empty.loadIfNeeded(isSearch: false)
        XCTAssertFalse(empty.rooms.isEmpty, "失败的结果不缓存，回到页面时重试")
        XCTAssertTrue(empty.issues.isEmpty)
    }
}

private actor BrowseProvider: LiveProvider {
    nonisolated let platform: LivePlatform
    var searches = 0
    var recommendationCalls = 0
    private var failing = false
    private var holding = false
    private var gate: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { gate != nil }

    init(platform: LivePlatform) { self.platform = platform }

    func setFailing(_ value: Bool) { failing = value }
    func hold() { holding = true }
    func release() {
        holding = false
        gate?.resume()
        gate = nil
    }

    func recommendations(page: Int) async throws -> RoomPage {
        recommendationCalls += 1
        let call = recommendationCalls
        if holding { await withCheckedContinuation { gate = $0 } }
        if failing { throw LiveError.http(503) }
        return RoomPage(rooms: [LiveRoom(platform: platform, roomID: String(page), title: "直播\(call)", streamer: "主播", isLive: true)], hasMore: page < 2)
    }
    func search(keyword: String, page: Int) async throws -> RoomPage {
        searches += 1
        return try await recommendations(page: page)
    }
}
