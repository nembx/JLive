import Foundation

public protocol LiveProvider: Sendable {
    var platform: LivePlatform { get }
    func recommendations(page: Int) async throws -> RoomPage
    func search(keyword: String, page: Int) async throws -> RoomPage
    func detail(room: LiveRoom) async throws -> LiveRoom
    func playback(roomID: String, quality: Int?) async throws -> PlaybackInfo
    func chat(roomID: String) async throws -> LiveChatEndpoint
}

public extension LiveProvider {
    func detail(room: LiveRoom) async throws -> LiveRoom { room }
    func playback(roomID: String, quality: Int?) async throws -> PlaybackInfo { throw LiveError.unsupported }
    func chat(roomID: String) async throws -> LiveChatEndpoint { throw LiveError.unsupported }
}

public struct PlatformIssue: Identifiable, Sendable {
    public let platform: LivePlatform
    public let message: String
    public var id: String { platform.id }
}

public struct DiscoveryResult: Sendable {
    public let rooms: [LiveRoom]
    public let platformsWithMore: Set<LivePlatform>
    public let issues: [PlatformIssue]
}

public struct LiveService: Sendable {
    private let providers: [LivePlatform: any LiveProvider]

    public init(providers: [any LiveProvider]) {
        self.providers = Dictionary(providers.map { ($0.platform, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public static func standard() -> LiveService {
        let client = HTTPClient()
        return LiveService(providers: [BilibiliProvider(client: client), HuyaProvider(client: client), DouyuProvider(client: client)])
    }

    public func discover(platforms: Set<LivePlatform>, page: Int = 1, keyword: String = "") async throws -> DiscoveryResult {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = await withTaskGroup(of: ProviderResult.self) { group in
            for platform in LivePlatform.allCases where platforms.contains(platform) {
                guard let provider = providers[platform] else { continue }
                group.addTask {
                    do {
                        let result = try await keyword.isEmpty
                            ? provider.recommendations(page: page)
                            : provider.search(keyword: keyword, page: page)
                        return ProviderResult(platform: platform, page: result, error: nil)
                    } catch {
                        return ProviderResult(platform: platform, page: nil, error: error.localizedDescription)
                    }
                }
            }
            var results: [ProviderResult] = []
            for await result in group { results.append(result) }
            return results
        }
        try Task.checkCancellation()
        let sorted = results.sorted {
            LivePlatform.allCases.firstIndex(of: $0.platform)! < LivePlatform.allCases.firstIndex(of: $1.platform)!
        }
        // Interleave providers; popularity metrics have different meanings on each platform.
        let largestPage = sorted.map { $0.page?.rooms.count ?? 0 }.max() ?? 0
        var rooms: [LiveRoom] = []
        var seen: Set<String> = []
        for index in 0..<largestPage {
            for result in sorted {
                if let page = result.page, index < page.rooms.count, seen.insert(page.rooms[index].id).inserted {
                    rooms.append(page.rooms[index])
                }
            }
        }
        return DiscoveryResult(
            rooms: rooms,
            platformsWithMore: Set(results.filter { $0.page?.hasMore == true }.map(\.platform)),
            issues: sorted.compactMap { result in
                result.error.map { PlatformIssue(platform: result.platform, message: $0) }
            }
        )
    }

    public func detail(_ room: LiveRoom) async throws -> LiveRoom {
        guard let provider = providers[room.platform] else { return room }
        return try await provider.detail(room: room)
    }

    public func playback(_ room: LiveRoom, quality: Int? = nil) async throws -> PlaybackInfo {
        guard let provider = providers[room.platform] else { throw LiveError.unsupported }
        return try await provider.playback(roomID: room.roomID, quality: quality)
    }

    public func chat(_ room: LiveRoom) async throws -> LiveChatEndpoint {
        guard let provider = providers[room.platform] else { throw LiveError.unsupported }
        return try await provider.chat(roomID: room.roomID)
    }

    public func setBilibiliCredentials(_ credentials: BilibiliCredentials?) async {
        await (providers[.bilibili] as? BilibiliProvider)?.setCredentials(credentials)
    }

    public func sendChat(_ text: String, room: LiveRoom) async throws {
        guard room.platform == .bilibili, let provider = providers[.bilibili] as? BilibiliProvider else { throw LiveError.unsupported }
        try await provider.sendChat(roomID: room.roomID, text: text)
    }

    private struct ProviderResult: Sendable {
        let platform: LivePlatform
        let page: RoomPage?
        let error: String?
    }
}
