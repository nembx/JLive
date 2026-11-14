import SwiftUI
import JLiveCore

struct BrowseView: View {
    let service: LiveService
    let isSearch: Bool
    @State private var model: BrowseModel
    @State private var showingAddRoom = false
    @State private var showingSearch = false
    @State private var showingDouyinLogin = false
    @State private var searchText = ""
    @State private var directRoom: LiveRoom?
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(DouyinAccountStore.self) private var douyinAccount

    init(service: LiveService, isSearch: Bool) {
        self.service = service
        self.isSearch = isSearch
        _model = State(initialValue: BrowseModel(service: service))
    }

    var body: some View {
        Group {
            if isSearch { page }
            else {
                NavigationStack {
                    page.navigationDestination(isPresented: $showingSearch) { BrowseView(service: service, isSearch: true) }
                }
            }
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JLiveLayout.sectionSpacing) {
                if isSearch { searchField.padding(.horizontal, JLiveLayout.pageInset) }
                else { header.padding(.horizontal, JLiveLayout.pageInset) }
                PlatformPicker(selection: $model.selectedPlatform)
                content.padding(.horizontal, JLiveLayout.pageInset)
            }
            .padding(.top, 12).padding(.bottom, 24)
        }
        .background(JLiveTheme.background)
        .scrollDismissesKeyboard(.interactively)
        .toolbar(isSearch ? .visible : .hidden, for: .navigationBar)
        .toolbar(isSearch ? .hidden : .visible, for: .tabBar)
        .navigationTitle(isSearch ? "搜索" : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSearch)
        .toolbar {
            if isSearch {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { searchFocused = false; dismiss() }
                        .accessibilityIdentifier("cancelSearch")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { searchFocused = false; showingAddRoom = true } label: { Image(systemName: "link") }
                        .accessibilityLabel("打开直播间链接")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { searchFocused = false }
                }
            }
        }
        .refreshable { await model.load(isSearch: isSearch) }
        .task(id: model.requestKey) { await model.load(isSearch: isSearch) }
        .task {
            if isSearch {
                try? await Task.sleep(for: .milliseconds(200))
                if !Task.isCancelled { searchFocused = true }
            }
        }
        .onDisappear { searchFocused = false }
        .onChange(of: douyinAccount.revision) {
            if isSearch && !model.keyword.isEmpty { Task { await model.load(isSearch: true) } }
        }
        .sheet(isPresented: $showingDouyinLogin) { DouyinLoginView() }
        .sheet(isPresented: $showingAddRoom) {
            AddRoomSheet { room in directRoom = room }
                .presentationDetents([.medium])
        }
        .navigationDestination(item: $directRoom) { room in RoomDetailView(room: room, service: service) }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Image("BrandMark").resizable().frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("JLive").font(.system(size: 34, weight: .heavy, design: .rounded))
                    Text("LIVE").font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .tracking(1.5).padding(.horizontal, 7).padding(.vertical, 4)
                        .foregroundStyle(.black).background(JLiveTheme.lime, in: Capsule())
                }
                Text("喜欢的直播，都在这里")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: JLiveLayout.itemSpacing) {
                CircleIconButton(symbol: "magnifyingglass", label: "搜索直播") { showingSearch = true }
                CircleIconButton(symbol: "link", label: "打开直播间链接") { showingAddRoom = true }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: JLiveLayout.itemSpacing) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索主播或直播间", text: $searchText)
                .font(.subheadline).submitLabel(.search).autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($searchFocused)
                .accessibilityIdentifier("searchField")
                .onSubmit { submitSearch() }
            if !searchText.isEmpty {
                Button { searchText = ""; model.keyword = ""; searchFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 32, height: 44)
                }
                    .accessibilityLabel("清空搜索")
            }
            Button("搜索", action: submitSearch)
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("submitSearch")
        }
        .padding(.horizontal, JLiveLayout.cardInset).padding(.vertical, 4)
        .background(JLiveTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func submitSearch() {
        searchFocused = false
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.keyword == keyword { Task { await model.load(isSearch: true) } }
        else { model.keyword = keyword }
    }

    @ViewBuilder private var content: some View {
        if isSearch && model.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyState(symbol: "magnifyingglass", title: "找到你喜欢的直播", message: "搜索 B站、虎牙、斗鱼和抖音\n输入关键词后点击搜索")
                .contentShape(Rectangle()).onTapGesture { searchFocused = false }
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
                            if issue.platform == .douyin && issue.requiresLogin {
                                Button(douyinAccount.isLoggedIn ? "重新登录抖音" : "登录抖音") {
                                    searchFocused = false
                                    showingDouyinLogin = true
                                }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("douyinSearchLogin")
                            }
                            if isSearch && issue.platform == .douyin, let url = douyinWebSearchURL {
                                Link("在抖音官网搜索", destination: url).font(.caption)
                            }
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

    private var douyinWebSearchURL: URL? {
        let base = URL(string: "https://www.douyin.com/search/")!
        var url = URLComponents(url: base.appendingPathComponent(model.keyword), resolvingAgainstBaseURL: false)
        url?.queryItems = [URLQueryItem(name: "type", value: "live")]
        return url?.url
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.accessibilityIdentifier("cancelRoomLink")
                }
            }
        }
    }
}
