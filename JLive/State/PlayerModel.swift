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
    private(set) var qualitySwitchMessage: String?
    private(set) var pendingQuality: Int?
    var qualityLabel: String {
        if isResolving, pendingQuality != nil { return "切换中…" }
        return playbackInfo?.qualities.first { $0.id == selectedQuality }?.name ?? "画质"
    }
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var videoAspectRatio = 16.0 / 9.0
    var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue; muteState = newValue }
    }
    private(set) var muteState = false
    private var wantsPlayback = true
    private var suspended = false
    private var generation = UUID()
    private var attemptedLines: Set<Int> = []
    @ObservationIgnored private let service: LiveService
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var sizeObservation: NSKeyValueObservation?
    @ObservationIgnored private var failureObserver: NotificationLifetime?
    @ObservationIgnored private var timeObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var interruptionObserver: NotificationLifetime?

    init(room: LiveRoom, service: LiveService) {
        self.room = room
        self.service = service
        player.allowsExternalPlayback = true
        player.preventsDisplaySleepDuringVideoPlayback = true
        timeObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                self?.isPlaying = status == .playing
                self?.isBuffering = status == .waitingToPlayAtSpecifiedRate
            }
        }
        interruptionObserver = NotificationLifetime(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue { self.player.pause() }
                else if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume), self.wantsPlayback, !self.suspended { self.player.play() }
            }
        })
        #if DEBUG
        // Lets simulator checks run without playing the stream through the Mac's speakers.
        if CommandLine.arguments.contains("--muted") { player.isMuted = true }
        #endif
        muteState = player.isMuted
    }

    func load(quality: Int? = nil, preference: PlaybackQuality? = nil) async {
        let requestedQuality = quality ?? (preference == nil ? selectedQuality : nil)
        let requestedName = playbackInfo?.qualities.first { $0.id == quality }?.name
        let shouldPlay = wantsPlayback
        stop()
        wantsPlayback = shouldPlay
        let token = generation
        errorMessage = nil
        qualitySwitchMessage = nil
        pendingQuality = quality
        guard room.platform.supportsNativePlayback else { return }
        isResolving = true
        defer { if generation == token { isResolving = false; pendingQuality = nil } }
        do {
            await Task.detached(priority: .userInitiated) {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try? AVAudioSession.sharedInstance().setActive(true)
            }.value
            guard generation == token, !Task.isCancelled else { return }
            // Metadata failure should not prevent trying an otherwise valid room URL.
            if let detail = try? await service.detail(room) {
                guard generation == token, !Task.isCancelled else { return }
                room = detail
            }
            try Task.checkCancellation()
            guard room.isLive != false else { throw LiveError.offline }
            var info = try await service.playback(room, quality: requestedQuality)
            guard generation == token, !Task.isCancelled else { return }
            if requestedQuality == nil, let preference,
               let preferred = preference.select(from: info.qualities), preferred.id != info.currentQuality {
                // Keep the default playable stream if the platform cannot supply the preferred tier.
                if let preferredInfo = try? await service.playback(room, quality: preferred.id) { info = preferredInfo }
            }
            guard generation == token, !Task.isCancelled else { return }
            playbackInfo = info
            selectedQuality = info.currentQuality
            pendingQuality = nil
            if let quality {
                let actualName = info.qualities.first { $0.id == info.currentQuality }?.name ?? "平台默认画质"
                if quality == info.currentQuality {
                    qualitySwitchMessage = "已切换至\(actualName)"
                } else {
                    let name = requestedName ?? info.qualities.first { $0.id == quality }?.name ?? "所选画质"
                    qualitySwitchMessage = "\(name)暂不可用，当前为\(actualName)"
                }
            }
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
        sizeObservation?.invalidate()
        failureObserver = nil
        selectedLine = index
        errorMessage = nil
        isPreparing = true
        timeout?.cancel()
        let token = UUID()
        generation = token
        let asset = AVURLAsset(url: info.lines[index].url, options: [
            AVURLAssetHTTPUserAgentKey: info.headers["User-Agent"] ?? HTTPClient.userAgent,
            "AVURLAssetHTTPHeaderFieldsKey": info.headers
        ])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 3
        sizeObservation = item.observe(\.presentationSize, options: [.initial, .new]) { [weak self] item, _ in
            let size = item.presentationSize
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, size.width > 0, size.height > 0 else { return }
                self.videoAspectRatio = size.width / size.height
            }
        }
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                switch status {
                case .readyToPlay: self.isPreparing = false; self.timeout?.cancel()
                case .failed:
                    self.handleLineFailure()
                default: break
                }
            }
        }
        failureObserver = NotificationLifetime(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.handleLineFailure()
            }
        })
        player.replaceCurrentItem(with: item)
        if wantsPlayback, !suspended { player.play() }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.generation == token, self.isPreparing else { return }
            self.handleLineFailure()
        }
    }

    func togglePlayback() {
        wantsPlayback.toggle()
        if wantsPlayback { player.play() } else { player.pause() }
    }

    func suspend() {
        suspended = true
        player.pause()
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        if wantsPlayback, player.currentItem != nil { player.play() }
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
        timeout?.cancel()
        timeout = nil
        generation = UUID()
        statusObservation?.invalidate()
        statusObservation = nil
        sizeObservation?.invalidate()
        sizeObservation = nil
        failureObserver = nil
        failureObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPreparing = false
        isResolving = false
        pendingQuality = nil
    }

}

/// NotificationCenter removal is thread safe; the token owns its cleanup.
private final class NotificationLifetime: @unchecked Sendable {
    let token: any NSObjectProtocol
    init(_ token: any NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}
