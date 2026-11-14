// Public endpoints, signing and stream mappings adapted from dart_simple_live.
// Copyright (C) 2023-2025 xiaoyaocz. GPL-3.0-or-later. See LICENSE.
import Foundation
import JavaScriptCore

public actor DouyinProvider: LiveProvider {
    public nonisolated let platform = LivePlatform.douyin
    private let client: any HTTPRequesting
    private var bootstrapped = false
    private var cachedRooms: [String: (room: JSONValue, at: Date)] = [:]
    private var searchSessions: [String: SearchSession] = [:]
    private var searchBootstrapped = false
    private var credentials: DouyinCredentials?
    private var credentialRevision = UUID()
    private struct SearchSession {
        let page: Int
        let cursor: String
        let searchID: String
        let at: Date
    }
    static let userAgent = DouyinCredentials.userAgent

    public init(client: any HTTPRequesting) { self.client = client }

    private func headers(roomID: String = "") async throws -> [String: String] {
        if !bootstrapped {
            _ = try await client.text(LivePlatform.douyin.homeURL, headers: ["User-Agent": Self.userAgent])
            bootstrapped = true
        }
        let cookie = await client.cookies(for: LivePlatform.douyin.homeURL)
        return ["User-Agent": Self.userAgent, "Referer": "https://live.douyin.com/\(roomID)", "Cookie": cookie]
    }

    private func request(_ path: String, query: [String: String], roomID: String = "") async throws -> JSONValue {
        let headers = try await headers(roomID: roomID)
        let url = try DouyinSigner.signedURL(try endpoint("https://live.douyin.com" + path, query))
        let response = try await client.get(url, headers: headers)
        guard !response["status_code"].isNull else { bootstrapped = false; throw LiveError.invalidResponse }
        guard response["status_code"].int == 0 else {
            bootstrapped = false
            throw LiveError.platform(response["status_msg"].string.isEmpty ? "抖音请求被拒绝，请稍后重试或前往官网观看。" : response["status_msg"].string)
        }
        return response["data"]
    }

    private var webParameters: [String: String] {
        ["aid": "6383", "app_name": "douyin_web", "live_id": "1", "device_platform": "web",
         "language": "zh-CN", "browser_language": "zh-CN", "browser_platform": "Win32",
         "browser_name": "Chrome", "browser_version": "116.0.0.0", "cookie_enabled": "true"]
    }

    public func recommendations(page: Int) async throws -> RoomPage {
        var query = webParameters
        query.merge(["enter_from": "link_share", "count": "15", "offset": String(max(0, page - 1) * 15),
            "partition": "720", "partition_type": "1", "req_from": "2", "screen_width": "1920", "screen_height": "1080"], uniquingKeysWith: { _, b in b })
        let data = try await request("/webcast/web/partition/detail/room/v2/", query: query)
        return try Self.parseRecommendations(data)
    }

    static func parseRecommendations(_ data: JSONValue) throws -> RoomPage {
        let list = try data["data"].requiredArray()
        var seen = Set<String>()
        let rooms = list.compactMap { item -> LiveRoom? in
            let id = item["web_rid"].string
            guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }), seen.insert(id).inserted else { return nil }
            var room = Self.room(item["room"], webID: id)
            // The recommendation endpoint omits status (protobuf default 0) for live rooms.
            if room.isLive == nil { room.isLive = true }
            return room
        }
        return RoomPage(rooms: rooms, hasMore: list.count >= 15)
    }

    public func setCredentials(_ credentials: DouyinCredentials?) async {
        self.credentials = credentials
        credentialRevision = UUID()
        searchSessions.removeAll()
        if credentials == nil {
            // Search responses may refresh account cookies in URLSession as well as WebKit.
            await client.clearCookies(for: URL(string: "https://www.douyin.com/")!)
            await client.clearCookies(for: LivePlatform.douyin.homeURL)
            searchBootstrapped = false
            bootstrapped = false
        }
    }

    /// Validate with the live search endpoint without replacing an existing account on failure.
    public func validateCredentials(_ credentials: DouyinCredentials) async throws {
        _ = try Self.parseSearch(await searchResponse(keyword: "游戏", offset: "0", searchID: "", credentials: credentials))
    }

    public func search(keyword: String, page: Int) async throws -> RoomPage {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return RoomPage(rooms: [], hasMore: false) }
        let page = max(1, page)
        let revision = credentialRevision
        searchSessions = searchSessions.filter { Date().timeIntervalSince($0.value.at) < 300 }
        let previous = searchSessions[keyword].flatMap { $0.page == page - 1 ? $0 : nil }
        let response = try await searchResponse(keyword: keyword, offset: previous?.cursor ?? String((page - 1) * 10),
            searchID: previous?.searchID ?? "", credentials: credentials)
        guard revision == credentialRevision else { throw CancellationError() }
        let result = try Self.parseSearch(response)
        if searchSessions.count >= 20 { searchSessions.removeAll() }
        searchSessions[keyword] = SearchSession(page: page, cursor: response["cursor"].string.isEmpty ? String(page * 10) : response["cursor"].string,
            searchID: response["log_pb"]["impr_id"].string, at: Date())
        return result
    }

    private func searchResponse(keyword: String, offset: String, searchID: String, credentials: DouyinCredentials?) async throws -> JSONValue {
        let home = URL(string: "https://www.douyin.com/")!
        _ = try await headers()
        if !searchBootstrapped {
            _ = try await client.text(home, headers: ["User-Agent": Self.userAgent])
            searchBootstrapped = true
        }
        let url = try Self.searchURL(keyword: keyword, offset: offset, searchID: searchID)
        var referer = URLComponents(url: home.appendingPathComponent("search").appendingPathComponent(keyword), resolvingAgainstBaseURL: false)!
        referer.queryItems = [URLQueryItem(name: "type", value: "live")]
        let guestCookies = await client.cookies(for: home)
        let cookie = Self.searchCookies(guest: guestCookies, account: credentials?.cookie ?? "")
        let headers = ["User-Agent": Self.userAgent, "Referer": referer.url!.absoluteString,
            "Cookie": cookie, "Accept": "application/json, text/plain, */*", "Accept-Language": "zh-CN,zh;q=0.9",
            "Sec-Fetch-Dest": "empty", "Sec-Fetch-Mode": "cors", "Sec-Fetch-Site": "same-origin"]
        do {
            return try await client.get(url, headers: headers)
        } catch LiveError.invalidResponse {
            try Task.checkCancellation()
            return try await client.get(DouyinSigner.signedURL(url), headers: headers)
        }
    }

    static func searchCookies(guest: String, account: String) -> String {
        var seen = Set<String>()
        return (account + ";" + guest).split(separator: ";").compactMap { field -> String? in
            let field = field.trimmingCharacters(in: .whitespaces)
            guard let separator = field.firstIndex(of: "="), separator != field.startIndex else { return nil }
            let name = String(field[..<separator])
            return seen.insert(name).inserted ? field : nil
        }.joined(separator: "; ")
    }

    static func searchURL(keyword: String, offset: String, searchID: String = "") throws -> URL {
        var query = ["device_platform": "webapp", "aid": "6383", "channel": "channel_pc_web", "search_channel": "aweme_live",
            "keyword": keyword, "search_source": "switch_tab", "query_correct_type": "1", "is_filter_search": "0", "from_group_id": "",
            "offset": offset, "count": "10", "pc_client_type": "1", "version_code": "170400", "version_name": "17.4.0",
            "cookie_enabled": "true", "screen_width": "1920", "screen_height": "1080", "browser_language": "zh-CN",
            "browser_platform": "Win32", "browser_name": "Chrome", "browser_version": "116.0.0.0", "browser_online": "true",
            "engine_name": "Blink", "engine_version": "116.0.0.0", "os_name": "Windows", "os_version": "10",
            "cpu_core_num": "12", "device_memory": "8", "platform": "PC", "downlink": "10", "effective_type": "4g", "round_trip_time": "100"]
        if !searchID.isEmpty { query["search_id"] = searchID }
        return try endpoint("https://www.douyin.com/aweme/v1/web/live/search/", query)
    }

    static func parseSearch(_ response: JSONValue) throws -> RoomPage {
        guard !response["status_code"].isNull else { throw LiveError.invalidResponse }
        if response["status_code"].int == 2483 { throw LiveError.loginRequired(.douyin) }
        guard response["status_code"].int == 0 else {
            let message = response["status_msg"].string
            throw LiveError.platform(message.isEmpty ? "抖音直播搜索暂时受限，请稍后重试。" : message)
        }
        let items = try response["data"].requiredArray()
        var seen = Set<String>()
        var decodedCount = 0
        let rooms = items.compactMap { item -> LiveRoom? in
            let raw = item["lives"]["rawdata"].string
            guard let data = try? JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)) else { return nil }
            decodedCount += 1
            let webID = data["owner"]["web_rid"].string
            let id = webID.isEmpty ? data["id_str"].string : webID
            guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }), seen.insert(id).inserted else { return nil }
            var room = Self.room(data, webID: id)
            if room.isLive == nil { room.isLive = true }
            if room.viewerCount == 0 { room.viewerCount = data["stats"]["total_user"].int }
            return room
        }
        guard items.isEmpty || decodedCount > 0 else { throw LiveError.invalidResponse }
        let hasMore: Bool
        if case .bool(let value) = response["has_more"] { hasMore = value }
        else if !response["has_more"].isNull { hasMore = response["has_more"].int != 0 }
        else { hasMore = items.count >= 10 }
        return RoomPage(rooms: rooms, hasMore: hasMore)
    }

    private func roomData(_ id: String, allowCache: Bool) async throws -> JSONValue {
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw LiveError.invalidRoomLink }
        if allowCache, let cache = cachedRooms[id], Date().timeIntervalSince(cache.at) < 20 { return cache.room }
        if id.count > 16 {
            // Shared links may contain an internal ID which changes on each new broadcast.
            let url = try endpoint("https://webcast.amemv.com/webcast/room/reflow/info/", [
                "type_id": "0", "live_id": "1", "room_id": id, "sec_user_id": "", "version_code": "99.99.99", "app_id": "6383"])
            let response = try await client.get(url, headers: try await headers())
            let room = response["data"]["room"]
            let webID = room["owner"]["web_rid"].string
            guard !webID.isEmpty, webID.count <= 16, webID.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw LiveError.invalidResponse }
            let current = try await roomData(webID, allowCache: allowCache)
            store(current, id: id)
            return current
        }
        var query = webParameters
        query["web_rid"] = id
        do {
            let data = try await request("/webcast/room/web/enter/", query: query, roomID: id)
            let room = data["data"][0]
            guard !room["id_str"].string.isEmpty else { throw LiveError.invalidResponse }
            store(room, id: id)
            return room
        } catch {
            try Task.checkCancellation()
            // Server-rendered room state remains useful when the public JSON API is restricted.
            let html = try await client.text(LivePlatform.douyin.roomURL(id), headers: try await headers(roomID: id))
            let room = try Self.parseRoomHTML(html)
            store(room, id: id)
            return room
        }
    }

    private func store(_ room: JSONValue, id: String) {
        cachedRooms = cachedRooms.filter { Date().timeIntervalSince($0.value.at) < 20 }
        if cachedRooms.count >= 50 { cachedRooms.removeAll() }
        cachedRooms[id] = (room, Date())
    }

    static func parseRoomHTML(_ html: String) throws -> JSONValue {
        // React flight strings are JSON strings containing an additional JSON document.
        let pattern = #"self\.__next_f\.push\(\[\d+,\s*("(?:\\.|[^"\\])*")\]\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        var decoded = ""
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html),
                  let string = try? JSONDecoder().decode(String.self, from: Data(html[range].utf8)) else { continue }
            decoded += string
        }
        // Some versions use the older SSR representation directly inside the page.
        if decoded.isEmpty { decoded = html.replacingOccurrences(of: #"\""#, with: "\"") }
        var remaining = decoded[...]
        while let marker = remaining.range(of: "\"roomInfo\":") {
            if let json = balancedObject(after: "\"roomInfo\":", in: String(remaining)),
               let info = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)),
               !info["room"]["id_str"].string.isEmpty {
                var room = info["room"].object
                if info["room"]["owner"].isNull { room["owner"] = info["anchor"] }
                return .object(room)
            }
            remaining = remaining[marker.upperBound...]
        }
        throw LiveError.invalidResponse
    }

    public func detail(room: LiveRoom) async throws -> LiveRoom {
        let data = try await roomData(room.roomID, allowCache: false)
        let webID = data["owner"]["web_rid"].string
        return Self.room(data, webID: webID.isEmpty ? room.roomID : webID)
    }

    private static func room(_ data: JSONValue, webID: String) -> LiveRoom {
        let owner = data["owner"]
        return LiveRoom(platform: .douyin, roomID: webID, title: data["title"].string,
            streamer: owner["nickname"].string, coverURL: imageURL(data["cover"]["url_list"][0].string),
            avatarURL: imageURL(owner["avatar_thumb"]["url_list"][0].string),
            viewerCount: data["room_view_stats"]["display_value"].int,
            category: data["partition_road_map"]["partition"]["title"].string,
            isLive: data["status"].int == 0 ? nil : data["status"].int == 2)
    }

    public func playback(roomID: String, quality: Int?) async throws -> PlaybackInfo {
        let data = try await roomData(roomID, allowCache: true)
        guard data["status"].int == 2 else { throw LiveError.offline }
        return try Self.parsePlayback(data["stream_url"], quality: quality, headers: try await headers(roomID: roomID))
    }

    static func parsePlayback(_ stream: JSONValue, quality: Int?, headers: [String: String]) throws -> PlaybackInfo {
        let pull = stream["live_core_sdk_data"]["pull_data"]
        let options = pull["options"]["qualities"].array
        let nested = (try? JSONDecoder().decode(JSONValue.self, from: Data(pull["stream_data"].string.utf8)))?["data"] ?? .null
        var levels: [(StreamQuality, [StreamLine])] = []
        var seen = Set<Int>()
        for item in options {
            let id = item["level"].int, key = item["sdk_key"].string
            let candidates = [nested[key]["main"]["hls"].string, nested[key]["backup"]["hls"].string,
                stream["hls_pull_url_map"][key].string]
            let lines = hlsLines(candidates)
            guard !lines.isEmpty, seen.insert(id).inserted else { continue }
            let name = item["name"].string
            levels.append((StreamQuality(id: id, name: name.isEmpty ? "画质 \(id)" : name), lines))
        }
        if levels.isEmpty {
            let map = stream["hls_pull_url_map"].object
            let keys = map.keys.sorted {
                let a = qualityRank($0), b = qualityRank($1)
                return a == b ? $0 < $1 : a < b
            }
            for (index, key) in keys.enumerated() {
                let lines = hlsLines([map[key]?.string ?? ""])
                if !lines.isEmpty { levels.append((StreamQuality(id: index + 1, name: qualityName(key)), lines)) }
            }
            if levels.isEmpty {
                let lines = hlsLines([stream["hls_pull_url"].string])
                if !lines.isEmpty { levels = [(StreamQuality(id: 0, name: "自动画质"), lines)] }
            }
        }
        guard !levels.isEmpty else { throw LiveError.noPlayableStream }
        levels.sort { $0.0.id > $1.0.id }
        let selected = levels.first { $0.0.id == quality } ?? levels[0]
        return PlaybackInfo(lines: selected.1, qualities: levels.map(\.0), currentQuality: selected.0.id, headers: headers)
    }

    private static func hlsLines(_ candidates: [String]) -> [StreamLine] {
        var seen = Set<URL>()
        return candidates.compactMap { raw in
            guard var components = URLComponents(string: raw.replacingOccurrences(of: "&amp;", with: "&")),
                  ["http", "https"].contains(components.scheme ?? ""), components.host != nil else { return nil }
            // Douyin advertises HTTP pull URLs even though its CDN supports HTTPS.
            // Use secure media URLs so AVPlayer can follow both playlists and segments under ATS.
            if components.scheme == "http" {
                components.scheme = "https"
                if components.port == 80 { components.port = nil }
            }
            guard let url = components.url, url.path.lowercased().hasSuffix(".m3u8"),
                  seen.insert(url).inserted else { return nil }
            return StreamLine(url: url)
        }
    }
    private static func qualityName(_ key: String) -> String {
        ["FULL_HD1": "原画", "HD1": "高清", "SD1": "标清", "SD2": "流畅", "ORIGIN": "原画"][key] ?? key
    }
    private static func qualityRank(_ key: String) -> Int {
        ["SD2": 1, "SD1": 2, "HD1": 3, "FULL_HD1": 4, "ORIGIN": 5][key] ?? 0
    }

    public func chat(roomID: String) async throws -> LiveChatEndpoint {
        let room = try await roomData(roomID, allowCache: true)
        guard room["status"].int == 2 else { throw LiveError.offline }
        let internalID = room["id_str"].string
        guard !internalID.isEmpty else { throw LiveError.invalidResponse }
        let webID = room["owner"]["web_rid"].string.isEmpty ? roomID : room["owner"]["web_rid"].string
        // Visit the room to obtain fresh guest cookies; never reuse an upstream identity.
        _ = try await client.text(LivePlatform.douyin.roomURL(webID), headers: try await headers(roomID: webID))
        let headers = try await headers(roomID: webID).merging(["Origin": "https://live.douyin.com"], uniquingKeysWith: { _, b in b })
        let guestID = String(UInt64.random(in: 100_000_000_000...999_999_999_999))
        let signature = try DouyinSigner.chatSignature(roomID: internalID, guestID: guestID)
        var query = webParameters
        query.merge([
            "version_code": "180800", "webcast_sdk_version": "1.3.0", "update_version_code": "1.3.0",
            "compress": "gzip", "cursor": "h-1_t-\(Int64(Date().timeIntervalSince1970 * 1000))_r-1_d-1_u-1",
            "host": "https://live.douyin.com", "did_rule": "3", "debug": "false", "maxCacheMessageNumber": "20",
            "endpoint": "live_pc", "support_wrds": "1", "im_path": "/webcast/im/fetch/", "user_unique_id": guestID,
            "screen_width": "1920", "screen_height": "1080", "browser_name": "Mozilla",
            "browser_version": String(Self.userAgent.dropFirst("Mozilla/".count)), "browser_online": "true",
            "tz_name": "Asia/Shanghai", "identity": "audience", "room_id": internalID, "heartbeatDuration": "0", "signature": signature
        ], uniquingKeysWith: { _, b in b })
        let hosts = ["webcast3-ws-web-lq.douyin.com", "webcast5-ws-web-lf.douyin.com"]
        return LiveChatEndpoint(urls: try hosts.map {
            let url = try endpoint("wss://\($0)/webcast/im/push/v2/", query)
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw LiveError.invalidResponse }
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            guard let url = components.url else { throw LiveError.invalidResponse }
            return url
        },
            headers: headers, handshake: DouyinChatCodec.heartbeat, heartbeat: DouyinChatCodec.heartbeat,
            heartbeatInterval: 10, process: { try DouyinChatCodec.process($0) })
    }
}

