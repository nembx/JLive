// Category structure and platform mappings adapted from dart_simple_live.
// Copyright (C) 2023-2025 xiaoyaocz. GPL-3.0-or-later. See LICENSE.
import Foundation

public struct LiveCategoryGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let children: [LiveCategory]
    public init(id: String, name: String, children: [LiveCategory]) {
        self.id = id
        self.name = name
        self.children = children
    }
}

public struct LiveCategory: Identifiable, Hashable, Sendable {
    public let platform: LivePlatform
    public let categoryID: String
    public let parentID: String
    public let name: String
    public let imageURL: URL?
    public var id: String { "\(platform.id):\(parentID):\(categoryID)" }
    public init(platform: LivePlatform, categoryID: String, parentID: String, name: String, imageURL: URL? = nil) {
        self.platform = platform
        self.categoryID = categoryID
        self.parentID = parentID
        self.name = name
        self.imageURL = imageURL
    }
}

actor CategoryCache {
    private var saved: [LivePlatform: (groups: [LiveCategoryGroup], date: Date)] = [:]

    func groups(for provider: any LiveProvider, refreshing: Bool) async throws -> [LiveCategoryGroup] {
        if !refreshing, let value = saved[provider.platform], Date().timeIntervalSince(value.date) < 3_600 {
            return value.groups
        }
        let groups = try await provider.categories()
        try Task.checkCancellation()
        if !groups.isEmpty { saved[provider.platform] = (groups, Date()) }
        return groups
    }
}
