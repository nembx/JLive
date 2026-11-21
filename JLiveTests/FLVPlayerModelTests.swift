import XCTest
import JLiveCore
@testable import JLive

@MainActor
final class FLVPlayerModelTests: XCTestCase {
    func testFLVQualityChangeLoadsTheNewStreamAndResumesPlayback() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "landscape", withExtension: "flv"))
        let room = LiveRoom(platform: .douyu, roomID: "42", title: "FLV", streamer: "测试", isLive: true)
        let model = PlayerModel(room: room, service: LiveService(providers: [FLVModelProvider(url: url)]))
        defer { model.stop() }
        await model.load()
        try await waitForPlayback(model)
        let started = Date()
        await model.load(quality: 400)
        XCTAssertEqual(model.selectedQuality, 400)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "停止旧流和加载新流不应阻塞切换")
        XCTAssertNil(model.errorMessage)
        try await waitForPlayback(model)
        XCTAssertEqual(model.qualityLabel, "蓝光")
    }

    private func waitForPlayback(_ model: PlayerModel) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !model.isPlaying, Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(model.isPlaying)
    }
}

private struct FLVModelProvider: LiveProvider {
    let platform = LivePlatform.douyu
    let url: URL
    func recommendations(page: Int) async throws -> RoomPage { RoomPage(rooms: [], hasMore: false) }
    func search(keyword: String, page: Int) async throws -> RoomPage { RoomPage(rooms: [], hasMore: false) }
    func playback(roomID: String, quality: Int?) async throws -> PlaybackInfo {
        PlaybackInfo(lines: [StreamLine(url: url)], qualities: [StreamQuality(id: 250, name: "超清"), StreamQuality(id: 400, name: "蓝光")], currentQuality: quality ?? 250, headers: [:])
    }
}
