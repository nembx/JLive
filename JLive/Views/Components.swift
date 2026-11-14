import SwiftUI
import JLiveCore

enum JLiveLayout {
    static let pageInset: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let cardInset: CGFloat = 12
    static let itemSpacing: CGFloat = 12
    static let gridSpacing: CGFloat = 12
}

struct CircleIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44).background(JLiveTheme.surface, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }
}

enum JLiveTheme {
    static let accent = Color(light: UIColor(red: 0.18, green: 0.42, blue: 0.08, alpha: 1), dark: UIColor(red: 0.72, green: 0.94, blue: 0.33, alpha: 1))
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let lime = Color(red: 0.77, green: 0.97, blue: 0.39)

    static func color(_ platform: LivePlatform) -> Color {
        switch platform {
        case .bilibili: Color(red: 0.91, green: 0.35, blue: 0.55)
        case .huya: Color(red: 0.85, green: 0.48, blue: 0.05)
        case .douyu: Color(red: 0.94, green: 0.34, blue: 0.15)
        case .douyin: Color(red: 0.30, green: 0.42, blue: 0.66)
        }
    }
}

private extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
}

struct PlatformBadge: View {
    let platform: LivePlatform
    var body: some View {
        Text(platform.shortName)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(JLiveTheme.color(platform), in: RoundedRectangle(cornerRadius: 5))
    }
}

struct PlatformPicker: View {
    @Binding var selection: LivePlatform?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip("全部", platform: nil)
                ForEach(LivePlatform.allCases) { platform in chip(platform.name, platform: platform) }
            }
            .padding(.horizontal, JLiveLayout.pageInset)
        }
    }

    private func chip(_ title: String, platform: LivePlatform?) -> some View {
        Button { selection = platform } label: {
            HStack(spacing: 6) {
                if let platform {
                    Circle().fill(JLiveTheme.color(platform)).frame(width: 6, height: 6)
                }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 15).padding(.vertical, 11)
            .foregroundStyle(selection == platform ? Color.black : Color.primary)
            .background(selection == platform ? JLiveTheme.lime : JLiveTheme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == platform ? .isSelected : [])
    }
}

struct RoomCard: View {
    let room: LiveRoom
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(JLiveTheme.color(room.platform).opacity(0.12))
                    .overlay {
                        GeometryReader { geometry in
                            AsyncImage(url: room.coverURL) { image in image.resizable().scaledToFill() } placeholder: {
                                Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        }
                    }
                PlatformBadge(platform: room.platform).padding(JLiveLayout.cardInset)
                VStack {
                    Spacer()
                    HStack(alignment: .center, spacing: 4) {
                        if room.isLive == true {
                            Image(systemName: "flame.fill").font(.system(size: 9)).frame(width: 12, height: 12)
                            Text(room.popularity).font(.system(size: 10, weight: .medium))
                        } else { Text(room.isLive == false ? "未开播" : "状态待更新").font(.system(size: 10)) }
                        Spacer()
                        Image(systemName: "play.fill").font(.system(size: 10)).frame(width: 12, height: 12)
                    }
                    .foregroundStyle(.white).padding(JLiveLayout.cardInset)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipped()

            VStack(alignment: .leading, spacing: JLiveLayout.itemSpacing) {
                Text(room.title.isEmpty ? "\(room.streamer)的直播间" : room.title)
                    .font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "person.circle").font(.caption).frame(width: 14, height: 14)
                    Text(room.streamer).font(.caption).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.secondary)
            }
            .padding(JLiveLayout.cardInset)
        }
        .background(JLiveTheme.surface, in: RoundedRectangle(cornerRadius: 13))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .contentShape(RoundedRectangle(cornerRadius: 13))
        .accessibilityElement(children: .combine)
    }
}

struct RoomGrid: View {
    let rooms: [LiveRoom]
    let service: LiveService
    @Environment(LibraryStore.self) private var library

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: JLiveLayout.gridSpacing, alignment: .top)], alignment: .leading, spacing: JLiveLayout.gridSpacing) {
            ForEach(rooms) { room in
                NavigationLink(value: room) { RoomCard(room: room) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("room-\(room.id)")
                    .contextMenu {
                        Button { library.toggle(room) } label: {
                            Label(library.contains(room) ? "取消收藏" : "收藏直播间", systemImage: library.contains(room) ? "heart.slash" : "heart")
                        }
                        ShareLink(item: room.webURL)
                    }
            }
        }
        .navigationDestination(for: LiveRoom.self) { room in RoomDetailView(room: room, service: service) }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: JLiveLayout.itemSpacing) {
            Image(systemName: symbol).font(.system(size: 36, weight: .light)).foregroundStyle(JLiveTheme.accent)
                .frame(width: 82, height: 82).background(JLiveTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(30).frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}
