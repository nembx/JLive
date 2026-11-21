import AVKit
@preconcurrency import KSPlayer

/// FFmpeg demuxing and VideoToolbox decoding for the desktop FLV streams.
/// HLS continues to use the existing AVPlayer.
@MainActor
final class FLVPlayback: MediaPlayerDelegate {
    private let engine: KSMEPlayer
    private let videoView: UIView
    var onChange: ((FLVPlayback) -> Void)?
    var onFailure: (() -> Void)?

    var view: UIView { videoView }
    var size: CGSize { engine.naturalSize }
    var isReady: Bool { engine.isReadyToPlay }
    var isPlaying: Bool { engine.isReadyToPlay && engine.isPlaying && engine.loadState == .playable }
    var isBuffering: Bool { engine.isPlaying && engine.loadState == .loading }
    var isMuted: Bool {
        get { engine.isMuted }
        set { engine.isMuted = newValue }
    }
    var pictureInPictureController: AVPictureInPictureController? { engine.pipController }

    init(url: URL, headers: [String: String], muted: Bool) {
        KSOptions.logLevel = .error
        let options = KSOptions()
        options.registerRemoteControll = false
        options.preferredForwardBufferDuration = 3
        options.appendHeader(headers)
        options.userAgent = headers["User-Agent"]
        engine = KSMEPlayer(url: url, options: options)
        videoView = engine.view ?? UIView()
        engine.contentMode = .scaleAspectFit
        engine.isMuted = muted
        engine.delegate = self
    }

    func start(playing: Bool) {
        engine.prepareToPlay()
        if playing { engine.play() }
    }
    func play() { engine.play(); onChange?(self) }
    func pause() { engine.pause(); onChange?(self) }
    func stop() {
        onChange = nil
        onFailure = nil
        engine.delegate = nil
        engine.pipController?.stopPictureInPicture()
        engine.shutdown()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func readyToPlay(player: some MediaPlayerProtocol) {
        onChange?(self)
    }
    func changeLoadState(player: some MediaPlayerProtocol) {
        UIApplication.shared.isIdleTimerDisabled = engine.isPlaying
        onChange?(self)
    }
    func changeBuffering(player: some MediaPlayerProtocol, progress: Int) {}
    func playBack(player: some MediaPlayerProtocol, loopCount: Int) {}
    func finish(player: some MediaPlayerProtocol, error: (any Error)?) {
        UIApplication.shared.isIdleTimerDisabled = false
        onFailure?()
    }
}
