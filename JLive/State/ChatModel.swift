import Foundation
import Observation
import UIKit
import JLiveCore

/// Live room chat: keeps the connection, batches messages and lays out the scrolling danmaku.
@MainActor @Observable
final class ChatModel {
    struct Entry: Identifiable, Equatable {
        let id: Int
        let message: LiveChatMessage
    }

    /// A message travelling across the video.
    struct Floating: Identifiable, Equatable {
        let id: Int
        let text: String
        let color: UInt32?
        let isSuperChat: Bool
        let lane: Int
        let width: CGFloat
        let duration: Double
        let delay: Double
        let fontSize: CGFloat
    }

    enum Status: Equatable {
        case idle, connecting, connected, reconnecting
        case failed(String)
    }

    var laneHeight: CGFloat { CGFloat(fontSize) + 11 }
    var fontSize: Double { didSet { defaults.set(fontSize, forKey: "jlive.danmaku.size"); resetFloating() } }
    var opacity: Double { didSet { defaults.set(opacity, forKey: "jlive.danmaku.opacity") } }
    var speed: Double { didSet { defaults.set(speed, forKey: "jlive.danmaku.speed"); resetFloating() } }
    var area: Double { didSet { defaults.set(area, forKey: "jlive.danmaku.area"); resetFloating() } }
    var blockedWords: String { didSet { defaults.set(blockedWords, forKey: "jlive.danmaku.blocked"); resetFloating() } }
    private static let floatingKey = "jlive.danmaku.floating"
    private static let maxEntries = 200
    private static let maxFloating = 22

    private(set) var entries: [Entry] = []
    private(set) var floating: [Floating] = []
    private(set) var status: Status = .idle

    var showsFloating: Bool {
        didSet {
            defaults.set(showsFloating, forKey: Self.floatingKey)
            if !showsFloating { floating.removeAll() }
        }
    }

    /// Size of the video surface, reported by the overlay view.
    var viewport: CGSize = .zero {
        didSet {
            // In-flight positions are meaningless after a resize such as rotation.
            guard abs(viewport.width - oldValue.width) > 1 else { return }
            floating.removeAll()
        }
    }

    var laneCount: Int { max(1, min(12, Int(max(0, viewport.height - 58) * area / laneHeight))) }

    @ObservationIgnored private let service: LiveService
    @ObservationIgnored private let client: LiveChatClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var session: Task<Void, Never>?
    @ObservationIgnored private var flush: Task<Void, Never>?
    @ObservationIgnored private var pending: [LiveChatMessage] = []
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var laneFree: [Date] = []
    @ObservationIgnored private var room: LiveRoom?
    @ObservationIgnored private var generation = UUID()

    init(service: LiveService, client: LiveChatClient = LiveChatClient(), defaults: UserDefaults = .standard) {
        self.service = service
        self.client = client
        self.defaults = defaults
        showsFloating = defaults.object(forKey: Self.floatingKey) as? Bool ?? true
        fontSize = min(24, max(12, defaults.object(forKey: "jlive.danmaku.size") as? Double ?? 15))
        opacity = min(1, max(0.25, defaults.object(forKey: "jlive.danmaku.opacity") as? Double ?? 0.9))
        speed = min(1.8, max(0.6, defaults.object(forKey: "jlive.danmaku.speed") as? Double ?? 1))
        area = min(1, max(0.25, defaults.object(forKey: "jlive.danmaku.area") as? Double ?? 0.6))
        blockedWords = defaults.string(forKey: "jlive.danmaku.blocked") ?? ""
    }

    func start(room: LiveRoom) {
        stop()
        guard room.platform.supportsChat else { return }
        self.room = room
        status = .connecting
        let token = generation
        let service = service
        let client = client
        session = Task { [weak self] in
            do {
                let endpoint = try await service.chat(room)
                guard let self, self.generation == token, !Task.isCancelled else { return }
                for try await event in client.events(endpoint) {
                    guard self.generation == token, !Task.isCancelled else { return }
                    self.handle(event)
                }
                if self.generation == token, !Task.isCancelled { self.finish(with: "弹幕连接已断开") }
            } catch {
                if self?.generation == token, !Task.isCancelled { self?.finish(with: error.localizedDescription) }
            }
        }
    }

    func stop() {
        generation = UUID()
        session?.cancel()
        session = nil
        flush?.cancel()
        flush = nil
        pending.removeAll()
        floating.removeAll()
        laneFree.removeAll()
        status = .idle
    }

    private func resetFloating() {
        floating.removeAll()
        laneFree.removeAll()
    }

    func restart() {
        guard let room else { return }
        start(room: room)
    }

    /// Called by the overlay once a message has left the screen.
    func expire(_ id: Int) {
        floating.removeAll { $0.id == id }
    }

    private func finish(with message: String) {
        status = .failed(message)
        floating.removeAll()
    }

    private func handle(_ event: LiveChatEvent) {
        switch event {
        case .connected: status = .connected
        case .reconnecting: status = .reconnecting
        case .message(let message):
            let words = blockedWords.split(whereSeparator: { $0 == "," || $0 == "，" || $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !words.contains(where: { message.text.localizedCaseInsensitiveContains($0) }) else { return }
            pending.append(message)
            if pending.count > Self.maxEntries { pending.removeFirst(pending.count - Self.maxEntries) }
            scheduleFlush()
        }
    }

    /// Busy rooms send hundreds of messages per second; publish in batches instead of one update each.
    private func scheduleFlush() {
        guard flush == nil else { return }
        flush = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard let self, !Task.isCancelled else { return }
            self.flush = nil
            self.publish()
        }
    }

    private func publish() {
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        guard !batch.isEmpty else { return }
        for message in batch {
            nextID += 1
            entries.append(Entry(id: nextID, message: message))
            appendFloating(message, id: nextID)
        }
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
    }

    private func appendFloating(_ message: LiveChatMessage, id: Int) {
        guard showsFloating, viewport.width > 0 else { return }
        var isSuperChat = false
        switch message.kind {
        case .chat: break
        case .superChat: isSuperChat = true
        case .gift: return
        }
        // Keep the lanes that are still occupied when the surface changes height, e.g. entering full screen.
        if laneFree.count > laneCount {
            laneFree.removeLast(laneFree.count - laneCount)
        } else if laneFree.count < laneCount {
            laneFree.append(contentsOf: repeatElement(.distantPast, count: laneCount - laneFree.count))
        }
        let now = Date()
        // Every message moves at the same speed, so a lane is free once the previous one fits in.
        guard let lane = laneFree.indices.first(where: { laneFree[$0] <= now }) else { return }
        let width = measure(message.text) + (isSuperChat ? 20 : 0)
        let speed = max(70, viewport.width / 6.5) * self.speed
        let delay = Double.random(in: 0...0.25)
        laneFree[lane] = now.addingTimeInterval(delay + Double((width + 26) / speed))
        floating.append(Floating(
            id: id, text: message.text, color: message.color, isSuperChat: isSuperChat, lane: lane,
            width: width, duration: Double((viewport.width + width) / speed), delay: delay, fontSize: CGFloat(fontSize)
        ))
        if floating.count > Self.maxFloating { floating.removeFirst(floating.count - Self.maxFloating) }
    }

    private func measure(_ text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: CGFloat(fontSize), weight: .semibold)]
        return ceil((text as NSString).size(withAttributes: attributes).width) + 2
    }
}
