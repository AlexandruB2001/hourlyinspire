import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where the Supabase project lives. The anon key is a public client key;
/// row level security is what protects data. Never put the service-role key
/// in the app.
public struct SupabaseConfig: Hashable, Sendable {
    public let url: URL
    public let anonKey: String

    public init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }

    /// Builds a config from build settings. Returns nil when either value is
    /// missing, which means "backend not configured" (the app falls back to
    /// local sample friends).
    public init?(host: String?, scheme: String? = "https", anonKey: String?) {
        guard let host = host?.trimmingCharacters(in: .whitespaces), !host.isEmpty, !host.hasPrefix("$("),
              let anonKey = anonKey?.trimmingCharacters(in: .whitespaces), !anonKey.isEmpty, !anonKey.hasPrefix("$("),
              let url = URL(string: "\(scheme?.isEmpty == false ? scheme! : "https")://\(host)") else { return nil }
        self.init(url: url, anonKey: anonKey)
    }
}

/// Sends HTTP requests. Abstracted so the client can be tested without a network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        return (data, http)
    }
}

public enum BackendError: Error, Hashable, Sendable {
    /// No session, or the session could not be refreshed. Sign in again.
    case notSignedIn
    /// The network request failed (offline, timeout…).
    case network(String)
    /// The server answered with an error. `message` is the database error
    /// key (e.g. "user_not_found") for API functions.
    case server(status: Int, code: String?, message: String)
    case invalidResponse
    case decoding(String)

    /// The machine-readable message raised by an API function, if any.
    public var serverMessage: String? {
        if case .server(_, _, let message) = self { return message }
        return nil
    }
}

/// Postgres timestamps ("2026-10-25T13:55:31.123456+00:00") ↔ Date.
enum PostgresDate {
    static func parse(_ string: String) -> Date? {
        // Normalise fractional seconds to milliseconds, which every
        // ISO8601DateFormatter implementation accepts.
        var value = string.replacingOccurrences(of: " ", with: "T")
        if let dot = value.firstIndex(of: ".") {
            let fractionStart = value.index(after: dot)
            let fractionEnd = value[fractionStart...].firstIndex { !$0.isNumber } ?? value.endIndex
            var fraction = String(value[fractionStart..<fractionEnd])
            fraction = String((fraction + "000").prefix(3))
            value.replaceSubrange(fractionStart..<fractionEnd, with: fraction)
        }
        if value.hasSuffix("+00") { value += ":00" }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static let decodingStrategy = JSONDecoder.DateDecodingStrategy.custom { decoder in
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let date = parse(string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Unrecognised timestamp \(string)"))
        }
        return date
    }

    static let encodingStrategy = JSONEncoder.DateEncodingStrategy.custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(format(date))
    }
}
