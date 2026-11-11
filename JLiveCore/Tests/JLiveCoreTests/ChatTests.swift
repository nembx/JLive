import Foundation
import Testing
@testable import JLiveCore

struct ChatTests {
    // MARK: Bilibili wire format

    @Test func handshakeAsksForZlibFramesAndCarriesTheRoomToken() throws {
        let packet = try BilibiliChatCodec.handshake(roomID: 5050, token: "tok", buvid: "buvid-1")
        #expect(Array(packet.prefix(16)) == [0, 0, 0, UInt8(packet.count), 0, 16, 0, 1, 0, 0, 0, 7, 0, 0, 0, 1])
        let body = try JSONDecoder().decode(JSONValue.self, from: packet.dropFirst(16))
        #expect(body["protover"].int == 2)
        #expect(body["roomid"].int == 5050)
        #expect(body["key"].string == "tok")
        #expect(body["buvid"].string == "buvid-1")
        #expect(body["uid"].int == 0)
    }

    @Test func decodesChatWithCommandSuffixAndColour() throws {
        let frame = packet(5, #"{"cmd":"DANMU_MSG:4:0:2:2:2:0","info":[[0,1,25,16776960,1700000000],"你好 JLive",[42,"观众A"]]}"#)
        #expect(try BilibiliChatCodec.decode(frame) == [
            .message(LiveChatMessage(kind: .chat, userName: "观众A", text: "你好 JLive", color: 0xFFFF00))
        ])
    }

    @Test func decodesCompressedBatchOfPackets() throws {
        let gift = #"{"cmd":"SEND_GIFT","data":{"uname":"观众B","action":"投喂","giftName":"辣条","num":3}}"#
        let inner = packet(5, chatJSON("一")) + packet(5, gift)
        let frame = BilibiliChatCodec.packet(operation: 5, version: 2, body: zlibStored(inner))
        #expect(try BilibiliChatCodec.decode(frame) == [
            chat("一"),
            .message(LiveChatMessage(kind: .gift, userName: "观众B", text: "投喂 辣条 ×3"))
        ])
    }

    @Test func inflatesAStreamProducedByZlib() throws {
        // Python `zlib.compress(packets, 9)`: eight chat packets in one Huffman-coded block.
        let compressed = try #require(Data(base64Encoded: "eNpjYGBIZRBgAAFWIGasVkrOTVGyUnJx9PMNjfcNdlfSUcrMS8tXsoqONtAx1DEy1TE0Mzc0NLMwiNVRerpn59OdU5/2dT/fs/LZ1u4X66cqGCrpRBsaGOoovVje9GTPdEOl2NhaBmpbYgS2xAhmiRFNLDEGW2IMs8SYJpaYgC0xgVliQhNLTMGWmMIsMaWJJWZgS8xglpjRxBJzsCXmMEvMaWKJBdgSC5glFiBLAEAKCUw="))
        let events = try BilibiliChatCodec.decode(BilibiliChatCodec.packet(operation: 5, version: 2, body: compressed))
        #expect(events.count == 8)
        #expect(events.first == .message(LiveChatMessage(kind: .chat, userName: "观众1", text: "弹幕压缩测试 1", color: 0xFF0000)))
        #expect(events.last == .message(LiveChatMessage(kind: .chat, userName: "观众8", text: "弹幕压缩测试 8", color: 0xFF0000)))
    }

    @Test func decodesEveryPacketInAFrameAndSkipsHeartbeatReplies() throws {
        let frame = packet(8, #"{"code":0}"#)
            + BilibiliChatCodec.packet(operation: 3, body: Data([0, 0, 0, 1]))
            + packet(5, chatJSON("二"))
        #expect(try BilibiliChatCodec.decode(frame) == [.connected, chat("二")])
        // Socket frames can arrive as slices that do not start at index zero.
        #expect(try BilibiliChatCodec.decode((Data([9, 9]) + frame).dropFirst(2)) == [.connected, chat("二")])
    }

    @Test func rejectedHandshakeIsAnError() {
        #expect(throws: LiveError.self) { try BilibiliChatCodec.decode(packet(8, #"{"code":-101}"#)) }
    }

    @Test func mapsSuperChatPriceAndColour() throws {
        // The colour value contains `"#`, so the literal needs a wider delimiter.
        let frame = packet(5, ##"{"cmd":"SUPER_CHAT_MESSAGE","data":{"message":"加油","price":30,"background_bottom_color":"#2A60B2","user_info":{"uname":"老板"}}}"##)
        #expect(try BilibiliChatCodec.decode(frame) == [
            .message(LiveChatMessage(kind: .superChat(price: 30), userName: "老板", text: "加油", color: 0x2A60B2))
        ])
    }

    @Test func ignoresTruncatedMalformedAndUnsupportedPackets() throws {
        let valid = packet(5, chatJSON("三"))
        #expect(try BilibiliChatCodec.decode(valid.dropLast(3)).isEmpty)
        #expect(try BilibiliChatCodec.decode(Data([1, 2, 3])).isEmpty)
        #expect(try BilibiliChatCodec.decode(packet(5, "not json")).isEmpty)
        #expect(try BilibiliChatCodec.decode(packet(5, #"{"cmd":"INTERACT_WORD","data":{"uname":"路人"}}"#)).isEmpty)
        #expect(try BilibiliChatCodec.decode(packet(5, #"{"cmd":"DANMU_MSG","info":[[0,1,25,0],"",[1,"空"]]}"#)).isEmpty)
        // Brotli frames are never requested; a corrupt zlib body must not take the batch down.
        #expect(try BilibiliChatCodec.decode(BilibiliChatCodec.packet(operation: 5, version: 3, body: Data([1, 2]))).isEmpty)
        let corrupt = BilibiliChatCodec.packet(operation: 5, version: 2, body: Data([0x78, 0x01, 0xFF, 0xFF]))
        #expect(try BilibiliChatCodec.decode(corrupt + valid) == [chat("三")])
        // A header shorter than the fixed sixteen bytes cannot be trusted.
        var shortHeader = valid
        shortHeader[5] = 8
        #expect(try BilibiliChatCodec.decode(shortHeader).isEmpty)
    }

    // MARK: Bilibili endpoint

    @Test func chatEndpointUsesSecureHostsAndFallsBackToTheDefaultHost() throws {
        let hosts = try json(#"[{"host":"a.chat.bilibili.com","wss_port":2245},{"host":"b.chat.bilibili.com"},{"host":""}]"#)
        let endpoint = try BilibiliProvider.chatEndpoint(roomID: 5050, token: "tok", hosts: hosts, buvid: "id")
        #expect(endpoint.urls.map(\.absoluteString) == [
            "wss://a.chat.bilibili.com:2245/sub", "wss://b.chat.bilibili.com:443/sub"
        ])
        let fallback = try BilibiliProvider.chatEndpoint(roomID: 5050, token: "tok", hosts: .null, buvid: "id")
        #expect(fallback.urls.map(\.host) == ["broadcastlv.chat.bilibili.com"])
        #expect(throws: LiveError.self) {
            try BilibiliProvider.chatEndpoint(roomID: 5050, token: "", hosts: .null, buvid: "id")
        }
    }

    @Test func chatJoinsTheCanonicalRoomRatherThanTheShortAlias() async throws {
        let key = String(repeating: "a", count: 32)
        let client = RoutingClient(routes: [
            "/finger/spi": try json(#"{"data":{"b_3":"B3","b_4":"B4"}}"#),
            "/web-interface/nav": try json(#"{"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/\#(key).png","sub_url":"https://i0.hdslb.com/bfs/wbi/\#(key).png"}}}"#),
            "/Room/get_info": try json(#"{"code":0,"data":{"room_id":21452505}}"#),
            "/getDanmuInfo": try json(#"{"code":0,"data":{"token":"tok","host_list":[{"host":"x.chat.bilibili.com","wss_port":443}]}}"#)
        ])
        let endpoint = try await BilibiliProvider(client: client).chat(roomID: "5050")
        let handshake = try JSONDecoder().decode(JSONValue.self, from: endpoint.handshake.dropFirst(16))
        #expect(handshake["roomid"].int == 21_452_505)
        #expect(handshake["buvid"].string == "B3")
        #expect(endpoint.urls.map(\.absoluteString) == ["wss://x.chat.bilibili.com:443/sub"])
        let tokenRequest = try #require(client.requests.last)
        let query = URLComponents(url: tokenRequest, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first { $0.name == "id" }?.value == "21452505")
        #expect(query.contains { $0.name == "w_rid" })
    }

    // MARK: Connection lifecycle

    @Test func clientSendsTheHandshakeThenYieldsEventsAndClosesWhenAbandoned() async throws {
        let socket = FakeSocket(frames: [.success(Data("ready".utf8)), .success(Data("hi".utf8))])
        let client = LiveChatClient(connector: FakeConnector([.success(socket)]), retryDelay: .milliseconds(1))
        var received: [LiveChatEvent] = []
        for try await event in client.events(endpoint()) {
            received.append(event)
            if received.count == 2 { break }
        }
        #expect(received == [.connected, chat("hi")])
        #expect(socket.sent.first == Data("hello".utf8))
        #expect(await eventually { socket.closed })
    }

    @Test func clientReconnectsOnTheNextHostAfterLosingTheConnection() async throws {
        let first = FakeSocket(frames: [.success(Data("ready".utf8)), .failure(URLError(.networkConnectionLost))])
        let second = FakeSocket(frames: [.success(Data("ready".utf8)), .success(Data("back".utf8))])
        let connector = FakeConnector([.success(first), .success(second)])
        let client = LiveChatClient(connector: connector, retryDelay: .milliseconds(1))
        var received: [LiveChatEvent] = []
        for try await event in client.events(endpoint(urls: ["wss://a.example.com/sub", "wss://b.example.com/sub"])) {
            received.append(event)
            if received.count == 4 { break }
        }
        #expect(received == [.connected, .reconnecting, .connected, chat("back")])
        #expect(connector.urls.map(\.host) == ["a.example.com", "b.example.com"])
        #expect(first.closed)
    }

    @Test func clientGivesUpAfterConsecutiveFailuresWithTheLastError() async {
        let connector = FakeConnector([])
        let client = LiveChatClient(connector: connector, retryDelay: .milliseconds(1), maxConsecutiveFailures: 3)
        var received: [LiveChatEvent] = []
        do {
            for try await event in client.events(endpoint()) { received.append(event) }
            Issue.record("A chat that cannot connect must end with an error")
        } catch {
            #expect(error is URLError)
        }
        #expect(received == [.reconnecting, .reconnecting])
        #expect(connector.urls.count == 3)
    }

    @Test func rejectedHandshakeEndsTheStreamWithThePlatformError() async {
        let socket = FakeSocket(frames: [.success(Data("reject".utf8))])
        let client = LiveChatClient(connector: FakeConnector([.success(socket)]), retryDelay: .milliseconds(1), maxConsecutiveFailures: 1)
        do {
            for try await _ in client.events(endpoint()) {}
            Issue.record("A rejected handshake must end with an error")
        } catch {
            #expect(error is LiveError)
        }
        #expect(socket.closed)
    }

    @Test func clientKeepsAnIdleConnectionAliveAndStopsWhenCancelled() async {
        let socket = FakeSocket(frames: [.success(Data("ready".utf8))])
        let client = LiveChatClient(connector: FakeConnector([.success(socket)]), retryDelay: .milliseconds(1))
        let stream = client.events(endpoint(heartbeat: 0.02))
        let consumer = Task { for try await _ in stream {} }
        #expect(await eventually { socket.sent.filter { $0 == Data("ping".utf8) }.count >= 2 })
        consumer.cancel()
        #expect(await eventually { socket.closed })
    }
}

// MARK: Fixtures

private func packet(_ operation: UInt32, _ json: String) -> Data {
    BilibiliChatCodec.packet(operation: operation, version: 0, body: Data(json.utf8))
}

private func chatJSON(_ text: String) -> String {
    #"{"cmd":"DANMU_MSG","info":[[0,1,25,0],"\#(text)",[1,"u"]]}"#
}

private func chat(_ text: String) -> LiveChatEvent {
    .message(LiveChatMessage(kind: .chat, userName: "u", text: text))
}

private func json(_ source: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8))
}

/// A zlib stream whose single DEFLATE block stores the payload uncompressed.
private func zlibStored(_ payload: Data) -> Data {
    let length = UInt16(payload.count)
    var data = Data([0x78, 0x01, 0x01])
    data.append(contentsOf: [UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8(~length >> 8)])
    data.append(payload)
    var a: UInt32 = 1, b: UInt32 = 0
    for byte in payload {
        a = (a + UInt32(byte)) % 65_521
        b = (b + a) % 65_521
    }
    let adler = b << 16 | a
    data.append(contentsOf: [UInt8(adler >> 24), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF), UInt8(adler & 0xFF)])
    return data
}

