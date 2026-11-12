import Foundation
import Testing
@testable import JLiveCore

struct NativePlatformTests {
    @Test func huyaSignsMobileHLSAndFiltersHDR() throws {
        let data = try json(#"{"roomInfo":{"tLiveInfo":{"tLiveStreamInfo":{"vStreamInfo":{"value":[{"sHlsUrl":"http://cdn.huya.com/src","sStreamName":"stream","sHlsAntiCode":"fm=cHJlZml4XyQwXyQxXyQyXyQz&wsTime=abc&ctype=tars_mobile&t=103&fs=bgct"}]},"vBitRateInfo":{"value":[{"iBitRate":0,"sDisplayName":"原画"},{"iBitRate":2000,"sDisplayName":"超清"},{"iBitRate":20100,"sDisplayName":"4K HDR"}]}}}}}"#)
        let info = try HuyaProvider.parsePlayback(data, quality: 2000, timestamp: 1000, uid: 1234)
        #expect(info.qualities.map(\.id) == [0, 2000])
        #expect(info.currentQuality == 2000)
        let url = try #require(info.lines.first?.url)
        #expect(url.scheme == "https")
        #expect(url.path == "/src/stream.m3u8")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let params = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        #expect(params["ratio"] == "2000")
        #expect(params["seqid"] == "2234")
        #expect(params["wsSecret"] == md5("prefix_1234_stream_\(md5("2234|tars_mobile|103"))_abc"))
        #expect(throws: LiveError.self) { try HuyaProvider.parsePlayback(try json("{}"), quality: nil) }
    }

    @Test func douyuRejectsFLVAndMapsMobileHLS() throws {
        let payload = try json(#"{"code":0,"data":{"url":"https://cdn.example.com/live.m3u8?x=1&amp;y=2","rate":2,"multirates":[{"rate":0,"name":"原画"},{"rate":2,"name":"高清"}]}}"#)
        let info = try DouyuProvider.parsePlayback(payload, quality: 2, headers: [:])
        #expect(info.lines.first?.url.absoluteString == "https://cdn.example.com/live.m3u8?x=1&y=2")
        #expect(info.currentQuality == 2)
        #expect(info.qualities.map(\.name) == ["原画", "高清"])
        #expect(throws: LiveError.self) { try DouyuProvider.parsePlayback(try json(#"{"code":0,"data":{"url":"https://cdn.example.com/live.flv"}}"#), quality: nil, headers: [:]) }
        #expect(throws: LiveError.self) { try DouyuProvider.parsePlayback(try json(#"{"code":401,"msg":"登录失效"}"#), quality: nil, headers: [:]) }
    }

    @Test func douyuPacketLengthsUseUTF8BytesAndDecodeEscapesAndBatches() {
        let first = DouyuChatCodec.packet("type@=loginres/")
        let chat = DouyuChatCodec.packet("type@=chatmsg/dms@=1/nn@=小明/txt@=你好@S世界@A/col@=2/")
        #expect(Int(chat[0]) == chat.count - 4)
        #expect(DouyuChatCodec.decode(first + chat) == [
            .connected, .message(LiveChatMessage(kind: .chat, userName: "小明", text: "你好/世界@", color: 0x1E87F0))
        ])
        #expect(DouyuChatCodec.decode(chat.dropLast()).isEmpty)
        #expect(DouyuChatCodec.decode(DouyuChatCodec.packet("type@=chatmsg/txt@=隐藏消息/")).isEmpty)
    }

