// Platform category endpoints and fields adapted from dart_simple_live.
// Copyright (C) 2023-2025 xiaoyaocz. GPL-3.0-or-later. See LICENSE.
import Foundation

extension HuyaProvider {
    public func categories() async throws -> [LiveCategoryGroup] {
        let parents = [("1", "网游"), ("2", "单机"), ("8", "娱乐"), ("3", "手游")]
        return try await withThrowingTaskGroup(of: (Int, LiveCategoryGroup).self) { group in
            for (index, parent) in parents.enumerated() {
                group.addTask {
                    let response = try await client.get(try endpoint("https://live.cdn.huya.com/liveconfig/game/bussLive", ["bussType": parent.0]), headers: ["Referer": "https://www.huya.com/"])
                    return (index, try Self.parseCategoryGroup(response, id: parent.0, name: parent.1))
                }
            }
            var result: [(Int, LiveCategoryGroup)] = []
            for try await value in group { result.append(value) }
            return result.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    static func parseCategoryGroup(_ response: JSONValue, id: String, name: String) throws -> LiveCategoryGroup {
        guard response["status"].int == 200 else { throw LiveError.invalidResponse }
        var seen = Set<String>()
        let children = try response["data"].requiredArray().compactMap { item -> LiveCategory? in
            guard item["isHide"].int != 1 else { return nil }
            let gid = item["gid"]["value"].isNull ? item["gid"].string : item["gid"]["value"].string
            let value = String(gid.split(separator: ",").first ?? "")
            let title = item["gameFullName"].string
            guard !value.isEmpty, !title.isEmpty, seen.insert(value).inserted else { return nil }
            return LiveCategory(platform: .huya, categoryID: value, parentID: id, name: title,
                imageURL: imageURL("https://huyaimg.msstatic.com/cdnimage/game/\(value)-MS.jpg"))
        }
        return LiveCategoryGroup(id: id, name: name, children: children)
    }

    public func categoryRooms(category: LiveCategory, page: Int) async throws -> RoomPage {
        guard category.platform == platform else { throw LiveError.invalidResponse }
        let response = try await client.get(try endpoint("https://www.huya.com/cache.php", [
            "m": "LiveList", "do": "getLiveListByPage", "tagAll": "0", "gameId": category.categoryID, "page": String(max(1, page))
        ]), headers: ["Referer": "https://www.huya.com/"])
        return try Self.parseRooms(response, page: max(1, page))
    }
}

extension DouyuProvider {
    public func categories() async throws -> [LiveCategoryGroup] {
        let response = try await client.get(URL(string: "https://m.douyu.com/api/cate/list")!, headers: ["Referer": "https://m.douyu.com/"])
        return try Self.parseCategories(response)
    }

    static func parseCategories(_ response: JSONValue) throws -> [LiveCategoryGroup] {
        guard !response["code"].isNull, response["code"].int == 0 else { throw LiveError.invalidResponse }
        let data = response["data"]
        let allChildren = try data["cate2Info"].requiredArray()
        return try data["cate1Info"].requiredArray().compactMap { item in
            let parent = item["cate1Id"].string, title = item["cate1Name"].string
            guard !parent.isEmpty, !title.isEmpty else { return nil }
            var seen = Set<String>()
            let children = allChildren.compactMap { child -> LiveCategory? in
                let id = child["cate2Id"].string, name = child["cate2Name"].string
                guard child["cate1Id"].string == parent, !id.isEmpty, !name.isEmpty, seen.insert(id).inserted else { return nil }
                return LiveCategory(platform: .douyu, categoryID: id, parentID: parent, name: name, imageURL: imageURL(child["icon"].string))
            }
            return LiveCategoryGroup(id: parent, name: title, children: children)
        }.sorted { (Int($0.id) ?? 0) < (Int($1.id) ?? 0) }
    }

    public func categoryRooms(category: LiveCategory, page: Int) async throws -> RoomPage {
        guard category.platform == platform, category.categoryID.allSatisfy(\.isNumber), !category.categoryID.isEmpty else { throw LiveError.invalidResponse }
        let response = try await client.get(try endpoint("https://www.douyu.com/gapi/rkc/directory/mixList/2_\(category.categoryID)/\(max(1, page))"), headers: ["Referer": "https://www.douyu.com/"])
        return try Self.parseRooms(response, page: max(1, page))
    }
}
