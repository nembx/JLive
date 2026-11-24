import XCTest
import JLiveCore
@testable import JLive

@MainActor
final class PlayerModelTests: XCTestCase {
    func testOpeningARoomKeepsThePlatformNoticeOutOfTheSwitchMessage() async {
        let model = makeModel(QualityProvider(notice: "平台当前仅返回原画"))
        await model.load()
        XCTAssertNil(model.qualitySwitchMessage, "打开直播间不是切换画质，不应弹出提示")
        XCTAssertEqual(model.playbackInfo?.qualityNotice, "平台当前仅返回原画", "提示仍保留在画质菜单和播放设置中")
        await model.load(preference: .high)
        XCTAssertNil(model.qualitySwitchMessage, "默认画质被平台回退时也不弹出提示")
        model.stop()
    }

    func testSwitchMessageExpiresAndReconnectDoesNotBringItBack() async throws {
        let model = makeModel(QualityProvider(returnsDefault: true, notice: "所选画质被平台回退"))
        model.qualityMessageDuration = .milliseconds(50)
        await model.load()
        await model.load(quality: 100)
        XCTAssertNotNil(model.qualitySwitchMessage)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(model.qualitySwitchMessage, "提示由模型到时清除，重新显示播放器（如进入全屏）不会再弹")
        await model.load()
        XCTAssertNil(model.qualitySwitchMessage, "重新连接不是切换画质")
        model.stop()
    }

    func testFailedQualitySelectionIncludesThePlatformReason() async {
        let model = makeModel(QualityProvider(returnsDefault: true, notice: "所选画质被平台回退"))
        await model.load()
        await model.load(quality: 100)
        XCTAssertEqual(model.selectedQuality, 0)
        XCTAssertEqual(model.qualitySwitchMessage, "高清暂不可用，当前为原画\n所选画质被平台回退")
        model.stop()
    }

    func testUnavailableManualQualityExplainsTheActualQuality() async {
        let provider = QualityProvider(returnsDefault: true)
        let model = makeModel(provider)
        await model.load()
        await model.load(quality: 100)
        XCTAssertEqual(model.selectedQuality, 0, "应保留平台确认的实际画质")
        XCTAssertEqual(model.qualitySwitchMessage, "高清暂不可用，当前为原画")
        XCTAssertNil(model.errorMessage)
        model.stop()
    }

    func testSwitchingShowsPendingLabelUntilThePlatformResponds() async {
        let provider = QualityProvider(holdsPreferred: true)
        let model = makeModel(provider)
        await model.load()
        XCTAssertEqual(model.qualityLabel, "原画")
        let switching = Task { await model.load(quality: 100) }
        while await !provider.isWaiting { await Task.yield() }
        XCTAssertEqual(model.qualityLabel, "切换中…")
        XCTAssertEqual(model.pendingQuality, 100)
        XCTAssertNotNil(model.playbackInfo, "切换期间保留画质菜单")
        XCTAssertNil(model.qualitySwitchMessage)
        await provider.release()
        await switching.value
        XCTAssertEqual(model.qualityLabel, "高清")
        XCTAssertEqual(model.qualitySwitchMessage, "已切换至高清")
        XCTAssertNil(model.pendingQuality)
        model.stop()
    }

    func testFailedSwitchDoesNotReportSuccessOrKeepThePendingLabel() async {
        let provider = QualityProvider(failsPreferred: true)
        let model = makeModel(provider)
        await model.load()
        await model.load(quality: 100)
        XCTAssertNil(model.qualitySwitchMessage)
        XCTAssertNil(model.pendingQuality)
        XCTAssertEqual(model.selectedQuality, 0)
        XCTAssertNotNil(model.errorMessage)
        model.stop()
    }

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
    private let returnsDefault: Bool
    private let notice: String?
    private var gate: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { gate != nil }

    init(failsPreferred: Bool = false, holdsPreferred: Bool = false, returnsDefault: Bool = false, notice: String? = nil) {
        self.failsPreferred = failsPreferred
        self.holdsPreferred = holdsPreferred
        self.returnsDefault = returnsDefault
        self.notice = notice
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
        return PlaybackInfo(lines: [], qualities: [StreamQuality(id: 0, name: "原画"), StreamQuality(id: 100, name: "高清")], currentQuality: returnsDefault ? 0 : (quality ?? 0), headers: [:], qualityNotice: notice)
    }
}
