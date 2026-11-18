import XCTest
import JLiveCore
@testable import JLive

@MainActor
final class PlayerModelTests: XCTestCase {
    func testOpeningRequestsThePreferredPlatformQuality() async {
        let provider = QualityProvider()
        let model = makeModel(provider)
        await model.load(preference: .high)
        XCTAssertEqual(model.selectedQuality, 100)
        let requests = await provider.requests
        XCTAssertEqual(requests, [nil, 100])
        model.stop()
    }

    func testCurrentPreferredQualityDoesNotNeedAnotherRequest() async {
        let provider = QualityProvider()
        let model = makeModel(provider)
        await model.load(preference: .original)
        let requests = await provider.requests
        XCTAssertEqual(requests, [nil])
        XCTAssertEqual(model.selectedQuality, 0)
        model.stop()
    }

    func testManualSelectionTakesPriorityAndSurvivesReconnect() async {
        let provider = QualityProvider()
        let model = makeModel(provider)
        await model.load(preference: .original)
        await model.load(quality: 100, preference: .original)
        await model.load()
        let requests = await provider.requests
        XCTAssertEqual(requests, [nil, 100, 100])
        XCTAssertEqual(model.selectedQuality, 100)
        model.stop()
    }

    func testUnavailablePreferredStreamKeepsThePlayableDefault() async {
        let provider = QualityProvider(failsPreferred: true)
        let model = makeModel(provider)
        await model.load(preference: .high)
        XCTAssertEqual(model.selectedQuality, 0)
        XCTAssertNotNil(model.playbackInfo)
        XCTAssertNil(model.errorMessage)
        model.stop()
    }

    func testStoppedPreferenceRequestCannotRestartThePlayer() async {
        let provider = QualityProvider(holdsPreferred: true)
        let model = makeModel(provider)
        let loading = Task { await model.load(preference: .high) }
        while await !provider.isWaiting { await Task.yield() }
        model.stop()
        await provider.release()
        await loading.value
        XCTAssertNil(model.playbackInfo)
        XCTAssertNil(model.player.currentItem)
        XCTAssertFalse(model.isResolving)
    }

    private func makeModel(_ provider: QualityProvider) -> PlayerModel {
        PlayerModel(room: LiveRoom(platform: .huya, roomID: "42", title: "直播", streamer: "主播", isLive: true), service: LiveService(providers: [provider]))
    }
}

private actor QualityProvider: LiveProvider {
    nonisolated let platform = LivePlatform.huya
    var requests: [Int?] = []
    private let failsPreferred: Bool
    private let holdsPreferred: Bool
    private var gate: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { gate != nil }

    init(failsPreferred: Bool = false, holdsPreferred: Bool = false) {
        self.failsPreferred = failsPreferred
        self.holdsPreferred = holdsPreferred
    }

    func release() { gate?.resume(); gate = nil }
    func recommendations(page: Int) async throws -> RoomPage { RoomPage(rooms: [], hasMore: false) }
    func search(keyword: String, page: Int) async throws -> RoomPage { RoomPage(rooms: [], hasMore: false) }
    func playback(roomID: String, quality: Int?) async throws -> PlaybackInfo {
        requests.append(quality)
        if quality != nil {
            if holdsPreferred { await withCheckedContinuation { gate = $0 } }
            if failsPreferred { throw LiveError.noPlayableStream }
        }
        return PlaybackInfo(lines: [], qualities: [StreamQuality(id: 0, name: "原画"), StreamQuality(id: 100, name: "高清")], currentQuality: quality ?? 0, headers: [:])
    }
}
