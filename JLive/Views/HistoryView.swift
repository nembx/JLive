import SwiftUI
import JLiveCore

struct HistoryView: View {
    let service: LiveService
    @Environment(LibraryStore.self) private var library
    @State private var confirmingClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JLiveLayout.sectionSpacing) {
                if library.history.isEmpty {
                    EmptyState(symbol: "clock", title: "还没有观看记录", message: "最近打开的直播间会出现在这里")
                } else {
                    Text("最近打开的 \(library.history.count) 个直播间，按时间排列")
                        .font(.caption).foregroundStyle(.secondary)
                    RoomGrid(rooms: library.history, service: service)
                }
            }
            .padding(JLiveLayout.pageInset)
        }
        .background(JLiveTheme.background)
        .navigationTitle("最近观看").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("清空", role: .destructive) { confirmingClear = true }
                    .disabled(library.history.isEmpty)
            }
        }
        .confirmationDialog("清空所有观看记录？", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("清空记录", role: .destructive) { library.clearHistory() }
        }
    }
}
