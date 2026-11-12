import SwiftUI
import AVKit
import JLiveCore

@MainActor @Observable
final class PlayerPresentation {
    var isFullScreen = false
    var isInPictureInPicture = false
    var canPictureInPicture = false
    var message: String?
}

struct LivePlayerView: UIViewControllerRepresentable {
    let model: PlayerModel
    let chat: ChatModel
    let presentation: PlayerPresentation
    let openWebsite: () -> Void

    func makeUIViewController(context: Context) -> PlayerContainerController {
        PlayerContainerController(model: model, chat: chat, presentation: presentation, openWebsite: openWebsite)
    }
    func updateUIViewController(_ controller: PlayerContainerController, context: Context) {}
    static func dismantleUIViewController(_ controller: PlayerContainerController, coordinator: ()) { controller.cleanup() }
}

/// Reparents the same video surface for full screen, keeping the player, PiP layer and chat alive.
@MainActor
final class PlayerContainerController: UIViewController, @preconcurrency AVPictureInPictureControllerDelegate {
    let model: PlayerModel
    let chat: ChatModel
    let presentation: PlayerPresentation
    let openWebsite: () -> Void
    private var host: UIHostingController<PlayerSurface>?
    private var fullScreen: FullscreenPlayerController?
    private var pip: AVPictureInPictureController?
    private var pipObservation: NSKeyValueObservation?

    init(model: PlayerModel, chat: ChatModel, presentation: PlayerPresentation, openWebsite: @escaping () -> Void) {
        self.model = model; self.chat = chat; self.presentation = presentation; self.openWebsite = openWebsite
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let surface = PlayerSurface(model: model, chat: chat, presentation: presentation,
            toggleFullScreen: { [weak self] in self?.toggleFullScreen() },
            togglePiP: { [weak self] in self?.togglePiP() }, openWebsite: openWebsite,
            onLayer: { [weak self] in self?.configurePiP($0) })
        let host = UIHostingController(rootView: surface)
        host.view.backgroundColor = .black
        self.host = host
        attach(host, to: self)
    }

    private func attach(_ host: UIViewController, to parent: UIViewController) {
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        parent.addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        parent.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: parent.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor)
        ])
        host.didMove(toParent: parent)
    }

    private func toggleFullScreen() {
        guard let host else { return }
        if let fullScreen {
            guard !fullScreen.isBeingDismissed else { return }
            fullScreen.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.attach(host, to: self)
                self.fullScreen = nil
                self.presentation.isFullScreen = false
                self.view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        } else {
            guard presentedViewController == nil else { return }
            presentation.isFullScreen = true
            let full = FullscreenPlayerController()
            full.modalPresentationStyle = .fullScreen
            full.loadViewIfNeeded()
            full.view.backgroundColor = .black
            fullScreen = full
            attach(host, to: full)
            present(full, animated: true) {
                full.setNeedsUpdateOfSupportedInterfaceOrientations()
                full.view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
            }
        }
    }

    private func configurePiP(_ layer: AVPlayerLayer) {
        guard pip == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let controller = AVPictureInPictureController(playerLayer: layer)
        pip = controller
        controller?.delegate = self
        controller?.canStartPictureInPictureAutomaticallyFromInline = false
        pipObservation = controller?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] pip, _ in
            let possible = pip.isPictureInPicturePossible
            Task { @MainActor [weak self] in self?.presentation.canPictureInPicture = possible }
        }
    }
    private func togglePiP() {
        guard let pip else { return }
        if pip.isPictureInPictureActive { pip.stopPictureInPicture() }
        else if pip.isPictureInPicturePossible { pip.startPictureInPicture() }
    }
    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        presentation.isInPictureInPicture = true
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        presentation.isInPictureInPicture = false
        if UIApplication.shared.applicationState != .active { model.suspend() }
    }
    func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: any Error) {
        presentation.isInPictureInPicture = false
        presentation.message = "暂时无法开启画中画，请稍后重试。"
        if UIApplication.shared.applicationState != .active { model.suspend() }
    }
    func pictureInPictureController(_ controller: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(view.window != nil || fullScreen?.view.window != nil)
    }
    func cleanup() {
        pipObservation?.invalidate()
        pip?.stopPictureInPicture()
        pip?.delegate = nil
        pip = nil
        presentation.isInPictureInPicture = false
        host?.view.removeFromSuperview()
        host?.removeFromParent()
        host = nil
    }
}

