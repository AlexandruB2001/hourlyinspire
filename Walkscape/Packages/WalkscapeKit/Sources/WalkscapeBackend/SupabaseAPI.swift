import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Calls Postgres functions through PostgREST (`/rest/v1/rpc/<name>`) as the
/// signed-in user. Every Walkscape API call is a database function, so this is
/// the only data-access path the app needs.
public struct SupabaseAPI: Sendable {
    let config: SupabaseConfig
    let transport: HTTPTransport
    let auth: SupabaseAuth

    public init(config: SupabaseConfig, transport: HTTPTransport, auth: SupabaseAuth) {
        self.config = config
        self.transport = transport
        self.auth = auth
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = PostgresDate.encodingStrategy
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = PostgresDate.decodingStrategy
        return decoder
    }()

    /// Calls `name` and decodes its result.
    public func call<Response: Decodable>(_ name: String, _ params: some Encodable = EmptyParams(),
                                          as type: Response.Type = Response.self) async throws -> Response {
        let data = try await send(name, params)
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw BackendError.decoding("\(name): \(error)")
        }
    }

    /// Calls a function that returns nothing.
    public func call(_ name: String, _ params: some Encodable = EmptyParams()) async throws {
        _ = try await send(name, params)
    }

    private func send(_ name: String, _ params: some Encodable) async throws -> Data {
        let body = try Self.encoder.encode(params)
        var token = try await auth.validAccessToken()
        for attempt in 0..<2 {
            var request = URLRequest(url: config.url.appendingPathComponent("rest/v1/rpc/\(name)"))
            request.httpMethod = "POST"
            request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = body

            let (data, response): (Data, HTTPURLResponse)
            do {
                (data, response) = try await transport.send(request)
            } catch let error as BackendError {
                throw error
            } catch {
                throw BackendError.network(error.localizedDescription)
            }

            // An expired or revoked token: refresh once and retry.
            if response.statusCode == 401 && attempt == 0 {
                token = try await auth.refresh().accessToken
                continue
            }
            guard (200..<300).contains(response.statusCode) else {
                throw Self.serverError(status: response.statusCode, data: data)
            }
            return data
        }
        throw BackendError.notSignedIn
    }

    /// Calls an Edge Function (`/functions/v1/<name>`) as the signed-in user.
    public func invokeFunction(_ name: String, _ body: some Encodable) async throws -> Data {
        let payload = try Self.encoder.encode(body)
        var token = try await auth.validAccessToken()
        for attempt in 0..<2 {
            var request = URLRequest(url: config.url.appendingPathComponent("functions/v1/\(name)"))
            request.httpMethod = "POST"
            request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload
            let (data, response): (Data, HTTPURLResponse)
            do {
                (data, response) = try await transport.send(request)
            } catch let error as BackendError {
                throw error
            } catch {
                throw BackendError.network(error.localizedDescription)
            }
            if response.statusCode == 401 && attempt == 0 {
                token = try await auth.refresh().accessToken
                continue
            }
            guard (200..<300).contains(response.statusCode) else {
                throw Self.serverError(status: response.statusCode, data: data)
            }
            return data
        }
        throw BackendError.notSignedIn
    }

    /// Parses a PostgREST/GoTrue error body.
    static func serverError(status: Int, data: Data) -> BackendError {
        struct Body: Decodable {
            let code: String?
            let message: String?
            let msg: String?
            let error_description: String?
            let error: String?
        }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        let candidates: [String?] = [body?.message, body?.msg, body?.error_description, body?.error,
                                     String(data: data, encoding: .utf8)]
        let message = candidates.compactMap { $0 }.first { !$0.isEmpty } ?? "HTTP \(status)"
        return .server(status: status, code: body?.code, message: message)
    }
}

public struct EmptyParams: Encodable, Sendable {
    public init() {}
}
