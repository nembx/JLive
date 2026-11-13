import Foundation
import Testing
@testable import JLiveCore

struct DouyinTests {
    @Test func recommendationsDeduplicateWebIDsAndMapRoomState() throws {
        let page = try DouyinProvider.parseRecommendations(json(#"{"data":[{"web_rid":"123","room":{"title":"直播","status":2,"owner":{"nickname":"主播","avatar_thumb":{"url_list":["//img.example.com/a.jpg"]}},"room_view_stats":{"display_value":"456"}}},{"web_rid":"123","room":{}},{"web_rid":"invalid","room":{}}]}"#))
        #expect(page.rooms.count == 1)
        #expect(page.rooms.first?.roomID == "123")
        #expect(page.rooms.first?.streamer == "主播")
        #expect(page.rooms.first?.viewerCount == 456)
        #expect(page.rooms.first?.avatarURL?.scheme == "https")
        #expect(page.rooms.first?.isLive == true)
        #expect(!page.hasMore)
    }

    @Test func flightRoomStateHandlesSplitStringsEscapesAndEmptyInitialState() throws {
        let state = #"{"roomInfo":null,"other":{"room":{}}}{"roomInfo":{"room":{"id_str":"7376429659866598196","title":"你好 {\"JLive\"}"},"anchor":{"nickname":"主播"}}}"#
        let split = state.index(state.startIndex, offsetBy: 75)
        let html = try flight(String(state[..<split])) + flight(String(state[split...]))
        let room = try DouyinProvider.parseRoomHTML(html)
        #expect(room["id_str"].string == "7376429659866598196")
        #expect(room["title"].string == "你好 {\"JLive\"}")
        #expect(room["owner"]["nickname"].string == "主播")
        #expect(throws: LiveError.self) { try DouyinProvider.parseRoomHTML("<html>没有房间</html>") }
        #expect(balancedObject(after: "\"roomInfo\":", in: #"{"roomInfo":null,"other":{}}"#) == nil)
    }

    @Test func onlyAdvertisesQualitiesWithPlayableHLSAndSelectsBackupLines() throws {
        let data = try json(#"{"hls_pull_url":"https://cdn.example.com/default.m3u8","hls_pull_url_map":{"hd":"https://cdn.example.com/hd.m3u8?x=1&amp;y=2","flv":"https://cdn.example.com/live.flv"},"live_core_sdk_data":{"pull_data":{"options":{"qualities":[{"level":4,"sdk_key":"origin","name":"原画"},{"level":2,"sdk_key":"hd","name":"高清"},{"level":1,"sdk_key":"flv","name":"流畅"}]},"stream_data":"{\"data\":{\"hd\":{\"main\":{\"hls\":\"https://cdn.example.com/hd.m3u8?x=1&y=2\"},\"backup\":{\"hls\":\"https://backup.example.com/hd.m3u8\"}}}}"}}}"#)
        let info = try DouyinProvider.parsePlayback(data, quality: 4, headers: [:])
        #expect(info.qualities.map(\.name) == ["高清"])
        #expect(info.currentQuality == 2)
        #expect(info.lines.count == 2)
        #expect(info.lines.first?.url.absoluteString == "https://cdn.example.com/hd.m3u8?x=1&y=2")
    }

    @Test func fallbackMapRanksOriginalAboveSmoothAndUnknownKeys() throws {
        let data = try json(#"{"hls_pull_url_map":{"SD2":"https://a.example.com/sd.m3u8","ORIGIN":"https://a.example.com/origin.m3u8","HD1":"https://a.example.com/hd.m3u8","other":"https://a.example.com/other.m3u8"}}"#)
        let info = try DouyinProvider.parsePlayback(data, quality: nil, headers: [:])
        #expect(info.qualities.map(\.name) == ["原画", "高清", "流畅", "other"])
        #expect(info.lines.first?.url.path == "/origin.m3u8")
        let low = try DouyinProvider.parsePlayback(data, quality: info.qualities[2].id, headers: [:])
        #expect(low.lines.first?.url.path == "/sd.m3u8")
        #expect(throws: LiveError.self) { try DouyinProvider.parsePlayback(json("{}"), quality: nil, headers: [:]) }
    }

    @Test func upgradesHTTPMediaToHTTPSAndDeduplicatesEquivalentURLs() throws {
        let data = try json(#"{"live_core_sdk_data":{"pull_data":{"options":{"qualities":[{"level":2,"sdk_key":"hd","name":"高清"}]},"stream_data":"{\"data\":{\"hd\":{\"main\":{\"hls\":\"http://cdn.example.com:80/live.m3u8\"},\"backup\":{\"hls\":\"https://cdn.example.com/live.m3u8\"}}}}"}}}"#)
        let info = try DouyinProvider.parsePlayback(data, quality: nil, headers: [:])
        #expect(info.lines.map(\.url.absoluteString) == ["https://cdn.example.com/live.m3u8"])
    }

    @Test func bundledSignersExecuteAndPreserveQuery() throws {
        let url = try DouyinSigner.signedURL(URL(string: "https://live.douyin.com/api?web_rid=123&msToken=old&a_bogus=old")!)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "web_rid" }?.value == "123")
        #expect(items.filter { $0.name == "msToken" }.count == 1)
        #expect(items.first { $0.name == "msToken" }?.value?.count == 107)
        #expect(items.filter { $0.name == "a_bogus" }.count == 1)
        #expect((items.first { $0.name == "a_bogus" }?.value?.count ?? 0) > 20)
        let signature = try DouyinSigner.chatSignature(roomID: "7376429659866598196", guestID: "123456789012")
        #expect(signature.count > 10)
        #expect(!signature.contains("="))
    }

    @Test func gzipChatBatchAcknowledgesExactUInt64LogIDAndInternalExtension() throws {
        // Independent Python protobuf encoder + gzip.compress; includes an unknown gift message.
        let fixture = try #require(Data(base64Encoded: "EP///////////wEyAnBiOgNtc2dCjwEfiwgAAAAAAAL/47LmEgpPTUpOLC5xzkgs8U0tLk5MTxVSFRLm2DKtZcbMb1PXp0mxv1je9GTPdEcpvid7Fzxduleh2ssnsyy1lssGq2Y1bJqdpPifr1nzZFfPs7kLn+7Z+XTnVC5xuG73zDS4bsb/WoLJpUXF+UU1T3asfTatvSYxOduDEQA4Hc2BqQAAAA=="))
        let result = try DouyinChatCodec.process((Data([1, 2]) + fixture).dropFirst(2))
        #expect(result.events == [
            .connected,
            .message(LiveChatMessage(kind: .chat, userName: "观众A", text: "你好 {JLive}")),
            .message(LiveChatMessage(kind: .chat, userName: "观众B", text: "第二条弹幕"))
        ])
        let ack = try ProtoFields(#require(result.replies.first))
        #expect(ack.integer(2) == UInt64.max)
        #expect(ack.string(7) == "ack")
        #expect(ack.string(8) == "cursor|中文|ack")
        #expect(try DouyinChatCodec.process(DouyinChatCodec.heartbeat).events.isEmpty)
        var corruptCRC = fixture
        corruptCRC[corruptCRC.endIndex - 8] ^= 0xff
        #expect(throws: LiveError.self) { try DouyinChatCodec.process(corruptCRC) }
        #expect(throws: LiveError.self) { try DouyinChatCodec.process(fixture.dropLast()) }
    }

    @Test func rejectsTruncatedOverlongAndCorruptFrames() throws {
        for bytes: [UInt8] in [[0], [0x12, 0xff, 0xff], [0x08] + Array(repeating: 0xff, count: 10), [0x09, 1], [0x0d, 1]] {
            #expect(throws: LiveError.self) { try DouyinChatCodec.process(Data(bytes)) }
        }
        let corrupt = DouyinChatCodec.packet(type: "msg", payload: Data([0x1f, 0x8b, 0, 0]))
        #expect(throws: LiveError.self) { try DouyinChatCodec.process(corrupt) }
        #expect(throws: LiveError.self) { try DouyinChatCodec.process(Data(repeating: 0, count: DouyinChatCodec.maxPayloadSize + 1)) }
        // Unknown fixed-size fields remain compatible with future protocol additions.
        let fields = try ProtoFields(Data([0x09] + Array(repeating: 0, count: 8) + [0x10, 42]))
        #expect(fields.integer(2) == 42)
    }

    @Test func resolvesTemporaryShareIDToStableWebRoomAndUsesInternalIDForChat() async throws {
        let client = DouyinRoutingClient()
        let provider = DouyinProvider(client: client)
        let detail = try await provider.detail(room: LiveRoom(platform: .douyin, roomID: "7376429659866598196", title: "", streamer: ""))
        #expect(detail.roomID == "123456")
        let info = try await provider.playback(roomID: detail.roomID, quality: nil)
        #expect(info.lines.first?.url.path == "/live.m3u8")
        let endpoint = try await provider.chat(roomID: detail.roomID)
        #expect(endpoint.headers["Cookie"] == "ttwid=fresh-guest")
        let items = URLComponents(url: endpoint.urls[0], resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "room_id" }?.value == "7376429659866598196")
        #expect(endpoint.urls.count == 2)
        #expect(endpoint.heartbeatInterval == 10)
        await #expect(throws: LiveError.self) { try await provider.playback(roomID: "invalid", quality: nil) }
    }

    @Test func restrictedRoomAPIUsesFlightStateAndKeepsUnavailableRoomsOffline() async throws {
        let roomJSON = #"{"roomInfo":{"room":{"id_str":"7376429659866598196","status":4,"owner":{"nickname":"主播"}}}}"#
        let client = DouyinHTMLClient(html: try flight(roomJSON))
        let provider = DouyinProvider(client: client)
        let detail = try await provider.detail(room: LiveRoom(platform: .douyin, roomID: "123456", title: "", streamer: ""))
        #expect(detail.streamer == "主播")
        #expect(detail.isLive == false)
        await #expect(throws: LiveError.self) { try await provider.playback(roomID: detail.roomID, quality: nil) }
        await #expect(throws: LiveError.self) { try await provider.chat(roomID: detail.roomID) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JLIVE_DOUYIN_LIVE_TESTS"] == "1"), .timeLimit(.minutes(2)))
    func liveDouyinDiscoveryPlaybackAndChat() async throws {
        let client = HTTPClient()
        let provider = DouyinProvider(client: client)
        let page = try await provider.recommendations(page: 1)
        let room = try #require(page.rooms.first { $0.isLive == true })
        print("抖音推荐：\(page.rooms.count)，房间 \(room.roomID)")
        let detail = try await provider.detail(room: room)
        let info = try await provider.playback(roomID: detail.roomID, quality: nil)
        let playlist = try await client.text(#require(info.lines.first?.url), headers: info.headers)
        #expect(playlist.hasPrefix("#EXTM3U"))
        print("抖音 HLS 验证通过：\(info.qualities.map(\.name).joined(separator: "、"))")
        let endpoint = try await provider.chat(roomID: detail.roomID)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await event in LiveChatClient(maxConsecutiveFailures: 1).events(endpoint) {
                    if event == .connected { print("抖音服务端推送已收到") }
                    if case .message = event { print("抖音弹幕接收验证通过"); return }
                }
                throw LiveError.invalidResponse
            }
            group.addTask { try await Task.sleep(for: .seconds(25)); throw LiveError.platform("抖音弹幕验证超时") }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private func json(_ string: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(string.utf8)) }
    private func flight(_ string: String) throws -> String {
        let value = String(decoding: try JSONEncoder().encode(string), as: UTF8.self)
        return "<script>self.__next_f.push([1,\(value)])</script>"
    }
}

private actor DouyinRoutingClient: HTTPRequesting {
    func get(_ url: URL, headers: [String: String]) async throws -> JSONValue {
        let source: String
        if url.path.contains("reflow") { source = #"{"data":{"room":{"owner":{"web_rid":"123456"}}}}"# }
        else { source = #"{"status_code":0,"data":{"data":[{"id_str":"7376429659866598196","status":2,"owner":{"web_rid":"123456","nickname":"主播"},"stream_url":{"hls_pull_url":"https://cdn.example.com/live.m3u8"}}]}}"# }
        return try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8))
    }
    func text(_ url: URL, headers: [String: String]) async throws -> String { "<html></html>" }
    func cookies(for url: URL) async -> String { "ttwid=fresh-guest" }
}

private struct DouyinHTMLClient: HTTPRequesting {
    let html: String
    func get(_ url: URL, headers: [String: String]) async throws -> JSONValue { throw LiveError.http(403) }
    func text(_ url: URL, headers: [String: String]) async throws -> String { html }
}
