import Foundation

/// A single message from a live room chat.
public struct LiveChatMessage: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case chat
        case gift
        case superChat(price: Int)
    }

    public let kind: Kind
    public let userName: String
    public let text: String
    /// Platform colour for the message, `nil` when the platform default applies.
    public let color: UInt32?

    public init(kind: Kind, userName: String, text: String, color: UInt32? = nil) {
        self.kind = kind
        self.userName = userName
        self.text = text
        self.color = color
    }
}

public enum LiveChatEvent: Equatable, Sendable {
    /// The server accepted the handshake; chat is live.
    case connected
    /// The client lost the connection and is about to try again.
    case reconnecting
    case message(LiveChatMessage)
}

/// Decoded events and any protocol acknowledgements required before publishing them.
public struct LiveChatFrame: Sendable {
    public let events: [LiveChatEvent]
    public let replies: [Data]

    public init(events: [LiveChatEvent], replies: [Data] = []) {
        self.events = events
        self.replies = replies
    }
}

/// Everything needed to open and keep alive a room chat connection.
///
/// Providers build this from their own API responses; the transport and the
/// reconnection policy stay platform independent.
public struct LiveChatEndpoint: Sendable {
    /// Hosts to try in order, rotating on failure.
    public let urls: [URL]
    public let headers: [String: String]
    /// Packet sent right after the socket opens.
    public let handshake: Data
    public let heartbeat: Data
    public let heartbeatInterval: TimeInterval
    public let process: @Sendable (Data) throws -> LiveChatFrame
    public var decode: @Sendable (Data) throws -> [LiveChatEvent] {
        { try process($0).events }
    }

    public init(
        urls: [URL],
        headers: [String: String] = [:],
        handshake: Data,
        heartbeat: Data,
        heartbeatInterval: TimeInterval = 30,
        decode: @escaping @Sendable (Data) throws -> [LiveChatEvent]
    ) {
        precondition(!urls.isEmpty, "A chat endpoint needs at least one host")
        self.urls = urls
        self.headers = headers
        self.handshake = handshake
        self.heartbeat = heartbeat
        self.heartbeatInterval = heartbeatInterval
        self.process = { LiveChatFrame(events: try decode($0)) }
    }

    public init(
        urls: [URL],
        headers: [String: String] = [:],
        handshake: Data,
        heartbeat: Data,
        heartbeatInterval: TimeInterval = 30,
        process: @escaping @Sendable (Data) throws -> LiveChatFrame
    ) {
        precondition(!urls.isEmpty, "A chat endpoint needs at least one host")
        self.urls = urls
        self.headers = headers
        self.handshake = handshake
        self.heartbeat = heartbeat
        self.heartbeatInterval = heartbeatInterval
        self.process = process
    }
}

public protocol LiveChatSocket: Sendable {
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close()
}

public protocol LiveChatConnecting: Sendable {
    func connect(to url: URL, headers: [String: String]) async throws -> any LiveChatSocket
}

public struct URLSessionChatConnector: LiveChatConnecting {
    public init() {}

    public func connect(to url: URL, headers: [String: String]) async throws -> any LiveChatSocket {
        var request = URLRequest(url: url)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        // Leave the idle timeout at the default: the heartbeat keeps the socket busy,
        // and a short timeout would drop quiet rooms.
        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        return URLSessionChatSocket(task: task)
    }
}

struct URLSessionChatSocket: LiveChatSocket {
    let task: URLSessionWebSocketTask

    func send(_ data: Data) async throws { try await task.send(.data(data)) }

    func receive() async throws -> Data {
        switch try await task.receive() {
        case .data(let value): return value
        case .string(let value): return Data(value.utf8)
        @unknown default: return Data()
        }
    }

    func close() { task.cancel(with: .goingAway, reason: nil) }
}

/// Keeps a room chat connection alive: heartbeat, host rotation and bounded retries.
public struct LiveChatClient: Sendable {
    private let connector: any LiveChatConnecting
    private let retryDelay: Duration
    private let maxConsecutiveFailures: Int

    public init(
        connector: any LiveChatConnecting = URLSessionChatConnector(),
        retryDelay: Duration = .seconds(3),
        maxConsecutiveFailures: Int = 5
    ) {
        self.connector = connector
        self.retryDelay = retryDelay
        self.maxConsecutiveFailures = maxConsecutiveFailures
    }

    public func events(_ endpoint: LiveChatEndpoint) -> AsyncThrowingStream<LiveChatEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var failures = 0
                var lastError: any Error = LiveError.platform("弹幕连接已断开")
                while !Task.isCancelled {
                    if failures > 0 { continuation.yield(.reconnecting) }
                    do {
                        try await runSession(
                            endpoint,
                            url: endpoint.urls[failures % endpoint.urls.count],
                            failures: &failures,
                            yield: { continuation.yield($0) }
                        )
                    } catch {
                        lastError = error
                    }
                    // Cancellation surfaces as a socket error, so check the task rather than the error.
                    if Task.isCancelled { break }
                    // A session only ends when the connection is lost, with or without an error.
                    failures += 1
                    if failures >= maxConsecutiveFailures {
                        continuation.finish(throwing: lastError)
                        return
                    }
                    try? await Task.sleep(for: retryDelay)
                }
                continuation.finish(throwing: nil)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runSession(
        _ endpoint: LiveChatEndpoint,
        url: URL,
        failures: inout Int,
        yield: (LiveChatEvent) -> Void
    ) async throws {
        let socket = try await connector.connect(to: url, headers: endpoint.headers)
        defer { socket.close() }
        try await socket.send(endpoint.handshake)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    while true {
                        try await Task.sleep(for: .seconds(endpoint.heartbeatInterval))
                        try await socket.send(endpoint.heartbeat)
                    }
                } catch {
                    // Unblock the receive loop instead of waiting for the idle timeout.
                    socket.close()
                    throw error
                }
            }
            do {
                while true {
                    let frame = try await socket.receive()
                    let decoded = try endpoint.process(frame)
                    for reply in decoded.replies { try await socket.send(reply) }
                    failures = 0
                    for event in decoded.events { yield(event) }
                }
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }
}
