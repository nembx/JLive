import SwiftUI
import JLiveCore

struct BrowseView: View {
    let service: LiveService
    let isSearch: Bool
    @State private var model: BrowseModel
    @State private var showingAddRoom = false
    @State private var directRoom: LiveRoom?

    init(service: LiveService, isSearch: Bool) {
        self.service = service
        self.isSearch = isSearch
        _model = State(initialValue: BrowseModel(service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header.padding(.horizontal, 20)
                    if isSearch { searchField.padding(.horizontal, 20) }
                    PlatformPicker(selection: $model.selectedPlatform)
                    content.padding(.horizontal, 20)
                }
                .padding(.top, 12).padding(.bottom, 24)
            }
            .background(JLiveTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await model.load(isSearch: isSearch) }
            .task(id: model.requestKey) { await model.load(isSearch: isSearch) }
            .sheet(isPresented: $showingAddRoom) {
                AddRoomSheet { room in directRoom = room }
                    .presentationDetents([.medium])
            }
            .navigationDestination(item: $directRoom) { room in RoomDetailView(room: room, service: service) }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    if !isSearch { Image("BrandMark").resizable().frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 12)) }
                    Text(isSearch ? "找到你的热爱" : "JLive").font(.system(size: isSearch ? 27 : 34, weight: .heavy, design: .rounded))
                    if !isSearch {
                        Text("LIVE").font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .tracking(1.5).padding(.horizontal, 7).padding(.vertical, 4)
                            .foregroundStyle(.black).background(JLiveTheme.lime, in: Capsule())
                    }
                }
                Text(isSearch ? "搜主播、直播间，或直接打开链接" : "喜欢的直播，都在这里")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showingAddRoom = true } label: {
                Image(systemName: "link").font(.system(size: 17, weight: .medium))
                    .frame(width: 42, height: 42).background(JLiveTheme.surface, in: Circle())
            }
            .accessibilityLabel("打开直播间链接")
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索主播或直播间", text: $model.keyword)
                .font(.subheadline).submitLabel(.search).autocorrectionDisabled()
            if !model.keyword.isEmpty {
                Button { model.keyword = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("清空搜索")
            }
        }
        .padding(15).background(JLiveTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private var content: some View {
        if isSearch && model.selectedPlatform?.supportsSearch == false {
            EmptyState(symbol: "link", title: "通过链接打开抖音直播", message: "抖音暂不支持关键词搜索\n点右上角粘贴直播间链接或输入房间号")
        } else if isSearch && model.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyState(symbol: "magnifyingglass", title: "下一场精彩，从搜索开始", message: "同时搜索 B站、虎牙和斗鱼\n也可以选择一个平台精准查找")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(isSearch ? "搜索结果" : "正在直播").font(.system(size: 19, weight: .bold))
                    Spacer()
                    if !model.rooms.isEmpty { Text("\(model.rooms.count) 个直播间").font(.caption).foregroundStyle(.secondary) }
                }
                if !model.issues.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.issues) { issue in
                            Text("\(issue.platform.name)：\(issue.message)").font(.caption).foregroundStyle(.secondary)
                        }
                        Button("重新加载") { Task { await model.load(isSearch: isSearch) } }.font(.caption.bold())
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(JLiveTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                if model.isLoading {
                    ProgressView("正在寻找精彩…").frame(maxWidth: .infinity).padding(.vertical, 70)
                } else if model.hasLoaded && model.rooms.isEmpty {
                    EmptyState(symbol: "antenna.radiowaves.left.and.right", title: model.issues.isEmpty ? "还没有找到直播间" : "暂时无法加载", message: "试试其他关键词、切换平台，或下拉刷新。")
                }
                if let error = model.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("重试") { Task { await model.load(isSearch: isSearch) } }
                }
                RoomGrid(rooms: model.rooms, service: service)
                if model.hasMore {
                    Button { Task { await model.loadMore(isSearch: isSearch) } } label: {
                        HStack {
                            if model.isLoadingMore { ProgressView() }
                            Text(model.isLoadingMore ? "加载中…" : "加载更多")
                        }
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(14)
                    }
                    .disabled(model.isLoadingMore).background(JLiveTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

struct AddRoomSheet: View {
    let onOpen: (LiveRoom) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var platform = LivePlatform.bilibili
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("直播间链接或房间号") {
                    TextField("https://live.bilibili.com/…", text: $text)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Picker("房间号所属平台", selection: $platform) {
                        ForEach(LivePlatform.allCases) { Text($0.name).tag($0) }
                    }
                }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                Section {
                    Button("打开直播间") {
                        do {
                            let room = try RoomLinkParser.parse(text, platform: platform)
                            dismiss()
                            onOpen(room)
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("打开直播间").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}
