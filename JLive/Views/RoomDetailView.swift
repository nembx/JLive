import SwiftUI
import AVKit
import SafariServices
import JLiveCore

struct RoomDetailView: View {
    let room: LiveRoom
    let service: LiveService
    @Environment(LibraryStore.self) private var library
    @State private var model: PlayerModel
    @State private var chat: ChatModel
    @State private var showingWebsite = false
    @State private var isFullScreen = false
    @State private var needsLoad = true
    @Environment(\.scenePhase) private var scenePhase

    init(room: LiveRoom, service: LiveService) {
        self.room = room
        self.service = service
        _model = State(initialValue: PlayerModel(room: room, service: service))
        _chat = State(initialValue: ChatModel(service: service))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                playerArea
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) {
                        PlatformBadge(platform: model.room.platform)
                        if model.room.isLive == true {
                            Label("正在直播", systemImage: "dot.radiowaves.left.and.right")
                                .font(.caption).foregroundStyle(JLiveTheme.accent)
                        } else if model.room.isLive == false {
                            Text("未开播").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("房间 \(model.room.roomID)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Text(model.room.title).font(.title3.bold()).textSelection(.enabled)
                    HStack(spacing: 12) {
                        AsyncImage(url: model.room.avatarURL) { image in image.resizable().scaledToFill() } placeholder: {
                            Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.tertiary)
                        }
                        .frame(width: 42, height: 42).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.room.streamer).font(.subheadline.weight(.semibold))
                            Text(model.room.category.isEmpty ? "\(model.room.popularity) 热度" : "\(model.room.category) · \(model.room.popularity) 热度")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { library.toggle(model.room) } label: {
                            Image(systemName: library.contains(model.room) ? "heart.fill" : "heart")
                                .font(.title3).frame(width: 44, height: 44)
                                .background(JLiveTheme.surface, in: Circle())
                        }
                        .accessibilityLabel(library.contains(model.room) ? "取消收藏" : "收藏直播间")
                    }
                    if let info = model.playbackInfo { playbackControls(info) }
                    if model.room.platform.supportsChat { ChatPanel(chat: chat) }
                    if !model.room.platform.supportsNativePlayback {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("前往平台观看", systemImage: "safari").font(.headline)
                            Text("这个平台目前通过官网观看，直播间可以收藏在 JLive 中。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button { showingWebsite = true } label: { Label("打开直播间", systemImage: "arrow.up.right") }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(JLiveTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    HStack {
                        Button { showingWebsite = true } label: { Label("平台网页", systemImage: "safari") }
                        Spacer()
                        ShareLink(item: model.room.webURL) { Label("分享", systemImage: "square.and.arrow.up") }
                    }
                    .font(.subheadline).padding(.top, 4)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 30)
        }
        .background(JLiveTheme.background)
        .navigationTitle(model.room.platform.name).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $showingWebsite) { WebsiteView(url: model.room.webURL).ignoresSafeArea() }
        .task {
            // The task runs again whenever the page reappears, e.g. after leaving full screen.
            guard needsLoad else { return }
            needsLoad = false
            library.record(room)
            await model.load()
            guard !Task.isCancelled else {
                needsLoad = true
                return
            }
            library.enrich(original: room, updated: model.room)
            chat.start(room: model.room)
        }
        .onDisappear {
            // Full screen is presented by another controller, so the page disappears while the video keeps playing.
            guard !isFullScreen else { return }
            needsLoad = true
            model.stop()
            chat.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.player.pause() }
        }
    }

    private var playerArea: some View {
        ZStack {
            Color.black
            if model.room.platform.supportsNativePlayback {
                NativePlayerView(player: model.player, chat: chat, isFullScreen: $isFullScreen)
                if model.isResolving || model.isPreparing {
                    ProgressView(model.isResolving ? "获取直播线路…" : "正在连接直播…")
                        .tint(.white).foregroundStyle(.white).font(.caption)
                        .padding(18).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                }
                if let error = model.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.title2)
                        Text(error).font(.caption).multilineTextAlignment(.center).lineLimit(3)
                        HStack {
                            Button("重试") { Task { await model.load() } }.buttonStyle(.bordered)
                            Button("官网观看") { showingWebsite = true }.buttonStyle(.bordered)
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white).padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.85))
                }
            } else {
                AsyncImage(url: model.room.coverURL) { image in image.resizable().scaledToFill().opacity(0.5) } placeholder: { Color.black }
                Button { showingWebsite = true } label: {
                    Image(systemName: "play.fill").font(.title).foregroundStyle(.black)
                        .frame(width: 62, height: 62).background(JLiveTheme.lime, in: Circle())
                }
                .accessibilityLabel("在官网观看")
            }
        }
        .frame(height: 235).clipped()
    }

    private func playbackControls(_ info: PlaybackInfo) -> some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(info.qualities) { quality in
                    Button {
                        Task { await model.load(quality: quality.id) }
                    } label: {
                        if model.selectedQuality == quality.id { Label(quality.name, systemImage: "checkmark") }
                        else { Text(quality.name) }
                    }
                }
            } label: {
                Label(info.qualities.first { $0.id == model.selectedQuality }?.name ?? "自动画质", systemImage: "slider.horizontal.3")
            }
            .disabled(model.isResolving || info.qualities.isEmpty)
            Spacer()
            Menu {
                ForEach(Array(info.lines.enumerated()), id: \.offset) { index, _ in
                    Button {
                        model.playLine(index)
                    } label: {
                        if index == model.selectedLine { Label("线路 \(index + 1)", systemImage: "checkmark") }
                        else { Text("线路 \(index + 1)") }
                    }
                }
            } label: { Label("线路 \(model.selectedLine + 1)", systemImage: "network") }
                .disabled(model.isResolving)
        }
        .font(.subheadline).padding(15).background(JLiveTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct NativePlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let chat: ChatModel
    @Binding var isFullScreen: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isFullScreen: $isFullScreen) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = false
        controller.videoGravity = .resizeAspect
        controller.loadViewIfNeeded()
        // The overlay view sits between the video and the playback controls.
        if let surface = controller.contentOverlayView {
            let overlay = UIHostingController(rootView: DanmakuOverlay(chat: chat))
            overlay.view.backgroundColor = .clear
            overlay.view.isUserInteractionEnabled = false
            overlay.view.translatesAutoresizingMaskIntoConstraints = false
            surface.addSubview(overlay.view)
            NSLayoutConstraint.activate([
                overlay.view.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
                overlay.view.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
                overlay.view.topAnchor.constraint(equalTo: surface.topAnchor),
                overlay.view.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
            ])
            context.coordinator.overlay = overlay
        }
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player = nil
        coordinator.overlay?.view.removeFromSuperview()
        coordinator.overlay = nil
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
        var overlay: UIHostingController<DanmakuOverlay>?
        private let isFullScreen: Binding<Bool>

        init(isFullScreen: Binding<Bool>) { self.isFullScreen = isFullScreen }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willBeginFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
        ) {
            isFullScreen.wrappedValue = true
            _ = coordinator.animate(alongsideTransition: nil) { [isFullScreen] context in
                // An abandoned transition leaves the player in line.
                if context.isCancelled { isFullScreen.wrappedValue = false }
            }
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
        ) {
            let wasPlaying = playerViewController.player?.timeControlStatus != .paused
            _ = coordinator.animate(alongsideTransition: nil) { [isFullScreen] context in
                guard !context.isCancelled else { return }
                isFullScreen.wrappedValue = false
                // AVKit pauses when full screen is dismissed; a live stream should keep going.
                if wasPlaying { playerViewController.player?.play() }
            }
        }
    }
}

private struct WebsiteView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