private final class FullscreenPlayerController: UIViewController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}

private struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer
    let onLayer: (AVPlayerLayer) -> Void
    func makeUIView(context: Context) -> VideoLayerSurface {
        let view = VideoLayerSurface()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "videoSurface"
        view.accessibilityLabel = "直播画面"
        onLayer(view.playerLayer)
        return view
    }
    func updateUIView(_ view: VideoLayerSurface, context: Context) {
        view.playerLayer.player = player
        view.accessibilityValue = player.timeControlStatus == .playing ? "播放中" : "未播放"
    }
    static func dismantleUIView(_ view: VideoLayerSurface, coordinator: ()) { view.playerLayer.player = nil }
}
private final class VideoLayerSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct PlayerSurface: View {
    let model: PlayerModel
    let chat: ChatModel
    let presentation: PlayerPresentation
    let toggleFullScreen: () -> Void
    let togglePiP: () -> Void
    let openWebsite: () -> Void
    let onLayer: (AVPlayerLayer) -> Void
    @State private var showsControls = true
    @State private var showsSettings = false
    @State private var interaction = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                VideoLayerView(player: model.player, onLayer: onLayer)
                if !presentation.isInPictureInPicture { DanmakuOverlay(chat: chat) }
                Color.clear.contentShape(Rectangle()).onTapGesture {
                    withAnimation(.easeOut(duration: 0.18)) {
                        if showsSettings { showsSettings = false; showsControls = true }
                        else { showsControls.toggle() }
                    }
                    interaction += 1
                }
                if presentation.isInPictureInPicture {
                    Label("正在画中画播放", systemImage: "pip.fill").font(.subheadline).foregroundStyle(.white)
                }
                if model.isResolving || model.isPreparing || model.isBuffering {
                    ProgressView().tint(.white).padding(18).background(.black.opacity(0.45), in: Circle())
                        .allowsHitTesting(false)
                }
                if let error = model.errorMessage { errorView(error) }
                if showsControls, !showsSettings { controls }
                if showsSettings {
                    HStack {
                        Spacer(minLength: 0)
                        PlayerSettings(model: model, chat: chat, presentation: presentation, togglePiP: togglePiP) { showsSettings = false; interaction += 1 }
                            .frame(width: min(320, geometry.size.width - 24))
                            .padding(12)
                    }
                }
            }
            .clipped()
        }
        .preferredColorScheme(.dark)
        .task(id: interaction) {
            guard !showsSettings else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, model.isPlaying, !UIAccessibility.isVoiceOverRunning else { return }
            withAnimation(.easeOut(duration: 0.2)) { showsControls = false }
        }
        .onChange(of: model.errorMessage) { _, error in if error != nil { showsControls = true } }
        .onChange(of: model.isPlaying) { _, playing in if playing { interaction += 1 } }
        .alert("播放器", isPresented: Binding(get: { presentation.message != nil }, set: { if !$0 { presentation.message = nil } })) {
            Button("知道了") { presentation.message = nil }
        } message: { Text(presentation.message ?? "") }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            if presentation.isFullScreen {
                HStack {
                    button("chevron.down", label: "退出全屏", action: toggleFullScreen)
                    Text(model.room.title).font(.subheadline.weight(.medium)).lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 8)
            }
            Spacer()
            HStack(spacing: 3) {
                button(model.isPlaying || model.isBuffering ? "pause.fill" : "play.fill", label: model.isPlaying ? "暂停" : "播放") { model.togglePlayback() }
                Text("直播").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(JLiveTheme.lime.opacity(0.22), in: Capsule()).foregroundStyle(JLiveTheme.lime)
                Spacer(minLength: 0)
                if let info = model.playbackInfo {
                    Menu {
                        ForEach(info.qualities) { quality in
                            Button { Task { await model.load(quality: quality.id) } } label: {
                                if quality.id == model.selectedQuality { Label(quality.name, systemImage: "checkmark") }
                                else { Text(quality.name) }
                            }
                        }
                    } label: {
                        Text(info.qualities.first { $0.id == model.selectedQuality }?.name ?? "画质")
                            .font(.system(size: 12, weight: .medium)).lineLimit(1).frame(minHeight: 44)
                    }
                    .disabled(model.isResolving).padding(.horizontal, 5)
                    .accessibilityLabel("切换清晰度")
                }
                button(model.muteState ? "speaker.slash.fill" : "speaker.wave.2.fill", label: model.muteState ? "开启声音" : "静音") { model.isMuted.toggle() }
                if chatEnabled {
                    button(chat.showsFloating ? "captions.bubble.fill" : "captions.bubble", label: chat.showsFloating ? "关闭弹幕" : "开启弹幕") { chat.showsFloating.toggle() }
                }
                if presentation.isFullScreen {
                    button("pip", label: "画中画", action: togglePiP).disabled(!presentation.canPictureInPicture)
                }
                button("slider.horizontal.3", label: "播放器设置") { showsSettings = true }
                button(presentation.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", label: presentation.isFullScreen ? "退出全屏" : "全屏播放", action: toggleFullScreen)
            }
            .padding(.horizontal, presentation.isFullScreen ? 22 : 8).padding(.bottom, presentation.isFullScreen ? 15 : 5)
        }
        .foregroundStyle(.white)
        .background(LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0), .init(color: .clear, location: 0.35), .init(color: .clear, location: 0.55), .init(color: .black.opacity(0.8), location: 1)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
    }

    private var chatEnabled: Bool { model.room.platform.supportsChat }
    private func button(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button { interaction += 1; action() } label: {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 10) {
            Text(error).font(.caption).multilineTextAlignment(.center).lineLimit(3)
            HStack(spacing: 18) {
                Button("重新连接") { Task { await model.load() } }
                Button("官网观看", action: openWebsite)
            }.font(.caption.weight(.semibold)).buttonStyle(.bordered)
        }
        .foregroundStyle(.white).padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85))
    }
}

