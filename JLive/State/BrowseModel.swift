import Foundation
import JLiveCore

@MainActor @Observable
final class BrowseModel {
    var selectedPlatform: LivePlatform?
    var keyword = ""
    private(set) var rooms: [LiveRoom] = []
    private(set) var issues: [PlatformIssue] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var hasLoaded = false
    private var page = 1
    private var morePlatforms: Set<LivePlatform> = []
    private var generation = UUID()
    @ObservationIgnored private let service: LiveService

    var hasMore: Bool { !morePlatforms.isEmpty }
    var requestKey: String { "\(selectedPlatform?.id ?? "all"):\(keyword)" }

    init(service: LiveService) { self.service = service }

    func load(isSearch: Bool) async {
        let token = UUID()
        generation = token
        rooms = []
        issues = []
        errorMessage = nil
        morePlatforms = []
        hasLoaded = false
        isLoading = false
        isLoadingMore = false
        page = 1
        guard selectedPlatform != .douyin else { return }
        guard !isSearch || !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        defer { if generation == token { isLoading = false } }
        do {
            if isSearch { try await Task.sleep(for: .milliseconds(350)) }
            let platforms = selectedPlatform.map { Set([$0]) } ?? Set(LivePlatform.allCases.filter(\.supportsDiscovery))
            let result = try await service.discover(platforms: platforms, keyword: isSearch ? keyword : "")
            guard generation == token else { return }
            rooms = result.rooms
            issues = result.issues
            morePlatforms = result.platformsWithMore
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
            let result = try await service.discover(platforms: morePlatforms, page: page + 1, keyword: isSearch ? keyword : "")
            guard generation == token else { return }
            var seen = Set(rooms.map(\.id))
            rooms.append(contentsOf: result.rooms.filter { seen.insert($0.id).inserted })
            morePlatforms = result.platformsWithMore
            issues = issues.filter { !result.issues.map(\.platform).contains($0.platform) } + result.issues
            page += 1
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
