// Platform endpoints and field mappings adapted from dart_simple_live.
// Copyright (C) 2023-2025 xiaoyaocz. GPL-3.0-or-later. See LICENSE.
import Foundation

public struct HuyaProvider: LiveProvider {
    public let platform = LivePlatform.huya
    private let client: any HTTPRequesting
    public init(client: any HTTPRequesting) { self.client = client }

    public func recommendations(page: Int) async throws -> RoomPage {
        let result = try await client.get(try endpoint("https://www.huya.com/cache.php", [
            "m": "LiveList", "do": "getLiveListByPage", "tagAll": "0", "page": String(page)
        ]), headers: ["Referer": "https://www.huya.com/"])
        guard result["status"].int == 200 else { throw LiveError.platform(result["message"].string) }
        let data = result["data"]
        let rooms = try data["datas"].requiredArray().compactMap { item -> LiveRoom? in
            guard !item["profileRoom"].string.isEmpty else { return nil }
            return LiveRoom(
                platform: .huya, roomID: item["profileRoom"].string,
                title: item["introduction"].string.isEmpty ? item["roomName"].string : item["introduction"].string,
                streamer: item["nick"].string, coverURL: imageURL(item["screenshot"].string),
                avatarURL: imageURL(item["avatar180"].string), viewerCount: item["totalCount"].int,
                category: item["gameFullName"].string, isLive: true
            )
        }
        return RoomPage(rooms: rooms, hasMore: page < data["totalPage"].int)
    }

    public func search(keyword: String, page: Int) async throws -> RoomPage {
        let result = try await client.get(try endpoint("https://search.cdn.huya.com/", [
            "m": "Search", "do": "getSearchContent", "q": keyword, "uid": "0", "v": "4",
            "typ": "-5", "livestate": "0", "rows": "20", "start": String((page - 1) * 20)
        ]), headers: ["Referer": "https://www.huya.com/"])
        let data = result["response"]["3"]
        let rooms = try data["docs"].requiredArray().compactMap { item -> LiveRoom? in
            guard !item["room_id"].string.isEmpty else { return nil }
            return LiveRoom(
                platform: .huya, roomID: item["room_id"].string,
                title: plainText(item["game_introduction"].string), streamer: plainText(item["game_nick"].string),
                coverURL: imageURL(item["game_screenshot"].string), avatarURL: imageURL(item["game_avatarUrl180"].string),
                viewerCount: item["game_total_count"].int, category: item["game_name"].string,
                isLive: item["gameLiveOn"].isNull ? nil : item["gameLiveOn"].int == 1
            )
        }
        return RoomPage(rooms: rooms, hasMore: page * 20 < data["numFound"].int)
    }
}

public struct DouyuProvider: LiveProvider {
    public let platform = LivePlatform.douyu
    private let client: any HTTPRequesting
    public init(client: any HTTPRequesting) { self.client = client }

    public func recommendations(page: Int) async throws -> RoomPage {
        let result = try await client.get(try endpoint("https://www.douyu.com/japi/weblist/apinc/allpage/6/\(page)"), headers: ["Referer": "https://www.douyu.com/"])
        guard !result["error"].isNull, result["error"].int == 0 else { throw LiveError.platform(result["msg"].string) }
        let data = result["data"]
        let rooms = try data["rl"].requiredArray().filter { $0["type"].int == 1 }.compactMap { item -> LiveRoom? in
            guard !item["rid"].string.isEmpty else { return nil }
            let cover = item["rs16_webp_1x"].string.isEmpty ? item["rs16"].string : item["rs16_webp_1x"].string
            return LiveRoom(
                platform: .douyu, roomID: item["rid"].string, title: item["rn"].string, streamer: item["nn"].string,
                coverURL: imageURL(cover), avatarURL: imageURL(item["av"].string),
                viewerCount: item["ol"].int, category: item["c2name"].string, isLive: true
            )
        }
        return RoomPage(rooms: rooms, hasMore: page < data["pgcnt"].int)
    }

    public func search(keyword: String, page: Int) async throws -> RoomPage {
        let did = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let result = try await client.get(try endpoint("https://www.douyu.com/japi/search/api/searchShow", [
            "kw": keyword, "page": String(page), "pageSize": "20"
        ]), headers: ["Referer": "https://www.douyu.com/search/", "Cookie": "dy_did=\(did);acf_did=\(did)"])
        guard !result["error"].isNull, result["error"].int == 0 else { throw LiveError.platform(result["msg"].string) }
        let rooms = try result["data"]["relateShow"].requiredArray().compactMap { item -> LiveRoom? in
            guard !item["rid"].string.isEmpty else { return nil }
            let hot = item["hot"].string
            let count = hot.hasSuffix("万") ? Int((Double(hot.dropLast()) ?? 0) * 10_000) : (Int(hot) ?? 0)
            return LiveRoom(
                platform: .douyu, roomID: item["rid"].string, title: item["roomName"].string,
                streamer: item["nickName"].string, coverURL: imageURL(item["roomSrc"].string),
                viewerCount: count, isLive: item["isLive"].isNull ? nil : item["isLive"].int == 1
            )
        }
        return RoomPage(rooms: rooms, hasMore: rooms.count >= 20)
    }
}
