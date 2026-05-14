import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case transport(Error)
    case http(status: Int, body: ServerError?)
    case decoding(Error)
    case noTokens

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL."
        case .transport(let e): return e.localizedDescription
        case .http(let status, let body):
            if let body { return body.error }
            return "Server error (\(status))."
        case .decoding: return "Unexpected response from server."
        case .noTokens: return "Not signed in."
        }
    }
}

struct ServerError: Codable {
    let error: String
}

typealias TokenProvider = () async -> AuthTokens?
typealias TokenRefresher = (String) async throws -> AuthTokens
typealias UnauthorizedHandler = () async -> Void

/// Single point of contact for the backend. Reads `API_BASE_URL` from Info.plist
/// (set per build configuration via xcconfig). All requests go through
/// `send(_:authenticated:)` which transparently refreshes a 401 once.
actor APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private var tokenProvider: TokenProvider?
    private var tokenRefresher: TokenRefresher?
    private var onUnauthorized: UnauthorizedHandler?

    init() {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String) ?? ""
        guard let url = URL(string: raw) else {
            fatalError("API_BASE_URL missing or invalid: \(raw)")
        }
        self.baseURL = url

        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: cfg)

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
    }

    func configure(
        tokenProvider: @escaping TokenProvider,
        tokenRefresher: @escaping TokenRefresher,
        onUnauthorized: @escaping UnauthorizedHandler
    ) {
        self.tokenProvider = tokenProvider
        self.tokenRefresher = tokenRefresher
        self.onUnauthorized = onUnauthorized
    }

    // MARK: - Public request helpers

    func get<Response: Decodable>(_ path: String, authenticated: Bool = true) async throws -> Response {
        try await send(path: path, method: "GET", body: Optional<Empty>.none, authenticated: authenticated)
    }

    func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        authenticated: Bool = true
    ) async throws -> Response {
        try await send(path: path, method: "POST", body: body, authenticated: authenticated)
    }

    // MARK: - Core

    private struct Empty: Codable {}

    private func currentAccessToken() async -> String? {
        guard let provider = tokenProvider else { return nil }
        return await provider()?.access
    }

    private func currentRefreshToken() async -> String? {
        guard let provider = tokenProvider else { return nil }
        return await provider()?.refresh
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body?,
        authenticated: Bool
    ) async throws -> Response {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { req.httpBody = try encoder.encode(body) }

        if authenticated, let access = await currentAccessToken() {
            req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await perform(req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1

        if status == 401, authenticated {
            // Try one refresh and retry the original request.
            if let refreshed = try await attemptRefresh() {
                var retry = req
                retry.setValue("Bearer \(refreshed.access)", forHTTPHeaderField: "Authorization")
                let (data2, response2) = try await perform(retry)
                let status2 = (response2 as? HTTPURLResponse)?.statusCode ?? -1
                return try ensureDecoded(status: status2, data: data2)
            }
            await onUnauthorized?()
            throw APIError.http(status: 401, body: nil)
        }

        return try ensureDecoded(status: status, data: data)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
    }

    private func ensureDecoded<Response: Decodable>(status: Int, data: Data) throws -> Response {
        guard (200..<300).contains(status) else {
            let body = try? decoder.decode(ServerError.self, from: data)
            throw APIError.http(status: status, body: body)
        }
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func attemptRefresh() async throws -> AuthTokens? {
        guard
            let refresher = tokenRefresher,
            let refreshToken = await currentRefreshToken()
        else { return nil }
        do {
            return try await refresher(refreshToken)
        } catch {
            return nil
        }
    }
}

struct EmptyResponse: Decodable {}
