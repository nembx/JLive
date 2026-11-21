import Foundation
import Testing
@testable import JLiveCore

struct NativePlatformTests {
    @Test func douyuReadsTheRealMobileSettingsList() throws {
        // Captured mobile API shape: the list is settings, not multirates.
        let payload = try json(#"{"error":0,"data":{"url":"https://cdn.example.com/live/room_2000.m3u8","rate":3,"settings":[{"rate":0,"name":"原画1080P60","high_bit":0},{"rate":3,"name":"超清","high_bit":0},{"rate":2,"name":"高清","high_bit":0}]}}"#)
        let rates = try json(#"[{"rate":0,"name":"原画1080P60","bit":10137},{"rate":3,"name":"超清","bit":2000},{"rate":2,"name":"高清","bit":900}]"#).array
        let info = try DouyuProvider.parsePlayback(payload, quality: 3, headers: [:], rates: rates)
        #expect(info.qualities.map(\.name) == ["原画1080P60", "超清", "高清"])
        #expect(info.currentQuality == 3)
    }

    @Test func douyuUsesTheRenditionInsteadOfTheEchoedRate() throws {
        // Real response: rate 0 is echoed, but _2000 is the ultra tier, not original.
        let payload = try json(#"{"error":0,"data":{"url":"https://cdn.example.com/live/room_2000.m3u8?token=test","rate":0,"settings":[{"rate":0,"name":"原画"},{"rate":3,"name":"超清"},{"rate":2,"name":"高清"}]}}"#)
        let rates = try json(#"[{"rate":0,"name":"原画","bit":10000},{"rate":3,"name":"超清","bit":2000},{"rate":2,"name":"高清","bit":900}]"#).array
        let info = try DouyuProvider.parsePlayback(payload, quality: 0, headers: [:], rates: rates)
        #expect(info.currentQuality == 3)
        #expect(info.qualityNotice?.contains("平台回退") == true)
        let unknown = try DouyuProvider.parsePlayback(payload, quality: 0, headers: [:])
        #expect(unknown.currentQuality == -1, "缺少码率映射时不能假装原画已切换")
        #expect(unknown.qualities.last?.name == "平台默认")
        #expect(unknown.qualityNotice != nil)
        #expect(throws: LiveError.self) { try DouyuProvider.parsePlayback(try json(#"{"data":{"url":"https://cdn.example.com/live.m3u8"}}"#), quality: nil, headers: [:]) }
        #expect(throws: LiveError.self) { try DouyuProvider.parsePlayback(try json(#"{"error":5,"msg":"时间戳错误"}"#), quality: nil, headers: [:]) }
    }

    @Test func douyuFallsBackToTheCurrentMobileEndpointWithItsOwnSigner() async throws {
        let client = DouyuQualityClient()
        let provider = DouyuProvider(client: client)
        let initial = try await provider.playback(roomID: "42", quality: nil)
        #expect(initial.currentQuality == 3)
        let switched = try await provider.playback(roomID: "42", quality: 2)
        #expect(switched.currentQuality == 2)
        #expect(switched.lines.first?.url.path == "/live/room_900.m3u8")
        #expect(switched.qualityNotice == nil, "实际流已切到目标时，不能因为错误的回显编号再提示回退")
        let requests = await client.mobileBodies
        #expect(requests.count == 2)
        #expect(requests[0].contains("sign=mobile"))
        #expect(requests[0].contains("&ver=22011191&rid=42&rate=-1"))
        #expect(requests[1].contains("&rate=2"))
        #expect(throws: LiveError.self) { try DouyuProvider.mobileSigningScript("<script src='external.js'></script>") }
    }

    @Test func douyuUsesSimpleLiveDesktopRequestsForRealQualityChanges() async throws {
        let client = DouyuDesktopClient()
        let provider = DouyuProvider(client: client)
        let high = try await provider.playback(roomID: "42", quality: 2)
        let ultra = try await provider.playback(roomID: "42", quality: 3)
        #expect(high.currentQuality == 2)
        #expect(ultra.currentQuality == 3)
        #expect(high.lines.first?.url.path == "/live/room_900.flv")
        #expect(ultra.lines.first?.url.path == "/live/room_2000.flv")
        #expect(high.qualityNotice == nil && ultra.qualityNotice == nil)
        #expect(high.qualities.map(\.name) == ["原画", "超清", "高清"])
        let bodies = await client.qualityBodies
        #expect(bodies == ["sign=desktop&cdn=hw-h5&rate=2", "sign=desktop&cdn=hw-h5&rate=3"], "切换请求不能带画质发现接口的 ver/iar/ive 等参数")
    }

    @Test func douyuDesktopLabelAlsoMatchesTheRendition() throws {
        let payload = try json(#"{"error":0,"data":{"rtmp_url":"https://cdn.example.com/live","rtmp_live":"room_2000.flv","rate":0,"multirates":[{"rate":0,"name":"原画","bit":10000},{"rate":3,"name":"超清","bit":2000}]}}"#)
        let info = try DouyuProvider.parseDesktopPlayback(payload, quality: 0, headers: [:])
        #expect(info.currentQuality == 3)
        #expect(info.qualityNotice?.contains("平台回退") == true)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JLIVE_QUALITY_LIVE_TESTS"] == "1"), .timeLimit(.minutes(2)))
    func liveDouyuActuallySwitchesDesktopQuality() async throws {
        let provider = DouyuProvider(client: HTTPClient())
        let high = try await provider.playback(roomID: "36252", quality: 2)
        let ultra = try await provider.playback(roomID: "36252", quality: 3)
        #expect(high.currentQuality == 2)
        #expect(ultra.currentQuality == 3)
        #expect(high.lines.first?.url.path != ultra.lines.first?.url.path)
        for info in [high, ultra] {
            let url = try #require(info.lines.first?.url)
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            for (key, value) in info.headers { request.setValue(value, forHTTPHeaderField: key) }
            let (bytes, _) = try await session.bytes(for: request)
            var prefix: [UInt8] = []
            for try await byte in bytes { prefix.append(byte); if prefix.count == 3 { break } }
            #expect(prefix == Array("FLV".utf8))
        }
        print("斗鱼真实切换：高清 rate=2 / _900.flv；超清 rate=3 / _2000.flv；均已读取 FLV 媒体头")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JLIVE_QUALITY_LIVE_TESTS"] == "1"), .timeLimit(.minutes(2)))
    func liveQualityResponsesAndHLS() async throws {
        let client = HTTPClient()
        let providers: [(any LiveProvider, String)] = [(BilibiliProvider(client: client), "545068"), (DouyuProvider(client: client), "36252")]
        for (provider, roomID) in providers {
            let initial = try await provider.playback(roomID: roomID, quality: nil)
            #expect(initial.qualities.allSatisfy { $0.name != "自动画质" })
            let alternate = try #require(initial.qualities.first { $0.id >= 0 && $0.id != initial.currentQuality })
            let switched = try await provider.playback(roomID: roomID, quality: alternate.id)
            if switched.currentQuality != alternate.id { #expect(switched.qualityNotice != nil) }
            let line = try #require(switched.lines.first)
            if line.url.pathExtension == "m3u8" {
                let playlist = try await client.text(line.url, headers: switched.headers)
                #expect(playlist.hasPrefix("#EXTM3U"))
            }
            print("实际画质验证：\(provider.platform.name)，请求 \(alternate.id)，返回 \(switched.currentQuality)，格式 \(line.url.pathExtension)；回退：\(switched.qualityNotice != nil)")
        }
    }

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

    @Test func bilibiliPlaybackPreservesTheLoggedInBrowserIdentity() async throws {
        let client = BilibiliIdentityClient()
        let provider = BilibiliProvider(client: client)
        await provider.setCredentials(BilibiliCredentials(cookie: "SESSDATA=account;buvid3=login-device;", csrf: "csrf", uid: 42))
        _ = try await provider.playback(roomID: "42", quality: 400)
        let cookie = await client.playbackCookie
        #expect(cookie == "SESSDATA=account;buvid3=login-device;")
        #expect(await client.guestRequests == 0, "已有登录浏览器标识时不能混入另一个访客设备")
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

private actor BilibiliIdentityClient: HTTPRequesting {
    var playbackCookie: String?
    var guestRequests = 0
    func get(_ url: URL, headers: [String: String]) async throws -> JSONValue {
        if url.path.contains("finger/spi") { guestRequests += 1; throw LiveError.invalidResponse }
        playbackCookie = headers["Cookie"]
        let query = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        #expect(query["platform"] == "web")
        #expect(query["protocol"] == "0,1")
        #expect(query["codec"] == "0,1")
        return try JSONDecoder().decode(JSONValue.self, from: Data(#"{"code":0,"data":{"live_status":1,"playurl_info":{"playurl":{"g_qn_desc":[{"qn":400,"desc":"蓝光"}],"stream":[{"protocol_name":"http_hls","format":[{"format_name":"fmp4","codec":[{"codec_name":"avc","current_qn":400,"accept_qn":[400],"base_url":"/live.m3u8","url_info":[{"host":"https://cdn.example.com","extra":""}]}]}]}]}}}}"#.utf8))
    }
}

private actor DouyuDesktopClient: HTTPRequesting {
    var qualityBodies: [String] = []
    func get(_ url: URL, headers: [String: String]) async throws -> JSONValue {
        try decode(#"{"data":{"room42":"function ub98484234(r,d,t) { return 'sign=desktop'; }"}}"#)
    }
    func post(_ url: URL, body: String, headers: [String: String]) async throws -> JSONValue {
        #expect(url.path == "/lapi/live/getH5Play/42")
        if body.contains("rate=-1") {
            return try decode(#"{"error":0,"data":{"cdnsWithName":[{"cdn":"scdn-test"},{"cdn":"hw-h5"}],"multirates":[{"rate":0,"name":"原画"},{"rate":3,"name":"超清"},{"rate":2,"name":"高清"}]}}"#)
        }
        qualityBodies.append(body)
        let rate = body.hasSuffix("rate=2") ? 2 : 3
        let bit = rate == 2 ? 900 : 2000
        return try decode("""
        {"error":0,"data":{"rtmp_url":"https://cdn.example.com/live","rtmp_live":"room_\(bit).flv","rate":\(rate),"multirates":[{"rate":0,"name":"原画"},{"rate":3,"name":"超清"},{"rate":2,"name":"高清"}]}}
        """)
    }
    private func decode(_ value: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(value.utf8)) }
}

private actor DouyuQualityClient: HTTPRequesting {
    var mobileBodies: [String] = []
    func text(_ url: URL, headers: [String: String]) async throws -> String {
        #expect(url.host == "m.douyu.com")
        return "<script>var unrelated = 'ub98484234';</script><script type='text/javascript'>function ub98484234(r,d,t) { return 'sign=mobile'; }</script>"
    }
    func get(_ url: URL, headers: [String: String]) async throws -> JSONValue {
        #expect(url.path == "/swf_api/homeH5Enc")
        return try decode(#"{"data":{"room42":"function ub98484234(r,d,t) { return 'sign=desktop'; }"}}"#)
    }
    func post(_ url: URL, body: String, headers: [String: String]) async throws -> JSONValue {
        if url.path == "/hgapi/livenc/room/getStreamUrl" {
            #expect(url.host == "m.douyu.com")
            #expect(body.contains("sign=mobile"))
            mobileBodies.append(body)
            let bitrate = body.hasSuffix("&rate=2") ? 900 : 2000
            return try decode("""
            {"error":0,"data":{"url":"https://cdn.example.com/live/room_\(bitrate).m3u8","rate":0,"settings":[{"rate":0,"name":"原画"},{"rate":3,"name":"超清"},{"rate":2,"name":"高清"}]}}
            """)
        }
        #expect(url.path == "/lapi/live/getH5Play/42")
        #expect(body.contains("sign=desktop"))
        return try decode(#"{"error":0,"data":{"multirates":[{"rate":0,"name":"原画","bit":10000},{"rate":3,"name":"超清","bit":2000},{"rate":2,"name":"高清","bit":900}]}}"#)
    }
    private func decode(_ value: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(value.utf8)) }
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
