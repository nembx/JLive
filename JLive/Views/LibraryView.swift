import SwiftUI
import JLiveCore

struct LibraryView: View {
    let service: LiveService
    @Environment(LibraryStore.self) private var library
    @State private var filter = FavoriteFilter.live
    @State private var showingAddRoom = false
    @State private var directRoom: LiveRoom?

    private var rooms: [LiveRoom] { library.favorites(matching: filter) }

    /// Tells the viewer how current the statuses are, since they decide which list a room is in.
    private var statusLine: some View {
        HStack(spacing: 6) {
            if library.isRefreshing { ProgressView().controlSize(.mini) }
            Text(library.isRefreshing ? "正在更新开播状态…" : (library.refreshMessage ?? "开播状态会自动更新"))
            Spacer(minLength: 12)
            if !rooms.isEmpty { Text("长按卡片管理收藏").fixedSize() }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JLiveLayout.sectionSpacing) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("我的直播间").font(.system(size: 28, weight: .bold))
                            Text("把喜欢留住，下次一键相遇").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        CircleIconButton(symbol: "plus", label: "添加直播间") { showingAddRoom = true }
                    }
                    Picker("开播状态", selection: $filter) {
                        ForEach(FavoriteFilter.allCases) { item in
                            Text("\(item.title) · \(library.favorites(matching: item).count)").tag(item)
                        }
                    }
                    .pickerStyle(.segmented).accessibilityIdentifier("favoriteStatusPicker")
                    if !library.favorites.isEmpty { statusLine }
                    if rooms.isEmpty {
                        EmptyState(symbol: filter == .live ? "antenna.radiowaves.left.and.right" : "heart",
                            title: library.favorites.isEmpty ? "收藏你的第一个直播间" : (filter == .live ? "暂时没有主播开播" : "暂时没有未开播的主播"),
                            message: library.favorites.isEmpty ? "打开直播间后点击爱心收藏，\n也可以直接添加直播间链接。" : "切换开播状态查看收藏，或下拉刷新。")
                    } else {
                        if filter == .offline, !library.isRefreshing, rooms.contains(where: { $0.isLive == nil }) {
                            Text("包含状态待更新的直播间，下拉可重新查询")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        RoomGrid(rooms: rooms, service: service)
                    }
                }
                .padding(JLiveLayout.pageInset)
            }
            .background(JLiveTheme.background)
            .refreshable { await library.refresh(using: service) }
            .task {
                // Check saved snapshots when the page is shown, reusing statuses for up to a minute.
                // Keep checking once a minute for as long as the page stays open.
                await library.refreshIfStale(using: service)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(LibraryStore.statusLifetime))
                    guard !Task.isCancelled else { break }
                    await library.refreshIfStale(using: service)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAddRoom) {
                AddRoomSheet { room in if !library.contains(room) { library.toggle(room) }; directRoom = room }
                    .presentationDetents([.medium])
            }
            .navigationDestination(item: $directRoom) { room in RoomDetailView(room: room, service: service) }
        }
    }
}
