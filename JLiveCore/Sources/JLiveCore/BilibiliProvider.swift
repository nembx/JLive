// Platform endpoints and signing flow adapted from dart_simple_live.
// Copyright (C) 2023-2025 xiaoyaocz. GPL-3.0-or-later. See LICENSE.
import Foundation

public actor BilibiliProvider: LiveProvider {
    public nonisolated let platform = LivePlatform.bilibili
    private let client: any HTTPRequesting
    private var cookie: String?
    private var buvid: String?
    private var keys: (image: String, sub: String, fetchedAt: Date)?
    private var canonicalRoomIDs: [String: String] = [:]
    private var credentials: BilibiliCredentials?
    private let base = "https://api.live.bilibili.com"

    public init(client: any HTTPRequesting) { self.client = client }

    private func headers() async throws -> [String: String] {
        if cookie == nil {
            let response = try await client.get(try endpoint("https://api.bilibili.com/x/frontend/finger/spi"), headers: [:])
            let data = response["data"]
            guard !data["b_3"].string.isEmpty else { throw LiveError.invalidResponse }
            buvid = data["b_3"].string
            cookie = "buvid3=\(data["b_3"].string);buvid4=\(data["b_4"].string);"
        }
        return ["Referer": "https://live.bilibili.com/", "User-Agent": HTTPClient.userAgent, "Cookie": (cookie ?? "") + (credentials?.cookie ?? "")]
    }

    public func setCredentials(_ credentials: BilibiliCredentials?) {
        self.credentials = credentials
        keys = nil
    }

    public func sendChat(roomID: String, text: String) async throws {
        guard let credentials else { throw LiveError.platform("请先登录 B站账号") }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 30, let id = Int(roomID), id > 0 else { throw LiveError.platform("弹幕需要在 1 到 30 个字之间") }
        let url = try endpoint(base + "/msg/send")
        let parameters = ["roomid": roomID, "msg": message, "color": "16777215", "fontsize": "25", "mode": "1", "rnd": String(Int(Date().timeIntervalSince1970)), "csrf": credentials.csrf, "csrf_token": credentials.csrf]
        let body = formBody(parameters)
        let response = try await client.post(url, body: body, headers: try await headers())
        guard !response["code"].isNull else { throw LiveError.invalidResponse }
        guard response["code"].int == 0 else { throw LiveError.platform(response["message"].string.isEmpty ? response["msg"].string : response["message"].string) }
    }

    private func request(_ path: String, query: [String: String], signed: Bool = false) async throws -> JSONValue {
        let headers = try await headers()
        var parameters = query
        if signed {
            if keys == nil || Date().timeIntervalSince(keys!.fetchedAt) > 3_600 {
                let response = try await client.get(try endpoint("https://api.bilibili.com/x/web-interface/nav"), headers: headers)
                func key(_ value: JSONValue) -> String {
                    URL(string: value.string)?.deletingPathExtension().lastPathComponent ?? ""
                }
                let image = key(response["data"]["wbi_img"]["img_url"])
                let sub = key(response["data"]["wbi_img"]["sub_url"])
                guard image.count == 32, sub.count == 32 else { throw LiveError.invalidResponse }
                keys = (image, sub, Date())
            }
            guard let keys else { throw LiveError.invalidResponse }
            parameters = try WBISigner.sign(query, imageKey: keys.image, subKey: keys.sub, timestamp: Int(Date().timeIntervalSince1970))
        }
        let response = try await client.get(try endpoint(path.hasPrefix("https://") ? path : base + path, parameters), headers: headers)
        guard !response["code"].isNull else { throw LiveError.invalidResponse }
        guard response["code"].int == 0 else {
            if [-352, -403].contains(response["code"].int) { keys = nil; cookie = nil }
            let message = response["message"].string
            throw LiveError.platform(message.isEmpty ? "请求被拒绝" : message)
        }
        return response["data"]
    }

    public func recommendations(page: Int) async throws -> RoomPage {
        let data = try await request("/xlive/web-interface/v1/second/getListByArea", query: [
            "platform": "web", "sort": "online", "page_size": "30", "page": String(page)
        ], signed: true)
        let rooms = try data["list"].requiredArray().compactMap(Self.room)
        return RoomPage(rooms: rooms, hasMore: !rooms.isEmpty)
    }

    public func search(keyword: String, page: Int) async throws -> RoomPage {
        let data = try await request("https://api.bilibili.com/x/web-interface/search/type", query: [
            "search_type": "live", "cover_type": "user_cover", "keyword": keyword,
            "page": String(page), "highlight": "0", "order": ""
        ])
        let rooms = try data["result"]["live_room"].requiredArray().compactMap(Self.room)
        return RoomPage(rooms: rooms, hasMore: page < data["numPages"].int)
    }

    private static func room(_ item: JSONValue) -> LiveRoom? {
        let id = item["roomid"].string
        guard !id.isEmpty else { return nil }
        return LiveRoom(
            platform: .bilibili, roomID: id, title: plainText(item["title"].string), streamer: plainText(item["uname"].string),
            coverURL: imageURL(item["cover"].string), avatarURL: imageURL(item["face"].string),
            viewerCount: item["online"].int, category: item["area_name"].string, isLive: true
        )
    }

    public func detail(room: LiveRoom) async throws -> LiveRoom {
        let data = try await request("/xlive/web-room/v1/index/getInfoByRoom", query: ["room_id": room.roomID], signed: true)
        let info = data["room_info"]
        let anchor = data["anchor_info"]["base_info"]
        guard !info["room_id"].string.isEmpty else { throw LiveError.invalidResponse }
        canonicalRoomIDs[room.roomID] = info["room_id"].string
        canonicalRoomIDs[info["room_id"].string] = info["room_id"].string
        return LiveRoom(
            platform: .bilibili, roomID: info["room_id"].string, title: plainText(info["title"].string),
            streamer: anchor["uname"].string, coverURL: imageURL(info["cover"].string),
            avatarURL: imageURL(anchor["face"].string), viewerCount: info["online"].int,
            category: info["area_name"].string, isLive: info["live_status"].int == 1
        )
    }

    public func playback(roomID: String, quality: Int?) async throws -> PlaybackInfo {
        let data = try await request("/xlive/web-room/v2/index/getRoomPlayInfo", query: [
            "room_id": roomID, "protocol": "1", "format": "1,2", "codec": "0",
            "platform": "html5", "qn": String(quality ?? 10_000)
        ])
        guard data["live_status"].int == 1 else { throw LiveError.offline }
        return try Self.parsePlayback(data, headers: ["Referer": "https://live.bilibili.com/", "User-Agent": HTTPClient.userAgent])
    }

    public static func parsePlayback(_ data: JSONValue, headers: [String: String]) throws -> PlaybackInfo {
        let playurl = data["playurl_info"]["playurl"]
        var candidates: [(line: StreamLine, priority: Int)] = []
        var accepted: Set<Int> = []
        var currentQuality = 0
        for stream in playurl["stream"].array where stream["protocol_name"].string == "http_hls" {
            for format in stream["format"].array {
                for codec in format["codec"].array where codec["codec_name"].string == "avc" {
                    let path = codec["base_url"].string
                    guard !path.isEmpty else { continue }
                    currentQuality = codec["current_qn"].int
                    accepted.formUnion(codec["accept_qn"].array.map(\.int))
                    for host in codec["url_info"].array {
                        guard let url = URL(string: host["host"].string + path + host["extra"].string),
                              ["https", "http"].contains(url.scheme ?? ""), url.host != nil else { continue }
                        if !candidates.contains(where: { $0.line.url == url }) {
                            let priority = (format["format_name"].string == "fmp4" ? 0 : 2) + (url.host?.contains("mcdn") == true ? 1 : 0)
                            candidates.append((StreamLine(url: url), priority))
                        }
                    }
                }
            }
        }
        guard !candidates.isEmpty else { throw LiveError.noPlayableStream }
        // Prefer fMP4 HLS on iOS; some TS hosts reject otherwise valid guest requests.
        let lines = candidates.sorted { $0.priority < $1.priority }.map(\.line)
        let qualities = playurl["g_qn_desc"].array.filter { accepted.contains($0["qn"].int) }
            .map { StreamQuality(id: $0["qn"].int, name: $0["desc"].string) }
            .sorted { $0.id > $1.id }
        return PlaybackInfo(lines: lines, qualities: qualities, currentQuality: currentQuality, headers: headers)
    }

    public func chat(roomID: String) async throws -> LiveChatEndpoint {
        // The chat server only knows the canonical room number, not the short alias used in links.
        var canonical = canonicalRoomIDs[roomID]
        if canonical == nil {
            let info = try await request("/room/v1/Room/get_info", query: ["room_id": roomID])
            canonical = info["room_id"].string
            canonicalRoomIDs[roomID] = canonical
        }
        guard let canonical, let room = Int(canonical) else { throw LiveError.invalidResponse }
        let data = try await request("/xlive/web-room/v1/index/getDanmuInfo", query: ["id": canonical, "type": "0"], signed: true)
        guard let buvid else { throw LiveError.invalidResponse }
        return try Self.chatEndpoint(roomID: room, token: data["token"].string, hosts: data["host_list"], buvid: buvid, credentials: credentials)
    }

    public static func chatEndpoint(roomID: Int, token: String, hosts: JSONValue, buvid: String, credentials: BilibiliCredentials? = nil) throws -> LiveChatEndpoint {
        guard !token.isEmpty else { throw LiveError.invalidResponse }
        let urls = hosts.array.compactMap { host -> URL? in
            let name = host["host"].string
            guard !name.isEmpty else { return nil }
            let port = host["wss_port"].int
            return URL(string: "wss://\(name):\(port > 0 ? port : 443)/sub")
        }
        return LiveChatEndpoint(
            urls: urls.isEmpty ? [URL(string: "wss://\(BilibiliChatCodec.fallbackHost)/sub")!] : urls,
            headers: [
                "User-Agent": HTTPClient.userAgent, "Origin": "https://live.bilibili.com",
                "Cookie": "buvid3=\(buvid);" + (credentials?.cookie ?? "")
            ],
            handshake: try BilibiliChatCodec.handshake(roomID: roomID, token: token, buvid: buvid, uid: credentials?.uid ?? 0),
            heartbeat: BilibiliChatCodec.heartbeat(),
            heartbeatInterval: 30,
            decode: { try BilibiliChatCodec.decode($0) }
        )
    }
}

public struct BilibiliCredentials: Codable, Sendable {
    public let cookie: String
    public let csrf: String
    public let uid: Int
    public init(cookie: String, csrf: String, uid: Int) { self.cookie = cookie; self.csrf = csrf; self.uid = uid }
}
