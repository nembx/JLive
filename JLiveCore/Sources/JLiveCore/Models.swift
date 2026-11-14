import Foundation

public enum LivePlatform: String, CaseIterable, Codable, Identifiable, Sendable {
    case bilibili, huya, douyu, douyin

    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .bilibili: "哔哩哔哩"
        case .huya: "虎牙"
        case .douyu: "斗鱼"
        case .douyin: "抖音"
        }
    }
    public var shortName: String {
        switch self {
        case .bilibili: "B站"
        default: name
        }
    }
    public var homeURL: URL {
        switch self {
        case .bilibili: URL(string: "https://live.bilibili.com")!
        case .huya: URL(string: "https://www.huya.com")!
        case .douyu: URL(string: "https://www.douyu.com")!
        case .douyin: URL(string: "https://live.douyin.com")!
        }
    }
    public var supportsDiscovery: Bool { true }
    public var supportsSearch: Bool { true }
    public var supportsNativePlayback: Bool { true }
    public var supportsChat: Bool { true }

    public func roomURL(_ roomID: String) -> URL {
        homeURL.appendingPathComponent(roomID)
    }
}

public struct LiveRoom: Identifiable, Codable, Hashable, Sendable {
    public let platform: LivePlatform
    public let roomID: String
    public var title: String
    public var streamer: String
    public var coverURL: URL?
    public var avatarURL: URL?
    public var viewerCount: Int
    public var category: String
    public var isLive: Bool?

    public var id: String { "\(platform.rawValue):\(roomID)" }
    public var webURL: URL { platform.roomURL(roomID) }
    public var popularity: String {
        if viewerCount >= 10_000 {
            return String(format: "%.1f万", Double(viewerCount) / 10_000)
        }
        return viewerCount.formatted()
    }

    public init(
        platform: LivePlatform, roomID: String, title: String, streamer: String,
        coverURL: URL? = nil, avatarURL: URL? = nil, viewerCount: Int = 0,
        category: String = "", isLive: Bool? = nil
    ) {
        self.platform = platform
        self.roomID = roomID
        self.title = title
        self.streamer = streamer
        self.coverURL = coverURL
        self.avatarURL = avatarURL
        self.viewerCount = viewerCount
        self.category = category
        self.isLive = isLive
    }
}

public struct RoomPage: Sendable {
    public let rooms: [LiveRoom]
    public let hasMore: Bool
    public init(rooms: [LiveRoom], hasMore: Bool) {
        self.rooms = rooms
        self.hasMore = hasMore
    }
}

public struct StreamQuality: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public init(id: Int, name: String) { self.id = id; self.name = name }
}

public struct StreamLine: Identifiable, Equatable, Sendable {
    public let url: URL
    public var id: String { url.absoluteString }
    public init(url: URL) { self.url = url }
}

public struct PlaybackInfo: Sendable {
    public let lines: [StreamLine]
    public let qualities: [StreamQuality]
    public let currentQuality: Int
    public let headers: [String: String]
    public init(lines: [StreamLine], qualities: [StreamQuality], currentQuality: Int, headers: [String: String]) {
        self.lines = lines
        self.qualities = qualities
        self.currentQuality = currentQuality
        self.headers = headers
    }
}

public enum LiveError: LocalizedError, Sendable {
    case invalidResponse
    case http(Int)
    case platform(String)
    case loginRequired(LivePlatform)
    case offline
    case noPlayableStream
    case unsupported
    case invalidRoomLink

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "平台返回的数据格式发生变化，请稍后重试。"
        case .http(let status): "网络请求失败（\(status)），请稍后重试。"
        case .platform(let message): "平台暂时无法访问：\(message)"
        case .loginRequired(let platform): "请先登录\(platform.name)，再继续搜索。"
        case .offline: "主播还未开播，收藏后下次再来看看。"
        case .noPlayableStream: "暂时没有可播放的线路，可以前往平台观看。"
        case .unsupported: "这个功能暂未接入，可以前往平台官网使用。"
        case .invalidRoomLink: "请输入 B站、虎牙、斗鱼或抖音的直播间链接。"
        }
    }
}

public enum RoomLinkParser {
    public static func parse(_ text: String, platform: LivePlatform? = nil) throws -> LiveRoom {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPlatform: LivePlatform
        let roomID: String
        if let url = URL(string: input), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host?.lowercased(),
           let site = LivePlatform.allCases.first(where: {
               guard let domain = $0.homeURL.host else { return false }
               let root = domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
               return host == root || host.hasSuffix("." + root)
           }) {
            let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if site == .bilibili, components.first == "blanc" {
                guard components.count == 2 else { throw LiveError.invalidRoomLink }
                roomID = components[1]
            } else {
                guard components.count == 1 else { throw LiveError.invalidRoomLink }
                roomID = components[0]
            }
            resolvedPlatform = site
        } else if let platform, !input.isEmpty,
                  input.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) {
            resolvedPlatform = platform
            roomID = input
        } else {
            throw LiveError.invalidRoomLink
        }
        guard !roomID.isEmpty, roomID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
              !["directory", "search", "category", "all"].contains(roomID.lowercased()),
              (resolvedPlatform == .huya || roomID.allSatisfy(\.isNumber)) else {
            throw LiveError.invalidRoomLink
        }
        return LiveRoom(platform: resolvedPlatform, roomID: roomID, title: "直播间 \(roomID)", streamer: resolvedPlatform.name)
    }
}
