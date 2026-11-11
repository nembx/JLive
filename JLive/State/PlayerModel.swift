import Foundation
import Observation
@preconcurrency import AVFoundation
import JLiveCore

@MainActor @Observable
final class PlayerModel {
    private(set) var room: LiveRoom
    let player = AVPlayer()
    private(set) var playbackInfo: PlaybackInfo?
    private(set) var isResolving = false
    private(set) var isPreparing = false
    private(set) var errorMessage: String?
    private(set) var selectedLine = 0
    private(set) var selectedQuality: Int?
    private var generation = UUID()
    private var attemptedLines: Set<Int> = []
    @ObservationIgnored private let service: LiveService
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var failureObserver: NSObjectProtocol?

    init(room: LiveRoom, service: LiveService) {
        self.room = room
        self.service = service
        player.allowsExternalPlayback = true
        #if DEBUG
        // Lets simulator checks run without playing the stream through the Mac's speakers.
        if CommandLine.arguments.contains("--muted") { player.isMuted = true }
        #endif
    }

    func load(quality: Int? = nil) async {
        stop()
        let token = generation
        errorMessage = nil
        playbackInfo = nil
        guard room.platform.supportsNativePlayback else { return }
        isResolving = true
        defer { if generation == token { isResolving = false } }
        do {
            // Metadata failure should not prevent trying an otherwise valid room URL.
            if let detail = try? await service.detail(room) {
                guard generation == token, !Task.isCancelled else { return }
                room = detail
            }
            try Task.checkCancellation()
            guard room.isLive != false else { throw LiveError.offline }
            let info = try await service.playback(room, quality: quality)
            guard generation == token else { return }
            playbackInfo = info
            selectedQuality = info.currentQuality
            selectedLine = 0
            isResolving = false
            playLine(0)
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            isPreparing = false
        }
    }

    func playLine(_ index: Int) {
        attemptedLines = []
        startLine(index)
    }

    private func startLine(_ index: Int) {
        guard let info = playbackInfo, info.lines.indices.contains(index) else { return }
        attemptedLines.insert(index)
        statusObservation?.invalidate()
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        selectedLine = index
        errorMessage = nil
        isPreparing = true
        let token = UUID()
        generation = token
        let asset = AVURLAsset(url: info.lines[index].url, options: [
            AVURLAssetHTTPUserAgentKey: HTTPClient.userAgent,
            "AVURLAssetHTTPHeaderFieldsKey": info.headers
        ])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 3
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                switch status {
                case .readyToPlay: self.isPreparing = false
                case .failed:
                    self.handleLineFailure()
                default: break
                }
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.handleLineFailure()
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func handleLineFailure() {
        if let info = playbackInfo, let next = info.lines.indices.first(where: { !attemptedLines.contains($0) }) {
            startLine(next)
        } else {
            isPreparing = false
            errorMessage = "直播线路暂时不可用，请重新加载或前往官网观看。"
        }
    }

    func stop() {
        generation = UUID()
        statusObservation?.invalidate()
        statusObservation = nil
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPreparing = false
        isResolving = false
    }
}
