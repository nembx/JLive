import SwiftUI
import JLiveCore

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
            .padding(.horizontal, 20)
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
                PlatformBadge(platform: room.platform).padding(8)
                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        if room.isLive != false {
                            Image(systemName: "flame.fill").font(.system(size: 9))
                            Text(room.popularity).font(.system(size: 10, weight: .medium))
                        } else { Text("未开播").font(.system(size: 10)) }
                        Spacer()
                        Image(systemName: "play.fill").font(.system(size: 10))
                    }
                    .foregroundStyle(.white).padding(8)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                }
            }
            .frame(height: 110)
            .clipped()

            VStack(alignment: .leading, spacing: 7) {
                Text(room.title.isEmpty ? "\(room.streamer)的直播间" : room.title)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    .frame(height: 36, alignment: .topLeading)
                HStack(spacing: 4) {
                    Image(systemName: "person.circle").font(.system(size: 11))
                    Text(room.streamer).font(.system(size: 11)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
            }
            .padding(10)
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 14) {
            ForEach(rooms) { room in
                NavigationLink(value: room) { RoomCard(room: room) }
                    .buttonStyle(.plain)
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
        VStack(spacing: 15) {
            Image(systemName: symbol).font(.system(size: 36, weight: .light)).foregroundStyle(JLiveTheme.accent)
                .frame(width: 82, height: 82).background(JLiveTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(30).frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}