private struct PlayerSettings: View {
    let model: PlayerModel
    @Bindable var chat: ChatModel
    let presentation: PlayerPresentation
    let togglePiP: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("播放设置").font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("关闭设置")
            }.padding(.leading, 16).padding(.trailing, 4)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let info = model.playbackInfo {
                        Picker("清晰度", selection: Binding(get: { model.selectedQuality ?? info.currentQuality }, set: { quality in Task { await model.load(quality: quality) } })) {
                            ForEach(info.qualities) { Text($0.name).tag($0.id) }
                        }.disabled(model.isResolving)
                        Picker("播放线路", selection: Binding(get: { model.selectedLine }, set: { model.playLine($0) })) {
                            ForEach(info.lines.indices, id: \.self) { Text("线路 \($0 + 1)").tag($0) }
                        }.disabled(model.isResolving)
                    }
                    if model.room.platform.supportsChat {
                        Divider()
                        Toggle("画面弹幕", isOn: $chat.showsFloating)
                        slider("不透明度", value: $chat.opacity, range: 0.25...1, text: "\(Int(chat.opacity * 100))%")
                        slider("字号", value: $chat.fontSize, range: 12...24, text: "\(Int(chat.fontSize))", step: 1)
                        slider("速度", value: $chat.speed, range: 0.6...1.8, text: String(format: "%.1f×", chat.speed))
                        slider("显示区域", value: $chat.area, range: 0.25...1, text: "\(Int(chat.area * 100))%")
                        TextField("屏蔽词，用逗号分隔", text: $chat.blockedWords)
                            .font(.subheadline).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        if case .failed = chat.status { Button("重新连接弹幕") { chat.restart() } }
                    }
                    Button { Task { await model.load() } } label: { Label("重新连接直播", systemImage: "arrow.clockwise") }
                    Button(action: togglePiP) { Label("画中画", systemImage: "pip") }
                        .disabled(!presentation.canPictureInPicture)
                    HStack {
                        Label("AirPlay", systemImage: "airplay.video")
                        Spacer()
                        AirPlayPicker().frame(width: 44, height: 44)
                    }
                }
                .font(.subheadline).pickerStyle(.menu).padding(16)
            }.scrollIndicators(.hidden)
        }
        .foregroundStyle(.white).tint(JLiveTheme.lime)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, text: String, step: Double = 0.05) -> some View {
        VStack(spacing: 6) {
            HStack { Text(title); Spacer(); Text(text).foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
    }
}

private struct AirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = .white
        picker.activeTintColor = UIColor(red: 0.77, green: 0.97, blue: 0.39, alpha: 1)
        return picker
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
