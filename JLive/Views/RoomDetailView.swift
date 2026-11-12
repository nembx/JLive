import SwiftUI
import AVKit
import SafariServices
import JLiveCore

struct RoomDetailView: View {
    let room: LiveRoom
    let service: LiveService
    @Environment(LibraryStore.self) private var library
    @Environment(AccountStore.self) private var account
    @State private var model: PlayerModel
    @State private var chat: ChatModel
    @State private var showingWebsite = false
    @State private var presentation = PlayerPresentation()
    @State private var needsLoad = true
    @Environment(\.scenePhase) private var scenePhase

    init(room: LiveRoom, service: LiveService) {
        self.room = room
        self.service = service
        _model = State(initialValue: PlayerModel(room: room, service: service))
        _chat = State(initialValue: ChatModel(service: service))
    }

    var body: some View {
        VStack(spacing: 0) {
            playerArea
            ScrollView {
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
                    if model.room.platform.supportsChat { ChatPanel(chat: chat) }
                    if model.room.platform == .bilibili { ChatComposer(room: model.room, service: service) }
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
                .padding(20)
                .padding(.bottom, 12)
            }
        }
        .background(JLiveTheme.background)
        .navigationTitle(model.room.platform.name).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
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
            guard !presentation.isFullScreen else { return }
            needsLoad = true
            model.stop()
            chat.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, !presentation.isInPictureInPicture { model.suspend() }
            if phase == .active { model.resume() }
        }
        .onChange(of: account.credentials?.uid) { _, _ in
            if !needsLoad { chat.restart() }
        }
    }

    private var playerArea: some View {
        ZStack {
            Color.black
            if model.room.platform.supportsNativePlayback {
                LivePlayerView(model: model, chat: chat, presentation: presentation) { showingWebsite = true }
            } else {
                AsyncImage(url: model.room.coverURL) { image in image.resizable().scaledToFill().opacity(0.5) } placeholder: { Color.black }
                Button { showingWebsite = true } label: {
                    Image(systemName: "play.fill").font(.title).foregroundStyle(.black)
                        .frame(width: 62, height: 62).background(JLiveTheme.lime, in: Circle())
                }
                .accessibilityLabel("在官网观看")
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit).clipped()
    }

}

private struct WebsiteView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
