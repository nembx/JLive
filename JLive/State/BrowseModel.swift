import Foundation
import JLiveCore

@MainActor @Observable
final class BrowseModel {
    /// Live lists change constantly; a list older than this is refreshed in place when it is shown again.
    static let cacheLifetime: TimeInterval = 600

    var selectedPlatform: LivePlatform?
    private var platformCategories: [LivePlatform: LiveCategory] = [:]
    var selectedCategory: LiveCategory? {
        get { selectedPlatform.flatMap { platformCategories[$0] } }
        set {
            guard let platform = selectedPlatform, newValue == nil || newValue?.platform == platform else { return }
            platformCategories[platform] = newValue
        }
    }
    var keyword = ""
    private(set) var rooms: [LiveRoom] = []
    private(set) var issues: [PlatformIssue] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private(set) var hasLoaded = false
    private var page = 1
    private var morePlatforms: Set<LivePlatform> = []
    private var generation = UUID()
    private var shownKey: String?
    private var cache: [String: Snapshot] = [:]
    @ObservationIgnored private let service: LiveService
    @ObservationIgnored private let now: () -> Date

    private struct Snapshot {
        let rooms: [LiveRoom]
        let issues: [PlatformIssue]
        let morePlatforms: Set<LivePlatform>
        let page: Int
        let loadedAt: Date
    }

    var hasMore: Bool { !morePlatforms.isEmpty }
    var requestKey: String { "\(selectedPlatform?.id ?? "all"):\(selectedCategory?.id ?? "recommendations"):\(keyword)" }

    init(service: LiveService, platform: LivePlatform? = .bilibili, now: @escaping () -> Date = Date.init) {
        self.service = service
        selectedPlatform = platform
        self.now = now
    }

    /// Called when the page appears or its platform / keyword changes. Returning to a list
    /// that was loaded recently shows it again without another request.
    func loadIfNeeded(isSearch: Bool) async {
        let key = requestKey
        if let snapshot = cache[key] {
            if shownKey != key { show(snapshot, key: key) }
            if now().timeIntervalSince(snapshot.loadedAt) < Self.cacheLifetime { return }
        }
        await load(isSearch: isSearch)
    }

    /// Pull-to-refresh. SwiftUI may cancel the refresh action while the page re-renders,
    /// so the request runs in its own task and always finishes.
    func refresh(isSearch: Bool) async {
        isRefreshing = true
        await Task { await load(isSearch: isSearch) }.value
        isRefreshing = false
    }

    /// Requests the first page. A list already on screen for the same request stays visible until the new one arrives.
    func load(isSearch: Bool) async {
        let key = requestKey
        let token = UUID()
        generation = token
        errorMessage = nil
        isLoadingMore = false
        if shownKey != key { clear() }
        shownKey = key
        guard !isSearch || selectedPlatform?.supportsSearch != false,
              !isSearch || !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clear()
            isLoading = false
            return
        }
        isLoading = true
        defer { if generation == token { isLoading = false } }
        do {
            let platforms = selectedPlatform.map { Set([$0]) } ?? Set(LivePlatform.allCases.filter { isSearch ? $0.supportsSearch : $0.supportsDiscovery })
            let result = try await service.discover(platforms: platforms, keyword: isSearch ? keyword : "", category: isSearch ? nil : selectedCategory)
            guard generation == token else { return }
            let failed = result.rooms.isEmpty && !result.issues.isEmpty
            if failed && !rooms.isEmpty {
                // A refresh that every platform rejected keeps the list the viewer already has.
                issues = result.issues
            } else {
                rooms = result.rooms
                issues = result.issues
                morePlatforms = result.platformsWithMore
                page = 1
                // Failures are not remembered, so coming back to the page tries again.
                cache[key] = failed ? nil : snapshot(loadedAt: now())
            }
            hasLoaded = true
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            hasLoaded = true
        }
    }

    func loadMore(isSearch: Bool) async {
        guard !isLoading, !isLoadingMore, hasMore else { return }
        let token = generation
        isLoadingMore = true
        defer { if generation == token { isLoadingMore = false } }
        do {
            let result = try await service.discover(platforms: morePlatforms, page: page + 1, keyword: isSearch ? keyword : "", category: isSearch ? nil : selectedCategory)
            guard generation == token else { return }
            var seen = Set(rooms.map(\.id))
            rooms.append(contentsOf: result.rooms.filter { seen.insert($0.id).inserted })
            morePlatforms = result.platformsWithMore
            issues = issues.filter { !result.issues.map(\.platform).contains($0.platform) } + result.issues
            page += 1
            if let key = shownKey, let loadedAt = cache[key]?.loadedAt { cache[key] = snapshot(loadedAt: loadedAt) }
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func snapshot(loadedAt: Date) -> Snapshot {
        Snapshot(rooms: rooms, issues: issues, morePlatforms: morePlatforms, page: page, loadedAt: loadedAt)
    }

    private func show(_ snapshot: Snapshot, key: String) {
        // Invalidates a request still running for the list being replaced.
        generation = UUID()
        shownKey = key
        rooms = snapshot.rooms
        issues = snapshot.issues
        morePlatforms = snapshot.morePlatforms
        page = snapshot.page
        errorMessage = nil
        isLoading = false
        isLoadingMore = false
        hasLoaded = true
    }

    private func clear() {
        rooms = []
        issues = []
        morePlatforms = []
        page = 1
        hasLoaded = false
    }
}
