import SwiftUI
import JLiveCore

struct LibraryView: View {
    let service: LiveService
    @Environment(LibraryStore.self) private var library
    @State private var filter = FavoriteFilter.all
    @State private var showingAddRoom = false
    @State private var directRoom: LiveRoom?

    private var rooms: [LiveRoom] { library.favorites(matching: filter) }

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
                    if rooms.isEmpty {
                        EmptyState(symbol: filter == .live ? "antenna.radiowaves.left.and.right" : "heart",
                            title: library.favorites.isEmpty ? "收藏你的第一个直播间" : (filter == .live ? "暂时没有主播开播" : "暂时没有未开播的主播"),
                            message: library.favorites.isEmpty ? "打开直播间后点击爱心收藏，\n也可以直接添加直播间链接。" : "切换到全部查看收藏，或下拉刷新开播状态。")
                    } else {
                        Text(library.refreshMessage ?? "下拉刷新开播状态，长按卡片管理收藏")
                            .font(.caption).foregroundStyle(.secondary)
                        if filter == .all, library.favorites.contains(where: { $0.isLive == nil }) {
                            Text("状态待更新的直播间保留在全部中")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        RoomGrid(rooms: rooms, service: service)
                    }
                }
                .padding(JLiveLayout.pageInset)
            }
            .background(JLiveTheme.background)
            .refreshable { await library.refresh(using: service) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAddRoom) {
                AddRoomSheet { room in if !library.contains(room) { library.toggle(room) }; directRoom = room }
                    .presentationDetents([.medium])
            }
            .navigationDestination(item: $directRoom) { room in RoomDetailView(room: room, service: service) }
        }
    }
}
