import XCTest
import JLiveCore
@testable import JLive

@MainActor
final class ChatModelTests: XCTestCase {
    func testConnectionFailureLetsOnscreenMessagesFinish() async throws {
        let suite = "jlive-danmaku-disconnect-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let socket = DanmakuSocket()
        let chat = ChatModel(service: LiveService(providers: [DanmakuProvider()]),
                             client: LiveChatClient(connector: DanmakuConnector(socket: socket), maxConsecutiveFailures: 1),
                             defaults: defaults)
        defer { chat.stop() }
        chat.viewport = CGSize(width: 900, height: 500)
        chat.start(room: LiveRoom(platform: .bilibili, roomID: "1", title: "直播", streamer: "主播"))
        await socket.deliver(Data("弹幕走完全程".utf8))
        try await waitForEntries(1, in: chat)
        let visible = chat.floating
        XCTAssertEqual(visible.count, 1)
        await socket.disconnect()
        let deadline = ContinuousClock.now + .seconds(2)
        while chat.status == .connected || chat.status == .connecting, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .failed = chat.status else { return XCTFail("连接失败应更新状态") }
        XCTAssertEqual(chat.floating, visible, "连接中断不能让正在移动的弹幕突然消失")
        chat.expire(visible[0].id)
        XCTAssertTrue(chat.floating.isEmpty)
    }

    func testBusyChatKeepsEveryOnscreenMessageUntilItFinishes() async throws {
        var date = Date(timeIntervalSince1970: 0)
        let suite = "jlive-danmaku-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let chat = ChatModel(service: LiveService(providers: []), defaults: defaults, now: { date })
        defer { chat.stop() }
        chat.viewport = CGSize(width: 900, height: 1000)
        chat.area = 1

        send(1...12, to: chat)
        try await waitForEntries(12, in: chat)
        let first = chat.floating
        XCTAssertEqual(first.count, 12)

        // Previous messages have entered the screen and freed their lanes, but are still travelling.
        date += 1
        send(13...24, to: chat)
        try await waitForEntries(24, in: chat)
        XCTAssertEqual(Array(chat.floating.prefix(12)), first, "新弹幕不能删除仍在画面中移动的旧弹幕")
        XCTAssertEqual(chat.floating.count, 22, "达到显示上限后跳过新弹幕")

        let remaining = chat.floating.filter { $0.id != first[0].id }
        chat.expire(first[0].id)
        XCTAssertEqual(chat.floating, remaining, "完成回调只删除已经走完的那一条")
        date += 1
        send(25...25, to: chat)
        try await waitForEntries(25, in: chat)
        XCTAssertEqual(Array(chat.floating.dropLast()), remaining)
        XCTAssertEqual(chat.floating.last?.id, 25, "旧弹幕走完后空位可接收新弹幕")
    }

    private func send(_ ids: ClosedRange<Int>, to chat: ChatModel) {
        for id in ids {
            chat.handle(.message(LiveChatMessage(kind: .chat, userName: "观众", text: "弹幕\(id)")))
        }
    }

    private func waitForEntries(_ count: Int, in chat: ChatModel) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while chat.entries.count < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(chat.entries.count, count)
    }
}

private struct DanmakuProvider: LiveProvider {
    let platform = LivePlatform.bilibili
    func recommendations(page: Int) async throws -> RoomPage { RoomPage(rooms: [], hasMore: false) }
    func search(keyword: String, page: Int) async throws -> RoomPage { RoomPage(rooms: [], hasMore: false) }
    func chat(roomID: String) async throws -> LiveChatEndpoint {
        LiveChatEndpoint(urls: [URL(string: "wss://chat.example.com")!], handshake: Data(), heartbeat: Data()) { data in
            [.connected, .message(LiveChatMessage(kind: .chat, userName: "观众", text: String(decoding: data, as: UTF8.self)))]
        }
    }
}

private struct DanmakuConnector: LiveChatConnecting {
    let socket: DanmakuSocket
    func connect(to url: URL, headers: [String: String]) async throws -> any LiveChatSocket { socket }
}

private actor DanmakuSocket: LiveChatSocket {
    private var frames: [Data] = []
    private var disconnected = false
    private var waiting: CheckedContinuation<Data, any Error>?
    func send(_ data: Data) async throws {}
    func receive() async throws -> Data {
        if !frames.isEmpty { return frames.removeFirst() }
        if disconnected { throw URLError(.networkConnectionLost) }
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }
    func deliver(_ frame: Data) {
        if let waiting { self.waiting = nil; waiting.resume(returning: frame) }
        else { frames.append(frame) }
    }
    func disconnect() {
        disconnected = true
        waiting?.resume(throwing: URLError(.networkConnectionLost))
        waiting = nil
    }
    nonisolated func close() { Task { await disconnect() } }
}
