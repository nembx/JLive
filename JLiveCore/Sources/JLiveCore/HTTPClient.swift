import Foundation

public enum JSONValue: Decodable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public subscript(key: String) -> JSONValue {
        guard case .object(let value) = self else { return .null }
        return value[key] ?? .null
    }
    public var string: String {
        switch self {
        case .string(let value): value
        case .number(let value): value.rounded() == value ? String(format: "%.0f", value) : String(value)
        default: ""
        }
    }
    public var int: Int { Int(string) ?? 0 }
    public var array: [JSONValue] {
        guard case .array(let value) = self else { return [] }
        return value
    }
    public var isNull: Bool { if case .null = self { true } else { false } }
    public func requiredArray() throws -> [JSONValue] {
        guard case .array(let value) = self else { throw LiveError.invalidResponse }
        return value
    }
}

public protocol HTTPRequesting: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> JSONValue
}

public actor HTTPClient: HTTPRequesting {
    public static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
    }

    public func get(_ url: URL, headers: [String: String] = [:]) async throws -> JSONValue {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw LiveError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw LiveError.http(response.statusCode) }
        do {
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            // A few Huya endpoints return JSON encoded inside a JSON string.
            if case .string(let string) = value {
                return try JSONDecoder().decode(JSONValue.self, from: Data(string.utf8))
            }
            return value
        } catch {
            throw LiveError.invalidResponse
        }
    }
}

func endpoint(_ base: String, _ query: [String: String] = [:]) throws -> URL {
    guard var components = URLComponents(string: base) else { throw LiveError.invalidResponse }
    components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    guard let url = components.url else { throw LiveError.invalidResponse }
    return url
}

func imageURL(_ value: String) -> URL? {
    guard !value.isEmpty else { return nil }
    let normalized = value.hasPrefix("//") ? "https:" + value : value
    guard var components = URLComponents(string: normalized),
          ["http", "https"].contains(components.scheme?.lowercased() ?? ""), components.host != nil else { return nil }
    components.scheme = "https"
    return components.url
}

func plainText(_ value: String) -> String {
    value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
}
