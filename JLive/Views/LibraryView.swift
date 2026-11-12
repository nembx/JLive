import SwiftUI
import JLiveCore

struct LibraryView: View {
    let service: LiveService
    @Environment(LibraryStore.self) private var library
    @State private var showingHistory = false
    @State private var showingAddRoom = false
    @State private var directRoom: LiveRoom?

    private var rooms: [LiveRoom] { showingHistory ? library.history : library.favorites }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("我的直播间").font(.system(size: 28, weight: .bold))
                            Text("把喜欢留住，下次一键相遇").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { showingAddRoom = true } label: {
                            Image(systemName: "plus").font(.title3).frame(width: 42, height: 42)
                                .background(JLiveTheme.surface, in: Circle())
                        }
                        .accessibilityLabel("添加直播间")
                    }
                    Picker("记录类型", selection: $showingHistory) {
                        Text("收藏 · \(library.favorites.count)").tag(false)
                        Text("最近观看").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if rooms.isEmpty {
                        EmptyState(symbol: showingHistory ? "clock" : "heart", title: showingHistory ? "还没有观看记录" : "收藏你的第一个直播间", message: "打开直播间后点击爱心收藏，\n也可以直接添加直播间链接。")
                    } else {
                        Text(showingHistory ? "最近打开的直播间，按时间排列" : (library.refreshMessage ?? "下拉刷新开播状态，长按卡片管理收藏"))
                            .font(.caption).foregroundStyle(.secondary)
                        RoomGrid(rooms: rooms, service: service)
                    }
                }
                .padding(20)
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
