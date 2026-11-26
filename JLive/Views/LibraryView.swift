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
        Group {
            if library.isRefreshing {
                ProgressView("正在更新开播状态…").progressViewStyle(.circular).controlSize(.mini)
            } else if let message = library.refreshMessage {
                Text(message)
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JLiveLayout.sectionSpacing) {
                    HStack {
                        Text("我的直播间").font(.system(size: 28, weight: .bold))
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
                            title: library.favorites.isEmpty ? "暂无收藏" : (filter == .live ? "暂无开播的直播间" : "暂无未开播的直播间"))
                    } else {
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
