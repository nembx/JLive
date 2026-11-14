import SwiftUI
import JLiveCore

@main
struct JLiveApp: App {
    @State private var library = LibraryStore()
    @State private var externalRoom: LiveRoom?
    @State private var account: AccountStore
    @State private var douyinAccount: DouyinAccountStore
    private let service: LiveService

    init() {
        #if DEBUG
        let useFixtures = CommandLine.arguments.contains("--ui-fixtures")
        let service = useFixtures ? UIFixtures.service : LiveService.standard()
        if useFixtures { _library = State(initialValue: UIFixtures.library()) }
        #else
        let service = LiveService.standard()
        #endif
        self.service = service
        _account = State(initialValue: AccountStore(service: service))
        _douyinAccount = State(initialValue: DouyinAccountStore(service: service))
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--open-room"),
           CommandLine.arguments.indices.contains(index + 1),
           let room = try? RoomLinkParser.parse(CommandLine.arguments[index + 1]) {
            _externalRoom = State(initialValue: room)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                BrowseView(service: service, isSearch: false)
                    .tabItem { Label("发现", systemImage: "play.rectangle.on.rectangle") }
                LibraryView(service: service)
                    .tabItem { Label("收藏", systemImage: "heart") }
                SettingsView(service: service)
                    .tabItem { Label("我的", systemImage: "person.crop.circle") }
            }
            .tint(JLiveTheme.accent)
            .environment(library)
            .environment(account)
            .environment(douyinAccount)
            .preferredColorScheme(library.appearance.colorScheme)
            .onOpenURL { url in
                guard url.scheme == "jlive", let platform = LivePlatform(rawValue: url.host ?? ""),
                      url.pathComponents.filter({ $0 != "/" }).count == 1,
                      let room = try? RoomLinkParser.parse(url.lastPathComponent, platform: platform) else { return }
                externalRoom = room
            }
            .sheet(item: $externalRoom) { room in
                NavigationStack {
                    RoomDetailView(room: room, service: service)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { externalRoom = nil } } }
                }
                .environment(library)
                .environment(account)
                .environment(douyinAccount)
                .preferredColorScheme(library.appearance.colorScheme)
                .tint(JLiveTheme.accent)
            }
        }
    }
}