    @Test func huyaTarsHandlesLargeIDsNestedChatAndMalformedFrames() throws {
        let handshake = HuyaChatCodec.handshake(uid: 6_123_456_789, top: 12, sub: 34)
        var reader = TarsReader(data: handshake)
        let command = try reader.fields()
        var bodyReader = TarsReader(data: try #require(command[1]?.bytes))
        let body = try bodyReader.fields()
        #expect(body[0]?.int == 6_123_456_789)
        #expect(body[4]?.int == 12)
        #expect(body[5]?.int == 34)
        // Recorded wire layout: nested sender, content tag 3, bullet formatting tag 6.
        var message = TarsWriter()
        message.head(10, tag: 0); message.string("主播", tag: 2); message.head(11, tag: 0)
        message.string("欢迎", tag: 3)
        message.head(10, tag: 6); message.integer(0xff8800, tag: 0); message.head(11, tag: 0)
        var push = TarsWriter()
        push.integer(1400, tag: 1); push.bytes(message.data, tag: 2)
        var packet = TarsWriter()
        packet.integer(7, tag: 0); packet.bytes(push.data, tag: 1)
        #expect(try HuyaChatCodec.decode(packet.data) == [.message(LiveChatMessage(kind: .chat, userName: "主播", text: "欢迎", color: 0xff8800))])
        #expect(throws: LiveError.self) { try HuyaChatCodec.decode(packet.data.dropLast(3)) }
    }

    @Test func isolatedSignerHandlesPlatformFunctionAndErrors() throws {
        let function = "function ub98484234(rid, did, time) { return 'rid=' + rid + '&sign=' + CryptoJS.MD5(rid + time).toString(); }"
        #expect(try DouyuSigner.sign(function, roomID: "42", timestamp: 100) == "rid=42&sign=\(md5("42100"))")
        #expect(throws: LiveError.self) { try DouyuSigner.sign("invalid", roomID: "42") }
    }

    @Test func sendingChatEncodesCSRFAndSpecialCharactersWithoutNetwork() async throws {
        let client = SendingClient()
        let provider = BilibiliProvider(client: client)
        await provider.setCredentials(BilibiliCredentials(cookie: "SESSDATA=private;", csrf: "csrf-token", uid: 123))
        try await provider.sendChat(roomID: "545068", text: "A+B & 你好")
        let request = await client.sent
        #expect(request?.body.contains("msg=A%2BB%20%26%20%E4%BD%A0%E5%A5%BD") == true)
        #expect(request?.body.contains("csrf=csrf-token") == true)
        #expect(request?.body.contains("roomid=545068") == true)
        #expect(request?.cookie.contains("SESSDATA=private;") == true)
        await provider.setCredentials(nil)
        await #expect(throws: LiveError.self) { try await provider.sendChat(roomID: "545068", text: "未登录") }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JLIVE_LIVE_TESTS"] == "1"), .timeLimit(.minutes(1)))
    func liveHLSAndChat() async throws {
        let client = HTTPClient()
        let providers: [(any LiveProvider, String)] = [(HuyaProvider(client: client), "998"), (DouyuProvider(client: client), "36252")]
        for (provider, id) in providers {
            let room = try await provider.detail(room: LiveRoom(platform: provider.platform, roomID: id, title: "", streamer: ""))
            let info = try await provider.playback(roomID: room.roomID, quality: nil)
            let url = try #require(info.lines.first?.url)
            let playlist = try await client.text(url, headers: info.headers)
            #expect(playlist.hasPrefix("#EXTM3U"))
            print("验证 HLS：\(provider.platform.name)")
            let endpoint = try await provider.chat(roomID: room.roomID)
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await event in LiveChatClient().events(endpoint) {
                        if event == .connected { print("验证弹幕入房：\(provider.platform.name)"); return }
                    }
                    throw LiveError.invalidResponse
                }
                group.addTask { try await Task.sleep(for: .seconds(20)); throw LiveError.platform("实时弹幕验证超时") }
                defer { group.cancelAll() }
                try await group.next()
            }
        }
    }

    private func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
}

private actor SendingClient: HTTPRequesting {
    var sent: (body: String, cookie: String)?
    func get(_ url: URL, headers: [String: String]) async throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(#"{"data":{"b_3":"buvid","b_4":"buvid4"}}"#.utf8))
    }
    func post(_ url: URL, body: String, headers: [String: String]) async throws -> JSONValue {
        sent = (body, headers["Cookie"] ?? "")
        return try JSONDecoder().decode(JSONValue.self, from: Data(#"{"code":0}"#.utf8))
    }
}
