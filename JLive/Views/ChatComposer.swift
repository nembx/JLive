import SwiftUI
import JLiveCore

struct ChatComposer: View {
    let room: LiveRoom
    let service: LiveService
    @Environment(AccountStore.self) private var account
    @State private var text = ""
    @State private var sending = false
    @State private var error: String?
    @State private var login = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if account.isLoggedIn {
                HStack(spacing: 10) {
                    TextField("发一条弹幕…", text: $text).font(.subheadline)
                        .submitLabel(.send).onSubmit { send() }
                        .onChange(of: text) { _, value in if value.count > 30 { text = String(value.prefix(30)) } }
                    Button(action: send) {
                        if sending { ProgressView() }
                        else { Image(systemName: "arrow.up").font(.subheadline.bold()) }
                    }
                    .frame(width: 36, height: 36).background(JLiveTheme.accent.opacity(0.12), in: Circle())
                    .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("发送弹幕")
                }
            } else {
                Button { login = true } label: { Label("登录 B站，参与聊天", systemImage: "bubble.left") }
                    .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(14).background(JLiveTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $login) { BilibiliLoginView() }
    }
    private func send() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sending, !message.isEmpty else { return }
        sending = true
        error = nil
        Task {
            defer { sending = false }
            do {
                try await service.sendChat(message, room: room)
                if text.trimmingCharacters(in: .whitespacesAndNewlines) == message { text = "" }
            } catch { self.error = error.localizedDescription }
        }
    }
}