private func endpoint(urls: [String] = ["wss://a.example.com/sub"], heartbeat: TimeInterval = 60) -> LiveChatEndpoint {
    LiveChatEndpoint(
        urls: urls.map { URL(string: $0)! }, handshake: Data("hello".utf8), heartbeat: Data("ping".utf8),
        heartbeatInterval: heartbeat,
        decode: { frame in
            switch String(decoding: frame, as: UTF8.self) {
            case "ready": [.connected]
            case "reject": throw LiveError.platform("rejected")
            case let text: [chat(text)]
            }
        }
    )
}

private func eventually(_ condition: @Sendable () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// Plays back scripted frames, then behaves like an idle socket until it is closed.
private final class FakeSocket: LiveChatSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [Result<Data, any Error>]
    private var waiters: [CheckedContinuation<Data, any Error>] = []
    private var sentPackets: [Data] = []
    private var isClosed = false

    init(frames: [Result<Data, any Error>]) { self.frames = frames }

    var sent: [Data] { lock.withLock { sentPackets } }
    var closed: Bool { lock.withLock { isClosed } }

    func send(_ data: Data) async throws {
        try lock.withLock {
            if isClosed { throw URLError(.networkConnectionLost) }
            sentPackets.append(data)
        }
    }

    func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !frames.isEmpty {
                let next = frames.removeFirst()
                lock.unlock()
                continuation.resume(with: next)
            } else if isClosed {
                lock.unlock()
                continuation.resume(throwing: URLError(.networkConnectionLost))
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func close() {
        lock.lock()
        isClosed = true
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume(throwing: URLError(.networkConnectionLost)) }
    }
}

private final class FakeConnector: LiveChatConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var sockets: [Result<FakeSocket, any Error>]
    private var requested: [URL] = []

    init(_ sockets: [Result<FakeSocket, any Error>]) { self.sockets = sockets }

    var urls: [URL] { lock.withLock { requested } }

    func connect(to url: URL, headers: [String: String]) async throws -> any LiveChatSocket {
        let next: Result<FakeSocket, any Error> = lock.withLock {
            requested.append(url)
            return sockets.isEmpty ? .failure(URLError(.cannotConnectToHost)) : sockets.removeFirst()
        }
        return try next.get()
    }
}

private final class RoutingClient: HTTPRequesting, @unchecked Sendable {
    private let lock = NSLock()
    private let routes: [String: JSONValue]
    private var received: [URL] = []

    init(routes: [String: JSONValue]) { self.routes = routes }

    var requests: [URL] { lock.withLock { received } }

    func get(_ url: URL, headers: [String: String]) async throws -> JSONValue {
        lock.withLock { received.append(url) }
        guard let response = routes.first(where: { url.path.hasSuffix($0.key) })?.value else {
            throw LiveError.http(404)
        }
        return response
    }
}
