import SwiftUI
import JLiveCore

/// Chat messages travelling right to left across the video.
struct DanmakuOverlay: View {
    let chat: ChatModel

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(chat.floating) { item in
                    DanmakuLabel(item: item, containerWidth: proxy.size.width) { chat.expire(item.id) }
                        .offset(y: 8 + CGFloat(item.lane) * ChatModel.laneHeight)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .onChange(of: proxy.size, initial: true) { _, size in chat.viewport = size }
        }
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct DanmakuLabel: View {
    let item: ChatModel.Floating
    let containerWidth: CGFloat
    let onFinish: () -> Void
    @State private var departed = false

    var body: some View {
        Text(item.text)
            .font(.system(size: 15, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(item.isSuperChat ? Color.black : color)
            .padding(.horizontal, item.isSuperChat ? 9 : 0)
            .padding(.vertical, item.isSuperChat ? 2 : 0)
            .background(item.isSuperChat ? JLiveTheme.lime : Color.clear, in: Capsule())
            .shadow(color: .black.opacity(item.isSuperChat ? 0 : 0.85), radius: 1, x: 0, y: 1)
            .offset(x: departed ? -item.width - 12 : containerWidth)
            .task {
                do {
                    if item.delay > 0 { try await Task.sleep(for: .seconds(item.delay)) }
                    withAnimation(.linear(duration: item.duration)) { departed = true }
                    try await Task.sleep(for: .seconds(item.duration))
                    onFinish()
                } catch {}
            }
    }

    private var color: Color {
        guard let value = item.color else { return .white }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Scrolling message list under the player, following the newest message until the viewer scrolls back.
struct ChatPanel: View {
    let chat: ChatModel
    /// Snapshot shown while the viewer reads older messages, so the list stops moving under their finger.
    @State private var frozen: [ChatModel.Entry]?

    private var visible: [ChatModel.Entry] { frozen ?? chat.entries }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("聊天").font(.system(size: 15, weight: .bold))
                statusLabel
                Spacer()
                Button { chat.showsFloating.toggle() } label: {
                    Image(systemName: chat.showsFloating ? "captions.bubble.fill" : "captions.bubble")
                        .font(.system(size: 16))
                        .foregroundStyle(chat.showsFloating ? JLiveTheme.accent : Color.secondary)
                        .frame(width: 36, height: 30)
                }
                .accessibilityLabel(chat.showsFloating ? "关闭画面弹幕" : "开启画面弹幕")
            }
            .padding(.leading, 15).padding(.trailing, 8).padding(.vertical, 8)
            Divider()
            messages
        }
        .background(JLiveTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private var statusLabel: some View {
        switch chat.status {
        case .idle: EmptyView()
        case .connecting: Text("连接中…").font(.caption).foregroundStyle(.secondary)
        case .reconnecting: Text("重连中…").font(.caption).foregroundStyle(.secondary)
        case .failed: Text("已断开").font(.caption).foregroundStyle(.secondary)
        case .connected:
            HStack(spacing: 4) {
                Circle().fill(JLiveTheme.accent).frame(width: 5, height: 5)
                Text("实时").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(visible) { entry in
                        ChatRow(message: entry.message).id(entry.id)
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 260)
            .scrollIndicators(.hidden)
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in
                if frozen == nil, !chat.entries.isEmpty { frozen = chat.entries }
            })
            .overlay { if visible.isEmpty { placeholder } }
            .overlay(alignment: .bottom) {
                if frozen != nil {
                    Button { frozen = nil } label: {
                        Label("回到最新", systemImage: "arrow.down")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 13).padding(.vertical, 7)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .padding(.bottom, 10)
                }
            }
            .onChange(of: chat.entries.last?.id) { _, id in
                guard frozen == nil, let id else { return }
                proxy.scrollTo(id, anchor: .bottom)
            }
            .onChange(of: frozen == nil) { _, isFollowing in
                guard isFollowing, let id = chat.entries.last?.id else { return }
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }

    @ViewBuilder private var placeholder: some View {
        switch chat.status {
        case .connecting: ProgressView("正在连接弹幕…").font(.caption)
        case .reconnecting: ProgressView("弹幕重连中…").font(.caption)
        case .failed(let message):
            VStack(spacing: 10) {
                Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("重新连接") { chat.restart() }.font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 24)
        case .idle, .connected:
            VStack(spacing: 7) {
                Image(systemName: "bubble.left.and.bubble.right").font(.title3).foregroundStyle(.tertiary)
                Text("还没有人发言").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ChatRow: View {
    let message: LiveChatMessage

    var body: some View {
        switch message.kind {
        case .chat:
            Text("\(Text(message.userName).foregroundStyle(.secondary))：\(message.text)")
                .font(.subheadline)
        case .gift:
            Text("\(Text(message.userName).fontWeight(.medium)) \(message.text)")
                .font(.caption).foregroundStyle(.secondary)
        case .superChat(let price):
            VStack(alignment: .leading, spacing: 5) {
                Text("醒目留言 ¥\(price) · \(message.userName)")
                    .font(.caption2.weight(.bold)).foregroundStyle(JLiveTheme.accent)
                Text(message.text).font(.subheadline)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JLiveTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
