import Foundation
import Testing
@testable import JLiveCore

struct CoreTests {
    @Test func wbiKnownSignature() throws {
        let query = try WBISigner.sign(
            ["foo": "114", "bar": "514", "baz": "1919810"],
            imageKey: "7cd084941338484aae1ad9425b84077c",
            subKey: "4932caff0ff746eab6f01bf08b70ac45", timestamp: 1_702_204_169
        )
        // Independently calculated with Python hashlib + urllib.parse.urlencode.
        #expect(query["w_rid"] == "6149fdadf571698ca7e6a567265cd0ee")
        #expect(query["wts"] == "1702204169")
    }

    @Test func wbiFiltersSpecialCharactersAndRejectsBadKeys() throws {
        let query = try WBISigner.sign(
            ["keyword": "hello!'()* world"], imageKey: String(repeating: "a", count: 32),
            subKey: String(repeating: "b", count: 32), timestamp: 100
        )
        #expect(query["keyword"] == "hello world")
        #expect(throws: LiveError.self) {
            try WBISigner.sign([:], imageKey: "bad", subKey: "bad", timestamp: 1)
        }
    }

    @Test func aggregateKeepsWorkingPlatformAndSeparatesRoomIDs() async throws {
        let bili = room(.bilibili, "100")
        let huya = room(.huya, "100")
        let service = LiveService(providers: [
            StubProvider(platform: .bilibili, rooms: [bili, bili], hasMore: true),
            StubProvider(platform: .huya, rooms: [huya]),
            StubProvider(platform: .douyu, fails: true)
        ])
        let result = try await service.discover(platforms: [.bilibili, .huya, .douyu])
        #expect(result.rooms.map(\.id) == ["bilibili:100", "huya:100"])
        #expect(result.issues.map(\.platform) == [.douyu])
        #expect(result.platformsWithMore == [.bilibili])
    }

    @Test func cancelledAggregationDoesNotPublishResults() async {
        let service = LiveService(providers: [StubProvider(platform: .huya)])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.discover(platforms: [.huya])
        }
        do {
            _ = try await task.value
            Issue.record("A cancelled request must not publish results")
        } catch { #expect(error is CancellationError) }
    }

    @Test func hlsParserSkipsFLVAndHEVCAndPrefersNormalCDNs() throws {
        let data = try json("""
        {"playurl_info":{"playurl":{
          "g_qn_desc":[{"qn":10000,"desc":"原画"},{"qn":400,"desc":"蓝光"},{"qn":80,"desc":"流畅"}],
          "stream":[
            {"protocol_name":"http_stream","format":[{"codec":[{"codec_name":"avc","base_url":"/live.flv","url_info":[{"host":"https://flv.example.com","extra":""}]}]}]},
            {"protocol_name":"http_hls","format":[{"codec":[
              {"codec_name":"hevc","base_url":"/hevc.m3u8","url_info":[{"host":"https://hevc.example.com","extra":""}]},
              {"codec_name":"avc","current_qn":400,"accept_qn":[400,80],"base_url":"/live.m3u8","url_info":[
                {"host":"https://mcdn.example.com","extra":"?token=abc"},
                {"host":"https://normal.example.com","extra":"?token=xyz"},
                {"host":"https://normal.example.com","extra":"?token=xyz"}
              ]}
            ]}]}
          ]
        }}}
        """)
        let info = try BilibiliProvider.parsePlayback(data, headers: [:])
        #expect(info.lines.count == 2)
        #expect(info.lines.first?.url.absoluteString == "https://normal.example.com/live.m3u8?token=xyz")
        #expect(info.qualities.map(\.id) == [400, 80])
        #expect(info.currentQuality == 400)
    }

    @Test func hlsParserRejectsEmptyOrFLVOnlyPayload() throws {
        #expect(throws: LiveError.self) { try BilibiliProvider.parsePlayback(try json("{}"), headers: [:]) }
    }

    @Test func nativePlaybackPrefersFMP4OverTS() throws {
        let data = try json("""
        {"playurl_info":{"playurl":{"stream":[{"protocol_name":"http_hls","format":[
          {"format_name":"ts","codec":[{"codec_name":"avc","base_url":"/live.m3u8","url_info":[{"host":"https://ts.example.com","extra":""}]}]},
          {"format_name":"fmp4","codec":[{"codec_name":"avc","base_url":"/index.m3u8","url_info":[{"host":"https://fmp4.example.com","extra":""}]}]}
        ]}]}}}
        """)
        let result = try BilibiliProvider.parsePlayback(data, headers: [:])
        #expect(result.lines.first?.url.host == "fmp4.example.com")
        #expect(result.lines.count == 2)
    }

    @Test func douyuListExcludesPromotionsAndMapsNumericID() async throws {
        let client = StubClient(response: try json("""
        {"error":0,"data":{"pgcnt":3,"rl":[
          {"type":2,"rid":999,"rn":"广告"},
          {"type":1,"rid":36252,"rn":"游戏直播","nn":"主播","ol":49697,"rs16":"//images.example.com/cover.jpg","c2name":"游戏"}
        ]}}
        """))
        let result = try await DouyuProvider(client: client).recommendations(page: 1)
        #expect(result.rooms.count == 1)
        #expect(result.rooms.first?.roomID == "36252")
        #expect(result.rooms.first?.coverURL?.scheme == "https")
        #expect(result.hasMore)
    }

    @Test func huyaListNormalizesHTTPArtworkAndHandlesLastPage() async throws {
        let client = StubClient(response: try json("""
        {"status":200,"data":{"page":2,"totalPage":2,"datas":[
          {"profileRoom":"998","introduction":"","roomName":"直播标题","nick":"楚河","totalCount":"5500797","screenshot":"http://images.example.com/cover.jpg"}
        ]}}
        """))
        let result = try await HuyaProvider(client: client).recommendations(page: 2)
        #expect(result.rooms.first?.title == "直播标题")
        #expect(result.rooms.first?.coverURL?.scheme == "https")
        #expect(!result.hasMore)
    }

    @Test func changedPlatformPayloadIsReportedInsteadOfEmptySuccess() async throws {
        let client = StubClient(response: try json("{\"error\":0,\"data\":{\"new_list\":[]}}"))
        do {
            _ = try await DouyuProvider(client: client).recommendations(page: 1)
            Issue.record("A missing list must be reported as an API format change")
        } catch { #expect(error is LiveError) }
    }

    @Test func roomLinksHandleCanonicalAndMobileURLs() throws {
        #expect(try RoomLinkParser.parse("https://live.bilibili.com/blanc/123?from=share").roomID == "123")
        #expect(try RoomLinkParser.parse("https://m.huya.com/chuhe").platform == .huya)
        #expect(try RoomLinkParser.parse("36252", platform: .douyu).webURL.absoluteString == "https://www.douyu.com/36252")
    }

    @Test(arguments: [
        "https://www.huya.com.evil.example/123", "https://evilhuya.com/123",
        "https://www.douyu.com/directory", "https://live.bilibili.com/not_a_room",
        "https://www.huya.com/", "ftp://www.huya.com/123", "https://www.huya.com/a/b"
    ]) func invalidRoomLinksAreRejected(input: String) {
        #expect(throws: LiveError.self) { try RoomLinkParser.parse(input) }
    }

    private func room(_ platform: LivePlatform, _ id: String) -> LiveRoom {
        LiveRoom(platform: platform, roomID: id, title: "标题", streamer: "主播")
    }

    private func json(_ source: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8))
    }
}

private struct StubClient: HTTPRequesting {
    let response: JSONValue
    func get(_ url: URL, headers: [String: String]) async throws -> JSONValue { response }
}

private struct StubProvider: LiveProvider {
    let platform: LivePlatform
    var rooms: [LiveRoom] = []
    var hasMore = false
    var fails = false
    func recommendations(page: Int) async throws -> RoomPage {
        if fails { throw LiveError.http(503) }
        return RoomPage(rooms: rooms, hasMore: hasMore)
    }
    func search(keyword: String, page: Int) async throws -> RoomPage { try await recommendations(page: page) }
}
