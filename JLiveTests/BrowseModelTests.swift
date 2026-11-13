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

    func testCombinedSearchSkipsPlatformsWithoutKeywordSearch() async {
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
        await model.load(isSearch: true)
        XCTAssertFalse(model.rooms.isEmpty)
        model.selectedPlatform = .douyin
        await model.load(isSearch: true)
        XCTAssertTrue(model.rooms.isEmpty)
        XCTAssertFalse(model.isLoading)
        let calls = await douyin.searches
        XCTAssertEqual(calls, 0)
    }
}

private actor BrowseProvider: LiveProvider {
    nonisolated let platform: LivePlatform
    var searches = 0
    init(platform: LivePlatform) { self.platform = platform }
    func recommendations(page: Int) async throws -> RoomPage {
        RoomPage(rooms: [LiveRoom(platform: platform, roomID: String(page), title: "直播", streamer: "主播", isLive: true)], hasMore: page < 2)
    }
    func search(keyword: String, page: Int) async throws -> RoomPage {
        searches += 1
        return try await recommendations(page: page)
    }
}