enum DouyinSigner {
    static func chatSignature(roomID: String, guestID: String) throws -> String {
        guard let sourceURL = Bundle.module.url(forResource: "douyin-chat-sign", withExtension: "js"), let context = JSContext() else {
            throw LiveError.invalidResponse
        }
        let stub = md5("live_id=1,aid=6383,version_code=180800,webcast_sdk_version=1.3.0,room_id=\(roomID),sub_room_id=,sub_channel_id=,did_rule=3,user_unique_id=\(guestID),device_platform=web,device_type=,ac=,identity=audience")
        context.evaluateScript(try String(contentsOf: sourceURL, encoding: .utf8))
        for _ in 0..<8 {
            guard let signature = context.objectForKeyedSubscript("getMSSDKSignature")?.call(withArguments: [stub, DouyinProvider.userAgent])?.toString(),
                  context.exception == nil, !signature.isEmpty, signature != "undefined" else { throw LiveError.invalidResponse }
            if !signature.contains("-"), !signature.contains("=") { return signature }
        }
        throw LiveError.platform("抖音弹幕签名暂时无法生成，请重试。")
    }

    static func signedURL(_ url: URL) throws -> URL {
        guard let sourceURL = Bundle.module.url(forResource: "douyin-abogus", withExtension: "js"),
              let context = JSContext(), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw LiveError.invalidResponse }
        let script = try String(contentsOf: sourceURL, encoding: .utf8)
        context.evaluateScript(script)
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        let token = String((0..<107).map { _ in alphabet.randomElement()! })
        var parameters = components.queryItems ?? []
        parameters.removeAll { ["a_bogus", "msToken"].contains($0.name) }
        parameters.append(URLQueryItem(name: "msToken", value: token))
        components.queryItems = parameters
        guard let signature = context.objectForKeyedSubscript("getABogus")?.call(withArguments: [components.percentEncodedQuery ?? "", DouyinProvider.userAgent])?.toString(),
              context.exception == nil, !signature.isEmpty, signature != "undefined" else { throw LiveError.invalidResponse }
        parameters.append(URLQueryItem(name: "a_bogus", value: signature))
        components.queryItems = parameters
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let result = components.url else { throw LiveError.invalidResponse }
        return result
    }
}

/// Reads balanced JSON without treating braces inside quoted strings as structure.
func balancedObject(after marker: String, in text: String) -> String? {
    guard let markerRange = text.range(of: marker),
          let start = text[markerRange.upperBound...].firstIndex(where: { !$0.isWhitespace }), text[start] == "{" else { return nil }
    var depth = 0, quoted = false, escaped = false
    for index in text[start...].indices {
        let character = text[index]
        if quoted {
            if escaped { escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "\"" { quoted = false }
        } else if character == "\"" { quoted = true }
        else if character == "{" { depth += 1 }
        else if character == "}" {
            depth -= 1
            if depth == 0 { return String(text[start...index]) }
        }
    }
    return nil
}

public struct DouyinCredentials: Codable, Sendable {
    public let cookie: String
    public init(cookie: String) { self.cookie = cookie }
    public static let userAgent = "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.5845.97 Safari/537.36 Core/1.116.567.400 QQBrowser/19.7.6764.400"
}
