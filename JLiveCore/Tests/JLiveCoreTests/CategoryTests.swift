import Foundation
import Testing
@testable import JLiveCore

struct CategoryTests {
    @Test func bilibiliCategoryIDsIncludeParentForZeroArea() throws {
        let data = try json(#"[{"id":2,"name":"网游","list":[{"id":"0","name":"全部网游"},{"id":"86","name":"英雄联盟","pic":"//img.example.com/lol.png"},{"id":"86","name":"重复"}]},{"id":3,"name":"手游","list":[{"id":"0","name":"全部手游"}]}]"#)
        let groups = try BilibiliProvider.parseCategories(data)
        #expect(groups.map(\.name) == ["网游", "手游"])
        #expect(groups[0].children.count == 2)
        #expect(groups[0].children[0].id != groups[1].children[0].id)
        #expect(groups[0].children[1].imageURL?.scheme == "https")
        #expect(throws: LiveError.self) { try BilibiliProvider.parseCategories(json("{}")) }
    }

    @Test func bilibiliCategoryRoomsStayInsideTheAreaAndPageByCount() throws {
        let game = LiveCategory(platform: .bilibili, categoryID: "86", parentID: "2", name: "英雄联盟")
        let everyGame = LiveCategory(platform: .bilibili, categoryID: "0", parentID: "2", name: "全部网游")
        let data = try json(#"{"count":61,"list":[{"roomid":1,"title":"上分","uname":"甲","area_v2_id":86,"area_v2_parent_id":2,"area_name":"英雄联盟"},{"roomid":2,"title":"对局","uname":"乙","area_v2_id":329,"area_v2_parent_id":2,"area_name":"无畏契约"},{"roomid":3,"title":"唱歌","uname":"丙","area_v2_id":21,"area_v2_parent_id":1,"area_name":"视频唱见"}]}"#)
        let page = try BilibiliProvider.parseCategoryRooms(data, category: game, page: 2)
        #expect(page.rooms.map(\.roomID) == ["1"], "其他分区的直播间不能出现在所选分区里")
        #expect(page.rooms.first?.category == "英雄联盟")
        #expect(page.rooms.first?.isLive == true)
        #expect(page.hasMore)
        #expect(try !BilibiliProvider.parseCategoryRooms(data, category: game, page: 3).hasMore)
        #expect(try BilibiliProvider.parseCategoryRooms(data, category: everyGame, page: 1).rooms.map(\.roomID) == ["1", "2"])
        // A page past the end is empty even though the count is larger.
        #expect(try !BilibiliProvider.parseCategoryRooms(json(#"{"count":175,"list":[]}"#), category: game, page: 2).hasMore)
        // Without area fields or a count the rooms are kept, and a short page ends the list.
        let plain = try BilibiliProvider.parseCategoryRooms(json(#"{"list":[{"roomid":1,"title":"游戏","uname":"主播"}]}"#), category: game, page: 1)
        #expect(plain.rooms.count == 1)
        #expect(!plain.hasMore)
        #expect(throws: LiveError.self) { try BilibiliProvider.parseCategoryRooms(json("{}"), category: game, page: 1) }
    }

    @Test func huyaDecodesCompoundIDsAndOmitsHiddenCategories() throws {
        let group = try HuyaProvider.parseCategoryGroup(json(#"{"status":200,"data":[{"gid":{"value":"1,2"},"gameFullName":"英雄联盟"},{"gid":862.0,"gameFullName":"CS2"},{"gid":1,"gameFullName":"重复"},{"gid":9,"gameFullName":"隐藏","isHide":1}]}"#), id: "1", name: "网游")
        #expect(group.children.map(\.categoryID) == ["1", "862"])
        #expect(group.children.allSatisfy { $0.parentID == "1" })
        #expect(group.children[0].imageURL?.lastPathComponent == "1-MS.jpg")
    }

    @Test func douyuAssociatesChildrenWithParentsAndFiltersNonRooms() throws {
        let groups = try DouyuProvider.parseCategories(json(#"{"code":0,"data":{"cate1Info":[{"cate1Id":15,"cate1Name":"单机"},{"cate1Id":1,"cate1Name":"网游"}],"cate2Info":[{"cate1Id":1,"cate2Id":1,"cate2Name":"英雄联盟"},{"cate1Id":15,"cate2Id":9,"cate2Name":"主机游戏"}]}}"#))
        #expect(groups.map(\.id) == ["1", "15"])
        #expect(groups[0].children.map(\.name) == ["英雄联盟"])
        let rooms = try DouyuProvider.parseRooms(json(#"{"code":0,"data":{"rl":[{"type":2,"rid":99},{"type":1,"rid":1,"rn":"游戏","nn":"主播"}],"pgcnt":2}}"#), page: 1)
        #expect(rooms.rooms.map(\.roomID) == ["1"])
        #expect(rooms.hasMore)
    }

    @Test func douyinReadsSplitFlightStateAndKeepsPartitionType() throws {
        let state = #"{"categoryData":[{"partition":{"id_str":"103","type":4,"title":"游戏 [直播]"},"sub_partition":[{"partition":{"id_str":"1010014","type":1,"title":"英雄联盟"},"sub_partition":[]}]}]}"#
        let split = state.index(state.startIndex, offsetBy: 42)
        let html = try flight(String(state[..<split])) + flight(String(state[split...]))
        let groups = try DouyinProvider.parseCategoriesHTML(html)
        #expect(try DouyinProvider.parseCategoriesHTML(html.replacingOccurrences(of: "__next_f", with: "__pace_f")) == groups)
        #expect(groups[0].children.map(\.categoryID) == ["103,4", "1010014,1"])
        #expect(groups[0].children[0].name == "游戏 [直播]")
        #expect(groups[0].children[1].parentID == "103,4")
        #expect(throws: LiveError.self) { try DouyinProvider.parseCategoriesHTML("<html>风控</html>") }
    }

    @Test func douyinReadsCategoriesAndRoomStateFromLargeEscapedFlightChunks() throws {
        let prefix = String(repeating: "直播 [\"\\]", count: 30_000)
        let state = #"{"categoryData":[{"partition":{"id_str":"101","type":4,"title":"聊天"},"sub_partition":[]}],"roomInfo":{"room":{"id_str":"42","title":"直播"}}}"#
        let html = try flight(prefix + state).replacingOccurrences(of: "__next_f", with: "__pace_f")
        let groups = try DouyinProvider.parseCategoriesHTML(html)
        #expect(groups.first?.children.first?.categoryID == "101,4")
        #expect(try DouyinProvider.parseRoomHTML(html)["id_str"].string == "42")
    }

    @Test func categoryRequestsCarryPlatformIDsAndPagination() async throws {
        let client = CategoryRoutingClient()
        let providers: [any LiveProvider] = [BilibiliProvider(client: client), HuyaProvider(client: client), DouyuProvider(client: client), DouyinProvider(client: client)]
        let categories = [
            LiveCategory(platform: .bilibili, categoryID: "86", parentID: "2", name: "英雄联盟"),
            LiveCategory(platform: .huya, categoryID: "1", parentID: "1", name: "英雄联盟"),
            LiveCategory(platform: .douyu, categoryID: "1", parentID: "1", name: "英雄联盟"),
            LiveCategory(platform: .douyin, categoryID: "1010014,1", parentID: "103,4", name: "英雄联盟")
        ]
        for (provider, category) in zip(providers, categories) { _ = try await provider.categoryRooms(category: category, page: 2) }
        let urls = await client.urls
        func query(_ url: URL, _ key: String) -> String? { URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == key }?.value }
        let bili = try #require(urls.first { $0.path == "/room/v3/area/getRoomList" })
        #expect(query(bili, "parent_area_id") == "2")
        #expect(query(bili, "area_id") == "86")
        #expect(query(bili, "page") == "2")
        #expect(!urls.contains { $0.path.hasSuffix("second/getListByArea") }, "推荐列表接口不按分区过滤，不能用于分区")
        let huya = try #require(urls.first { $0.path == "/cache.php" })
        #expect(query(huya, "gameId") == "1")
        #expect(query(huya, "page") == "2")
        #expect(urls.contains { $0.path == "/gapi/rkc/directory/mixList/2_1/2" })
        let douyin = try #require(urls.first { $0.path.contains("partition/detail") })
        #expect(query(douyin, "partition") == "1010014")
        #expect(query(douyin, "partition_type") == "1")
        #expect(query(douyin, "offset") == "15")
        let service = LiveService(providers: providers)
        await #expect(throws: LiveError.self) { try await service.discover(platforms: [.huya], category: categories[0]) }
    }

    @Test func directoryCacheAvoidsRepeatRequestsAndCanRefresh() async throws {
        let provider = CategoryProviderFixture()
        let service = LiveService(providers: [provider])
        _ = try await service.categories(platform: .huya)
        _ = try await service.categories(platform: .huya)
        #expect(await provider.requests == 1)
        _ = try await service.categories(platform: .huya, refreshing: true)
        #expect(await provider.requests == 2)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JLIVE_CATEGORY_LIVE_TESTS"] == "1"), .timeLimit(.minutes(3)))
    func livePlatformCategoriesAndRoomLists() async throws {
        let service = LiveService.standard()
        for platform in LivePlatform.allCases {
            let groups = try await service.categories(platform: platform)
            #expect(!groups.isEmpty)
            let all = groups.flatMap(\.children)
            let first = try #require(all.first { $0.name == "英雄联盟" } ?? all.first)
            let second = try #require(all.first { $0.name == "王者荣耀" } ?? all.last)
            let recommended = Set(try await service.discover(platforms: [platform]).rooms.map(\.id))
            var lists: [Set<String>] = []
            // A list that merely has rooms proves nothing: it must follow the selected category.
            for category in [first, second] {
                let result = try await service.discover(platforms: [platform], category: category)
                #expect(result.issues.isEmpty)
                #expect(!result.rooms.isEmpty)
                #expect(result.rooms.allSatisfy { $0.platform == platform })
                let ids = Set(result.rooms.map(\.id))
                #expect(ids != recommended, "\(platform.shortName)的\(category.name)分区返回了推荐列表")
                // Douyin does not name the category of a room; the other platforms must name the selected one.
                let named = result.rooms.filter { !$0.category.isEmpty }
                let matching = named.filter { $0.category == category.name }.count
                #expect(named.isEmpty || matching * 2 > named.count, "\(platform.shortName)的\(category.name)分区里多数直播间属于其他分区")
                print("\(platform.shortName) \(category.name)：\(result.rooms.count) 个直播间，\(matching)/\(named.count) 个标注为该分区，与推荐重合 \(ids.intersection(recommended).count) 个，例如「\(result.rooms[0].title.prefix(18))」")
                lists.append(ids)
                if !result.platformsWithMore.isEmpty {
                    let next = try await service.discover(platforms: [platform], page: 2, category: category)
                    #expect(next.issues.isEmpty)
                    #expect(!next.rooms.isEmpty)
                    #expect(Set(next.rooms.map(\.id)) != ids, "第二页不能重复第一页")
                    print("\(platform.shortName) \(category.name)第二页：\(next.rooms.count) 个直播间")
                }
            }
            #expect(lists[0].isDisjoint(with: lists[1]), "\(platform.shortName)的两个分区返回了相同的直播间")
        }
    }

    private func json(_ source: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8)) }
    private func flight(_ source: String) throws -> String {
        "<script>self.__next_f.push([1,\(String(decoding: try JSONEncoder().encode(source), as: UTF8.self))])</script>"
    }
}

private actor CategoryRoutingClient: HTTPRequesting {
    var urls: [URL] = []
    func get(_ url: URL, headers: [String: String]) async throws -> JSONValue {
        urls.append(url)
        let source: String
        if url.path.contains("finger/spi") { source = #"{"data":{"b_3":"guest","b_4":"guest4"}}"# }
        else if url.path.contains("interface/nav") { source = #"{"data":{"wbi_img":{"img_url":"https://a.com/12345678901234567890123456789012.png","sub_url":"https://a.com/12345678901234567890123456789012.png"}}}"# }
        else if url.host == "www.huya.com" { source = #"{"status":200,"data":{"datas":[],"totalPage":2}}"# }
        else if url.host == "www.douyu.com" { source = #"{"error":0,"data":{"rl":[],"pgcnt":2}}"# }
        else if url.host == "live.douyin.com" { source = #"{"status_code":0,"data":{"data":[]}}"# }
        else { source = #"{"code":0,"data":{"list":[],"has_more":0}}"# }
        return try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8))
    }
    func text(_ url: URL, headers: [String: String]) async throws -> String { "<html></html>" }
}

private actor CategoryProviderFixture: LiveProvider {
    nonisolated let platform = LivePlatform.huya
    var requests = 0
    func categories() async throws -> [LiveCategoryGroup] {
        requests += 1
        return [LiveCategoryGroup(id: "1", name: "网游", children: [LiveCategory(platform: .huya, categoryID: "1", parentID: "1", name: "英雄联盟")])]
    }
    func recommendations(page: Int) async throws -> RoomPage { RoomPage(rooms: [], hasMore: false) }
    func search(keyword: String, page: Int) async throws -> RoomPage { try await recommendations(page: page) }
}
